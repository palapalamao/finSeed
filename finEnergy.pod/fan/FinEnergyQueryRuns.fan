using concurrent
using haystack
using skyarcd
using util

** Short-lived read-only jobs. A worker owns the query and its cursors from start
** to finish. Polling only observes immutable results and cannot restart work.
internal const class FinEnergyQueryRuns
{
  private static const AtomicRef runs := AtomicRef(Str:FinEnergyQueryRun[:].toImmutable)
  private static const ActorPool pool := ActorPool() {name="finEnergyQueryRuns"; maxThreads=2}
  private static const Actor cleanup := Actor(pool, |Obj? message->Obj?| {retire((FinEnergyQueryRun)message); return null})

  static Str:Obj? submit(Context cx, Str:Obj? input)
  {
    session:=requireSession(cx)
    if(input["kind"]!="cockpit") throw FinEnergyHttpErr(409,"QUERY_RUN_UNAVAILABLE","queryRunUnavailable")
    request:=pinRequest(input["request"] as Map,DateTime.now)
    id:=Uuid().toStr.replace("-","")
    cancel:=FinEnergyQueryCancellation.open(cx.proj.name,cx.user.username,id)
    run:=FinEnergyQueryRun(id,request,session.id,cx.proj.id,cx.user.id,cx.user.mod,cx.sys,cancel)
    try
    {
      while(true)
      {
        before:=(Str:FinEnergyQueryRun)runs.val
        after:=before.dup
        before.each |previous,key|
        {
          if(previous.owner(session.id,cx.proj.id,cx.user.id) && previous.done) after.remove(key)
        }
        if(after.size>=4 || after.vals.any |previous| {previous.owner(session.id,cx.proj.id,cx.user.id)})
          throw FinEnergyHttpErr(429,"QUERY_RUN_BUSY","queryRunBusy")
        after[id]=run
        if(runs.compareAndSet(before,after.toImmutable)) break
      }
      Actor(pool,|Obj? message->Obj?| {execute((FinEnergyQueryRun)message);return null}).send(run)
      return run.status
    }
    catch(Err e)
    {
      retire(run)
      cancel.close
      throw e
    }
  }

  internal static Str:Obj? pinRequest(Map? source,DateTime now)
  {
    request:=source?.dup as Str:Obj? ?: throw ArgErr("queryRunRequest")
    raw:=request["asOf"]
    if(raw==null) return request.set("asOf",now.toIso)
    cutoff:=DateTime.fromIso(raw as Str ?: "",false) ?: throw ArgErr("queryRunCutoff")
    if(cutoff>now) request["asOf"]=now.toTimeZone(cutoff.tz).toIso
    return request
  }

  static Str:Obj? status(Context cx,Str id)
  { lookup(cx,id).status }

  static Str:Obj? stop(Context cx,Str id)
  {
    run:=lookup(cx,id)
    run.stop
    return run.status
  }

  private static FinEnergyQueryRun lookup(Context cx, Str id)
  {
    session:=requireSession(cx)
    run:=((Str:FinEnergyQueryRun)runs.val)[id]
    if(run==null || !run.owner(session.id,cx.proj.id,cx.user.id) || run.userMod!=cx.user.mod)
      throw FinEnergyHttpErr(404,"QUERY_RUN_MISSING","queryRunMissing")
    return run
  }

  static Bool available(Context cx) { eligibleSession(cx)!=null }

  private static ServerSession requireSession(Context cx)
  {eligibleSession(cx) ?: throw FinEnergyHttpErr(409,"QUERY_RUN_UNAVAILABLE","queryRunUnavailable")}

  private static ServerSession? eligibleSession(Context cx)
  {
    session:=cx.session(false) as ServerSession
    user:=cx.sys.user.user(cx.user.id,false)
    if(user==null || !user.isSu || user.mod!=cx.user.mod || !user.isProjAccessible(cx.proj) || session==null || !session.isWeb || cx.sys.user.noAuth ||
       session.isExpired(Duration.now) || cx.sys.session.sessionById(session.id,false)!==session ||
       session.user.id!=cx.user.id)
      return null
    return session
  }

  private static Void execute(FinEnergyQueryRun run)
  {
    try {run.execute}
    finally
    {
      run.cancellation.close
      cleanup.sendLater(1min,run)
    }
  }

  private static Void retire(FinEnergyQueryRun run)
  {
    while(true)
    {
      before:=(Str:FinEnergyQueryRun)runs.val
      if(before[run.id]!==run) return
      after:=before.dup
      after.remove(run.id)
      if(runs.compareAndSet(before,after.toImmutable)) return
    }
  }
}

internal const class FinEnergyQueryRun
{
  new make(Str id, Str:Obj? request, Ref sessionId, Ref projectId, Ref userId, DateTime userMod, Sys sys, FinEnergyQueryCancellation cancellation)
  {
    this.id=id;this.request=request.toImmutable;this.sessionId=sessionId;this.projectId=projectId
    this.userId=userId;this.userMod=userMod;this.sys=sys;this.cancellation=cancellation
  }

  const Str id
  const Ref sessionId
  const Ref projectId
  const Ref userId
  const DateTime userMod
  const FinEnergyQueryCancellation cancellation
  private const Sys sys
  private const Str:Obj? request
  private const Int started := Duration.nowTicks
  private const AtomicBool finished := AtomicBool(false)
  private const AtomicRef value := AtomicRef(Str:Obj?["state":"queued"].toImmutable)

  Bool owner(Ref session,Ref project,Ref user) {sessionId==session && projectId==project && userId==user}
  Bool done() {finished.val}

  Str:Obj? status()
  {
    record:=((Str:Obj?)value.val).dup
    end:=record.remove("endedAt") as Int ?: Duration.nowTicks
    bytes:=record.remove("payload") as Buf
    if(bytes!=null) record["result"]=((Map)JsonInStream(bytes.dup.in).readJson)["data"]
    return record.set("id",id).set("elapsedMs",(end-started)/1ms.ticks)
  }

  Void stop()
  {
    cancellation.requestCancel
    while(true)
    {
      before:=(Str:Obj?)value.val
      after:=terminal("cancelled")
      if(value.compareAndSet(before,after)) return
    }
  }

  Void execute()
  {
    try
    {
      update(Str:Obj?["state":"running"].toImmutable)
      cancellation.check
      ctx:=newContext
      data:=ctx.asCur |active|
      {
        repo:=FinEnergyRepo(active)
        repo.mustRead
        repo.requireConfigurationAccess
        return cockpit(repo)
      }
      cancellation.check
      newContext
      update(terminal("ready",(Buf)data))
    }
    catch(FinEnergyHttpErr e)
    {update(e.code=="QUERY_CANCELLED" ? terminal("cancelled") : terminal("failed",null,["code":e.code,"msg":e.msg]))}
    catch(ArgErr e) {update(terminal("failed",null,["code":"INVALID","msg":e.msg]))}
    catch(Err e)
    {
      Log.get("finEnergy").err("FIN Energy background query failed",e)
      update(terminal("failed",null,["code":"INTERNAL","msg":"queryRunFailed"]))
    }
    finally {finished.val=true}
  }

  private Context newContext()
  {
    session:=sys.session.sessionById(sessionId,false)
    user:=sys.user.user(userId,false)
    proj:=sys.proj.find(projectId,false)
    if(session==null || session.isExpired(Duration.now) || session.user.id!=userId ||
       user==null || user.mod!=userMod || !user.isSu || proj==null || !user.isProjAccessible(proj))
      throw FinEnergyHttpErr(403,"PERMISSION","queryRunUnavailable")
    return Context(sys,user,proj)
  }

  private Buf cockpit(FinEnergyRepo repo)
  {
    limit:=5min
    deadline:=FinEnergyCockpitDeadline(limit,|->Int| {Duration.nowTicks},cancellation)
    stream:=FinEnergyStreamBudget(50000,200000,20000000,limit,deadline)
    scope:=FinEnergyCockpitRequestScope(repo.cx.proj.name,repo.cx.user.username,stream)
    try
    {
      Buf? snapshot
      scope.deliver(repo.cockpitScoped(request,scope),|Buf bytes| {snapshot=bytes.dup.toImmutable})
      return snapshot ?: throw IOErr("No result payload")
    }
    finally {scope.close}
  }

  private Void update(Str:Obj? after)
  {
    while(true)
    {
      before:=(Str:Obj?)value.val
      if(before["state"]=="cancelled" || value.compareAndSet(before,after)) return
    }
  }

  private static Str:Obj? terminal(Str state, Buf? result:=null, [Str:Obj?]? error:=null)
  {
    record:=Str:Obj?["state":state,"endedAt":Duration.nowTicks]
    if(result!=null) record["payload"]=result
    if(error!=null) record["error"]=error
    return record.toImmutable
  }
}

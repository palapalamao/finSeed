using util
using haystack
using folio
using skyarcd

** Persisted native FIN calculation and alert operations.
class EnerCubixJobs
{
  EnerCubixRepo repo
  new make(EnerCubixRepo repo) { this.repo=repo }
  private [Str:Obj?]? currentJob
  private Str owner := ""
  private Int processed := 0
  private Int alarmsCreated := 0

  [Str:Obj?] run([Str:Obj?] request)
  {
    repo.mustWrite
    action:=request["action"] as Str ?: ""
    checkAction(action)
    if (action == "setAlarmEnabled")
    {
      enabled:=request["enabled"] as Bool ?: throw ArgErr("缺少启停状态")
      old:=repo.records.find |r| { r["kind"] == "job" && r["action"] == action }
      config:=old ?: ["kind":"job","name":"报警开关","action":action]
      config["enabled"]=enabled; config["status"]=enabled ? "enabled" : "disabled"
      config["message"]="FIN 原生每小时调度；原始历史同步由 FIN 连接器独立管理"
      ensureSchedule(repo.cx.db)
      return repo.save(config,true)
    }
    tz:=TimeZone.fromStr(repo.cx.proj.meta["tz"]?.toStr ?: "Shanghai")
    now:=DateTime.now.toTimeZone(tz); end:=EnerCubixMath.floorHour(now)
    from:=DateTime.fromIso(request["from"] as Str ?: (end-1hr).toIso).toTimeZone(tz)
    to:=DateTime.fromIso(request["to"] as Str ?: end.toIso).toTimeZone(tz)
    if (to <= from || to-from > 366day) throw ArgErr("任务范围须大于零且不超过366天")
    if (from != EnerCubixMath.floorHour(from) || to != EnerCubixMath.floorHour(to)) throw ArgErr("任务起止时间须按整小时选择，不能将部分小时用量写为完整小时")
    owner=Uuid().toStr; processed=0; alarmsCreated=0; currentJob=null
    return (Str:Obj?)EnerCubixTaskLock.withLock(repo.cx.db,owner) |held->Obj?|
    {
      interruptPrevious(held)
      all:=repo.records
      currentJob=repo.save(["kind":"job","name":"报警检查 "+now.toIso,"action":action,"status":"running","from":from.toIso,"to":to.toIso,"lastRun":now.toIso,"processed":0],true)
      currentJob["historyWriteMode"]="primaryReadOnly"
      currentJob["historyRewriteConfirmed"]=false
      try
      {
        progress(0)
        scan(all,from.toIso,to.toIso)
        currentJob["status"]="completed"
        currentJob["message"]="报警检查完成"
        currentJob["lastRun"]=DateTime.now.toIso
        if (action == "scanAlarms") currentJob["alarmsCreated"]=alarmsCreated
        currentJob=repo.save(currentJob,true)
        return currentJob
      }
      catch (Err e)
      {
        currentJob["status"]="failed"; currentJob["message"]=e.msg; currentJob["lastRun"]=DateTime.now.toIso
        try { currentJob=repo.save(currentJob,true) }
        catch (Err saveErr) { Log.get("enerCubix").err("Cannot persist failed task status",saveErr) }
        throw e
      }
    }
  }

  [Str:Obj?] scheduled()
  {
    repo.mustWrite
    all:=repo.records; result:=Str:Obj?[:]
    ["setAlarmEnabled":"scanAlarms"].each |action,setting|
    {
      if (all.any |r| { r["kind"] == "job" && r["action"] == setting && r["enabled"] == true }) result[action]=run(["action":action])
    }
    return result
  }

  internal static Void checkAction(Str action)
  {
    if (["recalculate","setCalculationEnabled"].contains(action)) throw ArgErr("报表只读主能耗点，不再创建或重算派生归档")
    if (!["scanAlarms","setAlarmEnabled"].contains(action)) throw ArgErr("任务操作无效")
  }

  private Void progress(Int count)
  {
    EnerCubixTaskLock.heartbeat(repo.cx.db,owner,Ref(currentJob["id"].toStr))
    processed+=count
    currentJob["processed"]=processed; currentJob["lastRun"]=DateTime.now.toIso
    currentJob=repo.save(currentJob,true)
  }

  private Void interruptPrevious(Dict held)
  {
    previous:=held["enerCubixPreviousJob"] as Ref
    if (previous == null) return
    record:=repo.cx.db.readById(previous,false)
    if (record == null || record["enerCubixKind"] != "job") return
    job:=EnerCubixRepo.decode(record)
    if (job["status"] != "running") return
    job["status"]="failed"; job["lastRun"]=DateTime.now.toIso
    job["message"]="任务中断：上次执行的共享锁租约已过期，新任务已通过 CAS 接管"
    repo.save(job,true)
  }

  internal static Void ensureSchedule(Folio db)
  {
    key:=Ref("enerCubix-native-hourly-job")
    existing:=db.readAllList(Filter.has("job")).find |r| { r["jobExpr"] == "enerCubixScheduled()" } ?: db.readById(key,false)
    if (existing != null)
    {
      if (!existing.has("job") || existing["jobExpr"] != "enerCubixScheduled()") throw ArgErr("EnerCubix 调度记录标识已被其他记录占用")
      if (existing["jobSchedule"] == "hourly") db.commit(Diff(existing,Etc.makeDict(["jobSchedule":"every 1hr"])))
      return
    }
    try { db.commit(Diff.makeAdd(Etc.makeDict(["dis":"EnerCubix 每小时计算与报警","job":Marker.val,"jobExpr":"enerCubixScheduled()","jobSchedule":"every 1hr"]),key)) }
    catch (Err e)
    {
      if (e.typeof.name != "DuplicateRecErr") throw e
      existing=db.readById(key,false)
      if (existing == null || existing["jobExpr"] != "enerCubixScheduled()") throw e
    }
  }

  private Void scan([Str:Obj?][] all, Str from, Str to)
  {
    all.findAll |r| { EnerCubixConfig.nodeKinds.contains(r["kind"]) }.each |node|
    {
      limits:=[Str:Obj?][,]
      if (node["alarmEnabled"] == true && node["alarmLimit"] != null) limits.add(["categoryId":node["categoryId"],"limit":node["alarmLimit"],"enabled":true])
      if (node["kind"] == "group") limits.addAll(EnerCubixMath.maps(node["alarmLimits"]))
      if (limits.isEmpty) return
      progress(0)
      existing:=all.findAll |r| { r["kind"] == "alarm" && r["nodeId"] == node["id"] }
      replay:=DateTime.fromIso(from)
      existing.each |e|
      {
        // First upgrade replays legacy evidence; later runs resume from the last
        // evaluated hour to catch recovery during missed scheduled executions.
        checkpoint:=e["episodeId"] == null ? e["ts"] :
          (e["episodeId"] == e["id"] && e["recoveredAt"] == null ? (e["lastEvaluatedTs"] ?: e["ts"]) : null)
        if (checkpoint != null && DateTime.fromIso(checkpoint.toStr) < replay) replay=DateTime.fromIso(checkpoint.toStr)
      }
      if (DateTime.fromIso(to)-replay > 366day) throw ArgErr("报警历史合并范围超过366天，请分段检查历史记录")
      report:=repo.report(["kind":"profile","nodeIds":[node["id"]],"from":replay.toIso,"to":to,"period":"hour","metric":"energy","perArea":false])
      pending:=0
      EnerCubixMath.maps(report["series"]).each |s|
      {
        limits.each |limit|
        {
          if (limit["enabled"] == false || (limit["categoryId"] != null && limit["categoryId"] != s["categoryId"])) return
          threshold:=EnerCubixConfig.number(limit["limit"])
          slice:=existing.findAll |e| { e["categoryId"] == s["categoryId"] && e["unit"] == s["unit"] }.dup
          samples:=EnerCubixMath.maps(s["points"])
          samples.each |p| { p["limit"]=threshold }
          samples.each |p|
          {
            pending++
            if (pending >= 100) { progress(pending); pending=0 }
            if (p["value"] == null || !["ok","derived","estimated","cleaned","corrected"].contains(p["quality"]) || EnerCubixConfig.number(p["value"]) <= threshold) return
            key:=alarmKey(node["id"],s["categoryId"],p["ts"])
            if (slice.any |e| { e["ts"] == p["ts"] }) return
            EnerCubixTaskLock.heartbeat(repo.cx.db,owner,Ref(currentJob["id"].toStr))
            label:=node["name"].toStr
            if (label.size > 60) label=label[0..<60]
            alarmName:=label+" > "+p["ts"]+" ["+key.toBuf.toDigest("SHA-256").toHex[0..<12]+"]"
            event:=repo.save(["kind":"alarm","name":alarmName,"nodeId":node["id"],"categoryId":s["categoryId"],"ts":p["ts"],"value":p["value"],"unit":s["unit"],"limit":threshold,"state":"open","sourceIds":p["sourceIds"],"quality":p["quality"]],true)
            slice.add(event); existing.add(event); alarmsCreated++
          }
          EnerCubixAlarmEpisodes.plan(slice,samples).each |episode|
          {
            EnerCubixTaskLock.heartbeat(repo.cx.db,owner,Ref(currentJob["id"].toStr))
            EnerCubixNativeAlarms(repo).applyEpisode(episode,samples.last?.get("ts") as Str)
          }
        }
      }
      progress(pending)
    }
  }

  private static Str alarmKey(Obj? node, Obj? category, Obj? ts) { "$node|$category|$ts" }

}


** One persisted CAS lock is shared by manual and native hourly tasks.
internal class EnerCubixTaskLock
{
  static const Ref key:=Ref("enerCubix-task-lock")
  static const Duration lease:=30min
  private static Dict? current(Folio db) { db.read(Filter.has("enerCubixTaskLock"),false) ?: db.readById(key,false) }

  static Obj? withLock(Folio db, Str owner, |Dict->Obj?| action)
  {
    held:=acquire(db,owner)
    try { return action(held) }
    finally { release(db,owner) }
  }

  static Dict acquire(Folio db, Str owner, DateTime now:=DateTime.now)
  {
    try { return db.commit(acquisition(current(db),owner,now)).newRec }
    catch (Err e)
    {
      if (["DuplicateRecErr","ConcurrentChangeErr"].contains(e.typeof.name)) throw EnerCubixHttpErr(409,"BUSY","已有计算任务正在执行")
      // HxFolio reports an add collision as CommitErr; confirm the competing
      // lock exists rather than depending only on one implementation's Err name.
      if (e.typeof.name == "CommitErr")
      {
        competing:=current(db)
        if (competing?.has("enerCubixTaskLock") == true && competing["enerCubixOwner"] != owner) throw EnerCubixHttpErr(409,"BUSY","已有计算任务正在执行")
      }
      throw e
    }
  }

  internal static Diff acquisition(Dict? previous, Str owner, DateTime now)
  {
    if (previous != null && !previous.has("enerCubixTaskLock")) throw ArgErr("任务锁标识已被其他记录占用")
    until:=previous?.get("enerCubixLeaseUntil") as DateTime
    if (previous?.has("enerCubixOwner") == true && (until == null || until > now)) throw EnerCubixHttpErr(409,"BUSY","已有计算任务正在执行")
    tags:=[Str:Obj?]["dis":"EnerCubix 共享计算锁","enerCubixTaskLock":Marker.val,"enerCubixOwner":owner,"enerCubixLeaseUntil":now+lease,"enerCubixLockAt":now]
    if (previous != null)
    {
      if (previous["enerCubixTaskJob"] is Ref) tags["enerCubixPreviousJob"]=previous["enerCubixTaskJob"]
      else if (previous.has("enerCubixPreviousJob")) tags["enerCubixPreviousJob"]=Remove.val
      if (previous.has("enerCubixTaskJob")) tags["enerCubixTaskJob"]=Remove.val
    }
    return previous == null ? Diff.makeAdd(Etc.makeDict(tags),key) : Diff(previous,Etc.makeDict(tags))
  }

  static Dict heartbeat(Folio db, Str owner, Ref? job:=null, DateTime now:=DateTime.now)
  {
    previous:=current(db)
    if (previous == null || previous["enerCubixOwner"] != owner) throw EnerCubixHttpErr(409,"LOCK_LOST","任务锁已由其他执行接管，当前任务停止写入")
    tags:=[Str:Obj?]["enerCubixLeaseUntil":now+lease,"enerCubixLockAt":now]
    if (job != null) tags["enerCubixTaskJob"]=job
    try { return db.commit(Diff(previous,Etc.makeDict(tags))).newRec }
    catch (Err e)
    {
      if (e.typeof.name == "ConcurrentChangeErr") throw EnerCubixHttpErr(409,"LOCK_LOST","任务锁已变更，当前任务停止写入")
      throw e
    }
  }

  static Bool release(Folio db, Str owner)
  {
    previous:=current(db)
    if (previous == null || previous["enerCubixOwner"] != owner) return false
    tags:=Etc.makeDict(["enerCubixOwner":Remove.val,"enerCubixLeaseUntil":Remove.val,"enerCubixTaskJob":Remove.val,"enerCubixReleasedAt":DateTime.now])
    try { db.commit(Diff(previous,tags)); return true }
    catch (Err e)
    {
      if (e.typeof.name == "ConcurrentChangeErr") return false
      throw e
    }
  }
}

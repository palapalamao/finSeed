using util
using haystack
using folio
using skyarcd

** Persisted native FIN calculation and alert operations.
class SeedJobs
{
  SeedRepo repo
  new make(SeedRepo repo) { this.repo=repo }
  private [Str:Obj?]? currentJob
  private Str owner := ""
  private Int processed := 0
  private Int alarmsCreated := 0

  [Str:Obj?] run([Str:Obj?] request)
  {
    repo.mustWrite
    action:=request["action"] as Str ?: ""
    if (["setCalculationEnabled","setAlarmEnabled"].contains(action))
    {
      enabled:=request["enabled"] as Bool ?: throw ArgErr("缺少启停状态")
      old:=repo.records.find |r| { r["kind"] == "job" && r["action"] == action }
      config:=old ?: ["kind":"job","name":action == "setCalculationEnabled" ? "计算开关" : "报警开关","action":action]
      config["enabled"]=enabled; config["status"]=enabled ? "enabled" : "disabled"
      config["message"]="FIN 原生每小时调度；原始历史同步由 FIN 连接器独立管理"
      ensureSchedule
      return repo.save(config,true)
    }
    if (!["recalculate","scanAlarms"].contains(action)) throw ArgErr("任务操作无效")
    tz:=TimeZone.fromStr(repo.cx.proj.meta["tz"]?.toStr ?: "Shanghai")
    now:=DateTime.now.toTimeZone(tz); end:=SeedMath.floorHour(now)
    from:=DateTime.fromIso(request["from"] as Str ?: (end-1hr).toIso).toTimeZone(tz)
    to:=DateTime.fromIso(request["to"] as Str ?: end.toIso).toTimeZone(tz)
    if (to <= from || to-from > 366day) throw ArgErr("任务范围须大于零且不超过366天")
    if (from != SeedMath.floorHour(from) || to != SeedMath.floorHour(to)) throw ArgErr("任务起止时间须按整小时选择，不能将部分小时用量写为完整小时")
    owner=Uuid().toStr; processed=0; alarmsCreated=0; currentJob=null
    return (Str:Obj?)SeedTaskLock.withLock(repo.cx.db,owner) |held->Obj?|
    {
      interruptPrevious(held)
      all:=repo.records
      currentJob=repo.save(["kind":"job","name":(action == "recalculate" ? "范围重算 " : "报警检查 ")+now.toIso,"action":action,"status":"running","from":from.toIso,"to":to.toIso,"lastRun":now.toIso,"processed":0],true)
      try
      {
        progress(0)
        if (action == "recalculate") recalculate(all,from.toIso,to.toIso)
        else scan(all,from.toIso,to.toIso)
        currentJob["status"]="completed"
        currentJob["message"]=action == "recalculate" ? "派生历史写入完成；未改写采集点原始历史" : "报警检查完成"
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
    ["setCalculationEnabled":"recalculate","setAlarmEnabled":"scanAlarms"].each |action,setting|
    {
      if (all.any |r| { r["kind"] == "job" && r["action"] == setting && r["enabled"] == true }) result[action]=run(["action":action])
    }
    return result
  }

  private Void progress(Int count)
  {
    SeedTaskLock.heartbeat(repo.cx.db,owner,Ref(currentJob["id"].toStr))
    processed+=count
    currentJob["processed"]=processed; currentJob["lastRun"]=DateTime.now.toIso
    currentJob=repo.save(currentJob,true)
  }

  private Void interruptPrevious(Dict held)
  {
    previous:=held["seedPreviousJob"] as Ref
    if (previous == null) return
    record:=repo.cx.db.readById(previous,false)
    if (record == null || record["seedKind"] != "job") return
    job:=SeedRepo.decode(record)
    if (job["status"] != "running") return
    job["status"]="failed"; job["lastRun"]=DateTime.now.toIso
    job["message"]="任务中断：上次执行的共享锁租约已过期，新任务已通过 CAS 接管"
    repo.save(job,true)
  }

  private Void ensureSchedule()
  {
    cx:=repo.cx; key:=Ref("finseed-native-hourly-job")
    existing:=cx.db.readById(key,false)
    if (existing != null)
    {
      if (!existing.has("job") || existing["jobExpr"] != "seedScheduled()") throw ArgErr("FIN Seed 调度记录标识已被其他记录占用")
      return
    }
    try { cx.db.commit(Diff.makeAdd(Etc.makeDict(["dis":"FIN Seed 每小时计算与报警","job":Marker.val,"jobExpr":"seedScheduled()","jobSchedule":"hourly"]),key)) }
    catch (Err e)
    {
      if (e.typeof.name != "DuplicateRecErr") throw e
      existing=cx.db.readById(key,false)
      if (existing == null || existing["jobExpr"] != "seedScheduled()") throw e
    }
  }

  private Void recalculate([Str:Obj?][] all, Str from, Str to)
  {
    nodes:=all.findAll |r| { r["kind"] == "group" || (["meter","totalMeter"].contains(r["kind"]) && r["expressionId"] != null) }
    if (nodes.isEmpty) throw ArgErr("没有可计算的管理组或虚拟表")
    cx:=repo.cx; tz:=TimeZone.fromStr(cx.proj.meta["tz"]?.toStr ?: "Shanghai")
    nodes.each |node|
    {
      progress(0)
      report:=repo.report(["kind":"profile","nodeIds":[node["id"]],"from":from,"to":to,"period":"hour","metric":"energy","perArea":false])
      SeedMath.maps(report["series"]).each |s|
      {
        progress(0)
        key:=Ref(derivedId(s)); rec:=cx.db.readById(key,false)
        if (rec == null)
        {
          unit:=s["unit"]?.toStr ?: ""
          if (!unit.isEmpty && Unit.fromStr(unit,false) == null) throw ArgErr("派生点单位不是 FIN 支持的单位：$unit")
          tags:=[Str:Obj?]["dis":s["name"],"point":Marker.val,"his":Marker.val,"kind":"Number","hisMode":"consumption","tz":tz.name,"seedComputed":Marker.val,"seedResultKey":s["id"].toStr,"seedResultCategory":s["categoryId"]?.toStr ?: ""]
          if (!unit.isEmpty) tags["unit"]=unit
          rec=cx.db.commit(Diff.makeAdd(Etc.makeDict(tags),key)).newRec
        }
        checkOwned(rec,s)
        batches:=monthBatches(s)
        batches.keys.sort.each |month|
        {
          progress(0)
          part:=s.dup; part["points"]=batches[month]
          // Verify ownership immediately before each write; source points are never targets.
          rec=cx.db.readById(key); checkOwned(rec,s)
          items:=historyItems(part,tz)
          // SDK HxHisService overwrites matching timestamps. 'replace' is not a
          // documented option; NA explicitly replaces stale values after quality failure.
          SeedTaskLock.heartbeat(cx.db,owner,Ref(currentJob["id"].toStr))
          cx.rt.his.write(rec,items,null).get(5min)
          qualityEvidence(part,rec.id.id,currentJob["id"].toStr).each |evidence| { repo.save(evidence,true) }
          progress(items.size)
        }
      }
    }
  }

  private Void scan([Str:Obj?][] all, Str from, Str to)
  {
    seen:=Str:Bool[:]
    all.findAll |r| { r["kind"] == "alarm" }.each |a| { seen[alarmKey(a["nodeId"],a["categoryId"],a["ts"])]=true }
    all.findAll |r| { SeedConfig.nodeKinds.contains(r["kind"]) }.each |node|
    {
      limits:=[Str:Obj?][,]
      if (node["alarmEnabled"] == true && node["alarmLimit"] != null) limits.add(["categoryId":node["categoryId"],"limit":node["alarmLimit"],"enabled":true])
      if (node["kind"] == "group") limits.addAll(SeedMath.maps(node["alarmLimits"]))
      if (limits.isEmpty) return
      progress(0)
      report:=repo.report(["kind":"profile","nodeIds":[node["id"]],"from":from,"to":to,"period":"hour","metric":"energy","perArea":false])
      pending:=0
      SeedMath.maps(report["series"]).each |s|
      {
        limits.each |limit|
        {
          if (limit["enabled"] == false || (limit["categoryId"] != null && limit["categoryId"] != s["categoryId"])) return
          threshold:=SeedConfig.number(limit["limit"])
          SeedMath.maps(s["points"]).each |p|
          {
            pending++
            if (pending >= 100) { progress(pending); pending=0 }
            if (p["value"] == null || SeedConfig.number(p["value"]) <= threshold) return
            key:=alarmKey(node["id"],s["categoryId"],p["ts"])
            if (seen.containsKey(key)) return
            SeedTaskLock.heartbeat(repo.cx.db,owner,Ref(currentJob["id"].toStr))
            label:=node["name"].toStr
            if (label.size > 60) label=label[0..<60]
            alarmName:=label+" 超限 "+p["ts"]+" ["+key.toBuf.toDigest("SHA-256").toHex[0..<12]+"]"
            repo.save(["kind":"alarm","name":alarmName,"nodeId":node["id"],"categoryId":s["categoryId"],"ts":p["ts"],"value":p["value"],"unit":s["unit"],"limit":threshold,"state":"open","sourceIds":p["sourceIds"],"quality":p["quality"]],true)
            seen[key]=true; alarmsCreated++
          }
        }
      }
      progress(pending)
    }
  }

  private static Str alarmKey(Obj? node, Obj? category, Obj? ts) { "$node|$category|$ts" }

  internal static Str derivedId([Str:Obj?] s)
  {
    identity:=s["id"].toStr+"|"+(s["categoryId"]?.toStr ?: "")+"|"+(s["unit"]?.toStr ?: "")
    return "finseed-derived-"+identity.toBuf.toDigest("SHA-256").toHex[0..<24]
  }

  internal static Void checkOwned(Dict point, [Str:Obj?] s)
  {
    category:=s["categoryId"]?.toStr ?: ""
    if (!point.has("seedComputed") || !point.has("point") || !point.has("his") || point.id.id.split(':').last != derivedId(s) || point["seedResultKey"] != s["id"] || point["seedResultCategory"] != category) throw ArgErr("派生点所有权检查失败，拒绝写入")
    if (point["hisMode"] != "consumption" || point.has("hisTotalized") || (point["unit"]?.toStr ?: "") != (s["unit"]?.toStr ?: "")) throw ArgErr("派生点历史模式或单位不匹配")
    point.each |v,k| { if (k.lower.endsWith("connref") || ["hisFunc","hisOnWrite"].contains(k)) throw ArgErr("派生点存在外部历史来源或写入钩子，拒绝写入") }
  }

  internal static HisItem[] historyItems([Str:Obj?] s, TimeZone tz)
  {
    symbol:=s["unit"]?.toStr ?: ""
    unit:=symbol.isEmpty ? null : Unit.fromStr(symbol,false)
    if (!symbol.isEmpty && unit == null) throw ArgErr("FIN 不支持此派生单位：$symbol")
    return SeedMath.maps(s["points"]).map |p->HisItem|
    {
      at:=DateTime.fromIso(p["ts"].toStr).toTimeZone(tz)
      if (at != SeedMath.floorHour(at)) throw ArgErr("派生历史必须为完整小时")
      n:=SeedMath.num(p["value"])
      return HisItem(at+1hr,n == null ? NA.val : Number(n,unit))
    }
  }

  private static Str:[Str:Obj?][] monthBatches([Str:Obj?] s)
  {
    out:=Str:[Str:Obj?][][:]
    SeedMath.maps(s["points"]).each |p|
    {
      month:=p["ts"].toStr[0..<7]
      if (!out.containsKey(month)) out[month]=[Str:Obj?][,]
      out[month].add(p)
    }
    return out
  }

  internal static [Str:Obj?][] qualityEvidence([Str:Obj?] s, Str point, Str parentJob)
  {
    result:=[Str:Obj?][,]
    batches:=monthBatches(s)
    batches.keys.sort.each |month|
    {
      quality:=Str:Obj?[:]
      batches[month].each |p|
      {
        if (p["quality"] == "ok" && p["value"] != null) return
        candidate:=quality.dup; candidate[p["ts"].toStr]=p["quality"] ?: "missing"
        if (JsonOutStream.writeJsonToStr(candidate).size > 20000)
        {
          if (quality.isEmpty) throw ArgErr("单条质量证据超过存储限制")
          result.add(evidence(point,parentJob,month,quality,result.size)); quality=Str:Obj?[:]
        }
        quality[p["ts"].toStr]=p["quality"] ?: "missing"
      }
      if (!quality.isEmpty) result.add(evidence(point,parentJob,month,quality,result.size))
    }
    return result
  }

  private static [Str:Obj?] evidence(Str point, Str parentJob, Str month, [Str:Obj?] quality, Int index)
  { ["kind":"job","name":"质量证据 "+point+" "+month+" #"+index+" "+parentJob,"action":"quality","status":"completed","resultPointId":point,"parentJobId":parentJob,"month":month,"quality":quality,"lastRun":DateTime.now.toIso,"processed":quality.size] }
}

** One persisted CAS lock is shared by manual and native hourly tasks.
internal class SeedTaskLock
{
  static const Ref key:=Ref("finseed-task-lock")
  static const Duration lease:=30min

  static Obj? withLock(Folio db, Str owner, |Dict->Obj?| action)
  {
    held:=acquire(db,owner)
    try { return action(held) }
    finally { release(db,owner) }
  }

  static Dict acquire(Folio db, Str owner, DateTime now:=DateTime.now)
  {
    try { return db.commit(acquisition(db.readById(key,false),owner,now)).newRec }
    catch (Err e)
    {
      if (["DuplicateRecErr","ConcurrentChangeErr"].contains(e.typeof.name)) throw SeedHttpErr(409,"BUSY","已有计算任务正在执行")
      // HxFolio reports an add collision as CommitErr; confirm the competing
      // lock exists rather than depending only on one implementation's Err name.
      if (e.typeof.name == "CommitErr")
      {
        competing:=db.readById(key,false)
        if (competing?.has("seedTaskLock") == true && competing["seedOwner"] != owner) throw SeedHttpErr(409,"BUSY","已有计算任务正在执行")
      }
      throw e
    }
  }

  internal static Diff acquisition(Dict? previous, Str owner, DateTime now)
  {
    if (previous != null && !previous.has("seedTaskLock")) throw ArgErr("任务锁标识已被其他记录占用")
    until:=previous?.get("seedLeaseUntil") as DateTime
    if (previous?.has("seedOwner") == true && (until == null || until > now)) throw SeedHttpErr(409,"BUSY","已有计算任务正在执行")
    tags:=[Str:Obj?]["dis":"FIN Seed 共享计算锁","seedTaskLock":Marker.val,"seedOwner":owner,"seedLeaseUntil":now+lease,"seedLockAt":now]
    if (previous != null)
    {
      if (previous["seedTaskJob"] is Ref) tags["seedPreviousJob"]=previous["seedTaskJob"]
      else if (previous.has("seedPreviousJob")) tags["seedPreviousJob"]=Remove.val
      if (previous.has("seedTaskJob")) tags["seedTaskJob"]=Remove.val
    }
    return previous == null ? Diff.makeAdd(Etc.makeDict(tags),key) : Diff(previous,Etc.makeDict(tags))
  }

  static Dict heartbeat(Folio db, Str owner, Ref? job:=null, DateTime now:=DateTime.now)
  {
    previous:=db.readById(key,false)
    if (previous == null || previous["seedOwner"] != owner) throw SeedHttpErr(409,"LOCK_LOST","任务锁已由其他执行接管，当前任务停止写入")
    tags:=[Str:Obj?]["seedLeaseUntil":now+lease,"seedLockAt":now]
    if (job != null) tags["seedTaskJob"]=job
    try { return db.commit(Diff(previous,Etc.makeDict(tags))).newRec }
    catch (Err e)
    {
      if (e.typeof.name == "ConcurrentChangeErr") throw SeedHttpErr(409,"LOCK_LOST","任务锁已变更，当前任务停止写入")
      throw e
    }
  }

  static Bool release(Folio db, Str owner)
  {
    previous:=db.readById(key,false)
    if (previous == null || previous["seedOwner"] != owner) return false
    tags:=Etc.makeDict(["seedOwner":Remove.val,"seedLeaseUntil":Remove.val,"seedTaskJob":Remove.val,"seedReleasedAt":DateTime.now])
    try { db.commit(Diff(previous,tags)); return true }
    catch (Err e)
    {
      if (e.typeof.name == "ConcurrentChangeErr") return false
      throw e
    }
  }
}

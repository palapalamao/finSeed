using haystack
using folio
using util

** Closed-minute generation. Inputs are read once here; report reads are meter-owned.
internal class EnerCubixMeterGeneration
{
  static Void update(Folio db, DateTime now:=DateTime.now)
  {
    task:=db.read(Filter.has("enerCubixTaskLock"),false)
    until:=task?.get("enerCubixLeaseUntil") as DateTime
    if (task?.has("enerCubixOwner") == true && (until == null || until > now)) return
    EnerCubixMeterTimeline.initialize(db,now)
    records:=EnerCubixMeterTimeline.current(db)
    targets:=records.findAll |r| { eligible(db,r) }
    targets.sort |a,b| { level(a,records,Str[,]) <=> level(b,records,Str[,]) }
    targets.each |record|
    {
      if (!retryDue(db,record,now)) return
      try { ensure(db,record,records,now) }
      catch (Err e) { failed(db,record,e,now) }
    }
    // One-minute settling allows native source collectors to archive the end boundary.
    finish:=EnerCubixMeterHistory.floorMinute(now-1min)
    targets.each |record|
    {
      if (!retryDue(db,record,now)) return
      try { runTarget(db,record,records,finish,now) }
      catch (Err e) { failed(db,record,e,now) }
    }
  }

  ** Explicit derived-history repair. Source raw histories are never write targets.
  static Int recalculate(Folio db, [Str:Obj?][] records, DateTime from, DateTime to, Bool locked:=false, |Int|? onProgress:=null)
  {
    if (to <= from || to-from > 366day || from != EnerCubixMeterHistory.floorMinute(from) || to != EnerCubixMeterHistory.floorMinute(to)) throw ArgErr("重算范围须按整分钟选择且不超过366天")
    if (to > EnerCubixMeterHistory.floorMinute(DateTime.now-1min)) throw ArgErr("不能重算未来或尚未结束的时间区间")
    if (db.readAllList(Filter.has("enerCubixMeterGeneration")).isEmpty) return 0
    if (!locked)
    {
      return (Int)EnerCubixTaskLock.withLock(db,Uuid().toStr) |held->Obj?|
      { recalculate(db,records,from,to,true,onProgress) }
    }
    count:=0; at:=from
    while (at < to)
    {
      end:=at+1min
      targets:=records.findAll |r| {eligible(db,r)}.sort |a,b| {level(a,records,Str[,]) <=> level(b,records,Str[,])}
      targets.each |record|
      {
        pointId:=record["pointId"] as Str ?: record["historyPointId"] as Str
        if (pointId == null) return
        point:=db.readById(Ref(pointId),false)
        if (point == null) return
        state:=db.readById(EnerCubixMeterHistory.stateId(point.id),false)
        start:=state?.get("enerCubixGenerationStart") as DateTime
        cursor:=state?.get("enerCubixGenerationCursor") as DateTime
        if (state == null || start == null || cursor == null || at < start) return
        if (end > cursor) throw ArgErr("只能修正已经生成的历史区间")
        publish(db,point,state,at,end,calculate(db,record,records,at,end),DateTime.now,record["expressionId"] != null,true)
        count++
        if (onProgress != null) onProgress(count == 0 ? 0 : 1)
        else
        {
          held:=db.read(Filter.has("enerCubixTaskLock"),false)
          owner:=held?.get("enerCubixOwner") as Str
          if (owner != null) EnerCubixTaskLock.heartbeat(db,owner)
        }
      }
      at=end
    }
    return count
  }

  private static Void runTarget(Folio db, [Str:Obj?] record, [Str:Obj?][] records, DateTime finish, DateTime now)
  {
      pointId:=record["pointId"] as Str ?: record["historyPointId"] as Str
      if (pointId == null) return
      point:=db.readById(Ref(pointId),false)
      if (point == null) return
      for (i:=0;i<4;i++)
      {
        state:=db.readById(EnerCubixMeterHistory.stateId(point.id),false)
        from:=state?.get("enerCubixGenerationCursor") as DateTime
        if (state == null || from == null || from+1min > finish) break
        if ((state["enerCubixOwnerRef"] as Ref)?.id != record["id"]) throw ArgErr("表计用量历史点归属已改变，停止写入")
        to:=from+1min
        value:=calculate(db,record,records,from,to)
        if (value.value != null && value.value < 0f) value=EnerCubixValue(null,"negative",value.sources)
        publish(db,point,state,from,to,value,now,record["expressionId"] != null)
      }
      if (record["expressionId"] != null)
      {
        last:=db.readById(EnerCubixMeterHistory.stateId(point.id),false)
        if (last?.has("enerCubixLastMissing") == true) refreshFormula(db,point,last)
      }
      issue:=db.readById(issueId(record),false)
      if (issue?.get("enerCubixIssueActive") == true) db.commit(Diff(issue,Etc.makeDict(["enerCubixIssueActive":false,"enerCubixResolvedAt":now])))
  }

  private static Ref issueId([Str:Obj?] record) { Ref("enerCubix-generation-issue-"+record["id"].toStr.toBuf.toDigest("SHA-256").toHex[0..<24]) }
  private static Bool retryDue(Folio db, [Str:Obj?] record, DateTime now)
  {
    issue:=db.readById(issueId(record),false)
    retry:=issue?.get("enerCubixRetryAfter") as DateTime
    return issue?.get("enerCubixIssueActive") != true || retry == null || retry <= now
  }
  private static Void failed(Folio db, [Str:Obj?] record, Err error, DateTime now)
  {
    Log.get("enerCubix").err("Meter generation failed: "+record["id"],error)
    previous:=db.readById(issueId(record),false)
    tags:=Etc.makeDict(["enerCubixGenerationIssue":Marker.val,"enerCubixIssueActive":true,"enerCubixOwnerRef":Ref(record["id"].toStr),"enerCubixGenerationError":error.msg,"enerCubixRetryAfter":now+1min,"enerCubixGenerationErrorAt":now,"dis":"EnerCubix meter generation failure"])
    try { db.commit(previous == null ? Diff.makeAdd(tags,issueId(record)) : Diff(previous,tags)) }
    catch (Err evidenceError) { Log.get("enerCubix").err("Cannot persist meter generation failure",evidenceError) }
  }

  internal static Void ensure(Folio db, [Str:Obj?] record, [Str:Obj?][] records, DateTime now)
  {
    if (record["pointId"] == null && record["expressionId"] == null) return
    mainId:=record["pointId"] == null ? EnerCubixMeterHistory.formulaId(Ref(record["id"].toStr)) : Ref(record["pointId"].toStr)
    // Reference and state keys use the committed point identity.
    if (db.idPrefix != null && mainId.isRel) mainId=mainId.toAbs(db.idPrefix)
    main:=db.readById(mainId,false)
    if (db.readById(EnerCubixMeterHistory.stateId(mainId),false) != null) return
    category:=records.find |r| {r["id"] == record["categoryId"]}
    categoryUnit:=category?.get("unit")?.toStr
    unit:=main?.get("unit")?.toStr ?: (record["expressionId"] != null && categoryUnit != null ? categoryUnit : (record["unit"]?.toStr ?: ""))
    if (unit.isEmpty || Unit.fromStr(unit,false) == null) return
    owner:=db.readById(Ref(record["id"].toStr),false)
    if (owner == null || !owner.has("equip")) return
    formula:=record["expressionId"] != null
    if (main == null && !formula) return
    if (main != null && (main["equipRef"] != owner.id || !main.has("his"))) return
    usageId:=formula ? mainId : EnerCubixMeterHistory.usageId(mainId)
    usage:=db.readById(usageId,false)
    if (usage != null && (usage["enerCubixIntervalSourceRef"] != mainId || usage["equipRef"] != owner.id)) throw ArgErr("表计用量历史点标识已被其他记录占用")
    tz:=main?.get("tz")?.toStr ?: "UTC"
    tags:=Str:Obj?["point":Marker.val,"his":Marker.val,"kind":"Number","unit":unit,"hisMode":"consumption","tz":tz,"equipRef":owner.id,"enerCubixComputed":Marker.val,"enerCubixIntervalSourceRef":mainId,"dis":record["name"]?.toStr ?: record["id"].toStr]
    if (formula) { tags["enerCubixFormulaResult"]=Marker.val; tags["cur"]=Marker.val }
    diffs:=Diff[,]
    if (usage == null) diffs.add(Diff.makeAdd(Etc.makeDict(tags),db.idPrefix == null ? usageId : usageId.toRel(db.idPrefix)))
    start:=EnerCubixMeterHistory.floorMinute(now)
    if (start < now) start+=1min
    seed:=main?.get("curVal") as Number
    legacy:=main?.get("hisFunc") == "enerCubixCleanHis" ? (main?.get("hisFuncConfig") as Dict ?: Etc.emptyDict) : Etc.emptyDict
    state:=Etc.makeDict(["enerCubixMeterGeneration":Marker.val,"enerCubixMainRef":mainId,"enerCubixOwnerRef":owner.id,"enerCubixUsageRef":usageId,"enerCubixArchiveUnit":unit,"enerCubixGenerationStart":start,"enerCubixGenerationCursor":start,"enerCubixGeneratedCumulative":Number(seed?.toFloat ?: 0f,Unit(unit)),"enerCubixGenerationHasGap":false,"enerCubixGenerationLegacyConfig":legacy,"dis":"EnerCubix owned interval publication"])
    diffs.add(Diff.makeAdd(state,EnerCubixMeterHistory.stateId(mainId)))
    db.commitAll(diffs)
  }

  private static Bool eligible(Folio db, [Str:Obj?] record)
  {
    kind:=record["kind"] as Str
    if (kind == null || !["meter","totalMeter"].contains(kind)) return false
    if (record["canonicalId"] != null) return false
    if (record["autoSum"] == true || record["expressionId"] != null || record["cleaningEnabled"] == true) return true
    point:=record["pointId"] as Str
    return point != null && db.readById(EnerCubixMeterHistory.stateId(Ref(point)),false) != null
  }

  internal static EnerCubixValue calculate(Folio db, [Str:Obj?] record, [Str:Obj?][] records, DateTime from, DateTime to)
  {
    if (record["expressionId"] != null)
    {
      expression:=records.find |r| {r["id"] == record["expressionId"] && r["kind"] == "expression"}
      if (expression == null) return EnerCubixValue(null,"missingExpression")
      variables:=Str:EnerCubixValue[:]
      Map refs:=expression["variables"] as Map ?: Str:Obj?[:]
      refs.each |id,name|
      {
        source:=records.find |r| {r["id"] == id}
        if (source == null) variables[name.toStr]=EnerCubixValue(null,"missingSource")
        else
        {
          category:=records.find |r| {r["id"] == source["categoryId"]}
          targetUnit:=category?.get("unit")?.toStr ?: meterUnit(db,source,records)
          factor:=source["kind"] == "sensor" ? 1f : EnerCubixMath.unitFactor(meterUnit(db,source,records),targetUnit)
          variables[name.toStr]=factor == null ? EnerCubixValue(null,"incompatibleUnit") : input(db,source,records,from,to).scale(factor)
        }
      }
      return EnerCubixExpression(expression["formula"]?.toStr ?: "",variables).calculate
    }
    physicalId:=record["pointId"] as Str
    physical:=physicalId == null ? null : db.readById(Ref(physicalId),false)
    if (record["autoSum"] != true || EnerCubixMeterRollup.collected(physical)) return input(db,record,records,from,to,true)
    children:=records.findAll |r| { ["meter","totalMeter"].contains(r["kind"]) && r["meterParentId"] == record["id"] && r["canonicalId"] == null }
    if (children.isEmpty) return EnerCubixValue(null,"missingBranches")
    unit:=meterUnit(db,record,records)
    values:=children.map |child->EnerCubixValue|
    {
      if (child["categoryId"] != record["categoryId"]) return EnerCubixValue(null,"incompatibleCategory")
      v:=input(db,child,records,from,to)
      childUnit:=meterUnit(db,child,records)
      factor:=EnerCubixMath.unitFactor(childUnit,unit)
      return factor == null ? EnerCubixValue(null,"incompatibleUnit",v.sources) : v.scale(factor)
    }
    sum:=EnerCubixValue.sum(values)
    if (record["cleaningEnabled"] == true && sum.value != null)
    {
      profile:=records.find |r| {r["id"] == record["cleaningProfileId"] && r["kind"] == "cleaningProfile"}
      pointId:=record["pointId"] as Str
      own:=pointId == null ? null : db.readById(Ref(pointId),false)
      if (profile == null || own == null) return EnerCubixValue(null,"missingCleaningProfile",sum.sources)
      config:=EnerCubixCleaningRepo.configFor(profile,own)
      checked:=EnerCubixCleaning.clean(own,[HisItem(from,Number(0)),HisItem(to,Number(sum.value))],config)
      last:=checked.details.last
      quality:=last["valueType"] == "na" ? "na" : (last["substituted"] == true ? "substituted" : (EnerCubixMath.num(last["value"]) == null ? "filtered" : "cleaned"))
      sum=EnerCubixValue(EnerCubixMath.num(last["value"]),EnerCubixValue.worse(sum.quality,quality),sum.sources)
    }
    return sum
  }

  private static EnerCubixValue input(Folio db, [Str:Obj?] record, [Str:Obj?][] records, DateTime from, DateTime to, Bool ownRaw:=false)
  {
    id:=record["pointId"] as Str ?: record["historyPointId"] as Str
    if (id == null) return EnerCubixValue(null,"missingSource")
    point:=db.readById(Ref(id),false)
    if (point == null || !point.has("his")) return EnerCubixValue(null,"missingSource",[id])
    published:=ownRaw ? null : EnerCubixMeterHistory.loadDb(db,point,from,to)
    if (published != null) return consume(EnerCubixMath.maps(published["intervals"]),from,to,[id])
    if (record["expressionId"] != null) return EnerCubixValue(null,"missing",[id])
    // Unknown computed contracts are never silently interpreted as raw counters.
    func:=point["hisFunc"] as Str
    if (func != null && !["enerCubixCleanHis","hfTotalized"].contains(func)) return EnerCubixValue(null,"unsupportedComputedMode",[id])
    raw:=HisItem[,]
    db.his.read(point.id,Span.makeAbs(from-1hr,to+1hr),null) |item|
    {
      if (raw.size >= 100000) throw ArgErr("历史生成的源读数超过100000条")
      raw.add(item)
    }
    if (record["kind"] == "sensor") return EnerCubixHistoryData(EnerCubixHistory.normalize(point,raw,from,to)).read(from,to)
    declared:=record["historyMode"] as Str ?: "auto"
    isInterval:=func != "hfTotalized" && (declared == "interval" || (declared != "cumulative" && !point.has("hisTotalized") && point["hisMode"] == "consumption"))
    if (isInterval)
    {
      cadence:=point["hisCollectInterval"] as Number ?: point["hisInterval"] as Number
      Duration? interval:=cadence?.toDuration
      if (interval == null)
      {
        sorted:=raw.dup.sort |a,b| {a.ts <=> b.ts}
        if (sorted.size > 1) interval=sorted[1].ts-sorted[0].ts
      }
      if (interval == null || interval <= 0sec) return EnerCubixValue(null,"missingInterval",[id])
      rows:=raw.map |item->[Str:Obj?]|
      {
        value:=item.val is Number ? ((Number)item.val).toFloat : null
        q:=item.val is NA ? "na" : (value == null ? "missing" : (value < 0f ? "negative" : (cadence == null ? "estimated" : "derived")))
        return ["from":(item.ts-interval).toIso,"to":item.ts.toIso,"value":value,"valueType":item.val is NA ? "na" : (value == null ? "null" : "number"),"quality":q]
      }
      return consume(rows,from,to,[id])
    }
    if (func != "hfTotalized" && declared != "cumulative" && !point.has("hisTotalized") && point["hisMode"] != "cumulative") return EnerCubixValue(null,"notEnergyHistory",[id])
    profile:=records.find |r| {r["id"] == record["cleaningProfileId"] && r["kind"] == "cleaningProfile"}
    Dict config:=Etc.makeDict(["deltaMin":Number(0),"defNull":Marker.val])
    if (record["cleaningEnabled"] == true)
    {
      if (profile == null) return EnerCubixValue(null,"missingCleaningProfile",[id])
      config=EnerCubixCleaningRepo.configFor(profile,point)
    }
    cleaned:=EnerCubixCleaning.clean(point,raw,config)
    intervals:=cleaned.details.findAll |d| {d["emitted"] == true && d["intervalSeconds"] != null}.map |d->[Str:Obj?]|
    {
      end:=DateTime.fromIso(d["ts"].toStr)
      seconds:=EnerCubixMath.num(d["intervalSeconds"]) ?: 0f
      q:=detailQuality(d,record["cleaningEnabled"] == true)
      return ["from":(end-Duration((seconds*1sec.ticks.toFloat).toInt)).toIso,"to":end.toIso,"value":d["value"],"valueType":d["valueType"],"quality":q]
    }
    return consume(intervals,from,to,[id])
  }

  private static Str meterUnit(Folio db, [Str:Obj?] record, [Str:Obj?][] records)
  {
    id:=record["pointId"] as Str ?: record["historyPointId"] as Str
    point:=id == null ? null : db.readById(Ref(id),false)
    state:=id == null ? null : db.readById(EnerCubixMeterHistory.stateId(Ref(id)),false)
    category:=records.find |r| {r["id"] == record["categoryId"]}
    return state?.get("enerCubixArchiveUnit")?.toStr ?: (point?.get("unit")?.toStr ?: (record["unit"]?.toStr ?: (category?.get("unit")?.toStr ?: "")))
  }

  private static Str detailQuality(Str:Obj? detail, Bool configured)
  {
    if (detail["valueType"] == "na") return "na"
    if (detail["substituted"] == true) return "substituted"
    if (detail["reason"] == "rollover") return "corrected"
    if (EnerCubixMath.num(detail["value"]) != null) return configured ? "cleaned" : "derived"
    if (["inputNull","previousNull","nonPositiveInterval"].contains(detail["reason"])) return "missing"
    return configured ? "filtered" : "reset"
  }

  ** Explicit bounded interpolation belongs only to generation and is marked estimated.
  internal static EnerCubixValue consume([Str:Obj?][] intervals, DateTime from, DateTime to, Str[] sources)
  {
    cursor:=from; values:=EnerCubixValue[,]
    intervals=intervals.dup.sort |a,b| {DateTime.fromIso(a["from"].toStr).ticks <=> DateTime.fromIso(b["from"].toStr).ticks}
    intervals.each |row|
    {
      a:=DateTime.fromIso(row["from"].toStr); b:=DateTime.fromIso(row["to"].toStr)
      if (b <= from || a >= to || b <= a) return
      left:=a < from ? from : a; right:=b > to ? to : b
      if (left != cursor) { values.add(EnerCubixValue(null,"missing",sources)); cursor=right; return }
      q:=row["quality"] as Str ?: "missing"
      value:=EnerCubixMath.num(row["value"])
      if (left != a || right != b)
      {
        // Long gaps cannot be spread into apparently complete minute values.
        if (b-a > 1hr) {value=null; q="missing"}
        else if (value != null) {value*=((right-left).ticks.toFloat/(b-a).ticks.toFloat); if (["ok","derived","cleaned","corrected"].contains(q)) q="estimated"}
      }
      values.add(EnerCubixValue(value,row["valueType"] == "na" ? "na" : q,sources)); cursor=right
    }
    if (cursor != to) values.add(EnerCubixValue(null,"missing",sources))
    return EnerCubixValue.sum(values)
  }

  internal static Void publish(Folio db, Dict main, Dict state, DateTime from, DateTime to, EnerCubixValue value, DateTime now, Bool formula, Bool repair:=false)
  {
    usageId:=state["enerCubixUsageRef"] as Ref ?: throw ArgErr("缺少表计用量历史点")
    usage:=db.readById(usageId)
    if (usage["enerCubixIntervalSourceRef"] != main.id || usage["equipRef"] != state["enerCubixOwnerRef"] || !usage.has("enerCubixComputed") || EnerCubixMeterRollup.collected(usage)) throw ArgErr("表计用量历史点归属已改变，停止写入")
    hour:=EnerCubixMath.floorHour(from.toTimeZone(TimeZone.utc)); key:=EnerCubixMeterHistory.batchId(main.id,hour)
    candidates:=db.readAllList(Filter.has("enerCubixIntervalBatch").and(Filter.eq("enerCubixMainRef",main.id)).and(Filter.ge("enerCubixBatchHour",hour)).and(Filter.lt("enerCubixBatchHour",hour+1hr)))
    matches:=candidates.findAll |batch| {EnerCubixMath.maps(JsonInStream(batch["enerCubixIntervals"].toStr.in).readJson).any |r| {DateTime.fromIso(r["from"].toStr).ticks == from.ticks}}
    if (!repair && !matches.isEmpty) throw ArgErr("已有发布区间不能由自动任务改写")
    if (repair && !matches.isEmpty) key=matches.first.id
    previous:=db.readById(key,false)
    rows:=previous == null ? [Str:Obj?][,] : EnerCubixMath.maps(JsonInStream(previous["enerCubixIntervals"].toStr.in).readJson)
    old:=rows.find |r| {DateTime.fromIso(r["from"].toStr).ticks == from.ticks}
    currentConfiguration:=EnerCubixMeterTimeline.current(db).sort |a,b| {a["id"].toStr <=> b["id"].toStr}
    configurationRevision:=JsonOutStream.writeJsonToStr(currentConfiguration).toBuf.toDigest("SHA-256").toHex
    sourceIds:=value.sources.dup.sort
    if (repair && matches.size <= 1 && old != null && EnerCubixMath.num(old["value"]) == value.value && old["valueType"] == value.valueType && old["quality"] == value.quality && old["configurationRevision"] == configurationRevision && EnerCubixMath.strings(old["generationSources"]).sort == sourceIds) return
    priorRevision:=EnerCubixMath.num(old?.get("revision")) ?: 0f
    row:=Str:Obj?["from":from.toIso,"to":to.toIso,"value":value.value,"valueType":value.valueType,"quality":value.quality,"sourceIds":[main.id.id],"generationSources":sourceIds,"configurationAt":from.toIso,"configurationRevision":configurationRevision,"calculationVersion":1,"revision":(priorRevision+1f).toInt]
    rows=rows.findAll |r| {DateTime.fromIso(r["from"].toStr).ticks != from.ticks}.dup.add(row)
    json:=JsonOutStream.writeJsonToStr(rows)
    if (json.size > 30000)
    {
      key=EnerCubixMeterHistory.minuteBatchId(main.id,from); previous=db.readById(key,false); rows=[row]; json=JsonOutStream.writeJsonToStr(rows)
      if (json.size > 30000) throw ArgErr("单段用量的来源证据超过30000字符")
    }
    // Identical acknowledged mirror writes are skipped on replay. Conflicting
    // existing values require explicit repair before Folio publication can move.
    usageTz:=TimeZone.fromStr(usage["tz"]?.toStr ?: from.tz.name)
    item:=HisItem(from.toTimeZone(usageTz),value.value == null ? NA.val : Number(value.value,Unit.fromStr(usage["unit"]?.toStr ?: "",false)))
    EnerCubixHistorySafety.write(db,usage,[item],repair)
    tags:=Etc.makeDict(["enerCubixIntervalBatch":Marker.val,"enerCubixMainRef":main.id,"enerCubixUsageRef":usageId,"enerCubixBatchHour":hour,"enerCubixIntervals":json,"enerCubixPublishedAt":now,"dis":"EnerCubix owned minute history"])
    cumulative:=state["enerCubixGeneratedCumulative"] as Number ?: Number(0)
    // A historical correction changes period results, never imports old energy
    // into the live cumulative index as a new current increment.
    next:=cumulative.toFloat+(repair ? 0f : (value.value ?: 0f))
    hasGap:=state["enerCubixGenerationHasGap"] == true || value.value == null || !value.reliable
    stateTags:=repair ? Etc.makeDict(["enerCubixRepairedAt":now]) : Etc.makeDict(["enerCubixGenerationCursor":to,"enerCubixGeneratedCumulative":Number(next,cumulative.unit),"enerCubixGenerationHasGap":hasGap,"enerCubixPublishedAt":now,"enerCubixLastMissing":value.value == null,"enerCubixLastQuality":value.quality])
    diffs:=[previous == null ? Diff.makeAdd(tags,key) : Diff(previous,tags),Diff(state,stateTags)]
    matches.each |batch|
    {
      // The computed key may be relative; both stored records use the same namespace.
      if (previous != null && batch.id == previous.id) return
      retained:=EnerCubixMath.maps(JsonInStream(batch["enerCubixIntervals"].toStr.in).readJson).findAll |r| {DateTime.fromIso(r["from"].toStr).ticks != from.ticks}
      diffs.add(Diff(batch,Etc.makeDict(["enerCubixIntervals":JsonOutStream.writeJsonToStr(retained)])))
    }
    if (repair)
      diffs.add(Diff.makeAdd(Etc.makeDict(["enerCubixIntervalCorrection":Marker.val,"enerCubixMainRef":main.id,"enerCubixCorrectionFrom":from,"enerCubixCorrectionTo":to,"enerCubixCorrectedAt":now,"enerCubixPreviousResult":JsonOutStream.writeJsonToStr(old),"enerCubixNewResult":JsonOutStream.writeJsonToStr(row),"dis":"EnerCubix owned history correction"])))
    db.commitAll(diffs)
    if (formula) refreshFormula(db,main,db.readById(state.id))
  }

  private static Void refreshFormula(Folio db, Dict main, Dict state)
  {
    missing:=state["enerCubixLastMissing"] == true
    tags:=Etc.makeDict(["curVal":missing ? Remove.val : state["enerCubixGeneratedCumulative"],"curStatus":missing ? "fault" : "ok","enerCubixRollupHasGap":state["enerCubixGenerationHasGap"] == true])
    db.commit(Diff(db.readById(main.id),tags,Diff.transient))
  }

  private static Int level([Str:Obj?] record, [Str:Obj?][] records, Str[] path)
  {
    id:=record["id"].toStr
    if (path.contains(id)) return records.size+1
    ids:=record["autoSum"] == true ? records.findAll |r| {r["meterParentId"] == id}.map |r->Str| {r["id"].toStr} : Str[,]
    if (record["expressionId"] != null)
    {
      expression:=records.find |r| {r["id"] == record["expressionId"]}
      Map refs:=expression?.get("variables") as Map ?: Str:Obj?[:]
      ids.addAll(refs.vals.map |v->Str| {v.toStr})
    }
    n:=0
    ids.each |child| {r:=records.find |r| {r["id"] == child}; if (r != null) n=n.max(1+level(r,records,path.dup.add(id)))}
    return n
  }
}

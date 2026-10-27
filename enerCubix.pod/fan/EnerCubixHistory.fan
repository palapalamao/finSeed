using haystack
using skyarcd

** Read-only native FIN history adapter; all arithmetic remains in EnerCubixEngine.
class EnerCubixHistory
{
  internal static Str:Obj? report(Str:Obj? request, [Str:Obj?][] records, [Str:Obj?][] histories)
  {
    return evidence(EnerCubixEngine.report(request,records,histories),histories)
  }

  private static Str:Obj? evidence(Str:Obj? report, [Str:Obj?][] histories)
  {
    Str:Obj? extra:=report["extra"] as Map ?: Str:Obj?[:]
    extra["cleaning"]=histories.findAll |h| { h["cleaning"] != null }.map |h->[Str:Obj?]| { ((Str:Obj?)h["cleaning"]).dup.set("pointId",h["pointId"]).set("sourceIds",h["sourceIds"] ?: [h["pointId"]]) }
    report["extra"]=extra
    return report
  }

  static [Str:Obj?][] load(Context cx, Str:Obj? request, [Str:Obj?][] records)
  {
    plan:=range(request,records)
    from:=(DateTime)plan["from"]; to:=(DateTime)plan["to"]
    out:=[Str:Obj?][,]
    modeRecords:=EnerCubixDimension.active(request) ? EnerCubixDimension(request["dimension"].toStr,records,request["spaceSource"] == "fin").records : records
    pointIds(request,records).each |id|
    {
      Dict? point:=null
      try
      {
        point=cx.db.readById(Ref(id),false)
        if (point == null || !point.has("his")) { out.add(unavailable(id,"missing")); return }
        if (!cx.canRead(point)) { out.add(unavailable(id,"forbidden")); return }
        if (!primaryReadAllowed(point,records)) { out.add(unavailable(id,"missingSource")); return }
        items:=HisItem[,]
        pointTz:=TimeZone.fromStr(point["tz"]?.toStr ?: from.tz.name,false) ?: from.tz
        // HxHisService may supply leading/trailing items. A modest extra day also
        // covers subdaily interval-end values on implementations that clip the span.
        readStart:=(from-1day).toTimeZone(pointTz); readEnd:=(to+1day).toTimeZone(pointTz)
        span:=Span.makeAbs(readStart,readEnd)
        // A trend is a stored-sample view, including when a point also has a
        // consumption function. Never replace it with cleaned child intervals.
        if (request["kind"] == "trend")
        {
          cx.rt.his.read(point,span,Etc.makeDict(["raw":Marker.val])) |HisItem item|
          {
            if (items.size >= 1000000) throw ArgErr("History exceeds 1000000 raw samples")
            items.add(item)
          }
          out.add(normalize(point,items,from,to,true))
          return
        }
        overrides:=modeRecords.findAll |r| { r["pointId"] == id && r["historyMode"] != null && r["historyMode"] != "auto" }.map |r->Str| { r["historyMode"].toStr }.unique
        if (overrides.size > 1) throw ArgErr("Conflicting EnerCubix history modes")
        if (point["hisFunc"] == "enerCubixCleanHis" && request["raw"] != true)
        {
          result:=cleanRead(cx,point,span,Etc.emptyDict,Etc.emptyDict)
          out.add(normalizeClean(point,result,from,to,request["kind"] == "trend"))
          return
        }
        cx.rt.his.read(point,span,request["raw"] == true ? Etc.makeDict(["raw":Marker.val]) : readOptions(point)) |HisItem item|
        {
          if (items.size >= 1000000) throw ArgErr("History exceeds 1000000 raw samples")
          items.add(item)
        }
        mode:=outputMode(point,overrides.first,true)
        out.add(normalize(point,items,from,to,request["kind"] == "trend",mode))
      }
      catch (ArgErr e)
      {
        code:=["missingSource","missingCleaningProfile","duplicateSource","cycle","incompatibleCategory","incompatibleUnit","missingBranches"].contains(e.msg) ? e.msg : "invalidCleaningConfiguration"
        failed:=unavailable(id,code); failed["error"]=e.msg; out.add(failed)
      }
      catch (Err e) { out.add(unavailable(id,"historyReadError")) }
    }
    return out
  }

  ** Generation never rewrites legacy raw history. A crossing query combines
  ** only complete pre-cutover own intervals with published post-cutover data.
  internal static Str:Obj? mergePublished(Str:Obj? legacy, Str:Obj? published, DateTime cutover)
  {
    rows:=EnerCubixMath.maps(legacy["intervals"]).findAll |row| { DateTime.fromIso(row["to"].toStr) <= cutover }
    out:=published.dup
    out["intervals"]=rows.dup.addAll(EnerCubixMath.maps(published["intervals"]))
    out["mode"]="interval"
    out["rawSamples"]=legacy["rawSamples"]
    if (legacy["cleaning"] != null) out["cleaning"]=legacy["cleaning"]
    return out
  }

  internal static Str[] pointIds(Str:Obj? request, [Str:Obj?][] records)
  {
    plan:=dependencies(request,records)
    return ((Str[])plan["points"]).sort
  }

  ** Non-energy references remain available, but energy histories require a device binding.
  internal static Bool primaryReadAllowed(Dict point, [Str:Obj?][] records)
  {
    if (point.has("enerCubixComputed")) return false
    if (records.any |r| {["meter","totalMeter","sensor"].contains(r["kind"]) && r["pointId"] == point.id.id}) return true
    unit:=point["unit"] as Str ?: ""
    return !records.any |r| {r["kind"] == "category" && EnerCubixMath.unitFactor(unit,r["unit"] as Str ?: "") != null}
  }

  internal static Str:Obj? range(Str:Obj? request, [Str:Obj?][] records)
  {
    from:=DateTime.fromIso(request["from"]?.toStr ?: ""); to:=DateTime.fromIso(request["to"]?.toStr ?: "")
    tz:=TimeZone.fromStr(request["tz"]?.toStr ?: from.tz.name)
    from=from.toTimeZone(tz); to=to.toTimeZone(tz)
    if (request["otherFrom"] != null && request["otherTo"] != null)
    {
      otherFrom:=DateTime.fromIso(request["otherFrom"].toStr).toTimeZone(tz)
      otherTo:=DateTime.fromIso(request["otherTo"].toStr).toTimeZone(tz)
      if (otherTo <= otherFrom) throw ArgErr("Invalid comparison range")
      if (otherFrom < from) from=otherFrom
      if (otherTo > to) to=otherTo
    }
    if (to <= from) throw ArgErr("Invalid history range")
    if (request["metric"] == "cost")
    {
      plan:=dependencies(request,records); nodes:=(Str[])plan["nodes"]
      ctx:=EnerCubixContext(records,[Str:Obj?][,],tz)
      records.each |r|
      {
        if (!nodes.contains(r["id"]?.toStr ?: "")) return
        tariff:=ctx.tariff(r)
        mode:=tariff?.get("mode")?.toStr
        if (mode == "yearlyBlock") from=EnerCubixMath.bucket(from,"year")
        else if (mode == "monthlyBlock") from=EnerCubixMath.bucket(from,"month")
      }
    }
    from=EnerCubixMath.floorHour(from)
    end:=EnerCubixMath.floorHour(to); if (end < to) end+=1hr
    if ((end-from).ticks/1hr.ticks > 100000) throw ArgErr("History range exceeds 100000 hours")
    return ["from":from,"to":end]
  }

  internal static Str:Obj? normalize(Dict point, HisItem[] items, DateTime from, DateTime to, Bool raw := false, Str? historyMode := null)
  {
    mode:=historyMode ?: "auto"
    if (mode == "auto")
    {
      mode=point["hisMode"]?.toStr ?: "sampled"
      if (point.has("hisTotalized")) mode="cumulative"
      else if (mode == "consumption") mode="interval"
    }
    byTime:=Int:HisItem[:]; items.each |item| { byTime[item.ts.ticks]=item }
    sorted:=byTime.vals.sort |a,b| { a.ts <=> b.ts }
    out:=[Str:Obj?]["pointId":point.id.id,"unit":point["unit"]?.toStr ?: "","mode":mode,"quality":"ok"]
    out["simulated"]=point.has("simulated")
    samples:=[Str:Obj?][,]
    rawSamples:=sorted.map |item->[Str:Obj?]| { ["ts":item.ts.toTimeZone(from.tz).toIso,"value":number(item.val),"valueType":valueType(item.val)] }
    out["rawSamples"]=rawSamples; out["rawQuality"]="ok"
    if (mode != "interval" || raw)
    {
      out["samples"]=rawSamples; return out
    }
    interval:=cadence(point,sorted)
    if (interval == null) { out["quality"]="missingInterval"; out["samples"]=samples; return out }
    known:=point["hisCollectInterval"] != null || point["hisInterval"] != null
    estimated:=!known
    hours:=Int:EnerCubixHourAccumulator[:]
    sorted.each |item|
    {
      end:=item.ts.toTimeZone(from.tz); start:=end-interval
      if (end <= from || start >= to) return
      at:=EnerCubixMath.floorHour(start)
      v:=number(item.val)
      while (at < end)
      {
        finish:=at+1hr
        left:=start > at ? start : at; right:=end < finish ? end : finish
        if (right > left && at >= from && at < to)
        {
          if (!hours.containsKey(at.ticks)) hours[at.ticks]=EnerCubixHourAccumulator()
          acc:=hours[at.ticks]; overlap:=(right-left).ticks
          acc.covered+=overlap
          if (v == null) acc.invalid=true
          else acc.value+=v*overlap.toFloat/interval.ticks.toFloat
          if (overlap != interval.ticks) estimated=true
        }
        at=finish
      }
    }
    cursor:=from
    while (cursor < to)
    {
      acc:=hours[cursor.ticks]
      valid:=acc != null && !acc.invalid && acc.covered == 1hr.ticks
      samples.add(["ts":cursor.toIso,"value":valid ? acc.value : null])
      cursor+=1hr
    }
    out["quality"]=estimated ? "estimated" : "ok"
    out["samples"]=samples
    return out
  }

  ** Read the primary point's stored samples; functions cannot redirect a report.
  internal static Dict readOptions(Dict point)
  {
    return Etc.makeDict(["raw":Marker.val])
  }

  internal static Str outputMode(Dict point, Str? configured := null, Bool raw := false)
  {
    return configured ?: "auto"
  }

  internal static Str valueType(Obj? value) { value is NA ? "na" : (value == null ? "null" : "number") }

  ** Shared entry for FIN hisRead and reports. Every meter cleans its own stored
  ** readings; historical queries never expand its current child relationships.
  internal static EnerCubixCleanResult cleanRead(Context cx, Dict point, Span span, Dict opts, Dict config)
  {
    if (!cx.canRead(point)) throw ArgErr("forbidden")
    return cleanStored(cx,point,span,opts,config)
  }

  private static EnerCubixCleanResult cleanStored(Context cx, Dict point, Span span, Dict opts, Dict config)
  {
    if (!cx.canRead(point)) throw ArgErr("forbidden")
    if (!opts.has("enerCubixCleaningPreview") || config.isEmpty)
    {
      defaults:=point["hisFuncConfig"] as Dict ?: Etc.emptyDict
      if (point.has("enerCubixCleaningOwned"))
      {
        stored:=cx.db.readById(point.id,false) ?: throw ArgErr("missingSource")
        defaults=EnerCubixCleaningRepo(EnerCubixRepo(cx)).currentConfig(stored)
      }
      config=selectConfig(defaults,config)
    }
    if (config.isEmpty) throw ArgErr("missingCleaningProfile")
    answer:=EnerCubixCleaning.clean(point,storedRaw(cx,point,span),config)
    answer.summary["sourceIds"]=[point.id.id]
    answer.summary["pointId"]=point.id.id
    answer.summary["profileId"]=(config["enerCubixProfileRef"] as Ref)?.id
    answer.summary["profileVersion"]=(config["enerCubixProfileVersion"] as Number)?.toInt
    answer.summary["parameters"]=EnerCubixCleaning.jsonConfig(config)
    return answer
  }

  private static HisItem[] storedRaw(Context cx, Dict point, Span span)
  {
    raw:=HisItem[,]
    cx.rt.his.read(point,span,Etc.makeDict(["raw":Marker.val])) |item|
    {
      if (raw.size >= 1000000) throw ArgErr("History exceeds 1000000 raw samples")
      raw.add(item)
    }
    return raw
  }

  ** Native consumption functions expose already-published own intervals
  ** directly; differencing them again would turn consumption into a counter.
  internal static EnerCubixCleanResult publishedResult(Dict point, Str:Obj? published, EnerCubixCleanResult? legacy := null)
  {
    cutover:=DateTime.fromIso(published["cutover"].toStr)
    result:=EnerCubixCleanResult()
    if (legacy != null)
    {
      result.rawItems=legacy.rawItems
      result.items=legacy.items.findAll |item| { item.ts <= cutover }
      result.details=legacy.details.findAll |detail|
      {
        at:=DateTime.fromIso(detail["ts"].toStr)
        return detail["emitted"] == true ? at <= cutover : at < cutover
      }
      result.summary=legacy.summary.dup
    }
    EnerCubixMath.maps(published["intervals"]).each |row|
    {
      start:=DateTime.fromIso(row["from"].toStr); end:=DateTime.fromIso(row["to"].toStr)
      if (start < cutover || end <= start) return
      number:=EnerCubixMath.num(row["value"])
      quality:=row["quality"] as Str ?: (number == null ? "missing" : "derived")
      isNA:=row["valueType"] == "na" || quality == "na"
      value:=isNA ? NA.val : (number == null ? null : Number(number,Unit.fromStr(point["unit"]?.toStr ?: "",false)))
      result.items.add(HisItem(end,value))
      detail:=row.dup
      detail["ts"]=end.toIso; detail["intervalSeconds"]=(end-start).ticks.toFloat/1sec.ticks.toFloat
      detail["value"]=isNA ? null : number; detail["valueType"]=isNA ? "na" : (number == null ? "null" : "number")
      detail["quality"]=quality; detail["emitted"]=true; detail["substituted"]=quality == "substituted"
      if (detail["reason"] == null) detail["reason"]=isNA ? "inputNA" : (number == null ? "inputNull" : "ok")
      result.details.add(detail)
    }
    result.summary["pointId"]=point.id.id; result.summary["sourceIds"]=[point.id.id]
    result.summary["inputCount"]=result.rawItems.size; result.summary["outputCount"]=result.items.size
    result.summary["validCount"]=result.items.findAll |item| { item.val is Number }.size
    result.summary["nullCount"]=result.items.findAll |item| { item.val == null }.size
    result.summary["naCount"]=result.items.findAll |item| { item.val === NA.val }.size
    return result
  }

  internal static EnerCubixCleanResult sumClean(Dict point, EnerCubixCleanResult[] parts, Str[] units)
  {
    result:=EnerCubixCleanResult(); times:=Int:DateTime[:]; indices:=Str:[Str:Obj?][:]
    parts.each |part,i|
    {
      // Nested totals already carry leaf events; do not recount their aggregate
      // intervals or deduplicate distinct sources that share the same timestamp.
      id:=(part.summary["pointId"] as Str) ?: (EnerCubixMath.strings(part.summary["sourceIds"]).first ?: "")
      result.sourceDetails.addAll(interventions(part,id,units[i]))
      part.details.findAll |d| { d["emitted"] != false && d["intervalSeconds"] != null }.each |d|
      {
        at:=DateTime.fromIso(d["ts"].toStr); times[at.ticks]=at; indices["$i|${at.ticks}"]=d
      }
    }
    unit:=point["unit"]?.toStr ?: ""
    times.keys.sort.each |ticks|
    {
      values:=EnerCubixValue[,]; seconds:=Float?[,]; reason:="ok"
      parts.each |part,i|
      {
        d:=indices["$i|$ticks"]
        if (d == null) { reason="unalignedSources"; values.add(EnerCubixValue()); return }
        seconds.add(EnerCubixMath.num(d["intervalSeconds"]))
        factor:=EnerCubixMath.unitFactor(units[i],unit) ?: throw ArgErr("incompatibleUnit")
        values.add(EnerCubixValue(EnerCubixMath.num(d["value"]),detailQuality(d)).scale(factor))
      }
      if (seconds.unique.size != 1 || seconds.size != parts.size) reason="unalignedSources"
      sum:=EnerCubixValue.sum(values)
      if (reason != "ok") sum=EnerCubixValue(null,"missing")
      val:=sum.quality == "na" ? NA.val : (sum.value == null ? null : Number(sum.value,Unit.fromStr(unit,false)))
      result.items.add(HisItem(times[ticks],val))
      result.details.add(["ts":times[ticks].toIso,"value":sum.value,"valueType":sum.valueType,"quality":sum.quality,"reason":reason,"substituted":sum.quality == "substituted","intervalSeconds":seconds.first,"emitted":true])
    }
    result.summary["pointId"]=point.id.id
    result.summary["sourceIds"]=parts.map |p->Str[]| { EnerCubixMath.strings(p.summary["sourceIds"]) }.flatten.unique
    result.summary["sources"]=parts.map |p->[Str:Obj?]| { p.summary.dup }
    ["inputCount","outputCount","validCount","nullCount","naCount","substitutedCount","removedNACount","rejectedCount","rolloverCount"].each |key|
    {
      n:=0f; parts.each |p| { n+=EnerCubixMath.num(p.summary[key]) ?: 0f }; result.summary[key]=n.toInt
    }
    return result
  }

  private static [Str:Obj?][] interventions(EnerCubixCleanResult result, Str id, Str unit)
  {
    if (result.summary.containsKey("sources")) return result.sourceDetails
    return result.details.findAll |d| { !["ok","noPrevious"].contains(d["reason"]) }.map |d->[Str:Obj?]|
    {
      event:=d.dup; reason:=d["reason"].toStr
      event["pointId"]=id; event["unit"]=unit
      event["rule"]=reason == "rollover" ? "hisTotalizedRollover" : (["deltaMin","deltaMax","derivMin","derivMax","timeMax","rolloverOutOfRange"].contains(reason) ? (reason == "rolloverOutOfRange" ? "hisTotalizedRollover" : reason) : null)
      ["profileId","profileVersion","parameters"].each |key| { if (result.summary[key] != null) event[key]=result.summary[key] }
      return event
    }
  }

  private static Bool eventInRange(Str:Obj? event, DateTime from, DateTime to)
  {
    end:=DateTime.fromIso(event["ts"].toStr)
    seconds:=EnerCubixMath.num(event["intervalSeconds"]) ?: 0f
    if (event["emitted"] != false && seconds > 0f)
      return end > from && end-Duration((seconds*1sec.ticks.toFloat).toInt) < to
    return end >= from && end < to
  }

  private static Str:Obj? processingCounts([Str:Obj?][] events)
  {
    return ["rolloverCount":events.findAll |d| { d["reason"] == "rollover" }.size,
      "rejectedCount":events.findAll |d| { d["emitted"] == true && d["reason"] != "rollover" }.size,
      "removedNACount":events.findAll |d| { d["reason"] == "removedNA" }.size,
      "substitutedCount":events.findAll |d| { d["substituted"] == true }.size]
  }

  private static [Str:Obj?][] scopedSources([Str:Obj?][] sources, [Str:Obj?][] events)
  {
    return sources.map |source->[Str:Obj?]|
    {
      ids:=EnerCubixMath.strings(source["sourceIds"])
      scoped:=source.dup.setAll(processingCounts(events.findAll |e| { ids.contains(e["pointId"]) }))
      if (source["sources"] is List) scoped["sources"]=scopedSources(EnerCubixMath.maps(source["sources"]),events)
      return scoped
    }
  }

  ** Shared report/preview provenance. Counts use all selected leaf events before
  ** diagnostics are capped; output counts and coverage still describe this object.
  internal static Str:Obj? cleaningEvidence(Dict point, EnerCubixCleanResult result, DateTime from, DateTime to)
  {
    derived:=result.summary.containsKey("sources")
    events:=interventions(result,point.id.id,point["unit"]?.toStr ?: "").findAll |d| { eventInRange(d,from,to) }
    details:=events.dup
    if (derived) result.details.findAll |d| { !["ok","noPrevious"].contains(d["reason"]) && eventInRange(d,from,to) }.each |d|
      { details.add(d.dup.set("pointId",point.id.id).set("unit",point["unit"])) }
    details.sort |a,b|
    {
      cmp:=DateTime.fromIso(a["ts"].toStr) <=> DateTime.fromIso(b["ts"].toStr)
      return cmp == 0 ? a["pointId"].toStr <=> b["pointId"].toStr : cmp
    }
    meta:=processingCounts(events)
    meta["processingScope"]=derived ? "sourceIntervals" : "objectIntervals"
    meta["detailsTruncated"]=details.size > 1000
    meta["details"]=(details.size > 1000 ? details[0..<1000] : details).map |d->[Str:Obj?]| { nativeDetail(d) }
    if (derived) meta["sources"]=scopedSources(EnerCubixMath.maps(result.summary["sources"]),events)
    return meta
  }

  ** The arithmetic core retains end-stamped intervals. FIN consumption functions
  ** expose their starts; translate only at the native boundary, never twice.
  internal static HisItem[] nativeItems(EnerCubixCleanResult result)
  {
    seconds:=Int:Float[:]
    result.details.each |d|
    {
      duration:=EnerCubixMath.num(d["intervalSeconds"])
      if (d["emitted"] != false && duration != null && duration > 0f)
        seconds[DateTime.fromIso(d["ts"].toStr).ticks]=duration
    }
    return result.items.map |item->HisItem|
    {
      duration:=seconds[item.ts.ticks] ?: throw ArgErr("missingInterval")
      return HisItem(item.ts-Duration((duration*1sec.ticks.toFloat).toInt),item.val)
    }
  }

  internal static Str:Obj? nativeDetail(Str:Obj? detail)
  {
    out:=detail.dup; seconds:=EnerCubixMath.num(detail["intervalSeconds"])
    if (detail["emitted"] != false && seconds != null && seconds > 0f)
    {
      end:=DateTime.fromIso(detail["ts"].toStr)
      start:=end-Duration((seconds*1sec.ticks.toFloat).toInt)
      out["ts"]=start.toIso; out["intervalStart"]=start.toIso; out["intervalEnd"]=end.toIso
    }
    return out
  }

  ** Explicit values override stored defaults. Clearing a rule removes it, and
  ** selecting an anomaly mode discards only conflicting inherited mode flags.
  internal static Dict selectConfig(Dict defaults, Dict explicit)
  {
    merged:=Etc.dictToMap(defaults)
    modes:=["defNull","defVal","hisTotalizedRollover"]
    if (modes.any |key| { explicit.has(key) && explicit[key] isnot Remove })
      modes.each |key| { if (!explicit.has(key)) merged.remove(key) }
    explicit.each |v,k| { if (v is Remove) merged.remove(k); else merged[k]=v }
    if (merged.containsKey("enerCubixMode")) merged["enerCubixMode"]=merged.containsKey("defNull") ? "drop" : (merged.containsKey("defVal") ? "replace" : "rollover")
    return Etc.makeDict(merged)
  }

  internal static EnerCubixCleanResult externalResult(Dict point, HisItem[] items)
  {
    result:=EnerCubixCleanResult()
    interval:=cadence(point,items)
    cfg:=point["hisFuncConfig"] as Dict
    items.each |item|
    {
      end:=point["hisMode"] == "consumption" && interval != null ? item.ts+interval : item.ts
      result.items.add(HisItem(end,item.val))
      reason:=item.val is NA ? "inputNA" : (item.val == null ? "externalNull" : "ok")
      quality:=item.val is NA ? "na" : (item.val == null ? (cfg?.has("defNull") == true ? "filtered" : "missing") : "cleaned")
      result.details.add(["ts":end.toIso,"value":number(item.val),"valueType":valueType(item.val),"reason":reason,"quality":quality,"substituted":false,"emitted":true,"intervalSeconds":interval == null ? null : interval.ticks.toFloat/1sec.ticks.toFloat])
    }
    result.summary=["pointId":point.id.id,"externalFunctionManaged":true,"function":point["hisFunc"],"sourceIds":[point.id.id],"parameters":cfg == null ? null : EnerCubixCleaning.jsonConfig(cfg)]
    return result
  }

  private static Str detailQuality(Str:Obj? d)
  {
    if (d["valueType"] == "na") return "na"
    if (d["quality"] is Str) return d["quality"]
    if (d["substituted"] == true) return "substituted"
    if (d["value"] == null) return ["inputNull","previousNull","nonPositiveInterval"].contains(d["reason"]) ? "missing" : "filtered"
    return d["reason"] == "rollover" ? "corrected" : "cleaned"
  }

  internal static Str:Obj? normalizeClean(Dict point, EnerCubixCleanResult result, DateTime from, DateTime to, Bool trend := false)
  {
    hours:=Int:EnerCubixCleanHour[:]
    details:=result.details.findAll |d| { d["emitted"] != false && d["intervalSeconds"] != null }
    selected:=[Str:Obj?][,]
    details.each |d|
    {
      end:=DateTime.fromIso(d["ts"].toStr).toTimeZone(from.tz)
      seconds:=EnerCubixMath.num(d["intervalSeconds"]) ?: 0f
      if (seconds <= 0f) return
      start:=end-Duration((seconds*1sec.ticks.toFloat).toInt)
      if (end <= from || start >= to) return
      selected.add(d)
      at:=EnerCubixMath.floorHour(start)
      while (at < end)
      {
        if (at >= from && at < to)
        {
          if (!hours.containsKey(at.ticks)) hours[at.ticks]=EnerCubixCleanHour()
          acc:=hours[at.ticks]
          if (start < at || end > at+1hr) acc.missing=true
          else
          {
            acc.covered+=(end-start).ticks
            q:=detailQuality(d)
            if (q == "missing") acc.missing=true
            acc.values.add(EnerCubixValue(EnerCubixMath.num(d["value"]),q))
            if (EnerCubixMath.num(d["value"]) != null && d["substituted"] != true && q != "filtered") acc.valid+=(end-start).ticks
          }
        }
        at+=1hr
      }
    }
    samples:=[Str:Obj?][,]; cursor:=from; validTicks:=0
    while (cursor < to)
    {
      acc:=hours[cursor.ticks]
      v:=acc == null || acc.missing || acc.covered != 1hr.ticks ? EnerCubixValue(null,"missing") : EnerCubixValue.sum(acc.values)
      if (acc != null) validTicks+=acc.valid
      samples.add(v.point(cursor)); cursor+=1hr
    }
    meta:=result.summary.dup
    meta["summary"]=["filteredCount":selected.findAll |d| { detailQuality(d) == "filtered" }.size,"substitutedCount":selected.findAll |d| { d["substituted"] == true }.size,"naCount":selected.findAll |d| { d["valueType"] == "na" }.size,"intervalCount":selected.size,"coverage":(validTicks.toFloat/(to-from).ticks.toFloat).min(1f)]
    meta["inputCount"]=result.rawItems.findAll |i| { i.ts >= from && i.ts < to }.size
    meta["outputCount"]=selected.size
    meta["validCount"]=selected.findAll |d| { EnerCubixMath.num(d["value"]) != null }.size
    meta["nullCount"]=selected.findAll |d| { d["valueType"] == "null" }.size
    meta["naCount"]=selected.findAll |d| { d["valueType"] == "na" }.size
    meta.setAll(cleaningEvidence(point,result,from,to))
    if (trend)
    {
      visible:=point["hisMode"] == "consumption" || point["hisFunc"] == "enerCubixCleanHis" ? nativeItems(result) : result.items
      samples=visible.findAll |i| { i.ts >= from && i.ts < to }.map |i->[Str:Obj?]| { ["ts":i.ts.toTimeZone(from.tz).toIso,"value":number(i.val),"valueType":valueType(i.val)] }
    }
    raw:=result.rawItems.map |i->[Str:Obj?]| { ["ts":i.ts.toTimeZone(from.tz).toIso,"value":number(i.val),"valueType":valueType(i.val)] }
    intervals:=selected.map |detail->[Str:Obj?]|
    {
      end:=DateTime.fromIso(detail["ts"].toStr).toTimeZone(from.tz)
      seconds:=EnerCubixMath.num(detail["intervalSeconds"]) ?: 0f
      start:=end-Duration((seconds*1sec.ticks.toFloat).toInt)
      return ["from":start.toIso,"to":end.toIso,"value":detail["value"],"valueType":detail["valueType"],"quality":detailQuality(detail)]
    }
    return ["pointId":point.id.id,"unit":point["unit"]?.toStr ?: "","mode":"interval","quality":"cleaned","rawQuality":"ok","samples":samples,"rawSamples":trend ? samples : raw,"intervals":intervals,"sourceIds":result.summary["sourceIds"] ?: [point.id.id],"cleaning":meta]
  }

  private static Str:Obj? unavailable(Str id, Str quality)
  { ["pointId":id,"mode":"sampled","quality":quality,"samples":[Str:Obj?][,]] }

  private static Float? number(Obj? value)
  {
    if (value is Number) return EnerCubixMath.num(((Number)value).toFloat)
    if (value is Bool) return value == true ? 1f : 0f
    return EnerCubixMath.num(value)
  }

  private static Duration? cadence(Dict point, HisItem[] items)
  {
    for (i:=0;i<2;i++)
    {
      v:=point[["hisCollectInterval","hisInterval"][i]]
      if (v is Duration && ((Duration)v).ticks > 0) return v
      if (v is Number)
      {
        duration:=((Number)v).toDuration(false)
        if (duration != null && duration.ticks > 0) return duration
      }
    }
    deltas:=Int[,]
    for (i:=1;i<items.size;i++)
    {
      delta:=(items[i].ts-items[i-1].ts).ticks
      if (delta > 0) deltas.add(delta)
    }
    // A repeated shortest interval is evidence of cadence; a single gap is not.
    if (deltas.size < 2) return null
    smallest:=deltas.min
    if (deltas.findAll |d| { d == smallest }.size < 2) return null
    if (deltas.any |d| { d % smallest != 0 }) return null
    return Duration(smallest)
  }

  private static Str:Obj? dependencies(Str:Obj? request, [Str:Obj?][] records)
  {
    if (EnerCubixDimension.active(request)) return EnerCubixDimension.dependencies(request,records)
    ctx:=EnerCubixContext(records,[Str:Obj?][,],TimeZone.utc)
    selected:=EnerCubixMath.strings(request["nodeIds"])
    if (request["kind"] == "utility")
    {
      meters:=EnerCubixEndUse.resolve(ctx,selected)
      points:=meters.map |r->Str| {r["pointId"] as Str ?: ""}
      return ["points":points.findAll |Str id->Bool| {!id.isEmpty}.unique,"nodes":meters.map |r->Str| {r["id"].toStr}]
    }
    if (selected.isEmpty && request["kind"] == "dashboard")
    {
      selected=records.findAll |r| { r["kind"] == "group" && r["parentId"] == null }.map |r->Str| { r["id"].toStr }
      if (selected.isEmpty) selected=records.findAll |r| { ctx.included(r) && r["parentId"] == null }.map |r->Str| { r["id"].toStr }
    }
    selected=selected.dup.addAll(EnerCubixMath.strings(request["referenceIds"]))
    ["xId","yId"].each |key| { if (request[key] != null) selected.add(request[key].toStr) }
    points:=Str[,]; nodes:=Str[,]
    selected.each |id| { collect(ctx,id,points,nodes,request["kind"] == "trend") }
    return ["points":points.unique,"nodes":nodes.unique]
  }

  private static Void collect(EnerCubixContext ctx, Str id, Str[] points, Str[] nodes, Bool trend)
  {
    if (nodes.contains(id)) return
    nodes.add(id)
    r:=ctx.byId[id]
    if (r == null) { if (ctx.byId.vals.any |row| {row["pointId"] == id}) points.add(id); return }
    if (r["kind"] == "nativePoint") return
    if (r["pointId"] != null && !r["pointId"].toStr.isEmpty) points.add(r["pointId"].toStr)
    if (r["kind"] == "group")
    {
      (ctx.children[id] ?: [Str:Obj?][,]).each |child|
      {
        if (ctx.included(child) || (trend && child["kind"] == "sensor")) collect(ctx,child["id"].toStr,points,nodes,trend)
      }
    }
    if (r["kind"] == "cop") ["numeratorId","denominatorId"].each |key| { if (r[key] != null) collect(ctx,r[key].toStr,points,nodes,trend) }

  }
}

internal class EnerCubixHourAccumulator
{
  Float value := 0f
  Int covered := 0
  Bool invalid := false
}

internal class EnerCubixCleanHour
{
  Int covered := 0
  Int valid := 0
  Bool missing := false
  EnerCubixValue[] values := [,]
}


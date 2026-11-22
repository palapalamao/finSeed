using haystack
using skyarcd

** Read-only native FIN history adapter; all arithmetic remains in FinEnergyEngine.
class FinEnergyHistory
{
  internal static Str:Obj? report(Str:Obj? request, [Str:Obj?][] records, [Str:Obj?][] histories)
  {
    result:=FinEnergyEngine.report(request,records,histories)
    if(request["_profileFirst"]!=true) result=evidence(result,histories)
    if (request["_cockpitCategoryId"] != null)
    {
      // Report arithmetic and coverage already used every source interval.
      // Cockpit ships bounded diagnostic evidence, never a truncated total.
      extra:=(Map)result["extra"]
      known:=extra["knownUsage"] as Map
      if (known != null)
      {
        rows:=FinEnergyMath.maps(known["sourceUsage"])
        if (rows.size > 1000)
        {
          if(known["sourceUsageTruncated"] != true) known["sourceUsageRowCount"]=rows.size
          if(known["sourceUsageCaptureId"] == null) known["sourceUsageCaptureId"]=Uuid().toStr
          known["sourceUsageTruncated"]=true
          known["sourceUsage"]=rows[0..<1000]
          known["detailsTruncated"]=true
          known["truncationReason"]="cockpitEvidenceRowLimit"
        }
      }
    }
    result["edition"]=FinEnergyEditionLicense.edition
    result["licenseMode"]=FinEnergyEditionLicense.licenseMode
    return result
  }

  private static Str:Obj? evidence(Str:Obj? report, [Str:Obj?][] histories)
  {
    Str:Obj? extra:=report["extra"] as Map ?: Str:Obj?[:]
    extra["cleaning"]=histories.findAll |h| { h["cleaning"] != null }.map |h->[Str:Obj?]| { ((Str:Obj?)h["cleaning"]).dup.set("pointId",h["pointId"]).set("sourceIds",h["sourceIds"] ?: [h["pointId"]]) }
    report["extra"]=extra
    return report
  }

  ** Freeze every planned primary point and its cleaning config before any history read.
  internal static FinEnergyCockpitSourceSession sourceSession(Context cx,Str:Obj? request,[Str:Obj?][] records,FinEnergyStreamBudget budget,FinEnergyCockpitRequestScope? scope := null)
  {
    scope?.checkContext(cx.proj.name,cx.user.username)
    return FinEnergyCockpitSourceSession.prepare(request,records,budget,
      |Str id->Dict?| {cx.db.readById(Ref(id),false)},|Dict p->Bool| {cx.canRead(p)},
      |Dict p->Dict| {FinEnergyCleaningRepo(FinEnergyRepo(cx)).currentConfig(p)},
      |Dict p,Span span,|HisItem| sink|
      {
        options:=FinEnergyPreparedOwner(budget.state)
        try {options.hold(3);cx.rt.his.read(p,span,Etc.makeDict(["raw":Marker.val]),sink)}
        finally {options.close}
      },scope,|Dict p,FinEnergyPreparedOwner work->Dict| {FinEnergyCleaningRepo(FinEnergyRepo(cx)).currentConfigOwned(p,work)})
  }

  ** Freeze every planned primary point and its cleaning config before any history read.
  internal static [Str:Obj?][] loadPrepared(Context cx, Str:Obj? request, [Str:Obj?][] records,FinEnergyStreamBudget? budget := null)
  {
    prepared:=prepareConfiguration(request,records,|Str id->Dict?| {cx.db.readById(Ref(id),false)},|Dict p->Bool| {cx.canRead(p)},|Dict p->Dict| {FinEnergyCleaningRepo(FinEnergyRepo(cx)).currentConfig(p)})
    points:=(Str:Dict?)prepared["points"]; configs:=(Str:Dict)prepared["configs"]
    out:=FinEnergyCockpitStream.load(cx,request,records,points,configs,budget)
    refs:=(Str:[Str:Obj?][])prepared["configRefs"]
    out.each |h|
    {
      h["configRefs"]=refs[h["pointId"].toStr]
      h["historyConfigObservedFrom"]=prepared["observedFrom"]
      h["historyConfigObservedTo"]=prepared["observedTo"]
    }
    return out
  }

  ** Pure lookup seam for checking preparation without a live FIN context.
  internal static Str:Obj? prepareConfiguration(Str:Obj? request, [Str:Obj?][] records,
    |Str->Dict?| read, |Dict->Bool| readable, |Dict->Dict| currentConfig,FinEnergyPreparedOwner? work := null)
  {
    work?.hold(16+records.size+((request["_cockpitPointIds"] as List)?.size ?: 0))
    observedFrom:=DateTime.now
    points:=Str:Dict?[:]; configs:=Str:Dict[:]
    work?.watch |->Void| {points.clear;configs.clear}
    ids:=FinEnergyMath.strings(request["_cockpitPointIds"])
    owners:=records.findAll |r| {r["nativeEquip"] == true && ids.contains(r["pointId"] as Str ?: "")}
    guards:=Str:Dict?[:]
    work?.watch |->Void| {ids.clear;owners.clear;guards.clear}
    // Flow formulas and current scope/relationship revisions participate in the
    // same freeze as primary bindings, before the first native history block.
    work?.hold(1+((request["_cockpitConfigIds"] as List)?.size ?: 0))
    configIds:=FinEnergyMath.strings(request["_cockpitConfigIds"])
    work?.watch |->Void| {configIds.clear}
    configIds.each |id|
    {
      expected:=records.find |r| {r["id"] == id}
      if (expected == null) configurationChanged
      source:=expected["nativeSourceId"] as Str ?: id
      actual:=read(source)
      if (actual != null && !readable(actual)) throw FinEnergyHttpErr(403,"PERMISSION","cockpitScopeForbidden")
      if (actual == null || FinEnergyRepo.iso(actual["mod"]) != expected["mod"]) configurationChanged
      if(!guards.containsKey(source)) work?.hold(1)
      guards[source]=actual
    }
    owners.each |owner|
    {
      id:=owner["id"].toStr
      actual:=read(id)
      if (actual != null && !readable(actual)) throw FinEnergyHttpErr(403,"PERMISSION","cockpitScopeForbidden")
      if (actual == null || FinEnergyRepo.iso(actual["mod"]) != owner["mod"]) configurationChanged
      work?.hold(11+FinEnergyRepo.refTags.size+FinEnergyNativeEquip.scalars.size)
      decoded:=FinEnergyNativeEquip.decode(actual)
      work?.watch |->Void| {decoded.clear}
      if (["pointId","cleaningEnabled","cleaningProfileId","historyMode"].any |key| {decoded[key] != owner[key]}) configurationChanged
      if(!guards.containsKey(id)) work?.hold(1)
      guards[id]=actual
      if (owner["cleaningEnabled"] != true) return
      profileId:=owner["cleaningProfileId"] as Str ?: ""
      profile:=records.find |r| {r["id"] == profileId && r["kind"] == "cleaningProfile"}
      current:=profileId.isEmpty ? null : read(profileId)
      if (current != null && !readable(current)) throw FinEnergyHttpErr(403,"PERMISSION","cockpitScopeForbidden")
      if (profile == null || current == null || FinEnergyRepo.iso(current["mod"]) != profile["mod"]) configurationChanged
      if(!guards.containsKey(profileId)) work?.hold(1)
      guards[profileId]=current
    }
    ids.each |id|
    {
      point:=read(id)
      // Opaque permission failure: no point ID/name is returned to this caller.
      if (point != null && !readable(point)) throw FinEnergyHttpErr(403,"PERMISSION","cockpitScopeForbidden")
      work?.hold(1)
      points[id]=point
      if(!guards.containsKey(id)) work?.hold(1)
      guards[id]=point
      work?.hold(1+owners.size)
      own:=owners.findAll |r| {r["pointId"] == id}
      work?.watch |->Void| {own.clear}
      if (point != null) own.each |owner|
      {
        if ((point["equipRef"] as Ref)?.id != owner["id"]) configurationChanged
        managed:=FinEnergyCleaningRepo.managed(point)
        if ((owner["cleaningEnabled"] == true) != managed) configurationChanged
        if (!managed) return
        profile:=records.find |r| {r["id"] == owner["cleaningProfileId"] && r["kind"] == "cleaningProfile"}
        work?.hold(64+16*((profile["parameters"] as Map)?.size ?: 0))
        expected:=FinEnergyCleaningRepo.configFor(profile,point)
        actual:=point["hisFuncConfig"] as Dict
        work?.hold(80+8*(configurationSize(expected)+configurationSize(actual)))
        if ((point["finEnergyCleaningProfileRef"] as Ref)?.id != profile["id"] || point["finEnergyCleaningProfileVersion"] != expected["finEnergyProfileVersion"] || actual == null || !sameCleaningConfiguration(actual,expected)) configurationChanged
      }
      if (point?.get("hisFunc") == "finEnergyCleanHis")
      {
        if(!configs.containsKey(id)) work?.hold(1)
        try { configs[id]=point.has("finEnergyCleaningOwned") ? currentConfig(point) : (point["hisFuncConfig"] as Dict ?: Etc.emptyDict) }
        catch (FinEnergyHttpErr e) {throw e}
        catch (Err e) { configs[id]=Etc.emptyDict }
        if (point.has("finEnergyCleaningOwned") && !configs[id].isEmpty)
        {
          actual:=point["hisFuncConfig"] as Dict
          work?.hold(80+8*(configurationSize(configs[id])+configurationSize(actual)))
          if (actual == null || !sameCleaningConfiguration(configs[id],actual)) configurationChanged
        }
      }
    }
    // A final guard closes edits during sequential point freezing. No history has
    // been read yet; after this boundary the frozen rules remain authoritative.
    guards.each |before,id|
    {
      after:=read(id)
      if (after != null && !readable(after)) throw FinEnergyHttpErr(403,"PERMISSION","cockpitScopeForbidden")
      if ((before == null) != (after == null) || (before != null && before["mod"] != after?.get("mod"))) configurationChanged
    }
    work?.hold(1+points.size)
    refs:=Str:[Str:Obj?][][:]
    work?.watch |->Void| {refs.each |list| {list.each |ref| {ref.clear};list.clear};refs.clear}
    points.each |point,id|
    {
      work?.hold(1)
      list:=[Str:Obj?][,]
      if(point!=null) work?.hold(4)
      if (point != null) list.add(["id":id,"mod":FinEnergyRepo.iso(point["mod"])])
      profileId:=(configs[id]?.get("finEnergyProfileRef") as Ref)?.id
      profile:=profileId == null ? null : guards[profileId]
      if (profile != null) {work?.hold(4);list.add(["id":profileId,"mod":FinEnergyRepo.iso(profile["mod"])])}
      refs[id]=list
    }
    work?.hold(6)
    return ["points":points,"configs":configs,"configRefs":refs,"observedFrom":observedFrom.toIso,"observedTo":DateTime.now.toIso]
  }

  private static Bool sameCleaningConfiguration(Dict a, Dict b)
  {
    return (a["finEnergyProfileRef"] as Ref)?.id == (b["finEnergyProfileRef"] as Ref)?.id && a["finEnergyProfileVersion"] == b["finEnergyProfileVersion"] && a["finEnergyMode"] == b["finEnergyMode"] && FinEnergyCleaning.jsonConfig(a) == FinEnergyCleaning.jsonConfig(b)
  }

  internal static Int configurationSize(Dict? config)
  {n:=0;config?.each |v,k| {n++};return n}

  private static Void configurationChanged()
  {throw FinEnergyHttpErr(409,"CONFIGURATION_CHANGED","cockpitConfigurationChanged")}

  static [Str:Obj?][] load(Context cx, Str:Obj? request, [Str:Obj?][] records, [Str:Dict?]? frozenPoints := null, [Str:Dict]? frozenConfigs := null,[Str:Int]? timing := null)
  {
    plan:=range(request,records)
    from:=(DateTime)plan["from"]; to:=(DateTime)plan["to"]
    out:=[Str:Obj?][,]
    modeRecords:=FinEnergyDimension.active(request) ? FinEnergyDimension(request["dimension"].toStr,records,request["spaceSource"] == "fin").records : records
    ids:=frozenPoints == null ? pointIds(request,records) : frozenPoints.keys
    guard:=request["_reportDeadline"] as FinEnergyCockpitDeadline
    addTiming(timing,"plannedPoints",ids.size)
    ids.each |id|
    {
      Dict? point:=null
      try
      {
        guard?.check
        point=frozenPoints == null ? cx.db.readById(Ref(id),false) : frozenPoints[id]
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
          reading:=Duration.nowTicks
          try
          {
          cx.rt.his.read(point,span,Etc.makeDict(["raw":Marker.val])) |HisItem item|
          {
            if (items.size >= 1000000) throw ArgErr("History exceeds 1000000 raw samples")
            if(items.size%2048==0) guard?.check
            items.add(item)
          }
          }
          finally {addTiming(timing,"nativeReadNs",Duration.nowTicks-reading);addTiming(timing,"rawRows",items.size);addTiming(timing,"nativeReads",1)}
          normalizing:=Duration.nowTicks
          out.add(normalize(point,items,from,to,true))
          addTiming(timing,"normalizeNs",Duration.nowTicks-normalizing)
          return
        }
        overrides:=modeRecords.findAll |r| { r["pointId"] == id && r["historyMode"] != null && r["historyMode"] != "auto" }.map |r->Str| { r["historyMode"].toStr }.unique
        if (overrides.size > 1) throw ArgErr("Conflicting FinEnergy history modes")
        if (point["hisFunc"] == "finEnergyCleanHis" && request["raw"] != true)
        {
          config:=frozenConfigs?.get(id)
          if (frozenConfigs != null && (config == null || config.isEmpty)) throw ArgErr("missingCleaningProfile")
          result:=cleanRead(cx,point,span,config == null ? Etc.emptyDict : Etc.makeDict(["finEnergyCleaningPreview":Marker.val]),config ?: Etc.emptyDict,timing,guard)
          normalizing:=Duration.nowTicks
          cockpit:=request.keys.any |key| {key.startsWith("_cockpit")}
          rawView:=request["kind"]=="regression" || !FinEnergyMath.strings(request["referenceIds"]).isEmpty
          out.add(request["_profileFirst"]==true ? normalizeChartClean(point,result,from,to) :
            (cockpit ? normalizeClean(point,result,from,to) : normalizeFullClean(point,result,from,to,rawView)))
          addTiming(timing,"normalizeNs",Duration.nowTicks-normalizing)
          return
        }
        reading:=Duration.nowTicks
        try
        {
        cx.rt.his.read(point,span,request["raw"] == true ? Etc.makeDict(["raw":Marker.val]) : readOptions(point)) |HisItem item|
        {
          if (items.size >= 1000000) throw ArgErr("History exceeds 1000000 raw samples")
          if(items.size%2048==0) guard?.check
          items.add(item)
        }
        }
        finally {addTiming(timing,"nativeReadNs",Duration.nowTicks-reading);addTiming(timing,"rawRows",items.size);addTiming(timing,"nativeReads",1)}
        mode:=outputMode(point,overrides.first,true)
        normalizing:=Duration.nowTicks
        normalized:=normalize(point,items,from,to,request["kind"] == "trend",mode)
        if(request["_profileFirst"]==true) normalized.remove("rawSamples")
        out.add(normalized)
        addTiming(timing,"normalizeNs",Duration.nowTicks-normalizing)
      }
      catch (ArgErr e)
      {
        code:=frozenPoints != null && e.msg.startsWith("History exceeds ") ? "historySampleLimit" : (["missingSource","missingCleaningProfile","duplicateSource","cycle","incompatibleCategory","incompatibleUnit","missingBranches"].contains(e.msg) ? e.msg : "invalidCleaningConfiguration")
        failed:=unavailable(id,code); failed["error"]=e.msg; out.add(failed)
      }
      catch (Err e) { guard?.check;out.add(unavailable(id,"historyReadError")) }
    }
    return out
  }

  ** Generation never rewrites legacy raw history. A crossing query combines
  ** only complete pre-cutover own intervals with published post-cutover data.
  internal static Str:Obj? mergePublished(Str:Obj? legacy, Str:Obj? published, DateTime cutover)
  {
    rows:=FinEnergyMath.maps(legacy["intervals"]).findAll |row| { DateTime.fromIso(row["to"].toStr) <= cutover }
    out:=published.dup
    out["intervals"]=rows.dup.addAll(FinEnergyMath.maps(published["intervals"]))
    out["mode"]="interval"
    out["rawSamples"]=legacy["rawSamples"]
    if (legacy["cleaning"] != null) out["cleaning"]=legacy["cleaning"]
    return out
  }

  internal static Str[] pointIds(Str:Obj? request, [Str:Obj?][] records)
  {
    if(request["_profileFirst"]==true) return FinEnergyProfileFirst.pointIds(request,records)
    plan:=dependencies(request,records)
    return ((Str[])plan["points"]).dup.addAll(FinEnergyReferenceCurves.pointIds(request,records)).unique.sort
  }

  ** Non-energy references remain available, but energy histories require a device binding.
  internal static Bool primaryReadAllowed(Dict point, [Str:Obj?][] records)
  {
    if (point.has("finEnergyComputed")) return false
    if (records.any |r| {["meter","totalMeter","sensor"].contains(r["kind"]) && r["pointId"] == point.id.id}) return true
    unit:=point["unit"] as Str ?: ""
    return !records.any |r| {r["kind"] == "category" && FinEnergyMath.unitFactor(unit,r["unit"] as Str ?: "") != null}
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
      ctx:=FinEnergyContext(records,[Str:Obj?][,],tz)
      records.each |r|
      {
        if (!nodes.contains(r["id"]?.toStr ?: "")) return
        tariff:=ctx.tariff(r)
        mode:=tariff?.get("mode")?.toStr
        if (mode == "yearlyBlock") from=FinEnergyMath.bucket(from,"year")
        else if (mode == "monthlyBlock") from=FinEnergyMath.bucket(from,"month")
      }
    }
    from=FinEnergyMath.floorHour(from)
    end:=FinEnergyMath.floorHour(to); if (end < to) end+=1hr
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
    hours:=Int:FinEnergyHourAccumulator[:]
    sorted.each |item|
    {
      end:=item.ts.toTimeZone(from.tz); start:=end-interval
      if (end <= from || start >= to) return
      at:=FinEnergyMath.floorHour(start)
      v:=number(item.val)
      while (at < end)
      {
        finish:=at+1hr
        left:=start > at ? start : at; right:=end < finish ? end : finish
        if (right > left && at >= from && at < to)
        {
          if (!hours.containsKey(at.ticks)) hours[at.ticks]=FinEnergyHourAccumulator()
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
  internal static FinEnergyCleanResult cleanRead(Context cx, Dict point, Span span, Dict opts, Dict config,[Str:Int]? timing := null,FinEnergyCockpitDeadline? guard := null)
  {
    if (!cx.canRead(point)) throw ArgErr("forbidden")
    return cleanStored(cx,point,span,opts,config,timing,guard)
  }

  private static FinEnergyCleanResult cleanStored(Context cx, Dict point, Span span, Dict opts, Dict config,[Str:Int]? timing := null,FinEnergyCockpitDeadline? guard := null)
  {
    if (!cx.canRead(point)) throw ArgErr("forbidden")
    if (!opts.has("finEnergyCleaningPreview") || config.isEmpty)
    {
      defaults:=point["hisFuncConfig"] as Dict ?: Etc.emptyDict
      if (point.has("finEnergyCleaningOwned"))
      {
        stored:=cx.db.readById(point.id,false) ?: throw ArgErr("missingSource")
        defaults=FinEnergyCleaningRepo(FinEnergyRepo(cx)).currentConfig(stored)
      }
      config=selectConfig(defaults,config)
    }
    if (config.isEmpty) throw ArgErr("missingCleaningProfile")
    raw:=storedRaw(cx,point,span,timing,guard)
    started:=Duration.nowTicks
    answer:=FinEnergyCleaning.clean(point,raw,config)
    guard?.check
    addTiming(timing,"cleanNs",Duration.nowTicks-started)
    answer.summary["sourceIds"]=[point.id.id]
    answer.summary["pointId"]=point.id.id
    answer.summary["profileId"]=(config["finEnergyProfileRef"] as Ref)?.id
    answer.summary["profileVersion"]=(config["finEnergyProfileVersion"] as Number)?.toInt
    answer.summary["parameters"]=FinEnergyCleaning.jsonConfig(config)
    return answer
  }

  private static HisItem[] storedRaw(Context cx, Dict point, Span span,[Str:Int]? timing := null,FinEnergyCockpitDeadline? guard := null)
  {
    raw:=HisItem[,]
    started:=Duration.nowTicks
    try
    {
    cx.rt.his.read(point,span,Etc.makeDict(["raw":Marker.val])) |item|
    {
      if (raw.size >= 1000000) throw ArgErr("History exceeds 1000000 raw samples")
      if(raw.size%2048==0) guard?.check
      raw.add(item)
    }
    }
    finally {addTiming(timing,"nativeReadNs",Duration.nowTicks-started);addTiming(timing,"rawRows",raw.size);addTiming(timing,"nativeReads",1)}
    return raw
  }

  private static Void addTiming([Str:Int]? timing,Str key,Int amount)
  {if(timing!=null) timing[key]=(timing[key] ?: 0)+amount}

  ** Native consumption functions expose already-published own intervals
  ** directly; differencing them again would turn consumption into a counter.
  internal static FinEnergyCleanResult publishedResult(Dict point, Str:Obj? published, FinEnergyCleanResult? legacy := null)
  {
    cutover:=DateTime.fromIso(published["cutover"].toStr)
    result:=FinEnergyCleanResult()
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
    FinEnergyMath.maps(published["intervals"]).each |row|
    {
      start:=DateTime.fromIso(row["from"].toStr); end:=DateTime.fromIso(row["to"].toStr)
      if (start < cutover || end <= start) return
      number:=FinEnergyMath.num(row["value"])
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

  internal static FinEnergyCleanResult sumClean(Dict point, FinEnergyCleanResult[] parts, Str[] units)
  {
    result:=FinEnergyCleanResult(); times:=Int:DateTime[:]; indices:=Str:[Str:Obj?][:]
    parts.each |part,i|
    {
      // Nested totals already carry leaf events; do not recount their aggregate
      // intervals or deduplicate distinct sources that share the same timestamp.
      id:=(part.summary["pointId"] as Str) ?: (FinEnergyMath.strings(part.summary["sourceIds"]).first ?: "")
      result.sourceDetails.addAll(interventions(part,id,units[i]))
      part.details.findAll |d| { d["emitted"] != false && d["intervalSeconds"] != null }.each |d|
      {
        at:=DateTime.fromIso(d["ts"].toStr); times[at.ticks]=at; indices["$i|${at.ticks}"]=d
      }
    }
    unit:=point["unit"]?.toStr ?: ""
    times.keys.sort.each |ticks|
    {
      values:=FinEnergyValue[,]; seconds:=Float?[,]; reason:="ok"
      parts.each |part,i|
      {
        d:=indices["$i|$ticks"]
        if (d == null) { reason="unalignedSources"; values.add(FinEnergyValue()); return }
        seconds.add(FinEnergyMath.num(d["intervalSeconds"]))
        factor:=FinEnergyMath.unitFactor(units[i],unit) ?: throw ArgErr("incompatibleUnit")
        values.add(FinEnergyValue(FinEnergyMath.num(d["value"]),detailQuality(d)).scale(factor))
      }
      if (seconds.unique.size != 1 || seconds.size != parts.size) reason="unalignedSources"
      sum:=FinEnergyValue.sum(values)
      if (reason != "ok") sum=FinEnergyValue(null,"missing")
      val:=sum.quality == "na" ? NA.val : (sum.value == null ? null : Number(sum.value,Unit.fromStr(unit,false)))
      result.items.add(HisItem(times[ticks],val))
      result.details.add(["ts":times[ticks].toIso,"value":sum.value,"valueType":sum.valueType,"quality":sum.quality,"reason":reason,"substituted":sum.quality == "substituted","intervalSeconds":seconds.first,"emitted":true])
    }
    result.summary["pointId"]=point.id.id
    result.summary["sourceIds"]=parts.map |p->Str[]| { FinEnergyMath.strings(p.summary["sourceIds"]) }.flatten.unique
    result.summary["sources"]=parts.map |p->[Str:Obj?]| { p.summary.dup }
    ["inputCount","outputCount","validCount","nullCount","naCount","substitutedCount","removedNACount","rejectedCount","rolloverCount"].each |key|
    {
      n:=0f; parts.each |p| { n+=FinEnergyMath.num(p.summary[key]) ?: 0f }; result.summary[key]=n.toInt
    }
    return result
  }

  private static [Str:Obj?][] interventions(FinEnergyCleanResult result, Str id, Str unit)
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
    seconds:=FinEnergyMath.num(event["intervalSeconds"]) ?: 0f
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
      ids:=FinEnergyMath.strings(source["sourceIds"])
      scoped:=source.dup.setAll(processingCounts(events.findAll |e| { ids.contains(e["pointId"]) }))
      if (source["sources"] is List) scoped["sources"]=scopedSources(FinEnergyMath.maps(source["sources"]),events)
      return scoped
    }
  }

  ** Shared report/preview provenance. Counts use all selected leaf events before
  ** diagnostics are capped; output counts and coverage still describe this object.
  internal static Str:Obj? cleaningEvidence(Dict point, FinEnergyCleanResult result, DateTime from, DateTime to)
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
    if (derived) meta["sources"]=scopedSources(FinEnergyMath.maps(result.summary["sources"]),events)
    return meta
  }

  ** The arithmetic core retains end-stamped intervals. FIN consumption functions
  ** expose their starts; translate only at the native boundary, never twice.
  internal static HisItem[] nativeItems(FinEnergyCleanResult result)
  {
    seconds:=Int:Float[:]
    result.details.each |d|
    {
      duration:=FinEnergyMath.num(d["intervalSeconds"])
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
    out:=detail.dup; seconds:=FinEnergyMath.num(detail["intervalSeconds"])
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
    if (merged.containsKey("finEnergyMode")) merged["finEnergyMode"]=merged.containsKey("defNull") ? "drop" : (merged.containsKey("defVal") ? "replace" : "rollover")
    return Etc.makeDict(merged)
  }

  internal static FinEnergyCleanResult externalResult(Dict point, HisItem[] items)
  {
    result:=FinEnergyCleanResult()
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
    result.summary=["pointId":point.id.id,"externalFunctionManaged":true,"function":point["hisFunc"],"sourceIds":[point.id.id],"parameters":cfg == null ? null : FinEnergyCleaning.jsonConfig(cfg)]
    return result
  }

  internal static Str detailQuality(Str:Obj? d)
  {detailQualityFields(d["valueType"],d["quality"],d["substituted"]==true,d["value"],d["reason"])}

  ** Shared quality precedence for a scalar transition and its diagnostic DTO.
  internal static Str detailQualityFields(Obj? valueType,Obj? explicitQuality,Bool substituted,Obj? value,Obj? reason)
  {
    if(valueType=="na") return "na"
    if(explicitQuality is Str) return explicitQuality
    if(substituted) return "substituted"
    if(value==null) return ["inputNull","previousNull","nonPositiveInterval"].contains(reason) ? "missing" : "filtered"
    return reason=="rollover" ? "corrected" : "cleaned"
  }

  ** Complete ordinary reports read authoritative intervals. Dense synthetic
  ** hourly samples are not an additional source of truth. Preserve all public
  ** cleaning evidence and keep raw observations for reference/regression views.
  ** The legacy helper remains available to raw/native/cockpit consumers.
  internal static Str:Obj? normalizeFullClean(Dict point, FinEnergyCleanResult result, DateTime from, DateTime to, Bool rawView := false)
  {
    // load.range aligns the start. Keep the more general helper's historical
    // cursor-based summary behavior if this seam is called with a partial hour.
    if(from!=FinEnergyMath.floorHour(from)) return normalizeClean(point,result,from,to)
    intervals:=FinEnergyInterval[,]
    filtered:=0; substituted:=0; na:=0; valid:=0; nulls:=0; validTicks:=0; selected:=0
    result.details.each |d|
    {
      if(d["emitted"]==false || d["intervalSeconds"]==null) return
      seconds:=FinEnergyMath.num(d["intervalSeconds"]) ?: 0f
      if(seconds<=0f) return
      end:=DateTime.fromIso(d["ts"].toStr).toTimeZone(from.tz)
      start:=end-Duration((seconds*1sec.ticks.toFloat).toInt)
      if(end<=from || start>=to) return
      q:=detailQuality(d); number:=FinEnergyMath.num(d["value"])
      // Match the legacy Map reader's serialization boundary once. In particular
      // native SDK offset-zone parsing is observable for fractional-hour DST;
      // retaining a project-zone DateTime directly would change that behavior.
      intervals.add(FinEnergyInterval(DateTime.fromIso(start.toIso),DateTime.fromIso(end.toIso),number,q,d["valueType"] as Str ?: (number==null ? "null" : "number")))
      selected++
      if(q=="filtered") filtered++
      if(d["substituted"]==true) substituted++
      if(d["valueType"]=="na") na++
      if(d["valueType"]=="null") nulls++
      if(number!=null) valid++
      hour:=FinEnergyMath.floorHour(start)
      // Exactly the original summary accumulator condition. Crossing segments
      // do not add coverage; another valid short segment in that hour still can.
      if(hour>=from && hour<to && (hour-from).ticks % 1hr.ticks==0 && end<=hour+1hr && number!=null && d["substituted"]!=true && q!="filtered")
        validTicks+=(end-start).ticks
    }
    meta:=result.summary.dup
    meta["summary"]=["filteredCount":filtered,"substitutedCount":substituted,"naCount":na,"intervalCount":selected,"coverage":(validTicks.toFloat/(to-from).ticks.toFloat).min(1f)]
    inputCount:=0
    result.rawItems.each |item| {if(item.ts>=from && item.ts<to) inputCount++}
    meta["inputCount"]=inputCount;meta["outputCount"]=selected
    meta["validCount"]=valid;meta["nullCount"]=nulls;meta["naCount"]=na
    meta.setAll(cleaningEvidence(point,result,from,to))
    out:=Str:Obj?["pointId":point.id.id,"unit":point["unit"]?.toStr ?: "","mode":"interval","quality":"cleaned","rawQuality":"ok","samples":[Str:Obj?][,],"_closedIntervals":FinEnergyClosedIntervals(intervals),"sourceIds":result.summary["sourceIds"] ?: [point.id.id],"cleaning":meta]
    if(rawView) out["rawSamples"]=result.rawItems.map |item->[Str:Obj?]| { ["ts":item.ts.toTimeZone(from.tz).toIso,"value":number(item.val),"valueType":valueType(item.val)] }
    return out
  }

  internal static Str:Obj? normalizeClean(Dict point, FinEnergyCleanResult result, DateTime from, DateTime to, Bool trend := false)
  {
    hours:=Int:FinEnergyCleanHour[:]
    details:=result.details.findAll |d| { d["emitted"] != false && d["intervalSeconds"] != null }
    selected:=[Str:Obj?][,]
    details.each |d|
    {
      end:=DateTime.fromIso(d["ts"].toStr).toTimeZone(from.tz)
      seconds:=FinEnergyMath.num(d["intervalSeconds"]) ?: 0f
      if (seconds <= 0f) return
      start:=end-Duration((seconds*1sec.ticks.toFloat).toInt)
      if (end <= from || start >= to) return
      selected.add(d)
      at:=FinEnergyMath.floorHour(start)
      while (at < end)
      {
        if (at >= from && at < to)
        {
          if (!hours.containsKey(at.ticks)) hours[at.ticks]=FinEnergyCleanHour()
          acc:=hours[at.ticks]
          if (start < at || end > at+1hr) acc.missing=true
          else
          {
            acc.covered+=(end-start).ticks
            q:=detailQuality(d)
            if (q == "missing") acc.missing=true
            acc.values.add(FinEnergyValue(FinEnergyMath.num(d["value"]),q))
            if (FinEnergyMath.num(d["value"]) != null && d["substituted"] != true && q != "filtered") acc.valid+=(end-start).ticks
          }
        }
        at+=1hr
      }
    }
    samples:=[Str:Obj?][,]; cursor:=from; validTicks:=0
    while (cursor < to)
    {
      acc:=hours[cursor.ticks]
      v:=acc == null || acc.missing || acc.covered != 1hr.ticks ? FinEnergyValue(null,"missing") : FinEnergyValue.sum(acc.values)
      if (acc != null) validTicks+=acc.valid
      samples.add(v.point(cursor)); cursor+=1hr
    }
    meta:=result.summary.dup
    meta["summary"]=["filteredCount":selected.findAll |d| { detailQuality(d) == "filtered" }.size,"substitutedCount":selected.findAll |d| { d["substituted"] == true }.size,"naCount":selected.findAll |d| { d["valueType"] == "na" }.size,"intervalCount":selected.size,"coverage":(validTicks.toFloat/(to-from).ticks.toFloat).min(1f)]
    meta["inputCount"]=result.rawItems.findAll |i| { i.ts >= from && i.ts < to }.size
    meta["outputCount"]=selected.size
    meta["validCount"]=selected.findAll |d| { FinEnergyMath.num(d["value"]) != null }.size
    meta["nullCount"]=selected.findAll |d| { d["valueType"] == "null" }.size
    meta["naCount"]=selected.findAll |d| { d["valueType"] == "na" }.size
    meta.setAll(cleaningEvidence(point,result,from,to))
    if (trend)
    {
      visible:=point["hisMode"] == "consumption" || point["hisFunc"] == "finEnergyCleanHis" ? nativeItems(result) : result.items
      samples=visible.findAll |i| { i.ts >= from && i.ts < to }.map |i->[Str:Obj?]| { ["ts":i.ts.toTimeZone(from.tz).toIso,"value":number(i.val),"valueType":valueType(i.val)] }
    }
    raw:=result.rawItems.map |i->[Str:Obj?]| { ["ts":i.ts.toTimeZone(from.tz).toIso,"value":number(i.val),"valueType":valueType(i.val)] }
    intervals:=selected.map |detail->[Str:Obj?]|
    {
      end:=DateTime.fromIso(detail["ts"].toStr).toTimeZone(from.tz)
      seconds:=FinEnergyMath.num(detail["intervalSeconds"]) ?: 0f
      start:=end-Duration((seconds*1sec.ticks.toFloat).toInt)
      return ["from":start.toIso,"to":end.toIso,"value":detail["value"],"valueType":detail["valueType"],"quality":detailQuality(detail)]
    }
    return ["pointId":point.id.id,"unit":point["unit"]?.toStr ?: "","mode":"interval","quality":"cleaned","rawQuality":"ok","samples":samples,"rawSamples":trend ? samples : raw,"intervals":intervals,"sourceIds":result.summary["sourceIds"] ?: [point.id.id],"cleaning":meta]
  }

  ** The admitted chart has no raw/reference/gauge consumers. Strict and known
  ** readers use these same authoritative closed intervals, without building
  ** raw-sample DTOs, synthetic hourly samples or deferred cleaning diagnostics.
  internal static Str:Obj? normalizeChartClean(Dict point,FinEnergyCleanResult result,DateTime from,DateTime to)
  {
    intervals:=[Str:Obj?][,]
    result.details.each |d|
    {
      if(d["emitted"]==false || d["intervalSeconds"]==null) return
      end:=DateTime.fromIso(d["ts"].toStr).toTimeZone(from.tz)
      seconds:=FinEnergyMath.num(d["intervalSeconds"]) ?: 0f
      if(seconds<=0f) return
      start:=end-Duration((seconds*1sec.ticks.toFloat).toInt)
      if(end<=from || start>=to) return
      intervals.add(["from":start.toIso,"to":end.toIso,"value":d["value"],"valueType":d["valueType"],"quality":detailQuality(d)])
    }
    return ["pointId":point.id.id,"unit":point["unit"]?.toStr ?: "","mode":"interval","quality":"cleaned","samples":[Str:Obj?][,],"intervals":intervals,"sourceIds":result.summary["sourceIds"] ?: [point.id.id]]
  }

  private static Str:Obj? unavailable(Str id, Str quality)
  { ["pointId":id,"mode":"sampled","quality":quality,"samples":[Str:Obj?][,]] }

  private static Float? number(Obj? value)
  {
    if (value is Number) return FinEnergyMath.num(((Number)value).toFloat)
    if (value is Bool) return value == true ? 1f : 0f
    return FinEnergyMath.num(value)
  }

  internal static Duration? cadence(Dict point, HisItem[] items)
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
    if (FinEnergyDimension.active(request)) return FinEnergyDimension.dependencies(request,records)
    ctx:=FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc)
    selected:=FinEnergyMath.strings(request["nodeIds"])
    if (request["kind"] == "utility")
    {
      meters:=FinEnergyEndUse.resolveReport(ctx,request)
      points:=meters.map |r->Str| {r["pointId"] as Str ?: ""}
      return ["points":points.findAll |Str id->Bool| {!id.isEmpty}.unique,"nodes":meters.map |r->Str| {r["id"].toStr}]
    }
    if (selected.isEmpty && request["kind"] == "dashboard")
    {
      selected=records.findAll |r| { r["kind"] == "group" && r["parentId"] == null }.map |r->Str| { r["id"].toStr }
      if (selected.isEmpty) selected=records.findAll |r| { ctx.included(r) && r["parentId"] == null }.map |r->Str| { r["id"].toStr }
    }
    selected=selected.dup.addAll(FinEnergyMath.strings(request["referenceIds"]))
    ["xId","yId"].each |key| { if (request[key] != null) selected.add(request[key].toStr) }
    points:=Str[,]; nodes:=Str[,]
    selected.each |id| { collect(ctx,id,points,nodes,request["kind"] == "trend") }
    return ["points":points.unique,"nodes":nodes.unique]
  }

  private static Void collect(FinEnergyContext ctx, Str id, Str[] points, Str[] nodes, Bool trend)
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

internal class FinEnergyHourAccumulator
{
  Float value := 0f
  Int covered := 0
  Bool invalid := false
}

internal class FinEnergyCleanHour
{
  Int covered := 0
  Int valid := 0
  Bool missing := false
  FinEnergyValue[] values := [,]
}


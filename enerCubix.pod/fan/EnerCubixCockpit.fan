using util

** Request-local read-only cockpit projection. No persistent snapshot or history store.
class EnerCubixCockpit
{
  internal static Str:Obj? execute(Str:Obj? input, [Str:Obj?][] records,
    |Str:Obj?,[Str:Obj?][]->[Str:Obj?][]| load, Str project, TimeZone tz, DateTime now, Bool canManage := false, |->DateTime|? clock := null, |->[Str:Obj?][]|? activeEvents := null)
  {
    input=(Str:Obj?)input.toImmutable
    readClock:=clock ?: |->DateTime| {DateTime.now}
    request:=query(input,project,tz,now)
    frozen:=([Str:Obj?][])records.toImmutable
    scope:=object(input,"reportScope")
    ids:=(Str[])request["nodeIds"]; category:=((Str[])request["categoryIds"]).first
    comparison:=EnerCubixCockpitMetrics.comparison(input,request,tz)
    auxiliary:=input["auxiliaryCategoryId"] as Str
    enabled:=strings(input["modules"])
    kpis:=enabled.contains("kpis")
    request["categoryIds"]=[category]
    request["_cockpitCategoryId"]=category
    request["_cockpitExplicitObjects"]=scope["selectionIntent"] == "explicitObjects"
    dim:=EnerCubixDimension(request["dimension"].toStr,frozen,request["spaceSource"] == "fin")
    ctx:=EnerCubixContext(dim.records,[Str:Obj?][,],tz,dim)
    if (!frozen.any |r| {r["id"] == category && r["kind"] == "category"}) forbidden
    ids.each |id|
    {
      r:=frozen.find |r| {r["id"] == id}
      if (r == null || r["nativeHidden"] == true || (!dim.scope(id) && !["meter","totalMeter"].contains(r["kind"]))) forbidden
    }
    members:=[Str:Obj?][,]; overlaps:=[Str:Obj?][,]
    scopes:=ids.map |id->[Str:Obj?][]| {ctx.scopeMeters(id,category)}
    scopes.each |[Str:Obj?][] own, Int i|
    {
      members.addAll(own)
      for (j:=0;j<i;j++)
      {
        combined:=own.dup.addAll(([Str:Obj?][])scopes[j])
        combinedIds:=combined.map |r->Str| {r["id"].toStr}
        points:=combined.map |r->Str| {r["pointId"] as Str ?: ""}.findAll |Str p->Bool| {!p.isEmpty}
        if (combinedIds.size != combinedIds.unique.size || ctx.selectionMeters(combined).size != combinedIds.unique.size || points.size != points.unique.size)
          overlaps.add(["nodeIds":[ids[j],ids[i]],"reason":"overlappingScopes"])
      }
    }
    meters:=ctx.selectionMeters(members)
    if (members.map |r->Str| {r["id"].toStr}.unique.size > 200) throw ArgErr("cockpitMeterLimit")
    allowed:=scope["selectionIntent"] != "explicitObjects" || overlaps.isEmpty
    if (!allowed) meters=members.unique
    boundaryId:=Uuid().toStr
    boundary:=Str:Obj?["id":boundaryId,"meterIds":meters.map |m->Str| {m["id"].toStr}.unique.sort,"sourcePointIds":meters.map |m->Str| {m["pointId"] as Str ?: ""}.findAll |Str p->Bool| {!p.isEmpty}.unique.sort,"aggregateAllowed":allowed,"overlaps":overlaps,"excluded":[Str:Obj?][,]]
    if (auxiliary != null && !frozen.any |r| {r["id"] == auxiliary && r["kind"] == "category"}) forbidden
    if (kpis && auxiliary != null)
    {
      combined:=members.dup
      ids.each |id| {combined.addAll(ctx.scopeMeters(id,auxiliary))}
      if (combined.map |m->Str| {m["id"].toStr}.unique.size > 200) throw ArgErr("cockpitMeterLimit")
    }
    // One union plan, frozen before reads; disjoint periods never imply a year-wide scan.
    request["_cockpitPointIds"]=boundary["sourcePointIds"]
    historyRequest:=request.dup
    effectiveEnd:=DateTime.fromIso(request["asOf"].toStr)
    if (DateTime.fromIso(request["to"].toStr) < effectiveEnd) effectiveEnd=DateTime.fromIso(request["to"].toStr)
    historyRequest["to"]=effectiveEnd.toIso
    plan:=EnerCubixCockpitMetrics.plan(request,kpis ? comparison : Str:Obj?["mode":"none"],ctx,kpis ? auxiliary : null,scope["selectionIntent"] == "explicitObjects",kpis)
    historyRequest["_cockpitRanges"]=plan
    historyRequest["_cockpitPointIds"]=plan.map |r->Str[]| {EnerCubixMath.strings(r["pointIds"])}.flatten.unique.sort
    observedFrom:=readClock()
    histories:=plan.isEmpty ? [Str:Obj?][,] : load((Str:Obj?)historyRequest.toImmutable,frozen)
    histories=([Str:Obj?][])histories.toImmutable
    observedTo:=readClock()
    report:=EnerCubixHistory.report(request,frozen,EnerCubixCockpitMetrics.histories(request,histories))
    row:=EnerCubixMath.maps(((Map)report["summary"])["selectionTotals"]).find |r| {r["categoryId"] == category}
    complete:=row == null ? null : EnerCubixMath.num(row["value"])
    known:=row == null ? null : EnerCubixMath.num(row["knownValue"])
    quality:=row?.get("quality") as Str ?: "missing"
    if (["filtered","substituted","na"].contains(quality)) complete=null
    na:=row?.get("valueType") == "na" || row?.get("knownValueType") == "na"
    if (complete == null && known == null && na) quality="na"
    reasons:=Str[,]
    if (!allowed) {complete=null; known=null; quality="overlappingScopes"}
    boundaryQuality:=row?.get("scopeQuality") as Str
    if (boundaryQuality != null && !["topologyIncomplete","accountingIncomplete","duplicateSource"].contains(boundaryQuality)) boundaryQuality=null
    sources:=meters.map |m->Str| {m["pointId"] as Str ?: ""}.findAll |Str p->Bool| {!p.isEmpty}
    if (sources.size != sources.unique.size) boundaryQuality="duplicateSource"
    if (boundaryQuality != null)
    {
      allowed=false; boundary["aggregateAllowed"]=false
      boundary["reasonCode"]=boundaryQuality
      complete=null; known=null; quality=boundaryQuality
    }
    if (complete == null) reasons.add(quality)
    value:=complete ?: known
    basis:=complete != null ? "complete" : (known != null ? "knownSubtotal" : "unavailable")
    coverage:=EnerCubixMath.maps(((Map)report["extra"])["usageCoverage"])
    if (value != null && (quality == "substituted" || row?.get("knownQuality") == "substituted")) basis="cleanedWithReplacement"
    metric:=Str:Obj?["id":"energy","categoryId":category,"value":value,"valueType":value != null ? "number" : (na && allowed ? "na" : "null"),"unit":row?.get("unit") ?: ctx.unit(ids.first,category,"energy"),"quality":complete == null && known != null ? "partial" : quality,"valueBasis":basis,"completeValue":complete,"knownValue":known,"sourceIds":row?.get("sourceIds") ?: boundary["sourcePointIds"],"reasonCodes":reasons,"boundaryId":boundaryId]
    metric["coverage"]=coverage
    reports:=Str:Obj?["profile-energy":report]
    values:=kpis ? EnerCubixCockpitMetrics.values(request,frozen,histories,metric,boundary,auxiliary,reports) : [metric]
    if (kpis && comparison["mode"] != "none")
    {
      referenceRequest:=request.dup.setAll((Map)comparison["referenceRange"])
      referenceReport:=EnerCubixHistory.report(referenceRequest,frozen,EnerCubixCockpitMetrics.histories(referenceRequest,histories))
      referenceEnergy:=EnerCubixCockpitMetrics.metric(referenceReport,"energy",category,boundary)
      referenceValues:=EnerCubixCockpitMetrics.values(referenceRequest,frozen,histories,referenceEnergy,boundary,auxiliary,reports,"reference-")
      reports["reference-profile-energy"]=referenceReport
      values.each |v|
      {
        previous:=referenceValues.find |p| {p["id"] == v["id"]}
        v["comparison"]=EnerCubixCockpitMetrics.comparisonValue(v,previous,comparison)
      }
    }
    events:=EnerCubixCockpitMetrics.events(kpis ? activeEvents : null,ctx,ids,category,boundary,readClock)
    carbon:=values.find |v| {v["id"] == "co2"}
    if (carbon != null && ((List)carbon["reasonCodes"]).contains("missingCoefficient"))
      values[values.index(carbon)]=events
    status:=complete != null ? "ok" : (known != null ? "partial" : "unavailable")
    if (values.any |v| {v["completeValue"] == null}) status=values.any |v| {v["value"] != null} ? "partial" : "unavailable"
    modules:=Str:Obj?[:]
    if (enabled.contains("kpis")) modules["kpis"]=["status":status,"boundaryId":boundaryId,"data":["values":values,"conclusions":EnerCubixCockpitMetrics.conclusions(values,events,request)]]
    if (enabled.contains("trend")) modules["trend"]=["status":coverage.isEmpty ? "empty" : (coverage.all |c| {c["complete"] == true} ? "ok" : "partial"),"boundaryId":boundaryId,"data":["reportRef":"profile-energy"]]
    config:=EnerCubixCockpitMetrics.configuration(ctx,ids,auxiliary == null ? [category] : [category,auxiliary])
    refs:=config.map |r->[Str:Obj?]| {["id":r["id"],"mod":r["mod"]]}
    histories.each |h| {refs.addAll(EnerCubixMath.maps(h["configRefs"]))}
    refs=refs.unique.sort |[Str:Obj?] a, [Str:Obj?] b->Int| {a["id"].toStr <=> b["id"].toStr}
    observed:=DateTime[,]; cutoff:=DateTime.fromIso(request["asOf"].toStr)
    histories.each |h|
    {
      if (!((Str[])boundary["sourcePointIds"]).contains(h["pointId"])) return
      rows:=EnerCubixMath.maps(h["rawSamples"] ?: h["samples"])
      rows.each |s| {t:=DateTime.fromIso(s["ts"]?.toStr ?: "",false); if (t != null && t <= effectiveEnd) observed.add(t)}
      if (rows.isEmpty) EnerCubixMath.maps(h["intervals"]).each |s| {t:=DateTime.fromIso(s["to"]?.toStr ?: "",false); if (t != null && t <= effectiveEnd) observed.add(t)}
    }
    context:=Str:Obj?["project":project,"projectTimeZone":tz.name,"reportScope":scope,"focusCategoryId":category,"auxiliaryCategoryId":auxiliary,"comparison":comparison,"time":["preset":object(input,"time")["preset"],"period":request["period"],"from":request["from"],"to":request["to"]],"asOf":request["asOf"]]
    provenance:=Str:Obj?["configFingerprint":JsonOutStream.writeJsonToStr(["refs":refs,"configuration":config]).toBuf.toDigest("SHA-256").toHex,"relationshipBasis":"currentConfiguration","historyBasis":"ownPrimaryPointRaw","historyObservedFrom":observedFrom.toIso,"historyObservedTo":observedTo.toIso,"sourceLastObservedAt":observed.isEmpty ? null : ((DateTime)observed.max).toIso,"configRefs":refs,"historyPlan":plan,"stateObservedAt":events["stateObservedAt"]]
    limitations:=Str[,]
    if (complete == null) limitations.add(known == null ? "ENERGY_UNAVAILABLE" : "PARTIAL_USAGE")
    if (scope["selectionIntent"] == "explicitObjects" && !overlaps.isEmpty) limitations.add("OVERLAPPING_EXPLICIT_OBJECTS")
    if (DateTime.fromIso(request["to"].toStr) > cutoff) limitations.add("REQUEST_END_AFTER_AS_OF")
    if (histories.any |h| {h["quality"] == "historySampleLimit"}) limitations.add("HISTORY_SAMPLE_LIMIT")
    if (histories.any |h| {h["quality"] == "historyReadError"}) limitations.add("HISTORY_READ_ERROR")
    return (Str:Obj?)["schemaVersion":1,"snapshotId":Uuid().toStr,"requestId":input["requestId"],"generatedAt":readClock().toIso,"context":context,"provenance":provenance,"boundary":boundary,"modules":modules,"reports":reports,"quality":coverage,"capabilities":["canRead":true,"canManage":canManage,"availableFaces":Str[,]],"limitations":limitations].toImmutable
  }

  ** Hidden scope members cannot silently disappear from a supposedly complete total.
  internal static Void guardVisibleScope(Str:Obj? request, [Str:Obj?][] visible, [Str:Obj?][] all)
  {
    dimension:=request["dimension"].toStr
    if (dimension == "metering") return // Explicit meter history owns its boundary.
    ids:=EnerCubixMath.strings(request["nodeIds"]).findAll |id| {visible.any |r| {r["id"] == id && r["kind"] == dimension}}
    if (ids.isEmpty) return
    categories:=EnerCubixMath.strings(request["categoryIds"])
    hidden:=all.findAll |r| {r["_comparisonReadable"] == false && ["meter","totalMeter"].contains(r["kind"]) && categories.contains(r["categoryId"]) && r["includeInTotals"] != false}
    index:=Str:[Str:Obj?][:]; all.each |r| {index[r["id"].toStr]=r}; visible.each |r| {index[r["id"].toStr]=r}
    hidden.each |r|
    {
      cursor:=r[dimension == "space" ? "spaceId" : "organizationId"] as Str
      // Native unplaced hidden equipment cannot be proven outside a space scope.
      if (dimension == "space" && cursor == null) forbidden
      seen:=Str[,]
      while (cursor != null && !seen.contains(cursor))
      {
        if (ids.contains(cursor)) forbidden
        seen.add(cursor); cursor=index[cursor]?.get("parentId") as Str
      }
    }
  }

  ** Client project/timezone and engine implementation fields are never accepted.
  internal static Str:Obj? query(Str:Obj? input, Str project, TimeZone tz, DateTime now)
  {
    allowed:=["schemaVersion","requestId","reportScope","focusCategoryId","time","asOf","modules","comparison","auxiliaryCategoryId"]
    if (input.keys.any |key| {!allowed.contains(key)} || input["schemaVersion"] isnot Int || input["schemaVersion"] != 1) throw ArgErr("cockpitSchema")
    requestId:=text(input,"requestId"); if (requestId.size > 200) throw ArgErr("cockpitRequestId")
    scope:=object(input,"reportScope"); time:=object(input,"time")
    dimension:=text(scope,"dimension"); intent:=text(scope,"selectionIntent")
    if (!["space","metering","organization"].contains(dimension) || !["range","explicitObjects"].contains(intent)) throw ArgErr("cockpitScope")
    ids:=strings(scope["nodeIds"]); if (ids.isEmpty || ids.size > 200) throw ArgErr("cockpitScopeLimit")
    ids.each |id| {ref(id,project)}
    category:=text(input,"focusCategoryId"); ref(category,project)
    modules:=strings(input["modules"])
    if (modules.isEmpty || modules.any |m| {!["kpis","trend"].contains(m)}) throw ArgErr("cockpitModules")
    if (input["auxiliaryCategoryId"] != null)
    {
      auxiliary:=text(input,"auxiliaryCategoryId"); ref(auxiliary,project)
      if (auxiliary == category) throw ArgErr("cockpitAuxiliaryCategory")
    }
    if (input["comparison"] != null && !["none","presetDefault","custom"].contains(object(input,"comparison")["mode"])) throw ArgErr("cockpitComparison")
    period:=text(time,"period"); preset:=text(time,"preset")
    if (!["hour","day","month"].contains(period) || !["today","thisMonth","thisYear","custom"].contains(preset)) throw ArgErr("cockpitTime")
    cutoff:=input["asOf"] == null ? now : instant(input,"asOf")
    if (cutoff > now) cutoff=now
    cutoff=cutoff.toTimeZone(tz)
    from:=cutoff.date.toDateTime(Time.defVal,tz); to:=cutoff
    if (preset == "thisMonth") from=EnerCubixMath.bucket(cutoff,"month")
    else if (preset == "thisYear") from=EnerCubixMath.bucket(cutoff,"year")
    else if (preset == "custom") {from=instant(time,"from").toTimeZone(tz); to=instant(time,"to").toTimeZone(tz)}
    if (to <= from || to.date-from.date > 366day) throw ArgErr("cockpitTimeRange")
    return ["kind":"profile","metric":"energy","dimension":dimension,"spaceSource":"fin","nodeIds":ids.unique,"categoryIds":input["auxiliaryCategoryId"] == null ? [category] : [category,input["auxiliaryCategoryId"]],"period":period,"from":from.toIso,"to":to.toIso,"asOf":cutoff.toIso,"tz":tz.name]
  }

  private static Void forbidden() {throw EnerCubixHttpErr(403,"PERMISSION","cockpitScopeForbidden")}
  private static Void ref(Str id, Str project)
  {
    if (id.trim != id || id.size > 300 || id.any |c| {c.isSpace || c < 32} || (id.startsWith("p:") && !id.startsWith("p:"+project+":r:"))) throw ArgErr("cockpitRef")
  }
  private static Str text(Str:Obj? value, Str key)
  {s:=value[key] as Str; if (s == null || s.isEmpty) throw ArgErr("cockpitField"); return s}
  private static Str:Obj? object(Str:Obj? value, Str key)
  {m:=value[key] as Map; if (m == null || m.keys.any |k| {k isnot Str}) throw ArgErr("cockpitField"); return m}
  private static Str[] strings(Obj? value)
  {list:=value as List; if (list == null || list.any |v| {v isnot Str || ((Str)v).isEmpty}) throw ArgErr("cockpitField"); return list.map |v->Str| {(Str)v}}
  private static DateTime instant(Str:Obj? value, Str key)
  {t:=DateTime.fromIso(text(value,key),false); if (t == null) throw ArgErr("cockpitTime"); return t}
}

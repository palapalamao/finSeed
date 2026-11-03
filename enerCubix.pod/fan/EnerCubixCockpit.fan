using util

** Request-local read-only cockpit projection. No persistent snapshot or history store.
class EnerCubixCockpit
{
  internal static Str:Obj? execute(Str:Obj? input, [Str:Obj?][] records,
    |Str:Obj?,[Str:Obj?][]->[Str:Obj?][]| load, Str project, TimeZone tz, DateTime now, Bool canManage := false, |->DateTime|? clock := null, |->[Str:Obj?][]|? activeEvents := null, |Str:Obj?,[Str:Obj?][],[Str:Obj?][]->Str:Obj?|? kpiReport := null, EnerCubixCockpitDeadline? deadline := null, Str:Obj? ownedConfig := [:], |Str,Str:Obj?->Str:Obj?|? preparedReport := null,|Str,Str:Obj?->Str:Obj?|? preparedCop := null,|Str,Str:Obj?->Str:Obj?|? preparedRule := null,EnerCubixCockpitRequestScope? requestScope := null)
  {
    if(requestScope==null) {input=(Str:Obj?)input.toImmutable;ownedConfig=(Str:Obj?)ownedConfig.toImmutable}
    else
    {
      requestScope.checkContext(project,requestScope.user)
      if(deadline!=null && deadline!==requestScope.deadline) throw ArgErr("cockpitRequestScopeDeadline")
      deadline=requestScope.deadline;bundle:=requestScope.freezeInputs(input,ownedConfig,records)
      input=(Str:Obj?)bundle["input"];ownedConfig=(Str:Obj?)bundle["owned"];records=([Str:Obj?][])bundle["records"]
    }
    snapshotId:=Uuid().toStr
    readClock:=clock ?: |->DateTime| {DateTime.now}
    request:=query(input,project,tz,now)
    deadline?.check
    if(deadline != null) request["_cockpitDeadline"]=deadline
    frozen:=([Str:Obj?][])records.toImmutable
    scope:=object(input,"reportScope")
    ids:=(Str[])request["nodeIds"]; category:=((Str[])request["categoryIds"]).first
    comparison:=EnerCubixCockpitMetrics.comparison(input,request,tz)
    auxiliary:=input["auxiliaryCategoryId"] as Str
    enabled:=strings(input["modules"])
    kpis:=enabled.contains("kpis")
    request["categoryIds"]=[category]
    request["_cockpitCategoryId"]=category
    if(input["payloadEncoding"] == "compact-v1") request["_cockpitDiagnosticCapture"]=true
    request["_cockpitExplicitObjects"]=scope["selectionIntent"] == "explicitObjects"
    EnerCubixContext? ctx
    if(requestScope==null)
    {original:=EnerCubixDimension(request["dimension"].toStr,frozen,request["spaceSource"] == "fin");ctx=EnerCubixContext(original.records,[Str:Obj?][,],tz,original)}
    else ctx=requestScope.planningContext(frozen,tz,request["dimension"].toStr,request["spaceSource"] == "fin")
    dim:=ctx.dimension
    if (!frozen.any |r| {r["id"] == category && r["kind"] == "category"}) forbidden
    ids.each |id|
    {
      r:=frozen.find |r| {r["id"] == id}
      if (r == null || r["nativeHidden"] == true || r["_comparisonReadable"] == false || (!dim.scope(id) && !["meter","totalMeter"].contains(r["kind"]))) forbidden
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
    Str:Obj? flow:=[:]
    if (enabled.contains("balance"))
    {
      try {flow=EnerCubixCockpitFlow.prepare(request,frozen,project,preparedReport!=null)}
      catch (EnerCubixHttpErr e) {throw e}
      catch (Err e) {flow=["error":true]}
    }
    Str:Obj? efficiency:=[:]
    if (enabled.contains("efficiency"))
    {
      try {efficiency=EnerCubixCockpitEfficiency.prepare(request,frozen,project,kpis && auxiliary != null ? [category,auxiliary] : [category])}
      catch (EnerCubixHttpErr e) {throw e}
      catch (Err e) {efficiency=["error":true]}
    }
    evidence:=EnerCubixMath.maps(flow["meters"]).dup.addAll(EnerCubixMath.maps(efficiency["meters"]))
    planned:=members.dup.addAll(evidence).addAll(EnerCubixMath.maps(efficiency["devices"]))
    if (kpis && auxiliary != null) ids.each |id| {planned.addAll(ctx.scopeMeters(id,auxiliary))}
    if (planned.map |m->Str| {m["id"].toStr}.unique.size > 200) throw ArgErr("cockpitMeterLimit")
    // One union plan, frozen before reads; disjoint periods never imply a year-wide scan.
    request["_cockpitPointIds"]=boundary["sourcePointIds"]
    historyRequest:=request.dup
    historyRequest["_cockpitNeedsRuleFacts"]=enabled.contains("issues") && EnerCubixMath.maps(ownedConfig["rules"]).any |r| {r["enabled"] == true && r["ruleType"] == "nonWorkingHighUsage" && r["categoryRef"] == category}
    effectiveEnd:=DateTime.fromIso(request["asOf"].toStr)
    if (DateTime.fromIso(request["to"].toStr) < effectiveEnd) effectiveEnd=DateTime.fromIso(request["to"].toStr)
    historyRequest["to"]=effectiveEnd.toIso
    plan:=EnerCubixCockpitMetrics.plan(request,kpis ? comparison : Str:Obj?["mode":"none"],ctx,kpis ? auxiliary : null,scope["selectionIntent"] == "explicitObjects",kpis,evidence)
    historyRequest["_cockpitReadRanges"]=[request]
    if (kpis && comparison["mode"] != "none") historyRequest["_cockpitReadRanges"]=[request,request.dup.setAll((Map)comparison["referenceRange"])]
    historyRequest["_cockpitRanges"]=plan
    pointIds:=Str[,];plan.each |r| {pointIds.addAll(EnerCubixMath.strings(r["pointIds"]))}
    pointIds.unique.each |id| {ref(id,project)}
    historyRequest["_cockpitPointIds"]=pointIds.unique.sort
    historyRequest["_cockpitConfigIds"]=EnerCubixMath.maps(flow["configuration"]).dup.addAll(EnerCubixMath.maps(efficiency["configuration"])).map |r->Str| {r["id"].toStr}.unique.sort
    // Only an explicit private prepared route gets this acyclic metadata bundle.
    // The report request never points back to its enclosing history request.
    if(preparedReport!=null) historyRequest["_cockpitConsumers"]=["request":request,"boundary":boundary,"enabled":enabled,"comparison":comparison,"auxiliary":auxiliary,"owned":ownedConfig,"flow":flow,"efficiency":efficiency]
    observedFrom:=readClock()
    deadline?.check
    histories:=plan.isEmpty && preparedReport==null ? [Str:Obj?][,] : load((Str:Obj?)historyRequest.toImmutable,frozen)
    Str:Obj? requestMeta:=[:]
    if(histories.any |h| {h.containsKey("_cockpitRequestMeta")})
    {
      metadataRows:=histories.findAll |h| {h.containsKey("_cockpitRequestMeta")}
      if(preparedReport==null || metadataRows.size!=1 || metadataRows.first.size!=1) throw ArgErr("cockpitPreparedRequestMeta")
      candidate:=metadataRows.first["_cockpitRequestMeta"] as Map
      if(candidate==null || candidate["schemaVersion"]!=1 || candidate["diagnostics"] isnot Map || candidate["preparedBudget"] isnot EnerCubixPreparedBudget || (candidate["streaming"]!=null && candidate["streaming"] isnot Map) || (candidate["publishDiagnostics"]!=null && candidate["publishDiagnostics"] isnot |Str:Obj?->Str:Obj?|) || (candidate["releaseSources"]!=null && (requestScope==null || candidate["releaseSources"] isnot |->Void|)) || candidate.keys.any |key| {!["schemaVersion","diagnostics","preparedBudget","streaming","historyConfigObservedFrom","historyConfigObservedTo","publishDiagnostics","releaseSources"].contains(key)}) throw ArgErr("cockpitPreparedRequestMeta")
      diagnostic:=(Map)candidate["diagnostics"];count:=diagnostic["returnedCount"] as Int
      if(diagnostic["schemaVersion"]!=1 || diagnostic["rowBudget"]!=1000 || count==null || count<0 || count>1000 || diagnostic["entries"] isnot List) throw ArgErr("cockpitPreparedRequestMeta")
      if(candidate.containsKey("historyConfigObservedFrom") || candidate.containsKey("historyConfigObservedTo"))
      {
        observedA:=DateTime.fromIso(candidate["historyConfigObservedFrom"] as Str ?: "",false);observedB:=DateTime.fromIso(candidate["historyConfigObservedTo"] as Str ?: "",false)
        if(observedA==null || observedB==null || observedA>observedB) throw ArgErr("cockpitPreparedRequestMeta")
      }
      if(deadline!=null && ((EnerCubixPreparedBudget)candidate["preparedBudget"]).deadline!==deadline) throw ArgErr("cockpitPreparedRequestMeta")
      requestMeta=(Str:Obj?)candidate
      // This control envelope has no point identity and is never parsed as a
      // history, including when there are no point headers at all.
      histories=histories.exclude |h| {h.containsKey("_cockpitRequestMeta")}
    }
    if(input["payloadEncoding"] == "compact-v1") histories=histories.map |h->[Str:Obj?]|
    {
      meta:=h["cleaning"] as Map
      if(meta == null || meta["detailsTruncated"] != true || meta["detailsCaptureId"] != null) return h
      return h.dup.set("cleaning",meta.dup.set("detailsCaptureId",Uuid().toStr))
    }
    histories=([Str:Obj?][])histories.toImmutable
    observedTo:=readClock()
    deadline?.check
    historyMeta:=EnerCubixCockpitHistoryMeta(pointIds.unique,effectiveEnd)
    histories.each |h| {historyMeta.observe(h)}
    report:=EnerCubixCockpitReports.read("profile-energy",request,frozen,EnerCubixCockpitMetrics.histories(request,histories),preparedReport)
    row:=EnerCubixMath.maps(((Map)report["summary"])["selectionTotals"]).find |r| {r["categoryId"] == category}
    boundaryQuality:=row?.get("scopeQuality") as Str
    if (boundaryQuality != null && !["topologyIncomplete","accountingIncomplete","duplicateSource"].contains(boundaryQuality)) boundaryQuality=null
    sources:=meters.map |m->Str| {m["pointId"] as Str ?: ""}.findAll |Str p->Bool| {!p.isEmpty}
    if (sources.size != sources.unique.size) boundaryQuality="duplicateSource"
    if (boundaryQuality != null)
    {
      allowed=false; boundary["aggregateAllowed"]=false
      boundary["reasonCode"]=boundaryQuality
    }
    coverage:=EnerCubixMath.maps(((Map)report["extra"])["usageCoverage"])
    metric:=EnerCubixCockpitMetrics.metric(report,"energy",category,boundary)
    if (row == null) metric.setAll(["unit":ctx.unit(ids.first,category,"energy"),"sourceIds":boundary["sourcePointIds"]])
    if (!allowed) metric["valueType"]="null"
    complete:=EnerCubixMath.num(metric["completeValue"])
    known:=EnerCubixMath.num(metric["knownValue"])
    reports:=Str:Obj?["profile-energy":report]
    values:=kpis ? EnerCubixCockpitMetrics.values(request,frozen,histories,metric,boundary,auxiliary,reports,"",kpiReport,preparedReport) : [metric]
    if (kpis && comparison["mode"] != "none")
    {
      referenceRequest:=request.dup.setAll((Map)comparison["referenceRange"])
      referenceReport:=EnerCubixCockpitReports.read("reference-profile-energy",referenceRequest,frozen,EnerCubixCockpitMetrics.histories(referenceRequest,histories),preparedReport)
      referenceEnergy:=EnerCubixCockpitMetrics.metric(referenceReport,"energy",category,boundary)
      referenceValues:=EnerCubixCockpitMetrics.values(referenceRequest,frozen,histories,referenceEnergy,boundary,auxiliary,reports,"reference-",kpiReport,preparedReport)
      reports["reference-profile-energy"]=referenceReport
      values.each |v|
      {
        previous:=referenceValues.find |p| {p["id"] == v["id"]}
        v["comparison"]=EnerCubixCockpitMetrics.comparisonValue(v,previous,comparison)
      }
    }
    cost:=values.find |v| {v["id"] == "cost"} ?: Str:Obj?[:]
    budgetBoundary:=EnerCubixCockpitBudget.physicalBoundary(boundary);budgetCost:=cost;canonical:=Str:Obj?[:]
    if((kpis || enabled.contains("issues")) && !EnerCubixMath.maps(ownedConfig["budgets"]).isEmpty)
    {
      try {canonical=EnerCubixCockpitBudget.canonical(request,frozen,histories,boundary,reports,preparedReport);budgetBoundary=(Map)canonical["boundary"];budgetCost=(Map)canonical["cost"]}
      catch(Err e) {if(!EnerCubixCockpitBudget.localError(e)) throw e;budgetCost=["value":null,"quality":"metricError"]}
    }
    Str:Obj? budgetResult:=[:]
    try {budgetResult=EnerCubixCockpitBudget.project(request,frozen,ownedConfig,budgetBoundary,budgetCost)}
    catch(Err e) {if(!EnerCubixCockpitBudget.localError(e)) throw e;budgetResult=EnerCubixBudgetMath.unavailable("BUDGET_INTERNAL_ERROR")}
    if(budgetCost["quality"] == "metricError") budgetResult=EnerCubixBudgetMath.unavailable("BUDGET_INTERNAL_ERROR")
    budgetResult.setAll(["comparisonFallback":cost["comparison"],"costReportRef":canonical.isEmpty ? "profile-cost" : "budget-canonical-cost","costBoundaryBasis":"canonicalOwnDeviceFrontier","viewAccountingQuality":boundary["reasonCode"],"costInputs":["request":canonical["request"],"meterIds":budgetBoundary["meterIds"],"sourcePointIds":budgetBoundary["sourcePointIds"],"valueBasis":budgetCost["valueBasis"],"coverage":budgetCost["coverage"],"sourceIds":budgetCost["sourceIds"]]])
    observation:=EnerCubixCockpitIssues.observe(kpis || enabled.contains("issues") ? activeEvents : null,ctx,ids,category,boundary,readClock,project)
    events:=EnerCubixCockpitMetrics.events(observation,category,boundary)
    carbon:=values.find |v| {v["id"] == "co2"}
    if (carbon != null && ((List)carbon["reasonCodes"]).contains("missingCoefficient"))
      values[values.index(carbon)]=events
    status:=complete != null ? "ok" : (known != null ? "partial" : "unavailable")
    if (values.any |v| {v["completeValue"] == null}) status=values.any |v| {v["value"] != null} ? "partial" : "unavailable"
    modules:=Str:Obj?[:]
    if (enabled.contains("kpis")) modules["kpis"]=["status":status,"boundaryId":boundaryId,"data":["values":values,"conclusions":EnerCubixCockpitMetrics.conclusions(values,events,request),"budget":budgetResult]]
    if (enabled.contains("trend")) modules["trend"]=["status":coverage.isEmpty ? "empty" : (coverage.all |c| {c["complete"] == true} ? "ok" : "partial"),"boundaryId":boundaryId,"data":["reportRef":"profile-energy"]]
    EnerCubixCockpitFaces.attach(enabled,request,frozen,histories,boundary,reports,modules,ctx,preparedReport)
    deadline?.check
    if (enabled.contains("space"))
    {
      try {modules["space"]=EnerCubixCockpitSpace.project(request,frozen,histories,pointIds.unique,boundary,preparedReport)}
      catch (EnerCubixHttpErr e) {throw e}
      catch (Err e) {modules["space"]=EnerCubixCockpitFlow.error}
    }
    if (enabled.contains("balance"))
    {
      if (flow["error"] == true) modules["balance"]=EnerCubixCockpitFlow.error
      else EnerCubixCockpitFlow.attach(flow,histories,boundary,reports,modules,preparedReport)
    }
    if (enabled.contains("efficiency"))
    {
      if (efficiency["error"] == true) modules["efficiency"]=EnerCubixCockpitFlow.error
      else EnerCubixCockpitEfficiency.attach(efficiency,histories,boundary,reports,modules,preparedCop)
    }
    ruleConfiguration:=[Str:Obj?][,]
    if (enabled.contains("issues"))
    {
      try
      {
        clues:=EnerCubixCockpitRules.project(request,frozen,histories,ownedConfig,budgetBoundary,budgetResult,snapshotId,preparedRule)
        ruleConfiguration=EnerCubixMath.maps(clues["configuration"])
        modules["issues"]=EnerCubixCockpitIssues.project(observation,events,values,request,boundary,ctx,clues)
      }
      catch (EnerCubixHttpErr e) {throw e}
      catch (Err e) {if(!EnerCubixCockpitBudget.localError(e)) throw e;modules["issues"]=EnerCubixCockpitFlow.error}
    }
    config:=EnerCubixCockpitMetrics.configuration(ctx,ids,auxiliary == null ? [category] : [category,auxiliary])
    config=config.dup.addAll(EnerCubixMath.maps(flow["configuration"])).addAll(EnerCubixMath.maps(efficiency["configuration"])).unique.sort |a,b| {a["id"].toStr <=> b["id"].toStr}
    ownedRefs:=kpis || enabled.contains("issues") ? EnerCubixMath.maps(budgetResult["configuration"]).dup.addAll(ruleConfiguration) : [Str:Obj?][,]
    config.addAll(ownedRefs)
    refs:=config.map |r->[Str:Obj?]| {["id":r["id"],"mod":r["mod"]]}
    proof:=historyMeta.snapshot
    if(requestMeta["streaming"] is Map) proof=proof.dup.set("streaming",[requestMeta["streaming"]])
    ["historyConfigObservedFrom","historyConfigObservedTo"].each |key| {if(requestMeta[key] is Str) proof=proof.dup.set(key,requestMeta[key])}
    refs.addAll(EnerCubixMath.maps(proof["configRefs"]))
    refs=refs.unique.sort |[Str:Obj?] a, [Str:Obj?] b->Int| {a["id"].toStr <=> b["id"].toStr}
    appliedCleaning:=proof["appliedCleaning"]
    cutoff:=DateTime.fromIso(request["asOf"].toStr)
    context:=Str:Obj?["project":project,"projectTimeZone":tz.name,"reportScope":scope,"focusCategoryId":category,"auxiliaryCategoryId":auxiliary,"comparison":comparison,"time":["preset":object(input,"time")["preset"],"period":request["period"],"from":request["from"],"to":request["to"]],"asOf":request["asOf"]]
    provenance:=Str:Obj?["configFingerprint":EnerCubixCockpitDigest.json(["refs":refs,"configuration":config,"appliedCleaning":appliedCleaning],deadline,requestScope?.stream?.state).sha256,"relationshipBasis":"currentConfiguration","historyBasis":"ownPrimaryPointRaw","historyObservedFrom":observedFrom.toIso,"historyObservedTo":observedTo.toIso,"sourceLastObservedAt":proof["sourceLastObservedAt"],"configRefs":refs,"historyPlan":plan,"stateObservedAt":events["stateObservedAt"],"appliedCleaning":appliedCleaning,"streaming":proof["streaming"],"historyLimitations":proof["historyLimitations"],"historyConfigObservedFrom":proof["historyConfigObservedFrom"],"historyConfigObservedTo":proof["historyConfigObservedTo"]]
    budget:=(requestMeta["preparedBudget"] as EnerCubixPreparedBudget) ?: (histories.find |h| {h["_preparedBudget"] is EnerCubixPreparedBudget}?.get("_preparedBudget") as EnerCubixPreparedBudget)
    if(budget != null) provenance["preparedRuntime"]=budget.evidence
    limitations:=Str[,]
    if (complete == null) limitations.add(known == null ? "ENERGY_UNAVAILABLE" : "PARTIAL_USAGE")
    if (scope["selectionIntent"] == "explicitObjects" && !overlaps.isEmpty) limitations.add("OVERLAPPING_EXPLICIT_OBJECTS")
    if (DateTime.fromIso(request["to"].toStr) > cutoff) limitations.add("REQUEST_END_AFTER_AS_OF")
    if (histories.any |h| {h["quality"] == "historySampleLimit"}) limitations.add("HISTORY_SAMPLE_LIMIT")
    if (histories.any |h| {h["quality"] == "streamingUnsupportedConfiguration"}) limitations.add("STREAMING_UNSUPPORTED_CONFIGURATION")
    if (histories.any |h| {h["quality"] == "historyReadError"}) limitations.add("HISTORY_READ_ERROR")
    faces:=enabled.findAll |m| {["time","endUse","organization","efficiency","balance"].contains(m)}
    if (!faces.isEmpty || enabled.contains("space")) faces.insert(0,"space")
    snapshotData:=Str:Obj?["schemaVersion":1,"snapshotId":snapshotId,"requestId":input["requestId"],"generatedAt":readClock().toIso,"context":context,"provenance":provenance,"boundary":boundary,"modules":modules,"reports":reports,"quality":coverage,"capabilities":["canRead":true,"canManage":canManage,"availableFaces":faces],"limitations":limitations]
    if(!requestMeta.isEmpty)
    {
      publisher:=requestMeta["publishDiagnostics"] as |Str:Obj?->Str:Obj?|
      snapshotData["diagnostics"]=publisher==null ? requestMeta["diagnostics"] : publisher(reports)
    }
    snapshot:=requestScope==null ? (Str:Obj?)snapshotData.toImmutable : requestScope.freezeSnapshot(snapshotData)
    releaseSources:=requestMeta["releaseSources"] as |->Void|
    releaseSources?.call
    requestScope?.finishPlanning
    deadline?.check
    result:=input["payloadEncoding"] == "compact-v1" ? EnerCubixCockpitPayload.encode(EnerCubixCockpitDiagnostics.project(snapshot,deadline),deadline,requestScope?.stream?.state,requestScope?.payloadOutput) : snapshot
    deadline?.check
    return result
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
    allowed:=["schemaVersion","requestId","reportScope","focusCategoryId","time","asOf","modules","comparison","auxiliaryCategoryId","payloadEncoding"]
    if (input.keys.any |key| {!allowed.contains(key)} || input["schemaVersion"] isnot Int || input["schemaVersion"] != 1) throw ArgErr("cockpitSchema")
    if (input["payloadEncoding"] != null && input["payloadEncoding"] != "compact-v1") throw ArgErr("cockpitPayloadEncoding")
    requestId:=text(input,"requestId"); if (requestId.size > 200) throw ArgErr("cockpitRequestId")
    scope:=object(input,"reportScope"); time:=object(input,"time")
    dimension:=text(scope,"dimension"); intent:=text(scope,"selectionIntent")
    if (!["space","metering","organization"].contains(dimension) || !["range","explicitObjects"].contains(intent)) throw ArgErr("cockpitScope")
    ids:=strings(scope["nodeIds"]); if (ids.isEmpty || ids.size > 200) throw ArgErr("cockpitScopeLimit")
    ids.each |id| {ref(id,project)}
    category:=text(input,"focusCategoryId"); ref(category,project)
    modules:=strings(input["modules"])
    if (modules.isEmpty || modules.any |m| {!["kpis","trend","time","endUse","organization","efficiency","balance","issues","space"].contains(m)}) throw ArgErr("cockpitModules")
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

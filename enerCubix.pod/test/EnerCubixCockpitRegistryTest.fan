using haystack

** Actual module report definitions are registered before the first source read.
class EnerCubixCockpitRegistryTest : Test
{
  Void testDisjointComparisonCyclesReuseOnlyTheRealCyclePrefixes()
  {comparisonCycles(DateTime.fromIso("2026-01-01T00:00:00Z"),DateTime.fromIso("2025-01-01T00:00:00Z"),"custom")}

  Void testPreviousMonthPreparedCyclesKeepIndependentBillingPrefixes()
  {comparisonCycles(DateTime.fromIso("2026-02-01T00:00:00Z"),DateTime.fromIso("2026-01-01T00:00:00Z"),"previousMonth")}

  private Void comparisonCycles(DateTime current,DateTime previous,Str mode)
  {
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c"],["id":"t","kind":"tariff","categoryId":"c","isDefault":true,"mode":"monthlyBlock","blocks":[["limit":1f,"rate":1f],["rate":3f]]]]
    q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"metering","nodeIds":["m"],"categoryIds":["c"],"_cockpitCategoryId":"c","period":"hour","from":(current+2hr).toIso,"to":(current+4hr).toIso,"asOf":(current+4hr).toIso,"tz":"UTC"]
    reference:=q.dup.setAll(["from":(previous+2hr).toIso,"to":(previous+4hr).toIso])
    comparison:=mode=="previousMonth" ? EnerCubixCockpitMetrics.comparison(["time":["preset":"custom"],"comparison":["mode":mode]],q,TimeZone.utc) : Str:Obj?["mode":"custom","referenceRange":["from":reference["from"],"to":reference["to"]]]
    verifyEq(((Map)comparison["referenceRange"])["from"],reference["from"])
    verifyEq(((Map)comparison["referenceRange"])["to"],reference["to"])
    boundary:=Str:Obj?["meterIds":["m"],"sourcePointIds":["p"]]
    budget:=EnerCubixStreamBudget();registry:=EnerCubixCockpitRegistry(q.toImmutable,rs.toImmutable,boundary.toImmutable,["kpis"],comparison,null,[:],budget,["p":"kWh"],["p"])
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])
    sourceRequest:=q.dup.set("_cockpitReadRanges",[q,reference])
    try
    {
      [previous,current].each |start|
      {
        source:=EnerCubixCockpitStream.openCursor(point,null,start,start+4hr,sourceRequest,rs,budget,|Dict p,Span span,|HisItem| sink| {(0..4).each |i| {at:=start+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(1)))}},registry.planning)
        try {(0..<4).each |i| {a:=start+1hr*i;b:=a+1hr;source.advance(b);EnerCubixCockpitStream.withFrames([source],budget.state) |h,frame| {registry.addFrame(a,b,h,frame)}}}
        finally {source.close}
      }
      registry.finish
      shared:=(EnerCubixCockpitCatalog)EnerCubixCockpitRegistry#.field("catalog").get(registry)
      pool:=(EnerCubixCockpitCapture)EnerCubixCockpitRegistry#.field("pool").get(registry)
      // Completed report owners retain the public result, not the report,
      // period reducers and line definitions captured by their old callbacks.
      ((Str:EnerCubixCockpitReportWork)EnerCubixCockpitRegistry#.field("works").get(registry)).each |work|
      {
        output:=(EnerCubixPreparedOwner)EnerCubixCockpitReportWork#.field("output").get(work)
        drops:=(List)EnerCubixPreparedOwner#.field("drops").get(output)
        verifyEq(drops.size,1,"finished report has one public cleanup root")
        borrowedRoots:=shared.protectedRoots.dup.addAll(pool.protectedRoots)
        verify(output.entries>=publicSize(work.result,borrowedRoots,Obj[,]),"public graph remains fully admitted")
      }
      ["","reference-"].each |prefix|
      {
        query:=prefix.isEmpty ? q : reference
        report:=registry.read(prefix+"profile-cost",EnerCubixCockpitReports.metricQuery(query,"cost",null))
        verifyEq(EnerCubixMath.maps(((Map)report["summary"])["totals"]).first["value"],6f)
        verifyEq(EnerCubixMath.maps(report["rows"]).size,2)
      }
      verifyEq(budget.state.unprepared.val,0);verifyEq(budget.logicalHours,8)
      query:=EnerCubixCockpitReports.metricQuery(q,"cost",null)
      report:=registry.read("profile-cost",query);before:=budget.state.temporary.val
      rows:=(List)report["rows"];row:=(Map)rows.first
      registry.releaseReport("profile-cost");verify(report.isEmpty);verify(budget.state.temporary.val<before)
      verify(rows.isEmpty);verify(row.isEmpty)
      registry.validateReport("profile-cost",query)
      verifyErr(ArgErr#) {registry.read("profile-cost",query)}
      verifyErr(ArgErr#) {registry.validateReport("profile-cost",query.dup.set("from",previous.toIso))}
      registry.releaseReport("profile-cost") // Closing the registry later is also idempotent.
    }
    finally {registry.close}
    verifyEq(budget.state.temporary.val,0)
  }

  private Int publicSize(Obj? value,Obj[] borrowedRoots,Obj[] seen)
  {
    if(value isnot Map && value isnot List) return 0
    if(borrowedRoots.any |r| {r===value} || seen.any |r| {r===value}) return 0
    seen.add(value)
    if(value is Map) return ((Map)value).reduce(1+((Map)value).size) |Int n,v->Int| {n+publicSize(v,borrowedRoots,seen)}
    return ((List)value).reduce(1+((List)value).size) |Int n,v->Int| {n+publicSize(v,borrowedRoots,seen)}
  }

  Void testAbortedCloseInsideFrameCanFinishCleanupAfterTheFrameExpires()
  {
    a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+1hr
    q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"metering","nodeIds":["m"],"categoryIds":["c"],"_cockpitCategoryId":"c","period":"hour","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC"]
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c"]]
    boundary:=Str:Obj?["meterIds":["m"],"sourcePointIds":["p"]]
    budget:=EnerCubixStreamBudget();registry:=EnerCubixCockpitRegistry(q.toImmutable,rs.toImmutable,boundary.toImmutable,["trend"],["mode":"none"],null,[:],budget,["p":"kWh"],["p"])
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])
    source:=EnerCubixCockpitStream.openCursor(point,null,a,b,q,rs,budget,|Dict p,Span span,|HisItem| sink| {(0..1).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(1)))}},registry.planning)
    try
    {
      source.advance(b)
      EnerCubixCockpitStream.withFrames([source],budget.state) |h,frame| {registry.addFrame(a,b,h,frame);verifyErr(ArgErr#) {registry.close}}
      source.close;registry.close;registry.close
      verifyErr(ArgErr#) {registry.finish}
    }
    finally {source.close;registry.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }

  Void testFinalCleaningMetadataIsDetachedAndUsesTheSharedSampleRows()
  {
    a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+4hr
    q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"metering","nodeIds":["m"],"categoryIds":["c"],"_cockpitCategoryId":"c","period":"day","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC"]
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c"]]
    boundary:=Str:Obj?["meterIds":["m"],"sourcePointIds":["p"]]
    key:=EnerCubixCockpitStream.diagnosticKey("p",a,b)
    cleaningPlan:=Str:[Str:Obj?][key:["kind":"cleaningEvents","grain":"cleaningEvent","sourceIds":["p"],"objectIds":["m"],"sourceIdsComplete":true,"reportRefs":["profile-energy"],"requestRange":["from":a.toIso,"to":b.toIso,"asOf":b.toIso]]]
    budget:=EnerCubixStreamBudget();registry:=EnerCubixCockpitRegistry(q.toImmutable,rs.toImmutable,boundary.toImmutable,["trend"],["mode":"none"],null,[:],budget,["p":"kWh"],["p"],cleaningPlan)
    cfg:=Etc.makeDict(["defNull":Marker.val,"deltaMax":Number(1)])
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":cfg])
    raw:=HisItem[,];amount:=0f;(0..240).each |i| {if(i>0) amount+=i%3==0 ? 3f : 0.5f;raw.add(HisItem(a+1min*i,Number(amount)))}
    read:=|Dict p,Span span,|HisItem| sink| {raw.each |r| {if(r.ts>=span.start && r.ts<span.end) sink(r)}}
    source:=EnerCubixCockpitStream.openCursor(point,cfg,a,b,q,rs,budget,read,registry.planning)
    try
    {
      (0..<4).each |i| {start:=a+1hr*i;end:=start+1hr;source.advance(end);EnerCubixCockpitStream.withFrames([source],budget.state) |h,frame| {registry.addFrame(start,end,h,frame)}}
      registry.finish
      verifyErr(ArgErr#) {registry.read("profile-energy",q)}
      source.withCleaningMetadata |meta|
      {
        registry.cleaning("p",a,b,meta)
        report:=registry.read("profile-energy",q);row:=EnerCubixMath.maps(((Map)report["extra"])["cleaning"]).first
        verifyEq(row["rejectedCount"],80);verifyEq(row["pointId"],"p")
        diagnostic:=EnerCubixMath.maps(registry.diagnostics["entries"]).find |entry| {entry["id"]==row["detailsDiagnosticRef"]}
        verifyEq(diagnostic["kind"],"cleaningEvents");verifyEq(diagnostic["returnedCount"],((List)row["details"]).size)
        verify(row["details"] === meta["details"],"sample rows are pool-owned and shared")
        verify(row["summary"] !== meta["summary"],"mutable source counters must be detached")
        ((Map)meta["summary"])["filteredCount"]=999
        verifyEq(((Map)row["summary"])["filteredCount"],80)
        verifyErr(ArgErr#) {registry.cleaning("p",a,b,meta)}
      }
      report:=registry.read("profile-energy",q)
      verifyEq(EnerCubixMath.maps(((Map)report["summary"])["knownTotals"]).first["value"],80f)
      verify((Int)registry.diagnostics["returnedCount"]<=1000);verifyEq(budget.state.unprepared.val,0)
    }
    finally {source.close;registry.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }

  Void testUnimplementedAndMutablePlansRefuseBeforeAnyHistoryAndKeepPeerCharge()
  {
    a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+1hr
    q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"metering","nodeIds":["m"],"categoryIds":["c"],"_cockpitCategoryId":"c","period":"hour","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC"]
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c"]]
    boundary:=Str:Obj?["meterIds":["m"],"sourcePointIds":["p"]]
    budget:=EnerCubixStreamBudget();peer:=EnerCubixPreparedOwner(budget.state);peer.hold(33);before:=budget.state.temporary.val
    try
    {
      verifyErr(ArgErr#) {invalid:=EnerCubixCockpitRegistry(q,rs.toImmutable,boundary.toImmutable,["trend"],["mode":"none"],null,[:],budget,[:],["p"])}
      verifyEq(budget.state.temporary.val,before)
      verifyErr(ArgErr#) {invalid:=EnerCubixCockpitRegistry(q.toImmutable,rs.toImmutable,boundary.toImmutable,["balance"],["mode":"none"],null,[:],budget,[:],["p"])}
      verifyEq(budget.state.temporary.val,before)
      verifyErr(ArgErr#) {invalid:=EnerCubixCockpitRegistry(q.toImmutable,rs.toImmutable,boundary.toImmutable,["unknown-module"],["mode":"none"],null,[:],budget,[:],["p"])}
      verifyEq(budget.state.temporary.val,before);verifyEq(budget.nativeReads,0);verifyNull(budget.diagnosticCapture)
    }
    finally {peer.close}
    verifyEq(budget.state.temporary.val,0)
  }

  Void testCostQueriesConsumeTheirRealBillingPrefixWithoutReportingIt()
  {
    cycle:=DateTime.fromIso("2026-01-01T00:00:00Z");a:=cycle+2hr;b:=cycle+4hr
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c"],["id":"t","kind":"tariff","categoryId":"c","isDefault":true,"mode":"monthlyBlock","blocks":[["limit":1f,"rate":1f],["rate":3f]]]]
    q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"metering","nodeIds":["m"],"categoryIds":["c"],"_cockpitCategoryId":"c","period":"hour","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC"]
    boundary:=Str:Obj?["meterIds":["m"],"sourcePointIds":["p"]]
    budget:=EnerCubixStreamBudget();registry:=EnerCubixCockpitRegistry(q.toImmutable,rs.toImmutable,boundary.toImmutable,["kpis"],["mode":"none"],null,[:],budget,["p":"kWh"],["p"])
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])
    source:=EnerCubixCockpitStream.openCursor(point,null,cycle,b,q,rs,budget,|Dict p,Span span,|HisItem| sink| {(0..4).each |i| {at:=cycle+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(1)))}},registry.planning)
    try
    {
      (0..<4).each |i| {start:=cycle+1hr*i;end:=start+1hr;source.advance(end);EnerCubixCockpitStream.withFrames([source],budget.state) |h,frame| {registry.addFrame(start,end,h,frame)}}
      source.close;registry.finish
      report:=registry.read("profile-cost",EnerCubixCockpitReports.metricQuery(q,"cost",null))
      verifyEq(EnerCubixMath.maps(((Map)report["summary"])["totals"]).first["value"],6f)
      verifyEq(EnerCubixMath.maps(report["rows"]).size,2)
      rows:=[Str:Obj?][,];(0..<4).each |i| {rows.add(["ts":(cycle+1hr*i).toIso,"value":1f])}
      expected:=EnerCubixEngine.report(q.dup.set("metric","cost"),rs,[["pointId":"p","mode":"interval","unit":"kWh","samples":rows]])
      ["summary","rows","series","warnings"].each |key| {verifyEq(report[key],expected[key],key)}
      verifyEq(budget.state.unprepared.val,0)
    }
    finally {source.close;registry.close}
    verifyEq(budget.state.temporary.val,0)
  }

  Void testModuleReportsConsumeOneFrameScheduleAndRouteWithoutWholeHistories()
  {
    a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+48hr
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"sub","kind":"subcategory","categoryId":"c","co2Factor":0.5f],["id":"s","kind":"space","area":100f],["id":"cal","kind":"calendar","workHours":[1,2],"workDays":[1,2,3,4,5]],["id":"t","kind":"tariff","categoryId":"c","isDefault":true,"mode":"flat","rate":0.75f]]
    (0..<2).each |i| {rs.add(["id":"m$i","kind":"meter","name":"Meter $i","pointId":"p$i","categoryId":"c","subcategoryId":"sub","spaceId":"s","nativeSpaceId":"s","nativeTreeParentId":"s","nativeEquip":true])}
    input:=Str:Obj?["schemaVersion":1,"requestId":"registry","reportScope":["dimension":"space","nodeIds":["s"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"day","from":a.toIso,"to":b.toIso],"asOf":b.toIso,"modules":["kpis","trend","space","time","endUse","organization"],"comparison":["mode":"none"]]
    q:=EnerCubixCockpit.query(input,"test",TimeZone.utc,b).setAll(["categoryIds":["c"],"_cockpitCategoryId":"c","_cockpitExplicitObjects":false])
    boundary:=Str:Obj?["id":"boundary","meterIds":["m0","m1"],"sourcePointIds":["p0","p1"],"aggregateAllowed":true]
    budget:=EnerCubixStreamBudget()
    registry:=EnerCubixCockpitRegistry(q.toImmutable,rs.toImmutable,boundary.toImmutable,(Str[])input["modules"],["mode":"none"],null,[:],budget,["p0":"kWh","p1":"kWh"],["p0","p1"])
    verifyEq(registry.keys.sort,["face-daily","face-endUse","face-heatmap","face-meter-profile","face-workingDays","face-workingHours","profile-area","profile-co2","profile-cost","profile-energy","space-summary"].sort)
    verifyErr(ArgErr#) {registry.read("profile-energy",q)}
    sources:=EnerCubixCockpitStream[,];calls:=0
    read:=|Dict p,Span span,|HisItem| sink| {(0..48).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) {calls++;sink(HisItem(at,Number(1)))}}}
    try
    {
      (0..<2).each |i|
      {point:=Etc.makeDict(["id":Ref("p$i"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"]);sources.add(EnerCubixCockpitStream.openCursor(point,null,a,b,q,rs,budget,read,registry.planning))}
      (0..<48).each |i|
      {
        start:=a+1hr*i;end:=start+1hr;sources.each |source| {source.advance(end)}
        EnerCubixCockpitStream.withFrames(sources,budget.state) |histories,frame| {registry.addFrame(start,end,histories,frame)}
      }
      sources.each |source| {source.close};registry.finish
      whole:=[Str:Obj?][,];meta:=[Str:Obj?][,]
      (0..<2).each |i|
      {rows:=[Str:Obj?][,];(0..<48).each |h| {rows.add(["ts":(a+1hr*h).toIso,"value":1f])};whole.add(["pointId":"p$i","unit":"kWh","mode":"interval","samples":rows]);meta.add(["pointId":"p$i","unit":"kWh","mode":"interval"])}
      expected:=EnerCubixCockpit.execute(input,rs,|rq,saved->[Str:Obj?][]| {whole},"test",TimeZone.utc,b)
      actual:=EnerCubixCockpit.execute(input,rs,|rq,saved->[Str:Obj?][]| {meta},"test",TimeZone.utc,b,false,null,null,null,null,[:],|key,rq->Str:Obj?| {registry.read(key,rq)})
      expectedReports:=(Map)expected["reports"];actualReports:=(Map)actual["reports"]
      verifyEq(actualReports.keys.sort,expectedReports.keys.sort)
      actualReports.each |raw,key|
      {
        report:=(Map)raw;before:=(Map)expectedReports[key]
        ["kind","from","to","asOf","period","summary","series","rows","warnings"].each |field| {verifyEq(report[field],before[field],key.toStr+"/"+field)}
        extra:=(Map)report["extra"];oldExtra:=(Map)before["extra"]
        oldExtra.each |value,field| {if(field!="knownUsage") verifyEq(extra[field],value,key.toStr+"/extra/"+field)}
      }
      time:=(Map)((Map)((Map)actual["modules"])["time"])["data"]
      verifyEq(time["heatmap"],((Map)((Map)((Map)expected["modules"])["time"])["data"])["heatmap"])
      verifyEq(((List)time["heatmap"]).size,48)
      verifyEq(calls,98);verifyEq(budget.state.unprepared.val,0)
      verify((Int)registry.diagnostics["returnedCount"] <= 1000)
      verifyErr(ArgErr#) {registry.read("not-planned",q)}
      verifyErr(ArgErr#) {registry.read("profile-energy",q.dup.set("period","hour"))}
      echo("MODULE_REGISTRY "+budget.evidence)
    }
    finally {sources.each |source| {source.close};registry.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
}

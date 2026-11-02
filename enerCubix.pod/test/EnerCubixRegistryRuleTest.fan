using haystack
using util

class EnerCubixRegistryRuleTest : Test
{
  Void testNineModulesShareSourcesAndRuleProjectionNeverFallsBackToHeaders()
  {
    a:=DateTime.fromIso("2026-10-01T00:00:00Z");b:=a+2hr
    rs:=[Str:Obj?][["id":"cn","kind":"category","unit":"MWh"],["id":"cd","kind":"category","unit":"kWh"],["id":"s","kind":"space","nativeSourceKind":"site","area":1000f],["id":"n","kind":"meter","nativeEquip":true,"nativeTreeParentId":"s","nativeSpaceId":"s","spaceId":"s","categoryId":"cn","pointId":"pn"],["id":"d","kind":"meter","nativeEquip":true,"nativeTreeParentId":"s","nativeSpaceId":"s","spaceId":"s","categoryId":"cd","pointId":"pd"],["id":"cal","kind":"calendar","workDays":[1,2,3,4,5],"workHours":[9,10,11,12,13,14,15,16,17]],["id":"cop","kind":"cop","numeratorId":"n","denominatorId":"d"],["id":"tariff","kind":"tariff","categoryId":"cd","mode":"flat","isDefault":true,"rate":1f]]
    q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"space","spaceSource":"fin","nodeIds":["s"],"categoryIds":["cd"],"_cockpitCategoryId":"cd","period":"day","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC","_cockpitNeedsRuleFacts":true]
    boundary:=Str:Obj?["id":"boundary","meterIds":["d"],"sourcePointIds":["pd"],"aggregateAllowed":true]
    profile:=Str:Obj?["id":"rule","version":1,"name":"Night usage","scopeKind":"project","scopeRef":"p:test","categoryRef":"cd","calendarRef":"cal","ruleType":"nonWorkingHighUsage","threshold":20f,"thresholdUnit":"kWh","enabled":true]
    owned:=Str:Obj?["rules":[profile,profile.dup.setAll(["id":"disabled","enabled":false]),profile.dup.setAll(["id":"pressure","ruleType":"budgetVariance","currency":"CNY","thresholdUnit":"%","threshold":5f])],"rulesComplete":true,"modelComplete":true,"projectRef":"p:test"]
    points:=Str:Dict[:]
    ["pn","pd"].each |id| {points[id]=Etc.makeDict(["id":Ref(id),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":id=="pn" ? "MWh" : "kWh","tz":"UTC"])}
    read:=|Dict point,Span span,|HisItem| sink| {(0..2).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(point.id.id=="pn" ? 0.1f*i : 10f*i*i)))}}
    budgetResult:=Str:Obj?["status":"ok","variancePct":12f,"currency":"CNY","periodBudget":100f,"periodActualCost":112f,"configRefs":[["id":"budget","version":1]],"costReportRef":"budget-canonical-cost"]
    expected:=EnerCubixCockpitRules.project(q,rs,EnerCubixCockpitStream.prepare(q,rs,points,[:],read,EnerCubixStreamBudget()),owned,boundary,budgetResult,"snapshot")
    cop:=EnerCubixCockpitEfficiency.prepare(q,rs,"test",["cd","cn"]);flow:=EnerCubixCockpitFlow.prepare(q,rs,"test",true)
    budget:=EnerCubixStreamBudget()
    registry:=EnerCubixCockpitRegistry(q.toImmutable,rs.toImmutable,boundary.toImmutable,["kpis","trend","space","time","endUse","organization","balance","efficiency","issues"],["mode":"none"],null,owned.toImmutable,budget,["pn":"MWh","pd":"kWh"],points.keys,[:],flow.toImmutable,cop.toImmutable)
    sources:=EnerCubixCockpitStream[,]
    try
    {
      verifyEq(budget.nativeReads,0);verifyErr(ArgErr#) {registry.ruleData("rule")}
      points.keys.sort.each |id| {sources.add(EnerCubixCockpitStream.openCursor(points[id],null,a,b,q,rs,budget,read,registry.planning))}
      (0..<2).each |i| {start:=a+1hr*i;end:=start+1hr;sources.each |source| {source.advance(end)};EnerCubixCockpitStream.withFrames(sources,budget.state) |h,frame| {registry.addFrame(start,end,h,frame)}}
      sources.each |source| {source.close};registry.finish
      calls:=0
      actual:=EnerCubixCockpitRules.project(q,rs,[Str:Obj?][,],owned,boundary,budgetResult,"snapshot",|Str id->Str:Obj?| {calls++;return registry.ruleData(id)})
      verifyEq(json(actual),json(expected));verifyEq(calls,1)
      evaluation:=EnerCubixMath.maps(actual["evaluations"]).find |e| {e["id"]=="rule"}
      verifyEq(evaluation["status"],"triggered");verifyEq(evaluation["actual"],40f)
      verifyEq(registry.read("cop:cop",EnerCubixCockpitReports.copQuery(q,"cop"))["kind"],"cop")
      verifyEq(registry.read("energy-flow",(Str:Obj?)flow["request"])["kind"],"energyFlow")
      verifyErr(ArgErr#) {registry.ruleData("disabled")};verifyErr(ArgErr#) {registry.ruleData("pressure")};verifyErr(ArgErr#) {registry.ruleData("unknown")}
      verifyEq(budget.nativeReads,2);verifyEq(budget.state.unprepared.val,0);verify((Int)registry.diagnostics["returnedCount"]<=1000)
      facts:=registry.ruleData("rule");registry.close;verify(facts.isEmpty)
    }
    finally {sources.each |source| {source.close};registry.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
  Void testMutableRulesAreRejectedBeforeIoWithoutReleasingPeer()
  {
    a:=DateTime.fromIso("2026-10-01T00:00:00Z");b:=a+1hr
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","categoryId":"c","pointId":"p"]]
    q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"metering","nodeIds":["m"],"categoryIds":["c"],"_cockpitCategoryId":"c","period":"day","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC"]
    budget:=EnerCubixStreamBudget();peer:=EnerCubixPreparedOwner(budget.state);peer.hold(37);before:=budget.state.temporary.val
    try
    {
      verifyErr(ArgErr#) {invalid:=EnerCubixCockpitRegistry(q.toImmutable,rs.toImmutable,Str:Obj?["id":"boundary","meterIds":["m"],"sourcePointIds":["p"]].toImmutable,["issues"],["mode":"none"],null,Str:Obj?[:],budget,[:],["p"])}
      verifyEq(budget.state.temporary.val,before);verifyEq(budget.nativeReads,0);verifyNull(budget.diagnosticCapture)
    }
    finally {peer.close}
    verifyEq(budget.state.temporary.val,0)
  }
  private Obj? json(Obj? value) {JsonInStream(JsonOutStream.writeJsonToStr(value).in).readJson}
}

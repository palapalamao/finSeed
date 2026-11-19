class FinEnergyTemporalBalanceTest : Test
{
  Void testCurrentCategoryUnitAppliesAcrossTheWholeRange()
  {
    before:=records.findAll |r| { r["id"] == "electric" || r["id"] == "m" }
    [Str:Obj?][] after:=before.map |r->[Str:Obj?]| { r.dup }
    after.find |r| { r["id"] == "electric" }["unit"]="MWh"
    req:=request("energyFlow",2); req["meterHistorySegments"]=[segment(0,1,before),segment(1,2,after)]
    result:=FinEnergyEngine.report(req,after,[closedHistory("pm",[10f,20f])])
    row:=FinEnergyMath.maps(result["rows"]).first
    near(row["value"],0.03f); verifyEq(row["unit"],"MWh")
  }
  Void testOwnOverviewDoesNotInventPartialCounterIntervals()
  {
    rs:=records.findAll |r| { r["id"] == "electric" || r["id"] == "m" }
    req:=request("energyFlow",3); req["from"]=(DateTime.fromIso(ts(0))+30min).toIso; req["to"]=(DateTime.fromIso(ts(2))+30min).toIso
    req["meterHistorySegments"]=[["from":req["from"],"to":req["to"],"known":false]]
    result:=FinEnergyEngine.report(req,rs,[history("pm",[0f,10f,30f,60f])])
    row:=FinEnergyMath.maps(result["rows"]).first
    near(row["value"],20f); near(row["coverage"],0.5f)
  }
  Void testUnknownTopologyLogKeepsCurrentTreeAndOwnSubtotals()
  {
    rs:=records.findAll |r| { r["id"] != "c" }
    req:=request("energyFlow",4); req["nodeIds"]=Str[,]
    req["meterHistorySegments"]=[["from":ts(0),"to":ts(4),"known":false]]
    result:=FinEnergyEngine.report(req,rs,[closedHistory("pm",[10f,null,0f,30f]),closedHistory("pa",[5f,6f,0f,9f])])
    overview:=((Map)result["extra"])["energyFlowOverview"] as Map
    verifyNotNull(overview)
    rows:=FinEnergyMath.maps(result["rows"])
    verifyEq(rows.size,2)
    main:=rows.find |r| { r["nodeId"] == "m" }
    near(main["value"],40f); near(main["coverage"],0.75f)
    verifyEq(main["complete"],false); near(main["coveredSeconds"],10800f)
    near(rows.find |r| { r["nodeId"] == "a" }["value"],20f)
    graph:=(Map)((Map)result["extra"])["energyFlow"]
    verify(FinEnergyMath.maps(graph["nodes"]).any |n| { n["id"] == "a" })
    verify(!FinEnergyMath.maps(graph["links"]).isEmpty)
    verifyNull(((Map)result["extra"])["energyFlowSegments"])
    verifyEq(graph["unit"],"kWh")
    verifyEq(FinEnergyMath.strings(FinEnergyDimension.dependencies(req,rs)["points"]),["pa","pm"])
  }

  Void testDeletionLogDoesNotReviveTheRemovedChildOrItsBinding()
  {
    before:=records.findAll |r| { r["id"] != "c" }
    after:=before.findAll |r| { r["id"] != "a" }
    req:=request("energyFlow",3); req["nodeIds"]=Str[,]
    req["meterHistorySegments"]=[segment(0,1,before),segment(1,3,after)]
    hs:=[closedHistory("pm",[10f,20f,30f]),closedHistory("pa",[5f,999f,999f])]
    result:=FinEnergyEngine.report(req,after,hs)
    rows:=FinEnergyMath.maps(result["rows"])
    main:=rows.find |r| { r["nodeId"] == "m" }; child:=rows.find |r| { r["nodeId"] == "a" }
    verifyNull(child); near(main["value"],60f)
    verifyEq(rows.size,1); verifyEq(main["complete"],true)
    plan:=FinEnergyDimension.dependencies(req,after)
    verifyEq(FinEnergyMath.strings(plan["points"]),["pm"])
    req["nodeIds"]=["a"]
    verifyErr(ArgErr#) { FinEnergyEngine.report(req,after,hs) }
  }

  Void testCurrentBindingAppliesAcrossTheRangeAndKeepsZeroNaAndSubstitutionDistinct()
  {
    before:=records.findAll |r| { r["id"] == "electric" || r["id"] == "m" }
    [Str:Obj?][] after:=before.map |r->[Str:Obj?]| { r.dup }
    after.find |r| { r["id"] == "m" }["pointId"]="new"
    req:=request("energyFlow",4); req["nodeIds"]=Str[,]
    req["meterHistorySegments"]=[segment(0,2,before),segment(2,4,after)]
    old:=closedHistory("pm",[999f,999f,900f,900f])
    newer:=closedHistory("new",[0f,null,4f,6f])
    intervals:=FinEnergyMath.maps(newer["intervals"]); intervals[3]["quality"]="substituted"
    intervals[1]["valueType"]="na"; intervals[1]["quality"]="na"
    newer["intervals"]=intervals
    result:=FinEnergyEngine.report(req,after,[old,newer])
    row:=FinEnergyMath.maps(result["rows"]).first
    near(row["value"],10f); near(row["coverage"],0.75f)
    verifyEq(row["quality"],"substituted")
    verify(FinEnergyMath.maps(row["periods"]).any |p| { p["quality"] == "na" && p["value"] == null })
    verify(FinEnergyMath.maps(row["periods"]).any |p| { p["value"] == 0f })
    verify(FinEnergyMath.maps(row["periods"]).all |p| { p["pointId"] == "new" })
    plan:=FinEnergyDimension.dependencies(req,after)
    verifyEq(FinEnergyMath.strings(plan["points"]),["new"])
  }

  Void testCurrentNativeBindingSuppressesItsLegacyAlias()
  {
    rs:=records.findAll |r| { r["id"] != "c" }
    rs.find |r| { r["id"] == "m" }["nativeEquip"]=true
    rs.find |r| { r["id"] == "a" }["nativeEquip"]=true
    rs.add(["id":"old-m","kind":"meter","name":"Old total","pointId":"pm","categoryId":"electric","unit":"kWh"])
    rs.add(["id":"old-a","kind":"meter","name":"Old branch","pointId":"pa","categoryId":"electric","unit":"kWh","meterParentId":"old-m"])
    req:=request("energyFlow",1); req["nodeIds"]=Str[,]; req["meterHistorySegments"]=[segment(0,1,rs)]
    result:=FinEnergyEngine.report(req,rs,[closedHistory("pm",[100f]),closedHistory("pa",[80f])])
    graph:=(Map)((Map)result["extra"])["energyFlow"]
    verifyEq(FinEnergyMath.maps(graph["unassigned"]).size,0)
    verifyFalse(FinEnergyMath.maps(graph["nodes"]).any |n| { n["id"] == "old-m" || n["id"] == "old-a" })
    near(FinEnergyMath.maps(graph["nodes"]).first["value"],100f)
  }

  Void testCurrentTreeUsesOneWholeQueryGraphAndPreservesKnownAmountsAcrossGaps()
  {
    rs:=records.findAll |r| { r["id"] != "c" }
    req:=request("energyFlow",4); req["from"]=ts(-1); req["to"]=(DateTime.fromIso(ts(4))+50sec).toIso
    req["meterHistorySegments"]=[["from":ts(-1),"to":ts(0),"known":false], ["from":ts(0),"to":req["to"],"known":true,"records":rs]]
    hs:=[closedHistory("pm",[100f,null,60f,70f]),closedHistory("pa",[80f,null,50f,60f])]
    result:=FinEnergyEngine.report(req,rs,hs)
    verifyNull(((Map)result["extra"])["energyFlowSegments"])
    graph:=(Str:Obj?)((Map)result["extra"])["energyFlow"]
    main:=FinEnergyMath.maps(graph["nodes"]).find |n| { n["id"] == "m" }
    verifyNull(main["value"]); near(main["knownValue"],230f)
    verifyNull(main["difference"])
    verify(!FinEnergyMath.maps(graph["links"]).isEmpty)
    verifyEq(result["from"],ts(-1)); verifyEq(result["to"],req["to"])
  }

  Void testDifferentIntervalCadencesUseCommonBoundariesAndKeepZeroComplete()
  {
    rs:=records.findAll |r| { r["id"] != "c" }
    req:=request("energyFlow",1)
    req["meterHistorySegments"]=[segment(0,1,rs)]
    a:=DateTime.fromIso(ts(0))
    main:=closedHistory("pm",[0f])
    child:=[Str:Obj?]["pointId":"pa","unit":"kWh","mode":"interval","intervals":[["from":a.toIso,"to":(a+30min).toIso,"value":0f,"quality":"cleaned"],["from":(a+30min).toIso,"to":(a+1hr).toIso,"value":0f,"quality":"cleaned"]]]
    result:=FinEnergyEngine.report(req,rs,[main,child])
    verifyNull(((Map)result["extra"])["energyFlowSegments"])
    graph:=(Str:Obj?)((Map)result["extra"])["energyFlow"]
    near(FinEnergyMath.maps(graph["nodes"]).find |n| { n["id"] == "m" }["value"],0f)
    verifyEq(FinEnergyMath.maps(graph["links"]).size,0)
  }

  private Str:Obj? closedHistory(Str id, Float?[] values)
  {
    rows:=values.map |value,i->[Str:Obj?]| { ["from":ts(i),"to":ts(i+1),"value":value,"valueType":value == null ? "null" : "number","quality":value == null ? "filtered" : "cleaned"] }
    return ["pointId":id,"unit":"kWh","mode":"interval","quality":"derived","intervals":rows]
  }

  Void testVirtualSumIsAConsistencyCheckRatherThanIndependentLoss()
  {
    rs:=records; rs.find |r| { r["id"] == "m" }["autoSum"]=true
    flow:=FinEnergyEngine.report(request("energyFlow",1),rs,histories)
    n:=FinEnergyMath.maps(((Str:Obj?)((Str:Obj?)flow["extra"])["energyFlow"])["nodes"]).find |r| { r["id"] == "m" }
    verifyEq(n["balanceMode"],"consistency")
    verifyEq(n["lossEligible"],false)
    leak:=FinEnergyEngine.report(request("leak",1),rs,histories)
    row:=FinEnergyMath.maps(leak["rows"]).first
    verifyEq(row["balanceMode"],"consistency")
    verifyEq(row["lossEligible"],false)
    verifyNull(row["percentage"])
  }

  Void testCurrentMembershipKeepsEarlierMissingChildIntervalsIncomplete()
  {
    rs:=records; before:=rs.findAll |r| { r["id"] != "c" }
    req:=request("leak",2); req["meterHistorySegments"]=[segment(0,1,before),segment(1,2,rs)]
    report:=FinEnergyEngine.report(req,rs,histories)
    row:=FinEnergyMath.maps(report["rows"]).first
    near(row["total"],220f); near(row["knownSubmeter"],200f)
    verifyNull(row["submeter"]); verifyNull(row["difference"]); verifyNull(row["percentage"])
    verifyEq(row["membershipQuality"],"ok"); verifyEq(row["lossEligible"],false)
    verifyEq(FinEnergyMath.maps(report["rows"]).size,1)
  }

  Void testFlowUsesTheCurrentTreeAcrossTheWholeRange()
  {
    rs:=records; before:=rs.findAll |r| { r["id"] != "c" }
    req:=request("energyFlow",2); req["meterHistorySegments"]=[segment(0,1,before),segment(1,2,rs)]
    report:=FinEnergyEngine.report(req,rs,histories)
    verifyNull(((Map)report["extra"])["energyFlowSegments"])
    nodes:=FinEnergyMath.maps(((Map)((Map)report["extra"])["energyFlow"])["nodes"])
    verify(nodes.any |r| {r["id"] == "c"})
    verifyNull(nodes.find |r| {r["id"] == "c"}["value"])
    near(nodes.find |r| {r["id"] == "c"}["knownValue"],40f)
    near(nodes.find |r| {r["id"] == "m"}["value"],220f)
  }

  Void testUnknownTopologyLogDoesNotHideCurrentBranchesOrInventMissingData()
  {
    req:=request("energyFlow",1); req["meterHistorySegments"]=[["from":ts(0),"to":ts(1),"known":false]]
    report:=FinEnergyEngine.report(req,records,histories)
    flow:=(Str:Obj?)((Str:Obj?)report["extra"])["energyFlow"]
    ns:=FinEnergyMath.maps(flow["nodes"])
    verifyEq(FinEnergyMath.maps(flow["links"]).size,1)
    verify(ns.any |r| { r["id"] == "a" })
    verify(ns.any |r| { r["id"] == "c" })
    verifyNull(ns.find |r| { r["id"] == "c" }["value"])
    n:=ns.find |r| { r["id"] == "m" }
    near(n["value"],100f); verifyEq(n["hasChildren"],true)
    verify(n["balanceQuality"] != "topologyUnknown"); verifyEq(n["lossEligible"],false)
  }

  Void testHistoryPlanIgnoresRetiredPointsFromTopologyLogs()
  {
    rs:=records; old:=records; old.find |r| { r["id"] == "m" }["pointId"]="old-pm"
    req:=request("energyFlow",2); req["meterHistorySegments"]=[segment(0,1,old),segment(1,2,rs)]
    plan:=FinEnergyDimension.dependencies(req,rs)
    verifyEq(plan["points"],["pa","pc","pm"])
  }

  Void testFormulaArchiveIsAuthoritativeAndMissingArchiveNeverFallsBack()
  {
    rs:=records
    rs.add(["id":"f","kind":"meter","name":"Formula","pointId":"pf","expressionId":"expr","categoryId":"electric","unit":"kWh"])
    rs.add(["id":"expr","kind":"expression","name":"Expr","formula":"a","variables":["a":"a"]])
    req:=request("profile",1); req["nodeIds"]=["f"]
    hs:=histories.add(history("pf",[0f,15f,30f]))
    report:=FinEnergyEngine.report(req,rs,hs)
    near(FinEnergyMath.maps(report["rows"]).first["value"],15f)
    missing:=FinEnergyEngine.report(req,rs,histories)
    verifyNull(FinEnergyMath.maps(missing["rows"]).first["value"])
    plan:=FinEnergyDimension.dependencies(req,rs)
    verifyEq(plan["points"],["pf"])
  }

  Void testIncompleteBranchCannotBecomeACompleteMergedLoss()
  {
    rs:=records; before:=rs.findAll |r| { r["id"] != "c" }
    req:=request("leak",2); req["meterHistorySegments"]=[segment(0,1,before),segment(1,2,rs)]
    hs:=histories; hs.find |h| { h["pointId"] == "pa" }["quality"]="filtered"
    report:=FinEnergyEngine.report(req,rs,hs)
    row:=FinEnergyMath.maps(report["rows"]).first
    near(row["total"],220f)
    verifyNull(row["submeter"]); verifyNull(row["difference"]); verifyNull(row["percentage"])
    verifyEq(row["lossEligible"],false)
  }

  Void testNegativeDifferenceRemainsSignedAndCannotBecomeALossClaim()
  {
    rs:=records.findAll |r| { r["id"] != "c" }
    hs:=histories; hs[0]=history("pm",[0f,50f,100f])
    report:=FinEnergyEngine.report(request("leak",1),rs,hs)
    row:=FinEnergyMath.maps(report["rows"]).first
    near(row["difference"],-30f); verifyEq(row["lossEligible"],false)
  }

  private Str:Obj? request(Str kind,Int hours)
  { ["kind":kind,"dimension":"metering","nodeIds":["m"],"categoryId":"electric","from":ts(0),"to":ts(hours),"period":"day","metric":"energy","perArea":false,"tz":"UTC"] }
  private Str:Obj? segment(Int from,Int to,[Str:Obj?][] rs)
  { ["from":ts(from),"to":ts(to),"known":true,"records":rs] }
  private [Str:Obj?][] records()
  { [["id":"electric","kind":"category","name":"Electric","unit":"kWh"],["id":"m","kind":"totalMeter","name":"M","pointId":"pm","categoryId":"electric","unit":"kWh"],["id":"a","kind":"meter","name":"A","pointId":"pa","meterParentId":"m","categoryId":"electric","unit":"kWh"],["id":"c","kind":"meter","name":"C","pointId":"pc","meterParentId":"m","categoryId":"electric","unit":"kWh"]] }
  private [Str:Obj?][] histories()
  { [history("pm",[0f,100f,220f]),history("pa",[0f,80f,160f]),["pointId":"pc","unit":"kWh","mode":"cumulative","samples":[["ts":ts(1),"value":1000f],["ts":ts(2),"value":1040f]]]] }
  private Str:Obj? history(Str point,Float[] values)
  { ["pointId":point,"unit":"kWh","mode":"cumulative","samples":values.map |v,i->[Str:Obj?]| { ["ts":ts(i),"value":v] }] }
  private Str ts(Int hour) { (DateTime.fromIso("2026-10-25T00:00:00Z")+Duration(hour*1hr.ticks)).toIso }
  private Void near(Obj? actual,Float expected) { verifyNotNull(actual); verify((((Float)actual)-expected).abs < 0.000001f) }
}

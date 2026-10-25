class EnerCubixTemporalBalanceTest : Test
{
  Void testCategoryUnitChangesDoNotAddDifferentScales()
  {
    before:=records.findAll |r| { r["id"] == "electric" || r["id"] == "m" }
    [Str:Obj?][] after:=before.map |r->[Str:Obj?]| { r.dup }
    after.find |r| { r["id"] == "electric" }["unit"]="MWh"
    req:=request("energyFlow",2); req["meterHistorySegments"]=[segment(0,1,before),segment(1,2,after)]
    result:=EnerCubixEngine.report(req,after,[closedHistory("pm",[10f,20f])])
    row:=EnerCubixMath.maps(result["rows"]).first
    near(row["value"],0.03f); verifyEq(row["unit"],"MWh")
  }
  Void testOwnOverviewDoesNotInventPartialCounterIntervals()
  {
    rs:=records.findAll |r| { r["id"] == "electric" || r["id"] == "m" }
    req:=request("energyFlow",3); req["from"]=(DateTime.fromIso(ts(0))+30min).toIso; req["to"]=(DateTime.fromIso(ts(2))+30min).toIso
    req["meterHistorySegments"]=[["from":req["from"],"to":req["to"],"known":false]]
    result:=EnerCubixEngine.report(req,rs,[history("pm",[0f,10f,30f,60f])])
    row:=EnerCubixMath.maps(result["rows"]).first
    near(row["value"],20f); near(row["coverage"],0.5f)
  }
  Void testWholeRangeOverviewKeepsOwnSubtotalsWhenPastTopologyIsUnknown()
  {
    rs:=records.findAll |r| { r["id"] != "c" }
    req:=request("energyFlow",4); req["nodeIds"]=Str[,]
    req["meterHistorySegments"]=[["from":ts(0),"to":ts(4),"known":false]]
    result:=EnerCubixEngine.report(req,rs,[closedHistory("pm",[10f,null,0f,30f]),closedHistory("pa",[5f,6f,0f,9f])])
    overview:=((Map)result["extra"])["energyFlowOverview"] as Map
    verifyNotNull(overview)
    rows:=EnerCubixMath.maps(result["rows"])
    verifyEq(rows.size,2)
    main:=rows.find |r| { r["nodeId"] == "m" }
    near(main["value"],40f); near(main["coverage"],0.75f)
    verifyEq(main["complete"],false); near(main["coveredSeconds"],10800f)
    near(rows.find |r| { r["nodeId"] == "a" }["value"],20f)
    graph:=(Map)EnerCubixMath.maps(((Map)result["extra"])["energyFlowSegments"]).first["energyFlow"]
    verifyEq(EnerCubixMath.maps(graph["nodes"]).size,2)
    verifyEq(EnerCubixMath.maps(graph["links"]).size,0)
    verifyEq(graph["unit"],"kWh")
    verifyEq(EnerCubixMath.strings(EnerCubixDimension.dependencies(req,rs)["points"]),["pa","pm"])
  }

  Void testDeletionRetainsPastOwnHistoryAndDoesNotUseChildAfterRemoval()
  {
    before:=records.findAll |r| { r["id"] != "c" }
    after:=before.findAll |r| { r["id"] != "a" }
    req:=request("energyFlow",3); req["nodeIds"]=Str[,]
    req["meterHistorySegments"]=[segment(0,1,before),segment(1,3,after)]
    hs:=[closedHistory("pm",[10f,20f,30f]),closedHistory("pa",[5f,999f,999f])]
    result:=EnerCubixEngine.report(req,after,hs)
    rows:=EnerCubixMath.maps(result["rows"])
    main:=rows.find |r| { r["nodeId"] == "m" }; child:=rows.find |r| { r["nodeId"] == "a" }
    verifyNotNull(child); near(main["value"],60f); near(child["value"],5f)
    verifyEq(child["removed"],true); near(child["activeSeconds"],3600f)
    verifyEq(child["complete"],true)
    plan:=EnerCubixDimension.dependencies(req,after)
    verify(EnerCubixMath.strings(plan["points"]).contains("pa"))
    req["nodeIds"]=["a"]
    focused:=EnerCubixEngine.report(req,after,hs)
    near(EnerCubixMath.maps(focused["rows"]).first["value"],5f)
  }

  Void testRebindingUsesEachEffectiveOwnArchiveAndKeepsNaAndSubstitutionDistinct()
  {
    before:=records.findAll |r| { r["id"] == "electric" || r["id"] == "m" }
    [Str:Obj?][] after:=before.map |r->[Str:Obj?]| { r.dup }
    after.find |r| { r["id"] == "m" }["pointId"]="new"
    req:=request("energyFlow",4); req["nodeIds"]=Str[,]
    req["meterHistorySegments"]=[segment(0,2,before),segment(2,4,after)]
    old:=closedHistory("pm",[0f,null,900f,900f])
    newer:=closedHistory("new",[999f,999f,4f,6f])
    intervals:=EnerCubixMath.maps(newer["intervals"]); intervals[3]["quality"]="substituted"
    newer["intervals"]=intervals
    intervals=EnerCubixMath.maps(old["intervals"]); intervals[1]["valueType"]="na"; intervals[1]["quality"]="na"; old["intervals"]=intervals
    result:=EnerCubixEngine.report(req,after,[old,newer])
    row:=EnerCubixMath.maps(result["rows"]).first
    near(row["value"],10f); near(row["coverage"],0.75f)
    verifyEq(row["quality"],"substituted")
    verify(EnerCubixMath.maps(row["periods"]).any |p| { p["quality"] == "na" && p["value"] == null })
    plan:=EnerCubixDimension.dependencies(req,after)
    verifyEq(EnerCubixMath.strings(plan["points"]),["new","pm"])
  }

  Void testCapturedNativeBindingSuppressesItsLegacyAliasWithoutTodaysMapping()
  {
    rs:=records.findAll |r| { r["id"] != "c" }
    rs.find |r| { r["id"] == "m" }["nativeEquip"]=true
    rs.find |r| { r["id"] == "a" }["nativeEquip"]=true
    rs.add(["id":"old-m","kind":"meter","name":"Old total","pointId":"pm","categoryId":"electric","unit":"kWh"])
    rs.add(["id":"old-a","kind":"meter","name":"Old branch","pointId":"pa","categoryId":"electric","unit":"kWh","meterParentId":"old-m"])
    req:=request("energyFlow",1); req["nodeIds"]=Str[,]; req["meterHistorySegments"]=[segment(0,1,rs)]
    result:=EnerCubixEngine.report(req,rs,[closedHistory("pm",[100f]),closedHistory("pa",[80f])])
    graph:=(Map)EnerCubixMath.maps(((Map)result["extra"])["energyFlowSegments"]).first["energyFlow"]
    verifyEq(EnerCubixMath.maps(graph["unassigned"]).size,0)
    verifyFalse(EnerCubixMath.maps(graph["nodes"]).any |n| { n["id"] == "old-m" || n["id"] == "old-a" })
    near(EnerCubixMath.maps(graph["nodes"]).first["value"],100f)
  }

  Void testTodayKeepsUnknownPastAndGapsSeparateFromCompleteFlowWindows()
  {
    rs:=records.findAll |r| { r["id"] != "c" }
    req:=request("energyFlow",4); req["from"]=ts(-1); req["to"]=(DateTime.fromIso(ts(4))+50sec).toIso
    req["meterHistorySegments"]=[["from":ts(-1),"to":ts(0),"known":false], ["from":ts(0),"to":req["to"],"known":true,"records":rs]]
    hs:=[closedHistory("pm",[100f,null,60f,70f]),closedHistory("pa",[80f,null,50f,60f])]
    result:=EnerCubixEngine.report(req,rs,hs)
    parts:=EnerCubixMath.maps(((Map)result["extra"])["energyFlowSegments"])
    verifyEq(parts.size,5)
    verifyEq(parts[0]["known"],false)
    verifyEq(parts[1]["from"],ts(0)); verifyEq(parts[1]["to"],ts(1))
    verifyEq(parts[2]["from"],ts(1)); verifyEq(parts[2]["to"],ts(2))
    verifyEq(parts[3]["from"],ts(2)); verifyEq(parts[3]["to"],ts(4))
    graph:=(Str:Obj?)parts[3]["energyFlow"]
    near(EnerCubixMath.maps(graph["nodes"]).find |n| { n["id"] == "m" }["value"],130f)
    verify(!EnerCubixMath.maps(graph["links"]).isEmpty)
    verifyEq(parts.last["to"],req["to"])
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
    result:=EnerCubixEngine.report(req,rs,[main,child])
    parts:=EnerCubixMath.maps(((Map)result["extra"])["energyFlowSegments"])
    verifyEq(parts.size,1)
    graph:=(Str:Obj?)parts.first["energyFlow"]
    near(EnerCubixMath.maps(graph["nodes"]).find |n| { n["id"] == "m" }["value"],0f)
    verifyEq(EnerCubixMath.maps(graph["links"]).size,0)
  }

  private Str:Obj? closedHistory(Str id, Float?[] values)
  {
    rows:=values.map |value,i->[Str:Obj?]| { ["from":ts(i),"to":ts(i+1),"value":value,"valueType":value == null ? "null" : "number","quality":value == null ? "filtered" : "cleaned"] }
    return ["pointId":id,"unit":"kWh","mode":"interval","quality":"derived","intervals":rows]
  }

  Void testVirtualSumIsAConsistencyCheckRatherThanIndependentLoss()
  {
    rs:=records; rs.find |r| { r["id"] == "m" }["autoSum"]=true
    flow:=EnerCubixEngine.report(request("energyFlow",1),rs,histories)
    n:=EnerCubixMath.maps(((Str:Obj?)((Str:Obj?)flow["extra"])["energyFlow"])["nodes"]).find |r| { r["id"] == "m" }
    verifyEq(n["balanceMode"],"consistency")
    verifyEq(n["lossEligible"],false)
    leak:=EnerCubixEngine.report(request("leak",1),rs,histories)
    row:=EnerCubixMath.maps(leak["rows"]).first
    verifyEq(row["balanceMode"],"consistency")
    verifyEq(row["lossEligible"],false)
    verifyNull(row["percentage"])
  }

  Void testMembershipChangeAggregatesOnlyTheActiveChildIntervals()
  {
    rs:=records; before:=rs.findAll |r| { r["id"] != "c" }
    req:=request("leak",2); req["meterHistorySegments"]=[segment(0,1,before),segment(1,2,rs)]
    report:=EnerCubixEngine.report(req,rs,histories)
    row:=EnerCubixMath.maps(report["rows"]).first
    near(row["total"],220f); near(row["submeter"],200f); near(row["difference"],20f)
    near(row["percentage"],20f/220f*100f)
    verifyEq(EnerCubixMath.maps(report["rows"]).size,1)
  }

  Void testFlowReturnsSeparateHistoricTreesWithoutReparentingThePast()
  {
    rs:=records; before:=rs.findAll |r| { r["id"] != "c" }
    req:=request("energyFlow",2); req["meterHistorySegments"]=[segment(0,1,before),segment(1,2,rs)]
    report:=EnerCubixEngine.report(req,rs,histories)
    segments:=EnerCubixMath.maps(((Str:Obj?)report["extra"])["energyFlowSegments"])
    verifyEq(segments.size,2)
    first:=EnerCubixMath.maps(((Str:Obj?)segments[0]["energyFlow"])["nodes"])
    last:=EnerCubixMath.maps(((Str:Obj?)segments[1]["energyFlow"])["nodes"])
    verify(!first.any |r| { r["id"] == "c" })
    verify(last.any |r| { r["id"] == "c" })
    near(first.find |r| { r["id"] == "m" }["value"],100f)
    near(last.find |r| { r["id"] == "m" }["value"],120f)
  }

  Void testUnknownPastDoesNotInventCurrentBranches()
  {
    req:=request("energyFlow",1); req["meterHistorySegments"]=[["from":ts(0),"to":ts(1),"known":false]]
    report:=EnerCubixEngine.report(req,records,histories)
    flow:=(Str:Obj?)((Str:Obj?)report["extra"])["energyFlow"]
    ns:=EnerCubixMath.maps(flow["nodes"])
    verifyEq(EnerCubixMath.maps(flow["links"]).size,0)
    verify(!ns.any |r| { r["id"] == "a" || r["id"] == "c" })
    n:=ns.find |r| { r["id"] == "m" }
    near(n["value"],100f); verifyEq(n["balanceQuality"],"topologyUnknown")
  }

  Void testHistoryPlanIncludesRetiredPointsFromKnownSegments()
  {
    rs:=records; old:=records; old.find |r| { r["id"] == "m" }["pointId"]="old-pm"
    req:=request("energyFlow",2); req["meterHistorySegments"]=[segment(0,1,old),segment(1,2,rs)]
    plan:=EnerCubixDimension.dependencies(req,rs)
    verify(((Str[])plan["points"]).contains("old-pm"))
    verify(((Str[])plan["points"]).contains("pm"))
  }

  Void testFormulaArchiveIsAuthoritativeAndMissingArchiveNeverFallsBack()
  {
    rs:=records
    rs.add(["id":"f","kind":"meter","name":"Formula","historyPointId":"pf","expressionId":"expr","categoryId":"electric","unit":"kWh"])
    rs.add(["id":"expr","kind":"expression","name":"Expr","formula":"a","variables":["a":"a"]])
    req:=request("profile",1); req["nodeIds"]=["f"]
    hs:=histories.add(history("pf",[0f,15f,30f]))
    report:=EnerCubixEngine.report(req,rs,hs)
    near(EnerCubixMath.maps(report["rows"]).first["value"],15f)
    missing:=EnerCubixEngine.report(req,rs,histories)
    verifyNull(EnerCubixMath.maps(missing["rows"]).first["value"])
    plan:=EnerCubixDimension.dependencies(req,rs)
    verifyEq(plan["points"],["pf"])
  }

  Void testIncompleteBranchCannotBecomeACompleteMergedLoss()
  {
    rs:=records; before:=rs.findAll |r| { r["id"] != "c" }
    req:=request("leak",2); req["meterHistorySegments"]=[segment(0,1,before),segment(1,2,rs)]
    hs:=histories; hs.find |h| { h["pointId"] == "pa" }["quality"]="filtered"
    report:=EnerCubixEngine.report(req,rs,hs)
    row:=EnerCubixMath.maps(report["rows"]).first
    near(row["total"],220f)
    verifyNull(row["submeter"]); verifyNull(row["difference"]); verifyNull(row["percentage"])
    verifyEq(row["lossEligible"],false)
  }

  Void testNegativeDifferenceRemainsSignedAndCannotBecomeALossClaim()
  {
    rs:=records.findAll |r| { r["id"] != "c" }
    hs:=histories; hs[0]=history("pm",[0f,50f,100f])
    report:=EnerCubixEngine.report(request("leak",1),rs,hs)
    row:=EnerCubixMath.maps(report["rows"]).first
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

class EnerCubixLeakMembershipTest : Test
{
  Void testInactiveAndUnconfirmedLogsDoNotChangeCurrentParticipation()
  {
    rs:=records;req:=request;req["period"]="hour"
    req["meterHistorySegments"]=[segment(0,2,rs.findAll |r| {r["id"] != "c"}),segment(2,4,rs)]
    report:=EnerCubixEngine.report(req,rs,histories)
    branches:=EnerCubixMath.maps(((Map)report["extra"])["leakBranches"])
    branch:=branches.find |r| {r["branchId"] == "c" && r["ts"] == ts(0)}
    verifyEq(branch["participationQuality"],"ok"); near(branch["knownValue"],999f)
    req["meterHistorySegments"]=[["from":ts(0),"to":ts(2),"known":false],segment(2,4,rs)]
    report=EnerCubixEngine.report(req,rs,histories)
    branches=EnerCubixMath.maps(((Map)report["extra"])["leakBranches"])
    branch=branches.find |r| {r["branchId"] == "c" && r["ts"] == ts(0)}
    verifyEq(branch["participationQuality"],"ok"); near(branch["knownValue"],999f)
  }
  Void testTwoDaysUseCurrentChildrenAcrossBothDays()
  {
    rs:=records;req:=request;req["to"]=ts(48);req["asOf"]=ts(48)
    req["meterHistorySegments"]=[segment(0,24,rs.findAll |r| {r["id"] != "c"}),segment(24,48,rs)]
    hs:=[history("pm",(0..<48).map |i->Float?| {100f}),history("pa",(0..<48).map |i->Float?| {10f}),history("pb",(0..<48).map |i->Float?| {5f}),history("pc",(0..<48).map |i->Float?| {i < 24 ? 999f : 3f})]
    report:=EnerCubixEngine.report(req,rs,hs);rows:=EnerCubixMath.maps(report["rows"])
    near(rows[0]["knownSubmeter"],24336f);near(rows[1]["knownSubmeter"],432f)
    near(total(report)["knownSubmeter"],24768f);near(total(report)["difference"],-19968f)
    verifyEq(total(report)["lossEligible"],false)
  }
  Void testBucketAxisUsesTheRequestedProjectTimezone()
  {
    req:=request;req["from"]="2026-10-20T12:00:00Z";req["to"]="2026-10-21T12:00:00Z";req["asOf"]=req["to"];req["tz"]="Shanghai"
    report:=EnerCubixEngine.report(req,records,[Str:Obj?][,])
    rows:=EnerCubixMath.maps(report["rows"])
    verifyEq(rows.size,2)
    verifyEq(rows.first["ts"],"2026-10-20T00:00:00+08:00")
    verifyEq(report["from"],"2026-10-20T20:00:00+08:00")
  }
  Void testMeterRegisteredLaterStillShowsItsStoredOwnHistory()
  {
    rs:=records; req:=request
    req["meterHistorySegments"]=[segment(0,4,rs.findAll |r| {r["kind"] == "category"})]
    report:=EnerCubixEngine.report(req,rs,histories)
    near(total(report)["knownTotal"],100f)
    near(total(report)["knownSubmeter"],2070f);near(total(report)["difference"],-1970f)
    verifyEq(total(report)["membershipQuality"],"ok")
    verifyEq(EnerCubixMath.maps(report["rows"]).size,1)
  }
  Void testUnknownTopologyLogKeepsCurrentMembershipAndOwnUsage()
  {
    rs:=records
    req:=request
    req["meterHistorySegments"]=[["from":ts(0),"to":ts(2),"known":false],segment(2,4,rs)]
    report:=EnerCubixEngine.report(req,rs,histories)
    row:=total(report)
    near(row["knownTotal"],100f); near(row["knownSubmeter"],2070f)
    verifyEq(row["membershipQuality"],"ok")
    near(row["difference"],-1970f); verifyEq(row["lossEligible"],false)
    own:=EnerCubixMath.maps(((Map)report["extra"])["leakOwnUsage"])
    near(own.find |r| {r["nodeId"] == "a"}["value"],40f)
    verifyEq(report["from"],req["from"]); verifyEq(report["to"],req["to"]); verifyEq(report["asOf"],req["asOf"])
    verifyEq(EnerCubixDimension.dependencies(req,rs)["points"],["pa","pb","pc","pm"])
  }

  Void testCurrentChildContributesForTheWholeRangeRegardlessOfJoiningLog()
  {
    rs:=records; before:=rs.findAll |r| {r["id"] != "c"}
    req:=request; req["meterHistorySegments"]=[segment(0,2,before),segment(2,4,rs)]
    report:=EnerCubixEngine.report(req,rs,histories)
    row:=total(report)
    near(row["knownSubmeter"],2070f) // A:40 + B:20 + C:999+999+5+7.
    verifyEq(row["membershipQuality"],"ok")
    near(row["difference"],-1970f)
    branches:=EnerCubixMath.maps(((Map)report["extra"])["leakBranches"])
    near(branches.find |r| {r["branchId"] == "c"}["activeSeconds"],14400f)
  }

  Void testActiveMissingChildDoesNotHideOtherKnownAmountsOrBecomeLeakage()
  {
    rs:=records; req:=request
    req["meterHistorySegments"]=[segment(0,4,rs)]
    hs:=histories
    hs[2]=history("pb",[null,null,null,null])
    report:=EnerCubixEngine.report(req,rs,hs); row:=total(report)
    near(row["knownTotal"],100f); near(row["knownSubmeter"],2050f) // 40 + 999 + 999 + 5 + 7
    verifyNull(row["difference"]); verifyNull(row["percentage"])
    verifyEq(row["knownSubmeterQuality"],"filtered")
    branches:=EnerCubixMath.maps(((Map)report["extra"])["leakBranches"])
    near(branches.find |r| {r["branchId"] == "a"}["knownValue"],40f)
    verifyNull(branches.find |r| {r["branchId"] == "b"}["knownValue"])
  }

  Void testTopologyLogDoesNotReviveRemovedVirtualChildren()
  {
    before:=records
    before.find |r| {r["id"] == "c"}.setAll(["historyPointId":"pc","expressionId":"unused","includeInTotals":true])
    after:=before.findAll |r| {r["id"] != "c"}
    req:=request; req["meterHistorySegments"]=[segment(0,2,before),segment(2,4,after)]
    report:=EnerCubixEngine.report(req,after,histories)
    near(total(report)["knownSubmeter"],60f)
    own:=EnerCubixMath.maps(((Map)report["extra"])["leakOwnUsage"])
    verifyNull(own.find |r| {r["nodeId"] == "c"})
    verifyEq(EnerCubixDimension.dependencies(req,after)["points"],["pa","pb","pm"])
  }

  Void testUnrelatedTopologyBoundaryDoesNotSplitOwnClosedIntervals()
  {
    rs:=records.findAll |r| {r["id"] != "b" && r["id"] != "c"}
    changed:=[Str:Obj?][["id":"other","kind":"organization","name":"Other"]].addAll(rs)
    req:=request; req["meterHistorySegments"]=[segment(0,1,rs),segment(1,4,changed)]
    hs:=[history("pm",[10f,20f,30f,40f]),["pointId":"pa","unit":"kWh","mode":"interval","intervals":[["from":ts(0),"to":ts(2),"value":12f],["from":ts(2),"to":ts(4),"value":18f]]]]
    near(total(EnerCubixEngine.report(req,changed,hs))["knownSubmeter"],30f)
  }

  Void testCalculatedMasterKeepsConsistencyModeAndFixedCutoff()
  {
    rs:=records; rs.find |r| {r["id"] == "m"}["autoSum"]=true
    req:=request; req["asOf"]=ts(2); req["meterHistorySegments"]=[segment(0,4,rs)]
    row:=total(EnerCubixEngine.report(req,rs,histories))
    near(row["knownTotal"],30f)
    verifyEq(row["balanceMode"],"consistency"); verifyEq(row["lossEligible"],false)
    verifyNull(row["percentage"])
  }

  Void testAreaNormalizationUsesTheMasterAreaForBothBars()
  {
    rs:=records; rs.find |r| {r["id"] == "m"}["area"]=10f
    req:=request; req["perArea"]=true
    row:=total(EnerCubixEngine.report(req,rs,histories))
    near(row["knownTotal"],10f); near(row["knownSubmeter"],207f)
    verifyEq(row["unit"],"kWh/m²")
  }

  Void testZeroAndNaRemainDistinctAndCurrentBindingAppliesAcrossTheRange()
  {
    before:=records.findAll |r| {r["id"] != "b" && r["id"] != "c"}
    [Str:Obj?][] after:=before.map |r->[Str:Obj?]| {r.dup}
    after.find |r| {r["id"] == "a"}["pointId"]="new"
    req:=request; req["meterHistorySegments"]=[segment(0,2,before),segment(2,4,after)]
    hs:=[history("pm",[0f,0f,0f,0f]),history("pa",[999f,999f,999f,999f]),history("new",[0f,0f,3f,7f])]
    row:=total(EnerCubixEngine.report(req,after,hs))
    near(row["knownTotal"],0f); near(row["knownSubmeter"],10f)
    verifyEq(EnerCubixDimension.dependencies(req,after)["points"],["new","pm"])
    hs[0]=history("pm",[null,null,null,null])
    EnerCubixMath.maps(hs[0]["intervals"]).each |r| {r["quality"]="na";r["valueType"]="na"}
    row=total(EnerCubixEngine.report(req,after,hs))
    verifyNull(row["knownTotal"]);verifyEq(row["knownTotalQuality"],"na")
  }

  private Str:Obj? total(Str:Obj? report) { EnerCubixMath.maps(((Map)report["extra"])["leakTotals"]).first }
  private Str:Obj? request() { ["kind":"leak","dimension":"metering","nodeIds":["m"],"categoryId":"e","from":ts(0),"to":ts(4),"asOf":ts(4),"period":"day","metric":"energy","tz":"UTC"] }
  private Str:Obj? segment(Int a,Int b,[Str:Obj?][] rs) { ["from":ts(a),"to":ts(b),"known":true,"records":rs] }
  private [Str:Obj?][] records() { [["id":"e","kind":"category","name":"Electric","unit":"kWh"],["id":"m","kind":"totalMeter","name":"Master","pointId":"pm","categoryId":"e","unit":"kWh"],["id":"a","kind":"meter","name":"A","pointId":"pa","categoryId":"e","unit":"kWh","meterParentId":"m"],["id":"b","kind":"meter","name":"B","pointId":"pb","categoryId":"e","unit":"kWh","meterParentId":"m"],["id":"c","kind":"meter","name":"C","pointId":"pc","categoryId":"e","unit":"kWh","meterParentId":"m"]] }
  private [Str:Obj?][] histories() { [history("pm",[10f,20f,30f,40f]),history("pa",[10f,10f,10f,10f]),history("pb",[5f,5f,5f,5f]),history("pc",[999f,999f,5f,7f])] }
  private Str:Obj? history(Str point,Float?[] values) { ["pointId":point,"unit":"kWh","mode":"interval","intervals":values.map |v,i->[Str:Obj?]| {["from":ts(i),"to":ts(i+1),"value":v]}] }
  private Str ts(Int hour) { (DateTime.fromIso("2026-10-20T00:00:00Z")+Duration(hour*1hr.ticks)).toIso }
  private Void near(Obj? actual,Float expected) { verifyNotNull(actual); verify((EnerCubixMath.num(actual)-expected).abs < 0.000001f) }
}

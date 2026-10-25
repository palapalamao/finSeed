class EnerCubixLegacyMembershipTest : Test
{
  Void testRecoveryLogDoesNotChangeCurrentMembersOrTheirOctober24Amounts()
  {
    req:=request
    req["legacyMembership"]=[edge("a","m",0,24,"pa"),edge("b","m",0,24,"pb")]
    result:=EnerCubixEngine.report(req,records,histories)
    total:=EnerCubixMath.maps(((Map)result["extra"])["leakTotals"]).first
    near(total["knownTotal"],232908f);near(total["knownSubmeter"],258153f)
    verifyEq(total["membershipQuality"],"ok")
    verifyEq(total["knownSubmeterQuality"],"filtered")
    verifyNull(total["difference"]);verifyNull(total["percentage"]);verifyEq(total["lossEligible"],false)
    branches:=EnerCubixMath.maps(((Map)result["extra"])["leakBranches"])
    near(branches.find |r| {r["branchId"] == "a"}["knownValue"],86071f)
    near(branches.find |r| {r["branchId"] == "b"}["knownValue"],172082f)
    verifyNull(branches.find |r| {r["branchId"] == "c"}["knownValue"])
    verifyEq(branches.find |r| {r["branchId"] == "c"}["participationQuality"],"ok")
    verifyEq(result["from"],req["from"]);verifyEq(result["to"],req["to"]);verifyEq(result["asOf"],req["asOf"])
  }

  Void testRecoveryLogDoesNotChangeTheDataCoverageOfEitherDay()
  {
    req:=request;req["to"]=ts(48);req["asOf"]=ts(48)
    req["meterHistorySegments"]=[["from":ts(0),"to":ts(24),"known":false],["from":ts(24),"to":ts(48),"known":true,"records":records]]
    req["legacyMembership"]=[edge("a","m",0,48,"pa"),edge("b","m",0,48,"pb")]
    hs:=histories.add(history("pc",24,48,5f))
    result:=EnerCubixEngine.report(req,records,hs);rows:=EnerCubixMath.maps(result["rows"])
    near(rows[0]["knownSubmeter"],258153f)
    near(rows[1]["knownSubmeter"],5f)
    verifyEq(rows[1]["membershipQuality"],"ok")
    verifyEq(rows[0]["membershipQuality"],"ok")
  }

  Void testRecoveryLogDoesNotReviveDeletedChildrenOrTheirFormerBindings()
  {
    rs:=records.findAll |r| {r["id"] != "a"}
    rs.add(["id":"other","kind":"totalMeter","name":"Other","categoryId":"e","pointId":"otherPoint","unit":"kWh"])
    req:=request;req["period"]="hour";req["to"]=ts(2);req["asOf"]=ts(2)
    req["meterHistorySegments"]=[["from":ts(0),"to":ts(2),"known":false]]
    req["legacyMembership"]=[edge("a","m",0,1,"old"),edge("a","other",1,2,"new")]
    hs:=[history("pm",0,1,10f),history("old",0,1,3f),history("new",0,1,999f)]
    [history("pm",1,2,20f),history("old",1,2,999f),history("new",1,2,7f)].each |h,i| {hs[i]["intervals"]=EnerCubixMath.maps(hs[i]["intervals"]).dup.addAll(EnerCubixMath.maps(h["intervals"]))}
    result:=EnerCubixEngine.report(req,rs,hs);rows:=EnerCubixMath.maps(result["rows"])
    verifyNull(rows[0]["knownSubmeter"]);verifyNull(rows[1]["knownSubmeter"])
    own:=EnerCubixMath.maps(((Map)result["extra"])["leakOwnUsage"])
    verifyNull(own.find |r| {r["nodeId"] == "a"})
    verifyEq(EnerCubixMath.strings(EnerCubixDimension.dependencies(req,rs)["points"]),["pb","pc","pm"])
  }

  Void testMissingCurrentBranchKeepsOtherKnownAmountsAndZeroDespiteRecoveryLog()
  {
    req:=request;req["legacyMembership"]=[edge("a","m",0,24,"pa"),edge("b","m",0,24,"pb")]
    hs:=[history("pm",0,24,0f),history("pa",0,24,0f)]
    total:=EnerCubixMath.maps(((Map)EnerCubixEngine.report(req,records,hs)["extra"])["leakTotals"]).first
    near(total["knownTotal"],0f);near(total["knownSubmeter"],0f)
    verifyEq(total["knownSubmeterQuality"],"filtered");verifyNull(total["difference"])
  }

  Void testMissingTopologyEvidenceDoesNotBlockCurrentMembersAndNonEnergyStaysConservative()
  {
    req:=request
    total:=EnerCubixMath.maps(((Map)EnerCubixEngine.report(req,records,histories)["extra"])["leakTotals"]).first
    near(total["knownSubmeter"],258153f);verifyEq(total["membershipQuality"],"ok")
    req["metric"]="coal";req["legacyMembership"]=[edge("a","m",0,24,"pa")]
    total=EnerCubixMath.maps(((Map)EnerCubixEngine.report(req,records,histories)["extra"])["leakTotals"]).first
    verifyNull(total["knownSubmeter"])
  }

  Void testRecoveryLogExclusionDoesNotExcludeACurrentChild()
  {
    req:=request;req["legacyMembership"]=[edge("a","m",0,24,"pa").set("participating",false),edge("b","m",0,24,"pb")]
    result:=EnerCubixEngine.report(req,records,histories)
    total:=EnerCubixMath.maps(((Map)result["extra"])["leakTotals"]).first
    near(total["knownSubmeter"],258153f)
    branch:=EnerCubixMath.maps(((Map)result["extra"])["leakBranches"]).find |r| {r["branchId"] == "a"}
    near(branch["knownValue"],86071f);verifyEq(branch["participationQuality"],"ok")
  }

  private Str:Obj? request() { ["kind":"leak","dimension":"metering","nodeIds":["m"],"from":ts(0),"to":ts(24),"asOf":ts(24),"period":"day","metric":"energy","tz":"UTC","meterHistorySegments":[["from":ts(0),"to":ts(24),"known":false]]] }
  private Str:Obj? edge(Str child,Str parent,Int from,Int to,Str point) { ["childId":child,"parentId":parent,"pointId":point,"categoryId":"e","unit":"kWh","from":ts(from),"to":ts(to),"name":child,"proofId":"proof","basis":"snapshotRecovered"] }
  private [Str:Obj?][] records() { [["id":"e","kind":"category","name":"Electric","unit":"kWh"],["id":"m","kind":"totalMeter","name":"Master","pointId":"pm","categoryId":"e","unit":"kWh"],["id":"a","kind":"meter","name":"A","pointId":"pa","categoryId":"e","meterParentId":"m","unit":"kWh"],["id":"b","kind":"meter","name":"B","pointId":"pb","categoryId":"e","meterParentId":"m","unit":"kWh"],["id":"c","kind":"meter","name":"C","pointId":"pc","categoryId":"e","meterParentId":"m","unit":"kWh"]] }
  private [Str:Obj?][] histories() { [history("pm",0,24,232908f),history("pa",0,24,86071f),history("pb",0,24,172082f)] }
  private Str:Obj? history(Str point,Int from,Int to,Float value) { ["pointId":point,"unit":"kWh","mode":"interval","intervals":[["from":ts(from),"to":ts(to),"value":value,"quality":"cleaned","valueType":"number"]]] }
  private Str ts(Int hour) { (DateTime.fromIso("2026-10-24T00:00:00Z")+Duration(hour*1hr.ticks)).toIso }
  private Void near(Obj? actual,Float expected) {verifyNotNull(actual);verify((EnerCubixMath.num(actual)-expected).abs < 0.000001f)}
}

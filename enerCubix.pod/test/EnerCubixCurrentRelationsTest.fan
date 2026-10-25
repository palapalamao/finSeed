class EnerCubixCurrentRelationsTest : Test
{
  Void testUnknownRelationshipLogDoesNotHideCurrentMembers()
  {
    req:=request
    req["meterHistorySegments"]=[["from":ts(0),"to":ts(2),"known":false]]
    result:=EnerCubixEngine.report(req,records,histories)
    row:=total(result)
    near(row["knownSubmeter"],190f)
    near(row["difference"],10f)
    verifyEq(row["lossEligible"],true)
    verifyEq(row["membershipQuality"],"ok")
  }

  Void testPastMembersCannotReplaceCurrentMembersOrDependencies()
  {
    current:=records
    current.find |r| {r["id"] == "b"}["meterParentId"]="other"
    current.add(["id":"c","kind":"meter","name":"C","categoryId":"electric","pointId":"pc","meterParentId":"m","includeInTotals":true])
    req:=request
    req["meterHistorySegments"]=[["from":ts(0),"to":ts(2),"known":true,"records":records]]
    hs:=histories.dup.add(history("pc",[60f,60f]))
    row:=total(EnerCubixEngine.report(req,current,hs))
    near(row["knownSubmeter"],200f)
    verifyEq(EnerCubixMath.strings(EnerCubixDimension.dependencies(req,current)["points"]),["pa","pc","pm"])
  }

  Void testOctober24KeepsBothAvailableBarsWhenThirdMeterIsMissing()
  {
    current:=records
    current.add(["id":"c","kind":"meter","name":"C","categoryId":"electric","pointId":"pc","meterParentId":"m","includeInTotals":true])
    req:=request; req["to"]=ts(1)
    req["meterHistorySegments"]=[["from":ts(0),"to":ts(1),"known":false]]
    result:=EnerCubixEngine.report(req,current,[history("pm",[232908f]),history("pa",[86071f]),history("pb",[172082f])])
    row:=total(result)
    near(row["knownSubmeter"],258153f)
    verifyNull(row["difference"])
    branches:=EnerCubixMath.maps(((Map)result["extra"])["leakBranches"])
    near(branches.find |r| {r["branchId"] == "a"}["knownValue"],86071f)
    near(branches.find |r| {r["branchId"] == "b"}["knownValue"],172082f)
    verifyNull(branches.find |r| {r["branchId"] == "c"}["knownValue"])
  }

  Void testRecoveryLogsAndInternalFlagsCannotChangeTheResult()
  {
    expected:=total(EnerCubixEngine.report(request,records,histories))
    req:=request
    req["legacyMembership"]=[["bad":"log only"]]
    req["leakSegment"]=true
    req["meterHistorySegments"]=[["invalid":"log only"]]
    actual:=total(EnerCubixEngine.report(req,records,histories))
    near(actual["knownSubmeter"],(Float)expected["knownSubmeter"])
    verifyEq(actual["lossEligible"],expected["lossEligible"])
  }

  Void testCurrentBindingIsUsedAcrossTheWholeQuery()
  {
    current:=records
    current.find |r| {r["id"] == "a"}["pointId"]="new"
    req:=request
    req["meterHistorySegments"]=[["from":ts(0),"to":ts(2),"known":true,"records":records]]
    hs:=histories.dup.add(history("new",[30f,30f]))
    near(total(EnerCubixEngine.report(req,current,hs))["knownSubmeter"],170f)
    verifyEq(EnerCubixMath.strings(EnerCubixDimension.dependencies(req,current)["points"]),["new","pb","pm"])
  }

  private Str:Obj? request()
  { ["kind":"leak","dimension":"metering","nodeIds":["m"],"from":ts(0),"to":ts(2),"asOf":ts(3),"period":"day","metric":"energy","perArea":false] }

  private [Str:Obj?][] records()
  { [["id":"electric","kind":"category","name":"Electricity","unit":"kWh"],
     ["id":"m","kind":"totalMeter","name":"Main","categoryId":"electric","pointId":"pm","includeInTotals":true],
     ["id":"a","kind":"meter","name":"A","categoryId":"electric","pointId":"pa","meterParentId":"m","includeInTotals":true],
     ["id":"b","kind":"meter","name":"B","categoryId":"electric","pointId":"pb","meterParentId":"m","includeInTotals":true]] }

  private [Str:Obj?][] histories()
  { [history("pm",[100f,100f]),history("pa",[40f,40f]),history("pb",[55f,55f])] }

  private Str:Obj? history(Str id, Float[] values)
  {
    intervals:=[Str:Obj?][,]
    values.each |value,i| {intervals.add(["from":ts(i),"to":ts(i+1),"value":value,"quality":"derived"])}
    return ["pointId":id,"mode":"interval","unit":"kWh","intervals":intervals]
  }
  private Str:Obj? total(Str:Obj? report) {EnerCubixMath.maps(((Map)report["extra"])["leakTotals"]).first}
  private Str ts(Int hour) {(DateTime.fromStr("2026-10-24T00:00:00+08:00 Shanghai")+Duration(hour*1hr.ticks)).toIso}
  private Void near(Obj? value, Float expected) {verifyNotNull(value); verify(EnerCubixMath.num(value).approx(expected))}
}

using util

class EnerCubixComparisonScopeTest : Test
{
  Void testPhysicalComparisonIncludesExcludedMembersWithoutChangingAutomaticReports()
  {
    rs:=records;req:=request
    result:=EnerCubixEngine.report(req,rs,histories)
    near(total(result)["knownSubmeter"],50f)
    verifyEq(EnerCubixMath.strings(scope(result)["selectedMemberIds"]),["a","b"])
    verifyEq(rs.find |r| {r["id"] == "a"}["includeInTotals"],false)
    req.remove("comparisonBasis")
    near(total(EnerCubixEngine.report(req,rs,histories))["knownSubmeter"],20f)
    req["kind"]="profile";req["nodeIds"]=["a"]
    own:=EnerCubixEngine.report(req,rs,histories)
    near(EnerCubixMath.maps(((Map)own["summary"])["knownTotals"]).first["value"],30f)
  }

  Void testDefaultEmptyAndSubsetHaveDifferentMeaning()
  {
    req:=request;req["comparisonMembers"]=["m":Str[,]]
    empty:=EnerCubixEngine.report(req,records,histories)
    verifyNull(total(empty)["knownSubmeter"]);verifyNull(total(empty)["difference"])
    verifyEq(EnerCubixMath.strings(scope(empty)["selectedMemberIds"]),Str[,])
    req["comparisonMembers"]=["m":["a"]]
    subset:=EnerCubixEngine.report(req,records,histories)
    near(total(subset)["knownSubmeter"],30f)
    verifyNull(total(subset)["difference"]);verifyNull(total(subset)["percentage"])
    verifyEq(total(subset)["lossEligible"],false)
    verifyEq(scope(subset)["quality"],"comparisonPartial")
    verifyEq(EnerCubixMath.strings(EnerCubixDimension.dependencies(req,records)["points"]),["pa","pm"])
  }

  Void testInvalidMembersAndForeignMasterKeysAreRejected()
  {
    req:=request;req["comparisonMembers"]=["m":["outside"]]
    verifyErr(ArgErr#) {EnerCubixEngine.report(req,records,histories)}
    req["comparisonMembers"]=["other":["a"]]
    verifyErr(ArgErr#) {EnerCubixEngine.report(req,records,histories)}
    req["comparisonMembers"]=["m":["m"]]
    verifyErr(ArgErr#) {EnerCubixEngine.report(req,records,histories)}
  }

  Void testAdditiveNodesExpandButPhysicalMetersStopTheBoundary()
  {
    rs:=records
    rs.find |r| {r["id"] == "a"}["meterParentId"]="v"
    rs.find |r| {r["id"] == "b"}["meterParentId"]="v"
    rs.add(["id":"v","kind":"totalMeter","name":"Intermediate","categoryId":"e","pointId":"pv","meterParentId":"m","autoSum":true,"includeInTotals":true])
    rs.add(["id":"z","kind":"meter","name":"Below physical A","categoryId":"e","pointId":"pz","meterParentId":"a","includeInTotals":true])
    hs:=histories.dup.add(history("pv",777f)).add(history("pz",9f))
    result:=EnerCubixEngine.report(request,rs,hs)
    near(total(result)["knownSubmeter"],50f)
    verifyEq(EnerCubixMath.strings(scope(result)["selectedMemberIds"]),["a","b"])
    verifyEq(EnerCubixMath.strings(EnerCubixDimension.dependencies(request,rs)["points"]),["pa","pb","pm"])
  }

  Void testStoredVirtualMasterDoesNotBecomeATemporaryChildSum()
  {
    rs:=records;rs.find |r| {r["id"] == "m"}["autoSum"]=true
    result:=EnerCubixEngine.report(request,rs,histories)
    near(total(result)["knownTotal"],100f);near(total(result)["knownSubmeter"],50f)
    verifyEq(total(result)["balanceMode"],"consistency")
    verifyEq(total(result)["lossEligible"],false)
  }

  Void testWeightedNodeRetainsItsOwnHistoryWithoutExpandingItsSources()
  {
    rs:=records
    rs.find |r| {r["id"] == "a"}["meterParentId"]="v"
    rs.find |r| {r["id"] == "b"}["meterParentId"]="v"
    rs.add(["id":"v","kind":"totalMeter","name":"Weighted","categoryId":"e","historyPointId":"pv","expressionId":"ex","meterParentId":"m","includeInTotals":true])
    rs.add(["id":"ex","kind":"expression","name":"Weighted expression","formula":"2*x+y","variables":["x":"a","y":"b"]])
    result:=EnerCubixEngine.report(request,rs,histories.dup.add(history("pv",777f)))
    near(total(result)["knownSubmeter"],777f)
    verifyNull(total(result)["difference"]);verifyEq(total(result)["lossEligible"],false)
    verifyEq(scope(result)["quality"],"comparisonUnresolved")
    verifyEq(EnerCubixMath.strings(scope(result)["selectedMemberIds"]),["v"])
    verifyEq(EnerCubixMath.strings(EnerCubixDimension.dependencies(request,rs)["points"]),["pm","pv"])
  }

  Void testUnreadableNecessaryMemberBlocksStrictConclusionWithoutLeakingIdentity()
  {
    rs:=records
    rs.add(["id":"secret-member","name":"Confidential meter","kind":"meter","categoryId":"e","pointId":"secret-point","meterParentId":"m","_comparisonReadable":false])
    result:=EnerCubixEngine.report(request,rs,histories.dup.add(history("secret-point",9f)))
    near(total(result)["knownSubmeter"],50f)
    verifyNull(total(result)["difference"]);verifyEq(total(result)["lossEligible"],false)
    verifyEq(scope(result)["quality"],"comparisonUnavailable")
    text:=JsonOutStream.writeJsonToStr(result)
    ["secret-member","secret-point","Confidential meter"].each |value| {verify(!text.contains(value))}
  }

  Void testAliasesAndMultipleMastersKeepGroupsButDeduplicateTheBoundaryUnion()
  {
    rs:=records
    rs.add(["id":"alias-a","kind":"meter","name":"Alias A","categoryId":"e","pointId":"pa","meterParentId":"m"])
    rs.add(["id":"n","kind":"totalMeter","name":"Intermediate","categoryId":"e","pointId":"pn","meterParentId":"m","autoSum":true])
    rs.find |r| {r["id"] == "b"}["meterParentId"]="n"
    req:=request;req["nodeIds"]=["m","n"];req["comparisonMembers"]=["m":["alias-a","b"]]
    result:=EnerCubixEngine.report(req,rs,histories.dup.add(history("pn",999f)))
    groups:=EnerCubixMath.maps(((Map)result["extra"])["leakTotals"])
    near(groups.find |r| {r["nodeId"] == "m"}["knownSubmeter"],50f)
    near(groups.find |r| {r["nodeId"] == "n"}["knownSubmeter"],20f)
    union:=EnerCubixMath.maps(((Map)result["extra"])["comparisonUnion"]).first
    verifyNotNull(union);near(union["knownValue"],50f)
    verifyEq(EnerCubixMath.strings(union["meterIds"]),["a","b"])
    verifyEq(EnerCubixMath.strings(union["sourceIds"]),["pa","pb"])
  }

  Void testAdditiveExpressionExpandsAndFrozenMetadataIncludesSourceBindings()
  {
    rs:=records
    rs.find |r| {r["id"] == "a"}["meterParentId"]="v"
    rs.find |r| {r["id"] == "b"}["meterParentId"]="v"
    rs.add(["id":"v","kind":"totalMeter","name":"Addition","categoryId":"e","historyPointId":"pv","expressionId":"ex","meterParentId":"m"])
    rs.add(["id":"ex","kind":"expression","name":"Addition formula","formula":"(x+y)","variables":["x":"a","y":"b"]])
    result:=EnerCubixEngine.report(request,rs,histories.dup.add(history("pv",777f)))
    near(total(result)["knownSubmeter"],50f)
    members:=EnerCubixMath.maps(scope(result)["availableMembers"])
    verifyEq(EnerCubixMath.strings(members.first["via"]),["v"])
    verifyEq(EnerCubixMath.strings(members.first["sourceIds"]),["pa"])
    verifyEq(EnerCubixMath.strings(EnerCubixDimension.dependencies(request,rs)["points"]),["pa","pb","pm"])
  }

  Void testPhysicalMetricAndCompleteMembershipAreRequiredForLossRate()
  {
    result:=EnerCubixEngine.report(request,records,histories)
    verifyEq(total(result)["lossEligible"],true);near(total(result)["percentage"],50f)
    rs:=records;rs.first["co2Factor"]=2f
    req:=request;req["metric"]="co2"
    converted:=EnerCubixEngine.report(req,rs,histories)
    verifyEq(total(converted)["lossEligible"],false);verifyNull(total(converted)["percentage"])
  }

  Void testUnreadableMainPointNeverAppearsInResponse()
  {
    rs:=records;rs.find |r| {r["id"] == "m"}["_comparisonPointReadable"]=false
    result:=EnerCubixEngine.report(request,rs,histories)
    verifyNull(total(result)["difference"])
    verify(!JsonOutStream.writeJsonToStr(result).contains("\"pm\""))
    verifyEq(EnerCubixMath.strings(EnerCubixDimension.dependencies(request,rs)["points"]),["pa","pb"])
  }

  Void testMissingVirtualArchiveNeverLoadsItsFormulaInputsAsReplacement()
  {
    rs:=records;rs.find |r| {r["id"] == "m"}["expressionId"]="ex"
    rs.find |r| {r["id"] == "m"}.remove("pointId")
    rs.add(["id":"ex","kind":"expression","formula":"x+y","variables":["x":"a","y":"b"]])
    req:=request;req["comparisonMembers"]=["m":["a"]]
    result:=EnerCubixEngine.report(req,rs,histories)
    verifyNull(total(result)["knownTotal"]);near(total(result)["knownSubmeter"],30f)
    verifyEq(EnerCubixMath.strings(EnerCubixDimension.dependencies(req,rs)["points"]),["pa"])
  }

  Void testCyclesAndIncompatibleEnergyAreLimitationsNotMissingZeros()
  {
    rs:=records;rs.find |r| {r["id"] == "m"}["meterParentId"]="b"
    result:=EnerCubixEngine.report(request,rs,histories)
    verifyEq(scope(result)["quality"],"comparisonUnresolved");verifyNull(total(result)["difference"])
    rs=records;rs.add(["id":"w","kind":"category","name":"Water","unit":"m3"])
    rs.find |r| {r["id"] == "a"}["categoryId"]="w"
    result=EnerCubixEngine.report(request,rs,histories)
    near(total(result)["knownSubmeter"],20f);verifyNull(total(result)["difference"])
    verify(EnerCubixMath.strings(scope(result)["limitations"]).contains("comparisonIncompatible"))
  }

  Void testPublishedProvenanceCannotExposeUnreadableSourceRefs()
  {
    value:=["sourceIds":["allowed","hidden"],"cleaning":[["pointId":"hidden","sourceIds":["hidden"]]],"name":"Business original"]
    cleaned:=EnerCubixComparisonScope.readableSources(value) |id->Bool| {id == "allowed"}
    text:=JsonOutStream.writeJsonToStr(cleaned)
    verify(!text.contains("hidden"));verify(text.contains("allowed"));verify(text.contains("Business original"))
  }

  private Str:Obj? request() { ["kind":"leak","dimension":"metering","nodeIds":["m"],"comparisonBasis":"physicalBoundary","from":ts(0),"to":ts(1),"asOf":ts(2),"period":"day","metric":"energy"] }
  private [Str:Obj?][] records()
  { [["id":"e","kind":"category","name":"Electricity","unit":"kWh"],["id":"m","kind":"totalMeter","name":"Main","categoryId":"e","pointId":"pm","includeInTotals":true],["id":"a","kind":"meter","name":"A","categoryId":"e","pointId":"pa","meterParentId":"m","includeInTotals":false],["id":"b","kind":"meter","name":"B","categoryId":"e","pointId":"pb","meterParentId":"m","includeInTotals":true]] }
  private [Str:Obj?][] histories() {[history("pm",100f),history("pa",30f),history("pb",20f)]}
  private Str:Obj? history(Str point,Float value) {["pointId":point,"mode":"interval","unit":"kWh","intervals":[["from":ts(0),"to":ts(1),"value":value,"quality":"derived"]]]}
  private Str:Obj? total(Str:Obj? result) {EnerCubixMath.maps(((Map)result["extra"])["leakTotals"]).first}
  private Str:Obj? scope(Str:Obj? result) {EnerCubixMath.maps(((Map)result["extra"])["comparisonScopes"]).first}
  private Str ts(Int hour) {(DateTime.fromIso("2026-10-24T00:00:00+08:00")+1hr*hour).toIso}
  private Void near(Obj? actual,Float expected) {verifyNotNull(actual);verify(EnerCubixMath.num(actual).approx(expected))}
}

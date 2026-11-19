** Baseline contracts for the bounded-consumption work. These deliberately keep
** existing reduction trees and source/quality precedence, not just UI rounding.
class FinEnergyCockpitFoldContractTest : Test
{
  Void testScopeSeriesAndSelectionTotalKeepDistinctReductionTrees()
  {
    big:=10000000000000000f
    r:=FinEnergyHistory.report(query,records,[history("pa",[big,1f]),history("pb",[2f,0f])])
    point:=FinEnergyMath.maps(FinEnergyMath.maps(r["series"]).first["points"]).first
    selection:=FinEnergyMath.maps(((Map)r["summary"])["selectionTotals"]).first
    verifyEq(point["value"],10000000000000004f)
    verifyEq(selection["value"],10000000000000002f)
    verify(point["value"] != selection["value"])
  }

  Void testEqualRankQualityAndInvalidReasonKeepFirstSourceOrder()
  {
    a:=FinEnergyValue(1f,"cleaned",["pa"]);b:=FinEnergyValue(2f,"corrected",["pb"])
    left:=FinEnergyValue.sum([a,b]);right:=FinEnergyValue.sum([b,a])
    verifyEq(left.quality,"cleaned");verifyEq(right.quality,"corrected")
    verifyEq(left.sources,["pa","pb"]);verifyEq(right.sources,["pb","pa"])
    aa:=FinEnergyValue(null,"invalidA",["pa"]);bb:=FinEnergyValue(null,"invalidB",["pb"])
    verifyEq(FinEnergyKnownUsage.combine([aa,bb,a]).quality,"invalidA")
    verifyEq(FinEnergyKnownUsage.combine([bb,aa,a]).quality,"invalidB")
  }

  Void testCoverageSumsEachPointBeforeMinimumWithoutIntersectingHours()
  {
    a:=history("pa",[10f]);b:=history("pb",[20f]);((Map)((List)b["samples"]).first)["ts"]=(at+1hr).toIso
    r:=FinEnergyHistory.report(query,records,[a,b])
    coverage:=FinEnergyMath.maps(((Map)r["extra"])["usageCoverage"]).first
    verifyEq(coverage["coveredSeconds"],3600f);verifyEq(coverage["coverage"],0.5f)
    verifyEq(coverage["coverageStart"],at.toIso);verifyEq(coverage["coverageEnd"],(at+2hr).toIso)
    rs:=records;rs.add(["id":"c-meter","kind":"meter","pointId":"pc","categoryId":"c","spaceId":"s","nativeSpaceId":"s"])
    r=FinEnergyHistory.report(query,rs,[a,b])
    coverage=FinEnergyMath.maps(((Map)r["extra"])["usageCoverage"]).first
    verifyEq(coverage["coveredSeconds"],0f);verifyEq(coverage["coverage"],0f)
  }

  Void testCopPeriodDividesOperandSumsDespiteZeroFirstDenominator()
  {
    rs:=records;rs.add(["id":"cop","kind":"cop","numeratorId":"a","denominatorId":"b"])
    q:=query;q["kind"]="cop";q["dimension"]="metering";q["nodeIds"]=["cop"]
    hs:=[history("pa",[10f,10f]),history("pb",[0f,10f])]
    r:=FinEnergyHistory.report(q,rs,hs)
    point:=FinEnergyMath.maps(FinEnergyMath.maps(r["series"]).first["points"]).first
    verifyEq(point["value"],2f)
    q["period"]="hour";r=FinEnergyHistory.report(q,rs,hs)
    points:=FinEnergyMath.maps(FinEnergyMath.maps(r["series"]).first["points"])
    verifyNull(points.first["value"]);verifyEq(points.first["quality"],"divisionByZero");verifyEq(points.last["value"],1f)
  }

  private Str:Obj? query() {["kind":"profile","dimension":"space","spaceSource":"fin","nodeIds":["s"],"categoryIds":["c"],"period":"day","metric":"energy","from":at.toIso,"to":(at+2hr).toIso,"asOf":(at+2hr).toIso,"tz":"UTC"]}
  private [Str:Obj?][] records() {[["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space","nativeSourceKind":"site"],["id":"a","kind":"meter","pointId":"pa","categoryId":"c","spaceId":"s","nativeSpaceId":"s"],["id":"b","kind":"meter","pointId":"pb","categoryId":"c","spaceId":"s","nativeSpaceId":"s"]]}
  private Str:Obj? history(Str id,Float[] values) {["pointId":id,"unit":"kWh","mode":"interval","samples":values.map |v,i->[Str:Obj?]| {["ts":(at+Duration(i*1hr.ticks)).toIso,"value":v]}]}
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

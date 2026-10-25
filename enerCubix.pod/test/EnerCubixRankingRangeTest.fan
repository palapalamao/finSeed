class EnerCubixRankingRangeTest : Test
{
  Void testRequestedCounterRangeAndKnownRanking()
  {
    req:=request
    histories:=[counter("pa",[0,60,120],[100f,110f,120f]),counter("pb",[45,90,135],[200f,230f,260f])]
    result:=EnerCubixHistory.report(req,records,histories)
    verifyEq(result["from"],ts(0)); verifyEq(result["to"],ts(180))
    rows:=EnerCubixMath.maps(result["rows"])
    verifyEq(rows.first["name"],"B"); verifyEq(rows.first["knownValue"],60f)
    verifyEq(rows.last["knownValue"],20f)
    verifyNull(result["rangeAdjustment"])
    verifyEq(req["from"],ts(0)); verifyEq(req["to"],ts(180))
  }

  Void testCompleteRangeAndOtherReportsStayUnchanged()
  {
    histories:=[counter("pa",[0,180],[100f,130f]),counter("pb",[0,180],[200f,260f])]
    result:=EnerCubixHistory.report(request,records,histories)
    verifyEq(result["from"],ts(0)); verifyEq(result["to"],ts(180)); verifyNull(result["rangeAdjustment"])
    req:=request; req["kind"]="profile"
    result=EnerCubixHistory.report(req,records,[counter("pa",[45,120],[100f,110f])])
    verifyEq(result["from"],ts(0)); verifyEq(result["to"],ts(180)); verifyNull(result["rangeAdjustment"])
  }

  Void testNoCommonRangeDoesNotExpandOrDropSources()
  {
    histories:=[counter("pa",[0,60],[100f,110f]),counter("pb",[90,120],[200f,220f])]
    result:=EnerCubixHistory.report(request,records,histories)
    verifyEq(result["from"],ts(0)); verifyEq(result["to"],ts(180))
    verifyNull(result["rangeAdjustment"])
    result=EnerCubixHistory.report(request,records,[histories.first])
    verifyNull(result["rangeAdjustment"])
    verifyEq(EnerCubixMath.maps(result["rows"]).size,2)
  }

  Void testInternalMissingAndResetArePreserved()
  {
    histories:=[counter("pa",[45,60,120],[100f,null,120f]),counter("pb",[45,60,120],[200f,190f,220f])]
    result:=EnerCubixHistory.report(request,records,histories)
    verifyEq(result["from"],ts(0)); verifyEq(result["to"],ts(180))
    rows:=EnerCubixMath.maps(result["rows"])
    verify(rows.all |r| { r["value"] == null })
    verifyEq(rows.find |r| {r["nodeId"] == "b"}["knownValue"],30f)
    verifyEq(rows.find |r| {r["nodeId"] == "a"}["knownValue"],null)
  }

  Void testIntervalHoursIntersectCountersAndKeepZero()
  {
    h:=[Str:Obj?]["pointId":"pb","mode":"interval","quality":"ok","samples":[
      ["ts":ts(0),"value":null],["ts":ts(60),"value":0f],["ts":ts(120),"value":null]]]
    result:=EnerCubixHistory.report(request,records,[counter("pa",[45,150],[100f,135f]),h])
    verifyEq(result["from"],ts(0)); verifyEq(result["to"],ts(180))
    verifyEq(EnerCubixMath.maps(result["rows"]).last["knownValue"],0f)
  }

  private Str:Obj? request() { ["kind":"ranking","nodeIds":["a","b"],"from":ts(0),"to":ts(180),"period":"hour","metric":"energy","perArea":false] }
  private [Str:Obj?][] records() { [[Str:Obj?]["id":"a","kind":"meter","name":"A","pointId":"pa","categoryId":"electric","unit":"kWh"],[Str:Obj?]["id":"b","kind":"meter","name":"B","pointId":"pb","categoryId":"electric","unit":"kWh"]] }
  private Str:Obj? counter(Str id, Int[] minutes, Float?[] values) { ["pointId":id,"mode":"cumulative","quality":"ok","samples":minutes.map |m,i->Str:Obj?| { ["ts":ts(m),"value":values[i]] }] }
  private Str ts(Int minutes) { (DateTime.fromIso("2026-10-24T00:00:00+08:00")+Duration(minutes*1min.ticks)).toIso }
}

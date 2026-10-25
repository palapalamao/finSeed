class EnerCubixPartialUsageTest : Test
{
  Void testKnownSubtotalDoesNotReplaceStrictTotal()
  {
    r:=report("hour",at(0),at(2)+30min,[interval(0,1,10f),interval(1,2,20f,"filtered")])
    verifyEq(known(r)["value"],30f)
    verifyNull(((Map)((List)((Map)r["summary"])["totals"]).first)["value"])
    points:=(List)((Map)((List)r["series"]).first)["points"]
    verifyEq(((Map)points[0])["knownValue"],10f)
    verifyEq(((Map)points[1])["knownValue"],20f)
    verifyNull(((Map)points[2])["knownValue"])
  }

  Void testHourDayWeekShareClosedIntervalSubtotal()
  {
    rows:=[interval(0,1,10f),interval(1,2,20f,"substituted")]
    ["hour","day","week","month","year"].each |period|
    {
      r:=report(period,at(0),at(2)+30min,rows)
      verifyEq(known(r)["value"],30f)
      ps:=(List)((Map)((List)r["series"]).first)["points"]
      if (period != "hour") verifyEq(((Map)ps.first)["knownValue"],30f)
    }
  }

  Void testBoundaryClippingIncludesOnlyClosedContainedIntervals()
  {
    rows:=[interval(0,1,100f),interval(1,2,20f),interval(2,3,300f)]
    r:=report("day",at(0)+30min,at(2)+30min,rows)
    verifyEq(known(r)["value"],20f)
    // Interior 15-minute intervals in a partial hour remain independently known.
    rows=[[Str:Obj?]["from":(at(0)+20min).toIso,"to":(at(0)+30min).toIso,"value":7f,"quality":"ok"]]
    r=report("hour",at(0)+15min,at(0)+35min,rows)
    verifyEq(known(r)["value"],7f)
  }

  Void testZeroMissingAndNAAreDistinct()
  {
    verifyEq(known(report("day",at(0),at(2),[interval(0,1,0f)]))["value"],0f)
    verifyNull(known(report("day",at(0),at(2),[Str:Obj?][,]))["value"])
    r:=report("day",at(0),at(1),[interval(0,1,null,"na")])
    verifyNull(known(r)["value"]); verifyEq(known(r)["valueType"],"na")
    r=report("day",at(0),at(2),[interval(0,1,10f),interval(1,2,null,"na")])
    verifyEq(known(r)["value"],10f)
    verifyEq(((Map)((List)((Map)r["summary"])["totals"]).first)["valueType"],"na")
  }

  Void testLongClosedIntervalIsAssignedOnceWithoutInterpolation()
  {
    ["hour","day","week"].each |period|
    {
      r:=report(period,at(0),at(3),[interval(0,2,20f)])
      verifyEq(known(r)["value"],20f)
      ps:=(List)((Map)((List)r["series"]).first)["points"]
      verifyEq(((Map)ps.first)["knownValue"],20f)
    }
  }

  Void testGroupKeepsOneMembersKnownUseWhenAnotherIsMissing()
  {
    recs:=records.dup
    recs.first["parentId"]="g"
    recs.add(["id":"g","kind":"group","name":"Group"])
    recs.add(["id":"missing","kind":"meter","name":"Missing","parentId":"g","categoryId":"c","pointId":"missingPoint"])
    req:=request("week",at(0)-6day,at(2)+30min); req["nodeIds"]=["g"]
    r:=EnerCubixEngine.report(req,recs,[history([interval(0,1,10f),interval(1,2,20f)])])
    verifyEq(known(r)["value"],30f)
    verifyNull(((Map)((List)((Map)r["summary"])["totals"]).first)["value"])
  }

  Void testUnfinishedSourceIntervalAndNegativeImplicitUsageAreNotKnown()
  {
    now:=DateTime.nowUtc; start:=EnerCubixMath.floorHour(now)
    row:=Str:Obj?["from":start.toIso,"to":(start+1hr).toIso,"value":100f,"quality":"ok"]
    verifyNull(known(report("day",start,start+1hr,[row]))["value"])
    h:=Str:Obj?["pointId":"p","unit":"kWh","mode":"interval","samples":[["ts":at(0).toIso,"value":-1f]]]
    verifyNull(known(EnerCubixEngine.report(request("hour",at(0),at(1)),records,[h]))["value"])
  }

  Void testCumulativeKnownUseDoesNotInterpolateCrossingIntervals()
  {
    h:=Str:Obj?["pointId":"p","unit":"kWh","mode":"cumulative","samples":[["ts":at(0).toIso,"value":100f],["ts":at(1).toIso,"value":110f],["ts":at(2).toIso,"value":130f],["ts":at(3).toIso,"value":160f]]]
    r:=EnerCubixEngine.report(request("day",at(0)+30min,at(2)+30min),records,[h])
    verifyEq(known(r)["value"],20f)
  }

  Void testCompleteHistoryAndStrictRatiosRemainUnchanged()
  {
    r:=report("day",at(0),at(2),[interval(0,1,10f),interval(1,2,20f)])
    verifyEq(known(r)["value"],30f)
    verifyEq(((Map)((List)((Map)r["summary"])["totals"]).first)["value"],30f)
    verifyNull(EnerCubixValue.sum([EnerCubixValue(10f),EnerCubixValue()]).value)
    verifyNull(EnerCubixValue.divide(EnerCubixValue(20f,"filtered"),EnerCubixValue(10f)).value)
    req:=request("day",at(0),at(2)); req["kind"]="cop"; req["nodeIds"]=["cop"]
    recs:=records.dup.add(["id":"cop","kind":"cop","name":"COP","numeratorId":"m","denominatorId":"m"])
    r=EnerCubixEngine.report(req,recs,[history([interval(0,1,10f)])])
    verifyNull(((Map)((List)((Map)r["summary"])["totals"]).first)["value"])
    verify(!((Map)r["summary"]).containsKey("knownTotals"))
  }

  Void testCoverageCountsStayCompleteWhenIntervalEvidenceIsBounded()
  {
    rows:=[Str:Obj?][,]
    1002.times |i| { start:=at(0)+Duration(i*1sec.ticks); rows.add(["from":start.toIso,"to":(start+1sec).toIso,"value":1f,"quality":"ok"]) }
    r:=report("hour",at(0),at(1),rows)
    verifyEq(known(r)["value"],1002f)
    sources:=(List)((Map)((Map)r["extra"])["knownUsage"])["sourceUsage"]
    evidence:=(Map)sources.first
    verifyEq(evidence["intervalCount"],1002)
    verifyEq(((List)evidence["intervals"]).size,1000)
    verifyEq(evidence["detailsTruncated"],true)
  }

  private Str:Obj? report(Str period, DateTime from, DateTime to, [Str:Obj?][] rows)
  { EnerCubixEngine.report(request(period,from,to),records,[history(rows)]) }
  private Str:Obj? request(Str period, DateTime from, DateTime to)
  { ["kind":"profile","nodeIds":["m"],"from":from.toIso,"to":to.toIso,"period":period,"metric":"energy"] }
  private [Str:Obj?][] records()
  { [["id":"m","kind":"meter","name":"Meter","categoryId":"c","pointId":"p"],["id":"c","kind":"category","name":"Energy","unit":"kWh"]] }
  private Str:Obj? history([Str:Obj?][] rows)
  { ["pointId":"p","unit":"kWh","mode":"interval","samples":[Str:Obj?][,],"intervals":rows] }
  private Str:Obj? interval(Int start, Int end, Float? value, Str quality := "ok")
  { ["from":at(start).toIso,"to":at(end).toIso,"value":value,"quality":quality,"valueType":quality == "na" ? "na" : (value == null ? "null" : "number")] }
  private Str:Obj? known(Str:Obj? report)
  {
    values:=((Map)report["summary"])["knownTotals"] as List
    verify(values != null && !values.isEmpty,"Known usage must be separate from the strict total")
    return values.first
  }
  private DateTime at(Int hour) { DateTime.fromIso("2026-10-25T00:00:00+08:00")+Duration(hour*1hr.ticks) }
}

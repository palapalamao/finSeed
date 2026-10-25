class EnerCubixComparisonTest : Test
{
  Void testExplicitBaselineDoesNotDependOnSelectionOrder()
  {
    req:=nodeRequest; req["baselineId"]="other"
    r:=EnerCubixEngine.report(req,nodeRecords,nodeHistories)
    comparisons:=EnerCubixMath.maps(((Map)r["extra"])["comparisons"])
    verifyEq(comparisons.size,1); row:=comparisons.first
    verifyEq(row["id"],"m|water"); verifyEq(row["referenceId"],"other")
    verifyEq(row["current"],168f); verifyEq(row["reference"],504f); verifyEq(row["difference"],-336f)
    verify(((Float)row["percentage"]+200f/3f).abs < 0.000001f)
    req["nodeIds"]=["other","m"]
    verifyEq(EnerCubixMath.maps(((Map)EnerCubixEngine.report(req,nodeRecords,nodeHistories)["extra"])["comparisons"]),comparisons)
  }

  Void testBaselineMustBelongToSelectedObjects()
  {
    req:=nodeRequest; req["baselineId"]="not-selected"
    verifyErr(ArgErr#) { EnerCubixEngine.report(req,nodeRecords,nodeHistories) }
  }

  Void testIncompatibleBaselineKeepsSeriesAndExplainsNullComparison()
  {
    req:=nodeRequest; req["baselineId"]="other"
    rs:=nodeRecords; rs[1]["categoryId"]="electric"; rs[1]["unit"]="kWh"
    r:=EnerCubixEngine.report(req,rs,nodeHistories)
    verifyEq(EnerCubixMath.maps(r["series"]).size,2)
    row:=EnerCubixMath.maps(((Map)r["extra"])["comparisons"]).first
    verifyEq(row["quality"],"incompatibleBaseline"); verifyNull(row["difference"]); verifyNull(row["percentage"])
    verify(!((List)r["warnings"]).isEmpty)
  }

  Void testLegacyObjectComparisonKeepsFirstObjectAsBaseline()
  {
    r:=EnerCubixEngine.report(nodeRequest,nodeRecords,nodeHistories)
    row:=EnerCubixMath.maps(((Map)r["extra"])["comparisons"]).first
    verifyEq(row["id"],"other|water"); verifyEq(row["difference"],336f); verifyEq(row["percentage"],200f)
  }

  private Str:Obj? nodeRequest() { req:=request; req.remove("otherFrom"); req.remove("otherTo"); req.remove("comparisonAlignment"); req["nodeIds"]=["m","other"]; return req }
  private [Str:Obj?][] nodeRecords() { records.add(["id":"other","name":"基准水表","kind":"meter","pointId":"p2","categoryId":"water","unit":"m³"]) }
  private [Str:Obj?][] nodeHistories()
  {
    hs:=histories; samples:=EnerCubixMath.maps(hs.first["samples"]).map |row->[Str:Obj?]| { row.dup.set("value",3f) }
    return hs.add(["pointId":"p2","mode":"interval","unit":"m³","samples":samples])
  }

  Void testEqualWeeksAlignAtEachStartAndPreserveTotals()
  {
    req:=request; req["period"]="week"
    r:=EnerCubixEngine.report(req,records,histories)
    lines:=([Str:Obj?][])r["series"]
    verifyEq(lines.size,2)
    a:=([Str:Obj?][])lines[0]["points"]; b:=([Str:Obj?][])lines[1]["points"]
    verifyEq(a.size,1); verifyEq(b.size,1)
    verifyEq(a.first["ts"],req["from"]); verifyEq(b.first["ts"],req["otherFrom"])
    verifyEq(a.first["value"],168f); verifyEq(b.first["value"],336f)
    comparisons:=([Str:Obj?][])((Str:Obj?)r["extra"])["comparisons"]
    verifyEq(comparisons.first["difference"],-168f)
  }

  Void testRejectUnequalDurationAndInvalidAlignment()
  {
    req:=request; req["otherTo"]="2026-09-07T00:00:00Z"
    verifyErr(ArgErr#) { EnerCubixEngine.report(req,records,histories) }
    req=request; req["comparisonAlignment"]="unknown"
    verifyErr(ArgErr#) { EnerCubixEngine.report(req,records,histories) }
  }

  Void testCalendarMonthsKeepThirtyAndThirtyOneDays()
  {
    req:=request; req["to"]="2026-11-01T00:00:00Z"; req["otherTo"]="2026-10-01T00:00:00Z"
    req["period"]="month"; req["comparisonAlignment"]="calendarMonth"; req["asOf"]=req["to"]
    r:=EnerCubixEngine.report(req,records,monthHistories)
    lines:=([Str:Obj?][])r["series"]
    verifyEq((([Str:Obj?][])lines[0]["points"]).first["value"],744f)
    verifyEq((([Str:Obj?][])lines[1]["points"]).first["value"],1440f)
    req["period"]="day"
    verifyErr(ArgErr#) { EnerCubixEngine.report(req,records,monthHistories) }
  }

  Void testLegacyRangesStillUseCalendarWeeksAndAllowUnequalLengths()
  {
    req:=request; req.remove("comparisonAlignment"); req["period"]="week"; req["otherTo"]="2026-09-07T00:00:00Z"
    r:=EnerCubixEngine.report(req,records,histories)
    lines:=([Str:Obj?][])r["series"]
    verifyEq((([Str:Obj?][])lines[0]["points"]).size,2)
  }

  Void testMissingDataDoesNotBecomeZero()
  {
    hs:=histories; (([Str:Obj?][])hs.first["samples"]).removeAt(2)
    r:=EnerCubixEngine.report(request,records,hs)
    verifyNull((([Str:Obj?][])r["rows"]).first["value"])
  }

  private Str:Obj? request() { ["kind":"comparison","dimension":"metering","nodeIds":["m"],"from":"2026-10-01T00:00:00Z","to":"2026-10-08T00:00:00Z","otherFrom":"2026-09-01T00:00:00Z","otherTo":"2026-09-08T00:00:00Z","period":"day","metric":"energy","perArea":false,"tz":"UTC","comparisonAlignment":"duration"] }
  private [Str:Obj?][] records() { [["id":"m","name":"水表","kind":"meter","pointId":"p","categoryId":"water","unit":"m³"]] }
  private [Str:Obj?][] histories() { history(168,168) }
  private [Str:Obj?][] monthHistories() { history(744,720) }
  private [Str:Obj?][] history(Int current,Int previous)
  {
    samples:=[Str:Obj?][,]
    current.times |i| { samples.add(["ts":(DateTime.fromIso("2026-10-01T00:00:00Z")+Duration(i*1hr.ticks)).toIso,"value":1f]) }
    previous.times |i| { samples.add(["ts":(DateTime.fromIso("2026-09-01T00:00:00Z")+Duration(i*1hr.ticks)).toIso,"value":2f]) }
    return [["pointId":"p","mode":"interval","unit":"m³","samples":samples]]
  }
}

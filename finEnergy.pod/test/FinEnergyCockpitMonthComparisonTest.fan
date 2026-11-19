class FinEnergyCockpitMonthComparisonTest : Test
{
  Void testMonthToDateUsesProjectLocalSameDayAndClock()
  {
    result:=monthContext(input,"2026-11-03T07:37:23Z",TimeZone("Shanghai"))
    verifyEq(result["mode"],"previousMonth")
    verifyEq(result["kind"],"previousMonthSameElapsedCalendar")
    verifyEq(((Map)result["currentRange"])["from"],"2026-11-01T00:00:00+08:00")
    verifyEq(((Map)result["currentRange"])["to"],"2026-11-03T15:37:23+08:00")
    verifyEq(result["from"],"2026-10-01T00:00:00+08:00")
    verifyEq(result["to"],"2026-10-03T15:37:23+08:00")
    verifyEq(result["durationDifferenceSeconds"],0)
  }

  Void testAsOfRemainsCurrentAndIsBoundedByNow()
  {
    q:=input;q["asOf"]="2026-05-15T14:37:23Z"
    result:=monthContext(q,"2026-05-20T14:37:23Z")
    verifyEq(result["to"],"2026-04-15T14:37:23Z")
    q["asOf"]="2026-05-30T14:37:23Z"
    result=monthContext(q,"2026-05-20T14:37:23Z")
    verifyEq(result["to"],"2026-04-20T14:37:23Z")
  }

  Void testClosedNaturalMonthUsesTheWholePreviousNaturalMonth()
  {
    [
      ["2026-01-01","2026-02-01","2025-12-01","2026-01-01",0],
      ["2026-03-01","2026-04-01","2026-02-01","2026-03-01",259200],
      ["2024-03-01","2024-04-01","2024-02-01","2024-03-01",172800],
      ["2026-02-01","2026-03-01","2026-01-01","2026-02-01",-259200],
    ].each |row|
    {
      q:=input;q["time"]=["preset":"custom","period":"day","from":row[0].toStr+"T00:00:00Z","to":row[1].toStr+"T00:00:00Z"]
      result:=monthContext(q,"2026-12-01T00:00:00Z")
      verifyEq(result["from"],row[2].toStr+"T00:00:00Z")
      verifyEq(result["to"],row[3].toStr+"T00:00:00Z")
      verifyEq(result["durationDifferenceSeconds"],row[4])
      verify(!((List)result["reasonCodes"]).contains("MONTH_DAY_CLAMPED"))
    }
  }

  Void testMonthEndClampingPreservesTheRequestedLocalBoundary()
  {
    [
      ["2026-03-31","2026-02-28","2026-02-31",259200],
      ["2024-03-31","2024-02-29","2024-02-31",172800],
      ["2026-05-31","2026-04-30","2026-04-31",86400],
      ["2026-07-31","2026-06-30","2026-06-31",86400],
    ].each |row|
    {
      result:=monthContext(input,row[0].toStr+"T14:37:23Z")
      verifyEq(result["to"],row[1].toStr+"T14:37:23Z")
      verifyEq(result["durationDifferenceSeconds"],row[3])
      verify(((List)result["reasonCodes"]).contains("MONTH_DAY_CLAMPED"))
      verify(((List)result["reasonCodes"]).contains("DURATION_DIFFERENCE"))
      change:=FinEnergyMath.maps(result["adjustments"]).first
      verifyEq(change["boundary"],"to")
      verifyEq(change["reasonCode"],"MONTH_DAY_CLAMPED")
      verifyEq(change["requestedLocal"],row[2].toStr+"T14:37:23")
      verifyEq(change["resolved"],result["to"])
    }
    result:=monthContext(input,"2024-02-29T14:37:23Z")
    verifyEq(result["to"],"2024-01-29T14:37:23Z")
    verify(!((List)result["reasonCodes"]).contains("MONTH_DAY_CLAMPED"))
  }

  Void testMonthShiftRecordsNativeDstGapAndFoldResolution()
  {
    tz:=TimeZone("New_York")
    result:=monthContext(input,"2026-04-08T06:30:00Z",tz)
    verifyEq(result["to"],"2026-03-08T01:30:00-05:00")
    verify(((List)result["reasonCodes"]).contains("LOCAL_TIME_ADJUSTED"))
    verify(((List)result["reasonCodes"]).contains("TIMEZONE_OFFSET_CHANGED"))
    verifyEq(FinEnergyMath.maps(result["adjustments"]).first["requestedLocal"],"2026-03-08T02:30:00")
    result=monthContext(input,"2026-12-01T06:30:00Z",tz)
    verifyEq(result["to"],"2026-11-01T01:30:00-04:00")
    verify(((List)result["reasonCodes"]).contains("LOCAL_TIME_AMBIGUOUS"))
    verify(((List)result["reasonCodes"]).contains("TIMEZONE_OFFSET_CHANGED"))
  }

  Void testUnsupportedPresetsAndCollapsedCustomRangeRejectBeforeHistory()
  {
    ["today","thisYear"].each |preset|
    {
      q:=input;q["time"]=["preset":preset,"period":"day"]
      verifyErr(ArgErr#) {FinEnergyCockpit.execute(q,records,|rq,rs->[Str:Obj?][]| {fail("must not read");return [,]},"test",TimeZone.utc,DateTime.fromIso("2026-03-31T00:00:00Z"))}
    }
    q:=input;q["time"]=["preset":"custom","period":"day","from":"2026-03-30T00:00:00Z","to":"2026-03-31T00:00:00Z"]
    verifyErr(ArgErr#) {monthContext(q,"2026-04-01T00:00:00Z")}
  }

  Void testMonthComparisonUsesOnlyTheTwoPrimaryWindowsAndKeepsMissing()
  {
    q:=input;q["time"]=["preset":"custom","period":"hour","from":"2026-10-03T02:00:00Z","to":"2026-10-03T04:00:00Z"]
    now:=DateTime.fromIso("2026-10-03T04:00:00Z");calls:=0
    result:=FinEnergyCockpit.execute(q,records,|Str:Obj? rq,[Str:Obj?][] rs->[Str:Obj?][]|
    {
      calls++
      windows:=FinEnergyMath.maps(rq["_cockpitRanges"])
      verifyEq(windows.size,2)
      verifyEq(windows.first["from"],"2026-09-03T02:00:00Z");verifyEq(windows.first["to"],"2026-09-03T04:00:00Z")
      verifyEq(windows.last["from"],"2026-10-03T02:00:00Z");verifyEq(windows.last["to"],now.toIso)
      windows.each |w| {verifyEq(FinEnergyMath.strings(w["pointIds"]),["p"])}
      queries:=FinEnergyMath.maps(rq["_cockpitReadRanges"])
      verifyEq(queries.size,2);verify(queries.all |r| {r["asOf"]==now.toIso})
      return histories
    },"test",TimeZone.utc,now,false,|->DateTime| {now})
    verifyEq(calls,1)
    values:=FinEnergyMath.maps(((Map)((Map)((Map)result["modules"])["kpis"])["data"])["values"])
    energy:=(Map)values.find |v| {v["id"]=="energy"}["comparison"]
    verifyEq(energy["kind"],"previousMonthSameElapsedCalendar")
    verifyEq(energy["current"],100f);verifyEq(energy["reference"],80f);verifyEq(energy["changeRate"],25f)
    missing:=histories;missing.first["samples"]=FinEnergyMath.maps(missing.first["samples"]).findAll |s| {s["ts"].toStr.startsWith("2026-10")}
    result=FinEnergyCockpit.execute(q,records,|rq,rs->[Str:Obj?][]| {missing},"test",TimeZone.utc,now,false,|->DateTime| {now})
    values=FinEnergyMath.maps(((Map)((Map)((Map)result["modules"])["kpis"])["data"])["values"])
    energy=(Map)values.find |v| {v["id"]=="energy"}["comparison"]
    verifyNull(energy["reference"]);verifyNull(energy["changeRate"])
    verify(((List)energy["reasonCodes"]).contains("REFERENCE_UNAVAILABLE"))
  }

  private Str:Obj? monthContext(Str:Obj? q,Str now,TimeZone tz:=TimeZone.utc)
  {FinEnergyCockpitMetrics.comparison(q,FinEnergyCockpit.query(q,"test",tz,DateTime.fromIso(now)),tz)}
  private Str:Obj? input()
  { ["schemaVersion":1,"requestId":"month-compare","reportScope":["dimension":"metering","nodeIds":["m"],"selectionIntent":"explicitObjects"],"focusCategoryId":"c","time":["preset":"thisMonth","period":"day"],"modules":["kpis","trend"],"comparison":["mode":"previousMonth"]] }
  private [Str:Obj?][] records()
  { [["id":"c","kind":"category","name":"Electricity","unit":"kWh"],["id":"m","kind":"meter","name":"Meter","pointId":"p","categoryId":"c"],["id":"tariff","kind":"tariff","categoryId":"c","isDefault":true,"mode":"flat","rate":2f]] }
  private [Str:Obj?][] histories()
  { [["pointId":"p","unit":"kWh","mode":"interval","samples":[["ts":"2026-09-03T02:00:00Z","value":40f],["ts":"2026-09-03T03:00:00Z","value":40f],["ts":"2026-10-03T02:00:00Z","value":50f],["ts":"2026-10-03T03:00:00Z","value":50f]]]] }
}

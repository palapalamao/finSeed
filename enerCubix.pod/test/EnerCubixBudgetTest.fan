class EnerCubixBudgetTest : Test
{
  Void testUniformMonthAndDistinctProgressRatios()
  {
    tz:=TimeZone("Shanghai");from:=DateTime("2026-10-01T00:00:00+08:00 Shanghai");to:=DateTime("2026-10-25T00:00:00+08:00 Shanghai")
    b:=budget("2026-10",310000f)
    result:=EnerCubixBudgetMath.period([b],from,to,to,224600f,tz)
    near(result["periodBudget"],240000f);near(result["variancePct"],-6.416666666666667f)
    near(result["monthUsagePct"],72.45161290322581f);near(result["calendarProgressPct"],77.41935483870968f)
    near(result["deviationAmount"],-15400f);verifyEq(((List)result["curve"]).size,25)
  }
  Void testDstDaysUseActualElapsedHours()
  {
    ny:=DateTime("2026-11-01T00:00:00-04:00 New_York")
    r:=EnerCubixBudgetMath.period([budget("2026-11",300000f)],ny,ny+12hr,ny+12hr,0f,ny.tz)
    near(r["periodBudget"],4800f)
    berlin:=DateTime("2026-03-29T00:00:00+01:00 Berlin")
    r=EnerCubixBudgetMath.period([budget("2026-03",310000f)],berlin,berlin+12hr,berlin+12hr,0f,berlin.tz)
    near(r["periodBudget"],5217.391304347826f)
    r=EnerCubixBudgetMath.period([budget("2026-11",300000f)],ny,ny+25hr,ny+25hr,0f,ny.tz);near(r["periodBudget"],10000f)
    r=EnerCubixBudgetMath.period([budget("2026-11",300000f)],ny,ny+13hr,ny+13hr,0f,ny.tz);near(r["periodBudget"],5200f)
    r=EnerCubixBudgetMath.period([budget("2026-03",310000f)],berlin,berlin+23hr,berlin+23hr,0f,berlin.tz);near(r["periodBudget"],10000f)
    r=EnerCubixBudgetMath.period([budget("2026-03",310000f)],berlin,berlin+11hr,berlin+11hr,0f,berlin.tz);near(r["periodBudget"],4782.608695652174f)
    r=EnerCubixBudgetMath.period([budget("2026-11",300000f)],ny,ny+12hr+30min,ny+12hr+30min,0f,ny.tz)
    near(r["periodBudget"],5000f)
  }
  Void testCompleteCrossMonthVersionsAndDailyZeroDenominator()
  {
    a:=budget("2026-10",310000f);a["mod"]="a1"
    b:=budget("2026-11",300000f);b["version"]=2;b["mod"]="b2"
    from:=DateTime.fromIso("2026-10-01T00:00:00Z");to:=DateTime.fromIso("2026-12-01T00:00:00Z")
    r:=EnerCubixBudgetMath.period([a,b],from,to,to,305000f,TimeZone.utc)
    near(r["monthBudget"],610000f);near(r["periodBudget"],610000f);near(r["monthUsagePct"],50f)
    months:=EnerCubixMath.maps(r["months"]);verifyEq(months.map |m->Str| {m["mod"].toStr},["a1","b2"])
    a["distribution"]="daily";a["dailyAmounts"]=(0..<31).map |i->Float| {i == 30 ? 310000f : 0f}
    r=EnerCubixBudgetMath.period([a],from,from+1day,from+1day,0f,TimeZone.utc)
    verifyEq(r["status"],"ok");verifyEq(r["periodBudget"],0f);verifyNull(r["variancePct"])
  }
  Void testDailyValidationAndMissingMonthAreExplicit()
  {
    b:=budget("2026-10",310000f);b["distribution"]="daily";b["dailyAmounts"]=[10000f]
    verifyErr(ArgErr#) |->Void| {EnerCubixBudgetMath.validate(b)}
    b["dailyAmounts"]=(0..<31).map |i->Float| {i == 0 ? 10001f : 10000f}
    verifyErr(ArgErr#) |->Void| {EnerCubixBudgetMath.validate(b)}
    from:=DateTime("2026-10-01T00:00:00Z UTC");to:=DateTime("2026-12-01T00:00:00Z UTC")
    r:=EnerCubixBudgetMath.period([budget("2026-10",310000f)],from,to,to,0f,TimeZone.utc)
    verifyEq(r["status"],"unavailable");verify(((List)r["reasonCodes"]).contains("BUDGET_MONTH_MISSING"))
  }
  Void testNonUniformDailyAndExactPartialCrossMonthOracle()
  {
    from:=DateTime.fromIso("2026-10-01T00:00:00Z")
    b:=budget("2026-10",310000f);b["distribution"]="daily";b["dailyAmounts"]=(0..<31).map |i->Float| {i == 0 ? 20000f : (i == 1 ? 0f : 10000f)}
    r:=EnerCubixBudgetMath.period([b],from,from+1day,from+1day,0f,TimeZone.utc)
    near(r["periodBudget"],20000f)
    from=DateTime.fromIso("2026-10-31T00:00:00Z");to:=DateTime.fromIso("2026-11-03T00:00:00Z")
    r=EnerCubixBudgetMath.period([budget("2026-10",310000f),budget("2026-11",600000f)],from,to,to,26000f,TimeZone.utc)
    near(r["periodBudget"],50000f)
  }
  Void testCalendarProgressIsIndependentOfMissingOrInvalidBudgetMonths()
  {
    from:=DateTime.fromIso("2026-10-01T00:00:00Z");to:=DateTime.fromIso("2026-12-01T00:00:00Z")
    missing:=EnerCubixBudgetMath.period([budget("2026-10",310000f)],from,to,to,0f,TimeZone.utc)
    complete:=EnerCubixBudgetMath.period([budget("2026-10",310000f),budget("2026-11",300000f)],from,to,to,0f,TimeZone.utc)
    near(missing["calendarProgressPct"],100f);verifyEq(missing["calendarProgressPct"],complete["calendarProgressPct"])
    invalid:=budget("2026-11",0f)
    r:=EnerCubixBudgetMath.period([budget("2026-10",310000f),invalid],from,to,to,0f,TimeZone.utc)
    near(r["calendarProgressPct"],100f);verifyEq(r["status"],"unavailable")
  }
  Void testLegalZeroTargetPreservesAmountCurveAndActualWithoutPercentageDivision()
  {
    from:=DateTime.fromIso("2026-10-01T00:00:00Z")
    b:=budget("2026-10",310000f);b["distribution"]="daily";b["dailyAmounts"]=(0..<31).map |i->Float| {i == 30 ? 310000f : 0f}
    [0f,5f].each |actual|
    {
      r:=EnerCubixBudgetMath.period([b],from,from+1day,from+1day,actual,TimeZone.utc)
      verifyEq(r["status"],"ok");verifyEq(r["budgetStatus"],"ok");verifyEq(r["comparisonStatus"],"unavailable")
      verifyEq(r["periodBudget"],0f);verifyEq(r["periodActualCost"],actual);verifyEq(r["deviationAmount"],actual)
      verifyNull(r["variancePct"]);verify(EnerCubixMath.strings(r["reasonCodes"]).contains("BUDGET_ZERO_PERIOD"))
      curve:=EnerCubixMath.maps(r["curve"]);verifyEq(curve.size,2);verifyEq(curve.last["cumulativeBudget"],0f)
    }
  }
  private Str:Obj? budget(Str month,Float amount) {["id":"b-"+month,"version":1,"month":month,"amount":amount,"distribution":"uniform","currency":"CNY"]}
  private Void near(Obj? v,Float expected) {verifyNotNull(v);verify(((Float)v-expected).abs < 0.0000001f)}
}

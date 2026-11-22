class FinEnergyIntervalClockTest : Test
{
  Void testWholeHourBoundaryNeedsNoSerializationAllocation()
  {
    at:=DateTime.fromIso("2026-11-01T00:00:00Z").toTimeZone(TimeZone.fromStr("Shanghai"))
    verify(FinEnergyIntervalClock.serialized(at)===at)
    clock:=FinEnergyIntervalClock()
    first:=clock.interval(at,at+10sec,1f,"cleaned","number")
    next:=clock.interval(at+10sec,at+20sec,1f,"cleaned","number")
    verify(first.end===next.start,"same original ISO boundary and instant is shared")
  }

  Void testAllZonesHistoricalAndDstInstantsKeepExactLegacyFormatAndTicks()
  {
    TimeZone.listNames.each |name|
    {
      zone:=TimeZone.fromStr(name)
      [1902,1940,1970,1990,2000,2026,2098].each |year|
      {
        [Month.jan,Month.apr,Month.jul,Month.oct].each |month|
        {
          [0,2,12,23].each |hour|
          {
            at:=DateTime(year,month,15,hour,17,23,123456789,zone)
            check(at)
          }
        }
      }
    }
    ["New_York","London","Berlin","Shanghai","Lord_Howe","Chatham","Katmandu","Dublin","Casablanca","Apia"].each |name|
    {
      zone:=TimeZone.fromStr(name,false)
      if(zone==null) return
      start:=DateTime(2026,Month.jan,1,0,0,0,0,zone)
      (0..<366*4).each |i| {check(start+6hr*i)}
    }
  }
  private Void check(DateTime at)
  {
    expected:=DateTime.fromIso(at.toIso)
    actual:=FinEnergyIntervalClock.serialized(at)
    verifyEq(actual.ticks,expected.ticks,"$at")
    verifyEq(actual.toIso,expected.toIso,"$at")
  }
}

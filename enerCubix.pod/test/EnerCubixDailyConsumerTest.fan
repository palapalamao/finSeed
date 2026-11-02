** Fixed bins preserve independent hour and interval reductions, including DST.
class EnerCubixDailyConsumerTest : Test
{
  Void testHourAndBandFoldsMatchOriginalSequencesForEnergyGaugeAndCop()
  {
    ["energy","gauge","cop"].each |mode|
    {
      line:=EnerCubixLine("m|c","m","M","c","kWh");line.gauge=mode=="gauge";line.ratio=mode=="cop"
      at:=DateTime.fromIso("2026-01-31T23:00:00Z")
      budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
      consumer:=EnerCubixDailyConsumer(line,state,output)
      bands:=Str[,]
      for(i:=0;i<49;i++)
      {
        value:=i==0 ? 10000000000000000f : i.toFloat
        t:=EnerCubixTick(at+Duration(i*1hr.ticks),at+Duration((i+1)*1hr.ticks),EnerCubixValue(i==24 ? null : value,i==24 ? "na" : "ok",["p$i"]))
        t.known=EnerCubixValue(i==24 ? null : value,i==24 ? "na" : "ok",["p$i"])
        t.numerator=EnerCubixValue(value,"ok",["n$i"]);t.denominator=EnerCubixValue(i==0 ? 0f : 2f,"ok",["d$i"])
        band:=i<24 ? "peak" : (i<48 ? "valley" : "unknown")
        consumer.add(t,band);line.ticks.add(t);bands.add(band)
      }
      data:=consumer.finish;hours:=EnerCubixMath.maps(data["hours"])
      (0..23).each |hour|
      {
        ticks:=line.ticks.findAll |t| {t.ts.hour==hour};row:=hours[hour]
        same((EnerCubixValue)row["value"],line.total(ticks));same((EnerCubixValue)row["known"],line.knownTotal(ticks))
        verifyEq(row["samples"],ticks.size);verifyEq(row["knownSamples"],ticks.findAll |t| {t.known.value!=null}.size)
        expected:=line.ticks.findAll |t| {t.ts.hour==hour}.map |t->Str| {bands[line.ticks.index(t)]}.unique
        verifyEq(row["band"],expected.size==1 ? expected.first : "mixed")
      }
      ((Map)data["bands"]).each |raw,key|
      {
        row:=(Map)raw;ticks:=line.ticks.findAll |t| {bands[line.ticks.index(t)]==key}
        same((EnerCubixValue)row["value"],EnerCubixValue.sum(ticks.map |t->EnerCubixValue| {t.value}))
        same((EnerCubixValue)row["known"],line.knownTotal(ticks))
      }
      state.close;verifyEq(hours.size,24);escaped:=hours.first as Map;borrowed:=(List)data["hours"];output.close
      verify(data.isEmpty);verify(borrowed.isEmpty);verify(escaped.isEmpty)
      verify(hours.all |row| {row.isEmpty});verifyEq(budget.temporary.val,0)
    }
  }

  Void testRepeatedDstHourAndPartialGaugeDurationsStayIndependent()
  {
    tz:=TimeZone("New_York");at:=Date(2026,Month.nov,1).toDateTime(Time.defVal,tz)
    line:=EnerCubixLine("m|c","m","M","c","kW");line.gauge=true
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    consumer:=EnerCubixDailyConsumer(line,state,output)
    for(i:=0;i<25;i++)
    {
      start:=at+Duration(i*1hr.ticks);end:=start+(i==24 ? 20min : 1hr)
      tick:=EnerCubixTick(start,end,EnerCubixValue(i.toFloat,"ok",["p"]))
      consumer.add(tick,i%2==0 ? "peak" : "valley");line.ticks.add(tick)
    }
    data:=consumer.finish;hours:=EnerCubixMath.maps(data["hours"])
    verifyEq(hours[1]["samples"],2)
    (0..23).each |hour| {same((EnerCubixValue)hours[hour]["value"],line.total(line.ticks.findAll |t| {t.ts.hour==hour}))}
    state.close;output.close;verifyEq(budget.temporary.val,0)
  }

  Void testTotalsOnlyPeriodConsumerHasNoRetainedHourSeries()
  {
    at:=DateTime.fromIso("2026-01-01T00:00:00Z");line:=EnerCubixLine("m|c","m","M","c","kWh")
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    consumer:=EnerCubixPeriodConsumer(line,at,at+1000hr,"hour",state,output,false)
    held:=0
    for(i:=0;i<1000;i++)
    {
      tick:=EnerCubixTick(at+Duration(i*1hr.ticks),at+Duration((i+1)*1hr.ticks),EnerCubixValue(1f,"ok",["p"]))
      consumer.add(tick)
      if(i==0) held=state.entries
      else verifyEq(state.entries,held)
    }
    consumer.finish;verify(consumer.periods.isEmpty);verifyEq(consumer.total.value,1000f)
    state.close;verifyEq(consumer.total.value,1000f);output.close;verifyEq(budget.temporary.val,0)
  }
  private Void same(EnerCubixValue actual,EnerCubixValue expected)
  {verifyEq(actual.value,expected.value);verifyEq(actual.quality,expected.quality);verifyEq(actual.sources,expected.sources)}
}

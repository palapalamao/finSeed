using [java] java.util::IdentityHashMap

** Fixed bins preserve independent hour and interval reductions, including DST.
class EnerCubixDailyConsumerTest : Test
{
  Void testSnapshotsChargeActualDetachedGraphAndShareOnlyEqualOrderedOutputSources()
  {
    at:=DateTime.fromIso("2026-01-01T00:00:00Z");line:=EnerCubixLine("m|c","m","M","c","kWh")
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    consumer:=EnerCubixDailyConsumer(line,state,output);ids:=["p","q"];reverse:=["q","p"]
    (0..<24).each |i|
    {value:=EnerCubixValue(i.toFloat,"ok",i==1 ? reverse : ids);tick:=EnerCubixTick(at+1hr*i,at+1hr*(i+1),value);tick.known=value;consumer.add(tick,"flat")}
    data:=consumer.finish;hours:=EnerCubixMath.maps(data["hours"])
    try
    {
      verifyEq(output.entries,5+graphEntries(data,IdentityHashMap()),"retained charge equals the physical snapshot graph, not a generic line-fold allowance")
      a:=(EnerCubixValue)hours[0]["value"];b:=(EnerCubixValue)hours[0]["known"];c:=(EnerCubixValue)hours[1]["value"];d:=(EnerCubixValue)hours[2]["value"];e:=(EnerCubixValue)hours[3]["value"]
      verify(a.sources===b.sources);verify(a.sources!==c.sources);verify(d.sources===e.sources)
      verifyEq(c.sources,["q","p"]);verifyEq(e.sources,["p","q"])
      ids.clear;reverse.clear;verifyEq(a.sources,["p","q"],"output sources must not alias frame inputs")
      state.close;verifyEq(a.value,0f)
      peer:=EnerCubixPreparedOwner(budget);peer.hold(budget.remaining);held:=peer.entries
      output.close;verify(data.isEmpty);verify(a.sources.isEmpty);verifyEq(budget.temporary.val,held);peer.close
    }
    finally {state.close;output.close}
    verifyEq(budget.temporary.val,0)
  }

  private Int graphEntries(Obj? value,IdentityHashMap seen)
  {
    if(value==null || (value isnot Map && value isnot List && value isnot EnerCubixValue) || seen.containsKey(value)) return 0
    seen.put(value,true)
    if(value is EnerCubixValue) return 3+graphEntries(((EnerCubixValue)value).sources,seen)
    n:=1+(value is Map ? ((Map)value).size : ((List)value).size)
    if(value is Map) ((Map)value).each |v| {n+=graphEntries(v,seen)}
    else ((List)value).each |v| {n+=graphEntries(v,seen)}
    return n
  }

  Void testPhysicalEnergyHoursRetainOnlyScalarReductionState()
  {
    at:=DateTime.fromIso("2026-01-01T00:00:00Z");line:=EnerCubixLine("m|c","m","M","c","kWh")
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    consumer:=EnerCubixDailyConsumer(line,state,output)
    (0..<48).each |i|
    {
      value:=EnerCubixValue(i==25 ? null : i.toFloat,i==25 ? "missing" : "ok",["p"])
      tick:=EnerCubixTick(at+1hr*i,at+1hr*(i+1),value)
      tick.known=i==25 ? EnerCubixValue(3f,"filtered",["p"]) : value
      consumer.add(tick,"flat");line.ticks.add(tick)
    }
    verify(consumer.stateEntries<=1100,"24 physical-energy bins must fit scalar folds, without retaining gauge/COP wrappers: ${consumer.stateEntries}")
    data:=consumer.finish
    EnerCubixMath.maps(data["hours"]).each |row|
    {ticks:=line.ticks.findAll |tick| {tick.ts.hour==row["hour"]};same((EnerCubixValue)row["value"],line.total(ticks));same((EnerCubixValue)row["known"],line.knownTotal(ticks))}
    peer:=EnerCubixPreparedOwner(budget);peer.hold(budget.remaining);held:=peer.entries
    state.close;output.close;verify(data.isEmpty);verifyEq(budget.temporary.val,held)
    peer.close;verifyEq(budget.temporary.val,0)
  }

  Void testFinishedDailyOutputReleasesItsBinStateBeforeTheParentReportCloses()
  {
    at:=DateTime.fromIso("2026-01-01T00:00:00Z");line:=EnerCubixLine("m|c","m","M","c","kWh")
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());parent:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    consumer:=EnerCubixDailyConsumer(line,parent,output)
    (0..<48).each |i|
    {tick:=EnerCubixTick(at+1hr*i,at+1hr*(i+1),EnerCubixValue(i.toFloat,"ok",["p"]));tick.known=tick.value;consumer.add(tick,"flat")}
    before:=budget.temporary.val;data:=consumer.finish
    verify(budget.temporary.val<before,"finished bin state must expire while detached output remains readable")
    hour:=EnerCubixMath.maps(data["hours"])[1];verifyEq(((EnerCubixValue)hour["value"]).value,26f)
    verifyEq(((EnerCubixValue)hour["known"]).value,26f)
    peer:=EnerCubixPreparedOwner(budget);peer.hold(budget.remaining);held:=peer.entries
    parent.close;verifyEq(((EnerCubixValue)hour["value"]).value,26f)
    output.close;verify(data.isEmpty);verifyEq(budget.temporary.val,held);peer.close;verifyEq(budget.temporary.val,0)
  }

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
      verifyEq(output.entries,5+graphEntries(data,IdentityHashMap()),"energy, gauge and COP charge their actual detached snapshots")
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

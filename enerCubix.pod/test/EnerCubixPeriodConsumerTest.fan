** Period and full-range reductions visit original ticks independently.
class EnerCubixPeriodConsumerTest : Test
{
  Void testPeriodSubtotalsCannotReplaceOriginalWholeRangeFloatOrder()
  {
    start:=DateTime.fromIso("2026-01-31T23:00:00Z");end:=start+3hr
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    consumer:=EnerCubixPeriodConsumer(line,start,end,"month",state,output)
    verifyErr(ArgErr#) {consumer.finish}
    values:=[10000000000000000f,1f,2f]
    values.each |value,i|
    {
      item:=tick(start+Duration(i*1hr.ticks),1hr,value)
      consumer.add(item);item.value.value=99f;item.value.sources.add("late")
    }
    consumer.finish
    rows:=consumer.periods
    verifyEq(rows.size,2);verifyEq(((EnerCubixValue)rows[0]["value"]).value,10000000000000000f)
    verifyEq(((EnerCubixValue)rows[1]["value"]).value,3f)
    verifyEq(consumer.total("value").value,10000000000000002f)
    verifyEq(consumer.total("value").sources,["p"])
    state.close // Results have their own owner and do not keep the folds alive.
    verifyEq(consumer.total("value").value,10000000000000002f)
    output.close;verify(rows.isEmpty);verifyEq(budget.temporary.val,0)
    verifyErr(ArgErr#) {consumer.periods}
  }

  Void testCopAndGaugeMatchExistingLineAndDoNotRetainTicks()
  {
    [false,true].each |gauge|
    {
      definition:=line;definition.ratio=!gauge;definition.gauge=gauge
      start:=at;end:=at+1hr
      a:=tick(start,20min,2f);b:=tick(start+20min,40min,8f)
      a.numerator=EnerCubixValue(10f,"ok",["n"]);a.denominator=EnerCubixValue(0f,"ok",["d"])
      b.numerator=EnerCubixValue(10f,"ok",["n"]);b.denominator=EnerCubixValue(10f,"ok",["d"])
      oracle:=line;oracle.ratio=definition.ratio;oracle.gauge=definition.gauge;oracle.ticks=[a,b]
      budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
      consumer:=EnerCubixPeriodConsumer(definition,start,end,"day",state,output)
      consumer.add(a);consumer.add(b);consumer.finish
      verifyEq(consumer.total("value").value,oracle.total.value)
      verifyEq(consumer.total("value").quality,oracle.total.quality)
      verifyEq(consumer.total("value").sources,oracle.total.sources)
      verify(definition.ticks.isEmpty)
      state.close;output.close;verifyEq(budget.temporary.val,0)
    }
  }

  Void testLocalDstPeriodAndQueryBoundsRemainExact()
  {
    zone:=TimeZone("New_York");start:=Date(2026,Month.nov,1).toDateTime(Time.defVal,zone)
    end:=Date(2026,Month.nov,2).toDateTime(Time.defVal,zone)
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    consumer:=EnerCubixPeriodConsumer(line,start,end,"day",state,output)
    verifyErr(ArgErr#) {consumer.add(tick(start+1hr,1hr,1f))}
    for(i:=0;i<25;i++) consumer.add(tick(start+Duration(i*1hr.ticks),1hr,1f))
    consumer.finish;rows:=consumer.periods
    verifyEq(rows.size,1);verifyEq(rows.first["samples"],25)
    verifyEq(rows.first["from"],start.toIso);verifyEq(rows.first["to"],end.toIso)
    verifyEq(consumer.total("value").value,25f)
    state.close;output.close;verifyEq(budget.temporary.val,0)
  }

  Void testOutputAdmissionFailureCannotPublishOrRetryHalfFinishedResult()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    consumer:=EnerCubixPeriodConsumer(line,at,at+2day,"day",state,output)
    for(i:=0;i<48;i++) consumer.add(tick(at+Duration(i*1hr.ticks),1hr,1f))
    peer:=EnerCubixPreparedOwner(budget);peer.hold(budget.remaining)
    held:=peer.entries
    verifyErr(EnerCubixHttpErr#) {consumer.finish}
    verifyErr(EnerCubixHttpErr#) {consumer.finish}
    verifyErr(EnerCubixHttpErr#) {consumer.periods}
    state.close;output.close;verifyEq(budget.temporary.val,held)
    peer.close;verifyEq(budget.temporary.val,0)
  }

  private EnerCubixLine line() {EnerCubixLine("m|c","m","M","c","kWh")}
  private EnerCubixTick tick(DateTime start,Duration length,Float value)
  {
    item:=EnerCubixTick(start,start+length,EnerCubixValue(value,"ok",["p"]))
    item.known=EnerCubixValue(value,"ok",["p"])
    return item
  }
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

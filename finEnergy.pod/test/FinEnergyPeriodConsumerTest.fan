** Period and full-range reductions visit original ticks independently.
class FinEnergyPeriodConsumerTest : Test
{
  Void testUnnormalizedBaseFoldsShareStateWithoutChangingAnyResult()
  {
    budget:=FinEnergyStreamBudget().state;a:=FinEnergyPreparedOwner(budget);ao:=FinEnergyPreparedOwner(budget);b:=FinEnergyPreparedOwner(budget);bo:=FinEnergyPreparedOwner(budget)
    expected:=FinEnergyPeriodConsumer(line,at,at+3hr,"hour",a,ao)
    actual:=FinEnergyPeriodConsumer(line,at,at+3hr,"hour",b,bo,true,true)
    try
    {
      [2f,null,0f].each |Float? number,Int i|
      {
        value:=FinEnergyValue(number,i==1 ? "na" : "ok",["p"]);item:=FinEnergyTick(at+1hr*i,at+1hr*(i+1),value);item.known=FinEnergyValue(number,i==1 ? "na" : "ok",["p"]);item.baseValue=item.value;item.baseKnown=item.known
        expected.add(item);actual.add(item)
      }
      expected.finish;actual.finish
      ["value","known","baseValue","baseKnown"].each |mode|
      {
        x:=expected.total(mode);y:=actual.total(mode);verifyEq(y.value,x.value);verifyEq(y.quality,x.quality);verifyEq(y.sources,x.sources)
        expected.periods.each |row,i| {xv:=(FinEnergyValue)row[mode];yv:=(FinEnergyValue)actual.periods[i][mode];verifyEq(yv.value,xv.value);verifyEq(yv.quality,xv.quality);verifyEq(yv.sources,xv.sources)}
      }
      verify(actual.total("value")===actual.total("baseValue"));verify(actual.total("known")===actual.total("baseKnown"))
      verify(b.entries<a.entries);verify(bo.entries<ao.entries)
      a.close;b.close;verifyEq(actual.total.value,expected.total.value)
    }
    finally {a.close;ao.close;b.close;bo.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testSharedBaseContractRejectsDifferentBaseValues()
  {
    budget:=FinEnergyStreamBudget().state;state:=FinEnergyPreparedOwner(budget);output:=FinEnergyPreparedOwner(budget)
    consumer:=FinEnergyPeriodConsumer(line,at,at+1hr,"hour",state,output,true,true)
    item:=tick(at,1hr,1f);item.baseValue=FinEnergyValue(2f,"ok",["p"])
    try {verifyErr(ArgErr#) {consumer.add(item)};verifyErr(ArgErr#) {consumer.finish}}
    finally {state.close;output.close}
    verifyEq(budget.temporary.val,0)
  }

  Void testPeriodSubtotalsCannotReplaceOriginalWholeRangeFloatOrder()
  {
    start:=DateTime.fromIso("2026-01-31T23:00:00Z");end:=start+3hr
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());state:=FinEnergyPreparedOwner(budget);output:=FinEnergyPreparedOwner(budget)
    consumer:=FinEnergyPeriodConsumer(line,start,end,"month",state,output)
    verifyErr(ArgErr#) {consumer.finish}
    values:=[10000000000000000f,1f,2f]
    values.each |value,i|
    {
      item:=tick(start+Duration(i*1hr.ticks),1hr,value)
      consumer.add(item);item.value.value=99f;item.value.sources.add("late")
    }
    consumer.finish
    rows:=consumer.periods
    verifyEq(rows.size,2);verifyEq(((FinEnergyValue)rows[0]["value"]).value,10000000000000000f)
    verifyEq(((FinEnergyValue)rows[1]["value"]).value,3f)
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
      a.numerator=FinEnergyValue(10f,"ok",["n"]);a.denominator=FinEnergyValue(0f,"ok",["d"])
      b.numerator=FinEnergyValue(10f,"ok",["n"]);b.denominator=FinEnergyValue(10f,"ok",["d"])
      oracle:=line;oracle.ratio=definition.ratio;oracle.gauge=definition.gauge;oracle.ticks=[a,b]
      budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());state:=FinEnergyPreparedOwner(budget);output:=FinEnergyPreparedOwner(budget)
      consumer:=FinEnergyPeriodConsumer(definition,start,end,"day",state,output)
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
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());state:=FinEnergyPreparedOwner(budget);output:=FinEnergyPreparedOwner(budget)
    consumer:=FinEnergyPeriodConsumer(line,start,end,"day",state,output)
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
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());state:=FinEnergyPreparedOwner(budget);output:=FinEnergyPreparedOwner(budget)
    consumer:=FinEnergyPeriodConsumer(line,at,at+2day,"day",state,output)
    for(i:=0;i<48;i++) consumer.add(tick(at+Duration(i*1hr.ticks),1hr,1f))
    peer:=FinEnergyPreparedOwner(budget);peer.hold(budget.remaining)
    held:=peer.entries
    verifyErr(FinEnergyHttpErr#) {consumer.finish}
    verifyErr(FinEnergyHttpErr#) {consumer.finish}
    verifyErr(FinEnergyHttpErr#) {consumer.periods}
    state.close;output.close;verifyEq(budget.temporary.val,held)
    peer.close;verifyEq(budget.temporary.val,0)
  }

  private FinEnergyLine line() {FinEnergyLine("m|c","m","M","c","kWh")}
  private FinEnergyTick tick(DateTime start,Duration length,Float value)
  {
    item:=FinEnergyTick(start,start+length,FinEnergyValue(value,"ok",["p"]))
    item.known=FinEnergyValue(value,"ok",["p"])
    return item
  }
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

class FinEnergyWorkingConsumerTest : Test
{
  Void testClassifiedEnergyGaugeAndCopMatchOriginalDstSequences()
  {
    ["energy","gauge","cop"].each |mode|
    {
      line:=FinEnergyLine("m|c","m","M","c","kWh");line.gauge=mode=="gauge";line.ratio=mode=="cop"
      at:=Date(2026,Month.nov,1).toDateTime(Time.defVal,TimeZone("New_York"))
      budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());state:=FinEnergyPreparedOwner(budget);output:=FinEnergyPreparedOwner(budget)
      consumer:=FinEnergyWorkingConsumer(line,state,output)
      for(i:=0;i<25;i++)
      {
        start:=at+Duration(i*1hr.ticks);end:=start+(i==24 ? 20min : 1hr)
        v:=FinEnergyValue(i==2 ? null : (i==0 ? 10000000000000000f : i.toFloat),i==2 ? "na" : "ok",["p$i"])
        tick:=FinEnergyTick(start,end,v);tick.known=v
        tick.numerator=FinEnergyValue(i.toFloat,"ok",["n$i"]);tick.denominator=FinEnergyValue(i==0 ? 0f : 2f,"ok",["d$i"])
        consumer.add(tick,tick.ts.hour==1);line.ticks.add(tick)
      }
      data:=consumer.finish
      (0..1).each |i|
      {
        ticks:=line.ticks.findAll |t| {(t.ts.hour==1)==(i==0)}
        same((FinEnergyValue)data[i]["value"],line.total(ticks));same((FinEnergyValue)data[i]["known"],line.knownTotal(ticks))
        verifyEq(data[i]["samples"],ticks.size)
      }
      verifyEq(data[0]["samples"],2)
      escaped:=data.first;value:=(FinEnergyValue)escaped["value"]
      state.close;verifyEq(data.size,2);output.close;verify(data.isEmpty);verify(escaped.isEmpty);verify(value.sources.isEmpty);verifyEq(value.quality,"ownerExpired")
      verifyEq(budget.temporary.val,0);verifyErr(ArgErr#) {consumer.finish}
    }
  }

  Void testEmptyGroupIsZeroAndNonemptyMissingGroupStaysMissing()
  {
    line:=FinEnergyLine("m|c","m","M","c","kWh");at:=DateTime.fromIso("2026-01-01T00:00:00Z")
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());state:=FinEnergyPreparedOwner(budget);output:=FinEnergyPreparedOwner(budget)
    consumer:=FinEnergyWorkingConsumer(line,state,output)
    tick:=FinEnergyTick(at,at+1hr,FinEnergyValue(null,"na",["p"]));tick.known=tick.value
    consumer.add(tick,false);data:=consumer.finish
    verifyEq(((FinEnergyValue)data[0]["value"]).value,0f);verifyEq(((FinEnergyValue)data[0]["known"]).quality,"ok")
    verifyEq(((FinEnergyValue)data[1]["value"]).value,null);verifyEq(((FinEnergyValue)data[1]["value"]).quality,"na")
    verifyEq(data[0]["samples"],0);verifyEq(data[1]["samples"],1)
    state.close;output.close;verifyEq(budget.temporary.val,0)
  }

  Void testOutputRejectionLeavesPeerAllocationAndNoPartialRows()
  {
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());state:=FinEnergyPreparedOwner(budget);output:=FinEnergyPreparedOwner(budget)
    consumer:=FinEnergyWorkingConsumer(FinEnergyLine("m|c","m","M","c","kWh"),state,output)
    peer:=FinEnergyPreparedOwner(budget);peer.hold(budget.remaining);held:=peer.entries
    verifyErr(FinEnergyHttpErr#) {consumer.finish}
    state.close;output.close;verifyEq(budget.temporary.val,held);peer.close;verifyEq(budget.temporary.val,0)
  }
  private Void same(FinEnergyValue actual,FinEnergyValue expected)
  {verifyEq(actual.value,expected.value);verifyEq(actual.quality,expected.quality);verifyEq(actual.sources,expected.sources)}
}

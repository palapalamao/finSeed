class EnerCubixWorkingConsumerTest : Test
{
  Void testClassifiedEnergyGaugeAndCopMatchOriginalDstSequences()
  {
    ["energy","gauge","cop"].each |mode|
    {
      line:=EnerCubixLine("m|c","m","M","c","kWh");line.gauge=mode=="gauge";line.ratio=mode=="cop"
      at:=Date(2026,Month.nov,1).toDateTime(Time.defVal,TimeZone("New_York"))
      budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
      consumer:=EnerCubixWorkingConsumer(line,state,output)
      for(i:=0;i<25;i++)
      {
        start:=at+Duration(i*1hr.ticks);end:=start+(i==24 ? 20min : 1hr)
        v:=EnerCubixValue(i==2 ? null : (i==0 ? 10000000000000000f : i.toFloat),i==2 ? "na" : "ok",["p$i"])
        tick:=EnerCubixTick(start,end,v);tick.known=v
        tick.numerator=EnerCubixValue(i.toFloat,"ok",["n$i"]);tick.denominator=EnerCubixValue(i==0 ? 0f : 2f,"ok",["d$i"])
        consumer.add(tick,tick.ts.hour==1);line.ticks.add(tick)
      }
      data:=consumer.finish
      (0..1).each |i|
      {
        ticks:=line.ticks.findAll |t| {(t.ts.hour==1)==(i==0)}
        same((EnerCubixValue)data[i]["value"],line.total(ticks));same((EnerCubixValue)data[i]["known"],line.knownTotal(ticks))
        verifyEq(data[i]["samples"],ticks.size)
      }
      verifyEq(data[0]["samples"],2)
      escaped:=data.first;value:=(EnerCubixValue)escaped["value"]
      state.close;verifyEq(data.size,2);output.close;verify(data.isEmpty);verify(escaped.isEmpty);verify(value.sources.isEmpty);verifyEq(value.quality,"ownerExpired")
      verifyEq(budget.temporary.val,0);verifyErr(ArgErr#) {consumer.finish}
    }
  }

  Void testEmptyGroupIsZeroAndNonemptyMissingGroupStaysMissing()
  {
    line:=EnerCubixLine("m|c","m","M","c","kWh");at:=DateTime.fromIso("2026-01-01T00:00:00Z")
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    consumer:=EnerCubixWorkingConsumer(line,state,output)
    tick:=EnerCubixTick(at,at+1hr,EnerCubixValue(null,"na",["p"]));tick.known=tick.value
    consumer.add(tick,false);data:=consumer.finish
    verifyEq(((EnerCubixValue)data[0]["value"]).value,0f);verifyEq(((EnerCubixValue)data[0]["known"]).quality,"ok")
    verifyEq(((EnerCubixValue)data[1]["value"]).value,null);verifyEq(((EnerCubixValue)data[1]["value"]).quality,"na")
    verifyEq(data[0]["samples"],0);verifyEq(data[1]["samples"],1)
    state.close;output.close;verifyEq(budget.temporary.val,0)
  }

  Void testOutputRejectionLeavesPeerAllocationAndNoPartialRows()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    consumer:=EnerCubixWorkingConsumer(EnerCubixLine("m|c","m","M","c","kWh"),state,output)
    peer:=EnerCubixPreparedOwner(budget);peer.hold(budget.remaining);held:=peer.entries
    verifyErr(EnerCubixHttpErr#) {consumer.finish}
    state.close;output.close;verifyEq(budget.temporary.val,held);peer.close;verifyEq(budget.temporary.val,0)
  }
  private Void same(EnerCubixValue actual,EnerCubixValue expected)
  {verifyEq(actual.value,expected.value);verifyEq(actual.quality,expected.quality);verifyEq(actual.sources,expected.sources)}
}

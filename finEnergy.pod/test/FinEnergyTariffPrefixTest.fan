using haystack

** Controlled canonical-prefix regression; never creates FIN field data.
class FinEnergyTariffPrefixTest : Test
{
  Void testPartialQueryCannotPoisonFollowingCanonicalHour()
  {
    ["monthlyBlock","yearlyBlock"].each |mode|
    {
      [false,true].each |budgeted|
      {
        cold:=context(mode,[1f,1f],"cleaned",budgeted)
        amount(cold.node("m","c",at+1hr,at+2hr,"cost"),1f)
        warm:=context(mode,[1f,1f],"cleaned",budgeted)
        partial:=warm.node("m","c",at+13min,at+1hr,"cost")
        verifyNull(partial.value);verifyEq(partial.quality,"missingTariffBaseline")
        amount(warm.node("m","c",at+1hr,at+2hr,"cost"),1f)
        for(i:=0;i<129;i++) warm.node("other$i","c",at,at+1hr,"cost")
        amount(warm.node("m","c",at+1hr,at+2hr,"cost"),1f)
        reverse:=context(mode,[1f,1f],"cleaned",budgeted)
        amount(reverse.node("m","c",at+1hr,at+2hr,"cost"),1f)
        reverse.node("m","c",at+13min,at+1hr,"cost")
        amount(reverse.node("m","c",at+1hr,at+2hr,"cost"),1f)
      }
    }
  }

  Void testActualMissingOrUnreliablePrefixCannotPriceCompleteLaterHour()
  {
    ["missing","na","filtered","substituted","reset","negative"].each |quality|
    {
      ctx:=context("monthlyBlock",[1f,1f],quality)
      verifyEq(ctx.node("m","c",at+1hr,at+2hr,"energy").value,1f)
      value:=ctx.node("m","c",at+1hr,at+2hr,"cost")
      verifyNull(value.value);verify(!["ok","cleaned"].contains(value.quality))
    }
    zero:=context("monthlyBlock",[0f,0f])
    zero.node("m","c",at+13min,at+1hr,"cost")
    amount(zero.node("m","c",at+1hr,at+2hr,"cost"),0f)
    maximum:=context("monthlyBlock",[100f,1f]);maximum.byId["m"]["maximum"]=2f
    verifyEq(maximum.node("m","c",at+1hr,at+2hr,"energy").value,1f)
    verifyNull(maximum.node("m","c",at+1hr,at+2hr,"cost").value)
  }

  Void testMultiHourRawSumCannotReplaceCanonicalHourlyPrefix()
  {
    intervals:=[Str:Obj?][["from":at.toIso,"to":(at+30min).toIso,"value":10000000000000000f,"quality":"cleaned"],["from":(at+30min).toIso,"to":(at+1hr).toIso,"value":1f,"quality":"cleaned"],["from":(at+1hr).toIso,"to":(at+90min).toIso,"value":1f,"quality":"cleaned"],["from":(at+90min).toIso,"to":(at+2hr).toIso,"value":1f,"quality":"cleaned"],["from":(at+2hr).toIso,"to":(at+3hr).toIso,"value":1f,"quality":"cleaned"]]
    [false,true].each |budgeted|
    {
      cold:=contextRows("monthlyBlock",intervals,budgeted)
      amount(cold.node("m","c",at+2hr,at+3hr,"cost"),2f)
      warm:=contextRows("monthlyBlock",intervals,budgeted)
      amount(warm.node("m","c",at,at+2hr,"cost"),10000000000000000f)
      amount(warm.node("m","c",at+2hr,at+3hr,"cost"),2f)
    }
  }

  Void testIndependentDeviceTariffsThresholdAndNewCycle()
  {
    ctx:=context("monthlyBlock",[9f,2f])
    ctx.byId["t"]["blocks"]=[["limit":10f,"rate":1f],["rate":2f]]
    ctx.byId["twice"]=["id":"twice","kind":"tariff","mode":"monthlyBlock","blocks":[["rate":2f]]]
    ctx.byId["alias"]=["id":"alias","kind":"meter","pointId":"p","categoryId":"c","tariffId":"twice"]
    ctx.node("m","c",at+13min,at+1hr,"cost")
    amount(ctx.node("m","c",at+1hr,at+2hr,"cost"),3f)
    amount(ctx.node("alias","c",at+1hr,at+2hr,"cost"),4f)
    // Missing previous-cycle history must not invalidate the new cycle's zero baseline.
    ["monthlyBlock","yearlyBlock"].each |mode|
    {
      old:=DateTime.fromIso("2025-12-31T23:00:00Z")
      cycle:=context(mode,[9f,2f],"cleaned",true,old)
      verifyNull(cycle.node("m","c",old,old+1hr,"cost").value)
      amount(cycle.node("m","c",old+1hr,old+2hr,"cost"),2f)
    }
  }

  Void testCanonicalPrefixKeepsOriginalHourlyFloatOrder()
  {
    ctx:=context("monthlyBlock",[10000000000000000f,1f,2f,1f])
    // Original Float sum is (big+1)+2 = big+2; price(big+3)-price(big+2)=2.
    // This preserves existing arithmetic rather than introducing new rounding.
    amount(ctx.node("m","c",at+3hr,at+4hr,"cost"),2f)
    ctx.node("m","c",at+13min,at+1hr,"cost")
    amount(ctx.node("m","c",at+3hr,at+4hr,"cost"),2f)
  }

  Void testPreparedPlanContainsPartialBillingPrefixWithoutExtraNativeRange()
  {
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c","tariffId":"t"],["id":"t","kind":"tariff","mode":"monthlyBlock","blocks":[["rate":1f]]]]
    p:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"])
    q:=Str:Obj?["kind":"profile","nodeIds":["m"],"categoryIds":["c"],"metric":"cost","period":"day","from":(at+13min).toIso,"to":(at+2hr).toIso,"asOf":(at+2hr).toIso,"tz":"UTC","_cockpitRanges":[["from":at.toIso,"to":(at+2hr).toIso,"pointIds":["p"]]]]
    q["_cockpitReadRanges"]=[q.dup]
    raw:=[HisItem(at,Number(0)),HisItem(at+1hr,Number(10)),HisItem(at+2hr,Number(20))]
    budget:=FinEnergyStreamBudget()
    hs:=FinEnergyCockpitStream.prepare(q,rs,["p":p],Str:Dict[:],|Dict pt,Span span,|HisItem| sink|
    {verifyEq(span.start,at-1day);verifyEq(span.end,at+2hr+1day);raw.each |row| {sink(row)}},budget)
    oracle:=FinEnergyEngine.report(q,rs,[FinEnergyHistory.normalize(p,raw,at,at+2hr)])
    actual:=FinEnergyEngine.report(q,rs,hs)
    verifyEq(actual["summary"],oracle["summary"]);verifyEq(actual["series"],oracle["series"])
    verifyEq(budget.state.unprepared.val,0);verifyEq(budget.nativeReads,1)
  }

  private Void amount(FinEnergyValue value,Float expected)
  {verifyEq(value.value,expected);verifyEq(value.quality,"cleaned");verifyEq(value.sources,["p"])}

  private FinEnergyContext context(Str mode,Float[] values := [1f,1f],Str firstQuality := "cleaned",Bool budgeted := true,DateTime start := at)
  {
    intervals:=[Str:Obj?][,]
    values.each |v,i|
    {
      quality:=i == 0 ? firstQuality : "cleaned"
      if(quality == "missing") return
      intervals.add(["from":(start+Duration(i*1hr.ticks)).toIso,"to":(start+Duration((i+1)*1hr.ticks)).toIso,"value":quality == "cleaned" ? v : null,"quality":quality,"valueType":quality == "na" ? "na" : (quality == "cleaned" ? "number" : "null")])
    }
    return contextRows(mode,intervals,budgeted)
  }
  private FinEnergyContext contextRows(Str mode,[Str:Obj?][] intervals,Bool budgeted)
  {
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"t","kind":"tariff","mode":mode,"blocks":[["rate":1f]]],["id":"m","kind":"meter","pointId":"p","categoryId":"c","tariffId":"t"]]
    for(i:=0;i<129;i++) rs.add(["id":"other$i","kind":"meter","pointId":"p$i","categoryId":"c","tariffId":"t"])
    hs:=[Str:Obj?][["pointId":"p","unit":"kWh","mode":"interval","quality":"cleaned","intervals":intervals]]
    for(i:=0;i<129;i++) hs.add(hs.first.dup.set("pointId","p$i"))
    if(budgeted) hs.first["_preparedBudget"]=FinEnergyPreparedBudget(FinEnergyCockpitDeadline())
    return FinEnergyContext(rs,hs,TimeZone.utc)
  }
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

using haystack

** Same primary-point data through whole-source and expiring-frame readers.
class FinEnergyTariffCursorTest : Test
{
  Void testPartialFirstHourStillPricesFollowingHoursAfterFramesExpire()
  {
    ["monthlyBlock","yearlyBlock"].each |mode|
    {
      [false,true].each |cleaned| {replay(mode,cleaned)}
    }
  }

  Void testPrimaryQualityMaximumAndUnitConversionRemainDeviceSpecific()
  {
    replay("monthlyBlock",true,[0,NA.val,20,30,40])
    replay("monthlyBlock",true,[0,null,20,30,40])
    replay("monthlyBlock",true,[90,1,11,21,31])
    replay("monthlyBlock",true,[0,20,30,40,50],15f)
    replay("yearlyBlock",false,[0,10000,20000,30000,40000],null,"Wh")
    replay("monthlyBlock",false,[0f,10000000000000000f,10000000000000000f,10000000000000002f,10000000000000004f])
  }

  Void testNewMonthResetsUnreliableEarlierPrefixAndNewYearStartsAtZero()
  {
    values:=Obj?[,];(0..746).each |i| {values.add(i == 1 ? NA.val : i*10)}
    replay("monthlyBlock",true,values)
    replay("yearlyBlock",true,null,null,"kWh",DateTime.fromIso("2027-01-01T00:00:00Z"))
  }

  Void testUnpreparedAdvanceFailsWithoutChangingCanonicalPrefix()
  {
    records:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c","tariffId":"t"],["id":"t","kind":"tariff","mode":"monthlyBlock","blocks":[["rate":1f]]]]
    budget:=FinEnergyStreamBudget();owner:=FinEnergyPreparedOwner(budget.state)
    ctx:=FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    verifyErr(ArgErr#) {invalid:=FinEnergyTariffCursor(ctx,"m",at+13min,owner)}
    billing:=FinEnergyTariffCursor(ctx,"m",at,owner)
    p:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"])
    q:=Str:Obj?["from":at.toIso,"to":(at+2hr).toIso,"asOf":(at+2hr).toIso,"tz":"UTC"]
    raw:=[HisItem(at,Number(0)),HisItem(at+1hr,Number(10)),HisItem(at+2hr,Number(20))]
    cursor:=FinEnergyCockpitStream.openCursor(p,null,at,at+2hr,q,records,budget,|Dict point,Span span,|HisItem| sink| {raw.each |row| {if(row.ts>=span.start && row.ts<span.end) sink(row)}})
    cursor.advance(at+1hr)
    cursor.withFrame |h|
    {
      frame:=FinEnergyPreparedOwner(budget.state);ctx.beginFrame(frame,["p":h])
      billing.consumeHour;verifyErr(ArgErr#) {billing.consumeHour}
      frame.close
    }
    cursor.advance(at+2hr)
    cursor.withFrame |h|
    {
      frame:=FinEnergyPreparedOwner(budget.state);ctx.beginFrame(frame,["p":h])
      verifyEq(ctx.node("m","c",at+1hr,at+2hr,"cost").value,10f)
      billing.consumeHour;frame.close
    }
    cursor.close;owner.close;verifyEq(budget.state.temporary.val,0)
  }

  private Void replay(Str mode,Bool cleaned,Obj?[]? values := null,Float? maximum := null,Str unit := "kWh",DateTime begin := at)
  {
    values=values ?: [0,10,20,30,40]
    hours:=values.size-1;end:=begin+Duration(hours*1hr.ticks)
    records:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c","tariffId":"t","maximum":maximum],["id":"alias","kind":"meter","pointId":"p","categoryId":"c","tariffId":"double"],["id":"t","kind":"tariff","mode":mode,"blocks":[["limit":15f,"rate":1f],["rate":2f]]],["id":"double","kind":"tariff","mode":mode,"blocks":[["rate":2f]]]]
    cfg:=Etc.makeDict(["defNull":Marker.val])
    tags:=Str:Obj?["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":unit,"tz":"UTC"]
    if(cleaned) tags.setAll(["hisFunc":"finEnergyCleanHis","hisFuncConfig":cfg])
    p:=Etc.makeDict(tags)
    q:=Str:Obj?["from":(begin+13min).toIso,"to":end.toIso,"asOf":end.toIso,"tz":"UTC","_cockpitRanges":[["from":begin.toIso,"to":end.toIso,"pointIds":["p"]]]]
    raw:=HisItem[,];values.each |v,i| {raw.add(HisItem(begin+Duration(i*1hr.ticks),v is Int ? Number((Int)v) : (v is Float ? Number((Float)v) : v)))}
    read:=|Dict point,Span span,|HisItem| sink| {raw.each |row| {if(row.ts>=span.start && row.ts<span.end) sink(row)}}
    whole:=FinEnergyContext(records,FinEnergyCockpitStream.prepare(q,records,["p":p],cleaned ? ["p":cfg] : Str:Dict[:],read,FinEnergyStreamBudget()),TimeZone.utc)
    budget:=FinEnergyStreamBudget();owner:=FinEnergyPreparedOwner(budget.state)
    ctx:=FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    billing:=FinEnergyTariffCursor(ctx,"m",begin,owner)
    other:=FinEnergyTariffCursor(ctx,"alias",begin,owner)
    known:=FinEnergyContext.known(ctx,end);expectedKnown:=FinEnergyContext.known(whole,end)
    cursor:=FinEnergyCockpitStream.openCursor(p,cleaned ? cfg : null,begin,end,q,records,budget,read)
    stable:=0
    for(i:=0;i<hours;i++)
    {
      hour:=begin+Duration(i*1hr.ticks);finish:=hour+1hr;start:=i == 0 ? hour+13min : hour
      cursor.advance(finish)
      cursor.withFrame |h|
      {
        frame:=FinEnergyPreparedOwner(budget.state);ctx.beginFrame(frame,["p":h]);known.beginFrame(frame,["p":h])
        ["m","alias"].each |id|
        {
          [false,true].each |observed|
          {
            expected:=(observed ? expectedKnown : whole).node(id,"c",start,finish,"cost")
            actual:=(observed ? known : ctx).node(id,"c",start,finish,"cost")
            verifyEq(actual.value,expected.value);verifyEq(actual.quality,expected.quality);verifyEq(actual.sources,expected.sources)
          }
        }
        billing.consumeHour;other.consumeHour
        verifyErr(ArgErr#) {billing.baseline(start,finish,Str[,])}
        frame.close
        if(i == 2) stable=owner.entries
        else if(i > 2) verifyEq(owner.entries,stable)
      }
    }
    verifyEq(budget.state.unprepared.val,0)
    cursor.close;owner.close;verifyEq(budget.state.temporary.val,0)
    verifyErr(ArgErr#) {billing.consumeHour}
  }
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

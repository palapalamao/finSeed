** A normal report may seal its fee catalog; mutable direct contexts stay live.
class FinEnergyTariffSnapshotTest : Test
{
  Void testSealedDefaultsScanTheCatalogOnlyOnce()
  {
    ctx:=context(records)
    ctx.sealTariffs
    meter:=ctx.byId["m"]
    200.times {verifyEq(ctx.tariff(meter)?.get("rate"),2f)}
    verifyEq(ctx.tariffCatalogScans,1)
    known:=FinEnergyContext.known(ctx,at+4hr)
    200.times {verifyEq(known.tariff(meter)?.get("rate"),2f)}
    verifyEq(known.tariffCatalogScans,0)
  }

  Void testUnsealedContextStillSeesTariffReplacementAndAmbiguity()
  {
    rs:=records;ctx:=context(rs);meter:=ctx.byId["m"]
    verifyEq(ctx.tariff(meter)?.get("rate"),2f)
    ctx.byId["t"]["rate"]=3f;verifyEq(ctx.tariff(meter)?.get("rate"),3f)
    ctx.byId["other"]=["id":"other","kind":"tariff","categoryId":"e","isDefault":true,"mode":"flat","rate":4f]
    verifyNull(ctx.tariff(meter))
    ctx.byId.remove("other");verifyEq(ctx.tariff(meter)?.get("rate"),3f)
    ctx.byId["t"]=["id":"t","kind":"tariff","categoryId":"e","isDefault":true,"mode":"flat","rate":5f]
    verifyEq(ctx.tariff(meter)?.get("rate"),5f)
  }

  Void testSealedTariffConfigurationIsDeepAndRequestLocal()
  {
    rs:=records
    rs.last["rules"]=[["startHour":0f,"endHour":24f,"rate":3f]]
    first:=context(rs);first.sealTariffs
    ((Map)((List)rs.last["rules"]).first)["rate"]=9f
    verifyEq(((Map)((List)first.tariff(first.byId["m"])["rules"]).first)["rate"],3f)
    next:=context(rs);next.sealTariffs
    verifyEq(((Map)((List)next.tariff(next.byId["m"])["rules"]).first)["rate"],9f)
  }

  Void testSealedPricingRetainsBoundaryOrderAndInputRepresentations()
  {
    cases:=[Str:Obj?][
      ["mode":"flat","rate":2f,"rules":[["startHour":0.5f,"rate":4f]],"exceptions":[["from":"2026-11-01","to":"2026-11-02","rate":3f]]],
      ["mode":"weekly","rate":1f,"rules":[["startHour":0f,"endHour":24f,"rate":2f],["startHour":0f,"endHour":24f,"rate":5f]],"exceptions":[["from":at.toIso,"to":(at+2hr).toIso,"rate":7f],["from":at.toIso,"to":(at+1hr).toIso,"rate":9f]]],
      ["mode":"weekly","rate":1f,"rules":[["startHour":23f,"endHour":2f,"rate":3f],["startHour":0f,"endHour":1f,"rate":null]]],
      ["mode":"monthlyBlock","blocks":[["limit":15f,"rate":1f],["limit":null,"rate":2f]]],
      ["mode":"yearlyBlock","blocks":[["limit":15f,"rate":1f],["limit":null,"rate":2f]]]]
    cases.each |tariff|
    {
      [false,true].each |closed|
      {
        rs:=records;rs.last.setAll(tariff)
        before:=context(rs,closed);after:=context(rs,closed);after.sealTariffs
        oldKnown:=FinEnergyContext.known(before,at+4hr);newKnown:=FinEnergyContext.known(after,at+4hr)
        (0..<4).each |i|
        {
          from:=at+1hr*i;to:=from+1hr
          sameValue(before.node("m","e",from,to,"cost"),after.node("m","e",from,to,"cost"))
          sameValue(oldKnown.node("m","e",from,to,"cost"),newKnown.node("m","e",from,to,"cost"))
          verifyEq(before.timeBand("m","e",from,to),after.timeBand("m","e",from,to))
        }
        verifyEq(after.usedTariffs,before.usedTariffs)
      }
    }
  }

  Void testSealedDefaultsPreserveInvalidReferencesAndLastIdWins()
  {
    rs:=records;rs.add(rs.last.dup.set("rate",7f))
    ctx:=context(rs);ctx.sealTariffs;meter:=ctx.byId["m"]
    verifyEq(ctx.tariff(meter)?.get("rate"),7f)
    verifyNull(ctx.tariff(meter.dup.set("tariffId","absent")))
    verify(ctx.tariff(meter.dup.set("tariffId","e"))===ctx.byId["e"])
    [null,"",1].each |category|
    {
      rs=records;rs[1]["categoryId"]=category;rs.last["categoryId"]=category
      old:=context(rs);sealed:=context(rs);sealed.sealTariffs
      verifyEq(sealed.tariff(sealed.byId["m"]),old.tariff(old.byId["m"]))
    }
  }

  Void testBoundMeterSharesSnapshotButBoundTariffRebuildsLookup()
  {
    rs:=records;rs.add(["id":"other","kind":"tariff","categoryId":"e","mode":"flat","rate":8f])
    ctx:=context(rs);ctx.sealTariffs
    meter:=ctx.byId["m"].dup.set("tariffId","other")
    bound:=FinEnergyContext.bound(ctx,"m",meter)
    verifyEq(bound.tariff(meter)?.get("rate"),8f)
    changed:=ctx.byId["t"].dup.set("rate",9f)
    bound=FinEnergyContext.bound(ctx,"t",changed)
    verifyEq(bound.tariff(bound.byId["m"])?.get("rate"),9f)
    verifyEq(ctx.tariff(ctx.byId["m"])?.get("rate"),2f)
    bound=FinEnergyContext.bound(ctx,"new",changed.dup.set("id","new"))
    verifyNull(bound.tariff(bound.byId["m"]))
  }

  Void testPreparedContextDoesNotSealItsCatalog()
  {
    ctx:=context(records);ctx.preparedBudget=FinEnergyPreparedBudget(FinEnergyCockpitDeadline())
    ctx.sealTariffs
    verifyEq(ctx.tariffCatalogScans,0)
  }

  private FinEnergyContext context([Str:Obj?][] rs,Bool closed := false)
  {
    rows:=(0..<4).map |i->[Str:Obj?]| {return closed ? ["from":(at+1hr*i).toIso,"to":(at+1hr*(i+1)).toIso,"value":10f,"quality":"cleaned"] : ["ts":(at+1hr*i).toIso,"value":10f]}
    h:=Str:Obj?["pointId":"p","unit":"kWh","mode":"interval",closed ? "intervals" : "samples":rows]
    return FinEnergyContext(rs,[h],TimeZone.utc)
  }
  private [Str:Obj?][] records()
  {[["id":"e","kind":"category","unit":"kWh"],["id":"m","kind":"meter","name":"Meter","pointId":"p","categoryId":"e"],["id":"t","mod":"m1","kind":"tariff","name":"Tariff","categoryId":"e","isDefault":true,"mode":"flat","rate":2f]]}
  private Void sameValue(FinEnergyValue a,FinEnergyValue b) {verifyEq(a.value,b.value);verifyEq(a.quality,b.quality);verifyEq(a.sources,b.sources)}
  private DateTime at() {DateTime.fromIso("2026-11-01T00:00:00Z")}
}

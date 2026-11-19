class FinEnergyLineFoldTest : Test
{
  Void testOwnedRatioAndGaugeStateExpiresWithItsOwner()
  {
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());owner:=FinEnergyPreparedOwner(budget)
    line:=definition;line.ratio=true
    ratio:=FinEnergyLineFold(line,"value",owner)
    item:=tick(0f,"ok",["p"]);item.numerator=FinEnergyValue(10f,"ok",["n"]);item.denominator=FinEnergyValue(5f,"ok",["d"])
    ratio.add(item);result:=ratio.finish
    line=definition;line.gauge=true
    gauge:=FinEnergyLineFold(line,"value",owner);gauge.add(tick(1f,"substituted",["p"]))
    verifyNull(gauge.finish.value)
    owner.close;verifyEq(budget.temporary.val,0)
    verifyEq(result.value,2f);verifyEq(result.sources,["n","d"])
    verifyErr(ArgErr#) {ratio.finish};verifyErr(ArgErr#) {gauge.add(item)}
  }
  Void testOriginalValueModesKeepOrderAndDetachInputs()
  {
    line:=definition
    ticks:=[tick(10000000000000000f,"cleaned",["a"]),tick(1f,"corrected",["b"]),tick(2f,"ok",["a"])]
    ticks[0].known=FinEnergyValue(10f,"cleaned",["a"]);ticks[1].known=FinEnergyValue(null,"missing",["b"]);ticks[2].known=FinEnergyValue(20f,"ok",["a"])
    ticks[0].baseValue=FinEnergyValue(5f,"ok",["a"]);ticks[1].baseValue=FinEnergyValue(7f,"ok",["b"]);ticks[2].baseValue=FinEnergyValue(null,"missing",["a"])
    ticks[0].baseKnown=FinEnergyValue(2f,"derived",["a"])
    folds:=[FinEnergyLineFold(line),FinEnergyLineFold(line,"known"),FinEnergyLineFold(line,"baseValue"),FinEnergyLineFold(line,"baseKnown")]
    folds.each |fold| {ticks.each |t| {fold.add(t)}}
    ticks[0].value.value=0f;ticks[0].value.sources.add("late");ticks[0].known.value=99f
    verifyEq(folds[0].finish.value,10000000000000002f);verifyEq(folds[0].finish.quality,"cleaned");verifyEq(folds[0].finish.sources,["a","b"])
    verifyEq(folds[1].finish.value,30f);verifyEq(folds[1].finish.quality,"filtered")
    verifyNull(folds[2].finish.value);verifyEq(folds[2].finish.quality,"missing")
    verifyEq(folds[3].finish.value,22f);verifyEq(folds[3].finish.quality,"filtered")
    verifyEq(line.ticks.size,0)
  }

  Void testCopUsesOperandSumsRatherThanHourlyRatioValidity()
  {
    line:=definition;line.ratio=true;fold:=FinEnergyLineFold(line)
    first:=FinEnergyTick(at,at+1hr,FinEnergyValue(null,"divisionByZero",["n","d"]),FinEnergyValue(10f,"ok",["n"]),FinEnergyValue(0f,"ok",["d"]))
    second:=FinEnergyTick(at+1hr,at+2hr,FinEnergyValue(1f,"ok",["n","d"]),FinEnergyValue(10f,"ok",["n"]),FinEnergyValue(10f,"ok",["d"]))
    fold.add(first);fold.add(second)
    verifyEq(fold.finish.value,2f);verifyEq(fold.finish.quality,"ok");verifyEq(fold.finish.sources,["n","d"])
  }

  Void testGaugeDurationWeightAndFirstUnreliableSource()
  {
    line:=definition;line.gauge=true
    a:=FinEnergyTick(at,at+30min,FinEnergyValue(10f,"ok",["a"]))
    b:=FinEnergyTick(at+30min,at+2hr,FinEnergyValue(30f,"ok",["b"]))
    fold:=FinEnergyLineFold(line);fold.add(a);fold.add(b)
    verifyEq(fold.finish.value,25f)
    a.value.quality="filtered";b.value.quality="na"
    fold=FinEnergyLineFold(line);fold.add(a);fold.add(b)
    a.value.quality="ok";a.value.sources.add("later")
    verifyNull(fold.finish.value);verifyEq(fold.finish.quality,"filtered");verifyEq(fold.finish.sources,["a"])
  }

  Void testEmptyAndContinuedFinishAreIndependent()
  {
    fold:=FinEnergyLineFold(definition)
    verifyNull(fold.finish.value);verifyEq(fold.finish.quality,"missing")
    fold.add(tick(3f,"ok",["a"]));first:=fold.finish;first.sources.add("caller")
    fold.add(tick(4f,"ok",["b"]))
    verifyEq(first.value,3f);verifyEq(fold.finish.value,7f);verifyEq(fold.finish.sources,["a","b"])
  }

  private FinEnergyLine definition() {FinEnergyLine("m|c","m","Meter","c","kWh")}
  private FinEnergyTick tick(Float v,Str q,Str[] sources) {FinEnergyTick(at,at+1hr,FinEnergyValue(v,q,sources))}
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

class EnerCubixLineFoldTest : Test
{
  Void testOriginalValueModesKeepOrderAndDetachInputs()
  {
    line:=definition
    ticks:=[tick(10000000000000000f,"cleaned",["a"]),tick(1f,"corrected",["b"]),tick(2f,"ok",["a"])]
    ticks[0].known=EnerCubixValue(10f,"cleaned",["a"]);ticks[1].known=EnerCubixValue(null,"missing",["b"]);ticks[2].known=EnerCubixValue(20f,"ok",["a"])
    ticks[0].baseValue=EnerCubixValue(5f,"ok",["a"]);ticks[1].baseValue=EnerCubixValue(7f,"ok",["b"]);ticks[2].baseValue=EnerCubixValue(null,"missing",["a"])
    ticks[0].baseKnown=EnerCubixValue(2f,"derived",["a"])
    folds:=[EnerCubixLineFold(line),EnerCubixLineFold(line,"known"),EnerCubixLineFold(line,"baseValue"),EnerCubixLineFold(line,"baseKnown")]
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
    line:=definition;line.ratio=true;fold:=EnerCubixLineFold(line)
    first:=EnerCubixTick(at,at+1hr,EnerCubixValue(null,"divisionByZero",["n","d"]),EnerCubixValue(10f,"ok",["n"]),EnerCubixValue(0f,"ok",["d"]))
    second:=EnerCubixTick(at+1hr,at+2hr,EnerCubixValue(1f,"ok",["n","d"]),EnerCubixValue(10f,"ok",["n"]),EnerCubixValue(10f,"ok",["d"]))
    fold.add(first);fold.add(second)
    verifyEq(fold.finish.value,2f);verifyEq(fold.finish.quality,"ok");verifyEq(fold.finish.sources,["n","d"])
  }

  Void testGaugeDurationWeightAndFirstUnreliableSource()
  {
    line:=definition;line.gauge=true
    a:=EnerCubixTick(at,at+30min,EnerCubixValue(10f,"ok",["a"]))
    b:=EnerCubixTick(at+30min,at+2hr,EnerCubixValue(30f,"ok",["b"]))
    fold:=EnerCubixLineFold(line);fold.add(a);fold.add(b)
    verifyEq(fold.finish.value,25f)
    a.value.quality="filtered";b.value.quality="na"
    fold=EnerCubixLineFold(line);fold.add(a);fold.add(b)
    a.value.quality="ok";a.value.sources.add("later")
    verifyNull(fold.finish.value);verifyEq(fold.finish.quality,"filtered");verifyEq(fold.finish.sources,["a"])
  }

  Void testEmptyAndContinuedFinishAreIndependent()
  {
    fold:=EnerCubixLineFold(definition)
    verifyNull(fold.finish.value);verifyEq(fold.finish.quality,"missing")
    fold.add(tick(3f,"ok",["a"]));first:=fold.finish;first.sources.add("caller")
    fold.add(tick(4f,"ok",["b"]))
    verifyEq(first.value,3f);verifyEq(fold.finish.value,7f);verifyEq(fold.finish.sources,["a","b"])
  }

  private EnerCubixLine definition() {EnerCubixLine("m|c","m","Meter","c","kWh")}
  private EnerCubixTick tick(Float v,Str q,Str[] sources) {EnerCubixTick(at,at+1hr,EnerCubixValue(v,q,sources))}
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

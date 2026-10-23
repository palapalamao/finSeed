class SeedForecastTest : Test
{
  Void testWeeklyPatternAndHorizon()
  {
    values:=Float?[,]; 56.times |i| { values.add(10f+(i%7).toFloat) }
    fit:=SeedForecast.fit(values,7)
    verifyEq(fit["status"],"ok")
    predicted:=(Float[])fit["predictions"]
    verifyEq(predicted,[10f,11f,12f,13f,14f,15f,16f])
    verifyEq(fit["model"],"seasonalNaive")
    verifyEq(fit["mae"],0f)
    verifyEq(fit["wape"],0f)
    verifyEq(((List)SeedForecast.fit(values,14)["predictions"]).size,14)
    verifyEq(((List)SeedForecast.fit(values,30)["predictions"]).size,30)
  }

  Void testZerosMissingAndInsufficient()
  {
    values:=Float?[,]; 56.times { values.add(0f) }
    fit:=SeedForecast.fit(values,7)
    verifyEq(fit["mae"],0f); verifyNull(fit["wape"])
    verifyEq(fit["predictions"],Float[,].fill(0f,7))
    values[3]=null; fit=SeedForecast.fit(values,7)
    verifyEq(fit["validDays"],55); verifyEq(values[3],null)
    20.times |i| { values[i]=null }
    verifyEq(SeedForecast.fit(values,7)["status"],"insufficientHistory")
    verifyEq(SeedForecast.fit(Float?[,].fill(1f,28),30)["status"],"insufficientBacktest")
  }

  Void testTrendSelectionAndNoHoldoutLeakage()
  {
    values:=Float?[,]; 90.times |i| { values.add(100f+i.toFloat*2f+(i%7).toFloat*3f) }
    fit:=SeedForecast.fit(values,7)
    verifyEq(fit["model"],"dampedTrend")
    verify((Float)fit["mae"] < (Float)fit["baselineMae"])
    before:=SeedForecast.fit(values[0..<56],7)
    34.times |i| { values[56+i]=1000000f }
    verifyEq(SeedForecast.fit(values[0..<56],7)["predictions"],before["predictions"])
    verify(((Float[])fit["predictions"]).all |v| { v >= 0f && !v.isNaN })
  }

  Void testEngineClipsFutureAndKeepsSource()
  {
    start:=DateTime.fromIso("2010-01-01T00:00:00Z")
    samples:=[Str:Obj?][,]
    (56*24).times |i| { samples.add(["ts":(start+Duration(i*1hr.ticks)).toIso,"value":1f]) }
    cutoff:=start+56day
    samples.add(["ts":cutoff.toIso,"value":1000000f])
    history:=[Str:Obj?]["pointId":"p","unit":"kWh","mode":"interval","simulated":true,"samples":samples]
    records:=[[Str:Obj?]["id":"m","name":"Meter","kind":"meter","pointId":"p","categoryId":"e"],[Str:Obj?]["id":"e","kind":"category","unit":"kWh"]]
    req:=[Str:Obj?]["kind":"forecast","nodeIds":["m"],"from":start.toIso,"to":cutoff.toIso,"period":"day","metric":"energy","forecastDays":7]
    result:=SeedEngine.report(req,records,[history])
    forecasts:=SeedMath.maps(((Str:Obj?)result["extra"])["forecasts"])
    verifyEq(forecasts.first["predictedTotal"],168f)
    verifyEq(forecasts.first["simulated"],true)
    verifyEq(samples.last["value"],1000000f)
    verifyEq(SeedMath.maps(result["rows"]).findAll |r| { r["phase"] == "forecast" }.size,7)
    req["to"]=(DateTime.now+1day).toIso
    verifyErr(ArgErr#) { SeedEngine.report(req,records,[history]) }
  }

  Void testHoldoutArithmeticAndBoundaryClip()
  {
    values:=Float?[,].fill(10f,56)
    // The final held-out week changes to 20. Its prefix still predicts 10.
    7.times |i| { values[49+i]=20f }
    fit:=SeedForecast.fit(values,7)
    pairs:=SeedMath.maps(fit["backtests"])
    pair:=pairs.find |r| { r["index"] == 49 }
    verifyEq(pair["origin"],49); verifyEq(pair["prediction"],10f)
    verifyEq(pair["actual"],20f); verifyEq(pair["absoluteError"],10f)
    cutoff:=DateTime.fromIso("2010-02-26T00:00:00Z")
    samples:=[[Str:Obj?]["ts":(cutoff-1hr).toIso,"value":10f],[Str:Obj?]["ts":(cutoff+1hr).toIso,"value":100f]]
    h:=[Str:Obj?]["pointId":"p","mode":"cumulative","samples":samples]
    clipped:=SeedHistoryData(SeedForecast.clip([h],cutoff).first)
    verifyNull(clipped.read(cutoff-1hr,cutoff).value)
    verifyEq(samples.size,2)
  }

  Void testRequestGuards()
  {
    req:=[Str:Obj?]["kind":"forecast","nodeIds":["m"],"from":"2010-01-01T00:00:00Z","to":"2010-02-26T00:00:00Z","metric":"energy","period":"day","forecastDays":7]
    SeedForecast.validate(req)
    ["forecastDays":"invalid","metric":"cost","period":"hour","nodeIds":Str[,],"from":"2010-02-01T00:00:00Z"].each |v,k| {
      bad:=req.dup.set(k,v); verifyErr(ArgErr#) { SeedForecast.validate(bad) }
    }
  }

  Void testCumulativeAcrossYearUsesConsumption()
  {
    start:=DateTime.fromIso("2009-12-01T00:00:00Z"); cutoff:=start+56day
    samples:=[Str:Obj?][,]
    (56*24+1).times |i| { samples.add(["ts":(start+Duration(i*1hr.ticks)).toIso,"value":10000f+i.toFloat]) }
    req:=[Str:Obj?]["kind":"forecast","nodeIds":["m"],"from":start.toIso,"to":cutoff.toIso,"metric":"energy","period":"day","forecastDays":7]
    records:=[[Str:Obj?]["id":"m","kind":"meter","name":"Counter","pointId":"p","categoryId":"e"],[Str:Obj?]["id":"e","kind":"category","unit":"kWh"]]
    history:=[Str:Obj?]["pointId":"p","unit":"kWh","mode":"cumulative","samples":samples]
    result:=SeedEngine.report(req,records,[history])
    meta:=SeedMath.maps(((Str:Obj?)result["extra"])["forecasts"]).first
    verifyEq(meta["predictedTotal"],168f); verifyEq(meta["validDays"],56)
    verifyEq(samples.first["value"],10000f); verifyEq(samples.last["value"],11344f)
  }
}

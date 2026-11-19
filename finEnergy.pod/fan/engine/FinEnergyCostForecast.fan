** Monetary forecasts reuse each canonical meter's model before view aggregation.
** They estimate historical cost patterns, not a future tariff-adjusted bill.
internal const class FinEnergyCostForecast
{
  static Str:Obj? combine([Str:Obj?][] fits, Float?[] history, Int horizon)
  {
    valid:=history.findAll |v| {v != null}.size
    out:=Str:Obj?["validDays":valid,"trainingDays":history.size,"coverage":history.isEmpty ? 0f : 100f*valid/history.size,"model":"meterSum"]
    bad:=fits.find |fit| {fit["status"] != "ok"}
    if (fits.isEmpty || bad != null) return out.set("status",bad?.get("status") ?: "insufficientHistory")
    predictions:=Float[,].fill(0f,horizon); spread:=0f
    fits.each |fit|
    {
      ((Float[])fit["predictions"]).each |v,i| {predictions[i]+=v}
      spread+=(Float)fit["errorRange"]
    }
    if (FinEnergyMath.num(spread) == null || predictions.any |v| {FinEnergyMath.num(v) == null || FinEnergyMath.num(v+spread) == null}) return out.set("status","invalidForecast")
    pairs:=[Str:Obj?][,]
    FinEnergyMath.maps(fits.first["backtests"]).each |sample|
    {
      parts:=fits.map |fit->[Str:Obj?]?| {FinEnergyMath.maps(fit["backtests"]).find |p| {p["origin"] == sample["origin"] && p["index"] == sample["index"]}}
      if (parts.any |part| {part == null}) return
      actual:=0f; prediction:=0f
      parts.each |part| {row:=(Str:Obj?)part;actual+=(Float)row["actual"];prediction+=(Float)row["prediction"]}
      pairs.add(sample.dup.set("actual",actual).set("prediction",prediction).set("absoluteError",(prediction-actual).abs))
    }
    if (pairs.size < 7) return out.set("status","insufficientBacktest")
    error:=0f; actual:=0f
    pairs.each |pair| {error+=(Float)pair["absoluteError"];actual+=((Float)pair["actual"]).abs}
    score:=Str:Obj?["model":"meterSum","mae":error/pairs.size,"wape":actual == 0f ? null : error/actual*100f,"backtestDays":pairs.size]
    out.setAll(score)
    return out.setAll(["status":"ok","predictions":predictions,"errorRange":spread,"baselineMae":null,"backtests":pairs,"modelScores":[score]])
  }
}

** Daily forecasts from completed history only. All validation folds use prefix data.
internal class EnerCubixForecast
{
  static Void validate(Str:Obj? request)
  {
    if (request["kind"] != "forecast") return
    from:=DateTime.fromIso(request["from"]?.toStr ?: "")
    to:=DateTime.fromIso(request["to"]?.toStr ?: "")
    tz:=TimeZone.fromStr(request["tz"]?.toStr ?: from.tz.name)
    from=from.toTimeZone(tz); to=to.toTimeZone(tz)
    horizon:=request["forecastDays"] == null ? 7f : EnerCubixMath.num(request["forecastDays"])
    if (horizon == null || ![7f,14f,30f].contains(horizon)) throw ArgErr("预测范围请选择 7、14 或 30 天")
    if (from != EnerCubixMath.bucket(from,"day") || to != EnerCubixMath.bucket(to,"day") || to <= from || (to-from) < 27day || (to-from) > 181day) throw ArgErr("训练范围须为 28 至 180 个完整日")
    days:=0; cursor:=from
    while (cursor < to) { days++; cursor=EnerCubixMath.nextBucket(cursor,"day") }
    if (days < 28 || days > 180) throw ArgErr("训练范围须为 28 至 180 个完整日")
    if (to > EnerCubixMath.bucket(DateTime.now.toTimeZone(tz),"day")) throw ArgErr("训练截止时间不能超过今天零点，不能使用未来或未完成的历史")
    if (request["metric"] != "energy" || request["period"] != "day") throw ArgErr("能耗预测使用每日能耗")
    selected:=EnerCubixMath.strings(request["nodeIds"])
    if (selected.isEmpty || selected.size > 10) throw ArgErr("每次请选择 1 至 10 个预测对象")
  }

  ** Discard future samples even when the counter reader requests a boundary buffer.
  static [Str:Obj?][] clip([Str:Obj?][] histories, DateTime cutoff)
  {
    return histories.map |h->[Str:Obj?]| {
      out:=h.dup
      ["samples","rawSamples"].each |key| {
        if (h[key] != null) out[key]=EnerCubixMath.maps(h[key]).findAll |s| { DateTime.fromIso(s["ts"].toStr) <= cutoff }
      }
      return out
    }
  }

  static Str:Obj? fit(Float?[] values, Int horizon)
  {
    valid:=values.findAll |v| { v != null && v >= 0f && EnerCubixMath.num(v) != null }.size
    base:=[Str:Obj?]["validDays":valid,"trainingDays":values.size,"coverage":values.isEmpty ? 0f : 100f*valid/values.size]
    if (valid < 28 || valid.toFloat/values.size < 0.8f || (0..<7).toList.any |day| { countDay(values,day) < 3 } || values.size < 7 || values[-7..-1].any |v| { v == null }) return base.set("status","insufficientHistory")
    origins:=Int[,]; origin:=values.size-horizon
    while (origin >= 14 && origins.size < 4) { origins.add(origin); origin-=horizon }
    if (origins.isEmpty) return base.set("status","insufficientBacktest")
    models:=["seasonalNaive","weekdayMean","dampedTrend"]
    scores:=[Str:Obj?][,]; residuals:=Str:Float[][:]; tests:=Str:[Str:Obj?][][:]
    models.each |model| {
      errors:=Float[,]; actualSum:=0f; pairs:=[Str:Obj?][,]
      origins.dup.reverse.each |n| {
        predictions:=predict(values[0..<n],horizon,model)
        horizon.times |lead| {
          actual:=values[n+lead]
          if (actual == null || actual < 0f || EnerCubixMath.num(actual) == null) return
          error:=(predictions[lead]-actual).abs
          errors.add(error); actualSum+=actual.abs
          pairs.add(["index":n+lead,"actual":actual,"prediction":predictions[lead],"absoluteError":error,"origin":n])
        }
      }
      total:=0f; errors.each |e| { total+=e }
      scores.add(["model":model,"mae":errors.isEmpty ? null : total/errors.size,"wape":actualSum == 0f ? null : total/actualSum*100f,"backtestDays":errors.size])
      residuals[model]=errors; tests[model]=pairs
    }
    best:=scores.first
    scores.each |score| { if (EnerCubixMath.num(score["mae"]) != null && (Float)score["mae"] < (Float)best["mae"]*0.98f) best=score }
    if ((Int)best["backtestDays"] < 7) return base.set("status","insufficientBacktest")
    model:=best["model"].toStr
    errors:=residuals[model].dup.sort
    spread:=errors[((errors.size-1).toFloat*0.9f).ceil.toInt]
    predictions:=predict(values,horizon,model)
    totalPrediction:=0f; predictions.each |v| { totalPrediction+=v }
    if (EnerCubixMath.num(spread) == null || EnerCubixMath.num(best["mae"]) == null || EnerCubixMath.num(totalPrediction) == null || predictions.any |v| { EnerCubixMath.num(v) == null || EnerCubixMath.num(v+spread) == null }) return base.set("status","invalidForecast")
    base.setAll(best)
    return base.setAll(["status":"ok","predictions":predictions,"errorRange":spread,"baselineMae":scores.first["mae"],"modelScores":scores,"backtests":tests[model]])
  }

  private static Int countDay(Float?[] values, Int day)
  {
    count:=0; values.each |v,i| { if (i%7 == day && v != null && v >= 0f && EnerCubixMath.num(v) != null) count++ }; return count
  }

  private static Float[] predict(Float?[] values, Int horizon, Str model)
  {
    n:=values.size; meanY:=Float[,].fill(0f,7); meanX:=Float[,].fill(0f,7); weights:=Float[,].fill(0f,7)
    values.each |v,i| {
      if (v == null || v < 0f || EnerCubixMath.num(v) == null) return
      d:=i%7; w:=1f/(1f+(n-1-i).toFloat/7f)
      weights[d]+=w; meanY[d]+=v*w; meanX[d]+=i.toFloat*w
    }
    fallback:=0f; totalWeight:=0f
    7.times |d| { fallback+=meanY[d]; totalWeight+=weights[d] }
    fallback=totalWeight == 0f ? 0f : fallback/totalWeight
    7.times |d| { if (weights[d] > 0f) { meanY[d]/=weights[d]; meanX[d]/=weights[d] } else { meanY[d]=fallback; meanX[d]=(n-1).toFloat } }
    numerator:=0f; denominator:=0f
    values.each |v,i| {
      if (v == null || v < 0f || EnerCubixMath.num(v) == null) return
      d:=i%7; w:=1f/(1f+(n-1-i).toFloat/7f); dx:=i.toFloat-meanX[d]
      numerator+=w*dx*(v-meanY[d]); denominator+=w*dx*dx
    }
    slope:=denominator == 0f ? 0f : numerator/denominator
    out:=Float[,]; damped:=0f; phi:=1f
    horizon.times |lead| {
      d:=(n+lead)%7; value:=meanY[d]
      if (model == "seasonalNaive")
      {
        index:=n+lead-7
        while (index >= n) index-=7
        while (index >= 0 && values[index] == null) index-=7
        if (index >= 0) value=values[index]
      }
      phi*=0.9f; damped+=phi
      if (model == "dampedTrend") value+=slope*((n-1).toFloat-meanX[d]+damped)
      out.add(value.max(0f))
    }
    return out
  }
}

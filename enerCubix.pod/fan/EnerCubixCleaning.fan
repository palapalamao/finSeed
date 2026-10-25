using haystack

** Pure cumulative-to-interval cleaning. No persistence, interpolation or implicit profile.
internal class EnerCubixCleaning
{
  internal static Dict config(Str:Obj? params, Str pointUnit)
  {
    out:=Str:Obj?[:]
    params.each |v,k|
    {
      if (meta.contains(k)) return
      if (!keys.contains(k)) throw ArgErr("Unknown cleaning parameter: $k")
      if (k == "defNull" || k == "removeNA")
      {
        if (v != true && v !== Marker.val) throw ArgErr("$k must be enabled or omitted")
        out[k]=Marker.val; return
      }
      if (k == "timeMax") { out[k]=duration(v); return }
      if (k == "defVal" && v is Map && ((Map)v)["type"] == "na")
      {
        if (((Map)v).size != 1) throw ArgErr("NA replacement only accepts type")
        out[k]=NA.val; return
      }
      if (k == "defVal" && v === NA.val) { out[k]=NA.val; return }
      if (k == "defVal" && v isnot Map && v isnot Number) throw ArgErr("defVal requires an explicit type")
      out[k]=parameter(v,k.startsWith("deriv") ? rateUnit(pointUnit) : pointUnit,k)
    }
    ["delta","deriv"].each |prefix|
    {
      min:=out[prefix+"Min"] as Number; max:=out[prefix+"Max"] as Number
      if (min != null && max != null && min.toFloat > max.toFloat) throw ArgErr("${prefix}Min exceeds ${prefix}Max")
    }
    drop:=out.containsKey("defNull"); replace:=out.containsKey("defVal"); rollover:=out.containsKey("hisTotalizedRollover")
    if ((drop && replace) || (rollover && (drop || replace))) throw ArgErr("Cleaning modes are mutually exclusive")
    if (!drop && !replace)
    {
      if (!rollover || (!out.containsKey("deltaMax") && !out.containsKey("derivMax"))) throw ArgErr("Rollover requires a period and an upper bound")
      if (((Number)out["hisTotalizedRollover"]).toFloat <= 0f) throw ArgErr("Rollover period must be positive")
      if (["deltaMax","derivMax"].any |k| { out.containsKey(k) && ((Number)out[k]).toFloat <= 0f }) throw ArgErr("Rollover upper bounds must be positive")
    }
    return Etc.makeDict(out)
  }

  ** JSON-safe parameter snapshot; ownership metadata remains on the point.
  internal static Str:Obj? jsonConfig(Dict config)
  {
    out:=Str:Obj?[:]
    config.each |v,k|
    {
      if (!keys.contains(k)) return
      if (v === Marker.val) out[k]=true
      else if (v === NA.val) out[k]=["type":"na"]
      else if (k == "timeMax") out[k]=((Number)v).toDuration.toStr
      else
      {
        n:=(Number)v
        value:=[Str:Obj?]["type":"number","value":n.toFloat]
        if (n.unit != null) value["unit"]=n.unit.symbol
        out[k]=value
      }
    }
    return out
  }

  internal static EnerCubixCleanResult clean(Dict point, HisItem[] raw, Dict config)
  {
    result:=EnerCubixCleanResult()
    result.rawItems=raw.dup
    unit:=point["unit"]?.toStr ?: ""
    // Revalidation also protects callers that supply a native Dict directly.
    cfg:=EnerCubixCleaning.config(nativeParams(config),unit)
    sorted:=raw.dup.sort |a,b| { a.ts <=> b.ts }
    HisItem? previous:=null
    removed:=0; substituted:=0; rejected:=0; rollovers:=0
    sorted.each |item|
    {
      detail:=[Str:Obj?]["ts":item.ts.toIso,"rawValue":jsonValue(item.val),"previousValue":jsonValue(previous?.val),
        "value":null,"valueType":"null","reason":"noPrevious","substituted":false,"intervalSeconds":null,"emitted":false]
      result.details.add(detail)
      if (item.val === NA.val && cfg.has("removeNA"))
      {
        detail["reason"]="removedNA"; removed++; return
      }
      if (previous == null) { previous=item; return }
      elapsed:=(item.ts-previous.ts).ticks.toFloat/1sec.ticks.toFloat
      detail["intervalSeconds"]=elapsed
      detail["emitted"]=true
      Obj? value:=null; reason:="ok"
      a:=reading(previous.val,unit); b:=reading(item.val,unit)
      if (item.val === NA.val) { value=NA.val; reason="inputNA" }
      else if (previous.val === NA.val) { value=NA.val; reason="previousNA" }
      else if (item.val == null) reason="inputNull"
      else if (previous.val == null) reason="previousNull"
      else if (a == null || b == null) reason="invalidValue"
      else if (elapsed <= 0f) reason="nonPositiveInterval"
      else
      {
        delta:=b-a
        maxTime:=cfg["timeMax"] as Number
        if (maxTime != null && elapsed > maxTime.toDuration.ticks.toFloat/1sec.ticks.toFloat) reason="timeMax"
        else
        {
          rollover:=cfg["hisTotalizedRollover"] as Number
          corrected:=false
          if (rollover != null && delta < 0f)
          {
            period:=rollover.toFloat
            if (a < 0f || a >= period || b < 0f || b >= period) reason="rolloverOutOfRange"
            else { delta=period-a+b; corrected=true }
          }
          if (reason == "ok") reason=bounds(delta,elapsed,unit,cfg)
          if (reason == "ok")
          {
            value=Number(delta,unit.isEmpty ? null : Unit(unit))
            if (corrected) { reason="rollover"; rollovers++ }
          }
        }
      }
      if (reason != "ok" && reason != "rollover")
      {
        rejected++
        // Missing source values retain their semantics; replacement applies to
        // rejected numeric intervals only, never to true source NA or null.
        if (cfg.has("defVal") && a != null && b != null)
        {
          value=cfg["defVal"]; detail["substituted"]=true; substituted++
        }
      }
      detail["reason"]=reason; detail["value"]=jsonValue(value)
      detail["valueType"]=value === NA.val ? "na" : (value is Number ? "number" : "null")
      result.items.add(HisItem(item.ts,value))
      previous=item
    }
    result.summary=["inputCount":raw.size,"outputCount":result.items.size,
      "validCount":result.items.findAll |i| { i.val is Number }.size,
      "nullCount":result.items.findAll |i| { i.val == null }.size,
      "naCount":result.items.findAll |i| { i.val === NA.val }.size,
      "substitutedCount":substituted,"removedNACount":removed,"rejectedCount":rejected,"rolloverCount":rollovers]
    return result
  }

  private static Str bounds(Float delta, Float elapsed, Str unit, Dict cfg)
  {
    rate:=delta/elapsed*rateSeconds(unit)
    for (i:=0;i<4;i++)
    {
      key:=["deltaMin","deltaMax","derivMin","derivMax"][i]
      limit:=cfg[key] as Number
      if (limit == null) continue
      value:=i < 2 ? delta : rate
      if (i % 2 == 0 ? value < limit.toFloat : value > limit.toFloat) return key
    }
    return "ok"
  }

  private static Str:Obj? nativeParams(Dict cfg)
  {
    params:=Str:Obj?[:]; cfg.each |v,k| { params[k]=v }
    return params
  }

  private static Number parameter(Obj? value, Str target, Str key)
  {
    Unit? from:=null
    Float? scalar:=null
    if (value is Map)
    {
      m:=(Map)value
      if (m["type"] != "number" || m.keys.any |k| { !["type","value","unit"].contains(k) }) throw ArgErr("$key requires a numeric value")
      scalar=num(m["value"])
      if (m["unit"] != null)
      {
        if (m["unit"] isnot Str) throw ArgErr("$key unit must be a string")
        from=Unit.fromStr(m["unit"].toStr,false)
        if (from == null) throw ArgErr("$key has an unknown unit")
      }
    }
    else if (value is Number) { scalar=num(value); from=((Number)value).unit }
    else scalar=num(value)
    if (scalar == null) throw ArgErr("$key requires a finite number")
    to:=target.isEmpty ? null : Unit.fromStr(target,false)
    if (!target.isEmpty && to == null) throw ArgErr("Unknown point or rate unit: $target")
    if (from != null)
    {
      if (to == null || from.dim != to.dim) throw ArgErr("$key unit is incompatible with $target")
      if (from != to) scalar=from.convertTo(scalar,to)
    }
    return Number(scalar,to)
  }

  private static Number duration(Obj? value)
  {
    Number? n:=value as Number
    if (value is Str)
    {
      s:=((Str)value).trim
      if (s.endsWith("h")) s=s[0..<-1]+"hr"
      else if (s.endsWith("d")) s=s[0..<-1]+"day"
      n=Number.fromStr(s,false)
    }
    d:=n?.toDuration(false)
    if (d == null || d.ticks <= 0) throw ArgErr("timeMax requires a positive duration")
    return Number.makeDuration(d)
  }

  private static Float? reading(Obj? value, Str unit)
  {
    n:=num(value); if (n == null) return null
    from:=(value as Number)?.unit
    if (from == null) return n
    to:=unit.isEmpty ? null : Unit.fromStr(unit,false)
    if (to == null || from.dim != to.dim) return null
    return from == to ? n : from.convertTo(n,to)
  }

  private static Float? num(Obj? value)
  {
    Float? n:=value is Number ? ((Number)value).toFloat : (value is Num ? ((Num)value).toFloat : null)
    return n == null || n.isNaN || n == Float.posInf || n == Float.negInf ? null : n
  }

  private static Obj? jsonValue(Obj? value) { value === NA.val ? "NA" : num(value) }

  private static Str rateUnit(Str unit)
  {
    if (unit.isEmpty) return ""
    rate:=rates[unit]
    if (rate == null) throw ArgErr("Unsupported cleaning rate unit: $unit")
    return rate
  }
  private static Float rateSeconds(Str unit) { ["gal","L"].contains(unit) ? 60f : (unit.isEmpty ? 1f : 3600f) }
  private static const Str:Str rates := ["Wh":"W","kWh":"kW","MWh":"MW","BTU":"BTU/h","kBTU":"kBTU/h","gal":"gal/min","L":"L/min"]
  private static const Str[] keys := ["deltaMin","deltaMax","timeMax","derivMin","derivMax","defVal","defNull","removeNA","hisTotalizedRollover"]
  private static const Str[] meta := ["enerCubixMode","enerCubixProfileRef","enerCubixProfileVersion"]
}

internal class EnerCubixCleanResult
{
  new make(HisItem[] items := HisItem[,], [Str:Obj?][] details := [Str:Obj?][,], Str:Obj? summary := [:])
  { this.items=items; this.details=details; this.summary=summary }
  HisItem[] rawItems := HisItem[,]
  // Internal end stamps identify the source-reading pair; nativeItems adapts FIN output.
  HisItem[] items
  [Str:Obj?][] details
  // Leaf interventions only. Aggregate intervals remain separate arithmetic data.
  [Str:Obj?][] sourceDetails := [Str:Obj?][,]
  Str:Obj? summary
}

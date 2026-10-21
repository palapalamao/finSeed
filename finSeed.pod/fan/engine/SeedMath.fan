** One value carries its quality and physical source lineage through every operation.
internal class SeedValue
{
  new make(Float? value := null, Str quality := "missing", Str[] sources := Str[,])
  {
    this.value = value
    this.quality = quality
    this.sources = sources
  }
  Float? value
  Str quality
  Str[] sources

  SeedValue scale(Float factor)
  {
    if (value == null) return this
    return SeedValue(value * factor, quality, sources)
  }

  Str:Obj? point(DateTime ts)
  {
    return ["ts":ts.toIso,"value":value,"quality":quality,"sourceIds":sources]
  }

  static SeedValue sum(SeedValue[] values)
  {
    if (values.isEmpty) return SeedValue()
    total := 0f; quality := "ok"; sources := Str[,]; missing := false
    values.each |v|
    {
      if (v.value == null) missing = true
      else total += v.value
      quality = worse(quality, v.quality)
      sources.addAll(v.sources)
    }
    return SeedValue(missing ? null : total, quality, sources.unique)
  }

  static SeedValue divide(SeedValue a, SeedValue b)
  {
    src := a.sources.dup.addAll(b.sources).unique
    if (a.value == null || b.value == null) return SeedValue(null,worse(a.quality,b.quality),src)
    if (b.value == 0f) return SeedValue(null,"divisionByZero",src)
    return SeedValue(a.value / b.value,worse(a.quality,b.quality),src)
  }

  static Str worse(Str a, Str b)
  {
    return rank(a) >= rank(b) ? a : b
  }

  private static Int rank(Str q)
  {
    if (q == "ok") return 0
    if (q == "derived") return 1
    if (q == "estimated") return 2
    return 3
  }
}

internal class SeedMath
{
  static Float? num(Obj? v)
  {
    Float? n := v is Float ? (Float)v : (v is Int ? ((Int)v).toFloat : null)
    if (n == null || n.isNaN || n == Float.posInf || n == Float.negInf) return null
    return n
  }

  static Str[] strings(Obj? v)
  {
    if (v isnot List) return Str[,]
    return ((List)v).map |Obj? x->Str| { x?.toStr ?: "" }.findAll |Str x->Bool| { !x.isEmpty }
  }

  static [Str:Obj?][] maps(Obj? v)
  {
    if (v isnot List) return [Str:Obj?][,]
    return ((List)v).findAll |Obj? x->Bool| { x is Map }.map |Obj? x->[Str:Obj?]| { (Str:Obj?)x }
  }

  static Bool containsNum(Obj? list, Int n)
  {
    if (list isnot List) return false
    return ((List)list).any |Obj? v->Bool| { num(v) == n.toFloat }
  }

  static Int isoDay(DateTime t) { t.weekday == Weekday.sun ? 7 : t.weekday.ordinal }

  ** Only dimensional conversions with explicit physical definitions are allowed.
  static Float? unitFactor(Str from, Str to)
  {
    if (from == to || from.isEmpty || to.isEmpty) return 1f
    energy:=["J":1f,"kJ":1000f,"MJ":1000000f,"GJ":1000000000f,"Wh":3600f,"kWh":3600000f,"MWh":3600000000f,"GWh":3600000000000f]
    volume:=["m³":1f,"m3":1f,"L":0.001f,"l":0.001f]
    mass:=["kg":1f,"t":1000f,"g":0.001f]
    for (i:=0;i<3;i++)
    {
      table:=[energy,volume,mass][i]
      if (table.containsKey(from) && table.containsKey(to)) return table[from]/table[to]
    }
    return null
  }

  static DateTime floorHour(DateTime t)
  {
    // Subtract elapsed minutes instead of rebuilding wall time (preserves repeated DST hours).
    return t - Duration(t.min * 1min.ticks + t.sec * 1sec.ticks + t.nanoSec)
  }

  static DateTime bucket(DateTime t, Str period)
  {
    if (period == "hour") return floorHour(t)
    if (period == "day") return t.date.toDateTime(Time.defVal,t.tz)
    if (period == "month") return Date(t.year,t.month,1).toDateTime(Time.defVal,t.tz)
    return Date(t.year,Month.jan,1).toDateTime(Time.defVal,t.tz)
  }

  static DateTime nextBucket(DateTime t, Str period)
  {
    if (period == "hour") return t + 1hr
    if (period == "day") return (t.date + 1day).toDateTime(Time.defVal,t.tz)
    if (period == "month")
    {
      month := t.month.ordinal + 1
      return Date(t.year + (month == 12 ? 1 : 0),Month.vals[month % 12],1).toDateTime(Time.defVal,t.tz)
    }
    return Date(t.year+1,Month.jan,1).toDateTime(Time.defVal,t.tz)
  }

  ** OLS using centered data; no fabricated fit for a constant x or fewer than 2 pairs.
  static Str:Obj? regression(Float[] xs, Float[] ys)
  {
    out := [Str:Obj?]["slope":null,"intercept":null,"r2":null,"count":xs.size]
    if (xs.size < 2 || xs.size != ys.size) return out
    xmean := xs.reduce(0f) |Obj? a, Float v->Obj?| { (Float)a + v } as Float
    ymean := ys.reduce(0f) |Obj? a, Float v->Obj?| { (Float)a + v } as Float
    xmean = xmean / xs.size.toFloat; ymean = ymean / ys.size.toFloat
    xx := 0f; xy := 0f; yy := 0f
    xs.each |x,i| { dx:=x-xmean; dy:=ys[i]-ymean; xx+=dx*dx; xy+=dx*dy; yy+=dy*dy }
    if (xx == 0f) return out
    slope := xy/xx; intercept := ymean-slope*xmean
    out["slope"] = slope; out["intercept"] = intercept
    out["r2"] = yy == 0f ? null : ((xy*xy)/(xx*yy)).min(1f).max(0f)
    out["equation"] = "y = ${slope} * x + ${intercept}"
    return out
  }
}

** A closed arithmetic grammar. No Axon, reflection, function calls or eval.
internal class SeedExpression
{
  new make(Str source, Str:SeedValue variables) { this.source=source; this.variables=variables }
  private Str source
  private Str:SeedValue variables
  private Int pos := 0
  private Bool unknownVariable := false

  ** Syntax/name validation reuses the same closed grammar. Arithmetic zero
  ** denominators are data-time quality failures, and are valid configuration.
  static Bool validate(Str source, Str[] names)
  {
    variables:=Str:SeedValue[:]
    names.each |name| { variables[name]=SeedValue(1f,"ok") }
    parser:=SeedExpression(source,variables)
    value:=parser.calculate
    return value.quality != "invalidExpression" && !parser.unknownVariable
  }

  SeedValue calculate()
  {
    if (source.size > 4096 || variables.size > 256) return SeedValue(null,"invalidExpression")
    try
    {
      v := add
      space
      if (pos != source.size) return SeedValue(null,"invalidExpression",v.sources)
      if (v.value != null && SeedMath.num(v.value) == null) return SeedValue(null,"invalidExpression",v.sources)
      if (v.quality == "ok") v.quality = "derived"
      return v
    }
    catch (Err e) { return SeedValue(null,"invalidExpression") }
  }

  private SeedValue add()
  {
    a := mul
    while (true)
    {
      space; op := peek
      if (op != '+' && op != '-') return a
      pos++; b := mul
      if (op == '-') b = b.scale(-1f)
      a = SeedValue.sum([a,b])
    }
    return a
  }
  private SeedValue mul()
  {
    a := unary
    while (true)
    {
      space; op := peek
      if (op != '*' && op != '/') return a
      pos++; b := unary
      if (op == '/') a = SeedValue.divide(a,b)
      else a = SeedValue(a.value == null || b.value == null ? null : a.value*b.value,SeedValue.worse(a.quality,b.quality),a.sources.dup.addAll(b.sources).unique)
    }
    return a
  }
  private SeedValue unary()
  {
    space
    if (peek == '+') { pos++; return unary }
    if (peek == '-') { pos++; return unary.scale(-1f) }
    if (peek == '(')
    {
      pos++; a := add; space
      if (peek != ')') throw ArgErr("Missing closing parenthesis")
      pos++; return a
    }
    begin := pos
    if (peek.isAlpha || peek == '_')
    {
      pos++
      while (peek.isAlphaNum || peek == '_') pos++
      value:=variables[source[begin..<pos]]
      if (value == null) unknownVariable=true
      return value ?: SeedValue(null,"unknownVariable")
    }
    while (peek.isDigit || peek == '.') pos++
    if (peek == 'e' || peek == 'E')
    {
      pos++; if (peek == '+' || peek == '-') pos++
      while (peek.isDigit) pos++
    }
    if (pos == begin) throw ArgErr("Expected number or variable")
    return SeedValue(Float.fromStr(source[begin..<pos]),"ok")
  }
  private Int peek() { pos < source.size ? source[pos] : -1 }
  private Void space() { while (pos < source.size && source[pos].isSpace) pos++ }
}




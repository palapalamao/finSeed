internal class EnerCubixSample
{
  new make(DateTime ts, Float? value, Str quality := "ok", Str valueType := "number") { this.ts=ts; this.value=value; this.quality=quality; this.valueType=valueType }
  DateTime ts
  Float? value
  Str quality
  Str valueType
}

internal class EnerCubixInterval
{
  new make(DateTime start, DateTime end, Float? value, Str quality, Str valueType)
  { this.start=start; this.end=end; this.value=value; this.quality=quality; this.valueType=valueType }
  DateTime start
  DateTime end
  Float? value
  Str quality
  Str valueType
}

internal class EnerCubixHistoryData
{
  new make(Str:Obj? data)
  {
    id = data["pointId"]?.toStr ?: ""
    unit = data["unit"]?.toStr ?: ""
    mode = data["mode"]?.toStr ?: "sampled"
    quality = data["quality"]?.toStr ?: "ok"
    rawQuality = data["rawQuality"]?.toStr ?: quality
    simulated = data["simulated"] == true
    cleaning = data["cleaning"] as Map
    sources = EnerCubixMath.strings(data["sourceIds"])
    if (sources.isEmpty) sources=[id]
    samples = parse(data["samples"])
    rawSamples = data["rawSamples"] == null ? samples : parse(data["rawSamples"])
    intervals = data.containsKey("intervals") ? parseIntervals(data["intervals"]) : null
  }
  Str id
  Str unit
  Str mode
  Str quality
  Str rawQuality
  Bool simulated
  [Str:Obj?]? cleaning
  Str[] sources
  EnerCubixSample[] samples
  EnerCubixSample[] rawSamples
  EnerCubixInterval[]? intervals
  private EnerCubixKnownUsage? knownReader

  Str:Obj? knownUsage(DateTime start, DateTime end, DateTime queryEnd)
  {
    if (knownReader == null) knownReader=EnerCubixKnownUsage(this)
    return knownReader.read(start,end,queryEnd)
  }

  EnerCubixValue read(DateTime start, DateTime end, Bool raw := false)
  {
    src := sources
    effective:=raw ? rawQuality : quality
    if (!["ok","estimated","derived","cleaned","corrected","filtered","substituted","na"].contains(effective)) return EnerCubixValue(null,effective,src)
    if (raw && mode != "cov")
    {
      first:=lowerBoundIn(rawSamples,start); last:=lowerBoundIn(rawSamples,end)
      selected:=first == last ? EnerCubixSample[,] : rawSamples[first..<last]
      if (selected.any |s| { s.valueType == "na" }) return EnerCubixValue(null,"na",src)
      if (selected.isEmpty || selected.any |s| { s.value == null }) return EnerCubixValue(null,"missing",[id])
      total:=0f; selected.each |s| { total+=s.value }
      return EnerCubixValue(total/selected.size.toFloat,effective,[id])
    }
    if (mode == "sampled" || mode == "cov") return gauge(start,end)
    if (mode == "cumulative")
    {
      a := boundary(start); b := boundary(end)
      if (a.value == null || b.value == null) return EnerCubixValue(null,EnerCubixValue.worse(a.quality,b.quality),src)
      prev := a.value
      bad := ""
      between(start,end).each |s|
      {
        if (s.ts <= start || s.ts >= end) return
        if (s.value == null) { bad="missing"; return }
        if (prev != null && s.value < prev) bad="reset"
        prev = s.value
      }
      if (prev != null && b.value < prev) bad="reset"
      if (!bad.isEmpty) return EnerCubixValue(null,bad,src)
      return EnerCubixValue(b.value-a.value,EnerCubixValue.worse(quality,EnerCubixValue.worse(a.quality,b.quality)),src)
    }
    if (mode != "interval") return EnerCubixValue(null,"unsupportedHistoryMode",src)
    if (intervals != null) return interval(start,end)
    if (cleaning != null)
    {
      if (start != EnerCubixMath.floorHour(start) || end-start != 1hr) return EnerCubixValue(null,"incompleteInterval",src)
      values:=between(start,end)
      if (values.isEmpty) return EnerCubixValue(null,"missing",src)
      return EnerCubixValue.sum(values.map |s->EnerCubixValue| { EnerCubixValue(s.value,s.valueType == "na" ? "na" : s.quality,src) })
    }
    // Interval values are START stamped; one value covers its hour, not a counter.
    hour := EnerCubixMath.floorHour(start)
    values := between(hour,hour+1hr)
    if (values.isEmpty || values.any |s| { s.value == null }) return EnerCubixValue(null,"missing",src)
    total := 0f; values.each |s| { total += s.value }
    if (total < 0f) return EnerCubixValue(null,"negative",src)
    fraction := (end-start).ticks.toFloat / 1hr.ticks.toFloat
    return EnerCubixValue(total*fraction,EnerCubixValue.worse(quality,fraction == 1f ? "ok" : "estimated"),src)
  }

  ** Interval values are authoritative for their exact covered time span. Never
  ** prorate a closed value into an unmeasured portion of the interval.
  private EnerCubixValue interval(DateTime start, DateTime end)
  {
    rows:=intervals
    lo:=0; hi:=rows.size
    while (lo < hi)
    {
      mid:=(lo+hi)/2
      if (rows[mid].start < start) lo=mid+1
      else hi=mid
    }
    if (lo > 0 && rows[lo-1].end > start) return EnerCubixValue(null,"incompleteInterval",sources)
    cursor:=start; values:=EnerCubixValue[,]
    for (i:=lo;i<rows.size && rows[i].start < end;i++)
    {
      row:=rows[i]
      if (row.start != cursor) return EnerCubixValue(null,"missing",sources)
      if (row.end > end) return EnerCubixValue(null,"incompleteInterval",sources)
      values.add(EnerCubixValue(row.value,row.valueType == "na" ? "na" : row.quality,sources))
      cursor=row.end
    }
    if (cursor != end) return EnerCubixValue(null,"missing",sources)
    return EnerCubixValue.sum(values)
  }

  private EnerCubixValue boundary(DateTime ts)
  {
    index:=lowerBound(ts)
    exact:=index < samples.size && samples[index].ts == ts ? samples[index] : null
    if (exact != null) return EnerCubixValue(exact.value,exact.value == null ? "missing" : "ok",[id])
    before:=index > 0 ? samples[index-1] : null
    after:=index < samples.size ? samples[index] : null
    if (before?.value == null || after?.value == null) return EnerCubixValue(null,"missing",[id])
    if (after.value < before.value) return EnerCubixValue(null,"reset",[id])
    fraction := (ts-before.ts).ticks.toFloat/(after.ts-before.ts).ticks.toFloat
    return EnerCubixValue(before.value+(after.value-before.value)*fraction,"estimated",[id])
  }

  private EnerCubixValue gauge(DateTime start, DateTime end)
  {
    if (mode == "cov") return cov(start,end)
    values := between(start,end)
    if (values.isEmpty || values.any |s| { s.value == null }) return EnerCubixValue(null,"missing",[id])
    total := 0f; values.each |s| { total+=s.value }
    return EnerCubixValue(total/values.size.toFloat,quality,[id])
  }

  private EnerCubixValue cov(DateTime start, DateTime end)
  {
    index:=lowerBound(start)
    if (index < samples.size && samples[index].ts == start) index++
    if (index == 0) return EnerCubixValue(null,"missing",[id])
    current:=samples[index-1].value; cursor:=start; weighted:=0f
    changes:=between(start,end)
    for (i:=0;i<changes.size;i++)
    {
      sample:=changes[i]
      if (sample.ts == start) { current=sample.value; continue }
      if (current == null) return EnerCubixValue(null,"missing",[id])
      weighted+=current*(sample.ts-cursor).ticks.toFloat
      cursor=sample.ts; current=sample.value
    }
    if (current == null) return EnerCubixValue(null,"missing",[id])
    weighted+=current*(end-cursor).ticks.toFloat
    return EnerCubixValue(weighted/(end-start).ticks.toFloat,quality,[id])
  }

  private EnerCubixSample[] between(DateTime start, DateTime end)
  {
    first:=lowerBound(start); last:=lowerBound(end)
    return first == last ? EnerCubixSample[,] : samples[first..<last]
  }

  private Int lowerBound(DateTime at)
  {
    return lowerBoundIn(samples,at)
  }

  private static Int lowerBoundIn(EnerCubixSample[] rows, DateTime at)
  {
    lo:=0; hi:=rows.size
    while (lo < hi)
    {
      mid:=(lo+hi)/2
      if (rows[mid].ts < at) lo=mid+1
      else hi=mid
    }
    return lo
  }

  private static EnerCubixSample[] parse(Obj? rows)
  {
    byTime:=Int:EnerCubixSample[:]
    EnerCubixMath.maps(rows).each |s|
    {
      ts:=DateTime.fromIso(s["ts"]?.toStr ?: "",false)
      if (ts != null) byTime[ts.ticks]=EnerCubixSample(ts,EnerCubixMath.num(s["value"]),s["quality"] as Str ?: "ok",s["valueType"] as Str ?: (s["value"] == null ? "null" : "number"))
    }
    return byTime.vals.sort |a,b| { a.ts <=> b.ts }
  }

  private static EnerCubixInterval[] parseIntervals(Obj? rows)
  {
    out:=EnerCubixInterval[,]
    EnerCubixMath.maps(rows).each |row|
    {
      start:=DateTime.fromIso(row["from"]?.toStr ?: "",false)
      end:=DateTime.fromIso(row["to"]?.toStr ?: "",false)
      if (start == null || end == null || end <= start) return
      value:=EnerCubixMath.num(row["value"])
      valueType:=row["valueType"] as Str ?: (value == null ? "null" : "number")
      out.add(EnerCubixInterval(start,end,value,row["quality"] as Str ?: (value == null ? "missing" : "ok"),valueType))
    }
    return out.sort |a,b| { cmp:=a.start <=> b.start; return cmp == 0 ? a.end <=> b.end : cmp }
  }
}


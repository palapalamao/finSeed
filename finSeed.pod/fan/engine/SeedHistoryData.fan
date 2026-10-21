internal class SeedSample
{
  new make(DateTime ts, Float? value) { this.ts=ts; this.value=value }
  DateTime ts
  Float? value
}

internal class SeedHistoryData
{
  new make(Str:Obj? data)
  {
    id = data["pointId"]?.toStr ?: ""
    unit = data["unit"]?.toStr ?: ""
    mode = data["mode"]?.toStr ?: "sampled"
    quality = data["quality"]?.toStr ?: "ok"
    rawQuality = data["rawQuality"]?.toStr ?: quality
    samples = parse(data["samples"])
    rawSamples = data["rawSamples"] == null ? samples : parse(data["rawSamples"])
  }
  Str id
  Str unit
  Str mode
  Str quality
  Str rawQuality
  SeedSample[] samples
  SeedSample[] rawSamples

  SeedValue read(DateTime start, DateTime end, Bool raw := false)
  {
    src := [id]
    effective:=raw ? rawQuality : quality
    if (effective != "ok" && effective != "estimated" && effective != "derived") return SeedValue(null,effective,src)
    if (raw && mode != "cov")
    {
      first:=lowerBoundIn(rawSamples,start); last:=lowerBoundIn(rawSamples,end)
      selected:=first == last ? SeedSample[,] : rawSamples[first..<last]
      if (selected.isEmpty || selected.any |s| { s.value == null }) return SeedValue(null,"missing",[id])
      total:=0f; selected.each |s| { total+=s.value }
      return SeedValue(total/selected.size.toFloat,effective,[id])
    }
    if (mode == "sampled" || mode == "cov") return gauge(start,end)
    if (mode == "cumulative")
    {
      a := boundary(start); b := boundary(end)
      if (a.value == null || b.value == null) return SeedValue(null,SeedValue.worse(a.quality,b.quality),src)
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
      if (!bad.isEmpty) return SeedValue(null,bad,src)
      return SeedValue(b.value-a.value,SeedValue.worse(quality,SeedValue.worse(a.quality,b.quality)),src)
    }
    if (mode != "interval") return SeedValue(null,"unsupportedHistoryMode",src)
    // Interval values are START stamped; one value covers its hour, not a counter.
    hour := SeedMath.floorHour(start)
    values := between(hour,hour+1hr)
    if (values.isEmpty || values.any |s| { s.value == null }) return SeedValue(null,"missing",src)
    total := 0f; values.each |s| { total += s.value }
    if (total < 0f) return SeedValue(null,"negative",src)
    fraction := (end-start).ticks.toFloat / 1hr.ticks.toFloat
    return SeedValue(total*fraction,SeedValue.worse(quality,fraction == 1f ? "ok" : "estimated"),src)
  }

  private SeedValue boundary(DateTime ts)
  {
    index:=lowerBound(ts)
    exact:=index < samples.size && samples[index].ts == ts ? samples[index] : null
    if (exact != null) return SeedValue(exact.value,exact.value == null ? "missing" : "ok",[id])
    before:=index > 0 ? samples[index-1] : null
    after:=index < samples.size ? samples[index] : null
    if (before?.value == null || after?.value == null) return SeedValue(null,"missing",[id])
    if (after.value < before.value) return SeedValue(null,"reset",[id])
    fraction := (ts-before.ts).ticks.toFloat/(after.ts-before.ts).ticks.toFloat
    return SeedValue(before.value+(after.value-before.value)*fraction,"estimated",[id])
  }

  private SeedValue gauge(DateTime start, DateTime end)
  {
    if (mode == "cov") return cov(start,end)
    values := between(start,end)
    if (values.isEmpty || values.any |s| { s.value == null }) return SeedValue(null,"missing",[id])
    total := 0f; values.each |s| { total+=s.value }
    return SeedValue(total/values.size.toFloat,quality,[id])
  }

  private SeedValue cov(DateTime start, DateTime end)
  {
    index:=lowerBound(start)
    if (index < samples.size && samples[index].ts == start) index++
    if (index == 0) return SeedValue(null,"missing",[id])
    current:=samples[index-1].value; cursor:=start; weighted:=0f
    changes:=between(start,end)
    for (i:=0;i<changes.size;i++)
    {
      sample:=changes[i]
      if (sample.ts == start) { current=sample.value; continue }
      if (current == null) return SeedValue(null,"missing",[id])
      weighted+=current*(sample.ts-cursor).ticks.toFloat
      cursor=sample.ts; current=sample.value
    }
    if (current == null) return SeedValue(null,"missing",[id])
    weighted+=current*(end-cursor).ticks.toFloat
    return SeedValue(weighted/(end-start).ticks.toFloat,quality,[id])
  }

  private SeedSample[] between(DateTime start, DateTime end)
  {
    first:=lowerBound(start); last:=lowerBound(end)
    return first == last ? SeedSample[,] : samples[first..<last]
  }

  private Int lowerBound(DateTime at)
  {
    return lowerBoundIn(samples,at)
  }

  private static Int lowerBoundIn(SeedSample[] rows, DateTime at)
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

  private static SeedSample[] parse(Obj? rows)
  {
    byTime:=Int:SeedSample[:]
    SeedMath.maps(rows).each |s|
    {
      ts:=DateTime.fromIso(s["ts"]?.toStr ?: "",false)
      if (ts != null) byTime[ts.ticks]=SeedSample(ts,SeedMath.num(s["value"]))
    }
    return byTime.vals.sort |a,b| { a.ts <=> b.ts }
  }
}


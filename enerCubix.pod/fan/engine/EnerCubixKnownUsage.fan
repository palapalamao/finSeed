** Report-only known usage. It never prorates an interval or replaces a strict total.
internal class EnerCubixKnownUsage
{
  static Bool supported(Str kind, Str metric)
  { metric != "cost" && !["trend","forecast","regression","cop","leak"].contains(kind) }

  static DateTime cutoff(Str:Obj? request)
  {
    text:=request["asOf"] as Str
    if (text != null) return DateTime.fromIso(text,false) ?: throw ArgErr("Invalid data cutoff")
    return DateTime.now
  }

  static [Str:Obj?][] clip([Str:Obj?][] histories, DateTime cutoff)
  {
    return histories.map |h->[Str:Obj?]|
    {
      if (h["dataCutoff"] == cutoff.toIso) return h
      out:=h.dup
      out["dataCutoff"]=cutoff.toIso
      ["samples","rawSamples"].each |key|
      {
        if (h[key] == null) return
        out[key]=EnerCubixMath.maps(h[key]).findAll |s|
        {
          at:=DateTime.fromIso(s["ts"].toStr)
          return at <= cutoff && (key == "rawSamples" || h["mode"] != "interval" || h.containsKey("intervals") || at+1hr <= cutoff)
        }
      }
      if (h.containsKey("intervals")) out["intervals"]=EnerCubixMath.maps(h["intervals"]).findAll |row| {DateTime.fromIso(row["to"].toStr) <= cutoff}
      return out
    }
  }

  static Str:Obj? fields(EnerCubixValue value)
  { ["knownValue":value.value,"knownValueType":value.valueType,"knownQuality":value.quality] }

  static [Str:Obj?][] evidence([Str:Obj?][] reads)
  {
    count:=0
    return reads.map |row->[Str:Obj?]|
    {
      out:=row.dup; intervals:=EnerCubixMath.maps(row["intervals"])
      keep:=intervals.size.min((1000-count).max(0))
      out["intervals"]=keep == 0 ? [Str:Obj?][,] : intervals[0..<keep]
      if (keep < intervals.size) out["detailsTruncated"]=true
      count+=keep; return out
    }
  }
  new make(EnerCubixHistoryData history)
  {
    this.history=history
    if (history.intervals != null) rows=history.intervals
    else if (history.mode == "cumulative")
    {
      for (i:=1;i<history.samples.size;i++)
      {
        a:=history.samples[i-1]; b:=history.samples[i]
        q:=a.valueType == "na" || b.valueType == "na" ? "na" : (a.value == null || b.value == null ? "missing" : (b.value < a.value ? "reset" : EnerCubixValue.worse(a.quality,b.quality)))
        v:=q == "na" || q == "missing" || q == "reset" ? null : b.value-a.value
        rows.add(EnerCubixInterval(a.ts,b.ts,v,q,q == "na" ? "na" : (v == null ? "null" : "number")))
      }
    }
    else if (history.mode == "interval")
    {
      history.samples.each |s|
      {
        negative:=s.value != null && s.value < 0f
        rows.add(EnerCubixInterval(s.ts,s.ts+1hr,negative ? null : s.value,negative ? "negative" : s.quality,negative ? "null" : s.valueType))
      }
    }
  }
  private EnerCubixHistoryData history
  private EnerCubixInterval[] rows := [,]

  Str:Obj? read(DateTime start, DateTime end, DateTime queryEnd)
  {
    values:=EnerCubixValue[,]; details:=[Str:Obj?][,]; cursor:=start; covered:=0f; count:=0
    DateTime? coverageStart:=null; DateTime? coverageEnd:=null
    lo:=0; hi:=rows.size
    while (lo < hi) { mid:=(lo+hi)/2; if (rows[mid].start < start) lo=mid+1; else hi=mid }
    for (i:=lo;i<rows.size && rows[i].start < end;i++)
    {
      row:=rows[i]
      // Keep the original closed interval whole, attributed once by its start.
      // queryEnd is the query/as-of bound, never a fabricated bucket boundary.
      if (row.end > queryEnd) continue
      if (row.start < cursor) return ["value":EnerCubixValue(null,"invalidConfiguration",history.sources),"intervals":details,"coveredSeconds":covered]
      if (row.start > cursor) values.add(EnerCubixValue(null,"missing",history.sources))
      q:=row.valueType == "na" ? "na" : row.quality
      if (row.value == null && ["ok","good","derived","estimated","cleaned","corrected"].contains(q)) q="missing"
      values.add(EnerCubixValue(row.value,q,history.sources)); cursor=row.end
      count++
      if (row.value != null)
      {
        if (coverageStart == null) coverageStart=row.start
        coverageEnd=row.end
        covered+=(row.end-row.start).ticks.toFloat/1sec.ticks.toFloat
      }
      if (details.size < 1000) details.add(["intervalStart":row.start.toIso,"intervalEnd":row.end.toIso,"value":row.value,"valueType":row.valueType,"quality":q])
    }
    if (cursor != end) values.add(EnerCubixValue(null,"incompleteInterval",history.sources))
    value:=combine(values)
    return ["value":value,"knownValue":value.value,"knownValueType":value.valueType,"knownQuality":value.quality,"intervals":details,"coveredSeconds":covered,"intervalCount":count,"intervalStart":coverageStart?.toIso,"intervalEnd":coverageEnd?.toIso,"detailsTruncated":count > details.size]
  }

  static EnerCubixValue combine(EnerCubixValue[] values)
  {
    sources:=Str[,]; total:=0f; numeric:=0; missing:=false; allNA:=!values.isEmpty; quality:="ok"
    values.each |v|
    {
      sources.addAll(v.sources)
      if (v.value != null) { total+=v.value; numeric++; allNA=false; quality=EnerCubixValue.worse(quality,v.quality) }
      else
      {
        missing=true
        if (v.quality != "na") allNA=false
      }
    }
    invalid:=values.find |v| { v.value == null && !["missing","incompleteInterval","filtered","substituted","na","reset","negative","maximum"].contains(v.quality) }
    if (invalid != null) return EnerCubixValue(null,invalid.quality,sources.unique)
    if (numeric == 0) return EnerCubixValue(null,allNA ? "na" : "missing",sources.unique)
    return EnerCubixValue(total,missing ? EnerCubixValue.worse(quality,"filtered") : quality,sources.unique)
  }
}

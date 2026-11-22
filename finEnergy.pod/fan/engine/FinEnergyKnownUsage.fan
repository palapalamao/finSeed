** Report-only known usage. It never prorates an interval or replaces a strict total.
internal class FinEnergyKnownUsage
{
  static Bool supported(Str kind, Str metric)
  { !["trend","forecast","regression","cop","leak"].contains(kind) }

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
        // Raw counters and explicit intervals have the same cutoff predicate.
        // Implicit hourly consumption does not: its processed hour must close.
        if(key=="rawSamples" && h[key]===h["samples"] && (h["mode"]!="interval" || h.containsKey("intervals")))
        {out[key]=out["samples"];return}
        out[key]=FinEnergyMath.maps(h[key]).findAll |s|
        {
          at:=DateTime.fromIso(s["ts"].toStr)
          return at <= cutoff && (key == "rawSamples" || h["mode"] != "interval" || h.containsKey("intervals") || at+1hr <= cutoff)
        }
      }
      if (h.containsKey("intervals")) out["intervals"]=FinEnergyMath.maps(h["intervals"]).findAll |row| {DateTime.fromIso(row["to"].toStr) <= cutoff}
      closed:=h["_closedIntervals"] as FinEnergyClosedIntervals
      if(closed!=null) out["_closedIntervals"]=closed.clip(cutoff)
      return out
    }
  }

  static Str:Obj? fields(FinEnergyValue value)
  { ["knownValue":value.value,"knownValueType":value.valueType,"knownQuality":value.quality] }

  ** Same contribution set, original hourly time order, stable alias/subpair ties.
  ** Compare instants rather than ISO text across a repeated local DST hour.
  internal static [Str:Obj?][] coverageOrder([Str:Obj?][] reads,[Str:DateTime]? parsed := null)
  {
    return reads.sort |a,b->Int| {coverageCompare(a,b,parsed)}
  }
  internal static Int coverageCompare(Str:Obj? a,Str:Obj? b,[Str:DateTime]? parsed := null)
  {
    c:=coverageTime(a["from"],parsed) <=> coverageTime(b["from"],parsed)
    if(c != 0) return c
    c=coverageTime(a["to"],parsed) <=> coverageTime(b["to"],parsed)
    if(c != 0) return c
    c=(a["nodeId"] as Str ?: "") <=> (b["nodeId"] as Str ?: "")
    return c != 0 ? c : ((a["pointId"] as Str ?: "") <=> (b["pointId"] as Str ?: ""))
  }
  ** Optional caller-owned scratch, expired after one coverage frame.
  internal static DateTime coverageTime(Obj? raw,[Str:DateTime]? parsed)
  {
    text:=raw.toStr
    if(parsed==null) return DateTime.fromIso(text)
    value:=parsed[text]
    if(value==null) {value=DateTime.fromIso(text);parsed[text]=value}
    return value
  }

  static [Str:Obj?][] evidence([Str:Obj?][] reads)
  {
    count:=0
    return reads.map |row->[Str:Obj?]|
    {
      out:=row.dup; intervals:=FinEnergyMath.maps(row["intervals"])
      keep:=intervals.size.min((1000-count).max(0))
      out["intervals"]=keep == 0 ? [Str:Obj?][,] : intervals[0..<keep]
      if (keep < intervals.size) out["detailsTruncated"]=true
      count+=keep; return out
    }
  }
  new make(FinEnergyHistoryData history)
  {
    this.history=history
    if (history.intervals != null) rows=history.intervals
    else if (history.mode == "cumulative")
    {
      for (i:=1;i<history.samples.size;i++)
      {
        a:=history.samples[i-1]; b:=history.samples[i]
        q:=a.valueType == "na" || b.valueType == "na" ? "na" : (a.value == null || b.value == null ? "missing" : (b.value < a.value ? "reset" : FinEnergyValue.worse(a.quality,b.quality)))
        v:=q == "na" || q == "missing" || q == "reset" ? null : b.value-a.value
        rows.add(FinEnergyInterval(a.ts,b.ts,v,q,q == "na" ? "na" : (v == null ? "null" : "number")))
      }
    }
    else if (history.mode == "interval")
    {
      history.samples.each |s|
      {
        negative:=s.value != null && s.value < 0f
        rows.add(FinEnergyInterval(s.ts,s.ts+1hr,negative ? null : s.value,negative ? "negative" : s.quality,negative ? "null" : s.valueType))
      }
    }
  }
  private FinEnergyHistoryData history
  private FinEnergyInterval[] rows := [,]

  Str:Obj? read(DateTime start, DateTime end, DateTime queryEnd, Bool includeRuleFacts := false, Int detailLimit := 1000,Int[]? originalDetails := null)
  {
    if(detailLimit<0 || detailLimit>1000) throw ArgErr("knownDetailLimit")
    values:=FinEnergyValue[,]; details:=[Str:Obj?][,]; cursor:=start; covered:=0f; count:=0
    DateTime? coverageStart:=null; DateTime? coverageEnd:=null; closedHour:=true;containsSubstitution:=false;continuous:=true
    lo:=0; hi:=rows.size
    while (lo < hi) { mid:=(lo+hi)/2; if (rows[mid].start < start) lo=mid+1; else hi=mid }
    for (i:=lo;i<rows.size && rows[i].start < end;i++)
    {
      row:=rows[i]
      // Keep the original closed interval whole, attributed once by its start.
      // queryEnd is the query/as-of bound, never a fabricated bucket boundary.
      if (row.end > queryEnd) continue
      if (row.start < cursor)
      {
        if(originalDetails!=null) originalDetails[0]=count.min(1000)
        return ["value":FinEnergyValue(null,"invalidConfiguration",history.sources),"intervals":details,"coveredSeconds":covered]
      }
      if (row.start > cursor) {values.add(FinEnergyValue(null,"missing",history.sources));if(includeRuleFacts) continuous=false}
      if(includeRuleFacts && row.end>end) continuous=false
      q:=row.valueType == "na" ? "na" : row.quality
      if(includeRuleFacts && q=="substituted") containsSubstitution=true
      if (row.value == null && ["ok","good","derived","estimated","cleaned","corrected"].contains(q)) q="missing"
      if(includeRuleFacts && (row.value == null || row.end > end || !["ok","cleaned","corrected"].contains(q))) closedHour=false
      values.add(FinEnergyValue(row.value,q,history.sources)); cursor=row.end
      count++
      if (row.value != null)
      {
        if (coverageStart == null) coverageStart=row.start
        coverageEnd=row.end
        covered+=(row.end-row.start).ticks.toFloat/1sec.ticks.toFloat
      }
      if (details.size < detailLimit) details.add(["intervalStart":row.start.toIso,"intervalEnd":row.end.toIso,"value":row.value,"valueType":row.valueType,"quality":q])
    }
    if (cursor != end) values.add(FinEnergyValue(null,"incompleteInterval",history.sources))
    value:=combine(values)
    out:=Str:Obj?["value":value,"knownValue":value.value,"knownValueType":value.valueType,"knownQuality":value.quality,"intervals":details,"coveredSeconds":covered,"intervalCount":count,"intervalStart":coverageStart?.toIso,"intervalEnd":coverageEnd?.toIso,"detailsTruncated":count > details.size]
    // Business eligibility is proven over every source interval, before either
    // the local or request-wide diagnostic capture can discard interval rows.
    if(includeRuleFacts && closedHour && count > 0 && covered == 3600f && end-start == 1hr) out["_closedOwnPrimaryHour"]=true
    if(includeRuleFacts && (containsSubstitution || (continuous && cursor==end && count>0 && covered==3600f && end-start==1hr))) out["_containsSubstitutedIntervals"]=containsSubstitution
    if(originalDetails!=null) originalDetails[0]=count.min(1000)
    return out
  }

  static FinEnergyValue combine(FinEnergyValue[] values)
  {
    fold:=FinEnergyValueFold.known()
    values.each |v| {fold.add(v)}
    return fold.finish
  }

}

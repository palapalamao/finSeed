using haystack

internal class FinEnergySample
{
  new make(DateTime ts, Float? value, Str quality := "ok", Str valueType := "number") { this.ts=ts; this.value=value; this.quality=quality; this.valueType=valueType }
  DateTime ts
  Float? value
  Str quality
  Str valueType
}

internal class FinEnergyInterval
{
  new make(DateTime start, DateTime end, Float? value, Str quality, Str valueType)
  { this.start=start; this.end=end; this.value=value; this.quality=quality; this.valueType=valueType }
  DateTime start
  DateTime end
  Float? value
  Str quality
  Str valueType
}

internal class FinEnergyHistoryData
{
  new make(Str:Obj? data)
  {
    frame:=data["_preparedFrame"] as FinEnergyPreparedFrame
    frame?.check
    sourceFrame=frame
    prepared = data["_preparedReads"] as Map
    preparedBudget = data["_preparedBudget"] as FinEnergyPreparedBudget
    id = data["pointId"]?.toStr ?: ""
    unit = data["unit"]?.toStr ?: ""
    mode = data["mode"]?.toStr ?: "sampled"
    quality = data["quality"]?.toStr ?: "ok"
    rawQuality = data["rawQuality"]?.toStr ?: quality
    simulated = data["simulated"] == true
    cleaning = data["cleaning"] as Map
    sources = FinEnergyMath.strings(data["sourceIds"])
    if (sources.isEmpty) sources=[id]
    samples = parse(data["samples"])
    rawSamples = data["rawSamples"] == null || data["rawSamples"] === data["samples"] ? samples : parse(data["rawSamples"])
    intervals = data.containsKey("intervals") ? parseIntervals(data["intervals"]) : null
    sparse=data["_preparedSparse"] as Map
    if(sparse != null)
    {
      sparseDomains=FinEnergyMath.maps(sparse["domains"])
      if(!sparseDomains.isEmpty)
      {
        empty=FinEnergyHistoryData(["pointId":id,"sourceIds":sources,"unit":unit,"mode":mode,"quality":quality])
        at:=(DateTime)sparseDomains.first["from"]
        emptyValue=empty.read(at,at+1hr)
        emptyKnown=empty.knownUsage(at,at+1hr,at+1hr)
      }
    }
    frame?.attach(this)
  }
  ** Typed bounded window for the streaming adapter. Arithmetic below is shared
  ** with whole-range reports; clipping keeps the original source cutoff rule.
  new window(Dict point, Str mode, HisItem[] raw, FinEnergyInterval[]? closed, DateTime cutoff)
    : this.make(["pointId":point.id.id,"unit":point["unit"] ?: "","mode":mode,"quality":closed == null ? "ok" : "cleaned"])
  {
    samples=raw.findAll |item| {item.ts <= cutoff}.map |item->FinEnergySample|
    {
      v:=item.val is Number ? FinEnergyMath.num(((Number)item.val).toFloat) : (item.val is Bool ? (item.val == true ? 1f : 0f) : FinEnergyMath.num(item.val))
      return FinEnergySample(item.ts.toTimeZone(cutoff.tz),v,"ok",FinEnergyHistory.valueType(item.val))
    }
    rawSamples=samples
    if (closed != null) intervals=closed.findAll |row| {row.end <= cutoff}
  }
  ** Private cleaned producer projection. Its strict/known scalar readers use
  ** authoritative closed intervals only; it never escapes to raw/gauge reads.
  ** The general window above retains its complete raw sample behavior.
  new closedWindow(Dict point,FinEnergyInterval[] closed,DateTime cutoff)
    : this.make(["pointId":point.id.id,"unit":point["unit"] ?: "","mode":"interval","quality":"cleaned"])
  {intervals=closed.findAll |row| {row.end<=cutoff}}
  Str id
  Str unit
  Str mode
  Str quality
  Str rawQuality
  Bool simulated
  [Str:Obj?]? cleaning
  Str[] sources
  FinEnergySample[] samples
  FinEnergySample[] rawSamples
  FinEnergyInterval[]? intervals
  private [Str:Obj?]? prepared
  FinEnergyPreparedBudget? preparedBudget
  private Map? sparse
  private [Str:Obj?][] sparseDomains := [,]
  private FinEnergyContext? sparseContext
  private FinEnergyHistoryData? empty
  private FinEnergyValue? emptyValue
  private Str:Obj? emptyKnown := [:]
  private FinEnergyKnownUsage? knownReader
  private Bool frameExpired := false
  private FinEnergyPreparedFrame? sourceFrame
  private FinEnergyPreparedOwner? ownEmptyOwner
  private FinEnergyOwnEmptyValue[]? ownEmptyValues
  private FinEnergyOwnEmptyValue[]? ownStrictValues
  private FinEnergySourceBounds? sourceBounds
  private Map? sourceHourRow
  private FinEnergyOwnEvidence[]? ownEvidence
  private Map? sourceIndex

  internal Bool ownedFrame(FinEnergyPreparedBudget budget)
  {sourceFrame != null && !frameExpired && preparedBudget === budget}

  ** Only the producer can attest that its exact read-only index and entries
  ** were admitted. Read-only caller maps alone carry no ownership proof.
  internal Void bindSourceIndex(Map index,FinEnergyPreparedOwner owner)
  {
    frameCheck
    if(ownEmptyOwner!==owner) return
    if(sourceIndex!=null || !index.isRO || index[id]!==this) throw ArgErr("preparedSourceIndex")
    owner.hold(1);sourceIndex=index
  }
  internal Bool ownsSourceIndex(Map index,FinEnergyPreparedBudget budget)
  {frameCheck;return sourceIndex===index && ownEmptyOwner!=null && ownEmptyOwner.entries!=0 && ownEmptyOwner.budget===budget}

  ** The common source owner outlives all consumer frames. Share only null
  ** results whose exact pair was already proven empty, within one real hour.
  ** Canonical record identity and strict/known queryEnd remain part of the key.
  internal Void bindOwnEmptyFrame(FinEnergyPreparedOwner owner,DateTime from,DateTime to,FinEnergySourceBounds bounds)
  {
    frameCheck
    if(ownEmptyOwner!=null || !ownedFrame(owner.budget)) throw ArgErr("ownEmptyFrameOwner")
    if(to-from!=1hr) return
    if(bounds.from!=from || bounds.to!=to) throw ArgErr("sourceBoundsFrame")
    owner.hold(7);owner.watch |->Void| {clearOwnEmpty};ownEmptyOwner=owner;sourceBounds=bounds
    sourceHourRow=prepared?.get(bounds.key) as Map
  }
  internal FinEnergySourceBounds? exactBounds(DateTime from,DateTime to)
  {frameCheck;return sourceBounds?.from==from && sourceBounds?.to==to ? sourceBounds : null}
  internal FinEnergyOwnEmptyValue? ownEmpty(Str:Obj? record,Str category,DateTime from,DateTime to,Str metric,DateTime? queryEnd)
  {
    frameCheck
    return ownEmptyValues?.find |entry| {entry.record===record && entry.category==category && entry.from==from && entry.to==to && entry.metric==metric && entry.queryEnd==queryEnd}
  }
  internal FinEnergyOwnEmptyValue? rememberOwnEmpty(Str:Obj? record,Str category,DateTime from,DateTime to,Str metric,DateTime? queryEnd,FinEnergyValue value,Str? stableKey := null)
  {
    frameCheck
    if(ownEmptyOwner==null || value.value!=null || emptyDomain(from,to,queryEnd)==null) return null
    existing:=ownEmpty(record,category,from,to,metric,queryEnd);if(existing!=null) return existing
    if(ownEmptyValues==null) {ownEmptyOwner.hold(1);ownEmptyValues=FinEnergyOwnEmptyValue[,]}
    // Entry fields/link and the value object now remain under this source
    // owner after the producing consumer closes; sources remain frame-owned.
    ownEmptyOwner.hold(15)
    entry:=FinEnergyOwnEmptyValue(record,category,from,to,metric,queryEnd,value,stableKey);ownEmptyValues.add(entry);return entry
  }
  ** Numeric strict reads have no known-usage diagnostic side effects. Only
  ** canonical physical records may borrow them, for the exact source hour.
  ** The source owner keeps their values alive after each consumer closes.
  internal FinEnergyOwnEmptyValue? ownStrict(Str:Obj? record,Str category,DateTime from,DateTime to,Str metric)
  {
    frameCheck
    return ownStrictValues?.find |entry| {entry.record===record && entry.category==category && entry.from==from && entry.to==to && entry.metric==metric}
  }
  internal Void rememberOwnStrict(Str:Obj? record,Str category,DateTime from,DateTime to,Str metric,FinEnergyValue value)
  {
    frameCheck
    if(ownEmptyOwner==null || prepared==null || metric=="cost" || value.value==null || value.sources!==sources) return
    if(ownStrict(record,category,from,to,metric)!=null) return
    if(ownStrictValues==null) {ownEmptyOwner.hold(1);ownStrictValues=FinEnergyOwnEmptyValue[,]}
    ownEmptyOwner.hold(15)
    ownStrictValues.add(FinEnergyOwnEmptyValue(record,category,from,to,metric,null,value))
  }
  private Void clearOwnEmpty()
  {
    ownEmptyValues?.clear;ownEmptyValues=null
    ownStrictValues?.clear;ownStrictValues=null;ownEmptyOwner=null;sourceBounds=null;sourceHourRow=null
    ownEvidence?.clear;ownEvidence=null;sourceIndex=null
  }
  internal [Str:Obj?]? knownEvidence(Str:Obj? record,DateTime from,DateTime to,DateTime queryEnd)
  {knownEvidenceSlot(record,from,to,queryEnd)?.evidence}
  internal FinEnergyOwnEvidence? knownEvidenceSlot(Str:Obj? record,DateTime from,DateTime to,DateTime queryEnd)
  {
    frameCheck
    return ownEvidence?.find |entry| {entry.record===record && entry.from==from && entry.to==to && entry.queryEnd==queryEnd}
  }
  internal Void rememberKnownEvidence(Str:Obj? record,DateTime from,DateTime to,DateTime queryEnd,Str:Obj? evidence,Str? key := null)
  {
    frameCheck
    if(ownEmptyOwner==null || prepared==null || !record.isImmutable || (record["kind"]!="meter" && record["kind"]!="totalMeter") || evidence["sourceIds"]!==sources) return
    if(knownEvidence(record,from,to,queryEnd)!=null) return
    if(ownEvidence==null) {ownEmptyOwner.hold(1);ownEvidence=FinEnergyOwnEvidence[,]}
    ownEmptyOwner.hold(9+evidence.size)
    ownEvidence.add(FinEnergyOwnEvidence(record,from,to,queryEnd,evidence,key))
  }

  internal Void expireFrame()
  {
    clearOwnEmpty
    frameExpired=true;sourceFrame=null;prepared=null;sparse=null;sparseDomains.clear
    sparseContext=null;empty=null;emptyValue=null;emptyKnown.clear;knownReader=null
    cleaning=null;samples.clear;rawSamples.clear;intervals=null
  }
  private Void frameCheck() {if(frameExpired) throw ArgErr("preparedFrameExpired")}

  Str:Obj? knownUsage(DateTime start, DateTime end, DateTime queryEnd, Bool includeRuleFacts := false)
  {readKnownUsage(start,end,queryEnd,includeRuleFacts,false)}

  ** Native window producer only: bound detail construction by capture room,
  ** without clipping numeric, coverage or all-interval rule evaluation.
  internal Str:Obj? captureKnownUsage(DateTime start,DateTime end,DateTime queryEnd,Bool includeRuleFacts,Int detailLimit)
  {
    frameCheck
    if(prepared!=null || sourceFrame!=null) throw ArgErr("captureKnownNeedsWindow")
    if(knownReader==null) knownReader=FinEnergyKnownUsage(this)
    return knownReader.read(start,end,queryEnd,includeRuleFacts,detailLimit)
  }

  ** The owned context reads this view synchronously without retaining or
  ** changing it. Only the existing proven-empty map is borrowed; other reads
  ** retain the public method's independent mutable result.
  internal Str:Obj? borrowedKnownUsage(DateTime start,DateTime end,DateTime queryEnd)
  {
    frameCheck
    if(sourceFrame==null || preparedBudget==null) throw ArgErr("preparedKnownViewNeedsFrame")
    return readKnownUsage(start,end,queryEnd,false,true)
  }
  internal Bool isBorrowedEmptyKnown(Map data)
  {frameCheck;return sourceFrame!=null && prepared!=null && !emptyKnown.isEmpty && data===emptyKnown}

  private Str:Obj? readKnownUsage(DateTime start,DateTime end,DateTime queryEnd,Bool includeRuleFacts,Bool borrowEmpty)
  {
    frameCheck
    if (prepared != null)
    {
      preparedBudget?.lookup
      row:=preparedPair(start,end)
      data:=((Map?)row?.get("known"))?.get(queryEnd.ticks.toStr) as Map
      if (data == null)
      {
        if(sparsePair(start,end) && ((DateTime[])sparse["queryEnds"]).contains(queryEnd))
        {preparedBudget?.sparseHits?.increment;return borrowEmpty ? emptyKnown : emptyKnown.dup}
        preparedBudget?.unprepared?.increment
        return ["value":FinEnergyValue(null,"streamingReadNotPrepared",sources)]
      }
      out:=data.dup; if(!includeRuleFacts) {out.remove("_closedOwnPrimaryHour");out.remove("_containsSubstitutedIntervals")}
      out["value"]=FinEnergyValue(FinEnergyMath.num(data["knownValue"]),data["knownQuality"].toStr,sources)
      return out
    }
    if (knownReader == null) knownReader=FinEnergyKnownUsage(this)
    return knownReader.read(start,end,queryEnd,includeRuleFacts)
  }

  FinEnergyValue read(DateTime start, DateTime end, Bool raw := false)
  {
    frameCheck
    if (prepared != null)
    {
      preparedBudget?.lookup
      row:=preparedPair(start,end)
      v:=row?.get(raw ? "raw" : "strict") as Map
      if(v == null && !raw && sparsePair(start,end))
      {
        preparedBudget?.sparseHits?.increment
        hour:=FinEnergyMath.floorHour(start)
        domain:=sparseDomains.find |r| {hour >= (DateTime)r["from"] && hour+1hr <= (DateTime)r["to"]}
        q:=domain?.get("strictQuality") as Str ?: "missing"
        return q == "missing" ? emptyValue : FinEnergyValue(null,q,sources)
      }
      if(v == null) preparedBudget?.unprepared?.increment
      return v == null ? FinEnergyValue(null,"streamingReadNotPrepared",sources) : FinEnergyValue(FinEnergyMath.num(v["value"]),v["quality"].toStr,sources)
    }
    src := sources
    effective:=raw ? rawQuality : quality
    if (!["ok","estimated","derived","cleaned","corrected","filtered","substituted","na"].contains(effective)) return FinEnergyValue(null,effective,src)
    if (raw && mode == "cov") return cov(start,end,true)
    if (raw && mode != "cov")
    {
      first:=lowerBoundIn(rawSamples,start); last:=lowerBoundIn(rawSamples,end)
      selected:=first == last ? FinEnergySample[,] : rawSamples[first..<last]
      if (selected.any |s| { s.valueType == "na" }) return FinEnergyValue(null,"na",src)
      if (selected.isEmpty || selected.any |s| { s.value == null }) return FinEnergyValue(null,"missing",[id])
      total:=0f; selected.each |s| { total+=s.value }
      return FinEnergyValue(total/selected.size.toFloat,effective,[id])
    }
    if (mode == "sampled" || mode == "cov") return gauge(start,end)
    if (mode == "cumulative")
    {
      a := boundary(start); b := boundary(end)
      if (a.value == null || b.value == null) return FinEnergyValue(null,FinEnergyValue.worse(a.quality,b.quality),src)
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
      if (!bad.isEmpty) return FinEnergyValue(null,bad,src)
      return FinEnergyValue(b.value-a.value,FinEnergyValue.worse(quality,FinEnergyValue.worse(a.quality,b.quality)),src)
    }
    if (mode != "interval") return FinEnergyValue(null,"unsupportedHistoryMode",src)
    if (intervals != null) return interval(start,end)
    if (cleaning != null)
    {
      if (start != FinEnergyMath.floorHour(start) || end-start != 1hr) return FinEnergyValue(null,"incompleteInterval",src)
      values:=between(start,end)
      if (values.isEmpty) return FinEnergyValue(null,"missing",src)
      return FinEnergyValue.sum(values.map |s->FinEnergyValue| { FinEnergyValue(s.value,s.valueType == "na" ? "na" : s.quality,src) })
    }
    // Interval values are START stamped; one value covers its hour, not a counter.
    hour := FinEnergyMath.floorHour(start)
    values := between(hour,hour+1hr)
    if (values.isEmpty || values.any |s| { s.value == null }) return FinEnergyValue(null,"missing",src)
    total := 0f; values.each |s| { total += s.value }
    if (total < 0f) return FinEnergyValue(null,"negative",src)
    fraction := (end-start).ticks.toFloat / 1hr.ticks.toFloat
    return FinEnergyValue(total*fraction,FinEnergyValue.worse(quality,fraction == 1f ? "ok" : "estimated"),src)
  }

  ** Only the already-read domain and exact original prepared pair rules qualify.
  private Bool sparsePair(DateTime start, DateTime end)
  {
    if(sparse == null || sparse["version"] != 1 || end <= start) return false
    hour:=FinEnergyMath.floorHour(start)
    if(!sparseDomains.any |r| {hour >= (DateTime)r["from"] && hour+1hr <= (DateTime)r["to"]}) return false
    if(start == hour && end == hour+1hr) return true
    // Full hours need no tariff-bound context. Construct it only when an
    // original partial pair actually requires the unchanged pair expansion.
    if(sparseContext==null) sparseContext=FinEnergyContext([Str:Obj?][,],[Str:Obj?][,],TimeZone.fromStr(sparse["tz"].toStr))
    return FinEnergyCockpitStream.pairs(hour,FinEnergyMath.maps(sparse["queries"]),( [Str:Obj?]?[])sparse["tariffs"],sparseContext).any |p| {p["from"] == start && p["to"] == end}
  }

  ** A whole range is empty only inside one proven domain, with prepared first/
  ** last subpairs and the exact known queryEnd. This never infers an unread gap.
  Int? emptyDomain(DateTime start,DateTime end,DateTime? queryEnd := null)
  {
    frameCheck
    if(sparse == null || sparse["version"] != 1 || end <= start || (queryEnd != null && !((DateTime[])sparse["queryEnds"]).contains(queryEnd))) return null
    index:=sparseDomains.findIndex |r| {start >= (DateTime)r["from"] && end <= (DateTime)r["to"]}
    if(index == null) return null
    if(start.min == 0 && start.sec == 0 && start.nanoSec == 0 && end-start == 1hr) return index
    firstEnd:=FinEnergyMath.floorHour(start)+1hr;if(firstEnd > end) firstEnd=end
    lastStart:=FinEnergyMath.floorHour(end-1ns);if(lastStart < start) lastStart=start
    return sparsePair(start,firstEnd) && sparsePair(lastStart,end) ? index : null
  }

  Bool unpreparedPair(DateTime start,DateTime end,DateTime? queryEnd)
  {
    frameCheck
    if(prepared == null) return false
    row:=preparedPair(start,end)
    if(row != null && (queryEnd == null || (row["known"] as Map)?.containsKey(queryEnd.ticks.toStr) == true)) return false
    return emptyDomain(start,end,queryEnd) == null
  }
  DateTime? constantEnd(DateTime start,DateTime end,DateTime? queryEnd)
  {
    frameCheck
    if(sparse == null || sparse["version"] != 1) return null
    // Outside the frozen prepared window is an error domain, never missing.
    a:=(DateTime)sparse["from"];b:=(DateTime)sparse["to"]
    if(start >= b) return end
    if(start < a) return end < a ? end : a
    domain:=sparseDomains.find |r| {start >= (DateTime)r["from"] && start < (DateTime)r["to"]}
    if(domain == null) return null
    until:=(DateTime)domain["to"];if(until > end) until=end
    return emptyDomain(start,until,queryEnd) == null ? null : until
  }

  ** The exact source watermark row is stable until its frame expires. Other
  ** partial pairs retain the original key lookup and missing-domain rules.
  private Map? preparedPair(DateTime start,DateTime end)
  {
    if(sourceBounds!=null && sourceBounds.from==start && sourceBounds.to==end) return sourceHourRow
    return prepared.isEmpty ? null : prepared[FinEnergyCockpitStream.key(start,end)] as Map
  }

  ** Interval values are authoritative for their exact covered time span. Never
  ** prorate a closed value into an unmeasured portion of the interval.
  private FinEnergyValue interval(DateTime start, DateTime end)
  {
    rows:=intervals
    lo:=0; hi:=rows.size
    while (lo < hi)
    {
      mid:=(lo+hi)/2
      if (rows[mid].start < start) lo=mid+1
      else hi=mid
    }
    if (lo > 0 && rows[lo-1].end > start) return FinEnergyValue(null,"incompleteInterval",sources)
    cursor:=start; values:=FinEnergyValue[,]
    for (i:=lo;i<rows.size && rows[i].start < end;i++)
    {
      row:=rows[i]
      if (row.start != cursor) return FinEnergyValue(null,"missing",sources)
      if (row.end > end) return FinEnergyValue(null,"incompleteInterval",sources)
      values.add(FinEnergyValue(row.value,row.valueType == "na" ? "na" : row.quality,sources))
      cursor=row.end
    }
    if (cursor != end) return FinEnergyValue(null,"missing",sources)
    return FinEnergyValue.sum(values)
  }

  private FinEnergyValue boundary(DateTime ts)
  {
    index:=lowerBound(ts)
    exact:=index < samples.size && samples[index].ts == ts ? samples[index] : null
    if (exact != null) return FinEnergyValue(exact.value,exact.value == null ? "missing" : "ok",[id])
    before:=index > 0 ? samples[index-1] : null
    after:=index < samples.size ? samples[index] : null
    if (before?.value == null || after?.value == null) return FinEnergyValue(null,"missing",[id])
    if (after.value < before.value) return FinEnergyValue(null,"reset",[id])
    fraction := (ts-before.ts).ticks.toFloat/(after.ts-before.ts).ticks.toFloat
    return FinEnergyValue(before.value+(after.value-before.value)*fraction,"estimated",[id])
  }

  private FinEnergyValue gauge(DateTime start, DateTime end)
  {
    if (mode == "cov") return cov(start,end)
    values := between(start,end)
    if (values.isEmpty || values.any |s| { s.value == null }) return FinEnergyValue(null,"missing",[id])
    total := 0f; values.each |s| { total+=s.value }
    return FinEnergyValue(total/values.size.toFloat,quality,[id])
  }

  private FinEnergyValue cov(DateTime start, DateTime end, Bool preserveNa := false)
  {
    index:=lowerBound(start)
    if (index < samples.size && samples[index].ts == start) index++
    if (index == 0) return FinEnergyValue(null,"missing",[id])
    if (preserveNa && samples[index-1].valueType == "na") return FinEnergyValue(null,"na",[id])
    current:=samples[index-1].value; cursor:=start; weighted:=0f
    changes:=between(start,end)
    if (preserveNa && changes.any |s| {s.valueType == "na"}) return FinEnergyValue(null,"na",[id])
    for (i:=0;i<changes.size;i++)
    {
      sample:=changes[i]
      if (sample.ts == start) { current=sample.value; continue }
      if (current == null) return FinEnergyValue(null,"missing",[id])
      weighted+=current*(sample.ts-cursor).ticks.toFloat
      cursor=sample.ts; current=sample.value
    }
    if (current == null) return FinEnergyValue(null,"missing",[id])
    weighted+=current*(end-cursor).ticks.toFloat
    return FinEnergyValue(weighted/(end-start).ticks.toFloat,quality,[id])
  }

  private FinEnergySample[] between(DateTime start, DateTime end)
  {
    first:=lowerBound(start); last:=lowerBound(end)
    return first == last ? FinEnergySample[,] : samples[first..<last]
  }

  private Int lowerBound(DateTime at)
  {
    return lowerBoundIn(samples,at)
  }

  private static Int lowerBoundIn(FinEnergySample[] rows, DateTime at)
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

  private static FinEnergySample[] parse(Obj? rows)
  {
    byTime:=Int:FinEnergySample[:]
    FinEnergyMath.maps(rows).each |s|
    {
      ts:=DateTime.fromIso(s["ts"]?.toStr ?: "",false)
      if (ts != null) byTime[ts.ticks]=FinEnergySample(ts,FinEnergyMath.num(s["value"]),s["quality"] as Str ?: "ok",s["valueType"] as Str ?: (s["value"] == null ? "null" : "number"))
    }
    return byTime.vals.sort |a,b| { a.ts <=> b.ts }
  }

  private static FinEnergyInterval[] parseIntervals(Obj? rows)
  {
    out:=FinEnergyInterval[,]
    FinEnergyMath.maps(rows).each |row|
    {
      start:=DateTime.fromIso(row["from"]?.toStr ?: "",false)
      end:=DateTime.fromIso(row["to"]?.toStr ?: "",false)
      if (start == null || end == null || end <= start) return
      value:=FinEnergyMath.num(row["value"])
      valueType:=row["valueType"] as Str ?: (value == null ? "null" : "number")
      out.add(FinEnergyInterval(start,end,value,row["quality"] as Str ?: (value == null ? "missing" : "ok"),valueType))
    }
    return out.sort |a,b| { cmp:=a.start <=> b.start; return cmp == 0 ? a.end <=> b.end : cmp }
  }
}

internal class FinEnergyOwnEmptyValue
{
  new make(Str:Obj? record,Str category,DateTime from,DateTime to,Str metric,DateTime? queryEnd,FinEnergyValue value,Str? stableKey := null)
  {this.record=record;this.category=category;this.from=from;this.to=to;this.metric=metric;this.queryEnd=queryEnd;this.value=value;this.stableKey=stableKey}
  Str:Obj? record
  Str category
  DateTime from
  DateTime to
  Str metric
  DateTime? queryEnd
  FinEnergyValue value
  Str? stableKey
}

** One source watermark's immutable text, shared by its owned reader group.
internal const class FinEnergySourceBounds
{
  new make(DateTime from,DateTime to) {this.from=from;this.to=to;fromIso=from.toIso;toIso=to.toIso;key=FinEnergyCockpitStream.key(from,to)}
  const DateTime from
  const DateTime to
  const Str fromIso
  const Str toIso
  const Str key
}

internal class FinEnergyOwnEvidence
{
  new make(Str:Obj? record,DateTime from,DateTime to,DateTime queryEnd,Str:Obj? evidence,Str? key)
  {this.record=record;this.from=from;this.to=to;this.queryEnd=queryEnd;this.evidence=evidence;this.key=key}
  Str:Obj? record
  DateTime from
  DateTime to
  DateTime queryEnd
  Str:Obj? evidence
  const Str? key
}


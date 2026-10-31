using haystack
using skyarcd

** Cockpit-only bounded native scan. Exact source windows feed the existing strict
** and known-interval readers; no resampling, auxiliary source or history write.
internal class EnerCubixCockpitStream
{
  static Str key(DateTime a, DateTime b) { "${a.ticks}|${b.ticks}" }

  static [Str:Obj?][] load(Context cx, Str:Obj? request, [Str:Obj?][] records, Str:Dict? points, Str:Dict configs)
  {
    budget:=EnerCubixStreamBudget()
    return prepare(request,records,points,configs,|Dict p,Span span,|HisItem| sink|
    {
      cx.rt.his.read(p,span,Etc.makeDict(["raw":Marker.val]),sink)
    },budget)
  }

  ** Callback seam uses the same block splitter as FIN; synthetic tests never write history.
  static [Str:Obj?][] prepare(Str:Obj? request, [Str:Obj?][] records, Str:Dict? points, Str:Dict configs,
    |Dict,Span,|HisItem|->Void| read, EnerCubixStreamBudget budget)
  {
    out:=[Str:Obj?][,]
    ranges:=EnerCubixMath.maps(request["_cockpitRanges"])
    if (ranges.isEmpty) ranges=[request.dup.set("pointIds",points.keys)]
    ranges.each |range|
    {
      a:=DateTime.fromIso(range["from"].toStr); b:=DateTime.fromIso(range["to"].toStr)
      tz:=TimeZone.fromStr(request["tz"]?.toStr ?: a.tz.name)
      a=a.toTimeZone(tz);b=b.toTimeZone(tz)
      EnerCubixMath.strings(range["pointIds"]).each |id|
      {
        budget.check
        point:=points[id]
        if (point == null || !point.has("his") || !EnerCubixHistory.primaryReadAllowed(point,records))
        {out.add(["pointId":id,"quality":"missing","mode":"cumulative"]);return}
        try
        {
          stream:=EnerCubixCockpitStream(point,configs[id],a,b,request,records,budget)
          pointTz:=TimeZone.fromStr(point["tz"]?.toStr ?: a.tz.name)
          cursor:=(stream.from-1day).toTimeZone(pointTz); end:=(stream.to+1day).toTimeZone(pointTz)
          while (cursor < end)
          {
            next:=cursor+4day; if (next > end) next=end
            stream.block(cursor,next,read); cursor=next
          }
          h:=stream.finish
          h["_cockpitFrom"]=range["from"];h["_cockpitTo"]=range["to"]
          out.add(h)
        }
        catch (EnerCubixHttpErr e) {throw e}
        catch (ArgErr e) {out.add(["pointId":id,"quality":"streamingUnsupportedConfiguration","mode":"cumulative","limitation":e.msg])}
        catch (Err e) {out.add(["pointId":id,"quality":"historyReadError","mode":"cumulative"])}
      }
    }
    stats:=budget.evidence
    out.each |h| {h["streaming"]=stats}
    return out
  }

  private new make(Dict point, Dict? config, DateTime from, DateTime to, Str:Obj? request,
    [Str:Obj?][] records, EnerCubixStreamBudget budget)
  {
    this.point=point; this.config=config;this.budget=budget
    observedEnd=to
    this.from=EnerCubixMath.floorHour(from)
    this.to=EnerCubixMath.floorHour(to);if (this.to < to) this.to+=1hr
    hour=this.from
    cutoff=DateTime.fromIso(request["asOf"]?.toStr ?: to.toIso).toTimeZone(from.tz)
    queries=EnerCubixMath.maps(request["_cockpitReadRanges"])
    if (queries.isEmpty) queries=[request]
    queryEnds=queries.map |q->DateTime| {end:=DateTime.fromIso(q["to"].toStr);return end < cutoff ? end : cutoff}.unique
    cleaned=point["hisFunc"] == "enerCubixCleanHis" && request["raw"] != true
    if (cleaned && (config == null || config.isEmpty)) throw ArgErr("missingCleaningProfile")
    modes:=records.findAll |r| {r["pointId"] == point.id.id && r["historyMode"] != null && r["historyMode"] != "auto"}.map |r->Str| {r["historyMode"].toStr}.unique
    if (modes.size > 1) throw ArgErr("Conflicting EnerCubix history modes")
    mode=modes.first ?: (point.has("hisTotalized") ? "cumulative" : (point["hisMode"]?.toStr == "consumption" ? "interval" : (point["hisMode"]?.toStr ?: "sampled")))
    if (!cleaned && mode != "cumulative" && mode != "interval") throw ArgErr("streamingEnergyModeRequired")
    ctx=EnerCubixContext(records,[Str:Obj?][,],from.tz)
    tariffs=records.findAll |r| {r["pointId"] == point.id.id}.map |r->[Str:Obj?]?| {ctx.tariff(r)}.exclude |t| {t == null}
    meta=["pointId":point.id.id,"sourceIds":[point.id.id],"inputCount":0,"outputCount":0,"validCount":0,"nullCount":0,"naCount":0,"rolloverCount":0,"rejectedCount":0,"removedNACount":0,"substitutedCount":0,"processingScope":"objectIntervals"]
    if (cleaned)
    {
      meta["profileId"]=(config["enerCubixProfileRef"] as Ref)?.id
      meta["profileVersion"]=(config["enerCubixProfileVersion"] as Number)?.toInt
      meta["parameters"]=EnerCubixCleaning.jsonConfig(config)
    }
  }
  private Dict point
  private Dict? config
  private EnerCubixStreamBudget budget
  private DateTime from
  private DateTime to
  private DateTime hour
  private DateTime observedEnd
  private DateTime cutoff
  private DateTime[] queryEnds
  private [Str:Obj?][] queries
  private EnerCubixContext ctx
  private [Str:Obj?]?[] tariffs
  private Bool cleaned
  private Str mode
  private Duration? inferredCadence
  private Bool inferredInterval := false
  private HisItem? previous
  private DateTime? last
  private HisItem[] raw := [,]
  private EnerCubixInterval[] intervals := [,]
  private [Str:Obj?][] diagnostics := [,]
  private Str:Obj? reads := [:]
  private Str:Obj? meta
  private Int eventCount := 0
  private Int filtered := 0
  private Int substituted := 0
  private Int naCount := 0
  private Int validTicks := 0
  private DateTime? lastObserved

  private Void block(DateTime a, DateTime b, |Dict,Span,|HisItem|->Void| read)
  {
    budget.check; budget.nativeReads++
    items:=HisItem[,]
    HisItem? leading:=null
    try
    {
      read(point,Span.makeAbs(a,b)) |HisItem item|
      {
        budget.scan
        // Leading/trailing native context is not owned by this block. Explicit
        // margins above provide context once, independent of SDK extra samples.
        if (item.ts < a) {if (last == null && (leading == null || item.ts > leading.ts)) leading=item;return}
        if (item.ts >= b) return
        if (items.size >= budget.blockLimit) throw EnerCubixStreamBlockErr()
        items.add(item); budget.hold(items.size+raw.size)
      }
      if (leading != null && last == null && items.size >= budget.blockLimit) throw EnerCubixStreamBlockErr()
    }
    catch (EnerCubixStreamBlockErr e)
    {
      items.clear
      ticks:=(b-a).ticks
      if (ticks <= 1ms.ticks) throw EnerCubixHttpErr(422,"HISTORY_DENSITY_LIMIT","cockpitHistoryDensityLimit")
      mid:=a+Duration(ticks/2)
      block(a,mid,read);block(mid,b,read);return
    }
    if (leading != null && last == null) items.insert(0,leading)
    // Native stored timestamps are unique. Keep the last repeated callback as
    // normalize does, and never accept a backwards cross-block source sequence.
    byTime:=Int:HisItem[:];items.each |item| {byTime[item.ts.ticks]=item}
    items=byTime.vals.sort |x,y| {x.ts <=> y.ts}
    budget.peakBlock=budget.peakBlock.max(items.size)
    if (!cleaned && mode == "interval" && !point.has("hisCollectInterval") && !point.has("hisInterval") && !items.isEmpty)
    {
      inferredCadence=EnerCubixHistory.cadence(point,items)
      if (inferredCadence == null) throw ArgErr("streamingCadenceRequired")
      point=Etc.makeDict(Etc.dictToMap(point).set("hisInterval",Number.makeDuration(inferredCadence)))
      inferredInterval=true
    }
    result:=cleaned ? EnerCubixCleaning.clean(point,items,config,previous,false,true) : null
    if (cleaned) previous=result.previous
    items.each |item,i|
    {
      if (last != null && item.ts <= last) throw ArgErr("nonMonotonicHistory")
      if (inferredInterval && last != null && (item.ts-last).ticks % inferredCadence.ticks != 0) throw ArgErr("streamingCadenceChanged")
      last=item.ts
      if (item.ts <= cutoff && item.ts <= observedEnd) lastObserved=item.ts.toTimeZone(from.tz)
      if (item.ts >= from && item.ts < to) increment("inputCount")
      if (!cleaned || raw.isEmpty || item.val !== NA.val || !config.has("removeNA")) raw.add(item)
      d:=result == null ? null : result.details[i]
      if (d != null)
      {
        observe(d,item.ts)
        seconds:=EnerCubixMath.num(d["intervalSeconds"]) ?: 0f
        if (d["emitted"] == true && seconds > 0f)
        {
          end:=item.ts.toTimeZone(from.tz)
          intervals.add(EnerCubixInterval(end-Duration((seconds*1sec.ticks.toFloat).toInt),end,EnerCubixMath.num(d["value"]),EnerCubixHistory.detailQuality(d),d["valueType"].toStr))
        }
      }
      budget.hold(items.size+raw.size)
      // Removed NA does not close an interval: wait for the next accepted reading.
      if (d != null && d["reason"] == "removedNA") return
      while (hour < to && item.ts >= hour+1hr) closeHour
    }
  }

  private Void increment(Str k) {meta[k]=((Int)meta[k])+1}

  private Void observe(Str:Obj? d, DateTime end)
  {
    seconds:=EnerCubixMath.num(d["intervalSeconds"]) ?: 0f
    start:=end-Duration((seconds*1sec.ticks.toFloat).toInt)
    selected:=d["emitted"] == true && end > from && start < to
    if (selected)
    {
      increment("outputCount")
      if (d["valueType"] == "number") increment("validCount")
      else if (d["valueType"] == "na") {increment("naCount");naCount++}
      else increment("nullCount")
      if (d["substituted"] == true) substituted++
      if (d["value"] == null && d["valueType"] != "na" && !["inputNull","previousNull","nonPositiveInterval"].contains(d["reason"])) filtered++
    }
    if (["ok","noPrevious"].contains(d["reason"]) || !(selected || (d["emitted"] != true && end >= from && end < to))) return
    eventCount++
    if (d["reason"] == "rollover") increment("rolloverCount")
    else if (d["emitted"] == true) increment("rejectedCount")
    if (d["reason"] == "removedNA") increment("removedNACount")
    if (d["substituted"] == true) increment("substitutedCount")
    if (diagnostics.size < 1000)
    {
      event:=EnerCubixHistory.nativeDetail(d).setAll(["pointId":point.id.id,"unit":point["unit"],"profileId":meta["profileId"],"profileVersion":meta["profileVersion"],"parameters":meta["parameters"]])
      reason:=d["reason"].toStr
      event["rule"]=reason == "rollover" || reason == "rolloverOutOfRange" ? "hisTotalizedRollover" : (["deltaMin","deltaMax","derivMin","derivMax","timeMax"].contains(reason) ? reason : null)
      diagnostics.add(event)
    }
  }

  private Void closeHour()
  {
    budget.check
    end:=hour+1hr
    EnerCubixHistoryData? history
    if (cleaned || mode == "cumulative")
    {
      history=EnerCubixHistoryData.window(point,cleaned ? "interval" : mode,raw,cleaned ? intervals : null,cutoff)
      if (cleaned) intervals.each |row|
      {
        if (row.start >= hour && row.end <= end && row.value != null && row.quality != "substituted" && row.quality != "filtered") validTicks+=(row.end-row.start).ticks
      }
    }
    else
    {
      normalized:=EnerCubixHistory.normalize(point,raw,hour,end,false,mode)
      if (inferredInterval) normalized["quality"]="estimated"
      history=EnerCubixHistoryData(EnerCubixKnownUsage.clip([normalized],cutoff).first)
    }
    pairs:=[Str:Obj?][["from":hour,"to":end]]
    queries.each |q|
    {
      a:=DateTime.fromIso(q["from"].toStr); b:=DateTime.fromIso(q["to"].toStr)
      if (a < hour) a=hour;if (b > end) b=end
      if (b > a) pairs.add(["from":a,"to":b])
    }
    pairs.dup.each |pair|
    {
      a:=(DateTime)pair["from"]; b:=(DateTime)pair["to"]
      tariffs.each |t|
      {
        bounds:=ctx.tariffBounds(t,a,b)
        for (i:=0;i<bounds.size-1;i++) pairs.add(["from":bounds[i],"to":bounds[i+1]])
      }
    }
    pairs.unique.each |pair|
    {
      a:=(DateTime)pair["from"]; b:=(DateTime)pair["to"]
      name:=key(a,b);if (reads.containsKey(name)) return
      budget.cell
      strict:=history.read(a,b)
      known:=Str:Obj?[:]
      queryEnds.each |qEnd|
      {
        row:=history.knownUsage(a,b,qEnd).dup;row.remove("value")
        // Diagnostics have a per-request limit, independent of arithmetic.
        events:=EnerCubixMath.maps(row["intervals"])
        keep:=events.size.min((1000-budget.detailCount).max(0))
        row["intervals"]=keep == 0 ? [Str:Obj?][,] : events[0..<keep]
        row["detailsTruncated"]=(EnerCubixMath.num(row["intervalCount"]) ?: 0f) > keep.toFloat
        budget.detailCount+=keep
        known[qEnd.ticks.toStr]=row
      }
      reads[name]=["strict":["value":strict.value,"quality":strict.quality],"known":known]
    }
    hour=end
    raw=raw.size > 2 ? raw[-2..-1] : raw
    intervals=intervals.findAll |row| {row.end > end}
  }

  private Str:Obj? finish()
  {
    while (hour < to) closeHour
    out:=Str:Obj?["pointId":point.id.id,"unit":point["unit"] ?: "","mode":cleaned ? "interval" : mode,"quality":cleaned ? "cleaned" : "ok","sourceIds":[point.id.id],"simulated":point.has("simulated"),"dataCutoff":cutoff.toIso,"_preparedReads":reads,"sourceLastObservedAt":lastObserved?.toIso]
    if (cleaned)
    {
      meta["details"]=diagnostics;meta["detailsTruncated"]=eventCount > diagnostics.size
      meta["summary"]=["filteredCount":filtered,"substitutedCount":substituted,"naCount":naCount,"intervalCount":meta["outputCount"],"coverage":validTicks.toFloat/(to-from).ticks.toFloat]
      out["cleaning"]=meta
    }
    return out
  }
}

internal const class EnerCubixStreamBlockErr : Err { new make() : super("block sample limit") {} }

** Shared across all points/ranges in a request. Exact limits accept equality.
internal class EnerCubixStreamBudget
{
  new make(Int blockLimit := 50000, Int heldLimit := 200000, Int scanLimit := 20000000, Duration timeout := 30sec)
  {this.blockLimit=blockLimit;this.heldLimit=heldLimit;this.scanLimit=scanLimit;this.timeout=timeout}
  Int blockLimit
  Int heldLimit
  Int scanLimit
  Duration timeout
  Int scanned := 0
  Int nativeReads := 0
  Int peakHeld := 0
  Int peakBlock := 0
  Int cells := 0
  Int detailCount := 0
  private Int started := Duration.nowTicks
  Void check() {if (Duration.nowTicks-started > timeout.ticks) throw EnerCubixHttpErr(504,"QUERY_TIMEOUT","cockpitQueryTimeout")}
  Void scan() {if (++scanned > scanLimit) throw EnerCubixHttpErr(422,"HISTORY_SCAN_LIMIT","cockpitHistoryScanLimit");if (scanned % 1024 == 0) check}
  Void hold(Int n) {peakHeld=peakHeld.max(n);if (n > heldLimit) throw EnerCubixHttpErr(422,"HISTORY_MEMORY_LIMIT","cockpitHistoryMemoryLimit")}
  Void cell() {if (++cells > 200000) throw EnerCubixHttpErr(422,"PREPARED_READ_LIMIT","cockpitPreparedReadLimit")}
  Str:Obj? evidence() {["nativeReadCount":nativeReads,"scannedSamples":scanned,"peakHeldRawSamples":peakHeld,"peakBlockSamples":peakBlock,"preparedReadCount":cells,"blockSampleLimit":blockLimit,"heldSampleLimit":heldLimit,"scanSampleLimit":scanLimit,"hardTimeoutSeconds":timeout.toSec,"elapsedMs":(Duration.nowTicks-started)/1ms.ticks,"softBudgetExceeded":Duration.nowTicks-started > 20sec.ticks]}
}

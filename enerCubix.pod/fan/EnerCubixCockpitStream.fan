using haystack
using skyarcd

** Cockpit-only bounded native scan. Exact source windows feed the existing strict
** and known-interval readers; no resampling, auxiliary source or history write.
internal class EnerCubixCockpitStream
{
  static Str key(DateTime a, DateTime b) { "${a.ticks}|${b.ticks}" }
  internal static Str diagnosticKey(Str id,DateTime from,DateTime to) {"cleaning|$id|${from.ticks}|${to.ticks}"}

  static [Str:Obj?][] load(Context cx, Str:Obj? request, [Str:Obj?][] records, Str:Dict? points, Str:Dict configs)
  {
    budget:=EnerCubixStreamBudget(50000,200000,20000000,30sec,request["_cockpitDeadline"] as EnerCubixCockpitDeadline)
    return prepare(request,records,points,configs,|Dict p,Span span,|HisItem| sink|
    {
      cx.rt.his.read(p,span,Etc.makeDict(["raw":Marker.val]),sink)
    },budget)
  }

  ** Callback seam uses the same block splitter as FIN; synthetic tests never write history.
  static [Str:Obj?][] prepare(Str:Obj? request, [Str:Obj?][] records, Str:Dict? points, Str:Dict configs,
    |Dict,Span,|HisItem|->Void| read, EnerCubixStreamBudget budget)
  {
    if(budget.diagnosticCapture!=null) throw ArgErr("diagnosticsRequireCursorFrames")
    if(budget.cursorActive) throw ArgErr("cursorBudgetAlreadyActive")
    out:=[Str:Obj?][,]
    ranges:=EnerCubixMath.maps(request["_cockpitRanges"])
    if (ranges.isEmpty) ranges=[request.dup.set("pointIds",points.keys)]
    budget.originalWindows=ranges.reduce(0) |Int n, r->Int| {n+EnerCubixMath.strings(r["pointIds"]).size}
    ranges=normalizeRanges(ranges)
    budget.normalizedWindows=ranges.reduce(0) |Int n, r->Int| {n+EnerCubixMath.strings(r["pointIds"]).size}
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
          budget.logicalHours+=(stream.to-stream.from).ticks/1hr.ticks
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
    out.each |h| {h["streaming"]=stats;h["_preparedBudget"]=budget.state}
    return out
  }

  ** Pausable producer seam. Concurrent tails share admission; report folding
  ** and prepared-frame ownership/release remain separate.
  internal static EnerCubixCockpitStream openCursor(Dict p,Dict? cfg,DateTime a,DateTime b,Str:Obj? q,[Str:Obj?][] records,EnerCubixStreamBudget budget,|Dict,Span,|HisItem|->Void| read,EnerCubixContext? planning := null)
  {
    if(planning != null && !planning.ownedCatalog(budget.state)) throw ArgErr("cursorPlanningOwner")
    tz:=TimeZone.fromStr(q["tz"] as Str ?: a.tz.name)
    // Without a shared owned catalog, admit a conservative bound for the
    // per-cursor byId/children indices before constructing their copies.
    charge:=planning == null ? 1+3*records.size : 0
    budget.state.holdOwned(charge)
    EnerCubixCockpitStream? stream
    try
    {
      stream=EnerCubixCockpitStream(p,cfg,a.toTimeZone(tz),b.toTimeZone(tz),q,records,budget,planning)
      stream.cursorCatalogCharge=charge
      stream.cursorMode=true;stream.cursorReader=read
      pointTz:=TimeZone.fromStr(p["tz"] as Str ?: tz.name)
      stream.cursorReadAt=(stream.from-1day).toTimeZone(pointTz)
      stream.cursorReadEnd=(stream.to+1day).toTimeZone(pointTz)
      budget.openCursor(stream.cursorId)
      budget.logicalHours+=(stream.to-stream.from).ticks/1hr.ticks
      return (EnerCubixCockpitStream)stream
    }
    catch(Err e)
    {
      if(stream != null) {stream.ctx=null;stream.cursorReader=null}
      budget.state.releaseTemporary(charge);throw e
    }
  }

  ** All readers stay borrowed while report leaves consume the same watermark.
  ** Context roots drop before unwinding any producer's prepared-frame release.
  internal static Void withFrames(EnerCubixCockpitStream[] streams,EnerCubixPreparedBudget budget,|Str:EnerCubixHistoryData,EnerCubixPreparedOwner| consume)
  {
    owner:=EnerCubixPreparedOwner(budget);histories:=Str:EnerCubixHistoryData[:];ids:=Str:Bool[:]
    |Int->Void|? visit
    try
    {
      owner.watch |->Void| {histories.clear;ids.clear}
      // Both indices, five legacy reader-wrapper cells, frame and registration.
      owner.hold(5+10*streams.size)
      DateTime? start;DateTime? end
      streams.each |stream|
      {
        if(stream.budget.state !== budget || ids.containsKey(stream.point.id.id)) throw ArgErr("cursorGroupOwnership")
        stream.frameCheck
        at:=stream.cursorConsumed ?: stream.from
        if(end != null && (at != start || stream.watermark != end)) throw ArgErr("cursorGroupWatermark")
        start=at;end=stream.watermark;ids[stream.point.id.id]=true
      }
      visit=|Int i|
      {
        if(i == streams.size)
        {
          try {consume(histories,owner)} finally {owner.close}
          return
        }
        streams[i].withFrame |h| {histories[h.id]=h;visit(i+1)}
      }
      visit(0)
    }
    finally {owner.close;visit=null}
  }

  internal Void advance(DateTime through)
  {
    cursorCheck
    if(cursorFrameActive) throw ArgErr("cursorFrameActive")
    if(through < watermark || through > to || (through != to && (through-from).ticks % 1hr.ticks != 0)) throw ArgErr("cursorWatermark")
    try
    {
      while(hour < through)
      {
        budget.check;flushCursor(through)
        if(hour >= through) break
        if(cursorIndex < cursorItems.size)
        {
          i:=cursorIndex++;item:=cursorItems[i];detail:=cursorDetails.isEmpty ? null : cursorDetails[i]
          append(item,detail,through,cursorItems.size-i)
          cursorItems[i]=null
          if(!cursorDetails.isEmpty) {cursorDetails[i]=null;detail=null;budget.state.releaseTemporary(1);cursorDetailCharge--}
          continue
        }
        clearCursorChunk
        if(!nextCursorChunk)
        {cursorEof=true;tailThrough(through);break}
      }
      if(cursorIndex >= cursorItems.size)
      {
        clearCursorChunk
        if(cursorSpans.isEmpty && cursorReadAt >= cursorReadEnd) cursorEof=true
      }
    }
    catch(Err e) {cursorFailure=e;throw e}
  }

  internal DateTime watermark() {hour < to ? hour : to}
  internal Bool scanComplete() {cursorEof && cursorFailure == null}
  ** Borrowed data must be consumed before returning. Retained reductions and
  ** copied diagnostic evidence belong to the consumer's separately charged state.
  internal Void withFrame(|EnerCubixHistoryData| consume)
  {
    frameCheck
    cursorFramed=true;cursorFrameActive=true;frame:=EnerCubixPreparedFrame()
    try
    {
      budget.check
      consume(EnerCubixHistoryData(capture.set("_preparedFrame",frame)))
      budget.check
    }
    catch(Err e) {cursorFailure=e;throw e}
    finally
    {
      frame.expire;clearPrepared;cursorConsumed=watermark;cursorFrameActive=false
    }
  }
  ** Borrowed prefix view, not a frozen application snapshot or an eviction API.
  internal Str:Obj? view()
  {
    cursorCheck
    if(cursorFramed) throw ArgErr("cursorFrameMode")
    cursorEscaped=true
    out:=capture;out["streaming"]=budget.evidence
    return out
  }
  ** Final scalar provenance for a fully consumed cursor. Unlike view(), this
  ** cannot escape prepared cells or revive a borrowed/expired source frame.
  ** The callback must detach what it retains before this header is cleared.
  internal Void withHeaderMetadata(|Str:Obj?| consume)
  {
    cursorCheck
    if(cursorFrameActive || !cursorFramed || cursorConsumed!=to) throw ArgErr("sourceHeaderNotReady")
    scratch:=EnerCubixPreparedOwner(budget.state)
    try
    {
      scratch.hold(32)
      ids:=[point.id.id]
      header:=Str:Obj?["pointId":point.id.id,"unit":point["unit"] ?: "","mode":cleaned ? "interval" : mode,"quality":cleaned ? "cleaned" : "ok","sourceIds":ids,"simulated":point.has("simulated"),"dataCutoff":cutoff.toIso,"sourceLastObservedAt":lastObserved?.toIso]
      try {consume(header)} finally {header.clear;ids.clear}
    }
    finally {scratch.close}
  }
  internal Void close()
  {
    if(!cursorMode || cursorClosed) return
    if(cursorFrameActive) throw ArgErr("cursorFrameActive")
    clearCursorChunk;raw.clear;intervals.clear;cursorReader=null;previous=null
    if(cursorIntervalCharge > 0) {budget.state.releaseTemporary(cursorIntervalCharge);cursorIntervalCharge=0}
    if(!cursorEscaped) clearPrepared
    ctx=null
    if(cursorCatalogCharge > 0) {budget.state.releaseTemporary(cursorCatalogCharge);cursorCatalogCharge=0}
    budget.closeCursor(cursorId);cursorClosed=true
    // Escaped prefix cells remain owned/charged; only private frames can expire.
  }
  private Void clearPrepared()
  {
    reads.clear;emptyDomains.clear
    if(cursorPreparedCharge > 0) {budget.state.releasePrepared(cursorPreparedCharge);cursorPreparedCharge=0}
  }
  private Void preparedCell(Int n)
  {
    if(cursorMode) budget.state.reserveOwned(n)
    else budget.cell(n)
    if(cursorMode) cursorPreparedCharge+=n
  }
  private Void cursorCheck()
  {
    if(!cursorMode || cursorClosed) throw ArgErr("cursorClosed")
    if(cursorFailure != null) throw cursorFailure
  }
  private Void frameCheck()
  {
    cursorCheck
    if(cursorEscaped || cursorFrameActive || watermark <= (cursorConsumed ?: from)) throw ArgErr("cursorFrameMode")
  }
  private Void clearCursorChunk()
  {
    cursorItems.clear;cursorDetails.clear;cursorIndex=0
    if(cursorDetailCharge > 0) {budget.state.releaseTemporary(cursorDetailCharge);cursorDetailCharge=0}
    budget.holdCursor(cursorId,raw.size+(previous == null ? 0 : 1))
  }
  private Bool nextCursorChunk()
  {
    while(true)
    {
      budget.check
      Span? span
      if(!cursorSpans.isEmpty) span=cursorSpans.removeAt(0)
      else
      {
        if(cursorReadAt >= cursorReadEnd) return false
        end:=cursorReadAt+4day;if(end > cursorReadEnd) end=cursorReadEnd
        span=Span.makeAbs(cursorReadAt,end);cursorReadAt=end
      }
      items:=HisItem[,]
      try {items=readBlock(span.start,span.end,cursorReader)}
      catch(EnerCubixStreamBlockErr e)
      {
        ticks:=(span.end-span.start).ticks
        if(ticks <= 1ms.ticks) throw EnerCubixHttpErr(422,"HISTORY_DENSITY_LIMIT","cockpitHistoryDensityLimit")
        mid:=span.start+Duration(ticks/2)
        cursorSpans.insert(0,Span.makeAbs(mid,span.end));cursorSpans.insert(0,Span.makeAbs(span.start,mid));continue
      }
      if(items.isEmpty) continue
      charge:=cleaned ? 2*items.size : 0
      if(charge > 0) budget.state.holdOwned(charge)
      EnerCubixCleanResult? result
      try
      {
        result=cleaned ? EnerCubixCleaning.clean(point,items,config,previous,false,true) : null
        cursorItems=items.map |item->HisItem?| {item}
        if(result != null)
        {
          previous=result.previous;result.previous=null
          cursorDetails=result.details.map |d->[Str:Obj?]?| {d}
          result.details.clear;result.items.clear
          cursorDetailCharge=cursorDetails.size
        }
        items.clear
        if(charge > cursorDetailCharge) budget.state.releaseTemporary(charge-cursorDetailCharge)
        budget.holdCursor(cursorId,cursorItems.size+raw.size+(previous == null ? 0 : 1))
        return true
      }
      catch(Err e)
      {
        items.clear;cursorItems.clear;cursorDetails.clear
        result?.details?.clear;result?.items?.clear;result=null
        if(charge > 0) budget.state.releaseTemporary(charge)
        cursorDetailCharge=0;throw e
      }
    }
    return false
  }
  private Void flushCursor(DateTime limit)
  {
    if(cursorClosable == null) return
    if(raw.size == 1 && intervals.isEmpty && raw.first.ts > hour)
    {
      end:=EnerCubixMath.floorHour(raw.first.ts)
      if(end > limit) end=limit
      if(end > to) end=to
      emptyUntil(end)
    }
    while(hour < limit && cursorClosable >= hour+1hr) closeHour
  }
  private Void tailThrough(DateTime limit)
  {
    while(hour < limit)
    {
      budget.check
      if((raw.isEmpty || raw.last.ts <= hour) && intervals.all |row| {row.end <= hour}) emptyUntil(limit)
      else closeHour
    }
  }

  ** Union only intersecting/adjacent windows of the same source, before scanning.
  internal static [Str:Obj?][] normalizeRanges([Str:Obj?][] ranges)
  {
    byPoint:=Str:[Str:Obj?][][:]
    ranges.each |r| {EnerCubixMath.strings(r["pointIds"]).each |p| {if(!byPoint.containsKey(p)) byPoint[p]=[,];byPoint[p].add(r)}}
    windows:=[Str:Obj?][,]
    byPoint.keys.sort.each |p|
    {
      own:=[Str:Obj?][,]
      byPoint[p].sort |a,b| {DateTime.fromIso(a["from"].toStr) <=> DateTime.fromIso(b["from"].toStr)}.each |r|
      {
        last:=own.last
        if(last != null && DateTime.fromIso(r["from"].toStr) <= DateTime.fromIso(last["to"].toStr))
        {if(DateTime.fromIso(r["to"].toStr) > DateTime.fromIso(last["to"].toStr)) last["to"]=r["to"]}
        else own.add(["from":r["from"],"to":r["to"],"pointIds":[p]])
      }
      windows.addAll(own)
    }
    out:=[Str:Obj?][,]
    windows.each |r|
    {
      same:=out.find |x| {DateTime.fromIso(x["from"].toStr) == DateTime.fromIso(r["from"].toStr) && DateTime.fromIso(x["to"].toStr) == DateTime.fromIso(r["to"].toStr)}
      if(same == null) out.add(r)
      else same["pointIds"]=EnerCubixMath.strings(same["pointIds"]).addAll(EnerCubixMath.strings(r["pointIds"]))
    }
    return out
  }

  private new make(Dict point, Dict? config, DateTime from, DateTime to, Str:Obj? request,
    [Str:Obj?][] records, EnerCubixStreamBudget budget,EnerCubixContext? planning := null)
  {
    this.point=point; this.config=config;this.budget=budget
    observedEnd=to
    ruleEnd=request["_cockpitNeedsRuleFacts"] == true ? DateTime.fromIso(request["to"].toStr) : null
    this.from=EnerCubixMath.floorHour(from)
    this.to=EnerCubixMath.floorHour(to);if (this.to < to) this.to+=1hr
    hour=this.from
    cutoff=DateTime.fromIso(request["asOf"]?.toStr ?: to.toIso).toTimeZone(from.tz)
    queries=EnerCubixMath.maps(request["_cockpitReadRanges"])
    if (queries.isEmpty) queries=[request]
    queries=queries.map |q->[Str:Obj?]| {["from":q["from"],"to":q["to"]]}
    queryEnds=queries.map |q->DateTime| {end:=DateTime.fromIso(q["to"].toStr);return end < cutoff ? end : cutoff}.unique
    cleaned=point["hisFunc"] == "enerCubixCleanHis" && request["raw"] != true
    if (cleaned && (config == null || config.isEmpty)) throw ArgErr("missingCleaningProfile")
    if(budget.diagnosticCapture!=null)
    {
      if(budget.diagnosticCapture.budget!==budget.state) throw ArgErr("sourceDiagnosticBudget")
      if(cleaned) {diagnosticGroup=diagnosticKey(point.id.id,this.from,this.to);budget.diagnosticCapture.expect(diagnosticGroup,"cleaningEvents")}
    }
    modes:=records.findAll |r| {r["pointId"] == point.id.id && r["historyMode"] != null && r["historyMode"] != "auto"}.map |r->Str| {r["historyMode"].toStr}.unique
    if (modes.size > 1) throw ArgErr("Conflicting EnerCubix history modes")
    mode=modes.first ?: (point.has("hisTotalized") ? "cumulative" : (point["hisMode"]?.toStr == "consumption" ? "interval" : (point["hisMode"]?.toStr ?: "sampled")))
    if (!cleaned && mode != "cumulative" && mode != "interval") throw ArgErr("streamingEnergyModeRequired")
    ctx=planning ?: EnerCubixContext(records,[Str:Obj?][,],from.tz)
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
  private DateTime? ruleEnd
  private DateTime cutoff
  private DateTime[] queryEnds
  private [Str:Obj?][] queries
  private EnerCubixContext? ctx
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
  private Str? diagnosticGroup
  private Str:Obj? reads := [:]
  private [Str:Obj?][] emptyDomains := [,]
  private Str:Obj? meta
  private Int eventCount := 0
  private Int filtered := 0
  private Int substituted := 0
  private Int naCount := 0
  private Int validTicks := 0
  private DateTime? lastObserved
  private Bool cursorMode := false
  private Str cursorId := Uuid().toStr
  private Bool cursorClosed := false
  private Bool cursorEof := false
  private Bool cursorEscaped := false
  private Bool cursorFramed := false
  private Bool cursorFrameActive := false
  private DateTime? cursorConsumed
  private Int cursorPreparedCharge := 0
  private Int cursorCatalogCharge := 0
  private Err? cursorFailure
  private |Dict,Span,|HisItem|->Void|? cursorReader
  private DateTime? cursorReadAt
  private DateTime? cursorReadEnd
  private DateTime? cursorClosable
  private Span[] cursorSpans := [,]
  private HisItem?[] cursorItems := [,]
  private [Str:Obj?]?[] cursorDetails := [,]
  private Int cursorIndex := 0
  private Int cursorDetailCharge := 0
  private Int cursorIntervalCharge := 0
  private Bool captured := false

  private Void block(DateTime a,DateTime b,|Dict,Span,|HisItem|->Void| read)
  {
    items:=HisItem[,]
    try {items=readBlock(a,b,read)}
    catch(EnerCubixStreamBlockErr e)
    {
      ticks:=(b-a).ticks
      if(ticks <= 1ms.ticks) throw EnerCubixHttpErr(422,"HISTORY_DENSITY_LIMIT","cockpitHistoryDensityLimit")
      mid:=a+Duration(ticks/2);block(a,mid,read);block(mid,b,read);return
    }
    result:=cleaned ? EnerCubixCleaning.clean(point,items,config,previous,false,true) : null
    if(cleaned) previous=result.previous
    items.each |item,i| {append(item,result == null ? null : result.details[i],to,items.size)}
  }

  private HisItem[] readBlock(DateTime a,DateTime b,|Dict,Span,|HisItem|->Void| read)
  {
    budget.check;budget.nativeReads++
    items:=HisItem[,];HisItem? leading:=null;cap:=budget.blockLimit
    if(cursorMode)
    {
      rawRoom:=((budget.rawRoom(cursorId)-raw.size-(previous == null ? 0 : 1))/3).max(0)
      if(rawRoom == 0) throw EnerCubixHttpErr(422,"HISTORY_MEMORY_LIMIT","cockpitHistoryMemoryLimit")
      cap=cap.min(rawRoom).min(budget.heldLimit/(budget.activeCursors*3))
      if(cap == 0) throw EnerCubixHttpErr(422,"HISTORY_MEMORY_LIMIT","cockpitHistoryMemoryLimit")
      if(cleaned)
      {
        prepRoom:=budget.state.remaining/2
        if(prepRoom == 0) throw EnerCubixHttpErr(422,"PREPARED_READ_LIMIT","cockpitPreparedReadLimit")
        cap=cap.min(prepRoom).min(200000/(budget.activeCursors*2))
        if(cap == 0) throw EnerCubixHttpErr(422,"PREPARED_READ_LIMIT","cockpitPreparedReadLimit")
      }
    }
    try
    {
      read(point,Span.makeAbs(a,b)) |HisItem item|
      {
        budget.scan
        if(item.ts < a) {if(last == null && (leading == null || item.ts > leading.ts)) leading=item;return}
        if(item.ts >= b) return
        if(items.size >= cap) throw EnerCubixStreamBlockErr()
        items.add(item)
        if(cursorMode) budget.holdCursor(cursorId,3*items.size+raw.size+(previous == null ? 0 : 1))
        else budget.hold(items.size+raw.size)
      }
      if(leading != null && last == null && items.size >= cap) throw EnerCubixStreamBlockErr()
    }
    catch(Err e)
    {
      items.clear;leading=null
      if(cursorMode) budget.holdCursor(cursorId,raw.size+(previous == null ? 0 : 1))
      throw e
    }
    if(leading != null && last == null) items.insert(0,leading)
    byTime:=Int:HisItem[:];items.each |item| {byTime[item.ts.ticks]=item}
    items=byTime.vals.sort |x,y| {x.ts <=> y.ts}
    if(cursorMode) budget.holdCursor(cursorId,3*items.size+raw.size+(previous == null ? 0 : 1))
    budget.peakBlock=budget.peakBlock.max(items.size)
    if(!cleaned && mode == "interval" && !point.has("hisCollectInterval") && !point.has("hisInterval") && !items.isEmpty)
    {
      inferredCadence=EnerCubixHistory.cadence(point,items)
      if(inferredCadence == null) throw ArgErr("streamingCadenceRequired")
      point=Etc.makeDict(Etc.dictToMap(point).set("hisInterval",Number.makeDuration(inferredCadence)))
      inferredInterval=true
    }
    return items
  }

  private Void append(HisItem item,Map? d,DateTime limit,Int heldItems)
  {
    if(last != null && item.ts <= last) throw ArgErr("nonMonotonicHistory")
    if(inferredInterval && last != null && (item.ts-last).ticks % inferredCadence.ticks != 0) throw ArgErr("streamingCadenceChanged")
    last=item.ts
    if(item.ts <= cutoff && item.ts <= observedEnd) lastObserved=item.ts.toTimeZone(from.tz)
    if(item.ts >= from && item.ts < to) increment("inputCount")
    if(!cleaned || raw.isEmpty || item.val !== NA.val || !config.has("removeNA")) raw.add(item)
    if(d != null)
    {
      observe(d,item.ts)
      seconds:=EnerCubixMath.num(d["intervalSeconds"]) ?: 0f
      if(d["emitted"] == true && seconds > 0f)
      {
        end:=item.ts.toTimeZone(from.tz)
        if(cursorMode) {budget.state.holdOwned(1);cursorIntervalCharge++}
        intervals.add(EnerCubixInterval(end-Duration((seconds*1sec.ticks.toFloat).toInt),end,EnerCubixMath.num(d["value"]),EnerCubixHistory.detailQuality(d),d["valueType"].toStr))
      }
    }
    if(cursorMode) budget.holdCursor(cursorId,heldItems+raw.size+(previous == null ? 0 : 1))
    else budget.hold(heldItems+raw.size)
    if(d != null && d["reason"] == "removedNA") return
    cursorClosable=item.ts
    firstHour:=EnerCubixMath.floorHour(item.ts)
    if(firstHour > limit) firstHour=limit
    if(raw.size == 1 && intervals.isEmpty && hour < firstHour) emptyUntil(firstHour < to ? firstHour : to)
    while(hour < limit && item.ts >= hour+1hr) closeHour
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
    capture:=cursorMode ? budget.diagnosticCapture : null
    if(capture!=null && !capture.canPutSimple(diagnosticGroup)) {capture.skipSimple(diagnosticGroup);return}
    if (capture!=null || diagnostics.size < 1000)
    {
      scratch:=capture==null ? null : EnerCubixPreparedOwner(budget.state)
      try
      {
      scratch?.hold(32+2*d.size)
      event:=EnerCubixHistory.nativeDetail(d).setAll(["pointId":point.id.id,"unit":point["unit"],"profileId":meta["profileId"],"profileVersion":meta["profileVersion"],"parameters":meta["parameters"]])
      reason:=d["reason"].toStr
      event["rule"]=reason == "rollover" || reason == "rolloverOutOfRange" ? "hisTotalizedRollover" : (["deltaMin","deltaMax","derivMin","derivMax","timeMax"].contains(reason) ? reason : null)
      if(capture!=null) capture.put(diagnosticGroup,event)
      else {if(cursorMode) budget.state.reserveOwned(1);diagnostics.add(event)}
      }
      finally {scratch?.close}
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
    pairs:=pairs(hour,queries,tariffs,(EnerCubixContext)ctx)
    values:=Str:Obj?[:]
    pairs.each |pair|
    {
      a:=(DateTime)pair["from"]; b:=(DateTime)pair["to"]
      name:=key(a,b);if (reads.containsKey(name)) return
      strict:=history.read(a,b)
      known:=Str:Obj?[:]
      queryEnds.each |qEnd|
      {
        row:=history.knownUsage(a,b,qEnd,ruleEnd == qEnd).dup;row.remove("value")
        events:=EnerCubixMath.maps(row["intervals"])
        keep:=events.size.min((1000-budget.detailCount).max(0))
        row["intervals"]=keep == 0 ? [Str:Obj?][,] : events[0..<keep]
        row["detailsTruncated"]=(EnerCubixMath.num(row["intervalCount"]) ?: 0f) > keep.toFloat
        if(row["detailsTruncated"] == true) row["intervalsCaptureId"]=Uuid().toStr
        else row.remove("_closedOwnPrimaryHour") // Complete diagnostics already prove the predicate.
        budget.detailCount+=keep
        known[qEnd.ticks.toStr]=row
      }
      values[name]=["strict":["value":strict.value,"quality":strict.quality],"known":known]
    }
    // A closed interval crossing an hour can have no attributed usage there.
    // Keep its strict incompleteInterval state distinct from missing history.
    qualities:=values.vals.map |v->Str| {((Map)((Map)v)["strict"])["quality"].toStr}.unique
    if(qualities.size == 1 && values.vals.all |v| {emptyPair((Map)v)}) emptyUntil(end,qualities.first)
    else values.each |v,k|
    {
      facts:=((Map)((Map)v)["known"]).vals.findAll |r| {((Map)r)["_closedOwnPrimaryHour"] == true}.size
      preparedCell(2+queryEnds.size+facts);budget.materializedPairs++;reads[k]=v
    }
    hour=end
    raw=raw.size > 2 ? raw[-2..-1] : raw
    oldIntervals:=intervals.size
    intervals=intervals.findAll |row| {row.end > end}
    if(cursorMode && intervals.size < oldIntervals)
    {released:=oldIntervals-intervals.size;budget.state.releaseTemporary(released);cursorIntervalCharge-=released}
  }

  internal static [Str:Obj?][] pairs(DateTime hour, [Str:Obj?][] queries, [Str:Obj?]?[] tariffs, EnerCubixContext ctx)
  {
    end:=hour+1hr
    pairs:=[Str:Obj?][["from":hour,"to":end]]
    queries.each |q|
    {
      a:=DateTime.fromIso(q["from"].toStr); b:=DateTime.fromIso(q["to"].toStr)
      if (a < hour) a=hour;if (b > end) b=end
      if (b > a)
      {
        pairs.add(["from":a,"to":b])
        // Tier pricing also consumes the preceding part of this first hour.
        // The native cycle range already includes it; prepare its exact pair.
        if(a > hour && tariffs.any |t| {["monthlyBlock","yearlyBlock"].contains(t?.get("mode") as Str ?: "")})
          pairs.add(["from":hour,"to":a])
      }
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
    return pairs.unique
  }

  private static Bool emptyPair(Map pair)
  {
    strict:=(Map)pair["strict"]
    return strict["value"] == null && ["missing","incompleteInterval"].contains(strict["quality"]) && ((Map)pair["known"]).vals.all |v|
    {
      r:=(Map)v
      return r["knownValue"] == null && r["knownValueType"] == "null" && r["knownQuality"] == "missing" && r["coveredSeconds"] == 0f && r["intervalCount"] == 0 && r["intervalStart"] == null && r["intervalEnd"] == null && EnerCubixMath.maps(r["intervals"]).isEmpty && r["detailsTruncated"] == false
    }
  }

  private Void emptyUntil(DateTime end, Str strictQuality := "missing")
  {
    if(end <= hour) return
    last:=emptyDomains.last
    if(last != null && last["to"] == hour && (last["strictQuality"] ?: "missing") == strictQuality) last["to"]=end
    else
    {
      domain:=Str:Obj?["from":hour,"to":end]
      if(strictQuality != "missing") domain["strictQuality"]=strictQuality
      preparedCell(domain.size);budget.sparseDomains++;emptyDomains.add(domain)
    }
    hour=end
  }

  private Str:Obj? finish()
  {
    tailThrough(to)
    return capture
  }

  private Str:Obj? capture()
  {
    if(!captured)
    {
      n:=4+queries.size+queryEnds.size+tariffs.size
      if(cursorMode) budget.state.reserveOwned(n)
      else budget.cell(n)
      captured=true
    }
    out:=Str:Obj?["pointId":point.id.id,"unit":point["unit"] ?: "","mode":cleaned ? "interval" : mode,"quality":cleaned ? "cleaned" : "ok","sourceIds":[point.id.id],"simulated":point.has("simulated"),"dataCutoff":cutoff.toIso,"_preparedReads":reads,"_preparedSparse":["version":1,"from":from,"to":to,"domains":emptyDomains,"queries":queries,"queryEnds":queryEnds,"tariffs":tariffs,"tz":from.tz.name],"_preparedBudget":budget.state,"sourceLastObservedAt":lastObserved?.toIso]
    if (cleaned)
    {
      refreshCleaningMeta
      out["cleaning"]=meta
    }
    return out
  }
  ** Borrowed counters/configuration only. Call after the global pool freezes to
  ** read final truncation flags; retaining a snapshot requires caller ownership.
  internal Void withCleaningMetadata(|Str:Obj?| consume)
  {
    if(!cursorMode || cursorFrameActive || !cleaned) throw ArgErr("sourceCleaningMetadata")
    refreshCleaningMeta;consume(meta)
  }
  private Void refreshCleaningMeta()
  {
    capture:=cursorMode ? budget.diagnosticCapture : null
    details:=capture==null ? diagnostics : capture.rows(diagnosticGroup)
    meta["details"]=details;meta["detailsTruncated"]=eventCount>details.size
    if(capture!=null && eventCount>details.size) {meta["detailsCaptureId"]=capture.captureId(diagnosticGroup);meta["detailsTruncationReason"]="snapshotDiagnosticBudget"}
    meta["summary"]=["filteredCount":filtered,"substitutedCount":substituted,"naCount":naCount,"intervalCount":meta["outputCount"],"coverage":validTicks.toFloat/(to-from).ticks.toFloat]
  }
}

internal const class EnerCubixStreamBlockErr : Err { new make() : super("block sample limit") {} }

** Shared across all points/ranges in a request. Exact limits accept equality.
internal class EnerCubixStreamBudget
{
  new make(Int blockLimit := 50000, Int heldLimit := 200000, Int scanLimit := 20000000, Duration timeout := 30sec, EnerCubixCockpitDeadline? deadline := null)
  {this.blockLimit=blockLimit;this.heldLimit=heldLimit;this.scanLimit=scanLimit;this.timeout=timeout;state=EnerCubixPreparedBudget(deadline ?: EnerCubixCockpitDeadline(timeout))}
  EnerCubixPreparedBudget state
  EnerCubixCockpitCapture? diagnosticCapture
  Int blockLimit
  Int heldLimit
  Int scanLimit
  Duration timeout
  Int scanned := 0
  Int nativeReads := 0
  Int peakHeld := 0
  Int peakBlock := 0
  Int cells {get {state.prepared.val} set {state.prepared.val=it}}
  Int materializedPairs := 0
  Int sparseDomains := 0
  Int logicalHours := 0
  Int originalWindows := 0
  Int normalizedWindows := 0
  Int detailCount := 0
  private Str:Int cursorRaw := [:]
  private Int cursorRawTotal := 0
  Bool cursorActive() {!cursorRaw.isEmpty}
  Int activeCursors() {cursorRaw.size}
  Int residentRaw() {cursorRawTotal}
  Int rawRoom(Str owner) {heldLimit-residentRaw+(cursorRaw[owner] ?: 0)}
  Void openCursor(Str owner)
  {
    if(cursorRaw.containsKey(owner)) throw ArgErr("cursorOwnership")
    cursorRaw[owner]=0
  }
  Void holdCursor(Str owner,Int n)
  {
    old:=cursorRaw[owner]
    if(old == null || n < 0) throw ArgErr("cursorOwnership")
    total:=cursorRawTotal-old+n
    hold(total)
    cursorRaw[owner]=n;cursorRawTotal=total
  }
  Void closeCursor(Str owner)
  {
    if(!cursorRaw.containsKey(owner)) throw ArgErr("cursorOwnership")
    cursorRawTotal-=cursorRaw.remove(owner)
  }
  private Int started := Duration.nowTicks
  Void check() {state.deadline.check}
  Void scan() {if (++scanned > scanLimit) throw EnerCubixHttpErr(422,"HISTORY_SCAN_LIMIT","cockpitHistoryScanLimit");if (scanned % 1024 == 0) check}
  Void hold(Int n) {peakHeld=peakHeld.max(n);if (n > heldLimit) throw EnerCubixHttpErr(422,"HISTORY_MEMORY_LIMIT","cockpitHistoryMemoryLimit")}
  Void cell(Int n := 1) {state.reserve(n)}
  Str:Obj? evidence() {["representationVersion":2,"originalPointWindows":originalWindows,"normalizedPointWindows":normalizedWindows,"logicalHourPairCount":logicalHours,"materializedPairCount":materializedPairs,"sparseDomainCount":sparseDomains,"nativeReadCount":nativeReads,"scannedSamples":scanned,"peakHeldRawSamples":peakHeld,"peakBlockSamples":peakBlock,"preparedReadCount":cells,"peakPreparedEntries":state.peak.val,"blockSampleLimit":blockLimit,"heldSampleLimit":heldLimit,"scanSampleLimit":scanLimit,"hardTimeoutSeconds":timeout.toSec,"elapsedMs":(Duration.nowTicks-started)/1ms.ticks,"softBudgetExceeded":Duration.nowTicks-started > 20sec.ticks]}
}

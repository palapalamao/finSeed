using haystack
using skyarcd

** Cockpit-only bounded native scan. Exact source windows feed the existing strict
** and known-interval readers; no resampling, auxiliary source or history write.
internal class EnerCubixCockpitStream
{
  static Str key(DateTime a, DateTime b) { "${a.ticks}|${b.ticks}" }
  internal static Str diagnosticKey(Str id,DateTime from,DateTime to) {"cleaning|$id|${from.ticks}|${to.ticks}"}

  static [Str:Obj?][] load(Context cx, Str:Obj? request, [Str:Obj?][] records, Str:Dict? points, Str:Dict configs,EnerCubixStreamBudget? shared := null)
  {
    budget:=shared ?: EnerCubixStreamBudget(50000,200000,20000000,30sec,request["_cockpitDeadline"] as EnerCubixCockpitDeadline)
    if(request["_cockpitDeadline"]!=null && request["_cockpitDeadline"]!==budget.state.deadline) throw ArgErr("cockpitSourceSessionDeadline")
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
    charge:=5+(planning == null ? 1+3*records.size : 0)
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
  {withFrameIndex(streams,budget,true,consume)}

  ** A producer that still needs to append unavailable readers retains the
  ** mutable legacy seam. It cannot publish an attested shared index yet.
  internal static Void withMutableFrames(EnerCubixCockpitStream[] streams,EnerCubixPreparedBudget budget,|Str:EnerCubixHistoryData,EnerCubixPreparedOwner| consume)
  {withFrameIndex(streams,budget,false,consume)}

  private static Void withFrameIndex(EnerCubixCockpitStream[] streams,EnerCubixPreparedBudget budget,Bool shareIndex,|Str:EnerCubixHistoryData,EnerCubixPreparedOwner| consume)
  {
    owner:=EnerCubixPreparedOwner(budget);[Str:EnerCubixHistoryData]? histories:=[:];ids:=Str:Bool[:]
    |Int->Void|? visit
    try
    {
      owner.watch |->Void| {histories?.clear;histories=null;ids.clear}
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
      EnerCubixSourceBounds? bounds
      if(start!=null) {owner.hold(6);bounds=EnerCubixSourceBounds(start,end)}
      visit=|Int i|
      {
        if(i == streams.size)
        {
          if(!shareIndex)
          {
            try {consume(histories,owner)} finally {owner.close}
            return
          }
          // One shallow read-only index header shares the producer-owned
          // entries. All consumers finish before this source owner expires.
          owner.hold(1)
          [Str:EnerCubixHistoryData]? index:=histories.ro
          // Dropping the mutable alias avoids Map.ro's implicit N-entry clone
          // on clear(). This must precede every possibly failing registration.
          histories=null
          try {index.each |h| {h.bindSourceIndex(index,owner)};consume(index,owner)}
          finally {index=null;owner.close}
          return
        }
        streams[i].withFrame |h| {h.bindOwnEmptyFrame(owner,(DateTime)start,(DateTime)end,bounds);histories[h.id]=h;visit(i+1)}
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
          i:=cursorIndex++;item:=cursorItems[i]
          scratch:=cleaned ? EnerCubixPreparedOwner(budget.state) : null
          EnerCubixCleanStep? detail
          try
          {
            if(cleaned)
            {
              if(cursorValidatedConfig==null)
              {
                // The immutable normalized configuration belongs to this cursor;
                // admit its fields/copy workspace before validation/allocation.
                n:=16;config.each |v,k| {n+=5};budget.state.holdOwned(n);cursorCatalogCharge+=n
                cursorValidatedConfig=EnerCubixCleaning.cursorConfig(point,config)
              }
              scratch.hold(32)
              detail=EnerCubixCleaning.cursorStep(point["unit"]?.toStr ?: "",cursorValidatedConfig,item,previous)
              if(detail.reason!="removedNA") previous=item
            }
            append(item,detail,through,cursorItems.size-i)
            cursorItems[i]=null
          }
          finally {detail=null;scratch?.close}
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
  ** Only actual cursor contents prove this empty prefix; never hisStart tags.
  internal DateTime? confirmedEmptyThrough()
  {
    cursorCheck
    if(cursorFrameActive || !intervals.isEmpty) return null
    // The native read plan is exhausted. The same condition used by
    // tailThrough proves the remaining suffix missing even with old boundary
    // readings retained; no unread future row or interval is inferred away.
    if(cursorEof && (raw.isEmpty || raw.last.ts<=hour))
    {
      pending:=cursorConsumed ?: from;domain:=emptyDomains.last
      // The caller still has to consume [pending,hour). Prove that prefix too;
      // a valid final reading closed at hour must never enter a constant group.
      if(domain!=null && (DateTime)domain["from"]<=pending && (DateTime)domain["to"]>=hour && (domain["strictQuality"] ?: "missing")=="missing") return to
    }
    if(raw.size==1 && raw.first.ts>hour)
    {
      end:=EnerCubixMath.floorHour(raw.first.ts)
      return end>to ? to : end
    }
    return null
  }
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
    clearCursorChunk;raw.clear;intervals.clear;cursorReader=null;previous=null;cursorValidatedConfig=null
    parsedQueries?.each |pair| {pair.clear};parsedQueries?.clear;parsedQueries=null
    if(cursorIntervalCharge > 0) {budget.state.releaseTemporary(cursorIntervalCharge);cursorIntervalCharge=0}
    if(!cursorEscaped) clearPrepared
    ctx=null;cutoffText="";formattedObserved=null;formattedObservedText=null
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
      queued:=!cursorSpans.isEmpty
      if(queued) span=cursorSpans.removeAt(0)
      else
      {
        if(cursorReadAt >= cursorReadEnd) return false
        end:=cursorReadAt+cursorReadStep;if(end > cursorReadEnd) end=cursorReadEnd
        span=Span.makeAbs(cursorReadAt,end);cursorReadAt=end
      }
      items:=HisItem[,]
      try {items=readBlock(span.start,span.end,cursorReader)}
      catch(EnerCubixStreamBlockErr e)
      {
        ticks:=(span.end-span.start).ticks
        if(ticks <= 1ms.ticks) throw EnerCubixHttpErr(422,"HISTORY_DENSITY_LIMIT","cockpitHistoryDensityLimit")
        // Reuse the smaller span learned under the unchanged block/raw/fair
        // cap. Resetting to four days repeats the entire split tree on every
        // dense block. Both queued halves still cover the original span.
        learned:=Duration(ticks/2);if(learned>4day) learned=4day
        if(learned<cursorReadStep) cursorReadStep=learned
        mid:=span.start+Duration(ticks/2)
        cursorSpans.insert(0,Span.makeAbs(mid,span.end));cursorSpans.insert(0,Span.makeAbs(span.start,mid));continue
      }
      if(items.isEmpty)
      {
        // Only an actual successful empty main span permits a wider next read.
        // Every instant is still read; queued density splits cannot grant this.
        // Untagged interval cadence is inferred from its first nonempty
        // four-day block. Preserve that exact legacy inference window.
        fixedCadence:=cleaned || mode!="interval" || (!inferredInterval && (point.has("hisCollectInterval") || point.has("hisInterval")))
        if(!queued)
        {
          if(cursorReadStep<4day) cursorReadStep=4day
          else if(fixedCadence && cursorReadStep<64day) cursorReadStep*=2
        }
        continue
      }
      // Wider empty-domain probes return to four days on any row, including
      // NA/null. Dense spans retain their learned bound. Sparse successful
      // main spans may grow back toward four days; inference still uses its
      // original first nonempty block, and readBlock enforces every hard cap.
      if(cursorReadStep>4day) cursorReadStep=4day
      else if(!queued && cursorReadStep<4day)
      {
        // Same effective ceiling as readBlock, including other owners' held
        // buffers and this cursor's retained boundary/cleaning rows.
        room:=((budget.rawRoom(cursorId)-raw.size-(previous==null ? 0 : 1))/3).max(0)
        cap:=budget.blockLimit.min(room).min(budget.heldLimit/(budget.activeCursors*3))
        if(items.size*2<=cap) {nextStep:=cursorReadStep*2;cursorReadStep=nextStep>4day ? 4day : nextStep}
      }
      // Future rows are charged only as raw samples. Cleaning derives exactly
      // the next consumed row in advance(), never a second future detail graph.
      try
      {
        cursorItems=items.map |item->HisItem?| {item};items.clear
        budget.holdCursor(cursorId,cursorItems.size+raw.size+(previous == null ? 0 : 1))
        return true
      }
      catch(Err e)
      {
        items.clear;cursorItems.clear;cursorDetails.clear;cursorDetailCharge=0
        budget.holdCursor(cursorId,raw.size+(previous == null ? 0 : 1));throw e
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
    cutoffText=cutoff.toIso
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
  private Str cutoffText
  private DateTime? formattedObserved
  private Str? formattedObservedText
  private DateTime[] queryEnds
  private DateTime[][]? parsedQueries
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
  private Duration cursorReadStep := 4day
  private DateTime? cursorClosable
  private Span[] cursorSpans := [,]
  private HisItem?[] cursorItems := [,]
  private [Str:Obj?]?[] cursorDetails := [,]
  private Int cursorIndex := 0
  private Int cursorDetailCharge := 0
  private Dict? cursorValidatedConfig
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
    items.each |item,i| {append(item,result == null ? null : EnerCubixCleanStep.fromDetail(result.details[i]),to,items.size)}
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

  private Void append(HisItem item,EnerCubixCleanStep? d,DateTime limit,Int heldItems)
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
      seconds:=d.intervalSeconds ?: 0f
      if(d.emitted == true && seconds > 0f)
      {
        end:=item.ts.toTimeZone(from.tz)
        if(cursorMode) {budget.state.holdOwned(1);cursorIntervalCharge++}
        intervals.add(EnerCubixInterval(end-Duration((seconds*1sec.ticks.toFloat).toInt),end,d.number,d.quality,d.valueType.toStr))
      }
    }
    if(cursorMode) budget.holdCursor(cursorId,heldItems+raw.size+(previous == null ? 0 : 1))
    else budget.hold(heldItems+raw.size)
    if(d != null && d.reason == "removedNA") return
    cursorClosable=item.ts
    firstHour:=EnerCubixMath.floorHour(item.ts)
    if(firstHour > limit) firstHour=limit
    if(raw.size == 1 && intervals.isEmpty && hour < firstHour) emptyUntil(firstHour < to ? firstHour : to)
    while(hour < limit && item.ts >= hour+1hr) closeHour
  }

  private Void increment(Str k) {meta[k]=((Int)meta[k])+1}

  private Void observe(EnerCubixCleanStep d, DateTime end)
  {
    seconds:=d.intervalSeconds ?: 0f
    start:=end-Duration((seconds*1sec.ticks.toFloat).toInt)
    selected:=d.emitted == true && end > from && start < to
    if (selected)
    {
      increment("outputCount")
      if (d.valueType == "number") increment("validCount")
      else if (d.valueType == "na") {increment("naCount");naCount++}
      else increment("nullCount")
      if (d.substituted == true) substituted++
      if (d.diagnosticValue == null && d.valueType != "na" && !["inputNull","previousNull","nonPositiveInterval"].contains(d.reason)) filtered++
    }
    if (["ok","noPrevious"].contains(d.reason) || !(selected || (d.emitted != true && end >= from && end < to))) return
    eventCount++
    if (d.reason == "rollover") increment("rolloverCount")
    else if (d.emitted == true) increment("rejectedCount")
    if (d.reason == "removedNA") increment("removedNACount")
    if (d.substituted == true) increment("substitutedCount")
    capture:=cursorMode ? budget.diagnosticCapture : null
    if(capture!=null && !capture.canPutSimple(diagnosticGroup)) {capture.skipSimple(diagnosticGroup);return}
    if (capture!=null || diagnostics.size < 1000)
    {
      scratch:=capture==null ? null : EnerCubixPreparedOwner(budget.state)
      try
      {
      scratch?.hold(50)
      event:=EnerCubixHistory.nativeDetail(d.detail).setAll(["pointId":point.id.id,"unit":point["unit"],"profileId":meta["profileId"],"profileVersion":meta["profileVersion"],"parameters":meta["parameters"]])
      reason:=d.reason.toStr
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
      history=cleaned ? EnerCubixHistoryData.closedWindow(point,intervals,cutoff) : EnerCubixHistoryData.window(point,mode,raw,null,cutoff)
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
    if(cursorMode && parsedQueries==null)
    {
      // Preserve original constraints and visit order. Only immutable parsing
      // is shared by this cursor; none of the hourly pairs are cached/changed.
      n:=1+4*queries.size;budget.state.holdOwned(n);cursorCatalogCharge+=n
      parsedQueries=queries.map |q->DateTime[]| {[DateTime.fromIso(q["from"].toStr),DateTime.fromIso(q["to"].toStr)]}
    }
    pairs:=pairs(hour,queries,tariffs,(EnerCubixContext)ctx,parsedQueries)
    fullKey:=key(hour,end)
    values:=Str:Obj?[:]
    pairs.each |pair|
    {
      a:=(DateTime)pair["from"]; b:=(DateTime)pair["to"]
      name:=a==hour && b==end ? fullKey : key(a,b);if (reads.containsKey(name)) return
      strict:=history.read(a,b)
      known:=Str:Obj?[:]
      queryEnds.each |qEnd|
      {
        // This fresh window has no prepared/borrowed map. knownUsage returns
        // its own mutable envelope; a second shallow copy repeats that work.
        // The global capture may already be full. Numeric/coverage/rule facts
        // still inspect every interval; do not build rows that cannot survive
        // this exact visit's unchanged diagnostic admission.
        room:=(1000-budget.detailCount).max(0)
        row:=history.captureKnownUsage(a,b,qEnd,ruleEnd == qEnd,room);row.remove("value")
        events:=EnerCubixMath.maps(row["intervals"])
        keep:=events.size.min((1000-budget.detailCount).max(0))
        row["intervals"]=keep == 0 ? [Str:Obj?][,] : events[0..<keep]
        row["detailsTruncated"]=(EnerCubixMath.num(row["intervalCount"]) ?: 0f) > keep.toFloat
        if(row["detailsTruncated"] == true) row["intervalsCaptureId"]=Uuid().toStr
        else {row.remove("_closedOwnPrimaryHour");row.remove("_containsSubstitutedIntervals")} // Complete diagnostics already prove the predicates.
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
      facts:=0
      ((Map)((Map)v)["known"]).vals.each |r| {row:=(Map)r;if(row.containsKey("_closedOwnPrimaryHour")) facts++;if(row.containsKey("_containsSubstitutedIntervals")) facts++}
      preparedCell(2+queryEnds.size+facts);budget.materializedPairs++;reads[k]=v
    }
    hour=end
    raw=raw.size > 2 ? raw[-2..-1] : raw
    oldIntervals:=intervals.size
    intervals=intervals.findAll |row| {row.end > end}
    if(cursorMode && intervals.size < oldIntervals)
    {released:=oldIntervals-intervals.size;budget.state.releaseTemporary(released);cursorIntervalCharge-=released}
  }

  internal static [Str:Obj?][] pairs(DateTime hour, [Str:Obj?][] queries, [Str:Obj?]?[] tariffs, EnerCubixContext ctx,DateTime[][]? parsed := null)
  {
    end:=hour+1hr
    pairs:=[Str:Obj?][["from":hour,"to":end]]
    for(qi:=0;qi<queries.size;qi++)
    {
      q:=queries[qi]
      a:=parsed==null ? DateTime.fromIso(q["from"].toStr) : parsed[qi][0]
      b:=parsed==null ? DateTime.fromIso(q["to"].toStr) : parsed[qi][1]
      if (a < hour) a=hour;if (b > end) b=end
      if (b > a)
      {
        pairs.add(["from":a,"to":b])
        // Keep the original tier prefix and every duplicate visit in order.
        if(a > hour)
        {
          tiered:=false
          for(ti:=0;ti<tariffs.size;ti++) {if(["monthlyBlock","yearlyBlock"].contains(tariffs[ti]?.get("mode") as Str ?: "")) {tiered=true;break}}
          if(tiered) pairs.add(["from":hour,"to":a])
        }
      }
    }
    base:=pairs.dup
    for(pi:=0;pi<base.size;pi++)
    {
      pair:=base[pi];a:=(DateTime)pair["from"];b:=(DateTime)pair["to"]
      for(ti:=0;ti<tariffs.size;ti++)
      {
        tariff:=tariffs[ti];rules:=tariff?.get("rules") as List;exceptions:=tariff?.get("exceptions") as List
        if(tariff!=null && (rules==null || rules.isEmpty) && (exceptions==null || exceptions.isEmpty))
          pairs.add(["from":a,"to":b])
        else
        {
          bounds:=ctx.tariffBounds(tariff,a,b)
          for(i:=0;i<bounds.size-1;i++) pairs.add(["from":bounds[i],"to":bounds[i+1]])
        }
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
    // The cutoff is immutable; the last observed timestamp changes only when
    // another original row is consumed. Empty hours need no repeated ISO work.
    if(formattedObserved!=lastObserved) {formattedObservedText=lastObserved?.toIso;formattedObserved=lastObserved}
    out:=Str:Obj?["pointId":point.id.id,"unit":point["unit"] ?: "","mode":cleaned ? "interval" : mode,"quality":cleaned ? "cleaned" : "ok","sourceIds":[point.id.id],"simulated":point.has("simulated"),"dataCutoff":cutoffText,"_preparedReads":reads,"_preparedSparse":["version":1,"from":from,"to":to,"domains":emptyDomains,"queries":queries,"queryEnds":queryEnds,"tariffs":tariffs,"tz":from.tz.name],"_preparedBudget":budget.state,"sourceLastObservedAt":formattedObservedText]
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

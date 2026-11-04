** Private full-profile consumer. Source frames remain borrowed; period, own-meter
** and coverage reductions are independent. No default route uses this seam.
internal class EnerCubixReportConsumer
{
  new make(EnerCubixContext ctx,EnerCubixReport report,EnerCubixLineCursor[] cursors,
    DateTime from,DateTime to,Str gran,EnerCubixPreparedOwner state,EnerCubixPreparedOwner output,EnerCubixCockpitCapture? diagnostics := null,Str? diagnosticKey := null)
  {
    if(!report.acceptsFrames || !report.ownedFrameCatalog(state) || state === output || state.budget !== output.budget || !ctx.ownedCatalog(state.budget) || cursors.any |c| {c.watermark != from || !c.line.ticks.isEmpty}) throw ArgErr("reportConsumerPlan")
    if(report.summaryFrames && cursors.any |c| {c.line.ratio || c.line.gauge || c.line.reference}) throw ArgErr("summaryFrameLine")
    if((diagnostics==null)!=(diagnosticKey==null) || (diagnostics!=null && (report.summaryFrames || diagnostics.budget!==state.budget))) throw ArgErr("reportDiagnosticPlan")
    diagnostics?.expect(diagnosticKey,"sourceUsage")
    this.diagnostics=diagnostics;this.diagnosticKey=diagnosticKey
    this.ctx=ctx;this.report=report;this.cursors=cursors.dup;this.to=to;this.at=from;this.output=output
    // Retain the closed child handle (four owner fields plus its reference)
    // until the parent expires, as with the daily bin owner's lifecycle.
    state.watch |->Void| {closeState};state.hold(27+5*cursors.size)
    // Reduction state expires once every detached result has been captured.
    // Context, report plans and cursors remain owned by the parent finalizer.
    reductions=state.fork
    try {state.watch |->Void| {reductions.close}}
    catch(Err e) {reductions.close;throw e}
    definitions:=EnerCubixLine[,]
    output.watch |->Void|
    {
      closeOutput;report.clearFrames
      definitions.each |EnerCubixLine line| {if(line.outputOwnsArea) EnerCubixArea.clearResult(line.normalizationArea);line.consumedTotals?.clear;line.consumedTotals=null}
      definitions.clear;if(!sharedBorrowed) borrowed.clear
    }
    diagnostics?.bind(output)
    if(ctx.sharedCatalog!=null) {ctx.sharedCatalog.bind(output);borrowed=ctx.sharedCatalog.protectedRoots;sharedBorrowed=true}
    shape:=report.freezeFrameMetadata(cursors.map |c->EnerCubixLine| {c.line},output)
    meterCount=initializeMeters(report,cursors,reductions,shape)
    // Only new DTO containers are reserved here. The frozen input catalog is
    // borrowed; protect() admits each additional reference, never a deep clone.
    n:=report.dailyFrames ? 24 : (report.workingFrames ? 2 : 0);bucket:=EnerCubixMath.bucket(from,gran)
    if(!report.summaryFrames && !report.dailyFrames && !report.workingFrames) while(bucket<to) {n++;bucket=EnerCubixMath.nextBucket(bucket,gran)}
    // 40 per period covers point+detail maps/links; 32 per membership covers
    // scope/detail rows and variable meter/source/area lists. The per-line/meter
    // envelope includes totals, utility groups and shallow tariff map heads.
    finalEntries=2048+128*(meterCount+cursors.size)+40*n*cursors.size+32*(shape["members"]+shape["details"])
    classEntries=2048+128*cursors.size
    // Keep cleanup workspace until output expires, so dropGraph can still clear
    // aliased lists/maps when another owner has filled the remaining budget.
    maxList:=(n*cursors.size).max(shape["details"]).max(shape["members"]).max(ctx.byId.size).max(1000)
    // Pooled DTOs are generated acyclic graphs. Clear their children in place;
    // no 1000-row evidence or unrelated catalog cleanup copy is allocated.
    // Keep the existing copy workspace for the independent legacy seam.
    output.hold(diagnostics==null ? 128+2*maxList : 128)
    // The summary finalizer creates only two line vectors and one coverage
    // vector. It never creates selection/detail candidate or area unions.
    // Final membership/area graphs are now frozen and charged above. Remaining
    // finalizers use actual member/detail vectors and one real ancestor path.
    finishScratch=report.summaryFrames ? 64*(cursors.size+shape["maxMembers"]+1) : 64*(report.frameFinalDepth+shape["members"]+shape["details"]+cursors.size+1)
    if(!sharedBorrowed) ctx.byId.each |record| {protect(record)}
    // Requested area graphs remain linked from definitions; non-normalized
    // owned reports carry only an empty placeholder. Transfer the actual graph.
    definitions.addAll(cursors.map |c->EnerCubixLine| {c.line})
    cursors.each |cursor| {output.hold(ownedMetadata(cursor.line.normalizationArea));cursor.line.outputOwnsArea=true}
    cursors.each |cursor|
    {
      line:=cursor.line;periods.add(EnerCubixPeriodConsumer(line,from,to,gran,reductions,output,!report.summaryFrames && !report.dailyFrames && !report.workingFrames,report.frameSharesBase(line)))
      if(report.dailyFrames) daily.add(EnerCubixDailyConsumer(line,reductions,output))
      if(report.workingFrames) working.add(EnerCubixWorkingConsumer(line,reductions,output))
      points:=report.frameScope(line).map |m->Str| {m["pointId"] as Str ?: ""}.findAll |Str id->Bool| {!id.isEmpty}
      covers.add(EnerCubixCoverageFold(points,from,to,reductions))
    }
  }
  private EnerCubixContext? ctx
  private EnerCubixReport? report
  private EnerCubixLineCursor[] cursors := [,]
  private EnerCubixPeriodConsumer[] periods := [,]
  private EnerCubixCoverageFold[] covers := [,]
  private EnerCubixDailyConsumer[] daily := [,]
  private EnerCubixWorkingConsumer[] working := [,]
  private EnerCubixMeterReduction[] firstMeters := [,]
  private EnerCubixMeterReduction[] lastMeters := [,]
  private Int meterCount := 0
  private Str:EnerCubixValueFold meters := [:]
  private Str:[Str:Obj?] evidence := [:]
  private DateTime at
  private DateTime to
  private EnerCubixPreparedOwner output
  private EnerCubixPreparedOwner reductions
  private Str:Obj? result := [:]
  private Obj[] borrowed := [,]
  private Bool sharedBorrowed := false
  private EnerCubixCockpitCapture? diagnostics
  private Str? diagnosticKey
  private EnerCubixValue[] frozenMeters := [,]
  private Int finishScratch := 0
  private Int finalEntries := 0
  private Int classEntries := 0
  private Int countVisits := 0
  private Bool meterValuesWereNull := false
  private Int readCount := 0
  private Int detailCount := 0
  private Bool emptyOmitted := false
  private Bool unpreparedOmitted := false
  private Bool closed := false
  private Bool stateClosed := false
  private Bool done := false
  private Err? failure

  ** Bind the frozen ledger once. Every hour retains its original phase/order,
  ** but does not filter maps, format keys or look up the same fold again.
  private Int initializeMeters(EnerCubixReport report,EnerCubixLineCursor[] cursors,EnerCubixPreparedOwner state,Str:Int shape)
  {
    scratch:=state.fork;raw:=[Str:Obj?][,]
    try
    {
      scratch.hold(4+10*(shape["members"]+shape["details"]+cursors.size))
      raw=report.frameLedger(cursors.map |c->EnerCubixLine| {c.line})
      // Two list roots, typed object/fields/list link and both meter-map slots.
      state.hold(3+9*raw.size)
      raw.each |item|
      {
        id:=item["id"].toStr;category:=item["category"].toStr;key:="$id|$category"
        strict:=EnerCubixValueFold.strict(state);known:=EnerCubixValueFold.known(state)
        meters[key+"|false"]=strict;meters[key+"|true"]=known
        plan:=EnerCubixMeterReduction(id,category,(Int)item["order"],strict,known)
        (item["phase"]==1 ? firstMeters : lastMeters).add(plan)
      }
      return raw.size
    }
    finally {raw.each |item| {item.clear};raw.clear;scratch.close}
  }

  Void addFrame(Str:EnerCubixHistoryData histories,EnerCubixPreparedOwner frame)
  {addFrames(histories,frame,EnerCubixMath.floorHour(at)+1hr)}
  Void addFrames(Str:EnerCubixHistoryData histories,EnerCubixPreparedOwner frame,DateTime through,Bool constantEmpty := false)
  {
    check
    if(done || at>=to || frame.budget !== output.budget) throw ArgErr("reportConsumerFrame")
    try
    {
      report.beginFrame(frame,histories,constantEmpty)
      meterValuesWereNull=true;skipMeters:=false
      while(at<to && at<through)
      {
        addHour(frame,skipMeters)
        // Repeating the same null-only own-meter input is idempotent for both
        // folds. Period counts and coverage still consume every original hour.
        if(constantEmpty && !skipMeters && meterValuesWereNull && report.constantEmptyMeters && report.frameReads.isEmpty) skipMeters=true
      }
    }
    catch(Err e) {failure=e;throw e}
  }
  private Void addHour(EnerCubixPreparedOwner frame,Bool skipMeters)
  {
      end:=EnerCubixMath.floorHour(at)+1hr;if(end>to) end=to
      cursors.each |cursor,i|
      {
        ctx.warningScope(0,i,at.ticks);tick:=cursor.next;periods[i].add(tick)
        if(!daily.isEmpty) daily[i].add(tick,report.frameBand(cursor.line,tick))
        if(!working.isEmpty) working[i].add(tick,report.frameWorking(tick))
      }
      if(!skipMeters) consumeMeters(1,end)
      // Normal finish freezes coverage/evidence before dimensionDetails reads.
      // Detail-only meters must not appear in that earlier evidence snapshot.
      freezeEvidence(frame)
      if(!skipMeters) consumeMeters(3,end)
      at=end
  }
  private Void freezeEvidence(EnerCubixPreparedOwner frame)
  {
    // No borrowed header list survives into detail reads that replace cache slots.
    reads:=report.frameReads;covers.each |cover| {cover.addFrame(reads,frame)}
    if(!report.summaryFrames)
    {capture(reads);emptyOmitted=emptyOmitted || report.frameEmptyOmitted;unpreparedOmitted=unpreparedOmitted || report.frameUnpreparedOmitted}
  }
  private Void consumeMeters(Int phase,DateTime end)
  {
    items:=phase==1 ? firstMeters : lastMeters
    for(i:=0;i<items.size;i++)
    {
      item:=items[i]
      ctx.warningScope(phase,item.order,at.ticks)
      strict:=report.frameMeter(item.id,item.category,at,end,false);known:=report.frameMeter(item.id,item.category,at,end,true)
      if(strict.value!=null || known.value!=null) meterValuesWereNull=false
      item.strict.add(strict);item.known.add(known)
    }
  }

  Str:Obj? finish()
  {
    check
    if(done) return result
    if(at!=to) throw ArgErr("reportConsumerIncomplete")
    try
    {
      // Final report DTOs do not exist while frames are being reduced. Admit
      // their unchanged envelope immediately before the first final allocation.
      // The class/line allowance covers preparation links. Each reduced value
      // and daily/working snapshot has its own admission below.
      output.hold(classEntries)
      totals:=Str:EnerCubixValue[:];coverage:=Str:[Str:Obj?][:];buckets:=Str:Str:Obj?[:];dailyData:=Str:[Str:Obj?][:];workingData:=Str:[Str:Obj?][][:]
      periods.each |consumer,i|
      {
        consumer.finish;line:=cursors[i].finish;output.hold(4)
        line.consumedTotals=Str:EnerCubixValue[:]
        ["value","known","baseValue","baseKnown"].each |mode| {line.consumedTotals[mode]=consumer.total(mode)}
        if(!report.summaryFrames) buckets[line.id]=["rows":consumer.periods]
        coverage[line.id]=report.frameCoverage(line,covers[i].finish)
        if(!daily.isEmpty) dailyData[line.id]=daily[i].finish
        if(!working.isEmpty) workingData[line.id]=working[i].finish
      }
      meters.each |fold,key| {output.hold(6+fold.sourceCount);value:=fold.finish;totals[key]=value;frozenMeters.add(value)}
      // No reducer is read by finishFrames. Its period/coverage/meter values
      // and source arrays have independent output admission and ownership.
      firstMeters.clear;lastMeters.clear;meters.clear;covers.clear;daily.clear;working.clear
      reductions.close
      captured:=diagnostics==null ? evidence.vals : diagnostics.rows(diagnosticKey)
      omitted:=readCount>captured.size || emptyOmitted || unpreparedOmitted
      output.hold(14+(diagnostics==null ? evidence.size : 0))
      // capture already enforces the report-wide child limit. Reuse those owned
      // maps instead of making a second shallow map/list graph with evidence().
      known:=Str:Obj?["basis":"closedSourceIntervals","sourceUsage":captured,"detailsTruncated":omitted || captured.any |r| {r["detailsTruncated"] == true}]
      if(diagnostics!=null)
      {
        diagnostics.knownEnvelope(diagnosticKey,known,output,readCount,emptyOmitted,unpreparedOmitted)
        diagnostics.seal(diagnosticKey,emptyOmitted || unpreparedOmitted)
      }
      else if(omitted) known.setAll(["sourceUsageCaptureId":Uuid().toStr,"sourceUsageTruncated":true,"sourceUsageRowCount":emptyOmitted || unpreparedOmitted ? null : readCount,"truncationReason":"cockpitBoundedPreparedEvidence","omittedConfirmedEmpty":emptyOmitted,"omittedUnprepared":unpreparedOmitted])
      // Finished daily bins have expired. Admit the complete remaining DTO
      // envelope before constructing the original final report maps.
      finalEntries=classEntries+finalDtoEntries(dailyData)
      output.hold(finalEntries-classEntries)
      scratch:=EnerCubixPreparedOwner(output.budget)
      try
      {
        // Original finalizers create candidate arrays, source unions and area
        // scratch graphs. Admit them before invoking any of those allocations.
        scratch.hold(finishScratch)
        result=report.finishFrames(cursors.map |c->EnerCubixLine| {c.line},buckets,totals,coverage,known,dailyData,workingData)
        ((Map)result["extra"])["relationBasis"]="current"
      }
      finally {scratch.close}
      releaseFinalSlack
      done=true;return result
    }
    catch(Err e) {failure=e;throw e}
  }
  internal Int childStateEntries() {n:=reductions.entries;daily.each |d| {n+=d.stateEntries};return n}

  ** Size this owned physical-energy daily DTO from its actual output shape.
  ** The old 40-per-period allowance combines hours and all band rows, even
  ** when only the single unclassified band will be emitted. Keep the shared
  ** meter/detail allowances and the entire original temporary workspace.
  private Int finalDtoEntries(Str:[Str:Obj?] dailyData)
  {
    original:=finalEntries-classEntries
    if(report.canSizeUtilityOutput && cursors.all |c| {!c.line.reference && !c.line.gauge && !c.line.ratio && !c.line.leak && c.line.ticks.isEmpty} &&
       cursors.all |c| {c.line.consumedTotals!=null && !c.line.consumedTotals.any |v| {v.sources.size>1}} &&
       periods.all |p| {p.periods.all |row| {((EnerCubixValue)row["value"]).sources.size<=1 && ((EnerCubixValue)row["known"]).sources.size<=1}})
    {
      count:=0;periods.each |p| {count+=p.periods.size}
      // Actual append DTO: point map+known/end fields10, detail map+known/end
      // fields15, two links2. Its source arrays are independently owned by
      // detached periods. Inspect actual totals/periods before using this bound.
      // New non-period graph: series9C, totals20C, coverage linksC, members24C,
      // selection16G+2C, shares22U+2C <=96C (G,U<=C). Reserve100C plus common
      // heads/warnings independently. The original32 per frozen member already
      // funds this same non-period graph: credit at most one such allowance per
      // line, never nonexistent members or private metadata/class/scratch.
      credit:=32*report.frameMemberCount.min(cursors.size)
      return original-40*count+27*count+100*cursors.size+report.dailyOutputCommonEntries-credit
    }
    if(!report.canSizeDailyOutput || cursors.any |c| {c.line.reference || c.line.gauge || c.line.ratio || c.line.leak || !c.line.ticks.isEmpty}) return original
    if(cursors.any |c| {data:=dailyData[c.line.id];return data==null || (data["hours"] as List)?.size!=24 || data["classified"] isnot List}) return original
    // Common fixed DTO heads/fields and warnings, plus coverage-vector links.
    needed:=report.dailyOutputCommonEntries+cursors.size
    cursors.each |cursor|
    {
      classified:=(List)dailyData[cursor.line.id]["classified"]
      bands:=classified.size==1 && classified.first=="unknown" ? 1 : 6
      // Per hour: point map(7)+known fields(4), detail map(14)+known
      // fields(4), and two list links =31. Sources are already owned by
      // the detached snapshots; scale/point/baseRow borrow those arrays.
      // Per line: series map/link/point-list head=9; two totals rows/links=20;
      // per band: base row(10)+band(1)+known(3)+link(1)+empty source head(1).
      needed+=24*31+9+20+16*bands
    }
    // Original 128*meters and 32*(scope/detail memberships) still cover
    // selection rows, source unions, member vectors and detail/area metadata.
    // Never clamp this bound to the old envelope if the actual shape is larger.
    return original-40*24*cursors.size+needed
  }

  ** Count only the public graph at the registry's explicit done boundary.
  ** No sample reclamation occurs merely to attempt this optional compaction.
  internal Int publicEntries()
  {
    if(!done || !sharedBorrowed || output.budget.remaining<68) return output.entries
    cap:=output.entries;scratch:=EnerCubixPreparedOwner(output.budget)
    [Int:Obj[]]? seen;countVisits=0
    try
    {
      scratch.hold(64);seen=Int:Obj[][:]
      n:=retainedEntries(result,cap,seen,scratch)
      // Owner/control references, one cleanup closure and the future fields
      // reserved by knownEnvelope remain admitted after private roots expire.
      return (n+32+(diagnostics?.pendingEntries(output) ?: 0)).min(cap)
    }
    finally {seen?.each |bucket| {bucket.clear};seen?.clear;scratch.close}
  }

  ** Generated report DTOs are acyclic. Shared catalog and sample containers
  ** remain owned by their original owners and must never be cleared here.
  internal static Void clearPublic(Obj? value,Obj[] catalog,Obj[] samples)
  {
    if(value isnot Map && value isnot List && value isnot EnerCubixValue) return
    if(catalog.any |root| {root===value} || samples.any |root| {root===value}) return
    if(value is EnerCubixValue)
    {v:=(EnerCubixValue)value;clearPublic(v.sources,catalog,samples);v.value=null;v.quality="ownerExpired";return}
    if(value is Map) {((Map)value).each |child| {clearPublic(child,catalog,samples)};((Map)value).clear}
    else {((List)value).each |child| {clearPublic(child,catalog,samples)};((List)value).clear}
  }

  private Void releaseFinalSlack()
  {
    if(diagnostics==null && !sharedBorrowed) return
    cap:=finalEntries-classEntries;if(cap<=0) return
    // Count physical containers once across all output roots. Other owners and
    // the original class allowance stay charged; only our unused envelope moves.
    scratch:=output.fork;[Int:Obj[]]? seen;count:=0;countVisits=0
    try
    {
      scratch.hold(64);seen=Int:Obj[][:]
      count=retainedEntries(result,cap,seen,scratch)
      report.eachFrameOutputRoot |root| {if(count<cap) count+=retainedEntries(root,cap-count,seen,scratch)}
      cursors.each |cursor|
      {if(count<cap) count+=retainedEntries(cursor.line.consumedTotals,cap-count,seen,scratch);if(count<cap) count+=retainedEntries(cursor.line.normalizationArea,cap-count,seen,scratch)}
      if(count<cap) count+=retainedEntries(frozenMeters,cap-count,seen,scratch)
    }
    finally {seen?.each |bucket| {bucket.clear};seen?.clear;scratch.close}
    if(count<cap) output.release(cap-count)
  }
  private Int retainedEntries(Obj? value,Int cap,Int:Obj[] seen,EnerCubixPreparedOwner scratch)
  {
    if(++countVisits%256==0) output.budget.deadline.check
    if(cap<=0 || (value isnot Map && value isnot List && value isnot EnerCubixValue)) return 0
    if(borrowed.any |item| {item===value} || diagnostics?.protectedRoots?.any |item| {item===value} == true) return 0
    id:=Env.cur.idHash(value);bucket:=seen[id]
    if(bucket?.any |item| {item===value} == true) return 0
    // Hash collisions use reference equality. Admit the map link, bucket header
    // and retained reference before allocating them. Without scratch room,
    // keep the original conservative cap rather than fail merely to trim it.
    charge:=bucket==null ? 3 : 1
    if(output.budget.remaining<charge) return cap
    scratch.hold(charge)
    if(bucket==null) {bucket=Obj[value];seen[id]=bucket}
    else bucket.add(value)
    if(value is EnerCubixValue) return (3+retainedEntries(((EnerCubixValue)value).sources,(cap-3).max(0),seen,scratch)).min(cap)
    n:=1+(value is Map ? ((Map)value).size : ((List)value).size)
    if(n>=cap) return cap
    if(value is Map) ((Map)value).each |child| {if(n<cap) n+=retainedEntries(child,cap-n,seen,scratch)}
    else ((List)value).each |child| {if(n<cap) n+=retainedEntries(child,cap-n,seen,scratch)}
    return n
  }
  private Void capture([Str:Obj?][] reads)
  {
    reads.each |row|
    {
      readCount++
      if(diagnostics!=null) {diagnostics.put(diagnosticKey,row);return}
      if(evidence.size>=1000) return
      intervals:=EnerCubixMath.maps(row["intervals"]);keep:=intervals.size.min((1000-detailCount).max(0))
      // Admit the complete detached graph before duplicating borrowed maps.
      output.hold(3+row.size+EnerCubixMath.strings(row["sourceIds"]).size+keep)
      for(i:=0;i<keep;i++) output.hold(1+intervals[i].size)
      copy:=row.dup;copy["sourceIds"]=EnerCubixMath.strings(row["sourceIds"]).dup
      copy["intervals"]=intervals[0..<keep].map |r->[Str:Obj?]| {r.dup}
      if(keep<intervals.size) copy["detailsTruncated"]=true
      detailCount+=keep
      evidence[row["nodeId"].toStr+"|"+row["pointId"].toStr+"|"+DateTime.fromIso(row["from"].toStr).ticks+"|"+DateTime.fromIso(row["to"].toStr).ticks]=copy
    }
  }
  private Int ownedMetadata(Obj? value)
  {
    if(value isnot Map && value isnot List) return 0
    if(borrowed.any |item| {item === value}) return 0
    n:=1+((value is Map) ? ((Map)value).size : ((List)value).size)
    if(value is Map) ((Map)value).each |child| {n+=ownedMetadata(child)}
    else ((List)value).each |child| {n+=ownedMetadata(child)}
    return n
  }
  private Void protect(Obj? value)
  {
    if(value isnot Map && value isnot List) return
    if(borrowed.any |item| {item === value}) return
    output.hold(1);borrowed.add(value)
    if(value is Map) ((Map)value).each |child| {protect(child)}
    else ((List)value).each |child| {protect(child)}
  }
  private Void dropGraph(Obj? value)
  {
    if(value isnot Map && value isnot List) return
    if(borrowed.any |item| {item === value}) return
    if(diagnostics?.protectedRoots?.any |item| {item===value} == true) return
    if(diagnostics!=null)
    {
      // Report fields, owned area results and detached cleaning metadata are
      // acyclic by construction. Shared pool/catalog graphs stopped above.
      if(value is Map) {((Map)value).each |child| {dropGraph(child)};((Map)value).clear}
      else {((List)value).each |child| {dropGraph(child)};((List)value).clear}
      return
    }
    // Clear before visiting children: repeated aliases and cycles terminate,
    // without mutating configuration containers borrowed from the catalog.
    if(value is Map) {children:=((Map)value).vals;((Map)value).clear;children.each |child| {dropGraph(child)}}
    else {children:=((List)value).dup;((List)value).clear;children.each |child| {dropGraph(child)}}
  }
  private Void check()
  {if(closed) throw ArgErr("reportConsumerClosed");if(failure!=null) throw failure;if(stateClosed && !done) throw ArgErr("reportConsumerClosed")}
  private Void closeState()
  {ctx=null;report=null;cursors.clear;firstMeters.clear;lastMeters.clear;meters.clear;covers.clear;daily.clear;working.clear;stateClosed=true}
  private Void closeOutput()
  {
    dropGraph(result);dropGraph(evidence)
    frozenMeters.each |value| {if(!value.sources.isEmpty) value.sources.clear;value.value=null;value.quality="ownerExpired"}
    frozenMeters.clear;periods.clear;diagnostics=null;diagnosticKey=null;closed=true
  }
}

internal class EnerCubixMeterReduction
{
  new make(Str id,Str category,Int order,EnerCubixValueFold strict,EnerCubixValueFold known)
  {this.id=id;this.category=category;this.order=order;this.strict=strict;this.known=known}
  Str id
  Str category
  Int order
  EnerCubixValueFold strict
  EnerCubixValueFold known
}

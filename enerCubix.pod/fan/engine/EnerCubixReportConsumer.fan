** Private full-profile consumer. Source frames remain borrowed; period, own-meter
** and coverage reductions are independent. No default route uses this seam.
internal class EnerCubixReportConsumer
{
  new make(EnerCubixContext ctx,EnerCubixReport report,EnerCubixLineCursor[] cursors,
    DateTime from,DateTime to,Str gran,EnerCubixPreparedOwner state,EnerCubixPreparedOwner output)
  {
    if(!report.acceptsFrames || !report.ownedFrameCatalog(state) || state === output || state.budget !== output.budget || !ctx.ownedCatalog(state.budget) || cursors.any |c| {c.watermark != from || !c.line.ticks.isEmpty}) throw ArgErr("reportConsumerPlan")
    this.ctx=ctx;this.report=report;this.cursors=cursors.dup;this.to=to;this.at=from;this.output=output
    state.watch |->Void| {closeState};state.hold(20+5*cursors.size)
    definitions:=EnerCubixLine[,]
    output.watch |->Void|
    {
      closeOutput;report.clearFrames
      definitions.each |EnerCubixLine line| {if(line.outputOwnsArea) EnerCubixArea.clearResult(line.normalizationArea);line.consumedTotals?.clear;line.consumedTotals=null}
      definitions.clear;borrowed.clear
    }
    ledger=report.frameLedger(cursors.map |c->EnerCubixLine| {c.line});state.hold(1+7*ledger.size)
    // Only new DTO containers are reserved here. The frozen input catalog is
    // borrowed; protect() admits each additional reference, never a deep clone.
    n:=report.dailyFrames ? 24 : 0;bucket:=EnerCubixMath.bucket(from,gran)
    if(!report.dailyFrames) while(bucket<to) {n++;bucket=EnerCubixMath.nextBucket(bucket,gran)}
    shape:=report.frameShape(cursors.map |c->EnerCubixLine| {c.line})
    // 40 per period covers point+detail maps/links; 32 per membership covers
    // scope/detail rows and variable meter/source/area lists. The per-line/meter
    // envelope includes totals, utility groups and shallow tariff map heads.
    output.hold(2048+128*(ledger.size+cursors.size)+40*n*cursors.size+32*(shape["members"]+shape["details"]))
    // Keep cleanup workspace until output expires, so dropGraph can still clear
    // aliased lists/maps when another owner has filled the remaining budget.
    maxList:=(n*cursors.size).max(shape["details"]).max(shape["members"]).max(ctx.byId.size).max(1000)
    output.hold(128+2*maxList)
    finishScratch=64*(ctx.byId.size+shape["members"]+shape["details"]+cursors.size+1)
    ctx.byId.each |record| {protect(record)}
    // Area graphs were created under the calculation owner. They remain linked
    // from definitions (even perArea=false), so transfer their actual graph too.
    definitions.addAll(cursors.map |c->EnerCubixLine| {c.line})
    cursors.each |cursor| {output.hold(ownedMetadata(cursor.line.normalizationArea));cursor.line.outputOwnsArea=true}
    cursors.each |cursor|
    {
      line:=cursor.line;periods.add(EnerCubixPeriodConsumer(line,from,to,gran,state,output,!report.dailyFrames))
      if(report.dailyFrames) daily.add(EnerCubixDailyConsumer(line,state,output))
      points:=ctx.scopeMeters(line.nodeId,line.category,Str[,],line.utility).map |m->Str| {m["pointId"] as Str ?: ""}.findAll |Str id->Bool| {!id.isEmpty}
      covers.add(EnerCubixCoverageFold(points,from,to,state))
    }
    ledger.each |item|
    {
      key:=item["id"].toStr+"|"+item["category"].toStr
      meters[key+"|false"]=EnerCubixValueFold.strict(state);meters[key+"|true"]=EnerCubixValueFold.known(state)
    }
  }
  private EnerCubixContext? ctx
  private EnerCubixReport? report
  private EnerCubixLineCursor[] cursors := [,]
  private EnerCubixPeriodConsumer[] periods := [,]
  private EnerCubixCoverageFold[] covers := [,]
  private EnerCubixDailyConsumer[] daily := [,]
  private [Str:Obj?][] ledger := [,]
  private Str:EnerCubixValueFold meters := [:]
  private Str:[Str:Obj?] evidence := [:]
  private DateTime at
  private DateTime to
  private EnerCubixPreparedOwner output
  private Str:Obj? result := [:]
  private Obj[] borrowed := [,]
  private EnerCubixValue[] frozenMeters := [,]
  private Int finishScratch := 0
  private Int readCount := 0
  private Int detailCount := 0
  private Bool emptyOmitted := false
  private Bool unpreparedOmitted := false
  private Bool closed := false
  private Bool stateClosed := false
  private Bool done := false
  private Err? failure

  Void addFrame(Str:EnerCubixHistoryData histories,EnerCubixPreparedOwner frame)
  {
    check
    if(done || at>=to || frame.budget !== output.budget) throw ArgErr("reportConsumerFrame")
    try
    {
      report.beginFrame(frame,histories)
      end:=EnerCubixMath.floorHour(at)+1hr;if(end>to) end=to
      cursors.each |cursor,i|
      {ctx.warningScope(0,i,at.ticks);tick:=cursor.next;periods[i].add(tick);if(!daily.isEmpty) daily[i].add(tick,report.frameBand(cursor.line,tick))}
      consumeMeters(1,end)
      // Normal finish freezes coverage/evidence before dimensionDetails reads.
      // Detail-only meters must not appear in that earlier evidence snapshot.
      freezeEvidence(frame)
      consumeMeters(3,end);at=end
    }
    catch(Err e) {failure=e;throw e}
  }
  private Void freezeEvidence(EnerCubixPreparedOwner frame)
  {
    // No borrowed header list survives into detail reads that replace cache slots.
    reads:=report.frameReads;covers.each |cover| {cover.addFrame(reads,frame)}
    capture(reads);emptyOmitted=emptyOmitted || report.frameEmptyOmitted;unpreparedOmitted=unpreparedOmitted || report.frameUnpreparedOmitted
  }
  private Void consumeMeters(Int phase,DateTime end)
  {
    ledger.findAll |item| {item["phase"] == phase}.each |item|
    {
      id:=item["id"].toStr;category:=item["category"].toStr;key:="$id|$category"
      ctx.warningScope(phase,(Int)item["order"],at.ticks)
      meters[key+"|false"].add(report.frameMeter(id,category,at,end,false))
      meters[key+"|true"].add(report.frameMeter(id,category,at,end,true))
    }
  }

  Str:Obj? finish()
  {
    check
    if(done) return result
    if(at!=to) throw ArgErr("reportConsumerIncomplete")
    try
    {
      totals:=Str:EnerCubixValue[:];coverage:=Str:[Str:Obj?][:];buckets:=Str:Str:Obj?[:];dailyData:=Str:[Str:Obj?][:]
      periods.each |consumer,i|
      {
        consumer.finish;line:=cursors[i].finish;output.hold(4)
        line.consumedTotals=Str:EnerCubixValue[:]
        ["value","known","baseValue","baseKnown"].each |mode| {line.consumedTotals[mode]=consumer.total(mode)}
        buckets[line.id]=["rows":consumer.periods];coverage[line.id]=report.frameCoverage(line,covers[i].finish)
        if(!daily.isEmpty) dailyData[line.id]=daily[i].finish
      }
      meters.each |fold,key| {output.hold(6+fold.sourceCount);value:=fold.finish;totals[key]=value;frozenMeters.add(value)}
      omitted:=readCount>evidence.size || emptyOmitted || unpreparedOmitted
      output.hold(14+evidence.size)
      captured:=evidence.vals
      // capture already enforces the report-wide child limit. Reuse those owned
      // maps instead of making a second shallow map/list graph with evidence().
      known:=Str:Obj?["basis":"closedSourceIntervals","sourceUsage":captured,"detailsTruncated":omitted || captured.any |r| {r["detailsTruncated"] == true}]
      if(omitted) known.setAll(["sourceUsageCaptureId":Uuid().toStr,"sourceUsageTruncated":true,"sourceUsageRowCount":emptyOmitted || unpreparedOmitted ? null : readCount,"truncationReason":"cockpitBoundedPreparedEvidence","omittedConfirmedEmpty":emptyOmitted,"omittedUnprepared":unpreparedOmitted])
      scratch:=EnerCubixPreparedOwner(output.budget)
      try
      {
        // Original finalizers create candidate arrays, source unions and area
        // scratch graphs. Admit them before invoking any of those allocations.
        scratch.hold(finishScratch)
        result=report.finishFrames(cursors.map |c->EnerCubixLine| {c.line},buckets,totals,coverage,known,dailyData)
        ((Map)result["extra"])["relationBasis"]="current"
      }
      finally {scratch.close}
      done=true;return result
    }
    catch(Err e) {failure=e;throw e}
  }
  private Void capture([Str:Obj?][] reads)
  {
    reads.each |row|
    {
      readCount++
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
    // Clear before visiting children: repeated aliases and cycles terminate,
    // without mutating configuration containers borrowed from the catalog.
    if(value is Map) {children:=((Map)value).vals;((Map)value).clear;children.each |child| {dropGraph(child)}}
    else {children:=((List)value).dup;((List)value).clear;children.each |child| {dropGraph(child)}}
  }
  private Void check()
  {if(closed) throw ArgErr("reportConsumerClosed");if(failure!=null) throw failure;if(stateClosed && !done) throw ArgErr("reportConsumerClosed")}
  private Void closeState()
  {ctx=null;report=null;cursors.clear;ledger.clear;meters.clear;covers.clear;daily.clear;stateClosed=true}
  private Void closeOutput()
  {
    dropGraph(result);dropGraph(evidence)
    frozenMeters.each |value| {if(!value.sources.isEmpty) value.sources.clear;value.value=null;value.quality="ownerExpired"}
    frozenMeters.clear;periods.clear;closed=true
  }
}

** COP consumes original hourly operands. Raw quantity folds precede each
** hour's unit/reliability transformation; normalized sums are never inferred
** by scaling a final raw sum. No source frame or tick survives addFrame.
internal class EnerCubixCopConsumer
{
  new make(Str:Obj? q,Str:Obj? item,EnerCubixCockpitCatalog catalog,EnerCubixPreparedOwner state,EnerCubixPreparedOwner output)
  {
    if(!q.isImmutable || !item.isImmutable || state===output || state.budget!==output.budget || state.budget!==catalog.owner.budget || q["perArea"]==true) throw ArgErr("copConsumerPlan")
    this.q=q;this.state=state;this.output=output
    from=DateTime.fromIso(q["from"].toStr).toTimeZone(catalog.tz);to=DateTime.fromIso(q["to"].toStr).toTimeZone(catalog.tz);at=from
    if(to<=from || to>DateTime.fromIso(q["asOf"].toStr)) throw ArgErr("copConsumerRange")
    reason=item["reason"] as Str;factor=EnerCubixMath.num(item["factor"]) ?: 1f
    calc=EnerCubixPreparedOwner(state.budget)
    state.watch |->Void| {calc.close;cursor=null;report=null;ctx=null;rawNumerator=null;rawDenominator=null;stateClosed=true};state.hold(14)
    output.watch |->Void| {drop(result);expire(numerator);expire(denominator);result.clear;outputClosed=true}
    output.hold(12);borrowed=catalog.protectedRoots;catalog.bind(output)
    ctx=EnerCubixContext.shared(catalog,q["dimension"].toStr,q["spaceSource"]=="fin",calc);ctx.orderWarnings
    calc.hold(2+q.size);request:=q.dup.set("kind","cop")
    report=EnerCubixReport(ctx,request,from,to,"cop",q["period"].toStr,"energy",calc)
    cursor=report.openLine(((Map)item["config"])["id"].toStr,"")
    stableReport:=report;stableLine:=cursor.line
    output.watch |->Void| {stableReport.clearFrames;stableLine.consumedTotals?.clear;stableLine.consumedTotals=null}
    period=EnerCubixPeriodConsumer(cursor.line,from,to,q["period"].toStr,calc,output)
    rawNumerator=EnerCubixValueFold.strict(calc);rawDenominator=EnerCubixValueFold.strict(calc)
  }
  private Str:Obj? q
  private EnerCubixPreparedOwner state
  private EnerCubixPreparedOwner output
  private EnerCubixPreparedOwner calc
  private DateTime from
  private DateTime to
  private DateTime at
  private Str? reason
  private Float factor
  private EnerCubixContext? ctx
  private EnerCubixReport? report
  private EnerCubixLineCursor? cursor
  private EnerCubixPeriodConsumer period
  private EnerCubixValueFold? rawNumerator
  private EnerCubixValueFold? rawDenominator
  private EnerCubixValue? numerator
  private EnerCubixValue? denominator
  private Str:Obj? result := [:]
  private Obj[] borrowed := [,]
  private Bool done := false
  private Bool stateClosed := false
  private Bool outputClosed := false
  private Err? failure

  Void addFrame(Str:EnerCubixHistoryData histories,EnerCubixPreparedOwner frame)
  {
    check
    if(done || stateClosed || at>=to || frame.budget!==state.budget) throw ArgErr("copConsumerFrame")
    try
    {
      frame.hold(32);report.beginFrame(frame,histories);ctx.warningScope(0,0,at.ticks)
      tick:=cursor.next
      rawNumerator.add(tick.numerator ?: EnerCubixValue());rawDenominator.add(tick.denominator ?: EnerCubixValue())
      tick.numerator=tick.numerator?.scale(factor)
      if(reason!=null) tick.numerator=EnerCubixValue(null,reason)
      else if(tick.numerator?.value==null || tick.denominator?.value==null || tick.numerator?.reliable!=true || tick.denominator?.reliable!=true)
        tick.numerator=EnerCubixValue(null,EnerCubixValue.worse(tick.numerator?.quality ?: "missing",tick.denominator?.quality ?: "missing"),tick.numerator?.sources ?: Str[,])
      period.add(tick);at=tick.end
    }
    catch(Err e) {failure=e;throw e}
  }
  Str:Obj? finish(Str[] previousWarnings := Str[,])
  {
    check;if(done) return result
    if(stateClosed || at!=to) throw ArgErr("copConsumerIncomplete")
    try
    {
      period.finish;line:=cursor.finish
      numerator=freeze(rawNumerator);denominator=freeze(rawDenominator)
      ratio:=period.total
      if(ratio.value==null && reason!=null)
      {output.hold(12);expire(numerator);expire(denominator);numerator=EnerCubixValue(null,reason);denominator=EnerCubixValue(null,reason)}
      output.hold(6);line.consumedTotals=Str:EnerCubixValue[:]
      ["value","known","baseValue","baseKnown"].each |mode| {line.consumedTotals[mode]=period.total(mode)}
      n:=0;bucket:=EnerCubixMath.bucket(from,q["period"].toStr)
      while(bucket<to) {n++;bucket=EnerCubixMath.nextBucket(bucket,q["period"].toStr)}
      ownWarnings:=ctx.orderedWarnings
      output.hold(1024+80*n+2*(previousWarnings.size+ownWarnings.size))
      warnings:=previousWarnings.dup;ownWarnings.each |warning| {if(!warnings.contains(warning)) warnings.add(warning)}
      scratch:=EnerCubixPreparedOwner(output.budget)
      try
      {
        scratch.hold(64+16*(n+1))
        data:=report.finishFrames([line],[line.id:["rows":period.periods]],Str:EnerCubixValue[:],Str:[Str:Obj?][:],Str:Obj?[:])
        data["warnings"]=warnings
        result=Str:Obj?["report":data,"numerator":numerator,"denominator":denominator,"ratio":ratio]
      }
      finally {scratch.close}
      done=true;return result
    }
    catch(Err e) {failure=e;throw e}
  }
  private EnerCubixValue freeze(EnerCubixValueFold fold)
  {
    scratch:=EnerCubixPreparedOwner(state.budget)
    try {scratch.hold(4+3*fold.sourceCount);output.hold(6+fold.sourceCount);return fold.finish}
    finally {scratch.close}
  }
  private Void expire(EnerCubixValue? value) {if(value!=null) {value.sources.clear;value.value=null;value.quality="ownerExpired"}}
  private Void drop(Obj? value)
  {
    if(value isnot Map && value isnot List) return
    if(borrowed.any |root| {root===value}) return
    if(value is Map) {((Map)value).each |child| {drop(child)};((Map)value).clear}
    else {((List)value).each |child| {drop(child)};((List)value).clear}
  }
  private Void check()
  {if(failure!=null) throw failure;if(outputClosed || (stateClosed && !done)) throw ArgErr("copConsumerClosed");state.budget.deadline.check}
}

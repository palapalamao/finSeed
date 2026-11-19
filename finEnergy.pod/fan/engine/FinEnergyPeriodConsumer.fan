** One active period, independent whole-range folds, and detached output values.
** Neither ticks nor expired history readers survive add. Returned rows are
** borrowed from the output owner until it closes, independently of fold state.
internal class FinEnergyPeriodConsumer
{
  new make(FinEnergyLine definition,DateTime from,DateTime to,Str gran,
    FinEnergyPreparedOwner state,FinEnergyPreparedOwner output,Bool emitPeriods := true,Bool sharedBase := false)
  {
    if(state.budget !== output.budget || to<=from || !definition.ticks.isEmpty || !["hour","day","week","month","year"].contains(gran)) throw ArgErr("periodConsumerPlan")
    if(sharedBase && (definition.gauge || definition.ratio || definition.leak || definition.reference)) throw ArgErr("periodSharedBasePlan")
    this.sharedBase=sharedBase
    this.definition=definition;this.to=to;this.gran=gran;at=from;stateOwner=state;outputOwner=output;this.emitPeriods=emitPeriods
    state.watch |->Void| {closeState};output.watch |->Void| {closeOutput}
    state.hold(26);output.hold(2)
    initializeFolds(all,state)
  }
  private static const Str[] modes := ["value","known","baseValue","baseKnown"].toImmutable
  private static const Str[] primaryModes := ["value","known"]
  private const Bool sharedBase
  private Str[] reductionModes() {sharedBase ? primaryModes : modes}
  private Void initializeFolds(Str:FinEnergyLineFold folds,FinEnergyPreparedOwner owner)
  {reductionModes.each |mode| {folds[mode]=FinEnergyLineFold(definition,mode,owner)};if(sharedBase) {folds["baseValue"]=folds["value"];folds["baseKnown"]=folds["known"]}}
  private FinEnergyLine? definition
  private const DateTime to
  private const Str gran
  private const Bool emitPeriods
  private FinEnergyPreparedOwner stateOwner
  private FinEnergyPreparedOwner outputOwner
  private DateTime at
  private DateTime? bucket
  private DateTime? firstAt
  private DateTime? lastAt
  private Int samples := 0
  private Int knownSamples := 0
  private Str:FinEnergyLineFold all := [:]
  private Str:FinEnergyLineFold active := [:]
  private [Str:Obj?][] rows := [,]
  private Str:FinEnergyValue totals := [:]
  private FinEnergyPreparedOwner? periodOwner
  private Bool stateClosed := false
  private Bool outputClosed := false
  private Bool finished := false
  private Err? failure

  Void add(FinEnergyTick tick)
  {
    checkState
    if(tick.ts != at || tick.end<=tick.ts || tick.end>to) throw ArgErr("periodConsumerTick")
    try
    {
      if(sharedBase && ((tick.baseValue!=null && tick.baseValue!==tick.value) || (tick.baseKnown!=null && tick.baseKnown!==tick.known))) throw ArgErr("periodSharedBaseTick")
      if(emitPeriods)
      {
        next:=FinEnergyMath.bucket(tick.ts,gran)
        if(bucket != null && next != bucket) seal
        if(bucket == null)
        {
          periodOwner=FinEnergyPreparedOwner(stateOwner.budget);periodOwner.hold(4)
          initializeFolds(active,periodOwner)
          bucket=next;firstAt=tick.ts;samples=0;knownSamples=0
        }
      }
      reductionModes.each |mode| {all[mode].add(tick);if(emitPeriods) active[mode].add(tick)}
      if(emitPeriods) {samples++;if(tick.known?.value != null) knownSamples++;lastAt=tick.end}
      at=tick.end
    }
    catch(Err e) {failure=e;throw e}
  }

  Void finish()
  {
    if(finished) {checkOutput;return}
    checkState
    if(at != to) throw ArgErr("periodConsumerIncomplete")
    try
    {
      seal
      capture(all,4) |values| {modes.each |mode| {totals[mode]=values[mode]}}
      finished=true
    }
    catch(Err e) {failure=e;throw e}
  }
  [Str:Obj?][] periods() {checkOutput;return rows}
  FinEnergyValue total(Str mode := "value") {checkOutput;return totals[mode] ?: throw ArgErr("lineFoldMode")}

  private Void seal()
  {
    if(bucket == null) return
    capture(active,11) |values|
    {
      row:=Str:Obj?["ts":bucket.toIso,"from":firstAt.toIso,"to":lastAt.toIso,"samples":samples,"knownSamples":knownSamples]
      modes.each |mode| {row[mode]=values[mode]};rows.add(row)
    }
    old:=periodOwner;active.clear;periodOwner=null;bucket=null;firstAt=null;lastAt=null
    old.close
  }
  private Void capture(Str:FinEnergyLineFold folds,Int entries,|Str:FinEnergyValue| consume)
  {
    scratch:=FinEnergyPreparedOwner(stateOwner.budget)
    values:=Str:FinEnergyValue[:]
    try
    {
      temporary:=5;retained:=entries
      reductionModes.each |mode| {temporary+=folds[mode].outputScratchEntries;retained+=folds[mode].outputEntries}
      scratch.hold(temporary);outputOwner.hold(retained)
      reductionModes.each |mode| {values[mode]=folds[mode].finish}
      if(sharedBase) {values["baseValue"]=values["value"];values["baseKnown"]=values["known"]}
      consume(values)
    }
    finally {values.clear;scratch.close}
  }
  private Void checkState()
  {
    if(failure != null) throw failure
    if(stateClosed || outputClosed || finished) throw ArgErr("periodConsumerClosed")
    stateOwner.budget.deadline.check
  }
  private Void checkOutput()
  {
    if(outputClosed) throw ArgErr("periodConsumerClosed")
    if(failure != null) throw failure
    if(!finished) throw ArgErr("periodConsumerIncomplete")
  }
  private Void closeState()
  {
    active.clear;all.clear;definition=null
    periodOwner?.close;periodOwner=null;stateClosed=true
  }
  private Void closeOutput()
  {
    rows.each |row| {modes.each |mode| {clearValue(row[mode] as FinEnergyValue)};row.clear}
    rows.clear;totals.each |value| {clearValue(value)};totals.clear;outputClosed=true
  }
  private Void clearValue(FinEnergyValue? value)
  {if(value != null) {if(!value.sources.isEmpty) value.sources.clear;value.value=null;value.quality="ownerExpired"}}
}

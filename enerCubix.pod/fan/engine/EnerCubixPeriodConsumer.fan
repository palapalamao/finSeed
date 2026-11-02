** One active period, independent whole-range folds, and detached output values.
** Neither ticks nor expired history readers survive add. Returned rows are
** borrowed from the output owner until it closes, independently of fold state.
internal class EnerCubixPeriodConsumer
{
  new make(EnerCubixLine definition,DateTime from,DateTime to,Str gran,
    EnerCubixPreparedOwner state,EnerCubixPreparedOwner output,Bool emitPeriods := true)
  {
    if(state.budget !== output.budget || to<=from || !definition.ticks.isEmpty || !["hour","day","week","month","year"].contains(gran)) throw ArgErr("periodConsumerPlan")
    this.definition=definition;this.to=to;this.gran=gran;at=from;stateOwner=state;outputOwner=output;this.emitPeriods=emitPeriods
    state.watch |->Void| {closeState};output.watch |->Void| {closeOutput}
    state.hold(26);output.hold(2)
    modes.each |mode| {all[mode]=EnerCubixLineFold(definition,mode,state)}
  }
  private static const Str[] modes := ["value","known","baseValue","baseKnown"].toImmutable
  private EnerCubixLine? definition
  private const DateTime to
  private const Str gran
  private const Bool emitPeriods
  private EnerCubixPreparedOwner stateOwner
  private EnerCubixPreparedOwner outputOwner
  private DateTime at
  private DateTime? bucket
  private DateTime? firstAt
  private DateTime? lastAt
  private Int samples := 0
  private Int knownSamples := 0
  private Str:EnerCubixLineFold all := [:]
  private Str:EnerCubixLineFold active := [:]
  private [Str:Obj?][] rows := [,]
  private Str:EnerCubixValue totals := [:]
  private EnerCubixPreparedOwner? periodOwner
  private Bool stateClosed := false
  private Bool outputClosed := false
  private Bool finished := false
  private Err? failure

  Void add(EnerCubixTick tick)
  {
    checkState
    if(tick.ts != at || tick.end<=tick.ts || tick.end>to) throw ArgErr("periodConsumerTick")
    try
    {
      if(emitPeriods)
      {
        next:=EnerCubixMath.bucket(tick.ts,gran)
        if(bucket != null && next != bucket) seal
        if(bucket == null)
        {
          periodOwner=EnerCubixPreparedOwner(stateOwner.budget);periodOwner.hold(4)
          modes.each |mode| {active[mode]=EnerCubixLineFold(definition,mode,periodOwner)}
          bucket=next;firstAt=tick.ts;samples=0;knownSamples=0
        }
      }
      modes.each |mode| {all[mode].add(tick);if(emitPeriods) active[mode].add(tick)}
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
  EnerCubixValue total(Str mode := "value") {checkOutput;return totals[mode] ?: throw ArgErr("lineFoldMode")}

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
  private Void capture(Str:EnerCubixLineFold folds,Int entries,|Str:EnerCubixValue| consume)
  {
    scratch:=EnerCubixPreparedOwner(stateOwner.budget)
    values:=Str:EnerCubixValue[:]
    try
    {
      temporary:=5;retained:=entries
      modes.each |mode| {temporary+=folds[mode].outputScratchEntries;retained+=folds[mode].outputEntries}
      scratch.hold(temporary);outputOwner.hold(retained)
      modes.each |mode| {values[mode]=folds[mode].finish}
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
    rows.each |row| {modes.each |mode| {clearValue(row[mode] as EnerCubixValue)};row.clear}
    rows.clear;totals.each |value| {clearValue(value)};totals.clear;outputClosed=true
  }
  private Void clearValue(EnerCubixValue? value)
  {if(value != null) {if(!value.sources.isEmpty) value.sources.clear;value.value=null;value.quality="ownerExpired"}}
}

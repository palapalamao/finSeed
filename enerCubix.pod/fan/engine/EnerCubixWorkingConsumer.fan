** Two calendar-classified folds. Empty groups are genuine zero; missing data
** within a nonempty group keeps the original strict/known quality semantics.
internal class EnerCubixWorkingConsumer
{
  new make(EnerCubixLine line,EnerCubixPreparedOwner state,EnerCubixPreparedOwner output)
  {
    if(state === output || state.budget !== output.budget) throw ArgErr("workingConsumerOwner")
    this.state=state;this.output=output
    state.watch |->Void| {values.clear;known.clear;counts.clear;closed=true};state.hold(10)
    (0..1).each |i| {values.add(EnerCubixLineFold(line,"value",state));known.add(EnerCubixLineFold(line,"known",state))}
  }
  private EnerCubixPreparedOwner state
  private EnerCubixPreparedOwner output
  private EnerCubixLineFold[] values := [,]
  private EnerCubixLineFold[] known := [,]
  private Int[] counts := [0,0]
  private Bool closed := false
  private Bool done := false

  Void add(EnerCubixTick tick,Bool working)
  {
    if(closed || done) throw ArgErr("workingConsumerClosed")
    i:=working ? 0 : 1;counts[i]++;values[i].add(tick);known[i].add(tick)
  }
  [Str:Obj?][] finish()
  {
    if(closed || done) throw ArgErr("workingConsumerClosed")
    scratch:=EnerCubixPreparedOwner(state.budget)
    rows:=[Str:Obj?][,]
    // Admit both returned value/source graphs and all temporary finish graphs
    // before creating any of them. There are exactly two bins, not one per hour.
    retained:=11;temporary:=5
    (0..1).each |i|
    {
      retained+=values[i].outputEntries+known[i].outputEntries
      temporary+=values[i].outputScratchEntries+known[i].outputScratchEntries
    }
    try
    {
      scratch.hold(temporary);output.hold(retained)
      (0..1).each |i| {rows.add(["value":counts[i]==0 ? EnerCubixValue(0f,"ok") : values[i].finish,"known":counts[i]==0 ? EnerCubixValue(0f,"ok") : known[i].finish,"samples":counts[i]])}
      output.watch |->Void|
      {
        rows.each |row|
        {
          ["value","known"].each |key| {v:=(EnerCubixValue)row[key];if(!v.sources.isEmpty) v.sources.clear;v.value=null;v.quality="ownerExpired"}
          row.clear
        }
        rows.clear
      }
      done=true;return rows
    }
    finally {scratch.close}
  }
}

** Fixed hour-of-day and tariff-band folds. The original tick sequence, gauge
** weighting and COP operand sums are retained without storing any ticks.
internal class EnerCubixDailyConsumer
{
  new make(EnerCubixLine line,EnerCubixPreparedOwner state,EnerCubixPreparedOwner output)
  {
    if(state === output || state.budget !== output.budget) throw ArgErr("dailyConsumerOwner")
    this.line=line;this.output=output
    // Parent retains the closed child-owner handle until its own cleanup.
    state.hold(5);local:=state.fork;this.state=local
    try
    {
      state.watch |->Void| {local.close}
      local.watch |->Void| {hours.clear;bands.clear;classified.clear;this.line=null;closed=true}
      local.hold(8)
    }
    catch(Err e) {local.close;throw e}
  }
  private EnerCubixLine? line
  private EnerCubixPreparedOwner state
  private EnerCubixPreparedOwner output
  private Int:EnerCubixDailyBin hours := [:]
  private Str:EnerCubixDailyBin bands := [:]
  private Str[] classified := [,]
  private Bool closed := false
  private Bool done := false

  Void add(EnerCubixTick tick,Str band)
  {
    if(closed || done) throw ArgErr("dailyConsumerClosed")
    if(!["sharp","peak","flat","valley","mixed","unknown"].contains(band)) throw ArgErr("dailyConsumerBand")
    if(!hours.containsKey(tick.ts.hour)) {state.hold(1);hours[tick.ts.hour]=EnerCubixDailyBin(line,false,state)}
    if(!bands.containsKey(band)) {state.hold(2);bands[band]=EnerCubixDailyBin(line,true,state);classified.add(band)}
    hours[tick.ts.hour].add(tick,band);bands[band].add(tick,band)
  }
  Str:Obj? finish()
  {
    if(closed || done) throw ArgErr("dailyConsumerClosed")
    output.hold(6+24+bands.size+classified.size)
    hourRows:=[Str:Obj?][,];bandRows:=Str:[Str:Obj?][:]
    (0..23).each |hour| {hourRows.add(snapshot(hours[hour]).set("hour",hour))}
    bands.each |bin,key| {bandRows[key]=snapshot(bin)}
    out:=Str:Obj?["hours":hourRows,"bands":bandRows,"classified":classified.dup]
    output.watch |->Void|
    {
      hourRows.each |r| {clear(r)};bandRows.each |r| {clear(r)}
      hourRows.clear;bandRows.clear;((List)out["classified"]).clear;out.clear
    }
    done=true;state.close;return out
  }
  internal Int stateEntries() {state.entries}

  private Str:Obj? snapshot(EnerCubixDailyBin? bin)
  {
    // Field links, copied values/sources, band list, plus temporary finish values.
    sources:=(bin?.sourceEntries ?: 0)
    scratch:=EnerCubixPreparedOwner(state.budget)
    try
    {
      scratch.hold(16+3*sources);output.hold(18+sources)
      return ["value":bin?.value ?: EnerCubixValue(),"known":bin?.known ?: EnerCubixValue(),"samples":bin?.samples ?: 0,"knownSamples":bin?.knownSamples ?: 0,"band":bin?.band ?: "unknown"]
    }
    finally {scratch.close}
  }
  private Void clear(Str:Obj? row)
  {
    ["value","known"].each |key|
    {value:=(EnerCubixValue)row[key];if(!value.sources.isEmpty) value.sources.clear;value.value=null;value.quality="ownerExpired"}
    row.clear
  }
}

internal class EnerCubixDailyBin
{
  new make(EnerCubixLine line,Bool intervalTotal,EnerCubixPreparedOwner state)
  {
    state.watch |->Void| {hour=null;interval=null;observed=null;firstBand=null;samples=0;knownSamples=0;closed=true};state.hold(8)
    if(intervalTotal) interval=EnerCubixValueFold.strict(state)
    else hour=EnerCubixLineFold(line,"value",state)
    observed=EnerCubixLineFold(line,"known",state)
  }
  private EnerCubixLineFold? hour
  private EnerCubixValueFold? interval
  private EnerCubixLineFold? observed
  private Bool closed := false
  Int samples := 0
  Int knownSamples := 0
  private Str? firstBand
  private Bool mixed := false
  Void add(EnerCubixTick tick,Str band := "unknown")
  {
    if(closed) throw ArgErr("dailyConsumerClosed")
    samples++;if(tick.known?.value != null) knownSamples++
    if(firstBand == null) firstBand=band
    else if(firstBand != band) mixed=true
    if(interval != null) interval.add(tick.value)
    else hour.add(tick)
    observed.add(tick)
  }
  Str band() {mixed ? "mixed" : (firstBand ?: "unknown")}
  EnerCubixValue value() {interval?.finish ?: hour.finish}
  EnerCubixValue known() {observed.finish}
  Int sourceEntries() {(interval == null ? hour.outputEntries : 4+interval.sourceCount)+observed.outputEntries}
}

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
    // Out map(4), hour vector(25), band map(1+B), classified(1+C),
    // and the 24 hour fields. Each snapshot admits its own detached values.
    output.hold(55+bands.size+classified.size)
    hourRows:=[Str:Obj?][,];bandRows:=Str:[Str:Obj?][:]
    Str[]? previous
    (0..23).each |hour|
    {row:=snapshot(hours[hour],previous).set("hour",hour);previous=((EnerCubixValue)row["value"]).sources;hourRows.add(row)}
    bands.each |bin,key|
    {row:=snapshot(bin,previous);previous=((EnerCubixValue)row["value"]).sources;bandRows[key]=row}
    out:=Str:Obj?["hours":hourRows,"bands":bandRows,"classified":classified.dup]
    output.watch |->Void|
    {
      hourRows.each |r| {clear(r)};bandRows.each |r| {clear(r)}
      hourRows.clear;bandRows.clear;((List)out["classified"]).clear;out.clear
    }
    done=true;state.close;return out
  }
  internal Int stateEntries() {state.entries}

  private Str:Obj? snapshot(EnerCubixDailyBin? bin,Str[]? previous)
  {
    // Field links, copied values/sources, band list, plus temporary finish values.
    sources:=(bin?.sourceEntries ?: 0)
    scratch:=EnerCubixPreparedOwner(state.budget)
    try
    {
      // Map with five fields(6), two values(6), two source headers(2).
      // sourceEntries includes the eight value/header entries already, and
      // ratio operands may overbound the distinct sources of their quotient.
      retained:=bin==null ? 14 : 6+sources
      scratch.hold(16+3*sources);output.hold(retained)
      value:=bin?.value ?: EnerCubixValue();known:=bin?.known ?: EnerCubixValue()
      output.release(retained-(14+value.sources.size+known.sources.size))
      // Only borrow ordered-equal vectors already owned by this output. Input
      // folds always return fresh arrays. Clear/sever the discarded array
      // before releasing its actual header and entries; never release a peer.
      if(previous!=null && value.sources!==previous && value.sources==previous)
      {old:=value.sources;n:=1+old.size;value.sources=previous;old.clear;output.release(n)}
      if(known.sources!==value.sources && known.sources==value.sources)
      {old:=known.sources;n:=1+old.size;known.sources=value.sources;old.clear;output.release(n)}
      return ["value":value,"known":known,"samples":bin?.samples ?: 0,"knownSamples":bin?.knownSamples ?: 0,"band":bin?.band ?: "unknown"]
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
    // Ordinary energy is an ordered scalar sum. Keep the line wrapper only
    // where its duration weighting or COP operands actually carry state.
    if(intervalTotal || (!line.gauge && !line.ratio)) interval=EnerCubixValueFold.strict(state)
    else hour=EnerCubixLineFold(line,"value",state)
    observed=EnerCubixValueFold.known(state)
  }
  private EnerCubixLineFold? hour
  private EnerCubixValueFold? interval
  private EnerCubixValueFold? observed
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
    observed.add(tick.known ?: EnerCubixValue())
  }
  Str band() {mixed ? "mixed" : (firstBand ?: "unknown")}
  EnerCubixValue value() {interval?.finish ?: hour.finish}
  EnerCubixValue known() {observed.finish}
  Int sourceEntries() {(interval == null ? hour.outputEntries : 4+interval.sourceCount)+4+observed.sourceCount}
}

** One local day of provisional points, then only the final heatmap cells or
** excluded-day reason. Neither input ticks nor hourly report DTOs are retained.
internal class EnerCubixHeatmapConsumer
{
  new make(EnerCubixLine definition,DateTime from,DateTime to,DateTime cutoff,
    EnerCubixPreparedOwner state,EnerCubixPreparedOwner output)
  {
    if(state === output || state.budget !== output.budget || to<=from || definition.ratio || definition.gauge || !definition.ticks.isEmpty) throw ArgErr("heatmapConsumerPlan")
    line=definition;this.from=from;this.to=to;this.cutoff=cutoff;at=from;this.state=state;this.output=output
    state.watch |->Void| {closeDay(false);line=null;stateClosed=true};state.hold(18)
    output.watch |->Void|
    {
      cells.each |row| {((List)row["sourceIds"]).clear;row.clear};excluded.each |row| {row.clear}
      cells.clear;excluded.clear;data.clear;outputClosed=true
    }
    output.hold(5);data=Str:Obj?["heatmap":cells,"excludedDays":excluded]
  }
  private EnerCubixLine? line
  private const DateTime from
  private const DateTime to
  private const DateTime cutoff
  private DateTime at
  private EnerCubixPreparedOwner state
  private EnerCubixPreparedOwner output
  private EnerCubixPreparedOwner? dayOwner
  private Date? date
  private [Str:Obj?][] pending := [,]
  private [Str:Obj?][] cells := [,]
  private [Str:Obj?][] excluded := [,]
  private Str:Obj? data := [:]
  private Bool stateClosed := false
  private Bool outputClosed := false
  private Bool done := false
  private Err? failure

  Void add(EnerCubixTick tick)
  {
    check
    end:=EnerCubixMath.floorHour(at)+1hr;if(end>to) end=to
    if(done || tick.ts!=at || tick.end!=end) throw ArgErr("heatmapConsumerTick")
    try
    {
      bucket:=EnerCubixMath.floorHour(tick.ts).toTimeZone(from.tz)
      if(date!=null && date!=bucket.date) seal
      if(date==null) {dayOwner=EnerCubixPreparedOwner(state.budget);dayOwner.hold(3);date=bucket.date}
      hour:=EnerCubixPreparedOwner(state.budget)
      try
      {
        // Use the same single-hour reduction as Report.append, including
        // filtered-null and first-source order, rather than copying tick.value.
        fold:=EnerCubixLineFold(line,"value",hour);fold.add(tick)
        dayOwner.hold(3+fold.outputEntries);hour.hold(fold.outputScratchEntries)
        v:=fold.finish
        pending.add(["ts":bucket.toIso,"value":v.value,"quality":v.quality,"sourceIds":v.sources])
      }
      finally {hour.close}
      at=tick.end
    }
    catch(Err e) {failure=e;throw e}
  }

  Str:Obj? finish()
  {
    check
    if(done) return data
    if(at!=to || stateClosed) throw ArgErr("heatmapConsumerIncomplete")
    try {seal;done=true;return data}
    catch(Err e) {failure=e;throw e}
  }
  ** The work has copied row references into its completed public vectors.
  ** Retire only these duplicate private vector links, never the shared rows or
  ** source arrays. Their original output charge now protects the public graph.
  internal Void retirePrivateLinks()
  {
    if(!done || !stateClosed || outputClosed) throw ArgErr("heatmapPublicTransfer")
    n:=cells.size+excluded.size+data.size
    cells.clear;excluded.clear;data.clear;output.release(n)
  }
  private Void seal()
  {
    if(date==null) return
    start:=date.toDateTime(Time.defVal,from.tz);end:=(date+1day).toDateTime(Time.defVal,from.tz)
    complete:=start>=from && end<=to && end<=cutoff && pending.size==(end-start).ticks/1hr.ticks && pending.all |p| {p["value"]!=null && !["filtered","substituted","na","incompleteInterval"].contains(p["quality"])}
    if(complete)
    {
      // Nine cell fields, map and list link, plus the transferred source array.
      // Admit the whole day before copying any cell, so failure cannot publish
      // a partial complete day. Day-owned links expire only after transfer.
      entries:=0
      pending.each |p,i|
      {
        ids:=(List)p["sourceIds"];seen:=false
        for(j:=0;j<i;j++) {if(pending[j]["sourceIds"]==ids) {seen=true;break}}
        // Every hourly cell keeps its full map and list link. Only equal,
        // ordered source vectors within this one day share the same array.
        entries+=11+(seen ? 0 : 1+ids.size)
      }
      output.hold(entries)
      firstCell:=cells.size
      pending.each |p,i|
      {
        ids:=(List)p["sourceIds"]
        for(j:=0;j<i;j++) {if(pending[j]["sourceIds"]==ids) {ids=(List)cells[firstCell+j]["sourceIds"];break}}
        ts:=DateTime.fromIso(p["ts"].toStr).toTimeZone(from.tz)
        cells.add(["seriesId":line.id,"nodeId":line.nodeId,"date":date.toStr,"hour":ts.hour,"ts":p["ts"],"value":p["value"],"unit":line.unit,"quality":p["quality"],"sourceIds":ids])
      }
      closeDay(true,firstCell)
    }
    else {output.hold(5);excluded.add(Str:Obj?["seriesId":line.id,"date":date.toStr,"reasonCode":"INCOMPLETE_DAY"]);closeDay(false)}
  }
  private Void closeDay(Bool transferred,Int firstCell := 0)
  {
    pending.each |p|
    {
      ids:=(List)p["sourceIds"];retained:=false
      if(transferred) for(i:=firstCell;i<cells.size;i++) {if(cells[i]["sourceIds"]===ids) {retained=true;break}}
      if(!retained) ids.clear
      p.clear
    }
    pending.clear;dayOwner?.close;dayOwner=null;date=null
  }
  private Void check()
  {
    if(failure!=null) throw failure
    if(outputClosed || (stateClosed && !done)) throw ArgErr("heatmapConsumerClosed")
    state.budget.deadline.check
  }
}

using haystack

** Incremental own-point full-report cleaning. No raw/detail graph is retained;
** scalar transitions share the native cleaning core and keep previous across
** every callback/batch. Public diagnostics retain their original sorted quota.
internal class FinEnergyFullCleaning
{
  new make(Dict point,Dict config,DateTime from,DateTime to,Int limit:=1000000,[Str:Int]? timing:=null)
  {
    if(from!=FinEnergyMath.floorHour(from)) throw ArgErr("unalignedFullCleaning")
    this.point=point;this.config=config;this.from=from;this.to=to;this.limit=limit;this.timing=timing
    validated=FinEnergyCleaning.cursorConfig(point,config)
    unit=point["unit"]?.toStr ?: ""
    profileId=(config["finEnergyProfileRef"] as Ref)?.id
    profileVersion=(config["finEnergyProfileVersion"] as Number)?.toInt
    parameters=FinEnergyCleaning.jsonConfig(config)
  }
  private Dict point
  private Dict config
  private Dict validated
  private DateTime from
  private DateTime to
  private Int limit
  private [Str:Int]? timing
  private Str unit
  private Str? profileId
  private Int? profileVersion
  private Str:Obj? parameters
  private HisItem? previous
  private DateTime? last
  private FinEnergyInterval[] intervals := [,]
  private FinEnergyIntervalClock clock := FinEnergyIntervalClock()
  private [Str:Obj?][] details := [,]
  private DateTime[] detailTimes := [,]
  private Int seen := 0
  private Int inputCount := 0
  private Int selected := 0
  private Int valid := 0
  private Int nulls := 0
  private Int na := 0
  private Int filtered := 0
  private Int substituted := 0
  private Int validTicks := 0
  private Int events := 0
  private Int rolloverCount := 0
  private Int rejectedCount := 0
  private Int removedNACount := 0
  private Int substitutedCount := 0
  private Bool finished := false
  internal Int processingNs := 0

  Void push(HisItem item)
  {
    if(finished) throw ArgErr("fullCleaningFinished")
    if(seen>=limit) throw ArgErr("History exceeds $limit raw samples")
    // Bulk clean sorts stable. A native provider that does not emit that order
    // cannot use this projection; its caller reopens the original bulk reader.
    if(last!=null && item.ts<last) throw FinEnergyFullCleaningOrderErr()
    seen++;last=item.ts
    if(item.ts>=from && item.ts<to) inputCount++
    started:=timing==null ? 0 : Duration.nowTicks
    step:=FinEnergyCleaning.cursorStep(unit,validated,item,previous)
    if(step.reason!="removedNA") previous=item
    cleaned:=timing==null ? 0 : Duration.nowTicks
    end:=FinEnergyIntervalClock.serialized(item.ts).toTimeZone(from.tz)
    seconds:=step.intervalSeconds ?: 0f
    start:=end-Duration((seconds*1sec.ticks.toFloat).toInt)
    active:=step.emitted && seconds>0f && end>from && start<to
    if(active)
    {
      selected++;q:=step.quality;number:=step.number;type:=step.valueType
      intervals.add(clock.interval(start,end,number,q,type))
      if(number!=null) valid++
      if(type=="null") nulls++
      if(type=="na") na++
      if(q=="filtered") filtered++
      if(step.substituted) substituted++
      hour:=FinEnergyMath.floorHour(start)
      if(hour>=from && hour<to && (hour-from).ticks % 1hr.ticks==0 && end<=hour+1hr && number!=null && !step.substituted && q!="filtered") validTicks+=(end-start).ticks
    }
    eventActive:=step.emitted && seconds>0f ? (end>from && start<to) : (end>=from && end<to)
    if(eventActive && !["ok","noPrevious"].contains(step.reason)) event(step,end)
    if(timing!=null)
    {
      ended:=Duration.nowTicks;add("cleanNs",cleaned-started);add("normalizeNs",ended-cleaned)
      processingNs+=ended-started
    }
  }

  private Void event(FinEnergyCleanStep step,DateTime at)
  {
    events++
    if(step.reason=="rollover") rolloverCount++
    else if(step.emitted) rejectedCount++
    if(step.reason=="removedNA") removedNACount++
    if(step.substituted) substitutedCount++
    if(details.size==1000 && at>=detailTimes.last) return
    row:=step.detail
    row["pointId"]=point.id.id;row["unit"]=unit
    reason:=step.reason
    row["rule"]=["rollover","rolloverOutOfRange"].contains(reason) ? "hisTotalizedRollover" : (["deltaMin","deltaMax","derivMin","derivMax","timeMax"].contains(reason) ? reason : null)
    if(profileId!=null) row["profileId"]=profileId
    if(profileVersion!=null) row["profileVersion"]=profileVersion
    row["parameters"]=parameters
    lo:=0;hi:=details.size
    while(lo<hi) {mid:=(lo+hi)/2;if(detailTimes[mid]<=at) lo=mid+1;else hi=mid}
    details.insert(lo,row);detailTimes.insert(lo,at)
    if(details.size>1000) {details.removeAt(-1);detailTimes.removeAt(-1)}
  }

  Str:Obj? finish()
  {
    if(finished) throw ArgErr("fullCleaningFinished")
    finished=true;started:=timing==null ? 0 : Duration.nowTicks
    // Keep the bulk summary's original typed-map shape as well as JSON fields.
    Str:Obj? meta:=["inputCount":inputCount,"outputCount":selected,"validCount":valid,"nullCount":nulls,"naCount":na,
      "rolloverCount":rolloverCount,"rejectedCount":rejectedCount,"removedNACount":removedNACount,"substitutedCount":substitutedCount]
    meta.setAll(["pointId":point.id.id,"sourceIds":[point.id.id],"profileId":profileId,"profileVersion":profileVersion,"parameters":parameters,
      "processingScope":"objectIntervals","detailsTruncated":events>details.size,"details":details.map |row->[Str:Obj?]| {FinEnergyHistory.nativeDetail(row)},
      "summary":["filteredCount":filtered,"substitutedCount":substituted,"naCount":na,"intervalCount":selected,"coverage":(validTicks.toFloat/(to-from).ticks.toFloat).min(1f)]])
    out:=Str:Obj?["pointId":point.id.id,"unit":unit,"mode":"interval","quality":"cleaned","rawQuality":"ok","samples":[Str:Obj?][,],"_closedIntervals":FinEnergyClosedIntervals(intervals),"sourceIds":[point.id.id],"cleaning":meta]
    details.clear;detailTimes.clear;intervals.clear;previous=null;last=null
    if(timing!=null) add("normalizeNs",Duration.nowTicks-started)
    return out
  }
  private Void add(Str key,Int n) {timing[key]=(timing[key] ?: 0)+n}
}

internal const class FinEnergyFullCleaningOrderErr : Err
{new make() : super("fullCleaningRequiresSortedSource") {}}

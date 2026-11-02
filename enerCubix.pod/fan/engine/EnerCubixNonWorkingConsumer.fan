** Non-working rule facts consume complete own-primary hours before diagnostics
** are sampled. Only counters and the maximum survive a borrowed source frame.
internal class EnerCubixNonWorkingConsumer
{
  new make(Str:Obj? q,Str:Obj? profile,[Str:Obj?][] records,Str:Obj? boundary,EnerCubixCockpitCatalog catalog,EnerCubixPreparedOwner state,EnerCubixPreparedOwner output)
  {
    if(!q.isImmutable || !profile.isImmutable || !records.isImmutable || !boundary.isImmutable || state===output || state.budget!==output.budget || state.budget!==catalog.owner.budget) throw ArgErr("nonWorkingConsumerPlan")
    this.state=state;this.output=output
    from=DateTime.fromIso(q["from"].toStr).toTimeZone(catalog.tz)
    to:=DateTime.fromIso(q["to"].toStr).toTimeZone(catalog.tz);asOf:=DateTime.fromIso(q["asOf"].toStr).toTimeZone(catalog.tz)
    end=to<asOf ? to : asOf;at=EnerCubixMath.floorHour(from)
    if(end<=from) throw ArgErr("nonWorkingConsumerRange")
    state.hold(40+((List)boundary["meterIds"]).size);ids=EnerCubixMath.strings(boundary["meterIds"])
    state.watch |->Void| {ctx=null;calendar=null;ids.clear;stateClosed=true}
    output.hold(72);output.watch |->Void|
    {calendarDto.clear;inputs.clear;(result["reasonCodes"] as List)?.clear;result.clear;outputClosed=true}
    catalog.bind(output)
    category=EnerCubixMath.strings(q["categoryIds"]).first
    calendar=records.find |r| {r["id"]==profile["calendarRef"] && r["kind"]=="calendar" && EnerCubixBudgetScope.readable(r)}
    if(calendar==null || !EnerCubixCockpitRules.validCalendar(calendar)) {result["reasonCodes"]=["RULE_CALENDAR_INVALID"];return}
    unit=records.find |r| {r["id"]==category}?.get("unit") as Str ?: ""
    factor:=unit.isEmpty || (profile["thresholdUnit"] as Str ?: "").isEmpty ? null : EnerCubixMath.unitFactor(profile["thresholdUnit"].toStr,unit)
    if(factor==null) {result["reasonCodes"]=["RULE_UNIT_INCOMPATIBLE"];return}
    threshold:=EnerCubixMath.num(profile["threshold"])
    if(threshold==null || threshold<0f) throw ArgErr("nonWorkingConsumerThreshold")
    normalized=threshold*factor
    ctx=EnerCubixContext.shared(catalog,q["dimension"].toStr,q["spaceSource"]=="fin",state);ctx.calendar=calendar;configured=true
  }
  private EnerCubixPreparedOwner state
  private EnerCubixPreparedOwner output
  private EnerCubixContext? ctx
  private [Str:Obj?]? calendar
  private Str[] ids := [,]
  private Str category
  private Str unit := ""
  private DateTime from
  private DateTime end
  private DateTime at
  private Float normalized := 0f
  private Bool configured := false
  private Int valid := 0
  private Int invalid := 0
  private Int off := 0
  private Int triggers := 0
  private Float? maximum
  private Str:Obj? calendarDto := [:]
  private Str:Obj? inputs := [:]
  private Str:Obj? result := [:]
  private Bool done := false
  private Bool stateClosed := false
  private Bool outputClosed := false
  private Err? failure

  Void addFrame(DateTime a,DateTime b,Str:EnerCubixHistoryData histories,EnerCubixPreparedOwner frame)
  {
    check
    if(done || stateClosed || frame.budget!==state.budget || a!=EnerCubixMath.floorHour(a) || b!=a+1hr) throw ArgErr("nonWorkingConsumerFrame")
    if(!configured || at>=end || b<=at) return
    if(a!=at) throw ArgErr("nonWorkingConsumerMissingFrame")
    try
    {
      ctx.beginFrame(frame,histories)
      if(!ctx.working(at.toTimeZone(ctx.tz),false) || !ctx.working(at.toTimeZone(ctx.tz),true))
      {
        off++;frame.hold(8+ids.size);values:=EnerCubixValue[,];reliable:=at>=from && b<=end
        ids.each |id|
        {
          state.budget.deadline.check
          r:=ctx.byId[id];h:=ctx.byPoint[r?.get("pointId") as Str ?: ""]
          if(r==null || h==null || !EnerCubixBudgetScope.readable(r)) {reliable=false;return}
          value:=ctx.node(id,category,at,b)
          frame.hold(64);evidence:=h.knownUsage(at,b,end,true)
          List raw:=(evidence["intervals"] as List) ?: Obj?[,];frame.hold(1+raw.size)
          intervals:=EnerCubixMath.maps(raw);proven:=evidence["_closedOwnPrimaryHour"]==true
          completeDetails:=evidence["detailsTruncated"]!=true && !intervals.isEmpty && intervals.all |i| {DateTime.fromIso(i["intervalStart"].toStr)>=at && DateTime.fromIso(i["intervalEnd"].toStr)<=b && ["ok","cleaned","corrected"].contains(i["quality"])}
          if(value.value==null || !["ok","cleaned","corrected"].contains(value.quality) || EnerCubixMath.num(evidence["coveredSeconds"])!=3600f || (!proven && !completeDetails)) reliable=false
          values.add(value)
        }
        Int references:=values.reduce(0) |Int n,EnerCubixValue v->Int| {n+v.sources.size}
        frame.hold(6+2*references);actual:=EnerCubixValue.sum(values).value
        if(!reliable || actual==null) invalid++
        else
        {
          valid++
          if(maximum==null || actual>maximum) {maximum=actual;result["triggerFrom"]=at.toIso;result["triggerTo"]=b.toIso}
          if(actual>normalized) triggers++
        }
      }
      at=b
    }
    catch(Err e) {failure=e;throw e}
  }
  Str:Obj? finish()
  {
    check;if(done) return result
    if(stateClosed || (configured && at<end)) throw ArgErr("nonWorkingConsumerIncomplete")
    if(configured)
    {
      calendarDto.setAll(["id":calendar["id"],"mod":calendar["mod"],"workDays":calendar["workDays"],"workHours":calendar["workHours"],"exceptions":calendar["exceptions"]])
      inputs.setAll(["validNonWorkingHours":valid,"unavailableNonWorkingHours":invalid,"nonWorkingHours":off,"triggerCount":triggers,"normalizedThreshold":normalized,"unit":unit,"coverageRequirement":"completeClosedOwnPrimaryIntervalsWithinActualHour"])
      result.setAll(["calendar":calendarDto,"inputs":inputs,"actual":maximum,"unit":unit,"formula":"completeOwnPrimaryHourUsage > normalizedThreshold","status":triggers>0 ? "triggered" : (invalid>0 ? "unavailable" : "notTriggered"),"reasonCodes":invalid>0 ? ["RULE_HOURLY_EVIDENCE_INCOMPLETE"] : (off==0 ? ["RULE_NO_NON_WORKING_HOURS"] : Str[,])])
    }
    done=true;return result
  }
  private Void check()
  {if(failure!=null) throw failure;if(outputClosed || (stateClosed && !done)) throw ArgErr("nonWorkingConsumerClosed");state.budget.deadline.check}
}

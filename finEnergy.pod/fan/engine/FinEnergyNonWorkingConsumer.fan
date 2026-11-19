** Non-working rule facts consume complete own-primary hours before diagnostics
** are sampled. Only counters and the maximum survive a borrowed source frame.
internal class FinEnergyNonWorkingConsumer
{
  new make(Str:Obj? q,Str:Obj? profile,[Str:Obj?][] records,Str:Obj? boundary,FinEnergyCockpitCatalog catalog,FinEnergyPreparedOwner state,FinEnergyPreparedOwner output)
  {
    if(!q.isImmutable || !profile.isImmutable || !records.isImmutable || !boundary.isImmutable || state===output || state.budget!==output.budget || state.budget!==catalog.owner.budget) throw ArgErr("nonWorkingConsumerPlan")
    this.state=state;this.output=output
    from=DateTime.fromIso(q["from"].toStr).toTimeZone(catalog.tz)
    to:=DateTime.fromIso(q["to"].toStr).toTimeZone(catalog.tz);asOf:=DateTime.fromIso(q["asOf"].toStr).toTimeZone(catalog.tz)
    end=to<asOf ? to : asOf;at=FinEnergyMath.floorHour(from)
    state.hold(42+((List)boundary["meterIds"]).size);ids=FinEnergyMath.strings(boundary["meterIds"])
    state.watch |->Void| {ctx=null;calendar=null;ids.clear;stateClosed=true}
    output.hold(74);output.watch |->Void|
    {calendarDto.clear;inputs.clear;(result["reasonCodes"] as List)?.clear;result.clear;outputClosed=true}
    catalog.bind(output)
    category=FinEnergyMath.strings(q["categoryIds"]).first
    calendar=records.find |r| {r["id"]==profile["calendarRef"] && r["kind"]=="calendar" && FinEnergyBudgetScope.readable(r)}
    if(calendar==null || !FinEnergyCockpitRules.validCalendar(calendar)) {result["reasonCodes"]=["RULE_CALENDAR_INVALID"];return}
    unit=records.find |r| {r["id"]==category}?.get("unit") as Str ?: ""
    factor:=unit.isEmpty || (profile["thresholdUnit"] as Str ?: "").isEmpty ? null : FinEnergyMath.unitFactor(profile["thresholdUnit"].toStr,unit)
    if(factor==null) {result["reasonCodes"]=["RULE_UNIT_INCOMPATIBLE"];return}
    threshold:=FinEnergyMath.num(profile["threshold"])
    if(threshold==null || threshold<0f) throw ArgErr("nonWorkingConsumerThreshold")
    normalized=threshold*factor
    ctx=FinEnergyContext.shared(catalog,q["dimension"].toStr,q["spaceSource"]=="fin",state);ctx.calendar=calendar;configured=true
  }
  private FinEnergyPreparedOwner state
  private FinEnergyPreparedOwner output
  private FinEnergyContext? ctx
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
  private Int substituted := 0
  private Int unknownSubstitution := 0
  private Float? maximum
  private Str:Obj? calendarDto := [:]
  private Str:Obj? inputs := [:]
  private Str:Obj? result := [:]
  private Bool done := false
  private Bool stateClosed := false
  private Bool outputClosed := false
  private Err? failure

  Void addFrame(DateTime a,DateTime b,Str:FinEnergyHistoryData histories,FinEnergyPreparedOwner frame)
  {
    check
    if(done || stateClosed || frame.budget!==state.budget || a!=FinEnergyMath.floorHour(a) || b!=a+1hr) throw ArgErr("nonWorkingConsumerFrame")
    if(!configured || at>=end || b<=at) return
    if(a!=at) throw ArgErr("nonWorkingConsumerMissingFrame")
    try
    {
      ctx.beginFrame(frame,histories)
      if(!ctx.working(at.toTimeZone(ctx.tz),false) || !ctx.working(at.toTimeZone(ctx.tz),true))
      {
        off++;frame.hold(11+ids.size);values:=FinEnergyValue[,];completeHour:=at>=from && b<=end;reliable:=completeHour;hadSubstitution:=false;substitutionUnknown:=false
        ids.each |id|
        {
          state.budget.deadline.check
          r:=ctx.byId[id];h:=ctx.byPoint[r?.get("pointId") as Str ?: ""]
          if(r==null || h==null || !FinEnergyBudgetScope.readable(r)) {reliable=false;substitutionUnknown=true;return}
          value:=ctx.node(id,category,at,b)
          frame.hold(64);evidence:=h.knownUsage(at,b,end,true)
          List raw:=(evidence["intervals"] as List) ?: Obj?[,];frame.hold(1+raw.size)
          intervals:=FinEnergyMath.maps(raw);proven:=evidence["_closedOwnPrimaryHour"]==true
          subState:=completeHour ? FinEnergyCockpitRules.substitutionEvidence(evidence,intervals,at,b,value.quality) : 2
          hadSubstitution=hadSubstitution || subState==1;substitutionUnknown=substitutionUnknown || subState==2
          completeDetails:=evidence["detailsTruncated"]!=true && !intervals.isEmpty && intervals.all |i| {DateTime.fromIso(i["intervalStart"].toStr)>=at && DateTime.fromIso(i["intervalEnd"].toStr)<=b && ["ok","cleaned","corrected"].contains(i["quality"])}
          if(value.value==null || !["ok","cleaned","corrected"].contains(value.quality) || FinEnergyMath.num(evidence["coveredSeconds"])!=3600f || (!proven && !completeDetails)) reliable=false
          values.add(value)
        }
        Int references:=values.reduce(0) |Int n,FinEnergyValue v->Int| {n+v.sources.size}
        frame.hold(6+2*references);actual:=FinEnergyValue.sum(values).value
        if(hadSubstitution) substituted++;if(substitutionUnknown) unknownSubstitution++
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
      inputs.setAll(["validNonWorkingHours":valid,"unavailableNonWorkingHours":invalid,"nonWorkingHours":off,"triggerCount":triggers,"normalizedThreshold":normalized,"unit":unit,"coverageRequirement":"completeClosedOwnPrimaryIntervalsWithinActualHour","substitutedNonWorkingHours":substituted,"unknownSubstitutionNonWorkingHours":unknownSubstitution])
      result.setAll(["calendar":calendarDto,"inputs":inputs,"actual":maximum,"unit":unit,"formula":"completeOwnPrimaryHourUsage > normalizedThreshold","status":triggers>0 ? "triggered" : (invalid>0 ? "unavailable" : "notTriggered"),"reasonCodes":invalid>0 ? ["RULE_HOURLY_EVIDENCE_INCOMPLETE"] : (off==0 ? ["RULE_NO_NON_WORKING_HOURS"] : Str[,])])
    }
    done=true;return result
  }
  private Void check()
  {if(failure!=null) throw failure;if(outputClosed || (stateClosed && !done)) throw ArgErr("nonWorkingConsumerClosed");state.budget.deadline.check}
}

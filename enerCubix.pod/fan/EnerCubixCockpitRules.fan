** Pure optional clues over this frozen snapshot. No rules are installed, no
** alarm/message is created, and no history beyond the existing plan is read.
internal class EnerCubixCockpitRules
{
  static Str:Obj? project(Str:Obj? q,[Str:Obj?][] records,[Str:Obj?][] histories,Str:Obj? owned,Str:Obj? boundary,Str:Obj? budget,Str snapshotId,|Str,Str:Obj?->Str:Obj?|? preparedRule := null)
  {
    evaluations:=[Str:Obj?][,];items:=[Str:Obj?][,]
    if(owned["rulesComplete"] == false) return ["evaluations":[["status":"unavailable","reasonCodes":["RULE_CONFIG_UNREADABLE"]]],"items":items]
    profiles:=EnerCubixCockpitBudget.related("rule",q,records,owned,boundary)
    category:=EnerCubixMath.strings(q["categoryIds"]).first
    model:=EnerCubixMath.maps(owned["modelRecords"]);if(model.isEmpty) model=records
    profiles.each |p|
    {
      if(p["validation"] != "invalid" && p["categoryRef"] != category) return
      ((EnerCubixCockpitDeadline?)q["_cockpitDeadline"])?.check
      e:=Str:Obj?["id":p["id"],"ruleType":p["ruleType"],"profileRef":["id":p["id"],"mod":p["mod"],"version":p["version"]],"configuration":p,"status":"unavailable","reasonCodes":Str[,],"threshold":p["threshold"],"thresholdUnit":p["thresholdUnit"],"boundaryId":boundary["id"],"sourceIds":boundary["sourcePointIds"],"from":q["from"],"to":q["to"],"asOf":q["asOf"]]
      evaluations.add(e)
      if(p["validation"] == "invalid") {e["reasonCodes"]=["RULE_CONFIG_INVALID"];return}
      if(p["enabled"] != true) {e["status"]="disabled";e["reasonCodes"]=["RULE_DISABLED"];return}
      if(owned["modelComplete"] != true) {e["reasonCodes"]=["RULE_SCOPE_UNPROVEN"];return}
      Str:Obj? match:=[:]
      try {match=EnerCubixBudgetScope.match(p["scopeKind"].toStr,p["scopeRef"].toStr,category,q,boundary,model,owned["projectRef"] as Str)}
      catch(ArgErr err) {e["reasonCodes"]=["RULE_SCOPE_UNPROVEN"];return}
      if(match["eligible"] != true) {e["reasonCodes"]=["RULE_SCOPE_MISMATCH"];return}
      threshold:=EnerCubixMath.num(p["threshold"])
      if(threshold == null || threshold < 0f) {e["reasonCodes"]=["RULE_THRESHOLD_INVALID"];return}
      if(p["ruleType"] == "budgetVariance")
      {
        variance:=EnerCubixMath.num(budget["variancePct"])
        e["inputs"]=["budgetConfigRefs":budget["configRefs"],"budgetStatus":budget["status"],"periodBudget":budget["periodBudget"],"periodActualCost":budget["periodActualCost"],"deviationAmount":budget["deviationAmount"],"variancePct":variance,"currency":budget["currency"],"currencyBasis":budget["currencyBasis"],"costReportRef":budget["costReportRef"]]
        e["formula"]="(periodActualCost - periodBudget) / periodBudget * 100 > threshold"
        if(budget["status"] != "ok" || variance == null || p["currency"] != budget["currency"] || p["thresholdUnit"] != "%") {e["reasonCodes"]=["RULE_BUDGET_UNAVAILABLE"];return}
        e["actual"]=variance;e["unit"]="%";e["status"]=variance > threshold ? "triggered" : "notTriggered"
      }
      else if(p["ruleType"] == "nonWorkingHighUsage")
      {
        if(preparedRule==null) nonWorking(e,p,q,records,histories,boundary,threshold)
        else e.setAll(preparedRule(p["id"].toStr,q))
      }
      else {e["reasonCodes"]=["RULE_TYPE_UNSUPPORTED"];return}
      if(e["status"] != "triggered") return
      from:=e["triggerFrom"] ?: q["from"];to:=e["triggerTo"] ?: q["to"]
      reference:=p["ruleType"] == "nonWorkingHighUsage" ? ((Map)e["inputs"])["normalizedThreshold"] : threshold
      item:=e.dup.setAll(["id":"rule:"+p["id"].toStr,"type":"ruleClue","name":p["name"],"objectId":EnerCubixMath.strings(q["nodeIds"]).first,"categoryId":category,"active":null,"acknowledged":null,"reference":reference,"evidenceFrom":from,"evidenceTo":to,"detailTarget":["kind":"profile","metricId":p["ruleType"] == "budgetVariance" ? "cost" : "energy"],"evidenceTarget":["kind":"profile","parentSnapshotId":snapshotId,"request":["kind":"profile","dimension":q["dimension"],"spaceSource":"fin","nodeIds":q["nodeIds"],"categoryIds":q["categoryIds"],"from":from,"to":to,"asOf":q["asOf"],"period":"hour","metric":p["ruleType"] == "budgetVariance" ? "cost" : "energy"]]])
      if(p["ruleType"] == "budgetVariance" && budget["costInputs"] is Map)
      {
        item["reportRef"]=budget["costReportRef"]
        item["evidenceTarget"]=["kind":"profile","parentSnapshotId":snapshotId,"reportRef":budget["costReportRef"],"request":((Map)budget["costInputs"])["request"]]
      }
      items.add(item)
    }
    return ["evaluations":evaluations,"items":items,"configuration":profiles]
  }
  private static Void nonWorking(Str:Obj? out,Str:Obj? profile,Str:Obj? q,[Str:Obj?][] records,[Str:Obj?][] histories,Str:Obj? boundary,Float threshold)
  {
    calendar:=records.find |r| {r["id"] == profile["calendarRef"] && r["kind"] == "calendar" && EnerCubixBudgetScope.readable(r)}
    if(calendar == null || !validCalendar(calendar)) {out["reasonCodes"]=["RULE_CALENDAR_INVALID"];return}
    category:=EnerCubixMath.strings(q["categoryIds"]).first
    unit:=records.find |r| {r["id"] == category}?.get("unit") as Str ?: ""
    factor:=unit.isEmpty || (profile["thresholdUnit"] as Str ?: "").isEmpty ? null : EnerCubixMath.unitFactor(profile["thresholdUnit"].toStr,unit)
    if(factor == null) {out["reasonCodes"]=["RULE_UNIT_INCOMPATIBLE"];return}
    normalized:=threshold*factor
    tz:=TimeZone(q["tz"].toStr);from:=DateTime.fromIso(q["from"].toStr);to:=DateTime.fromIso(q["to"].toStr);asOf:=DateTime.fromIso(q["asOf"].toStr);end:=to < asOf ? to : asOf
    guard:=histories.find |h| {h["_preparedBudget"] is EnerCubixPreparedBudget}?.get("_preparedBudget") as EnerCubixPreparedBudget
    baseline:=guard?.temporary?.val ?: 0
    try
    {
      dim:=EnerCubixDimension(q["dimension"].toStr,records,q["spaceSource"] == "fin")
      ctx:=EnerCubixContext(dim.records,EnerCubixCockpitMetrics.histories(q,histories),tz,dim);ctx.calendar=calendar
      valid:=0;invalid:=0;triggerCount:=0;off:=0;Float? maximum:=null
      cursor:=EnerCubixMath.floorHour(from)
      while(cursor < end)
      {
        guard?.deadline?.check;((EnerCubixCockpitDeadline?)q["_cockpitDeadline"])?.check
        next:=cursor+1hr
        if(!ctx.working(cursor.toTimeZone(tz),false) || !ctx.working(cursor.toTimeZone(tz),true))
        {
          off++;values:=EnerCubixValue[,];reliable:=cursor >= from && next <= end
          EnerCubixMath.strings(boundary["meterIds"]).each |id|
          {
            r:=ctx.byId[id];h:=ctx.byPoint[r?.get("pointId") as Str ?: ""]
            if(r == null || h == null || !EnerCubixBudgetScope.readable(r)) {reliable=false;return}
            value:=ctx.node(id,category,cursor,next)
            evidence:=h.knownUsage(cursor,next,end,true);intervals:=EnerCubixMath.maps(evidence["intervals"])
            proven:=evidence["_closedOwnPrimaryHour"] == true
            completeDetails:=evidence["detailsTruncated"] != true && !intervals.isEmpty && intervals.all |i| {DateTime.fromIso(i["intervalStart"].toStr) >= cursor && DateTime.fromIso(i["intervalEnd"].toStr) <= next && ["ok","cleaned","corrected"].contains(i["quality"])}
            if(value.value == null || !["ok","cleaned","corrected"].contains(value.quality) || EnerCubixMath.num(evidence["coveredSeconds"]) != 3600f || (!proven && !completeDetails)) reliable=false
            values.add(value)
          }
          actual:=EnerCubixValue.sum(values).value
          if(!reliable || actual == null) invalid++
          else
          {
            valid++
            if(maximum == null || actual > maximum) {maximum=actual;out["triggerFrom"]=cursor.toIso;out["triggerTo"]=next.toIso}
            if(actual > normalized)
            {
              triggerCount++
            }
          }
        }
        cursor=next
      }
      out.setAll(["calendar":["id":calendar["id"],"mod":calendar["mod"],"workDays":calendar["workDays"],"workHours":calendar["workHours"],"exceptions":calendar["exceptions"]],"inputs":["validNonWorkingHours":valid,"unavailableNonWorkingHours":invalid,"nonWorkingHours":off,"triggerCount":triggerCount,"normalizedThreshold":normalized,"unit":unit,"coverageRequirement":"completeClosedOwnPrimaryIntervalsWithinActualHour"],"actual":maximum,"unit":unit,"formula":"completeOwnPrimaryHourUsage > normalizedThreshold","status":triggerCount > 0 ? "triggered" : (invalid > 0 ? "unavailable" : "notTriggered"),"reasonCodes":invalid > 0 ? ["RULE_HOURLY_EVIDENCE_INCOMPLETE"] : (off == 0 ? ["RULE_NO_NON_WORKING_HOURS"] : Str[,])])
    }
    finally {if(guard != null) guard.temporary.val=baseline}
  }
  internal static Bool validCalendar(Str:Obj? c)
  {
    if(c["workDays"] isnot List || c["workHours"] isnot List) return false
    if(((List)c["workDays"]).any |v| {n:=EnerCubixMath.num(v);return n == null || n < 1f || n > 7f || n.floor != n}) return false
    if(((List)c["workHours"]).any |v| {n:=EnerCubixMath.num(v);return n == null || n < 0f || n > 23f || n.floor != n}) return false
    if(c["exceptions"] != null && c["exceptions"] isnot List) return false
    dates:=Str[,];List exceptions:=(c["exceptions"] as List) ?: Obj?[,]
    return exceptions.all |v|
    {
      e:=v as Map;if(e == null) return false
      date:=e["date"] as Str ?: ""
      if(Date.fromStr(date,false) == null || e["working"] isnot Bool || dates.contains(date)) return false
      dates.add(date);return true
    }
  }
}

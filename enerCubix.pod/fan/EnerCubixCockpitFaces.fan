** Views over the same effective primary-meter set and prepared history.
internal class EnerCubixCockpitFaces
{
  static Void attach(Str[] enabled, Str:Obj? q, [Str:Obj?][] records, [Str:Obj?][] histories,
    Str:Obj? boundary, Str:Obj? reports, Str:Obj? modules, EnerCubixContext ctx)
  {
    faces:=["time","endUse","organization"].findAll |id| {enabled.contains(id)}
    if (faces.isEmpty) return
    ids:=EnerCubixMath.strings(boundary["meterIds"])
    base:=q.dup.setAll(["nodeIds":ids,"dimension":"metering","metric":"energy","perArea":false])
    base.remove("spaceSource")
    Str:Obj? own:=[:]
    try {own=EnerCubixHistory.report(base.dup.set("kind","profile"),records,EnerCubixCockpitMetrics.histories(q,histories))}
    catch (EnerCubixHttpErr e) {throw e}
    catch (Err e) {faces.each |face| {modules[face]=["status":"error","error":["code":"COCKPIT_MODULE_ERROR"]]};return}
    reports["face-meter-profile"]=own
    faces.each |face|
    {
      try
      {
        data:=face == "time" ? time(base,q,records,histories,reports,ctx) :
          (face == "endUse" ? endUse(base,records,histories,reports,boundary) : organization(own,records,ids,boundary))
        modules[face]=data
      }
      catch (EnerCubixHttpErr e) {throw e}
      catch (Err e) {modules[face]=["status":"error","error":["code":"COCKPIT_MODULE_ERROR"]]}
    }
  }

  private static Str:Obj? time(Str:Obj? base, Str:Obj? scopeQuery, [Str:Obj?][] records, [Str:Obj?][] histories, Str:Obj? reports, EnerCubixContext ctx)
  {
    deadline:=base["_cockpitDeadline"] as EnerCubixCockpitDeadline
    visited:=0
    q:=base.dup.set("period","hour")
    daily:=EnerCubixHistory.report(q.dup.set("kind","daily"),records,EnerCubixCockpitMetrics.histories(q,histories))
    reports["face-daily"]=daily
    data:=Str:Obj?["dailyReportRef":"face-daily"]
    // Heatmap evidence is sufficient for the view; don't ship a duplicate annual
    // hourly report. Preserve independent selected objects without adding them.
    hourly:=EnerCubixHistory.report(scopeQuery.dup.set("period","hour"),records,EnerCubixCockpitMetrics.histories(q,histories))
    reasons:=Str[,]
    ["workingHours","workingDays"].each |kind|
    {
      field:=kind == "workingHours" ? "workHours" : "workDays"
      if (ctx.calendar?.get(field) is List)
      {
        key:="face-"+kind
        reports[key]=EnerCubixHistory.report(q.dup.set("kind",kind),records,EnerCubixCockpitMetrics.histories(q,histories))
        data[kind == "workingHours" ? "workingReportRef" : "workingDaysReportRef"]=key
      }
    }
    if (ctx.calendar == null) reasons.add("MISSING_CALENDAR")
    else if (data["workingReportRef"] == null && data["workingDaysReportRef"] == null) reasons.add("INVALID_CALENDAR")
    from:=DateTime.fromIso(q["from"].toStr); to:=DateTime.fromIso(q["to"].toStr)
    cutoff:=DateTime.fromIso(q["asOf"].toStr); tz:=TimeZone(q["tz"].toStr)
    cells:=[Str:Obj?][,]; excluded:=[Str:Obj?][,]
    EnerCubixMath.maps(hourly["series"]).each |series|
    {
      points:=EnerCubixMath.maps(series["points"])
      byDay:=Date:[Str:Obj?][][:]
      points.each |p|
      {
        if(++visited % 128 == 0) deadline?.check
        date:=DateTime.fromIso(p["ts"].toStr).toTimeZone(tz).date
        if (!byDay.containsKey(date)) byDay[date]=[Str:Obj?][,]
        byDay[date].add(p)
      }
      byDay.keys.sort.each |Date date|
      {
        start:=date.toDateTime(Time.defVal,tz); end:=(date+1day).toDateTime(Time.defVal,tz)
        day:=byDay[date]
        complete:=start >= from && end <= to && end <= cutoff && day.size == (end-start).ticks/1hr.ticks && day.all |p| {p["value"] != null && !["filtered","substituted","na","incompleteInterval"].contains(p["quality"])}
        if (!complete) {excluded.add(["seriesId":series["id"],"date":date.toStr,"reasonCode":"INCOMPLETE_DAY"]);return}
        day.each |p|
        {
          at:=DateTime.fromIso(p["ts"].toStr).toTimeZone(tz)
          cells.add(["seriesId":series["id"],"nodeId":series["nodeId"],"date":date.toStr,"hour":at.hour,"ts":p["ts"],"value":p["value"],"unit":series["unit"],"quality":p["quality"],"sourceIds":p["sourceIds"]])
        }
      }
    }
    data["heatmap"]=cells;data["excludedDays"]=excluded
    if (!excluded.isEmpty) reasons.add("INCOMPLETE_DAY")
    return ["status":reasons.isEmpty ? "ok" : "partial","data":data,"reasonCodes":reasons]
  }

  private static Str:Obj? endUse(Str:Obj? q, [Str:Obj?][] records, [Str:Obj?][] histories, Str:Obj? reports, Str:Obj? boundary)
  {
    report:=EnerCubixHistory.report(q.dup.set("kind","utility"),records,EnerCubixCockpitMetrics.histories(q,histories))
    shares:=EnerCubixMath.maps(((Map)report["extra"])["utilityShares"])
    additive:=boundary["aggregateAllowed"] == true && shares.all |s| {!["overlappingScopes","areaNormalized","negativeConsumption"].contains(s["percentageBasis"])}
    complete:=shares.all |s| {s["value"] != null && ["ok","good","estimated","derived","cleaned","corrected"].contains(s["quality"])}
    reasons:=Str[,]
    if (!additive) reasons.add("NON_ADDITIVE_END_USE")
    if (!complete) reasons.add("DATA_INCOMPLETE")
    reports["face-endUse"]=report
    return ["status":shares.isEmpty ? "empty" : (additive && complete ? "ok" : "partial"),"data":["reportRef":"face-endUse","additive":additive,"meterIds":boundary["meterIds"]],"reasonCodes":reasons]
  }

  private static Str:Obj? organization(Str:Obj? report, [Str:Obj?][] records, Str[] ids, Str:Obj? boundary)
  {
    byId:=Str:[Str:Obj?][:];records.each |r| {byId[r["id"].toStr]=r}
    groups:=Str:Str[][:];reasons:=Str[,]
    ids.each |id|
    {
      member:=byId[id]; current:=member["organizationId"] as Str
      path:=Str[,];valid:=true
      while (current != null)
      {
        org:=byId[current]
        if (org?.get("kind") != "organization" || path.contains(current)) {valid=false;break}
        path.add(current);current=org["parentId"] as Str
      }
      if (path.isEmpty || !valid) {path=["__unassigned__:organization"];reasons.add(valid ? "UNASSIGNED_ORGANIZATION" : "INVALID_ORGANIZATION")}
      path.each |key| {if (!groups.containsKey(key)) groups[key]=Str[,];groups[key].add(id)}
    }
    totals:=EnerCubixMath.maps(((Map)report["summary"])["totals"])
    knowns:=EnerCubixMath.maps(((Map)report["summary"])["knownTotals"])
    nodes:=[Str:Obj?][,]
    category:=totals.first?.get("categoryId") as Str ?: ""
    groups.keys.sort.each |id|
    {
      members:=groups[id].unique.sort
      strict:=EnerCubixValue[,];known:=EnerCubixValue[,];units:=Str[,]
      members.each |member|
      {
        row:=totals.find |r| {r["id"] == member+"|"+category}
        partial:=knowns.find |r| {r["id"] == member+"|"+category}
        if (row != null) units.add(row["unit"].toStr)
        strict.add(EnerCubixValue(EnerCubixMath.num(row?.get("value")),row?.get("quality") as Str ?: "missing",EnerCubixMath.strings(row?.get("sourceIds"))))
        known.add(EnerCubixValue(EnerCubixMath.num(partial?.get("value")),partial?.get("quality") as Str ?: "missing",EnerCubixMath.strings(partial?.get("sourceIds"))))
      }
      complete:=EnerCubixValue.sum(strict);available:=EnerCubixKnownUsage.combine(known)
      if (!complete.reliable) complete=EnerCubixValue(null,complete.quality,complete.sources)
      sources:=members.map |member->Str| {byId[member]["pointId"] as Str ?: ""}
      if (boundary["aggregateAllowed"] != true || sources.size != sources.unique.size || units.unique.size > 1)
      {
        quality:=units.unique.size > 1 ? "incompatibleUnit" : "overlappingScopes"
        complete=EnerCubixValue(null,quality,complete.sources);available=EnerCubixValue(null,quality,available.sources);reasons.add(quality)
      }
      value:=complete.value ?: available.value
      basis:=complete.value != null ? "complete" : (available.value == null ? "unavailable" : (available.quality == "substituted" ? "cleanedWithReplacement" : "knownSubtotal"))
      parent:=byId[id]?.get("parentId") as Str
      nodes.add(["id":id,"name":byId[id]?.get("name") ?: "","parentId":groups.containsKey(parent ?: "") ? parent : null,"nodeKind":id == "__unassigned__:organization" ? "unassigned" : "organization","meterIds":members,"unit":units.unique.size == 1 ? units.first : "","value":value,"valueType":value != null ? "number" : (available.quality == "na" ? "na" : "null"),"completeValue":complete.value,"knownValue":available.value,"valueBasis":basis,"quality":complete.value == null ? available.quality : complete.quality,"sourceIds":available.sources])
    }
    if (nodes.any |n| {n["completeValue"] == null}) reasons.add("DATA_INCOMPLETE")
    return ["status":nodes.isEmpty ? "empty" : (reasons.isEmpty ? "ok" : "partial"),"data":["rootIds":nodes.findAll |n| {n["parentId"] == null}.map |n->Str| {n["id"].toStr},"nodes":nodes,"meterIds":ids,"meterReportRef":"face-meter-profile","additive":boundary["aggregateAllowed"]],"reasonCodes":reasons.unique]
  }
}

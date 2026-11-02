** Focus evidence over the already prepared primary-history plan. No reads or
** inferred child sum can replace a device's own primary history.
internal class EnerCubixCockpitSpace
{
  static Str:Obj? project(Str:Obj? q, [Str:Obj?][] records, [Str:Obj?][] histories, Str[] plannedPoints, Str:Obj? boundary, |Str,Str:Obj?->Str:Obj?|? preparedReport := null)
  {
    current:=EnerCubixCockpitMetrics.histories(q,histories)
    prepared:=prepare(q,records,plannedPoints,current.map |h->Str| {h["pointId"].toStr})
    query:=(Str:Obj?)prepared["query"]
    report:=query.isEmpty ? Str:Obj?[:] : EnerCubixCockpitReports.read("space-summary",query,records,current,preparedReport)
    return projectPrepared(prepared,report,boundary)
  }

  ** Resolve membership from frozen metadata and actual loaded/placeholder source
  ** IDs. No history arithmetic is run while discovering the summary query.
  static Str:Obj? prepare(Str:Obj? q,[Str:Obj?][] records,Str[] plannedPoints,Str[] loadedPoints,EnerCubixContext? sourceContext := null,EnerCubixContext? spaceContext := null,EnerCubixPreparedOwner? owner := null)
  {
    category:=EnerCubixMath.strings(q["categoryIds"]).first
    dim:=sourceContext?.dimension ?: EnerCubixDimension(q["dimension"].toStr,records,true)
    selected:=EnerCubixMath.strings(q["nodeIds"]); candidates:=selected.dup
    selected.each |id| {candidates.addAll((dim.scope(id) ? dim.members(id) : dim.usageMembers(id)).map |r->Str| {r["id"].toStr})}
    records.findAll |r| {plannedPoints.contains(r["pointId"] as Str ?: "") && r["categoryId"] == category}.each |r| {candidates.add(r["id"].toStr)}
    byId:=Str:[Str:Obj?][:];records.findAll |r| {readable(r)}.each |r| {owner?.hold(1);byId[r["id"].toStr]=r}
    candidates=candidates.unique.findAll |id| {r:=byId[id];return r != null && (r["kind"] == "space" || (["meter","totalMeter"].contains(r["kind"]) && r["categoryId"] == category && r["canonicalId"] == null))}
    candidates.dup.each |id|
    {
      seen:=[id];parent:=parent(byId[id])
      while (parent != null && !seen.contains(parent))
      {
        r:=byId[parent];if (r == null) break
        candidates.add(parent);seen.add(parent);parent=EnerCubixCockpitSpace.parent(r)
      }
    }
    candidates=candidates.unique.sort
    ctx:=spaceContext
    if(ctx==null)
    {space:=EnerCubixDimension("space",records,true);ctx=EnerCubixContext(space.records,[Str:Obj?][,],TimeZone(q["tz"].toStr),space)}
    available:=Str[,];members:=Str:Str[][:];sources:=Str:Str[][:]
    units:=Str:Str[:]
    owner?.hold(8)
    owner?.watch |->Void| {byId.clear;candidates.clear;available.clear;members.each |v| {v.clear};members.clear;sources.each |v| {v.clear};sources.clear;units.clear}
    candidates.each |id|
    {
      record:=byId[id]
      // A native equipment folder may contain meters but is not their meter.
      // Focus on equipment requires its own enrolled primary source.
      ms:=record["nativeSourceKind"] == "equip" && !["meter","totalMeter"].contains(record["kind"]) ? [Str:Obj?][,] : ctx.scopeMeters(id,category)
      readableMembers:=ms.findAll |m| {readable(m) && byId.containsKey(m["id"].toStr)}
      owner?.hold(5+2*readableMembers.size)
      units[id]=ctx.unit(id,category,"energy")
      members[id]=readableMembers.map |m->Str| {m["id"].toStr}.unique.sort
      sources[id]=readableMembers.map |m->Str| {m["pointId"] as Str ?: ""}.findAll |Str p->Bool| {!p.isEmpty}.unique.sort
      // A readable ancestor with an inaccessible member is not a loaded partial
      // aggregate. Keep its visible metadata without disclosing the hidden IDs.
      if (!ms.isEmpty && readableMembers.size == ms.size && ms.all |m| {p:=m["pointId"] as Str;return p != null && plannedPoints.contains(p) && loadedPoints.contains(p)}) available.add(id)
    }
    query:=available.isEmpty ? Str:Obj?[:] : q.dup.setAll(["nodeIds":available,"dimension":"space","kind":"profile","perArea":false])
    owner?.hold(14+query.size+candidates.size+available.size)
    result:=Str:Obj?["category":category,"candidates":candidates,"byId":byId,"members":members,"sources":sources,"available":available,"units":units,"query":query,"plannedPoints":plannedPoints]
    owner?.watch |->Void| {query.clear;result.clear}
    return result
  }

  static Str:Obj? projectPrepared(Str:Obj? prepared,Str:Obj? report,Str:Obj? boundary)
  {
    category:=prepared["category"].toStr;candidates:=(Str[])prepared["candidates"]
    byId:=(Str:[Str:Obj?])prepared["byId"];members:=(Str:Str[])prepared["members"];sources:=(Str:Str[])prepared["sources"]
    available:=(Str[])prepared["available"];units:=(Str:Str)prepared["units"];plannedPoints:=(Str[])prepared["plannedPoints"]
    Map summary:=report["summary"] as Map ?: Str:Obj?[:];Map extra:=report["extra"] as Map ?: Str:Obj?[:]
    totals:=EnerCubixMath.maps(summary["totals"]);knowns:=EnerCubixMath.maps(summary["knownTotals"])
    [Str:Obj?][] nodes:=candidates.map |id->[Str:Obj?]|
    {
      r:=byId[id];own:=r["nativeSourceKind"] == "equip" || ["meter","totalMeter"].contains(r["kind"])
      row:=totals.find |v| {v["id"] == id+"|"+category}
      known:=knowns.find |v| {v["id"] == id+"|"+category}
      if (row != null) row=row.dup
      if (row != null && known != null) row.setAll(["knownValue":known["value"],"knownValueType":known["valueType"],"knownQuality":known["quality"]])
      coverage:=EnerCubixMath.maps(extra["usageCoverage"]).findAll |c| {c["nodeId"] == id}
      basis:=Str:Obj?["id":boundary["id"],"aggregateAllowed":true]
      local:=Str:Obj?["summary":["selectionTotals":row == null ? [Str:Obj?][,] : [row]],"extra":["usageCoverage":coverage]]
      metric:=EnerCubixCockpitMetrics.metric(local,"energy",category,basis)
      metric.remove("id");metric.remove("boundaryId")
      if (!available.contains(id)) metric.setAll(["quality":"notLoaded","reasonCodes":["FOCUS_NOT_LOADED"],"unit":units[id]])
      p:=parent(r)
      metric.setAll(["id":id,"nativeId":r["nativeSourceId"] ?: id,"name":r["name"] ?: id,"parentId":p != null && candidates.contains(p) ? p : null,"nodeKind":r["nativeSourceKind"] ?: (own ? "equip" : "space"),"basis":own ? "ownPrimary" : "scopeAggregate","meterIds":members[id],"sourceIds":sources[id].findAll |point| {plannedPoints.contains(point)}])
      return metric
    }
    return ["status":nodes.isEmpty ? "empty" : (nodes.any |n| {n["valueBasis"] != "complete"} ? "partial" : "ok"),"boundaryId":boundary["id"],"data":["rootIds":nodes.findAll |n| {n["parentId"] == null}.map |n->Str| {n["id"].toStr},"nodes":nodes]]
  }
  private static Str? parent(Str:Obj? r) {r["nativeEquip"] == true ? (r["nativeTreeParentId"] as Str) : (r["parentId"] as Str)}
  private static Bool readable(Str:Obj? r) {r["nativeHidden"] != true && r["_comparisonReadable"] != false && r["_comparisonPointReadable"] != false}
}

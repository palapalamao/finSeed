** Optional balance projection over the existing flow engine and prepared history.
internal class FinEnergyCockpitFlow
{
  ** Resolve current readable relationships before loading any primary history.
  static Str:Obj? prepare(Str:Obj? q, [Str:Obj?][] records, Str project,Bool includeCanonicalRecords := false)
  {
    visible:=FinEnergyEnergyFlow.visible(records.findAll |r| {r["_comparisonReadable"] != false},records)
    normalized:=FinEnergyEnergyFlow.normalizeRecords(visible)
    dim:=FinEnergyDimension(q["dimension"].toStr,normalized,q["spaceSource"] == "fin")
    request:=dim.normalizeRequest(q.dup.setAll(["kind":"energyFlow","categoryId":FinEnergyMath.strings(q["categoryIds"]).first,"metric":"energy","perArea":false]))
    scope:=FinEnergyEnergyFlow.scope(request,dim)
    meters:=FinEnergyMath.maps(scope["selected"]).dup.addAll(FinEnergyMath.maps(scope["unassigned"])).unique
    config:=FinEnergyMath.maps(scope["roots"]).dup.addAll(meters)
    roots:=FinEnergyMath.maps(scope["roots"]).findAll |r| {dim.scope(r["id"].toStr)}.map |r->Str| {r["id"].toStr}
    dim.records.findAll |r| {dim.scope(r["id"].toStr)}.each |r|
    {
      seen:=Str[,];cursor:=r["id"] as Str
      while (cursor != null && !seen.contains(cursor))
      {
        if (roots.contains(cursor)) {config.add(r);break}
        seen.add(cursor);cursor=dim.byId[cursor]?.get("parentId") as Str
      }
    }
    meters.each |m|
    {
      id:=m["expressionId"] as Str
      expr:=id == null ? null : dim.byId[id]
      if (expr != null && expr["_comparisonReadable"] != false) config.add(expr)
      [m["id"],m["pointId"]].each |ref|
      {
        if (ref is Str && ref.toStr.startsWith("p:") && !ref.toStr.startsWith("p:"+project+":r:")) throw ArgErr("cockpitRef")
      }
    }
    result:=Str:Obj?["request":request,"records":visible,"meters":meters,"configuration":config.unique]
    if(includeCanonicalRecords) result["canonicalRecords"]=normalized
    return result
  }

  static Void attach(Str:Obj? prepared, [Str:Obj?][] histories, Str:Obj? boundary, Str:Obj? reports, Str:Obj? modules,|Str,Str:Obj?->Str:Obj?|? route := null)
  {
    try
    {
      q:=(Str:Obj?)prepared["request"]
      report:=FinEnergyCockpitReports.read("energy-flow",q,([Str:Obj?][])prepared["records"],FinEnergyCockpitMetrics.histories(q,histories),route)
      graphs:=FinEnergyMath.maps(((Map)report["extra"])["energyFlowGraphs"])
      account:=(Map)((Map)report["extra"])["energyFlowAccounting"]
      partial:=account["canAdd"] != true || graphs.any |g|
      {
        return g["additive"] != true || g["boundaryQuality"] != "ok" || FinEnergyMath.maps(g["nodes"]).any |n|
        {n["value"] == null || !["ok","estimated","derived","cleaned","corrected"].contains(n["balanceQuality"])}
      }
      reports["energy-flow"]=report
      modules["balance"]=["status":graphs.isEmpty ? "empty" : (partial ? "partial" : "ok"),"boundaryId":boundary["id"],"data":["reportRef":"energy-flow","graphIds":graphs.map |g->Str| {g["graphId"].toStr}],"reasonCodes":graphs.isEmpty ? ["EMPTY_FLOW"] : (partial ? ["PARTIAL_FLOW"] : Str[,])]
    }
    catch (FinEnergyHttpErr e) {throw e}
    catch (Err e) {modules["balance"]=error}
  }

  static Str:Obj? error() {["status":"error","error":["code":"COCKPIT_MODULE_ERROR"]]}
}

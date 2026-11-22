** Opt-in first chart for the ordinary profile. Configuration stays complete;
** only noncontributing member histories and diagnostic evidence are deferred.
internal class FinEnergyProfileFirst
{
  static Str:Obj? activate(Str:Obj? request,[Str:Obj?][] records)
  {
    out:=request.dup
    out.remove("_profileFirst")
    if(request["responseMode"]!="chart" || !eligible(out,records)) return out
    out["_profileFirst"]=true
    return out
  }

  private static Bool eligible(Str:Obj? q,[Str:Obj?][] records)
  {
    if(q["kind"]!="profile" || q["metric"]!="energy" || q["period"]!="day" || q["dimension"]!="space" || q["spaceSource"]!="fin" || q["perArea"]==true || q["raw"]==true) return false
    if(q["otherFrom"]!=null || q["otherTo"]!=null || !FinEnergyMath.strings(q["referenceIds"]).isEmpty) return false
    if(q.keys.any |key| {key.startsWith("_cockpit") || key=="_comparisonScope" || key=="comparisonMembers"}) return false
    dim:=FinEnergyDimension("space",records,true)
    req:=dim.normalizeRequest(q);ids:=FinEnergyMath.strings(req["nodeIds"])
    return !ids.isEmpty && ids.all |id| {r:=dim.byId[id];return dim.scope(id) || (r!=null && ["meter","totalMeter"].contains(r["kind"]))}
  }

  ** Match line categories and scopeMeters exactly. Do not prune the catalog or
  ** substitute a child's reading for a selected meter's own primary history.
  static Str[] pointIds(Str:Obj? request,[Str:Obj?][] records)
  {
    dim:=FinEnergyDimension(request["dimension"].toStr,records,request["spaceSource"]=="fin")
    q:=dim.normalizeRequest(request)
    ctx:=FinEnergyContext(dim.records,[Str:Obj?][,],TimeZone.utc,dim)
    points:=Str[,]
    FinEnergyMath.strings(q["nodeIds"]).unique.each |id|
    {
      cats:=ctx.categories(id);if(cats.isEmpty) cats=[""]
      cats.each |category|
      {ctx.scopeMeters(id,category).each |m| {point:=m["pointId"] as Str;if(point!=null && !point.isEmpty) points.add(point)}}
    }
    return points.unique.sort
  }
}

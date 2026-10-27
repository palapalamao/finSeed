** Report-local selection and overlap checks. Every meter reads its own primary.
internal class EnerCubixEndUse
{
  static [Str:Obj?][] resolve(EnerCubixContext ctx,Str[] selected)
  {
    found:=Str:[Str:Obj?][:]
    selected.each |id|
    {
      r:=ctx.byId[id]
      if (r == null) {ctx.warn("Unknown selected node: $id");return}
      if (!["meter","totalMeter","group"].contains(r["kind"]) && ctx.dimension?.scope(id) != true)
        throw ArgErr("utilityMeterOrScopeRequired")
      if (["space","organization","group"].contains(r["kind"]) && ctx.dimension != null && !ctx.dimension.scope(id))
        throw ArgErr("Selected node does not belong to the report dimension")
      ctx.categories(id).each |cat|
      {
        ctx.scopeMeters(id,cat).each |m|
        {
          canonical:=ctx.dimension?.canonical(m["id"].toStr) ?: (m["canonicalId"] as Str ?: m["id"].toStr)
          found[canonical]=ctx.byId[canonical] ?: m
        }
      }
    }
    return found.vals.sort |a,b| {a["id"].toStr <=> b["id"].toStr}
  }

  static Bool overlap(EnerCubixContext ctx,[Str:Obj?][] meters,EnerCubixValue[] readings := EnerCubixValue[,])
  {
    for (i:=0;i<meters.size;i++) for (j:=i+1;j<meters.size;j++)
    {
      a:=meters[i];b:=meters[j]
      if (a["id"] == b["id"]) continue
      if (ancestor(ctx,a["id"].toStr,b["id"].toStr) || ancestor(ctx,b["id"].toStr,a["id"].toStr)) return true
      if (a["pointId"] != null && a["pointId"] == b["pointId"]) return true
      if (readings.size == meters.size && readings[i].sources.any |id| {readings[j].sources.contains(id)}) return true
    }
    return false
  }

  private static Bool ancestor(EnerCubixContext ctx,Str parent,Str child)
  {
    seen:=Str[,];cursor:=ctx.byId[child]?.get("meterParentId") as Str
    while (cursor != null && !seen.contains(cursor))
    {
      if (cursor == parent) return true
      seen.add(cursor);cursor=ctx.byId[cursor]?.get("meterParentId") as Str
    }
    return false
  }
}

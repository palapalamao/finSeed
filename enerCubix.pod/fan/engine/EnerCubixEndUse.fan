** Report-local selection and overlap checks. Every meter reads its own primary.
internal class EnerCubixEndUse
{
  static [Str:Obj?][] resolve(EnerCubixContext ctx,Str[] selected,Str? category := null)
  {
    found:=Str:[Str:Obj?][:]
    children:=Str:[Str:Obj?][][:]
    ctx.byId.each |r|
    {
      ctx.deadline?.check
      if (!meter(r) || !readable(r)) return
      parent:=r["meterParentId"] as Str
      if (parent == null) return
      siblings:=children[parent]
      if (siblings == null) {siblings=[Str:Obj?][,];children[parent]=siblings}
      siblings.add(r)
    }
    selected.each |id|
    {
      ctx.deadline?.check
      r:=ctx.byId[id]
      if (r == null) {ctx.warn("Unknown selected node: $id");return}
      if (!["meter","totalMeter","group"].contains(r["kind"]) && ctx.dimension?.scope(id) != true)
        throw ArgErr("utilityMeterOrScopeRequired")
      if (["space","organization","group"].contains(r["kind"]) && ctx.dimension != null && !ctx.dimension.scope(id))
        throw ArgErr("Selected node does not belong to the report dimension")
      if (!readable(r)) return
      if (ctx.dimension?.scope(id) == true)
      {
        // Scope membership is authoritative: do not follow a contained main
        // meter into another site's or organization's members.
        ctx.dimension.members(id).each |m| {add(ctx,found,m)}
      }
      else if (meter(r))
      {
        // The selected meter is a range entrance. Keep an excluded explicit
        // leaf analyzable, but apply automatic-participation rules downstream.
        add(ctx,found,r)
        pending:=[r];seen:=Str:Bool[:]
        while (!pending.isEmpty)
        {
          ctx.deadline?.check
          current:=pending.removeAt(pending.size-1);key:=current["id"].toStr
          if (seen.containsKey(key)) continue
          seen[key]=true
          (children[key] ?: [Str:Obj?][,]).each |child|
          {
            if (child["categoryId"] != r["categoryId"]) return
            if (ctx.included(child)) add(ctx,found,child)
            pending.add(child)
          }
        }
      }
      else ctx.categories(id).each |cat| {ctx.scopeMeters(id,cat).each |m| {add(ctx,found,m)}}
    }
    // Resolve the union before removing ancestors, so overlapping scope/root
    // selections converge on one final own-meter set, independently per energy.
    covered:=Str:Bool[:]
    found.each |m|
    {
      seen:=[m["id"].toStr];parents:=Str[,];parent:=m["meterParentId"] as Str
      while (parent != null)
      {
        ctx.deadline?.check
        if (seen.contains(parent)) {parents.clear;break}
        ancestor:=ctx.byId[parent]
        if (ancestor == null || !readable(ancestor) || ancestor["categoryId"] != m["categoryId"]) break
        seen.add(parent)
        parents.add(parent)
        parent=ancestor["meterParentId"] as Str
      }
      parents.each |key| {if (found.containsKey(key)) covered[key]=true}
    }
    return (category==null ? found.vals : found.vals.findAll |m| {m["categoryId"]==category}).findAll |m| {!covered.containsKey(m["id"].toStr)}.sort |a,b| {a["id"].toStr <=> b["id"].toStr}
  }

  private static Bool meter(Str:Obj? r) {["meter","totalMeter"].contains(r["kind"])}
  private static Bool readable(Str:Obj? r) {r["nativeHidden"] != true && r["_comparisonReadable"] != false && r["_comparisonPointReadable"] != false}
  private static Void add(EnerCubixContext ctx,Str:[Str:Obj?] found,Str:Obj? record)
  {
    canonical:=ctx.dimension?.canonical(record["id"].toStr) ?: (record["canonicalId"] as Str ?: record["id"].toStr)
    r:=ctx.byId[canonical] ?: record
    if (readable(r)) found[canonical]=r
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

** Exact canonical own-device frontier. No leaf/formula expansion, value-based
** filtering, allocation to children or dimension-dependent budget precedence.
internal class FinEnergyBudgetScope
{
  static Str:Obj? match(Str kind,Str scope,Str category,Str:Obj? q,Str:Obj? boundary,[Str:Obj?][] records,Str? projectRef)
  {
    if(boundary["aggregateAllowed"] != true) return no("BUDGET_OVERLAP")
    dim:=FinEnergyDimension("space",records,true)
    ctx:=FinEnergyContext(dim.records,[Str:Obj?][,],TimeZone.utc,dim)
    currentIds:=FinEnergyMath.strings(boundary["meterIds"])
    selected:=currentIds.map |id->[Str:Obj?]?| {ctx.byId[id]}.exclude |r| {r == null}.map |r->[Str:Obj?]| {r}
    if(selected.size != currentIds.size || selected.isEmpty) return no("BUDGET_SCOPE_UNPROVEN")
    members:=[Str:Obj?][,]
    if(kind == "project")
    {
      if(projectRef == null || projectRef != scope) return no("BUDGET_SCOPE_UNPROVEN")
      members=dim.records.findAll |r| {["meter","totalMeter"].contains(r["kind"]) && ctx.included(r) && r["categoryId"] == category}
    }
    else if(kind == "space")
    {
      space:=dim.records.find |r| {(r["id"] == scope || r["nativeSourceId"] == scope) && r["kind"] == "space" && (r["nativeSourceKind"] == "site" || r["nativeSourceKind"] == "floor")}
      if(space == null || !readable(space)) return no("BUDGET_SCOPE_UNPROVEN")
      members=dim.members(space["id"].toStr).findAll |r| {r["categoryId"] == category}
    }
    else return no("BUDGET_SCOPE_UNPROVEN")
    // A hidden meter with unknown ancestry cannot be proven outside a space.
    if(!complete(kind,scope,category,dim.records)) return no("BUDGET_SCOPE_UNPROVEN")
    if(members.isEmpty || members.any |r| {!readable(r) || r["configurationError"] != null}) return no("BUDGET_SCOPE_UNPROVEN")
    frontier:=ctx.selectionMeters(members)
    if(signature(frontier) != signature(selected)) return no("BUDGET_SCOPE_MISMATCH")
    return ["eligible":true,"scopeKind":kind,"scopeRef":scope,"meterIds":frontier.map |r->Str| {r["id"].toStr},"boundaryBasis":"canonicalOwnDeviceFrontier"]
  }
  private static Bool complete(Str kind,Str scope,Str category,[Str:Obj?][] rs)
  {
    hidden:=rs.findAll |r| {["meter","totalMeter"].contains(r["kind"]) && r["categoryId"] == category && r["includeInTotals"] != false && !readable(r)}
    return hidden.all |r|
    {
      if(kind == "project") return false
      cursor:=r["spaceId"] as Str;seen:=Str[,]
      if(cursor == null) return false
      while(cursor != null)
      {
        if(cursor == scope || seen.contains(cursor)) return false
        seen.add(cursor);parent:=rs.find |p| {p["id"] == cursor || p["nativeSourceId"] == cursor}
        if(parent == null) return false
        cursor=parent["parentId"] as Str
      }
      return true
    }
  }
  private static Str[] signature([Str:Obj?][] rows)
  {rows.map |r->Str| {r["id"].toStr+"|"+(r["pointId"] as Str ?: "")+"|"+(r["expressionId"] as Str ?: "")+"|"+r["kind"].toStr}.sort}
  static Bool readable(Str:Obj? r) {r["nativeHidden"] != true && r["_comparisonReadable"] != false && r["_comparisonPointReadable"] != false}
  private static Str:Obj? no(Str reason) {["eligible":false,"reasonCodes":[reason]]}
}

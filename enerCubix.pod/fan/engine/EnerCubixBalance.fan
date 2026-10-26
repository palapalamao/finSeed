** Identify whether the compared readings have independent metering lineage.
** This traverses configuration evidence only; each value still reads its own history.
internal const class EnerCubixBalance
{
  static Str mode(EnerCubixContext ctx, Str id)
  {
    if (ctx.comparison?.derived(id) == true) return "consistency"
    own:=lineage(ctx,id,Str[,])
    children:=ctx.comparison?.members(id) ?: (ctx.dimension?.directChildren(id) ?: [Str:Obj?][,])
    branch:=Str[,]
    children.each |r| { branch.addAll(lineage(ctx,r["id"].toStr,Str[,])) }
    if (own.isEmpty || branch.isEmpty) return "unknown"
    if (own.any |source| { branch.contains(source) }) return "consistency"
    return "independent"
  }

  static Bool eligible(Str mode, EnerCubixValue own, EnerCubixValue branches)
  {
    qualities:=["ok","good","derived","cleaned","corrected"]
    return mode == "independent" && own.value != null && branches.value != null &&
      qualities.contains(own.quality) && qualities.contains(branches.quality)
  }

  private static Str[] lineage(EnerCubixContext ctx, Str id, Str[] path)
  {
    if (path.contains(id)) return Str[,]
    r:=ctx.byId[id]
    if (r == null) return Str[,]
    refs:=Str[,]
    if (r["autoSum"] == true)
      refs=(ctx.dimension?.directChildren(id) ?: [Str:Obj?][,]).map |child->Str| { child["id"].toStr }
    else if (r["expressionId"] != null)
    {
      expr:=ctx.byId[r["expressionId"].toStr]
      vars:=expr?.get("variables") as Map
      if (vars != null) vars.each |value| { if (value != null) refs.add(value.toStr) }
    }
    else
    {
      point:=r["pointId"] as Str
      return point == null ? Str[,] : [point]
    }
    sources:=Str[,]
    refs.each |ref| { sources.addAll(lineage(ctx,ref,path.dup.add(id))) }
    return sources.unique
  }
}

** Current physical-boundary membership for an explicit local balance query.
** Automatic aggregation keeps its existing includeInTotals rules.
internal class EnerCubixComparisonScope
{
  static Bool active(Str:Obj? request)
  {
    basis:=request["comparisonBasis"]
    if (basis == null) return false
    if (basis != "physicalBoundary" || request["kind"] != "leak") throw ArgErr("comparisonInvalidBasis")
    return true
  }

  static EnerCubixComparisonScope? of(Str:Obj? request,[Str:Obj?][] records)
  { active(request) ? ((request["_comparisonScope"] as EnerCubixComparisonScope) ?: make(request,records)) : null }

  ** Published derived histories can retain provenance refs with different ACLs.
  ** Check those refs too; permission on the archive is not permission on inputs.
  static Obj? readableSources(Obj? value, |Str->Bool| allowed)
  {
    if (value is List) return ((List)value).map |item->Obj?| {readableSources(item,allowed)}
    if (value isnot Map) return value
    out:=Str:Obj?[:]
    ((Map)value).each |v,k|
    {
      key:=k.toStr
      if (key == "sourceIds" && v is List) out[key]=((List)v).findAll |id| {id is Str && allowed(id)}
      else if (["pointId","sourceId"].contains(key) && v is Str) out[key]=allowed(v) ? v : null
      else out[key]=readableSources(v,allowed)
    }
    return out
  }

  new make(Str:Obj? request,[Str:Obj?][] source)
  {
    // Hidden aliases must not expose a target Ref through constructor errors.
    try {dim=EnerCubixDimension("metering",source)}
    catch (ArgErr e) {throw ArgErr("comparisonUnresolved")}
    dim.records.each |r| {byId[r["id"].toStr]=r}
    masters=EnerCubixMath.strings(request["nodeIds"]).map |id->Str| {canonical(id)}.unique
    if (masters.isEmpty) throw ArgErr("comparisonMasterRequired")
    input:=request["comparisonMembers"]
    if (input != null && input isnot Map) throw ArgErr("comparisonInvalidMembers")
    chosen:=Str:Obj?[:]
    Map supplied:=input as Map ?: Str:Obj?[:]
    supplied.each |v,k|
    {
      key:=canonical(k.toStr)
      if (!masters.contains(key) || chosen.containsKey(key) || v isnot List || ((List)v).any |item| {item isnot Str}) throw ArgErr("comparisonInvalidMembers")
      chosen[key]=v
    }
    masters.each |id|
    {
      root:=byId[id]
      if (root == null || !meter(root) || root["_comparisonReadable"] == false) throw ArgErr("comparisonMasterRequired")
      category:=root["categoryId"] as Str ?: ""
      limits:=Str[,];found:=[Str:Obj?][,];aliases:=Str:Str[:];paths:=Str:Str[][:]
      if (root["_comparisonUnavailable"] == true || root["_comparisonPointReadable"] == false) limits.add("comparisonUnavailable")
      checkChain(id,limits)
      descend(root,category,Str[,],[id],found,aliases,paths,limits)
      defaults:=found.map |r->Str| {r["id"].toStr}.sort
      selection:=defaults
      if (chosen.containsKey(id))
      {
        selection=EnerCubixMath.strings(chosen[id]).map |member->Str| {c:=canonical(member);return aliases[c] ?: c}.unique.sort
        if (selection.any |member| {!defaults.contains(member)}) throw ArgErr("comparisonInvalidMembers")
      }
      quality:=limits.contains("comparisonUnavailable") ? "comparisonUnavailable" : (!limits.isEmpty ? "comparisonUnresolved" : (selection.isEmpty ? "comparisonEmpty" : (selection.size != defaults.size ? "comparisonPartial" : "ok")))
      if (chosen.containsKey(id) && selection.isEmpty) quality="comparisonEmpty"
      membersByMaster[id]=found.findAll |r| {selection.contains(r["id"])}.sort |a,b| {a["id"].toStr <=> b["id"].toStr}
      groups[id]=["nodeId":id,"categoryId":category,"basis":"physicalBoundary","defaultMemberIds":defaults,"selectedMemberIds":selection,"quality":quality,"completeSelection":quality == "ok","limitations":limits.unique,"availableMembers":found.sort |a,b| {a["id"].toStr <=> b["id"].toStr}.map |r->[Str:Obj?]|
      {
        point:=(r["historyPointId"] ?: (r["pointId"] ?: "")).toStr
        return ["nodeId":r["id"],"name":r["alias"] ?: r["name"],"unit":r["unit"] ?: byId[category]?.get("unit"),"via":paths[r["id"].toStr] ?: Str[,],"sourceIds":point.isEmpty ? Str[,] : [point]]
      }]
    }
  }

  private EnerCubixDimension dim
  private Str:[Str:Obj?] byId:=[:]
  private Str:[Str:Obj?][] membersByMaster:=[:]
  private Str:[Str:Obj?] groups:=[:]
  Str[] masters:=Str[,]
  [Str:Obj?][] members(Str master) {membersByMaster[master] ?: [Str:Obj?][,]}
  Str? quality(Str master) {q:=groups[master]?.get("quality") as Str;return q == "ok" ? null : q}
  [Str:Obj?][] snapshots() {masters.map |id->[Str:Obj?]| {groups[id].dup}}
  Bool derived(Str id)
  {
    r:=byId[id];if (r == null) return false
    origin:=r["meterOrigin"] as Map
    return r["autoSum"] == true || r["expressionId"] != null || origin?.get("type") == "virtual"
  }
  Str[] memberIds() {masters.map |id->Str[]| {members(id).map |r->Str| {r["id"].toStr}}.flatten.unique}
  [Str:Obj?][] unionMembers()
  {
    selected:=memberIds.map |id->[Str:Obj?]| {byId[id]}
    seen:=Str[,]
    return dim.frontier(selected).sort |a,b| {a["id"].toStr <=> b["id"].toStr}.findAll |r|
    {
      source:=(r["historyPointId"] ?: (r["pointId"] ?: r["id"])).toStr
      if (seen.contains(source)) return false
      seen.add(source);return true
    }
  }

  private Str canonical(Str id)
  {
    try {return dim.canonical(id)} catch (Err e) {throw ArgErr("comparisonInvalidMembers")}
  }
  private Bool meter(Str:Obj? r) {["meter","totalMeter"].contains(r["kind"])}
  private [Str:Obj?][] children(Str id) {byId.vals.findAll |r| {meter(r) && r["meterParentId"] == id}.sort |a,b| {a["id"].toStr <=> b["id"].toStr}}

  private Void checkChain(Str id,Str[] limits)
  {
    seen:=Str[,];cursor:=id
    while (!cursor.isEmpty)
    {
      if (seen.contains(cursor)) {limits.add("comparisonCycle");return}
      seen.add(cursor);r:=byId[cursor]
      if (r == null) {limits.add("comparisonMissingSource");return}
      cursor=r["meterParentId"] as Str ?: ""
    }
  }

  private Void descend(Str:Obj? node,Str category,Str[] via,Str[] path,[Str:Obj?][] found,Str:Str aliases,Str:Str[] paths,Str[] limits)
  {
    id:=node["id"].toStr
    refs:=Str[,]
    if (node["expressionId"] != null)
    {
      expression:=byId[node["expressionId"].toStr]
      if (expression?.get("_comparisonReadable") == false) limits.add("comparisonUnavailable")
      else refs=additive(expression) ?: Str[,]
      if (refs.isEmpty) {limits.add("comparisonNonAdditive");return}
    }
    else refs=children(id).map |r->Str| {r["id"].toStr}
    if (refs.isEmpty && path.size > 1) limits.add("comparisonMissingSource")
    refs.each |ref|
    {
      child:=byId[canonical(ref)]
      if (child == null || !meter(child)) {limits.add("comparisonMissingSource");return}
      childId:=child["id"].toStr
      if (path.contains(childId)) {limits.add("comparisonCycle");return}
      if (child["_comparisonReadable"] == false || child["_comparisonPointReadable"] == false) {limits.add("comparisonUnavailable");return}
      unit:=child["unit"] as Str ?: (byId[category]?.get("unit") as Str ?: "")
      if (child["categoryId"] != category || EnerCubixMath.unitFactor(unit,byId[category]?.get("unit") as Str ?: "") == null) {limits.add("comparisonIncompatible");return}
      checkChain(childId,limits)
      if (derived(childId))
      {
        expr:=child["expressionId"] == null ? null : byId[child["expressionId"].toStr]
        if (expr?.get("_comparisonReadable") == false) limits.add("comparisonUnavailable")
        expandable:=child["autoSum"] == true || (expr != null && additive(expr) != null)
        if (expandable) {descend(child,category,via.dup.add(childId),path.dup.add(childId),found,aliases,paths,limits);return}
        limits.add("comparisonNonAdditive")
      }
      if (child["pointId"] == null && child["historyPointId"] == null) limits.add("comparisonMissingSource")
      source:=(child["historyPointId"] ?: (child["pointId"] ?: childId)).toStr
      prior:=found.find |r| {(r["historyPointId"] ?: (r["pointId"] ?: r["id"])).toStr == source}
      if (prior != null) {aliases[childId]=prior["id"].toStr;return}
      found.add(child);aliases[childId]=childId;paths[childId]=via
    }
  }

  ** Only sums of distinct named inputs are safely flattened. Other arithmetic
  ** keeps its stored node as an opaque boundary instead of inventing weights.
  internal static Str[]? additive([Str:Obj?]? expression)
  {
    if (expression == null || expression["_comparisonReadable"] == false) return null
    formula:=expression["formula"] as Str ?: ""
    Map vars:=expression["variables"] as Map ?: Str:Obj?[:]
    names:=Str[,];i:=0
    while (i < formula.size)
    {
      c:=formula[i]
      if (c.isSpace || c == '+' || c == '(' || c == ')') {i++;continue}
      if (!c.isAlpha && c != '_') return null
      start:=i++
      while (i < formula.size && (formula[i].isAlphaNum || formula[i] == '_')) i++
      name:=formula[start..<i]
      if (!vars.containsKey(name) || names.contains(name)) return null
      names.add(name)
    }
    if (names.isEmpty || !EnerCubixExpression.validate(formula,names)) return null
    Str[] refs:=names.map |name->Str| {return vars[name]?.toStr ?: ""}
    if (refs.any |ref| {ref.isEmpty} || refs.unique.size != refs.size) return null
    return refs
  }
}

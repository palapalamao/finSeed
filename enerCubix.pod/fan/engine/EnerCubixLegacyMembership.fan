** Curated backup evidence supplies edges only. It never upgrades a missing
** configuration event log into a complete independent leakage calculation.
internal const class EnerCubixLegacyMembership
{
  static Str:Obj? plan(Str:Obj? input, [Str:Obj?][] sources, Str:Str aliases)
  {
    from:=DateTime.fromIso(input["from"]?.toStr ?: "");to:=DateTime.fromIso(input["to"]?.toStr ?: "")
    ids:=EnerCubixMath.strings(input["legacyIds"]).unique
    if (to <= from || to-from > 366day || ids.isEmpty || ids.size > 100 || sources.size < 2 || sources.size > 8) throw ArgErr("legacyTopologyInvalidProof")
    sorted:=sources.dup.sort |a,b| {DateTime.fromIso(a["capturedAt"].toStr) <=> DateTime.fromIso(b["capturedAt"].toStr)}
    if (DateTime.fromIso(sorted.last["capturedAt"].toStr) < to) throw ArgErr("legacyTopologyUnobservedRange")
    result:=[Str:Obj?][,]
    ids.each |id|
    {
      child:=EnerCubixMath.maps(sorted.first["records"]).find |r| {r["id"] == id}
      if (child == null || !["meter","totalMeter"].contains(child["kind"])) throw ArgErr("legacyTopologyMissingSource")
      parentId:=child["meterParentId"] as Str ?: throw ArgErr("legacyTopologyMissingSource")
      parent:=EnerCubixMath.maps(sorted.first["records"]).find |r| {r["id"] == parentId}
      if (parent == null || parent["categoryId"] != child["categoryId"]) throw ArgErr("legacyTopologyCategoryMismatch")
      nativeChild:=aliases[id] ?: throw ArgErr("legacyTopologyMissingMapping")
      nativeParent:=aliases[parentId] ?: throw ArgErr("legacyTopologyMissingMapping")
      if ((child["pointId"] as Str ?: "").isEmpty || (parent["pointId"] as Str ?: "").isEmpty || (child["unit"] as Str ?: "").isEmpty) throw ArgErr("legacyTopologyMissingSource")
      fields:=["id","pointId","meterParentId","categoryId","kind","unit","includeInTotals","expressionId","updatedAt"]
      sorted.each |s|
      {
        rs:=EnerCubixMath.maps(s["records"]);own:=rs.find |r| {r["id"] == id};up:=rs.find |r| {r["id"] == parentId}
        if (own == null || up == null || fields.any |k| {own[k] != child[k]} || ["pointId","categoryId","unit"].any |k| {up[k] != parent[k]}) throw ArgErr("legacyTopologyChangedSource")
        revision:=DateTime.fromIso((own["updatedAt"] ?: own["mod"]).toStr)
        if (revision > from || revision > DateTime.fromIso(s["capturedAt"].toStr)) throw ArgErr("legacyTopologyUnobservedRange")
      }
      included:=(Bool?)child["includeInTotals"] ?: child["expressionId"] == null
      result.add(["childId":nativeChild,"parentId":nativeParent,"legacyChildId":id,"legacyParentId":parentId,"pointId":child["pointId"],"parentPointId":parent["pointId"],"categoryId":child["categoryId"],"unit":child["unit"],"kind":child["kind"],"name":child["name"],"from":from.toIso,"to":to.toIso,"businessSince":child["updatedAt"] ?: child["mod"],"participating":included,"basis":"snapshotRecovered","proofId":"preview"])
    }
    validate(result)
    return ["from":from.toIso,"to":to.toIso,"edges":result,"sources":sorted.map |s->[Str:Obj?]| {s.findAll |v,k| {["file","sha256","capturedAt"].contains(k)}} ,"basis":"snapshotRecovered","strictEligible":false]
  }

  static [Str:Obj?][] edges(Str:Obj? request)
  { request["kind"] == "leak" && (request["metric"] ?: "energy") == "energy" ? EnerCubixMath.maps(request["legacyMembership"]) : [Str:Obj?][,] }

  static Str:Obj? record([Str:Obj?][] current, Str:Obj? edge)
  {
    id:=edge["childId"].toStr; point:=edge["pointId"].toStr
    existing:=current.find |r| {r["id"] == id}
    out:=existing?.dup ?: Str:Obj?[:]
    if (out["pointId"] != point || out["expressionId"] != edge["expressionId"]) out.remove("historyPointId")
    out.remove("expressionId"); out.remove("configurationError")
    out.setAll(["id":id,"kind":edge["kind"] ?: "meter","name":existing?.get("name") ?: (edge["name"] ?: id),"pointId":point,"categoryId":edge["categoryId"],"unit":edge["unit"],"meterParentId":edge["parentId"],"includeInTotals":true,"nativeEquip":true])
    if (edge["historyPointId"] != null) out["historyPointId"]=edge["historyPointId"]
    return out
  }

  static [Str:Obj?][] windows(Str:Obj? request, [Str:Obj?][] current, [Str:Obj?][] segments, Str master, Str category, Bool activeOnly := true)
  {
    from:=DateTime.fromIso(request["from"].toStr); to:=DateTime.fromIso(request["to"].toStr)
    out:=[Str:Obj?][,]
    edges(request).findAll |e| {e["parentId"] == master && e["categoryId"] == category && (!activeOnly || e["participating"] != false)}.each |edge|
    {
      a:=DateTime.fromIso(edge["from"].toStr); b:=DateTime.fromIso(edge["to"].toStr)
      segments.findAll |s| {s["known"] != true}.each |s|
      {
        start:=DateTime.fromIso(s["from"].toStr); end:=DateTime.fromIso(s["to"].toStr)
        if (start < from) start=from
        if (start < a) start=a
        if (end > to) end=to
        if (end > b) end=b
        if (end > start) out.add(["id":edge["childId"],"from":start.toIso,"to":end.toIso,"record":record(current,edge),"proofId":edge["proofId"],"participating":edge["participating"] != false])
      }
    }
    return out
  }

  static Bool used([Str:Obj?][] windows, DateTime from, DateTime to, Str? child := null)
  { windows.any |w| {(child == null || w["id"] == child) && DateTime.fromIso(w["from"].toStr) < to && DateTime.fromIso(w["to"].toStr) > from} }

  static Bool excluded([Str:Obj?][] windows, Str child, DateTime from, DateTime to)
  {
    cursor:=from
    windows.findAll |w| {w["id"] == child && w["participating"] == false}.sort |a,b| {DateTime.fromIso(a["from"].toStr) <=> DateTime.fromIso(b["from"].toStr)}.each |w|
    {
      a:=DateTime.fromIso(w["from"].toStr);b:=DateTime.fromIso(w["to"].toStr)
      if (a <= cursor && b > cursor) cursor=b
    }
    return cursor >= to
  }

  static Void validate([Str:Obj?][] edges)
  {
    edges.each |edge,i|
    {
      ["childId","parentId","pointId","categoryId","from","to","proofId"].each |key| {if ((edge[key] as Str ?: "").isEmpty) throw ArgErr("legacyTopologyInvalidProof")}
      from:=DateTime.fromIso(edge["from"].toStr); to:=DateTime.fromIso(edge["to"].toStr)
      if (to <= from || edge["childId"] == edge["parentId"]) throw ArgErr("legacyTopologyInvalidProof")
      edges.each |other,j|
      {
        if (j >= i || other["childId"] != edge["childId"]) return
        if (DateTime.fromIso(other["from"].toStr) < to && DateTime.fromIso(other["to"].toStr) > from) throw ArgErr("legacyTopologyOverlap")
      }
      checkPath(edges,edge["parentId"].toStr,from,to,[edge["childId"].toStr])
    }
  }

  ** Follow every overlapping transition, preserving the common time window.
  ** A path is cyclic only while all of its relationships coexist.
  private static Void checkPath([Str:Obj?][] edges,Str parent,DateTime from,DateTime to,Str[] seen)
  {
    if (seen.contains(parent)) throw ArgErr("legacyTopologyCycle")
    path:=seen.dup.add(parent)
    edges.findAll |e| {e["childId"] == parent && DateTime.fromIso(e["from"].toStr) < to && DateTime.fromIso(e["to"].toStr) > from}.each |next|
    {
      a:=DateTime.fromIso(next["from"].toStr);b:=DateTime.fromIso(next["to"].toStr)
      if (a < from) a=from
      if (b > to) b=to
      checkPath(edges,next["parentId"].toStr,a,b,path)
    }
  }
}

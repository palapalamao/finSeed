** Orthogonal report membership. Legacy reports never construct this projection.
class SeedDimension
{
  new make(Str dimension, [Str:Obj?][] source, Bool nativeSpace := false)
  {
    if (!["space","metering","organization"].contains(dimension)) throw ArgErr("Invalid report dimension")
    this.dimension=dimension
    this.nativeSpace=dimension == "space" && nativeSpace
    source.each |r| { id:=r["id"]?.toStr; if (id != null) originals[id]=r }
    source.each |r|
    {
      id:=r["id"]?.toStr
      if (id == null || canonical(id) != id) return
      copy:=r.dup
      ["meterParentId","numeratorId","denominatorId"].each |key|
      { ref:=copy[key]?.toStr; if (ref != null) copy[key]=canonical(ref) }
      if (copy["variables"] is Map)
      {
        vars:=Str:Obj?[:]
        ((Map)copy["variables"]).each |Obj? ref, Obj key| { vars[key.toStr]=ref == null ? null : canonical(ref.toStr) }
        copy["variables"]=vars
      }
      records.add(copy); byId[id]=copy
    }
  }

  Str dimension
  Bool nativeSpace
  [Str:Obj?][] records := [,]
  internal Str:[Str:Obj?] byId := [:]
  private Str:[Str:Obj?] originals := [:]

  static Bool active(Str:Obj? request)
  {
    value:=request["dimension"]?.toStr
    if (value == null || value == "legacy") return false
    if (!["space","metering","organization"].contains(value)) throw ArgErr("Invalid report dimension")
    return true
  }

  Str canonical(Str id)
  {
    seen:=Str[,]; current:=id
    while (true)
    {
      if (seen.contains(current)) throw ArgErr("Cyclic canonical meter reference")
      seen.add(current)
      ref:=originals[current]?.get("canonicalId")?.toStr
      if (ref == null) return current
      if (!originals.containsKey(ref)) throw ArgErr("Unknown canonical meter: $ref")
      current=ref
    }
    return id
  }

  Str:Obj? normalizeRequest(Str:Obj? source)
  {
    out:=source.dup
    ["nodeIds","referenceIds"].each |key| { if (source[key] != null) out[key]=SeedMath.strings(source[key]).map |id->Str| { canonical(id) }.unique }
    ["xId","yId"].each |key| { id:=source[key]?.toStr; if (id != null) out[key]=canonical(id) }
    return out
  }

  Bool scope(Str id) { dimension != "metering" && byId[id]?.get("kind") == dimension && (!nativeSpace || byId[id]?.get("nativeHidden") != true) }

  Str[] roots()
  {
    if (dimension == "metering") return records.findAll |r| { included(r) && r["meterParentId"] == null }.map |r->Str| { r["id"].toStr }
    return records.findAll |r| { scope(r["id"].toStr) && r["parentId"] == null }.map |r->Str| { r["id"].toStr }
  }

  ** Only confirmed membership edges are followed; legacy parentId is irrelevant.
  [Str:Obj?][] members(Str id)
  {
    if (!scope(id)) return [Str:Obj?][,]
    return records.findAll |r| { included(r) && within(membership(r),id,dimension) }
  }

  [Str:Obj?][] directChildren(Str id)
  { records.findAll |r| { included(r) && r["meterParentId"]?.toStr == id } }

  [Str:Obj?][] frontier([Str:Obj?][] candidates)
  {
    ids:=candidates.map |r->Str| { r["id"].toStr }
    return candidates.findAll |r| { !ancestors(r["id"].toStr).any |parent| { ids.contains(parent) } }
  }

  ** Usage describes measured end branches; a master-child difference is not a use.
  [Str:Obj?][] usageFrontier([Str:Obj?][] candidates)
  {
    return candidates.findAll |r| { !candidates.any |other| { ancestors(other["id"].toStr).contains(r["id"].toStr) } }
  }

  ** One denominator for the union; overlapping selected child scopes add no area.
  internal SeedValue selectionArea(Str[] selected)
  {
    ids:=selected.map |id->Str| { canonical(id) }.unique
    scopes:=ids.findAll |id| { scope(id) }
    scopes=scopes.findAll |id| { !scopes.any |other| { id != other && within(id,other,dimension) } }
    [Str:Obj?][] meters:=ids.findAll |id| { r:=byId[id]; return r != null && included(r) }.map |id->[Str:Obj?]| { (Str:Obj?)byId[id] }
    covered:=Str[,]
    scopes.each |id| { covered.addAll(members(id).map |m->Str| { m["id"].toStr }) }
    meters=frontier(meters.findAll |Str:Obj? m->Bool| { !covered.contains(m["id"].toStr) })
    if (!scopes.isEmpty && !meters.isEmpty) return SeedValue(null,"ambiguousArea")
    [Str:Obj?][] areas:=scopes.isEmpty ? meters : scopes.map |id->[Str:Obj?]| { (Str:Obj?)byId[id] }
    if (areas.isEmpty) return SeedValue(null,"missingArea")
    total:=0f; missing:=false
    areas.each |Str:Obj? r|
    {
      area:=SeedMath.num(r["area"])
      if (area == null || area <= 0f) missing=true
      else total+=area
    }
    return missing ? SeedValue(null,"missingArea") : SeedValue(total,"ok")
  }

  Str? quality([Str:Obj?][] candidates)
  {
    if (candidates.any |r| { invalidChain(r["id"].toStr) }) return "topologyIncomplete"
    selected:=candidates.map |r->Str| { r["id"].toStr }
    if (dimension == "organization")
    {
      // An attributed upstream reading includes another owner's confirmed branch.
      shared:=candidates.any |r|
      {
        id:=r["id"].toStr
        return records.any |other|
        {
          if (!included(other) || other["categoryId"] != r["categoryId"] || selected.contains(other["id"].toStr)) return false
          otherId:=other["id"].toStr
          owner:=r["organizationId"]?.toStr
          if (owner != null && within(other["organizationId"]?.toStr,owner,"organization")) return false
          if (ancestors(otherId).contains(id)) return true
          return master(r) && !ancestors(id).contains(otherId) && overlap(r,other)
        }
      }
      if (shared) return "accountingIncomplete"
    }
    roots:=frontier(candidates)
    for (i:=0;i<roots.size;i++) for (j:=i+1;j<roots.size;j++)
    {
      a:=roots[i]; b:=roots[j]
      if ((master(a) || master(b)) && overlap(a,b)) return "topologyIncomplete"
    }
    return null
  }

  Bool utilityAllowed(Str id)
  {
    if (!scope(id)) return false
    parent:=byId[byId[id]?.get("parentId")?.toStr ?: ""]
    return parent == null || parent["parentId"] == null
  }

  Str? leakQuality(Str id)
  {
    r:=byId[id]
    if (r == null || invalidChain(id)) return "topologyIncomplete"
    // An unlinked reading in the master's coverage cannot be silently ignored.
    incomplete:=records.any |other|
    {
      otherId:=other["id"].toStr
      if (otherId == id || !included(other) || other["categoryId"] != r["categoryId"]) return false
      if (ancestors(otherId).contains(id) || ancestors(id).contains(otherId)) return false
      return overlap(r,other)
    }
    return incomplete ? "topologyIncomplete" : null
  }

  ** Shared with history planning so native reads use precisely the new membership.
  static Str:Obj? dependencies(Str:Obj? request, [Str:Obj?][] records)
  {
    dim:=SeedDimension(request["dimension"]?.toStr ?: "",records,request["spaceSource"] == "fin")
    req:=dim.normalizeRequest(request)
    selected:=SeedMath.strings(req["nodeIds"])
    if (selected.isEmpty && req["kind"] == "dashboard") selected=dim.roots
    selected=selected.dup.addAll(SeedMath.strings(req["referenceIds"]))
    ["xId","yId"].each |key| { id:=req[key]?.toStr; if (id != null) selected.add(id) }
    points:=Str[,]; nodes:=Str[,]
    selected.unique.each |id| { dim.collect(id,req["kind"] == "leak",nodes,points) }
    return ["points":points.unique.sort,"nodes":nodes.unique]
  }

  private Void collect(Str id, Bool leak, Str[] nodes, Str[] points)
  {
    if (nodes.contains(id)) return
    nodes.add(id)
    r:=byId[id]
    if (r == null) { points.add(id); return }
    if (r["kind"] == "nativePoint" || (nativeSpace && r["nativeSourceMissing"] == true)) return
    if (scope(id)) members(id).each |m| { collect(m["id"].toStr,false,nodes,points) }
    else if (r["kind"] == "group") records.findAll |m| { m["parentId"]?.toStr == id }.each |m| { collect(m["id"].toStr,false,nodes,points) }
    else
    {
      point:=r["pointId"]?.toStr
      if (point != null && !point.isEmpty && r["expressionId"] == null) points.add(point)
      if (leak) directChildren(id).each |m| { collect(m["id"].toStr,false,nodes,points) }
      ["numeratorId","denominatorId"].each |key| { ref:=r[key]?.toStr; if (ref != null) collect(ref,false,nodes,points) }
      expr:=byId[r["expressionId"]?.toStr ?: ""]
      vars:=expr?.get("variables") as Map
      if (vars != null) vars.each |Obj? ref, Obj name| { if (ref != null) collect(ref.toStr,false,nodes,points) }
    }
  }

  private Bool within(Str? member, Str root, Str kind)
  {
    seen:=Str[,]; cursor:=member
    while (cursor != null && !seen.contains(cursor))
    {
      r:=byId[cursor]
      if (r == null || r["kind"] != kind) return false
      if (nativeSpace && kind == "space" && r["nativeHidden"] == true) return false
      if (cursor == root) return true
      seen.add(cursor); cursor=r["parentId"]?.toStr
    }
    return false
  }

  private Str[] ancestors(Str id)
  {
    out:=Str[,]; cursor:=byId[id]?.get("meterParentId")?.toStr
    while (cursor != null && cursor != id && !out.contains(cursor))
    { out.add(cursor); cursor=byId[cursor]?.get("meterParentId")?.toStr }
    return out
  }

  private Bool invalidChain(Str id)
  {
    seen:=[id]; cursor:=byId[id]?.get("meterParentId")?.toStr
    while (cursor != null)
    {
      if (seen.contains(cursor)) return true
      parent:=byId[cursor]
      if (parent == null || !["meter","totalMeter"].contains(parent["kind"]?.toStr ?: "")) return true
      seen.add(cursor); cursor=parent["meterParentId"]?.toStr
    }
    return false
  }

  private Bool overlap(Str:Obj? a, Str:Obj? b)
  {
    aParents:=ancestors(a["id"].toStr); bParents:=ancestors(b["id"].toStr)
    if (!aParents.contains(b["id"].toStr) && !bParents.contains(a["id"].toStr) && aParents.any |id| { bParents.contains(id) }) return false
    x:=spaceMembership(a); y:=spaceMembership(b)
    if (x == null || y == null) return true
    return within(x,y,"space") || within(y,x,"space")
  }

  private Bool master(Str:Obj? r)
  { r["kind"] == "totalMeter" || records.any |other| { included(other) && other["meterParentId"] == r["id"] } }

  private Bool included(Str:Obj? r)
  {
    if (!["meter","totalMeter"].contains(r["kind"]?.toStr ?: "")) return false
    return (Bool?)r["includeInTotals"] ?: (r["expressionId"] == null)
  }

  private Str? membership(Str:Obj? r)
  { dimension == "space" ? spaceMembership(r) : r["organizationId"]?.toStr }

  private Str? spaceMembership(Str:Obj? r)
  {
    if (nativeSpace && r["pointId"] != null && r["expressionId"] == null) return r["nativeSpaceId"]?.toStr
    return r["spaceId"]?.toStr
  }
}

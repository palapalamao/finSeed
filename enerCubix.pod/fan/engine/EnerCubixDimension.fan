** Orthogonal report membership. Legacy reports never construct this projection.
class EnerCubixDimension
{
  new make(Str dimension, [Str:Obj?][] source, Bool nativeSpace := false)
  {this.dimension=dimension;initialize(dimension,source,nativeSpace,null)}

  ** Private request-owned projection; the ordinary report constructor is unchanged.
  internal new owned(Str dimension,[Str:Obj?][] source,Bool nativeSpace,EnerCubixPreparedOwner owner)
  {
    this.dimension=dimension
    if(!source.isImmutable) throw ArgErr("catalogSourceNotFrozen")
    initialize(dimension,source,nativeSpace,owner)
  }
  internal new projected(Str dimension,EnerCubixDimension source,Bool nativeSpace)
  {
    if(!["space","metering","organization"].contains(dimension)) throw ArgErr("Invalid report dimension")
    this.dimension=dimension;this.nativeSpace=dimension=="space" && nativeSpace
    records=source.records;byId=source.byId;originals=source.originals
  }
  private Void initialize(Str dimension,[Str:Obj?][] source,Bool nativeSpace,EnerCubixPreparedOwner? owner)
  {
    if (!["space","metering","organization"].contains(dimension)) throw ArgErr("Invalid report dimension")
    this.nativeSpace=dimension == "space" && nativeSpace
    copies:=owner==null ? null : [Str:Obj?][,];variables:=owner==null ? null : Map[,]
    if(owner!=null)
    {
      owner.watch |->Void|
      {
        variables.each |Map v| {v.clear};copies.each |Map r| {r.clear}
        variables.clear;copies.clear;records.clear;byId.clear;originals.clear
      }
      owner.hold(8)
    }
    scratch:=owner==null ? null : EnerCubixPreparedOwner(owner.budget)
    try
    {
    // Canonical traversal has at most one reference per source record. This
    // scratch lease covers temporary seen paths, independently of retained maps.
    scratch?.hold(4+source.size)
    source.each |r| { id:=r["id"]?.toStr; if (id != null) {owner?.hold(1);originals[id]=r} }
    source.each |r|
    {
      id:=r["id"]?.toStr
      if (id == null || canonical(id) != id) return
      owner?.hold(2+r.size)
      copy:=r.dup
      copies?.add(copy)
      ["meterParentId","numeratorId","denominatorId"].each |key|
      { ref:=copy[key]?.toStr; if (ref != null) copy[key]=canonical(ref) }
      if (copy["variables"] is Map)
      {
        raw:=(Map)copy["variables"];owner?.hold(2+raw.size)
        vars:=Str:Obj?[:]
        copy["variables"]=vars
        variables?.add(vars)
        raw.each |Obj? ref, Obj key| { vars[key.toStr]=ref == null ? null : canonical(ref.toStr) }
      }
      owner?.hold(2)
      records.add(copy); byId[id]=copy
    }
    }
    finally {scratch?.close}
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
    ["nodeIds","referenceIds"].each |key| { if (source[key] != null) out[key]=EnerCubixMath.strings(source[key]).map |id->Str| { canonical(id) }.unique }
    ["xId","yId","baselineId"].each |key| { id:=source[key]?.toStr; if (id != null) out[key]=canonical(id) }
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
  internal EnerCubixValue selectionArea(Str[] selected)
  {
    area:=EnerCubixArea(records).selection(selected,this)
    return EnerCubixValue(EnerCubixMath.num(area["value"]),area["quality"].toStr)
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

  ** Metering usage follows only confirmed upstream links; other scopes keep their existing limits.
  [Str:Obj?][] usageMembers(Str id)
  {
    if (dimension != "metering") return members(id)
    if (!utilityAllowed(id)) return [Str:Obj?][,]
    return records.findAll |r| { r["id"] == id || (included(r) && ancestors(r["id"].toStr).contains(id)) }
  }

  Bool utilityAllowed(Str id)
  {
    if (dimension == "metering") return ["meter","totalMeter"].contains(byId[id]?.get("kind")?.toStr ?: "")
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
    if (request["kind"] == "energyFlow") records=EnerCubixEnergyFlow.normalizeRecords(records)
    dim:=EnerCubixDimension(request["dimension"]?.toStr ?: "",records,request["spaceSource"] == "fin")
    req:=dim.normalizeRequest(request)
    if (req["kind"] == "utility")
    {
      selected:=EnerCubixEndUse.resolve(EnerCubixContext(dim.records,[Str:Obj?][,],TimeZone.utc,dim),EnerCubixMath.strings(req["nodeIds"]))
      points:=selected.map |r->Str| {r["pointId"] as Str ?: ""}
      return ["points":points.findAll |Str id->Bool| {!id.isEmpty}.unique.sort,"nodes":selected.map |r->Str| {r["id"].toStr}]
    }
    if (req["kind"] == "energyFlow")
    {
      flow:=EnerCubixEnergyFlow.scope(req,dim)
      points:=Str[,]; nodes:=Str[,]
      EnerCubixMath.maps(flow["selected"]).addAll(EnerCubixMath.maps(flow["unassigned"])).each |r|
      { dim.collect(r["id"].toStr,false,nodes,points) }
      return ["points":points.unique.sort,"nodes":nodes.unique]
    }
    selected:=EnerCubixMath.strings(req["nodeIds"])
    if (selected.isEmpty && req["kind"] == "dashboard") selected=dim.roots
    selected=selected.dup.addAll(EnerCubixMath.strings(req["referenceIds"]))
    ["xId","yId"].each |key| { id:=req[key]?.toStr; if (id != null) selected.add(id) }
    points:=Str[,]; nodes:=Str[,]
    comparison:=EnerCubixComparisonScope.of(req,dim.records)
    if (comparison != null)
    {
      selected=EnerCubixMath.strings(req["nodeIds"]).dup.addAll(comparison.memberIds).unique
      selected.each |id|
      {
        r:=dim.byId[id]
        if (r == null || r["_comparisonReadable"] == false || r["_comparisonPointReadable"] == false) return
        nodes.add(id)
        point:=r["pointId"] as Str
        if (point != null) points.add(point)
      }
      return ["points":points.unique.sort,"nodes":nodes.unique]
    }
    selected.unique.each |id|
    {
      dim.collect(id,req["kind"] == "leak",nodes,points)
    }
    return ["points":points.unique.sort,"nodes":nodes.unique]
  }

  private Void collect(Str id, Bool leak, Str[] nodes, Str[] points)
  {
    if (nodes.contains(id)) return
    nodes.add(id)
    r:=byId[id]
    if (r == null) { if (records.any |row| {row["pointId"] == id}) points.add(id); return }
    if (r["kind"] == "nativePoint" || (nativeSpace && r["nativeSourceMissing"] == true)) return
    if (scope(id)) members(id).each |m| { collect(m["id"].toStr,false,nodes,points) }
    else if (r["kind"] == "group") records.findAll |m| { m["parentId"]?.toStr == id }.each |m| { collect(m["id"].toStr,false,nodes,points) }
    else
    {
      point:=r["pointId"] as Str
      if (point != null && !point.isEmpty) points.add(point)
      if (leak) directChildren(id).each |m| { collect(m["id"].toStr,false,nodes,points) }
      ["numeratorId","denominatorId"].each |key| { ref:=r[key]?.toStr; if (ref != null) collect(ref,false,nodes,points) }

    }
  }

  private Bool within(Str? member, Str root, Str kind)
  {
    seen:=Str[,]; cursor:=member
    while (cursor != null && !seen.contains(cursor))
    {
      r:=byId[cursor]
      if (r == null || (r["kind"] != kind && !(nativeSpace && kind == "space" && r["nativeEquip"] == true))) return false
      if (nativeSpace && kind == "space" && r["nativeHidden"] == true) return false
      if (cursor == root) return true
      seen.add(cursor); cursor=(nativeSpace && kind == "space" && r["nativeEquip"] == true) ? r["nativeTreeParentId"]?.toStr : r["parentId"]?.toStr
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
    if (r["nativeEquip"] == true) return (r["spaceId"] as Str) ?: (r["id"] as Str)
    if (nativeSpace && r["pointId"] != null && r["expressionId"] == null) return r["nativeSpaceId"]?.toStr
    return r["spaceId"]?.toStr
  }
}

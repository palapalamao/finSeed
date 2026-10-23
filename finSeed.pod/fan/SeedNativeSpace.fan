using haystack
using legacy
using skyarcd
using util

** Read-through FIN navigation; never persists or changes a native record.
class SeedNativeSpace
{
  Str path := ""
  Str[] warnings := [,]
  [Str:Obj?][] nodes := [,]

  static SeedNativeSpace load(Context cx)
  {
    out:=SeedNativeSpace()
    tree:=NavTree.find(cx,"equip",false)
    if (tree == null) { out.warnings.add("FIN equip navigation tree is unavailable"); return out }
    navPath:=tree.path(cx)
    out.path=navPath.toStr
    out.walk(cx,tree,navPath,null,null,0,Str:Bool[:])
    return out
  }

  private Void walk(Context cx, NavTree tree, NavPath navPath, Dict? base, Str? parent, Int depth, Str:Bool seen)
  {
    if (depth > 128) throw ArgErr("FIN navigation tree exceeds 128 levels")
    children:=tree.children(cx,base).findAll |rec| { cx.canRead(rec) && NavTree.canAccess(cx,navPath,rec) && (!rec.has("point") || rec.has("his")) }
    // A path level includes indented equips as well as their parents. Defer
    // those equips until their own parent is expanded, regardless of sorting.
    childRoots(children) |rec->Ref?| { tree.isIndentable(cx,rec) ? tree.indentParentRef(cx,rec) : null }.each |rec|
    {
      id:=rec.id.id
      if (seen.containsKey(id)) { if (warnings.size < 20) warnings.add("Repeated FIN navigation node: $id"); return }
      if (nodes.size >= 50000) throw ArgErr("FIN navigation tree exceeds 50000 nodes")
      seen[id]=true
      sourceKind:=rec.has("point") ? "point" : (navPath.segForRec(rec)?.tag ?: "equip")
      node:=Str:Obj?["id":id,"name":rec["navName"] as Str ?: rec.dis,"parentId":parent,"sourceKind":sourceKind,"nativeDis":rec.dis,"mod":SeedRepo.iso(rec["mod"])]
      area:=rec["area"]
      if (area is Number) node["area"]=((Number)area).toFloat
      if (sourceKind == "point")
      {
        node["unit"]=rec["unit"]?.toStr
        node["his"]=rec.has("his")
        node["pointKind"]=rec["kind"]?.toStr
        node["hisMode"]=rec["hisMode"]?.toStr
        node["energyTags"]=["elec","water","gas","steam","heat","chilledWater","hotWater","fuelOil"].findAll |tag| { rec[tag] is Marker || base?.get(tag) is Marker }
      }
      nodes.add(node)
      // Points are leaves even when an unusual source has reference tags.
      if (sourceKind != "point") walk(cx,tree,navPath,rec,id,depth+1,seen)
    }
  }

  internal static Dict[] childRoots(Dict[] children, |Dict->Ref?| indentParent)
  {
    ids:=Ref:Bool[:]
    children.each |rec| { ids[rec.id]=true }
    return children.findAll |rec| { parent:=indentParent(rec); return parent == null || !ids.containsKey(parent) }
  }

  ** Pure projection. Overlay IDs are reused only when they already exist.
  [Str:Obj?][] project([Str:Obj?][] stored)
  {
    ids:=Str:Str[:]
    overlays:=Str:[Str:Obj?][:]
    stored.findAll |r| { r["kind"] == "space" && r["migrationSourceId"] != null }.sort |a,b| { a["id"].toStr <=> b["id"].toStr }.each |r|
    {
      source:=r["migrationSourceId"].toStr
      if (!overlays.containsKey(source)) overlays[source]=r
    }
    nodes.each |n| { source:=n["id"].toStr; ids[source]=n["sourceKind"] == "point" ? source : (overlays[source]?.get("id")?.toStr ?: source) }
    projected:=[Str:Obj?][,]
    points:=Str:[Str:Obj?][:]
    nodes.each |n|
    {
      source:=n["id"].toStr
      isPoint:=n["sourceKind"] == "point"
      r:=isPoint ? Str:Obj?[:] : (overlays[source]?.dup ?: Str:Obj?[:])
      r["id"]=ids[source]; r["kind"]=isPoint ? "nativePoint" : "space"
      r["name"]=n["name"]; r["parentId"]=ids[n["parentId"]?.toStr ?: ""]
      r["nativeReadonly"]=true; r["nativeSourceId"]=source; r["nativeSourceKind"]=n["sourceKind"]
      r["nativeDis"]=n["nativeDis"] ?: n["name"]
      r["mod"]=n["mod"]
      if (n["sourceKind"] == "equip")
      {
        business:=stored.find |s| { s["id"] == source && s["nativeEquip"] == true }
        if (business != null)
        {
          business.each |v,k| { r[k]=v }
          r["parentId"]=business["parentId"]
          r["nativeReadonly"]=false
          r["nativeTreeParentId"]=ids[n["parentId"]?.toStr ?: ""]
          r["nativeSpaceId"]=r["spaceId"] ?: source
        }
      }
      if (n["area"] != null && r["area"] == null) r["area"]=n["area"]
      if (isPoint)
      {
        ["unit","his","pointKind","hisMode","energyTags"].each |key| { if (n[key] != null) r[key]=n[key] }
        points[source]=r
      }
      projected.add(r)
    }
    nativeIds:=projected.map |r->Str| { r["id"].toStr }
    stored.each |old|
    {
      if (nativeIds.contains(old["id"])) return
      r:=clean(old)
      if (old["nativeEquip"] == true)
      {
        r["nativeEquip"]=true
        r["nativeDis"]=old["nativeDis"]
        r["nativeSourceKind"]="equip"
        r["nativeSpaceId"]=r["spaceId"] ?: r["id"]
      }
      if (r["kind"] == "space") r["nativeHidden"]=true
      if (SeedRelations.meterKinds.contains(r["kind"]) && r["pointId"] != null && r["expressionId"] == null)
      {
        point:=points[r["pointId"].toStr]
        r["nativeSpaceReadonly"]=true
        if (point == null) r["nativeSourceMissing"]=true
        else r["nativeSpaceId"]=point["parentId"]
      }
      projected.add(r)
    }
    return projected
  }

  ** Ignore submitted presentation metadata; native write guards use live IDs.
  static [Str:Obj?] clean([Str:Obj?] record)
  {
    out:=record.dup
    out.keys.findAll |key| { key.startsWith("native") || ["configurationError","legacyId","legacyParentId"].contains(key) }.each |key| { out.remove(key) }
    return out
  }

  static Void mustEditable(Str? id, [Str:Obj?][] records)
  {
    if (id != null && records.any |r| { r["id"] == id && r["nativeReadonly"] == true })
      throw ArgErr("FIN 原生空间和点位为只读，请在 FIN 设备树中维护")
  }

  ** New physical bindings follow current FIN placement; edits retain old coverage.
  static Void placeBinding([Str:Obj?] record, [Str:Obj?]? previous, [Str:Obj?][] projection)
  {
    point:=record["pointId"] as Str
    if (point == null || record["expressionId"] != null || !SeedRelations.meterKinds.contains(record["kind"])) return
    if (previous != null && previous["pointId"] == point) return
    leaf:=projection.find |r| { r["kind"] == "nativePoint" && r["nativeSourceId"] == point }
    if (leaf != null) record["spaceId"]=leaf["parentId"]
  }

  [Str:Obj?] info([Str:Obj?][] stored)
  {
    projected:=project(stored)
    missing:=projected.findAll |r| { r["nativeSourceMissing"] == true }.size
    notices:=warnings.dup
    if (missing > 0) notices.add("$missing configured point sources are outside the visible FIN tree")
    return ["spaceSource":"fin","nativeTreePath":path,"nodeCount":nodes.size,
      "containerCount":nodes.findAll |r| { r["sourceKind"] != "point" }.size,
      "pointCount":nodes.findAll |r| { r["sourceKind"] == "point" }.size,
      "missingSourceCount":missing,"sourceSignature":JsonOutStream.writeJsonToStr(nodes).hash.toHex,"warnings":notices]
  }
}

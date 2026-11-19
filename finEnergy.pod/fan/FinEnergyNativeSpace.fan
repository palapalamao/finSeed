using haystack
using legacy
using skyarcd
using util

** Read-through FIN navigation. Area writes use the separate area-only save path.
class FinEnergyNativeSpace
{
  Str path := ""
  Str[] warnings := [,]
  [Str:Obj?][] nodes := [,]
  private FinEnergyPreparedOwner? owner
  private [Str:Bool]? analysisPoints

  static FinEnergyNativeSpace load(Context cx)
  {loadTree(cx,null)}

  internal static FinEnergyNativeSpace loadAnalysis(Context cx,[Str:Obj?][] stored,FinEnergyPreparedOwner? owner := null)
  {owner?.hold(1+2*stored.size);return loadTree(cx,analysisPointIds(stored),owner)}

  private static FinEnergyNativeSpace loadTree(Context cx,[Str:Bool]? keep,FinEnergyPreparedOwner? owner := null)
  {
    owner?.hold(8)
    out:=FinEnergyNativeSpace();out.analysisPoints=keep;out.owner=owner
    owner?.watch |->Void| {out.nodes.clear;out.warnings.clear;keep?.clear}
    tree:=NavTree.find(cx,"equip",false)
    if (tree == null) { out.warnings.add("FIN equip navigation tree is unavailable"); return out }
    navPath:=tree.path(cx)
    out.path=navPath.toStr
    out.walk(cx,tree,navPath,null,null,0,Str:Bool[:])
    return out
  }

  private Void walk(Context cx, NavTree tree, NavPath navPath, Dict? base, Str? parent, Int depth, Str:Bool seen)
  {
    owner?.budget?.deadline?.check
    if (depth > 128) throw ArgErr("FIN navigation tree exceeds 128 levels")
    children:=tree.children(cx,base).findAll |rec| { cx.canRead(rec) && NavTree.canAccess(cx,navPath,rec) && (!rec.has("point") || rec.has("his")) }
    // A path level includes indented equips as well as their parents. Defer
    // those equips until their own parent is expanded, regardless of sorting.
    childRoots(children) |rec->Ref?| { tree.isIndentable(cx,rec) ? tree.indentParentRef(cx,rec) : null }.each |rec|
    {
      id:=rec.id.id
      if (seen.containsKey(id)) { if (warnings.size < 20) warnings.add("Repeated FIN navigation node: $id"); return }
      if (seen.size >= 50000) throw ArgErr("FIN navigation tree exceeds 50000 nodes")
      owner?.hold(1);seen[id]=true
      if(rec.has("point") && analysisPoints!=null && !analysisPoints.containsKey(id)) return
      owner?.hold(30)
      sourceKind:=rec.has("point") ? "point" : (navPath.segForRec(rec)?.tag ?: "equip")
      node:=Str:Obj?["id":id,"name":rec["navName"] as Str ?: rec.dis,"parentId":parent,"sourceKind":sourceKind,"nativeDis":rec.dis,"mod":FinEnergyRepo.iso(rec["mod"])]
      // Navigation records may omit native tags. Freeze the actual readable
      // Site/Floor record's area and revision together, never an overlay value.
      original:=["site","floor"].contains(sourceKind) ? cx.db.readById(rec.id,false) : rec
      if (original != null && !cx.canRead(original)) original=null
      area:=FinEnergySpaceArea.squareMetres(original?.get("area"))
      if (area != null) node["area"]=area
      if (["site","floor"].contains(sourceKind))
      {
        node["mod"]=FinEnergyRepo.iso(original?.get("mod"))
        if (original != null) node["nativeArea"]=FinEnergySpaceArea.provenance(original)
      }
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

  internal static Str:Bool analysisPointIds([Str:Obj?][] stored)
  {
    keep:=Str:Bool[:]
    stored.each |r|
    {
      // Preserve nativeIds shadowing for any stored-ID collision as well as
      // every configured primary point, independently of visibility/category.
      id:=r["id"] as Str;if(id!=null) keep[id]=true
      point:=r["pointId"] as Str
      if(FinEnergyRelations.meterKinds.contains(r["kind"]) && point!=null) keep[point]=true
    }
    return keep
  }

  ** Pure equivalent of the private DTO filter, for complete projection parity.
  internal FinEnergyNativeSpace forAnalysis([Str:Obj?][] stored)
  {
    keep:=analysisPointIds(stored);out:=FinEnergyNativeSpace();out.path=path;out.warnings=warnings.dup
    out.nodes=nodes.findAll |n| {n["sourceKind"]!="point" || keep.containsKey(n["id"].toStr)}
    return out
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
    owner?.hold(5+3*nodes.size+3*stored.size)
    ids:=Str:Str[:]
    overlays:=Str:[Str:Obj?][:]
    stored.findAll |r| { r["kind"] == "space" && r["migrationSourceId"] != null }.sort |a,b| { a["id"].toStr <=> b["id"].toStr }.each |r|
    {
      source:=r["migrationSourceId"].toStr
      if (!overlays.containsKey(source)) overlays[source]=r
    }
    nodes.each |n| { source:=n["id"].toStr; ids[source]=n["sourceKind"] == "point" ? source : (overlays[source]?.get("id")?.toStr ?: source) }
    projected:=[Str:Obj?][,]
    owner?.watch |->Void| {projected.clear}
    points:=Str:[Str:Obj?][:]
    nodes.each |n|
    {
      source:=n["id"].toStr
      isPoint:=n["sourceKind"] == "point"
      owner?.hold(30+(overlays[source]?.size ?: 0))
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
          owner?.hold(business.size)
          business.each |v,k| { r[k]=v }
          r["parentId"]=business["parentId"]
          r["nativeReadonly"]=false
          r["nativeTreeParentId"]=ids[n["parentId"]?.toStr ?: ""]
          r["nativeSpaceId"]=r["spaceId"] ?: source
        }
      }
      // FIN is authoritative for native space area, including a cleared value.
      if (["site","floor"].contains(n["sourceKind"]))
      {
        r.remove("area")
        if (n["area"] != null) r["area"]=n["area"]
        r["nativeArea"]=n["nativeArea"]
      }
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
      owner?.hold(10+3*old.size)
      r:=clean(old)
      if (old["nativeEquip"] == true)
      {
        r["nativeEquip"]=true
        r["nativeDis"]=old["nativeDis"]
        r["nativeSourceKind"]="equip"
        r["nativeSpaceId"]=r["spaceId"] ?: r["id"]
      }
      if (r["kind"] == "space") r["nativeHidden"]=true
      if (FinEnergyRelations.meterKinds.contains(r["kind"]) && r["pointId"] != null && r["expressionId"] == null)
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
    alarmFields:=record["kind"] == "alarm" ? ["nativeAlarmId","nativeAlarmArchive","nativeRecoveredAt"] : Str[,]
    out.keys.findAll |key| { (key.startsWith("native") && !alarmFields.contains(key)) || ["configurationError","areaConfigurationError","legacyId","legacyParentId","meterOrigin"].contains(key) }.each |key| { out.remove(key) }
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
    if (point == null || record["expressionId"] != null || !FinEnergyRelations.meterKinds.contains(record["kind"])) return
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

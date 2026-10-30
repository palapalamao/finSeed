** Explicit physical area provenance. Meter placement never implies service area.
internal class EnerCubixArea
{
  new make([Str:Obj?][] records)
  {
    records.each |r|
    {
      byId[r["id"].toStr]=r
      if (r["kind"] == "space" && r["nativeSourceId"] != null) nativeIds[r["nativeSourceId"].toStr]=r["id"].toStr
    }
  }
  private Str:[Str:Obj?] byId := [:]
  private Str:Str nativeIds := [:]

  Str:Obj? node(Str id)
  {
    r:=find(id)
    if (r == null) return result([,],"missingArea")
    if (r["kind"] == "space") return spaceArea(r)
    if (r["areaSource"] == "space")
    {
      target:=find(r["areaSpaceId"] as Str ?: "")
      if (target == null || target["kind"] != "space") return result([,],"missingArea")
      return spaceArea(target)
    }
    return result([source(r,"custom")])
  }

  Str:Obj? selection(Str[] selected, EnerCubixDimension? dimension := null)
  {
    ids:=selected.map |id->Str| {dimension?.canonical(id) ?: id}.unique
    scopes:=ids.findAll |id->Bool| {dimension == null ? find(id)?.get("kind") == "group" : dimension.scope(id)}
    scopes=scopes.findAll |id| {!scopes.any |other| {id != other && inside(id,other)}}
    covered:=Str[,]
    scopes.each |id|
    {
      if (dimension != null) covered.addAll(dimension.members(id).map |r->Str| {r["id"].toStr})
      else ids.findAll |other| {inside(other,id)}.each |other| {covered.add(other)}
    }
    meters:=ids.findAll |id| {!scopes.contains(id) && !covered.contains(id) && ["meter","totalMeter"].contains(find(id)?.get("kind")?.toStr ?: "")}
    meters=meters.findAll |id| {!meters.any |other| {id != other && inside(id,other,"meterParentId")}}
    sources:=[Str:Obj?][,]; missing:=false
    scopes.dup.addAll(meters).unique.each |id|
    {
      area:=node(id)
      if (area["quality"] != "ok") missing=true
      sources.addAll(EnerCubixMath.maps(area["sources"]))
    }
    unique:=Str:[Str:Obj?][:]
    sources.each |s| {unique[s["source"].toStr+"|"+s["id"].toStr]=s}
    sources=unique.vals
    sources=sources.findAll |s|
    {
      return s["source"] != "space" || !sources.any |other|
      {other["source"] == "space" && s["id"] != other["id"] && inside(s["id"].toStr,other["id"].toStr)}
    }
    if (sources.size > 1 && sources.any |s| {s["source"] == "custom"}) return result(sources,"ambiguousArea")
    if (missing || sources.isEmpty) return result(sources,"missingArea")
    return result(sources)
  }

  static EnerCubixValue scale(EnerCubixValue value, Str:Obj? area)
  {
    n:=EnerCubixMath.num(area["value"])
    return n == null || n <= 0f ? EnerCubixValue(null,area["quality"].toStr,value.sources) : value.scale(1f/n)
  }

  private [Str:Obj?]? find(Str id) {byId[id] ?: byId[nativeIds[id] ?: ""]}

  private Str:Obj? spaceArea(Str:Obj? r)
  {
    kind:=r["nativeSourceKind"] as Str
    if (kind != null && !["site","floor"].contains(kind)) return result([,],"missingArea")
    return result([source(r,"space")])
  }

  private Str:Obj? source(Str:Obj? r, Str kind)
  {
    id:=kind == "space" ? (r["nativeSourceId"] ?: r["id"]) : r["id"]
    return ["id":id,"name":r["name"] ?: id,"area":EnerCubixMath.num(r["area"]),"source":kind]
  }

  private Str:Obj? result([Str:Obj?][] sources, Str? quality := null)
  {
    sorted:=sources.dup.sort |a,b| {a["id"].toStr <=> b["id"].toStr}
    invalid:=sorted.any |s| {n:=EnerCubixMath.num(s["area"]);return n == null || n <= 0f || n.isNaN || n.abs == Float.posInf}
    if (quality == null) quality=sorted.isEmpty || invalid ? "missingArea" : "ok"
    total:=quality == "ok" ? sorted.reduce(0f) |Float sum,s->Float| {sum+(Float)s["area"]} : null
    return ["value":total,"quality":quality,"unit":"m²","sources":sorted]
  }

  private Bool inside(Str child, Str ancestor, Str relation := "parentId")
  {
    target:=find(ancestor); cursor:=find(child); seen:=Str[,]
    if (target == null || cursor == null) return false
    while (cursor != null)
    {
      id:=cursor["id"].toStr
      if (id == target["id"]) return true
      if (seen.contains(id)) return false
      seen.add(id);cursor=find(cursor[relation] as Str ?: "")
    }
    return false
  }
}

using haystack
using folio

** Native point metadata only. Exact resolution never scans the project catalog.
internal class FinEnergyPointCatalog
{
  static Str:Obj? resolve(Folio db,|Dict->Bool| canRead,Str:Obj? body)
  {
    ids:=body["ids"] as List
    if(body.keys.any |k| {k!="ids"} || ids==null || ids.size>200 || ids.any |id| {id isnot Str || id.toStr.isEmpty}) throw ArgErr("pointBatchInvalid")
    reader:=FinEnergyPointCatalog(db,canRead)
    items:=[Str:Obj?][,];seen:=Str:Bool[:]
    ids.each |id|
    {
      key:=id.toStr;if(seen.containsKey(key)) return;seen[key]=true
      r:=reader.read(key)
      if(r!=null && r.has("point") && !r.has("finEnergyComputed")) items.add(reader.project(r))
    }
    return ["items":items]
  }

  static Str:Obj? page(Folio db,|Dict->Bool| canRead,Str query:="",Int offset:=0,Int limit:=200,Str? equipId:=null)
  {
    if(offset<0 || limit<1 || limit>500) throw ArgErr("分页范围无效")
    reader:=FinEnergyPointCatalog(db,canRead)
    filter:=Filter.has("point")
    if(equipId!=null)
    {
      eq:=reader.read(equipId)
      if(eq==null || !eq.has("equip")) return ["items":[Str:Obj?][,],"total":0,"offset":offset,"limit":limit]
      filter=filter.and(Filter.eq("equipRef",eq.id))
    }
    q:=query.lower
    rows:=db.readAllList(filter).findAll |r| {canRead(r) && !r.has("finEnergyComputed") && (q.isEmpty || r.dis.lower.contains(q) || r.id.id.lower.contains(q))}
    end:=(offset+limit).min(rows.size)
    return ["items":offset>=end ? [Str:Obj?][,] : rows[offset..<end].map |r->Str:Obj?| {reader.project(r)},"total":rows.size,"offset":offset,"limit":limit]
  }

  new make(Folio db,|Dict->Bool| canRead) {this.db=db;this.canRead=canRead}
  private Folio db
  private |Dict->Bool| canRead
  private Str:Dict? cache:=[:]
  private Dict? read(Str id)
  {
    if(!cache.containsKey(id)) {r:=db.readById(Ref(id),false);cache[id]=r!=null && canRead(r) ? r : null}
    return cache[id]
  }
  Str:Obj? project(Dict r)
  {
    equip:=r["equipRef"] as Ref;eq:=equip==null ? null : read(equip.id)
    floor:=(r["floorRef"] as Ref) ?: (eq?.get("floorRef") as Ref)
    site:=(r["siteRef"] as Ref) ?: (eq?.get("siteRef") as Ref)
    floorRec:=floor==null ? null : read(floor.id);siteRec:=site==null ? null : read(site.id)
    energyTags:=["elec","water","gas","steam","heat","chilledWater","hotWater","fuelOil"].findAll |tag| {r[tag] is Marker || eq?.get(tag) is Marker}
    return ["id":r.id.id,"name":r.dis,"navName":r["navName"] as Str,"unit":r["unit"],"kind":r["kind"],"his":r.has("his"),"hisMode":r["hisMode"],"source":r["connRef"]?.toStr,"hisStart":iso(r["hisStart"]),"hisEnd":iso(r["hisEnd"]),"curStatus":r["curStatus"],"hisStatus":r["hisStatus"],"hisErr":r["hisErr"],"hisLastCollect":iso(r["hisCollectLastTime"]),"equipName":eq?.dis,"equipNavName":eq?.get("navName") as Str,"floorName":floorRec?.dis,"siteName":siteRec?.dis,"energyTags":energyTags,"equipId":eq?.id?.id,"floorId":floorRec?.id?.id,"siteId":siteRec?.id?.id]
  }
  private static Str? iso(Obj? value) {value is DateTime ? ((DateTime)value).toIso : value?.toStr}
}

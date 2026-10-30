using haystack
using folio
using skyarcd

** Native writes touch only disposable fixtures in the registered isolated project.
class EnerCubixAreaAcceptance
{
  Context cx
  EnerCubixRepo repo
  Ref[] owned := [,]
  Int checks := 0
  new make(Context cx) { this.cx=cx; repo=EnerCubixRepo(cx) }

  Str:Obj? run()
  {
    if (cx.proj.name != "finseed_acceptance") throw ArgErr("Area acceptance requires the isolated project")
    repo.mustWrite
    try
    {
      site:=source(["site":Marker.val,"dis":"Area acceptance "+DateTime.nowTicks,"navName":"Area acceptance","tz":"Shanghai","area":Number(3000f,Unit.fromStr("m²"))])
      floor:=source(["floor":Marker.val,"dis":"Area acceptance floor","navName":"Area acceptance floor","siteRef":site.id,"area":Number(1000f,Unit.fromStr("m²"))])
      row:=space(floor.id)
      check(row["area"] == 1000f,"native area is readable")
      saved:=repo.save(["id":row["id"],"mod":row["mod"],"kind":"space","areaOnly":true,"area":1200f])
      current:=cx.db.readById(floor.id)
      check(current["area"] == Number(1200f,Unit.fromStr("m²")),"save persists Number in m2 on the original FIN floor")
      check(current["siteRef"] == site.id && current.dis == floor.dis && current["navName"] == floor["navName"],"native identity and placement stay unchanged")
      check(!current.has("enerCubixKind") && !current.has("enerCubixConfig"),"native space receives no duplicate business area record")
      check(saved["area"] == 1200f && saved["id"] == row["id"],"refresh sees the native saved area")
      fails |->| { repo.save(["id":row["id"],"mod":row["mod"],"areaOnly":true,"area":1300f]) }
      fails |->| { repo.save(["id":saved["id"],"mod":saved["mod"],"areaOnly":true,"name":"Forbidden rename","area":1300f]) }
      fails |->| { repo.save(["id":saved["id"],"mod":saved["mod"],"areaOnly":true,"area":0f]) }
      check(cx.db.readById(floor.id)["area"] == Number(1200f,Unit.fromStr("m²")),"rejected writes preserve area")
      cleared:=repo.save(["id":saved["id"],"mod":saved["mod"],"kind":"space","areaOnly":true,"area":null])
      check(!cx.db.readById(floor.id).has("area") && cleared["area"] == null,"clearing removes the native area tag")
      return ["status":"passed","checks":checks,"project":cx.proj.name,"historyWrites":0]
    }
    finally
    {
      owned.dup.reverse.each |id| { rec:=cx.db.readById(id,false); if (rec != null) cx.db.commit(Diff(rec,null,Diff.remove)) }
    }
  }

  private Dict source(Str:Obj? tags)
  {
    id:=Ref.gen; cx.db.commit(Diff.makeAdd(Etc.makeDict(tags),id)); owned.add(id)
    return cx.db.readById(id)
  }
  private Str:Obj? space(Ref id)
  { repo.liveRecords.find |r| { r["nativeSourceId"] == id.id } ?: throw Err("Fixture is missing from native navigation") }
  private Void check(Bool condition, Str message)
  { if (!condition) throw Err(message); checks++ }
  private Void fails(|->| action)
  {
    Bool rejected:=false
    try { action() } catch (ArgErr e) { rejected=true } catch (EnerCubixHttpErr e) { rejected=true }
    check(rejected,"Expected native area write to be rejected")
  }
}

using haystack
using folio
using skyarcd

** Self-cleaning fixtures, restricted to the two dedicated acceptance projects.
class EnerCubixCleaningAcceptance
{
  Context cx
  EnerCubixRepo repo
  Ref[] owned := [,]
  Int checks := 0
  new make(Context cx) { this.cx=cx; repo=EnerCubixRepo(cx) }

  Str:Obj? run()
  {
    if (!["finseed_acceptance","enerCubix_acceptance"].contains(cx.proj.name)) throw ArgErr("Cleaning acceptance requires the isolated project")
    repo.mustWrite
    prefix:="Cleaning acceptance "+DateTime.nowTicks.toStr
    try
    {
      category:=save(["kind":"category","name":prefix+" energy","unit":"kWh"])
      site:=source(["site":Marker.val,"dis":prefix,"navName":prefix,"tz":"Shanghai"])
      floor:=source(["floor":Marker.val,"siteRef":site.id,"dis":prefix+" floor","navName":"floor"])
      eq1:=source(["equip":Marker.val,"dis":prefix+" A","navName":"A","siteRef":site.id,"floorRef":floor.id])
      eq2:=source(["equip":Marker.val,"dis":prefix+" B","navName":"B","siteRef":site.id,"floorRef":floor.id])
      p1:=point(eq1,site,"first"); p2:=point(eq2,site,"second"); alternate:=point(eq1,site,"alternate")
      original:=Etc.dictToMap(p1)
      profile:=save(["kind":"cleaningProfile","name":prefix+" profile","mode":"drop","parameters":["deltaMin":0,"timeMax":"1h","defNull":true]])
      eq1=attach(eq1,p1,category,profile)
      eq2=attach(eq2,p2,category,profile)
      check(cx.db.readById(p1.id)["hisTotalized"] === Marker.val,"an empty unmarked source is totalized before enabling cleaning in the same save")
      check(cx.db.readById(p1.id).has("enerCubixCleaningOwned"),"primary point ownership installed")
      check(cx.db.readById(eq1.id)["enerCubixCleaningEnabled"] === Marker.val,"equipment enable is a native Marker")
      check(cx.db.readById(p1.id)["enerCubixCleaningProfileRef"] == Ref(profile["id"].toStr),"profile is a native Ref")
      rejected(|->| { repo.remove(profile["id"].toStr,profile["mod"]) },"referenced profile deletion rejected")

      stale:=profile.dup
      edit:=profile.dup; edit["name"]=prefix+" renamed"; profile=repo.save(edit)
      rejected(|->| { repo.save(stale) },"stale profile revision rejected")
      check(cx.db.readById(p1.id)["enerCubixCleaningProfileVersion"] == Number(2),"first point version advanced")
      check(cx.db.readById(p2.id)["enerCubixCleaningProfileVersion"] == Number(2),"all referenced points updated atomically")
      beforeProfile:=cx.db.readById(Ref(profile["id"].toStr)); beforeP1:=cx.db.readById(p1.id); beforeP2:=cx.db.readById(p2.id)
      bad:=profile.dup; bad["parameters"]=["deltaMin":["type":"number","value":0,"unit":"L"],"defNull":true]
      rejected(|->| { repo.save(bad) },"incompatible unit rejected")
      check(cx.db.readById(beforeProfile.id)["mod"] == beforeProfile["mod"] && cx.db.readById(p1.id)["mod"] == beforeP1["mod"] && cx.db.readById(p2.id)["mod"] == beforeP2["mod"],"invalid profile leaves profile and all points unchanged")

      from:=DateTime.fromIso("2026-10-01T00:00:00+08:00").toTimeZone(TimeZone.fromStr("Shanghai"))
      values:=HisItem[,]
      [100f,110f,90f,120f].each |v,i| { values.add(HisItem(from+1hr*i,Number(v,Unit("kWh")))) }
      values.add(HisItem(from+4hr,NA.val)); values.add(HisItem(from+5hr,Number(130,Unit("kWh"))))
      // Explicit raw history writes exist only in this isolated fixture setup.
      cx.rt.his.write(cx.db.readById(p1.id),values,null).get(1min)
      span:=Span.makeAbs(from,from+6hr)
      raw:=read(p1.id,span,Etc.makeDict(["raw":Marker.val]))
      normal:=read(p1.id,span,Etc.emptyDict)
      check(raw.size == values.size && raw[0].val == values[0].val,"raw history retains cumulative source values")
      check(normal.any |v| { v.val === NA.val },"normal history preserves true NA")
      check(normal.any |v| { v.val == Number(10,Unit("kWh")) },"normal history returns interval consumption")
      preview:=EnerCubixCleaningRepo(repo).preview(["nodeId":eq1.id.id,"from":from.toIso,"to":(from+6hr).toIso])
      check(preview["status"] == "ok" && ((List)preview["raw"]).size == values.size,"read-only preview exposes raw and cleaned data")
      check(read(p1.id,span,Etc.makeDict(["raw":Marker.val])).map |v->Obj?| { v.val } == raw.map |v->Obj?| { v.val },"preview never rewrites raw history")

      // Main-point replacement must release the previous point in the same save.
      record:=EnerCubixRepo.decode(cx.db.readById(eq1.id)); record["pointId"]=alternate.id.id
      repo.save(record)
      check(!cx.db.readById(p1.id).has("enerCubixCleaningOwned") && cx.db.readById(alternate.id).has("enerCubixCleaningOwned"),"changing primary point restores previous ownership")
      cx.db.commit(Diff(cx.db.readById(alternate.id),Etc.makeDict(["description":"external note"])))
      record=EnerCubixRepo.decode(cx.db.readById(eq1.id)); record["cleaningEnabled"]=false
      repo.save(record)
      restored:=cx.db.readById(alternate.id)
      check(!restored.has("hisFunc") && !restored.has("hisFuncWritable") && !restored.has("enerCubixCleaningOwned"),"disable restores original history attributes")
      check(restored["description"] == "external note" && restored.has("hisTotalized") && restored["equipRef"] == eq1.id,"disable preserves unrelated point attributes")
      check(!cx.db.readById(p1.id).has("hisFunc") && cx.db.readById(p1.id)["unit"] == original["unit"],"previous point retains original unit and source attributes")

      // An unrelated computed function must never be adopted or overwritten.
      cx.db.commit(Diff(restored,Etc.makeDict(["hisFunc":"acceptanceExternalHis"])))
      record=EnerCubixRepo.decode(cx.db.readById(eq1.id)); record["cleaningEnabled"]=true
      beforeEq:=cx.db.readById(eq1.id)
      rejected(|->| { repo.save(record) },"external history function adoption rejected")
      check(cx.db.readById(eq1.id)["mod"] == beforeEq["mod"] && cx.db.readById(alternate.id)["hisFunc"] == "acceptanceExternalHis","rejected adoption changes neither equipment nor external function")
      return ["status":"passed","project":cx.proj.name,"checks":checks]
    }
    finally
    {
      owned.dup.reverse.each |id|
      {
        record:=cx.db.readById(id,false)
        if (record != null && record.has("enerCubixCleaningAcceptance")) cx.db.commit(Diff(record,null,Diff.remove))
      }
    }
  }

  private Dict attach(Dict equip, Dict point, Str:Obj? category, Str:Obj? profile)
  {
    data:=Str:Obj?["id":equip.id.id,"mod":EnerCubixRepo.iso(equip["mod"]),"kind":"meter","name":equip.dis,"pointId":point.id.id,"categoryId":category["id"],"cleaningEnabled":true,"cleaningProfileId":profile["id"],"historyMode":"auto"]
    repo.save(data)
    return cx.db.readById(equip.id)
  }
  private Dict source(Str:Obj? tags)
  {
    tags=tags.dup; tags["enerCubixCleaningAcceptance"]=Marker.val
    record:=cx.db.commit(Diff.makeAdd(Etc.makeDict(tags))).newRec
    owned.add(record.id); return cx.db.readById(record.id)
  }
  private Dict point(Dict equip, Dict site, Str name)
  { source(["point":Marker.val,"his":Marker.val,"hisMode":"consumption","kind":"Number","unit":"kWh","tz":"Shanghai","dis":name,"equipRef":equip.id,"siteRef":site.id]) }
  private Str:Obj? save(Str:Obj? data)
  {
    record:=repo.save(data); id:=Ref(record["id"].toStr); owned.add(id)
    cx.db.commit(Diff(cx.db.readById(id),Etc.makeDict(["enerCubixCleaningAcceptance":Marker.val])))
    return EnerCubixRepo.decode(cx.db.readById(id))
  }
  private HisItem[] read(Ref id, Span span, Dict opts)
  { out:=HisItem[,]; cx.rt.his.read(cx.db.readById(id),span,opts) |HisItem item| { out.add(item) }; return out }
  private Void check(Bool value, Str message) { if (!value) throw Err(message); checks++ }
  private Void rejected(|->| operation, Str message)
  {
    failed:=false
    try { operation() } catch (Err e) { failed=true }
    check(failed,message)
  }
}

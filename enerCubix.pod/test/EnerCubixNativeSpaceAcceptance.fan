using util
using haystack
using folio
using skyarcd
using legacy

** Real navigation mutations are restricted to owned fixtures in the isolated project.
class EnerCubixNativeSpaceAcceptance
{
  Context cx
  EnerCubixRepo repo
  Ref[] nativeOwned := [,]
  Str[] enerCubixOwned := [,]
  Int checks := 0
  new make(Context cx) { this.cx=cx; repo=EnerCubixRepo(cx) }

  Str:Obj? run()
  {
    if (cx.proj.name != "enerCubix_acceptance") throw ArgErr("Native-space acceptance requires isolated project")
    repo.mustWrite
    prefix:="原生空间验收 "+DateTime.nowTicks.toStr
    try
    {
      site:=source(["site":Marker.val,"dis":prefix+" 园区","navName":prefix+" 园区","tz":"Shanghai","area":Number(1000f)])
      floor:=source(["floor":Marker.val,"dis":prefix+" 功能目录","navName":"功能目录","siteRef":site.id])
      a:=source(["equip":Marker.val,"dis":prefix+" 总设备","navName":"总设备","siteRef":site.id,"floorRef":floor.id])
      b:=source(["equip":Marker.val,"dis":prefix+" 另一设备","navName":"另一设备","siteRef":site.id,"floorRef":floor.id])
      nested:=source(["equip":Marker.val,"dis":prefix+" 下级设备","navName":"下级设备","siteRef":site.id,"floorRef":floor.id,"equipRef":a.id])
      p:=source(["point":Marker.val,"dis":prefix+" 完整原始名称","navName":"正向有功电能","siteRef":site.id,"equipRef":nested.id,"kind":"Number","unit":"kWh","his":Marker.val,"elec":Marker.val,"tz":"Shanghai"])
      overlay:=save(["kind":"space","name":prefix+" 旧空间名","migrationSourceId":site.id.id])
      original:=rawJson
      catalog:=repo.catalog
      check(catalog["spaceSource"] == "fin","catalog identifies native navigation")
      rows:=EnerCubixMath.maps(catalog["records"])
      check(node(rows,site.id)["id"] == overlay["id"],"mapped site keeps its persisted EnerCubix ID")
      check(node(rows,floor.id)["parentId"] == overlay["id"],"native parent maps to stable existing ID")
      check(node(rows,nested.id)["parentId"] == a.id.id,"nested equipRef hierarchy is preserved")
      check(node(rows,p.id)["kind"] == "nativePoint" && node(rows,p.id)["parentId"] == nested.id.id,"point leaf remains a native point")
      check(node(rows,p.id)["name"] == "正向有功电能","point uses FIN navigation name")
      check(!EnerCubixRelations.meterKinds.contains(node(rows,p.id)["kind"]),"raw point is not automatically admitted to energy analysis")
      check(rawJson == original,"catalog read never persists projected records")
      nav:=NavTree.find(cx,"equip")
      siblings:=nav.children(cx,floor)
      siblingIds:=siblings.map |r->Str| { r.id.id }
      expected:=siblings.findAll |r| { parent:=nav.isIndentable(cx,r) ? nav.indentParentRef(cx,r) : null; return parent == null || !siblingIds.contains(parent.id) }.map |r->Str| { r.id.id }
      actual:=rows.findAll |r| { r["nativeReadonly"] == true && r["parentId"] == floor.id.id }.map |r->Str| { r["nativeSourceId"].toStr }
      check(actual == expected,"native children retain exact FIN order")
      expectFailure(|->| { edit:=node(rows,site.id).dup; edit["name"]="禁止改名"; repo.save(edit) },"mapped native site cannot be edited")
      expectFailure(|->| { repo.remove(overlay["id"].toStr,overlay["mod"]) },"mapped native site cannot be removed")
      expectFailure(|->| { repo.manage(["action":"move","dimension":"space","items":[node(rows,site.id)],"parentId":null]) },"mapped native site cannot be moved")
      expectFailure(|->| { repo.manage(["action":"copy","dimension":"space","items":[node(rows,site.id)]]) },"mapped native site cannot be copied")
      cat:=save(["kind":"category","name":prefix+" 电","unit":"kWh"])
      org:=save(["kind":"organization","name":prefix+" 组织"])
      meter:=save(["kind":"meter","name":prefix+" 计量档案","pointId":p.id.id,"categoryId":cat["id"],"organizationId":org["id"],"spaceId":overlay["id"],"includeInTotals":true])
      check(meter["spaceId"] == nested.id.id,"new physical binding uses native point parent")
      check(repo.stored(meter["id"].toStr)["enerCubixSpaceRef"] is Ref,"native coverage is stored as a real Folio Ref")
      floor=change(floor,["navName":"改名后的功能目录"])
      nested=change(nested,["equipRef":b.id])
      refreshed:=EnerCubixMath.maps(repo.catalog["records"])
      check(node(refreshed,floor.id)["name"] == "改名后的功能目录","refresh reads native rename")
      check(node(refreshed,nested.id)["parentId"] == b.id.id,"refresh reads native nested-equipment move")
      p=change(p,["equipRef":b.id])
      refreshed=EnerCubixMath.maps(repo.catalog["records"])
      liveMeter:=refreshed.find |r| { r["id"] == meter["id"] }
      check(node(refreshed,p.id)["parentId"] == b.id.id && liveMeter["nativeSpaceId"] == b.id.id,"point move updates live meter coverage")
      storedMeter:=repo.records.find |r| { r["id"] == meter["id"] }
      check(storedMeter["spaceId"] == nested.id.id && storedMeter["organizationId"] == org["id"],"refresh preserves stored historical coverage and organization")
      liveMeter["name"]=prefix+" 更新档案"; saved:=repo.save(liveMeter)
      check(saved["spaceId"] == nested.id.id && saved["organizationId"] == org["id"],"unrelated edit preserves historical and organization references")
      check(!saved.keys.any |key| { key.startsWith("native") },"transient navigation metadata is not persisted")
      cx.db.commit(Diff(p,null,Diff.remove))
      refreshed=EnerCubixMath.maps(repo.catalog["records"])
      check(!refreshed.any |r| { r["nativeSourceId"] == p.id.id },"deleted FIN point disappears on refresh")
      liveMeter=refreshed.find |r| { r["id"] == meter["id"] }
      check(liveMeter != null && liveMeter["nativeSourceMissing"] == true && liveMeter["nativeSpaceId"] == null,"source deletion retains archive and clears native coverage")
      check(repo.records.any |r| { r["id"] == meter["id"] && r["organizationId"] == org["id"] },"source deletion preserves canonical archive and organization")
      return ["status":"passed","project":cx.proj.name,"checks":checks,"nativeTreePath":catalog["nativeTreePath"]]
    }
    finally
    {
      // Only IDs created above are removed; no user or other acceptance data is touched.
      enerCubixOwned.dup.reverse.each |id|
      {
        rec:=cx.db.readById(Ref.fromStr(id),false)
        if (rec != null && rec.has("enerCubix")) cx.db.commit(Diff(rec,null,Diff.remove))
      }
      nativeOwned.dup.reverse.each |id|
      {
        rec:=cx.db.readById(id,false)
        if (rec != null && rec.has("enerCubixNativeSpaceAcceptanceSource")) cx.db.commit(Diff(rec,null,Diff.remove))
      }
    }
  }

  private Dict source(Str:Obj? tags)
  {
    tags["enerCubixNativeSpaceAcceptanceSource"]=Marker.val
    rec:=cx.db.commit(Diff.makeAdd(Etc.makeDict(tags))).newRec
    nativeOwned.add(rec.id)
    return rec
  }
  private Dict change(Dict previous, Str:Obj? tags) { cx.db.commit(Diff(previous,Etc.makeDict(tags))).newRec }
  private [Str:Obj?] save([Str:Obj?] data) { rec:=repo.save(data); enerCubixOwned.add(rec["id"].toStr); return rec }
  private Str rawJson() { JsonOutStream.writeJsonToStr(repo.records.sort |a,b| { a["id"].toStr <=> b["id"].toStr }) }
  private [Str:Obj?] node([Str:Obj?][] rows, Ref source)
  {
    return rows.find |r| { r["nativeSourceId"] == source.id } ?: throw Err("Missing native projection: "+source.id)
  }
  private Void check(Bool condition, Str message) { if (!condition) throw Err(message); checks++ }
  private Void expectFailure(|->| op, Str message)
  {
    rejected:=false
    try { op() } catch (Err e) { rejected=true }
    check(rejected,message)
  }
}

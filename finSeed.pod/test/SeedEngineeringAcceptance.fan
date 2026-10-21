using haystack
using folio
using skyarcd

** Destructive configuration checks run only in the dedicated acceptance project.
class SeedEngineeringAcceptance
{
  Context cx
  SeedRepo repo
  Str[] owned := [,]
  Int checks := 0
  new make(Context cx) { this.cx=cx; repo=SeedRepo(cx) }
  Str:Obj? run()
  {
    if (cx.proj.name != "finseed_acceptance") throw ArgErr("Engineering acceptance requires the isolated project")
    prefix:="工程验收 "+DateTime.nowTicks.toStr
    cat:=repo.records.find |r| { r["kind"] == "category" && r["unit"] == "kWh" } ?: throw Err("Run seedAcceptance first")
    point1:=cx.db.readById(Ref("finseed-test-tariff-source"))
    if (!point1.has("seedAcceptanceSource")) throw Err("Acceptance source ownership mismatch")
    point2:=cx.db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"kind":"Number","unit":"kWh","tz":"Shanghai","dis":prefix+" 专用绑点来源","seedEngineeringAcceptanceSource":Marker.val]))).newRec
    originalSize:=point1["hisSize"]
    try
    {
      root:=save(["kind":"group","name":prefix+" 根"])
      other:=save(["kind":"group","name":prefix+" 目标"])
      child:=save(["kind":"group","name":prefix+" 楼层","parentId":root["id"]])
      rows:=[
        [Str:Obj?]["kind":"meter","name":prefix+" 表一","parentId":child["id"],"pointId":point1.id.id,"categoryId":cat["id"],"includeInTotals":false],
        [Str:Obj?]["kind":"meter","name":prefix+" 表二","parentId":child["id"],"pointId":point2.id.id,"categoryId":cat["id"],"includeInTotals":false]]
      result:=repo.manage(["action":"save","records":rows]); meters:=SeedMath.maps(result["records"])
      meters.each |r| { owned.add(r["id"].toStr) }
      check(meters.size == 2,"atomic batch persisted")
      expectFailure(|->| { repo.manage(["action":"save","records":[["kind":"group","name":prefix+" 不应保存"],["kind":"group","name":prefix+" 无效","parentId":"missing"]]]) })
      check(repo.records.all |r| { r["name"] != prefix+" 不应保存" },"invalid batch leaves no partial write")
      template:=save(["kind":"template","name":prefix+" 外部模板","request":["kind":"profile","nodeIds":[meters.first["id"]]]])
      preview:=repo.manage(["action":"previewDelete","items":[root]])
      check(((List)preview["records"]).size == 4 && ((List)preview["blockers"]).size == 1,"preview includes descendants and external template")
      expectFailure(|->| { repo.manage(["action":"delete","items":[root],"revision":preview["revision"]]) })
      check(repo.records.any |r| { r["id"] == root["id"] },"blocked branch remains")
      repo.remove(template["id"].toStr,template["mod"])
      preview=repo.manage(["action":"previewDelete","items":[root]])
      child["name"]=prefix+" 楼层已修改"; child=repo.save(child)
      expectFailure(|->| { repo.manage(["action":"delete","items":[root],"revision":preview["revision"]]) })
      check(repo.records.any |r| { r["id"] == child["id"] },"stale preview preserves descendants")
      expectFailure(|->| { repo.manage(["action":"move","items":[root],"parentId":child["id"]]) })
      moved:=repo.manage(["action":"move","items":[child,meters.first],"parentId":other["id"]])
      check(((List)moved["records"]).size == 1,"moving selected ancestor keeps child relationship")
      check(repo.records.find |r| { r["id"] == meters.first["id"] }?.get("parentId") == child["id"],"meter stays below moved group")
      repo.manage(["action":"totals","items":meters,"included":true])
      check(repo.records.findAll |r| { meters.any |m| { m["id"] == r["id"] } }.all |r| { r["includeInTotals"] == true },"bulk total flags persisted")
      preview=repo.manage(["action":"previewDelete","items":[other]])
      check(((List)preview["blockers"]).isEmpty,"no outside references")
      deleted:=repo.manage(["action":"delete","items":[other],"revision":preview["revision"]])
      check(((List)deleted["deleted"]).size == 4,"branch removed in one transaction")
      check(!repo.records.any |r| { ((List)deleted["deleted"]).contains(r["id"]) },"deleted configuration absent")
      check(cx.db.readById(point1.id)["hisSize"] == originalSize && cx.db.readById(point2.id).has("his"),"original points and history retained")
      return ["status":"passed","project":cx.proj.name,"checks":checks]
    }
    finally
    {
      remaining:=repo.records.findAll |r| { owned.contains(r["id"]) }
      remaining.findAll |r| { r["kind"] == "template" }.each |r| { repo.remove(r["id"].toStr,r["mod"]) }
      remaining=repo.records.findAll |r| { owned.contains(r["id"]) }
      if (!remaining.isEmpty)
      {
        preview:=repo.manage(["action":"previewDelete","items":remaining])
        repo.manage(["action":"delete","items":remaining,"revision":preview["revision"]])
      }
      source:=cx.db.readById(point2.id,false)
      if (source != null && source.has("seedEngineeringAcceptanceSource")) cx.db.commit(Diff(source,null,Diff.remove))
    }
  }
  private [Str:Obj?] save([Str:Obj?] data) { r:=repo.save(data); owned.add(r["id"].toStr); return r }
  private Void check(Bool condition, Str label) { if (!condition) throw Err(label); checks++ }
  private Void expectFailure(|->| fn)
  {
    failed:=false
    try { fn() } catch (Err e) { failed=true }
    check(failed,"Expected rejection")
  }
}

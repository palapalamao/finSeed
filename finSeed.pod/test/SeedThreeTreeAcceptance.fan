using util
using haystack
using folio
using skyarcd

** Native persistence, history, permissions and rollback fixture; isolated project only.
class SeedThreeTreeAcceptance
{
  Context cx
  SeedRepo repo
  Str[] owned := [,]
  Ref[] nativeOwned := [,]
  Ref? sourceSite
  Int checks := 0
  new make(Context cx) { this.cx=cx; repo=SeedRepo(cx) }

  Str:Obj? run()
  {
    if (cx.proj.name != "finseed_acceptance") throw ArgErr("Three-tree acceptance requires isolated project")
    repo.mustWrite
    prefix:="三树验收 "+DateTime.nowTicks.toStr
    from:=DateTime.fromIso("2026-10-19T00:00:00+08:00").toTimeZone(TimeZone.fromStr("Shanghai"))
    try
    {
      nativeSite:=cx.db.commit(Diff.makeAdd(Etc.makeDict(["site":Marker.val,"dis":prefix+" 原生站点","seedThreeTreeAcceptanceSource":Marker.val]))).newRec
      sourceSite=nativeSite.id; nativeOwned.add(nativeSite.id)
      cat:=save(["kind":"category","name":prefix+" 电","unit":"kWh"])
      check(SeedMath.maps(repo.treeView("metering")["records"]).any |r| { r["id"] == cat["id"] },"metering tree includes energy-category folder metadata")
      site:=save(["kind":"space","name":prefix+" 园区"])
      floor:=save(["kind":"space","name":prefix+" 3F","parentId":site["id"]])
      org:=save(["kind":"organization","name":prefix+" 物业"])
      other:=save(["kind":"organization","name":prefix+" 租户"])
      legacy:=save(["kind":"group","name":prefix+" 旧分组"])
      p1:=point(prefix+" 总表",from,100f); p2:=point(prefix+" 子表",from,30f)
      source:=SeedMath.maps(repo.points(p1.id.id,0,1)["items"]).first
      check(source["siteId"] == nativeSite.id.id && source["siteName"] == nativeSite.dis,"point suggestions retain native site provenance")
      check(SeedMath.strings(source["energyTags"]).contains("elec"),"point suggestions expose native energy markers")
      master:=save(["kind":"totalMeter","name":prefix+" 总电表","spaceId":site["id"],"organizationId":org["id"],"categoryId":cat["id"],"pointId":p1.id.id,"historyMode":"cumulative","includeInTotals":true])
      child:=save(["kind":"meter","name":prefix+" 分电表","spaceId":floor["id"],"organizationId":org["id"],"meterParentId":master["id"],"categoryId":cat["id"],"pointId":p2.id.id,"historyMode":"cumulative","includeInTotals":true])
      check(repo.stored(child["id"].toStr)["seedSpaceRef"] is Ref,"coverage is native Ref")
      check(repo.stored(child["id"].toStr)["seedMeterParentRef"] is Ref,"upstream is native Ref")
      check(repo.stored(child["id"].toStr)["seedOrganizationRef"] is Ref,"organization is native Ref")
      value(report("space",site["id"].toStr,from),100f,"site deduplicates master and child")
      value(report("space",floor["id"].toStr,from),30f,"floor excludes external master")
      leak:=report("metering",master["id"].toStr,from,"leak")
      value(leak,70f,"native history explicit direct-branch leak")
      result:=repo.manage(["action":"move","dimension":"space","items":[child],"parentId":site["id"]])
      child=SeedMath.maps(result["records"]).first
      check(child["meterParentId"] == master["id"] && child["organizationId"] == org["id"],"space move preserves other dimensions")
      expectFailure(|->| { repo.manage(["action":"move","dimension":"metering","items":[master],"parentId":child["id"]]) })
      result=repo.manage(["action":"assign","items":[child],"patch":["organizationId":other["id"]]])
      child=SeedMath.maps(result["records"]).first
      incomplete:=SeedMath.maps(report("organization",org["id"].toStr,from)["series"])
      check(SeedMath.maps(incomplete.first["points"]).first["value"] == null,"cross-owner coverage is incomplete")
      legacyPoint:=point(prefix+" 旧总表来源",from,100f)
      legacyMaster:=save(["kind":"totalMeter","name":prefix+" 旧总表","parentId":legacy["id"],"pointId":legacyPoint.id.id,"categoryId":cat["id"],"includeInTotals":true,"historyMode":"cumulative"])
      legacyData:=Str:Obj?["kind":"meter","name":prefix+" 兼容旧表","parentId":legacy["id"],"pointId":legacyPoint.id.id,"categoryId":cat["id"],"includeInTotals":true,"historyMode":"cumulative"]
      expectFailure(|->| { repo.save(legacyData) })
      duplicate:=legacyFixture(legacyData)
      before:=JsonOutStream.writeJsonToStr(report("legacy",legacy["id"].toStr,from))
      preview:=repo.migration(["action":"preview"])
      newSpace:=SeedMath.maps(preview["records"]).find |r| { r["kind"] == "space" && r["name"] == nativeSite.dis }
      check(newSpace != null,"native site generates a new persisted space")
      owned.add(newSpace["id"].toStr)
      applied:=repo.migration(["action":"apply","revision":preview["revision"],"sourceRevision":preview["sourceRevision"],"acceptedSuggestionIds":Str[,]])
      job:=applied["job"] as Map ?: throw Err("Expected migration changes")
      check(repo.stored(newSpace["id"].toStr)["seedKind"] == "space","generated space ID is accepted by Folio")
      check(repo.records.find |r| { r["id"] == duplicate["id"] }?.get("canonicalId") == legacyMaster["id"],"legacy duplicate becomes compatibility reference")
      check(JsonOutStream.writeJsonToStr(report("legacy",legacy["id"].toStr,from)) == before,"legacy report unchanged by migration")
      expectFailure(|->| { repo.migration(["action":"apply","revision":preview["revision"],"sourceRevision":preview["sourceRevision"]]) })
      next:=repo.migration(["action":"preview"])
      noop:=repo.migration(["action":"apply","revision":next["revision"],"sourceRevision":next["sourceRevision"]])
      check(noop["applied"] == 0,"repeated migration is idempotent")
      dup:=repo.records.find |r| { r["id"] == duplicate["id"] }
      oldName:=dup["name"]; dup["name"]=prefix+" 迁移后编辑"; dup=repo.save(dup)
      expectFailure(|->| { repo.migration(["action":"rollback","jobId":job["id"],"mod":job["mod"]]) })
      dup["name"]=oldName; repo.save(dup)
      repo.migration(["action":"rollback","jobId":job["id"],"mod":job["mod"]])
      check(repo.records.find |r| { r["id"] == duplicate["id"] }?.get("canonicalId") == null,"rollback restores prior compatibility state")
      check(JsonOutStream.writeJsonToStr(report("legacy",legacy["id"].toStr,from)) == before,"legacy report unchanged after rollback")
      check(cx.db.readById(p1.id).has("his") && cx.db.readById(p2.id).has("his"),"configuration operations retain native histories")
      return ["status":"passed","project":cx.proj.name,"checks":checks]
    }
    finally
    {
      remaining:=repo.records.findAll |r| { owned.contains(r["id"]) && SeedConfig.nodeKinds.contains(r["kind"]) }
      if (!remaining.isEmpty)
      {
        preview:=repo.manage(["action":"previewDelete","items":remaining])
        repo.manage(["action":"delete","items":remaining,"revision":preview["revision"]])
      }
      repo.records.findAll |r| { owned.contains(r["id"]) && !SeedConfig.nodeKinds.contains(r["kind"]) }.each |r|
      {
        repo.remove(r["id"].toStr,r["mod"])
      }
      nativeOwned.dup.reverse.each |id|
      {
        r:=cx.db.readById(id,false)
        if (r != null && r.has("seedThreeTreeAcceptanceSource")) cx.db.commit(Diff(r,null,Diff.remove))
      }
    }
  }

  private [Str:Obj?] save([Str:Obj?] data) { r:=repo.save(data); owned.add(r["id"].toStr); return r }
  ** Seed an already-existing pre-migration duplicate, never through product APIs.
  private [Str:Obj?] legacyFixture([Str:Obj?] data)
  {
    if (!nativeOwned.any |id| { id.id == data["pointId"] }) throw Err("Legacy fixture source ownership mismatch")
    json:=data.dup
    tags:=Str:Obj?["seed":Marker.val,"seedKind":data["kind"],"dis":data["name"]]
    SeedRepo.refTags.each |tag,key|
    {
      value:=json.remove(key) as Str
      if (value != null) tags[tag]=Ref.fromStr(value)
    }
    tags["seedConfig"]=JsonOutStream.writeJsonToStr(json)
    rec:=cx.db.commit(Diff.makeAdd(Etc.makeDict(tags))).newRec
    owned.add(rec.id.id)
    return SeedRepo.decode(rec)
  }
  private Void check(Bool condition, Str msg) { if (!condition) throw Err(msg); checks++ }
  private Void expectFailure(|->| op)
  {
    failed:=false
    try { op() } catch (Err e) { failed=true }
    check(failed,"expected guarded rejection")
  }
  private Void value(Str:Obj? report, Float expected, Str msg)
  {
    point:=SeedMath.maps(SeedMath.maps(report["series"]).first["points"]).first
    actual:=SeedMath.num(point["value"])
    check(actual != null && (actual-expected).abs < 0.00001f,msg)
  }
  private Str:Obj? report(Str dimension, Str id, DateTime from, Str kind := "profile")
  {
    return repo.report(["dimension":dimension,"kind":kind,"nodeIds":[id],"from":from.toIso,"to":(from+24hr).toIso,"period":"day","metric":"energy","perArea":false])
  }
  private Dict point(Str name, DateTime from, Float use)
  {
    rec:=cx.db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"elec":Marker.val,"his":Marker.val,"kind":"Number","unit":"kWh","tz":"Shanghai","hisTotalized":Marker.val,"siteRef":sourceSite,"dis":name,"seedThreeTreeAcceptanceSource":Marker.val]))).newRec
    nativeOwned.add(rec.id)
    items:=[HisItem(from,Number(1000f,Unit.fromStr("kWh"))),HisItem(from+24hr,Number(1000f+use,Unit.fromStr("kWh")))]
    cx.rt.his.write(rec,items,null).get(1min)
    return rec
  }
}

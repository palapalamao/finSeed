using haystack
using folio
using skyarcd
using util

** Native writes, migration, concurrency and rollback on isolated owned fixtures.
class EnerCubixNativeEquipAcceptance
{
  Context cx
  EnerCubixRepo repo
  Ref[] owned := [,]
  Int checks := 0
  new make(Context cx) { this.cx=cx; repo=EnerCubixRepo(cx) }

  Str:Obj? run(Bool stage := false)
  {
    if (cx.proj.name != "enerCubix_acceptance") throw ArgErr("Native-equipment acceptance requires isolated project")
    repo.mustWrite
    if (repo.nativeModel) throw ArgErr("Acceptance requires original read mode")
    prefix:="原生设备验收 "+DateTime.nowTicks.toStr
    try
    {
      site:=source(["site":Marker.val,"dis":prefix,"navName":prefix,"tz":"Shanghai"])
      floor:=source(["floor":Marker.val,"dis":prefix+" 楼层","navName":"楼层","siteRef":site.id])
      master:=source(["equip":Marker.val,"dis":prefix+" 总设备","navName":"总设备","siteRef":site.id,"floorRef":floor.id])
      child:=source(["equip":Marker.val,"dis":prefix+" 分设备","navName":"分设备","siteRef":site.id,"floorRef":floor.id])
      target:=source(["equip":Marker.val,"dis":prefix+" 复制目标","navName":"复制目标","siteRef":site.id,"floorRef":floor.id])
      p1:=point(master,site,"总量"); p2:=point(child,site,"分量"); p3:=point(target,site,"备用量")
      noHistory:=source(["point":Marker.val,"dis":prefix+" 未启用历史","equipRef":child.id,"siteRef":site.id,"kind":"Number","unit":"kWh"])
      category:=save(["kind":"category","name":prefix+" 电","unit":"kWh"])
      factors:=save(["kind":"subcategory","name":prefix+" 系数","categoryId":category["id"],"coalFactor":0.1229f,"co2Factor":0.5306f])
      tariff:=save(["kind":"tariff","name":prefix+" 费率","categoryId":category["id"],"mode":"flat","rate":1.2f])
      organization:=save(["kind":"organization","name":prefix+" 组织"])
      total:=save(["kind":"totalMeter","name":prefix+" 总表","pointId":p1.id.id,"categoryId":category["id"],"subcategoryId":factors["id"],"tariffId":tariff["id"],"includeInTotals":true])
      sub:=save(["kind":"meter","name":prefix+" 分表","pointId":p2.id.id,"categoryId":category["id"],"subcategoryId":factors["id"],"tariffId":tariff["id"],"meterParentId":total["id"],"organizationId":organization["id"],"includeInTotals":true])
      from:=DateTime.fromIso("2026-09-01T00:00:00+08:00").toTimeZone(TimeZone.fromStr("Shanghai"))
      [p1,p2].each |p,index|
      {
        values:=HisItem[,]
        for (i:=0;i<=24*60;i++) values.add(HisItem(from+1hr*i,Number(i*(index == 0 ? 10f : 6f),Unit.fromStr("kWh"))))
        cx.rt.his.write(p,values,null).get(1min)
      }
      requests:=[Str:Obj?][,]; baseline:=[Str:Obj?][,]
      ["energy","cost","coal","co2"].each |metric|
      {
        q:=Str:Obj?["kind":"profile","dimension":"metering","nodeIds":[sub["id"]],"from":"2026-10-01T00:00:00+08:00","to":"2026-10-08T00:00:00+08:00","period":"day","metric":metric,"perArea":false]
        requests.add(q); baseline.add(repo.report(q))
      }
      requests.add(["kind":"leak","dimension":"metering","nodeIds":[total["id"]],"from":"2026-10-01T00:00:00+08:00","to":"2026-10-08T00:00:00+08:00","period":"day","metric":"energy","perArea":false])
      requests.add(["kind":"forecast","dimension":"metering","nodeIds":[sub["id"]],"from":"2026-09-01T00:00:00+08:00","to":"2026-10-22T00:00:00+08:00","period":"day","metric":"energy","perArea":false,"forecastDays":7,"trainingDays":56])
      baseline.add(repo.report(requests[4])); baseline.add(repo.report(requests[5]))
      template:=save(["kind":"template","name":prefix+" 模板","request":["kind":"profile","dimension":"metering","nodeIds":[sub["id"]],"baselineId":sub["id"]]])
      originalMaster:=cx.db.readById(master.id)
      fixtureIds:=[total["id"],sub["id"]]
      preview:=repo.migration(["action":"preview","fixtureIds":fixtureIds])
      check(EnerCubixMath.strings(preview["conflicts"]).isEmpty,"preview has no conflicts")
      check(cx.db.readById(master.id) == originalMaster,"preview is read-only")
      stale:=preview.dup; stale["action"]="apply"; stale["sourceRevision"]="stale"
      rejected(|->| { repo.migration(stale) },"stale source revision rejected")
      applied:=repo.migration(["action":"apply","revision":preview["revision"],"sourceRevision":preview["sourceRevision"],"fixtureIds":fixtureIds])
      job:=(Str:Obj?)applied["job"]
      check(repo.nativeModel,"native read mode enabled")
      tags:=cx.db.readById(child.id)
      check(tags["enerCubixMeterParentRef"] == master.id,"upstream relation points to native equip")
      check(tags["enerCubixPointRef"] == p2.id,"history point ref unchanged")
      check(tags["dis"] == child["dis"] && tags["siteRef"] == site.id && tags.has("equip"),"native structural tags preserved")
      check(((Map)repo.catalog)["storageModel"] == "nativeEquip","catalog identifies storage model")
      check(repo.records.findAll |r| { EnerCubixRelations.meterKinds.contains(r["kind"]) }.all |r| { r["nativeEquip"] == true },"all physical business records use native equip")
      requests.each |q,i|
      {
        actual:=repo.report(q)
        beforeValues:=EnerCubixMath.maps(baseline[i]["series"]).map |s->Obj?| { s["points"] }
        afterValues:=EnerCubixMath.maps(actual["series"]).map |s->Obj?| { s["points"] }
        check(beforeValues == afterValues,"fixed report values, quality and history sources unchanged: "+q["kind"]+" / "+q["metric"])
      }
      if (stage) return ["status":"staged","project":cx.proj.name,"job":job,"nativeId":child.id.id,"primaryPointId":p2.id.id,"checks":checks]
      migratedTemplate:=repo.records.find |r| { r["id"] == template["id"] }
      check(EnerCubixMath.strings(((Map)migratedTemplate["request"])["nodeIds"]) == [child.id.id],"template references migrated")
      rows:=EnerCubixMath.maps(repo.catalog["records"])
      check(!rows.any |r| { r["id"] == noHistory.id.id },"native tree omits non-historized point leaves before serialization")
      check(rows.findAll |r| { r["id"] == child.id.id }.size == 1,"three views share one equipment record")
      originalSub:=EnerCubixRepo.decode(tags)
      invalid:=originalSub.dup; invalid["pointId"]=p1.id.id
      rejected(|->| { repo.save(invalid) },"foreign equipment point rejected")
      invalid=originalSub.dup; invalid["meterParentId"]=child.id.id
      rejected(|->| { repo.save(invalid) },"cycle rejected")
      invalid=originalSub.dup; invalid["mod"]="stale"
      rejected(|->| { repo.save(invalid) },"stale equipment revision rejected")
      changed:=originalSub.dup; changed["description"]="迁移后新增备注"
      saved:=repo.save(changed)
      check(saved["description"] == "迁移后新增备注","native scalar saved")
      check(saved["organizationId"] == organization["id"] && saved["meterParentId"] == master.id.id,"dimension edit preserves other relationships")
      // Restore scalar so rollback can prove the original migration fields unchanged.
      saved.remove("description"); saved=repo.save(saved)
      tags=cx.db.readById(child.id)
      cx.db.commit(Diff(tags,Etc.makeDict(["enerCubixMaximum":Number(999f)])))
      refreshed:=EnerCubixMath.maps(repo.catalog["records"]).find |r| { r["id"] == child.id.id }
      check(refreshed["maximum"] == 999f,"direct native tag edits visible on refresh")
      cx.db.commit(Diff(cx.db.readById(child.id),Etc.makeDict(["enerCubixMaximum":Remove.val,"enerCubixPointRef":p1.id])))
      refreshed=EnerCubixMath.maps(repo.catalog["records"]).find |r| { r["id"] == child.id.id }
      check(refreshed["configurationError"] != null,"invalid native tag edit is reported")
      rejected(|->| { repo.migration(["action":"rollback","jobId":job["id"],"mod":job["mod"]]) },"rollback refuses a conflicting later energy edit")
      cx.db.commit(Diff(cx.db.readById(child.id),Etc.makeDict(["enerCubixPointRef":p2.id])))
      copy:=repo.manage(["action":"copy","dimension":"metering","items":[["id":child.id.id,"mod":EnerCubixRepo.iso(cx.db.readById(child.id)["mod"])]],"targetId":target.id.id,"targetMod":EnerCubixRepo.iso(target["mod"]),"pointId":p3.id.id])
      check(cx.db.readById(target.id)["enerCubixPointRef"] == p3.id,"copy config uses existing target equip and own primary point")
      copied:=EnerCubixMath.maps(copy["records"]).first
      repo.remove(target.id.id,copied["mod"])
      check(cx.db.readById(target.id).has("equip") && !cx.db.readById(target.id).has("enerCubixKind"),"unenrollment retains native equip")
      check(cx.db.readById(p3.id).has("his"),"unenrollment retains point and history tags")
      formula:=save(["kind":"expression","name":prefix+" 公式","formula":"x*2","variables":["x":child.id.id]])
      virtualEquip:=repo.save(["kind":"meter","name":prefix+" 虚拟设备","createVirtual":true,"siteId":site.id.id,"floorId":floor.id.id,"expressionId":formula["id"],"categoryId":category["id"]])
      owned.add(Ref(virtualEquip["id"].toStr))
      check(cx.db.readById(Ref(virtualEquip["id"].toStr)).has("enerCubixVirtual"),"new expression object is a native FIN virtual equip")
      repo.remove(virtualEquip["id"].toStr,virtualEquip["mod"])
      check(cx.db.readById(Ref(virtualEquip["id"].toStr)).has("equip"),"virtual unenrollment retains native carrier")
      finalized:=repo.migration(["action":"finalize","jobId":job["id"],"mod":job["mod"]])
      check(finalized["removed"] == 2,"cleanup count excludes task and shared revision updates")
      job=(Str:Obj?)finalized["job"]
      check(cx.db.readById(Ref(total["id"].toStr),false) == null && cx.db.readById(Ref(sub["id"].toStr),false) == null,"old physical archives removed after verification")
      cx.db.commit(Diff(cx.db.readById(master.id),Etc.makeDict(["description":"FIN 外部备注"])))
      repo.migration(["action":"rollback","jobId":job["id"],"mod":job["mod"]])
      check(!repo.nativeModel,"rollback restores old read mode")
      check(cx.db.readById(Ref(total["id"].toStr),false) != null && cx.db.readById(Ref(sub["id"].toStr),false) != null,"rollback restores archive IDs")
      check(!cx.db.readById(master.id).has("enerCubixKind") && cx.db.readById(master.id)["description"] == "FIN 外部备注","rollback preserves unrelated native edits")
      return ["status":"passed","checks":checks,"project":cx.proj.name]
    }
    finally
    {
      // A failed run retains model/snapshots for reconciliation. Successful runs clean owned fixtures only.
      if (!repo.nativeModel)
      {
        owned.dup.reverse.each |id| { r:=cx.db.readById(id,false); if (r != null) cx.db.commit(Diff(r,null,Diff.remove)) }
      }
    }
  }

  private Dict source(Str:Obj? tags) { r:=cx.db.commit(Diff.makeAdd(Etc.makeDict(tags))).newRec; owned.add(r.id); return cx.db.readById(r.id) }
  private Dict point(Dict equip, Dict site, Str name) { source(["point":Marker.val,"dis":equip.dis+" "+name,"equipRef":equip.id,"siteRef":site.id,"his":Marker.val,"hisTotalized":Marker.val,"hisMode":"consumption","hisCollectInterval":Number(1,Unit.fromStr("hr")),"kind":"Number","unit":"kWh","tz":"Shanghai"]) }
  private [Str:Obj?] save(Str:Obj? data)
  {
    // Deliberately enerCubix the historical layout to exercise its recovery protocol.
    if (EnerCubixRelations.meterKinds.contains(data["kind"]))
    {
      added:=cx.db.commit(Diff.makeAdd(repo.encode(data))).newRec
      owned.add(added.id)
      return EnerCubixRepo.decode(cx.db.readById(added.id))
    }
    r:=repo.save(data); owned.add(Ref(r["id"].toStr)); return r
  }
  private Void check(Bool value, Str message) { if (!value) throw Err(message); checks++ }
  private Void rejected(|->| operation, Str message)
  {
    failed:=false
    try { operation() } catch (Err e) { failed=true }
    check(failed,message)
  }
}

using haystack
using folio
using skyarcd

** Real persistence checks: energy properties belong to FIN equipment without a model switch.
class EnerCubixDirectEquipAcceptance
{
  Context cx
  EnerCubixRepo repo
  Ref[] owned := [,]
  Int checks := 0
  new make(Context cx) { this.cx=cx; repo=EnerCubixRepo(cx) }

  Str:Obj? run()
  {
    if (!["finseed_acceptance","enerCubix_acceptance"].contains(cx.proj.name)) throw ArgErr("Direct-equipment acceptance requires isolated project")
    repo.mustWrite
    prefix:="原生直接读写 "+DateTime.nowTicks.toStr
    try
    {
      site:=source(["site":Marker.val,"dis":prefix,"tz":"Shanghai"])
      floor:=source(["floor":Marker.val,"dis":prefix+" 楼层","siteRef":site.id])
      master:=source(["equip":Marker.val,"dis":prefix+" 总设备","navName":"总设备","siteRef":site.id,"floorRef":floor.id])
      child:=source(["equip":Marker.val,"dis":prefix+" 分设备","navName":"分设备","siteRef":site.id,"floorRef":floor.id])
      p1:=point(master,site); p2:=point(child,site)
      category:=repo.save(["kind":"category","name":prefix+" 电","unit":"kWh"]); owned.add(Ref(category["id"].toStr))
      org:=repo.save(["kind":"organization","name":prefix+" 组织"]); owned.add(Ref(org["id"].toStr))
      total:=repo.save(["id":master.id.id,"mod":EnerCubixRepo.iso(master["mod"]),"kind":"meter","name":prefix+" 总表","pointId":p1.id.id,"categoryId":category["id"],"area":500f,"autoSum":true,"includeInTotals":true,"description":"原生属性"])
      check(total["id"] == master.id.id,"single save must retain the raw equipment ID")
      check(cx.db.readById(p1.id)["hisTotalized"] === Marker.val,"single save marks an empty-history primary energy point as cumulative")
      check(cx.db.readById(p1.id)["hisMode"] == p1["hisMode"] && cx.db.readById(p1.id)["unit"] == p1["unit"],"totalization preserves existing point attributes")
      tags:=cx.db.readById(master.id)
      check(tags["enerCubixPointRef"] == p1.id && tags["enerCubixAutoSum"] == true,"primary point and autoSum must be visible on equipment")
      check(tags["enerCubixArea"] == Number(500f) && tags["enerCubixDescription"] == "原生属性","numeric and text attributes must be native tags")
      child=cx.db.readById(child.id)
      saved:=repo.manage(["action":"save","records":[["id":child.id.id,"mod":EnerCubixRepo.iso(child["mod"]),"kind":"meter","name":prefix+" 分表","pointId":p2.id.id,"categoryId":category["id"],"meterParentId":master.id.id,"organizationId":org["id"],"includeInTotals":true]]])
      tags=cx.db.readById(child.id)
      check(cx.db.readById(p2.id)["hisTotalized"] === Marker.val,"batch save marks the selected primary energy point")
      pointMod:=cx.db.readById(p2.id)["mod"]
      check(tags["enerCubixMeterParentRef"] == master.id,"batch save must point to the actual master equipment")
      check(tags["enerCubixOrganizationRef"] == Ref(org["id"].toStr),"organization ref must be on raw equipment")
      check(!cx.db.readAllList(Filter("enerCubix and enerCubixKind==\"meter\" and not equip")).any |r| { r.dis.startsWith(prefix) },"normal saves must not create an independent meter archive")
      repo.manage(["action":"assign","items":[["id":child.id.id,"mod":EnerCubixRepo.iso(tags["mod"])]],"patch":["meterParentId":null,"includeInTotals":false]])
      tags=cx.db.readById(child.id)
      check(!tags.has("enerCubixMeterParentRef") && tags["enerCubixIncludeInTotals"] == false,"clearing parent updates that same raw record")
      check(cx.db.readById(p2.id)["mod"] == pointMod,"saving an already marked point does not rewrite it")
      cx.db.commit(Diff(tags,Etc.makeDict(["enerCubixMaximum":Number(321f),"enerCubixLocation":"FIN 直接编辑"])))
      row:=EnerCubixMath.maps(repo.catalog["records"]).find |r| { r["id"] == child.id.id }
      check(row["maximum"] == 321f && row["location"] == "FIN 直接编辑","refresh reads native tag edits")
      foreign:=point(master,site)
      invalid:=row.dup; invalid["pointId"]=foreign.id.id
      failed:=false; try { repo.save(invalid) } catch (Err e) { failed=true }
      check(failed && cx.db.readById(child.id)["enerCubixPointRef"] == p2.id,"foreign point edit is rejected without changing the native binding")
      check(!cx.db.readById(foreign.id).has("hisTotalized"),"failed saves do not mark a foreign point")
      alternate:=point(child,site)
      row=EnerCubixRepo.decode(cx.db.readById(child.id)); row["pointId"]=alternate.id.id; repo.save(row)
      check(cx.db.readById(alternate.id)["hisTotalized"] === Marker.val && cx.db.readById(p2.id)["hisTotalized"] === Marker.val,"changing the primary point marks the new source and preserves the old source")
      sensorEq:=source(["equip":Marker.val,"dis":prefix+" 传感器","siteRef":site.id,"floorRef":floor.id])
      sensorPoint:=point(sensorEq,site)
      repo.save(["id":sensorEq.id.id,"mod":EnerCubixRepo.iso(sensorEq["mod"]),"kind":"sensor","name":prefix+" 传感器","pointId":sensorPoint.id.id,"includeInTotals":false])
      check(!cx.db.readById(sensorPoint.id).has("hisTotalized"),"sensor bindings do not receive energy-counter semantics")
      repo.remove(child.id.id,EnerCubixRepo.iso(cx.db.readById(child.id)["mod"]))
      check(cx.db.readById(child.id).has("equip") && !cx.db.readById(child.id).has("enerCubixKind") && cx.db.readById(p2.id).has("his"),"unenrollment only clears business tags")
      return ["status":"passed","checks":checks,"project":cx.proj.name]
    }
    finally
    {
      owned.dup.reverse.each |id| { r:=cx.db.readById(id,false); if (r != null) cx.db.commit(Diff(r,null,Diff.remove)) }
    }
  }

  Str:Obj? runCreation()
  {
    if (cx.proj.name != "enerCubix_acceptance") throw ArgErr("Native creation acceptance requires isolated project")
    repo.mustWrite
    prefix:="原生新建验收 "+DateTime.nowTicks.toStr
    try
    {
      site:=source(["site":Marker.val,"dis":prefix,"tz":"Shanghai"])
      floor:=source(["floor":Marker.val,"dis":prefix+" 楼层","siteRef":site.id])
      otherSite:=source(["site":Marker.val,"dis":prefix+" 其他站点","tz":"Shanghai"])
      category:=repo.save(["kind":"category","name":prefix+" 电能","unit":"kWh","energyType":"elec"]); owned.add(Ref(category["id"].toStr))
      input:=Str:Obj?["kind":"totalMeter","name":prefix+" 总表","createNative":true,"siteId":site.id.id,"floorId":floor.id.id,"categoryId":category["id"],"autoSum":true]
      saved:=repo.save(input)
      eqId:=Ref(saved["id"].toStr); pId:=Ref(saved["pointId"].toStr)
      owned.add(eqId); owned.add(pId)
      eq:=cx.db.readById(eqId); p:=cx.db.readById(pId)
      check(eq.has("equip") && eq["enerCubixKind"] == "totalMeter" && !eq.has("enerCubixVirtual"),"new main meter is raw FIN equipment without an expression")
      check(eq["enerCubixPointRef"] == pId && p["equipRef"] == eqId,"device and point refs form one native identity")
      check(eq["siteRef"] == site.id && eq["floorRef"] == floor.id && p["floorRef"] == floor.id,"new equipment and point share the selected native location")
      check(p.has("point") && p.has("his") && p.has("hisTotalized") && p["unit"] == "kWh" && p["kind"] == "Number","new native energy point is historized and cumulative")
      check(p.has("elec") && p.has("energy") && p["navName"] == category["name"],"energy metadata comes from the selected category")
      check(eq["enerCubixAutoSum"] == true && eq["enerCubixIncludeInTotals"] == true,"calculated current values and totals defaults are visible device tags")
      check(saved["nativeEquip"] == true && saved["expressionId"] == null,"response uses native equipment identity")
      row:=EnerCubixMath.maps(repo.catalog["records"]).find |r| { r["id"] == eqId.id }
      check(row != null && row["pointId"] == pId.id,"new device is immediately visible in the native catalog")
      before:=cx.db.readAllList(Filter.has("equip").or(Filter.has("point"))).size
      bad:=input.dup; bad["name"]=prefix+" 错误位置"; bad["siteId"]=otherSite.id.id
      failed:=false; try { repo.save(bad) } catch (Err e) { failed=true }
      check(failed && cx.db.readAllList(Filter.has("equip").or(Filter.has("point"))).size == before,"invalid native location creates neither an equipment nor an orphan point")
      bad=input.dup; bad["name"]=prefix+" 错误公式"; bad["expressionId"]="not-an-expression"
      failed=false; try { repo.save(bad) } catch (Err e) { failed=true }
      check(failed && cx.db.readAllList(Filter.has("equip").or(Filter.has("point"))).size == before,"ordinary meter creation rejects an expression without partial writes")
      return ["status":"passed","checks":checks,"project":cx.proj.name]
    }
    finally
    {
      owned.dup.reverse.each |id| { r:=cx.db.readById(id,false); if (r != null) cx.db.commit(Diff(r,null,Diff.remove)) }
    }
  }

  private Dict source(Str:Obj? tags) { r:=cx.db.commit(Diff.makeAdd(Etc.makeDict(tags))).newRec; owned.add(r.id); return cx.db.readById(r.id) }
  private Dict point(Dict eq,Dict site) { source(["point":Marker.val,"dis":eq.dis+" 电能","equipRef":eq.id,"siteRef":site.id,"his":Marker.val,"hisMode":"consumption","kind":"Number","unit":"kWh","tz":"Shanghai"]) }
  private Void check(Bool value,Str message) { if (!value) throw Err(message); checks++ }
}

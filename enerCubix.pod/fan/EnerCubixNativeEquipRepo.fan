using haystack
using folio
using skyarcd
using util

** Native-equipment persistence and reversible model migration.
class EnerCubixNativeEquipRepo
{
  EnerCubixRepo repo
  Context cx
  static const Str modelId := "enerCubix-native-equip-model"
  new make(EnerCubixRepo repo) { this.repo=repo; this.cx=repo.cx }

  Dict? model() { cx.db.read(Filter.has("enerCubixStorageModel"),false) }
  Bool active() { model?.get("enerCubixStorageModel") == "nativeEquip" }
  Str:Str mapping()
  {
    json:=model?.get("enerCubixAliases") as Str ?: "{}"
    out:=Str:Str[:]
    ((Map)JsonInStream(json.in).readJson).each |v,k| { out[k.toStr]=v.toStr }
    return out
  }

  Str resolve(Str id) { mapping[id] ?: id }

  ** Repair old application-owned archives when they are first edited. Normal
  ** enrollment needs no model record; every subsequent write uses equipment.
  [Str:Obj?][] prepareWrite([Str:Obj?][] input)
  {
    if (active) return input
    legacy:=input.findAll |r|
    {
      id:=r["id"] as Str
      old:=id == null ? null : cx.db.readById(Ref(id),false)
      return old != null && !old.has("equip") && old.has("enerCubix") && EnerCubixRelations.meterKinds.contains(old["enerCubixKind"])
    }
    if (legacy.isEmpty) return input
    legacy.each |r| { EnerCubixRepo.checkMod(repo.stored(r["id"].toStr),r["mod"]) }
    plan:=migrate(["action":"preview"])
    migrate(["action":"apply","revision":plan["revision"],"sourceRevision":plan["sourceRevision"]])
    aliases:=mapping
    return input.map |r->[Str:Obj?]|
    {
      out:=EnerCubixNativeEquip.rewrite(r,aliases)
      if (aliases.containsKey(r["id"]?.toStr ?: "")) out["mod"]=EnerCubixRepo.iso(equipment(out["id"].toStr)["mod"])
      return out
    }
  }

  [Str:Obj?][] records([Str:Obj?][] raw)
  {
    raw=raw.findAll |r| { r["action"] != "nativeEquipSnapshot" }
    if (!active) return raw
    return raw.findAll |r| { !EnerCubixRelations.meterKinds.contains(r["kind"]) || r["nativeEquip"] == true }
  }

  Dict equipment(Str id)
  {
    r:=cx.db.readById(Ref(resolve(id)),false)
    if (r == null || !r.has("equip")) throw ArgErr("请选择当前项目中已有的 FIN 设备")
    if (!cx.canRead(r)) throw EnerCubixHttpErr(403,"PERMISSION","没有此 FIN 设备的读取权限")
    return r
  }

  [Str:Obj?] prepare([Str:Obj?] input)
  {
    out:=EnerCubixNativeSpace.clean(input)
    id:=input["id"] as Str
    if (id == null)
    {
      pointId:=input["pointId"] as Str ?: throw ArgErr("请选择 FIN 设备及其主能耗点")
      p:=cx.db.readById(Ref(pointId),false)
      id=(p?.get("equipRef") as Ref)?.id ?: throw ArgErr("主点没有 FIN 设备归属")
      out["id"]=id
    }
    else out["id"]=resolve(id)
    eq:=equipment(out["id"].toStr)
    // Enrollment also requires the equipment revision observed in the catalog.
    EnerCubixRepo.checkMod(eq,input["mod"])
    if (eq.has("enerCubixKind") && !EnerCubixRelations.meterKinds.contains(eq["enerCubixKind"])) throw ArgErr("设备已被其他 EnerCubix 配置占用")
    if (out["parentId"] != (eq["enerCubixParentRef"] as Ref)?.id) throw ArgErr("空间层级由 FIN 维护，旧分析分组只读；请设置计量覆盖范围")
    out["nativeEquip"]=true
    return out
  }

  Void validate([Str:Obj?] record, [Str:Obj?][] all)
  {
    eq:=equipment(record["id"].toStr)
    pointId:=record["pointId"] as Str
    point:=pointId == null ? null : cx.db.readById(Ref(pointId),false)
    if (point != null && !cx.canRead(point)) throw EnerCubixHttpErr(403,"PERMISSION","没有主计量点的读取权限")
    if (!EnerCubixRelations.meterKinds.contains(record["kind"])) throw ArgErr("设备能源类型标签无效")
    EnerCubixConfig.validateNewBinding(record,eq.has("enerCubixKind") ? EnerCubixRepo.decode(eq) : null,all)
    EnerCubixNativeEquip.validateSource(record,eq,point,all)
    // Native parentId is display-only; legacy membership is separately retained.
    checked:=record.dup; checked.remove("parentId")
    validation:=all
    coverage:=record["spaceId"] as Str
    if (coverage != null && !all.any |r| { r["id"] == coverage })
    {
      space:=cx.db.readById(Ref(coverage),false)
      if (space == null || !(space.has("site") || space.has("floor") || space.has("equip")) || !cx.canRead(space)) throw ArgErr("计量覆盖范围的 FIN 引用无效或无权访问")
      validation=all.dup.add(["id":coverage,"kind":"space","name":space.dis])
    }
    EnerCubixConfig.validate(checked,validation)
  }

  [Str:Obj?][] validateRead([Str:Obj?][] all)
  {
    all.findAll |r| { r["nativeEquip"] == true }.each |r|
    {
      try { validate(r,all) }
      catch (Err e) { r["configurationError"]=e.msg }
    }
    return all
  }

  Diff write([Str:Obj?] record)
  {
    prev:=equipment(record["id"].toStr)
    EnerCubixRepo.checkMod(prev,record["mod"])
    return Diff(prev,EnerCubixNativeEquip.tags(record,prev,cx.user.username))
  }

  [Str:Obj?] createNative([Str:Obj?] input)
  {
    if (!["meter","totalMeter"].contains(input["kind"])) throw ArgErr("仅支持新建总表或分表")
    if (input["pointId"] != null || input["expressionId"] != null) throw ArgErr("新建原生表计将自动创建主能耗点，请勿绑定已有点或表达式")
    siteId:=input["siteId"] as Str ?: throw ArgErr("请选择设备所属 FIN 站点")
    site:=cx.db.readById(Ref(siteId),false)
    if (site == null || !site.has("site") || !cx.canRead(site)) throw ArgErr("请选择本项目可访问的 FIN 站点")
    floorId:=input["floorId"] as Str ?: throw ArgErr("请选择 FIN 楼层 / 设备目录")
    floor:=cx.db.readById(Ref(floorId),false)
    if (floor == null || !floor.has("floor") || floor["siteRef"] != site.id || !cx.canRead(floor)) throw ArgErr("设备目录必须属于所选 FIN 站点")
    all:=repo.liveRecords
    category:=all.find |r| { r["id"] == input["categoryId"] && r["kind"] == "category" } ?: throw ArgErr("请选择能耗分类")
    unit:=(input["unit"] as Str)?.trim
    if (unit == null || unit.isEmpty) unit=category["unit"] as Str ?: ""
    if (unit.isEmpty || EnerCubixMath.unitFactor(unit,category["unit"]?.toStr ?: "") == null) throw ArgErr("主能耗点单位与能源类型不兼容")
    id:=Ref.gen; pointId:=Ref.gen
    rec:=EnerCubixNativeSpace.clean(input); rec["id"]=id.id; rec["pointId"]=pointId.id; rec["unit"]=unit
    rec["includeInTotals"]=input["includeInTotals"] ?: true
    rec["autoSum"]=input["autoSum"] ?: (input["kind"] == "totalMeter")
    rec.remove("parentId"); rec.remove("createNative"); rec.remove("siteId"); rec.remove("floorId")
    pointName:=category["name"].toStr
    tz:=site["tz"] ?: (cx.proj.meta["tz"] ?: "UTC")
    pointTags:=Str:Obj?["point":Marker.val,"sensor":Marker.val,"cur":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"hisMode":"consumption","hisCollectInterval":Number(15,Unit.fromStr("min")),"kind":"Number","unit":unit,"dis":pointName,"navName":pointName,"equipRef":id,"siteRef":site.id,"floorRef":floor.id,"tz":tz]
    tags:=Etc.dictToMap(EnerCubixNativeEquip.tags(rec,Etc.emptyDict,cx.user.username))
    tags["equip"]=Marker.val; tags["meter"]=Marker.val; tags["dis"]=rec["name"]; tags["navName"]=rec["name"]; tags["siteRef"]=site.id; tags["floorRef"]=floor.id
    if (category["energyType"] == "elec" || ["电","电力","电能","electric","electricity","elec"].contains(pointName.lower))
    {
      tags["elec"]=Marker.val; pointTags["elec"]=Marker.val; pointTags["energy"]=Marker.val
    }
    EnerCubixConfig.validate(rec,all.dup.add(rec))
    EnerCubixNativeEquip.validateSource(rec,Etc.makeDict(tags.dup.set("id",id)),Etc.makeDict(pointTags.dup.set("id",pointId)),all)
    if (rec["cleaningEnabled"] == true)
    {
      profile:=repo.stored(rec["cleaningProfileId"] as Str ?: throw ArgErr("请选择清洗方案"))
      if (profile["enerCubixKind"] != "cleaningProfile") throw ArgErr("清洗方案不存在")
      newPoint:=Etc.makeDict(pointTags.dup.set("id",pointId))
      cleaning:=EnerCubixCleaningRepo.install(newPoint,id,EnerCubixCleaningRepo.configFor(EnerCubixRepo.decode(profile),newPoint))
      cleaning.each |v,k| { pointTags[k]=v }
    }
    // Equipment, its own historical point and the configuration revision are one commit.
    repo.commit([Diff.makeAdd(Etc.makeDict(tags),id),Diff.makeAdd(Etc.makeDict(pointTags),pointId)])
    return EnerCubixRepo.decode(repo.stored(id.id))
  }

  [Str:Obj?] createVirtual([Str:Obj?] input)
  {
    if (input["cleaningEnabled"] == true) throw ArgErr("公式或别名档案不能配置点位清洗")
    if (input["pointId"] != null || input["expressionId"] == null) throw ArgErr("新建虚拟设备必须选择表达式且不绑定物理点")
    siteId:=input["siteId"] as Str ?: throw ArgErr("请选择虚拟设备所属 FIN 站点")
    site:=cx.db.readById(Ref(siteId),false)
    if (site == null || !site.has("site") || !cx.canRead(site)) throw ArgErr("请选择本项目可访问的 FIN 站点")
    floorId:=input["floorId"] as Str ?: throw ArgErr("请选择虚拟设备所属 FIN 楼层或设备目录")
    floor:=cx.db.readById(Ref(floorId),false)
    if (floor == null || !floor.has("floor") || floor["siteRef"] != site.id || !cx.canRead(floor)) throw ArgErr("虚拟设备目录必须属于所选 FIN 站点")
    id:=Ref.gen
    rec:=EnerCubixNativeSpace.clean(input); rec["id"]=id.id; rec["includeInTotals"]=false
    rec.remove("parentId"); rec.remove("createVirtual"); rec.remove("siteId"); rec.remove("floorId")
    all:=repo.liveRecords
    EnerCubixConfig.validate(rec,all)
    tags:=Etc.dictToMap(EnerCubixNativeEquip.tags(rec,Etc.emptyDict,cx.user.username))
    tags["equip"]=Marker.val; tags["enerCubixVirtual"]=Marker.val; tags["dis"]=rec["name"]; tags["navName"]=rec["name"]; tags["siteRef"]=site.id
    tags["floorRef"]=floor.id
    repo.commit([Diff.makeAdd(Etc.makeDict(tags),id)])
    return EnerCubixRepo.decode(repo.stored(id.id))
  }

  [Str:Obj?] migrate([Str:Obj?] input)
  {
    repo.mustWrite
    action:=input["action"] as Str ?: "preview"
    if (action == "rollback") return rollback(input)
    if (action == "finalize") return finalize(input)
    if (active) return ["target":"nativeEquip","alreadyApplied":true,"records":[Str:Obj?][,],"conflicts":Str[,],"warnings":["已使用 FIN 原生设备模型"],"suggestions":[Str:Obj?][,],"counts":["added":0,"updated":0,"canonicalAliases":mapping.size,"spaces":0,"suggestions":0,"unboundMeters":0]]
    all:=repo.rawRecords
    // Older acceptance suites retain intentionally unbound examples. Limit this
    // fixture-only migration without touching those unrelated test records.
    if (input["fixtureIds"] != null)
    {
      if (cx.proj.name != "enerCubix_acceptance") throw ArgErr("迁移范围限制仅供独立验收项目使用")
      fixtureIds:=EnerCubixMath.strings(input["fixtureIds"])
      all=all.findAll |r| { !EnerCubixRelations.meterKinds.contains(r["kind"]) || fixtureIds.contains(r["id"]) }
    }
    equips:=cx.db.readAllList(Filter.has("equip")).findAll |r| { cx.canRead(r) }
    points:=cx.db.readAllList(Filter.has("point")).findAll |r| { cx.canRead(r) }
    plan:=EnerCubixNativeEquip.preview(all,equips,points)
    plan["revision"]=EnerCubixRepo.iso(cx.db.read(Filter.has("enerCubixRevision"),false)?.get("mod")) ?: ""
    // Exclude volatile collection metadata; protect ownership, unit, history and every owned tag.
    targetIds:=((Map)plan["mapping"]).vals
    pointIds:=EnerCubixMath.maps(plan["records"]).map |r->Str| { r["pointId"]?.toStr ?: "" }
    plan["sourceRevision"]=EnerCubixNativeEquip.sourceRevision(equips.findAll |e| { targetIds.contains(e.id.id) },points.findAll |p| { pointIds.contains(p.id.id) })
    if (action == "preview") return plan
    if (action != "apply") throw ArgErr("无效的原生设备迁移操作")
    if (input["revision"] != plan["revision"] || input["sourceRevision"] != plan["sourceRevision"]) throw EnerCubixHttpErr(409,"CONFLICT","源配置已变化，请重新预览迁移")
    if (!EnerCubixMath.strings(plan["conflicts"]).isEmpty) throw ArgErr("请先处理迁移预览中的冲突")
    aliases:=(Str:Str)plan["mapping"]
    edits:=EnerCubixMath.maps(plan["records"])
    candidate:=all.findAll |r| { !aliases.containsKey(r["id"]) }.dup.addAll(edits)
    diffs:=Diff[,]; snapshots:=[Str:Obj?][,]
    edits.each |r|
    {
      validate(r,candidate)
      eq:=equipment(r["id"].toStr)
      snapshots.add(["type":"equip","id":eq.id.id,"before":zinc(Etc.makeDict(owned(eq))),"after":zinc(Etc.makeDict(ownedAfter(eq,EnerCubixNativeEquip.tags(r,eq,cx.user.username))))])
      diffs.add(write(r))
      old:=repo.stored(r["legacyId"].toStr)
      snapshots.add(["type":"archive","id":old.id.id,"before":zinc(old)])
    }
    all.findAll |r| { !aliases.containsKey(r["id"]) && r["kind"] != "alarm" && !(r["action"]?.toStr ?: "").contains("Snapshot") }.each |r|
    {
      updated:=EnerCubixNativeEquip.rewrite(r,aliases)
      if (updated == r) return
      prev:=repo.stored(r["id"].toStr)
      snapshots.add(["type":"config","id":prev.id.id,"before":zinc(prev),"afterBusiness":JsonOutStream.writeJsonToStr(updated)])
      diffs.add(Diff(prev,repo.encode(updated,prev)))
    }
    key:=Ref.gen
    snapshots.each |s,i|
    {
      backup:=Str:Obj?["kind":"job","name":"设备模型恢复材料 "+key.id+" "+i,"action":"nativeEquipSnapshot","status":"retained","enabled":false,"migrationKey":key.id,"snapshot":s]
      diffs.add(Diff.makeAdd(repo.encode(backup)))
    }
    oldModel:=model
    tags:=Etc.makeDict(["enerCubixStorageModel":"nativeEquip","enerCubixAliases":JsonOutStream.writeJsonToStr(aliases),"enerCubixMigrationKey":key.id])
    if (oldModel != null) throw ArgErr("原生设备模型标识已存在，请先处理旧迁移记录")
    diffs.add(Diff.makeAdd(tags,Ref(modelId)))
    job:=Str:Obj?["id":key.id,"kind":"job","name":"FIN 原生设备模型迁移","action":"nativeEquipMigration","status":"applied","enabled":false,"migrationKey":key.id,"processed":edits.size,"lastRun":DateTime.now.toIso]
    diffs.add(Diff.makeAdd(repo.encode(job),key))
    repo.commit(diffs)
    return ["applied":edits.size,"job":EnerCubixRepo.decode(repo.stored(key.id))]
  }

  private [Str:Obj?][] snapshots(Str key)
  { repo.rawRecords(true).findAll |r| { r["action"] == "nativeEquipSnapshot" && r["migrationKey"] == key }.map |r->[Str:Obj?]| { (Str:Obj?)r["snapshot"] } }

  private [Str:Obj?] finalize([Str:Obj?] input)
  {
    job:=repo.stored(input["jobId"].toStr); EnerCubixRepo.checkMod(job,input["mod"])
    if (!active || job["enerCubixKind"] != "job") throw ArgErr("没有可完成的迁移")
    data:=EnerCubixRepo.decode(job)
    if (data["action"] != "nativeEquipMigration" || data["status"] != "applied") throw ArgErr("此迁移状态不可清理")
    if (model?.get("enerCubixMigrationKey") != data["migrationKey"]) throw ArgErr("迁移记录与当前读取模型不匹配")
    snaps:=snapshots(data["migrationKey"].toStr)
    if (snaps.isEmpty) throw ArgErr("恢复材料缺失，不能清理")
    diffs:=Diff[,]
    snaps.findAll |s| { s["type"] == "archive" }.each |s|
    {
      original:=readZinc(s["before"].toStr)
      current:=cx.db.readById(original.id,false)
      if (current == null || Etc.dictToMap(current) != Etc.dictToMap(original)) throw EnerCubixHttpErr(409,"CONFLICT","旧档案已变化，停止清理")
      diffs.add(Diff(current,null,Diff.remove))
    }
    data["status"]="finalized"; diffs.add(Diff(job,repo.encode(data,job)))
    removed:=diffs.size-1
    repo.commit(diffs)
    return ["removed":removed,"job":EnerCubixRepo.decode(repo.stored(job.id.id))]
  }

  private [Str:Obj?] rollback([Str:Obj?] input)
  {
    job:=repo.stored(input["jobId"].toStr); EnerCubixRepo.checkMod(job,input["mod"])
    data:=EnerCubixRepo.decode(job)
    if (!active || data["action"] != "nativeEquipMigration" || !["applied","finalized"].contains(data["status"])) throw ArgErr("此迁移不可回滚")
    if (model?.get("enerCubixMigrationKey") != data["migrationKey"]) throw ArgErr("迁移记录与当前读取模型不匹配")
    snaps:=snapshots(data["migrationKey"].toStr)
    if (snaps.isEmpty) throw ArgErr("恢复材料缺失")
    diffs:=Diff[,]
    snaps.each |s|
    {
      original:=readZinc(s["before"].toStr)
      current:=cx.db.readById(Ref(s["id"].toStr),false)
      if (s["type"] == "equip")
      {
        if (current == null) throw EnerCubixHttpErr(409,"CONFLICT","原生设备已删除，停止回滚")
        after:=readZinc(s["after"].toStr)
        before:=owned(original); expected:=owned(after); currentTags:=owned(current)
        patch:=Str:Obj?[:]
        ownedKeys:=before.keys.dup.addAll(expected.keys).unique
        ownedKeys.each |tag|
        {
          if (["enerCubixUpdatedAt","enerCubixUpdatedBy"].contains(tag)) return
          if (before[tag] == expected[tag]) return
          if (currentTags[tag] != expected[tag]) throw EnerCubixHttpErr(409,"CONFLICT","设备能源标签已有后续修改，停止回滚："+current.dis+" / "+tag)
          patch[tag]=before[tag] ?: Remove.val
        }
        diffs.add(Diff(current,Etc.makeDict(patch)))
      }
      else if (s["type"] == "archive")
      {
        if (current == null)
        {
          tags:=Etc.dictToMap(original); tags.remove("id"); tags.remove("mod")
          diffs.add(Diff.makeAdd(Etc.makeDict(tags),EnerCubixRepo.addId(s["id"].toStr,cx.proj.name)))
        }
        else if (Etc.dictToMap(current) != Etc.dictToMap(original)) throw EnerCubixHttpErr(409,"CONFLICT","旧档案已有后续修改，停止回滚")
      }
      else
      {
        if (current == null) throw EnerCubixHttpErr(409,"CONFLICT","引用配置已删除，停止回滚")
        before:=EnerCubixRepo.decode(original); after:=(Str:Obj?)JsonInStream(s["afterBusiness"].toStr.in).readJson
        now:=EnerCubixRepo.decode(current); restored:=now.dup
        before.keys.dup.addAll(after.keys).unique.each |field|
        {
          if (["id","mod"].contains(field) || before[field] == after[field]) return
          if (now[field] != after[field]) throw EnerCubixHttpErr(409,"CONFLICT","迁移引用已有后续修改，停止回滚")
          if (before[field] == null) restored.remove(field); else restored[field]=before[field]
        }
        diffs.add(Diff(current,repo.encode(restored,current)))
      }
    }
    diffs.add(Diff(model,null,Diff.remove))
    data["status"]="rolledBack"; diffs.add(Diff(job,repo.encode(data,job)))
    repo.commit(diffs)
    return ["rolledBack":snaps.size,"job":EnerCubixRepo.decode(repo.stored(job.id.id))]
  }

  private static Str:Obj? owned(Dict rec)
  { out:=Str:Obj?[:]; EnerCubixNativeEquip.ownedTags.each |tag| { if (rec.has(tag)) out[tag]=rec[tag] }; return out }
  private static Str:Obj? ownedAfter(Dict before, Dict patch)
  { out:=owned(before); patch.each |v,k| { if (v is Remove) out.remove(k); else out[k]=v }; return out }
  private static Str zinc(Dict rec) { ZincWriter.gridToStr(Etc.makeDictsGrid(null,[rec])) }
  private static Dict readZinc(Str text) { ZincReader(text.in).readGrid.first ?: Etc.emptyDict }
}

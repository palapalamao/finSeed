using haystack
using folio
using skyarcd
using util

** Native-equipment persistence and reversible model migration.
class FinEnergyNativeEquipRepo
{
  FinEnergyRepo repo
  Context cx
  static const Str modelId := "finEnergy-native-equip-model"
  new make(FinEnergyRepo repo) { this.repo=repo; this.cx=repo.cx }

  Dict? model() { cx.db.read(Filter.has("finEnergyStorageModel"),false) }
  Bool active() { model?.get("finEnergyStorageModel") == "nativeEquip" }
  Str:Str mapping()
  {
    owner:=repo.cockpitPreparation
    if(owner!=null)
    {
      if(repo.cockpitAliases==null) repo.cockpitAliases=FinEnergyNativeAliases(owner)
      return repo.cockpitAliases.read |->Str| {model?.get("finEnergyAliases") as Str ?: "{}"}
    }
    json:=model?.get("finEnergyAliases") as Str ?: "{}"
    out:=Str:Str[:]
    ((Map)JsonInStream(json.in).readJson).each |v,k| {out[k.toStr]=v.toStr}
    return out
  }

  Str resolve(Str id) { mapping[id] ?: id }

  ** Repair old application-owned archives when they are first edited. Normal
  ** enrollment needs no model record; every subsequent write uses equipment.
  [Str:Obj?][] prepareWrite([Str:Obj?][] input, Str? copyTarget := null)
  {
    if (active) return input
    legacy:=input.findAll |r|
    {
      id:=r["id"] as Str
      old:=id == null ? null : cx.db.readById(Ref(id),false)
      return old != null && !old.has("equip") && old.has("finEnergy") && FinEnergyRelations.meterKinds.contains(old["finEnergyKind"])
    }
    if (legacy.isEmpty) return input
    legacy.each |r| { FinEnergyRepo.checkMod(repo.stored(r["id"].toStr),r["mod"]) }
    plan:=migrate(["action":"preview"])
    pending:=input
    if (copyTarget!=null && input.size==1)
    {
      kind:=repo.stored(legacy.first["id"].toStr)["finEnergyKind"]
      pending=input.dup.add(["id":copyTarget,"kind":kind])
    }
    FinEnergyLicenseQuota.checkMigration(cx.sys,cx.db,pending,plan)
    migrate(["action":"apply","revision":plan["revision"],"sourceRevision":plan["sourceRevision"]])
    aliases:=mapping
    return input.map |r->[Str:Obj?]|
    {
      out:=FinEnergyNativeEquip.rewrite(r,aliases)
      if (aliases.containsKey(r["id"]?.toStr ?: "")) out["mod"]=FinEnergyRepo.iso(equipment(out["id"].toStr)["mod"])
      return out
    }
  }

  [Str:Obj?][] records([Str:Obj?][] raw)
  {
    repo.cockpitPreparation?.hold(2*(1+raw.size))
    raw=raw.findAll |r| { r["action"] != "nativeEquipSnapshot" }
    if (!active) return raw
    return raw.findAll |r| { !FinEnergyRelations.meterKinds.contains(r["kind"]) || r["nativeEquip"] == true }
  }

  Dict equipment(Str id)
  {
    r:=cx.db.readById(Ref(resolve(id)),false)
    if (r == null || !r.has("equip")) throw ArgErr("请选择当前项目中已有的 FIN 设备")
    if (!cx.canRead(r)) throw FinEnergyHttpErr(403,"PERMISSION","没有此 FIN 设备的读取权限")
    return r
  }

  [Str:Obj?] prepare([Str:Obj?] input)
  {
    out:=FinEnergyNativeSpace.clean(input)
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
    if (out["useAlias"] != true) out["name"]=FinEnergyNativeEquip.decode(eq)["nativeName"]
    // Enrollment also requires the equipment revision observed in the catalog.
    FinEnergyRepo.checkMod(eq,input["mod"])
    if (eq.has("finEnergyKind") && !FinEnergyRelations.meterKinds.contains(eq["finEnergyKind"])) throw ArgErr("设备已被其他 FinEnergy 配置占用")
    if (out["parentId"] != (eq["finEnergyParentRef"] as Ref)?.id) throw ArgErr("空间层级由 FIN 维护，旧分析分组只读；请设置计量覆盖范围")
    out["nativeEquip"]=true
    return out
  }

  Void validate([Str:Obj?] record, [Str:Obj?][] all)
  {
    eq:=equipment(record["id"].toStr)
    pointId:=record["pointId"] as Str
    point:=pointId == null ? null : cx.db.readById(Ref(pointId),false)
    if (point != null && !cx.canRead(point)) throw FinEnergyHttpErr(403,"PERMISSION","没有主计量点的读取权限")
    if (!FinEnergyRelations.meterKinds.contains(record["kind"])) throw ArgErr("设备能源类型标签无效")
    FinEnergyConfig.validateNewBinding(record,eq.has("finEnergyKind") ? FinEnergyRepo.decode(eq) : null,all)
    FinEnergyNativeEquip.validateSource(record,eq,point,all)
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
    areaSpace:=record["areaSpaceId"] as Str
    if (record["areaSource"] == "space" && areaSpace != null)
    {
      target:=validation.find |r| { r["id"] == areaSpace || r["nativeSourceId"] == areaSpace }
      sourceId:=target?.get("nativeSourceId") as Str ?: areaSpace
      space:=cx.db.readById(Ref(sourceId),false)
      if (space == null || !(space.has("site") || space.has("floor")) || !cx.canRead(space)) throw ArgErr("invalidAreaSpace")
      // A coverage placeholder is not an authoritative service-space definition.
      areaRow:=FinEnergySpaceArea.referenceRow(areaSpace,space,target)
      validation=validation.findAll |r| { r["id"] != areaRow["id"] }.dup.add(areaRow)
    }
    FinEnergyConfig.validate(checked,validation)
  }

  [Str:Obj?][] validateRead([Str:Obj?][] all)
  {
    all.each |r|
    {
      if(r["nativeEquip"] != true) return
      repo.cockpitPreparation?.budget?.deadline?.check
      repo.cockpitPreparation?.hold(2+r.size)
      // Area is optional metadata. A lost/inaccessible service space must not
      // invalidate primary-history consumption; normalization diagnoses it later.
      checked:=r.dup
      ["areaSource","areaSpaceId","area"].each |key| { checked.remove(key) }
      try { validate(checked,all) }
      catch (Err e) { r["configurationError"]=e.msg }
    }
    return all
  }

  Diff write([Str:Obj?] record)
  {
    prev:=equipment(record["id"].toStr)
    FinEnergyRepo.checkMod(prev,record["mod"])
    return Diff(prev,FinEnergyNativeEquip.tags(record,prev,cx.user.username))
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
    if (unit.isEmpty || FinEnergyMath.unitFactor(unit,category["unit"]?.toStr ?: "") == null) throw ArgErr("主能耗点单位与能源类型不兼容")
    id:=Ref.gen; pointId:=Ref.gen
    rec:=FinEnergyNativeSpace.clean(input); rec["id"]=id.id; rec["pointId"]=pointId.id; rec["unit"]=unit
    rec["includeInTotals"]=input["includeInTotals"] ?: true
    rec["autoSum"]=input["autoSum"] ?: (input["kind"] == "totalMeter")
    rec.remove("parentId"); rec.remove("createNative"); rec.remove("siteId"); rec.remove("floorId")
    pointName:=category["name"].toStr
    tz:=site["tz"] ?: (cx.proj.meta["tz"] ?: "UTC")
    pointTags:=Str:Obj?["point":Marker.val,"sensor":Marker.val,"cur":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"hisMode":"consumption","hisCollectInterval":Number(15,Unit.fromStr("min")),"kind":"Number","unit":unit,"dis":pointName,"navName":pointName,"equipRef":id,"siteRef":site.id,"floorRef":floor.id,"tz":tz]
    tags:=Etc.dictToMap(FinEnergyNativeEquip.tags(rec,Etc.emptyDict,cx.user.username))
    tags["equip"]=Marker.val; tags["meter"]=Marker.val; tags["dis"]=rec["name"]; tags["navName"]=rec["name"]; tags["siteRef"]=site.id; tags["floorRef"]=floor.id
    if (category["energyType"] == "elec" || ["电","电力","电能","electric","electricity","elec"].contains(pointName.lower))
    {
      tags["elec"]=Marker.val; pointTags["elec"]=Marker.val; pointTags["energy"]=Marker.val
    }
    FinEnergyConfig.validate(rec,all.dup.add(rec))
    FinEnergyNativeEquip.validateSource(rec,Etc.makeDict(tags.dup.set("id",id)),Etc.makeDict(pointTags.dup.set("id",pointId)),all)
    if (rec["cleaningEnabled"] == true)
    {
      profile:=repo.stored(rec["cleaningProfileId"] as Str ?: throw ArgErr("请选择清洗方案"))
      if (profile["finEnergyKind"] != "cleaningProfile") throw ArgErr("清洗方案不存在")
      newPoint:=Etc.makeDict(pointTags.dup.set("id",pointId))
      cleaning:=FinEnergyCleaningRepo.install(newPoint,id,FinEnergyCleaningRepo.configFor(FinEnergyRepo.decode(profile),newPoint))
      cleaning.each |v,k| { pointTags[k]=v }
    }
    // Equipment, its own historical point and the configuration revision are one commit.
    repo.commit([Diff.makeAdd(Etc.makeDict(tags),id),Diff.makeAdd(Etc.makeDict(pointTags),pointId)])
    return FinEnergyRepo.decode(repo.stored(id.id))
  }

  [Str:Obj?] createVirtual([Str:Obj?] input)
  {
    throw ArgErr("虚拟表也必须选择已有主能耗点，请先在 FIN 中准备设备和点位")
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
      if (cx.proj.name != "finEnergy_acceptance") throw ArgErr("迁移范围限制仅供独立验收项目使用")
      fixtureIds:=FinEnergyMath.strings(input["fixtureIds"])
      all=all.findAll |r| { !FinEnergyRelations.meterKinds.contains(r["kind"]) || fixtureIds.contains(r["id"]) }
    }
    equips:=cx.db.readAllList(Filter.has("equip")).findAll |r| { cx.canRead(r) }
    points:=cx.db.readAllList(Filter.has("point")).findAll |r| { cx.canRead(r) }
    plan:=FinEnergyNativeEquip.preview(all,equips,points)
    plan["revision"]=FinEnergyRepo.iso(cx.db.read(Filter.has("finEnergyRevision"),false)?.get("mod")) ?: ""
    // Exclude volatile collection metadata; protect ownership, unit, history and every owned tag.
    targetIds:=((Map)plan["mapping"]).vals
    pointIds:=FinEnergyMath.maps(plan["records"]).map |r->Str| { r["pointId"]?.toStr ?: "" }
    plan["sourceRevision"]=FinEnergyNativeEquip.sourceRevision(equips.findAll |e| { targetIds.contains(e.id.id) },points.findAll |p| { pointIds.contains(p.id.id) })
    if (action == "preview") return plan
    if (action != "apply") throw ArgErr("无效的原生设备迁移操作")
    if (input["revision"] != plan["revision"] || input["sourceRevision"] != plan["sourceRevision"]) throw FinEnergyHttpErr(409,"CONFLICT","源配置已变化，请重新预览迁移")
    if (!FinEnergyMath.strings(plan["conflicts"]).isEmpty) throw ArgErr("请先处理迁移预览中的冲突")
    aliases:=(Str:Str)plan["mapping"]
    edits:=FinEnergyMath.maps(plan["records"])
    candidate:=all.findAll |r| { !aliases.containsKey(r["id"]) }.dup.addAll(edits)
    diffs:=Diff[,]; snapshots:=[Str:Obj?][,]
    edits.each |r|
    {
      validate(r,candidate)
      eq:=equipment(r["id"].toStr)
      snapshots.add(["type":"equip","id":eq.id.id,"before":zinc(Etc.makeDict(owned(eq))),"after":zinc(Etc.makeDict(ownedAfter(eq,FinEnergyNativeEquip.tags(r,eq,cx.user.username))))])
      diffs.add(write(r))
      old:=repo.stored(r["legacyId"].toStr)
      snapshots.add(["type":"archive","id":old.id.id,"before":zinc(old)])
    }
    all.findAll |r| { !aliases.containsKey(r["id"]) && r["kind"] != "alarm" && !(r["action"]?.toStr ?: "").contains("Snapshot") }.each |r|
    {
      updated:=FinEnergyNativeEquip.rewrite(r,aliases)
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
    tags:=Etc.makeDict(["finEnergyStorageModel":"nativeEquip","finEnergyAliases":JsonOutStream.writeJsonToStr(aliases),"finEnergyMigrationKey":key.id])
    if (oldModel != null) throw ArgErr("原生设备模型标识已存在，请先处理旧迁移记录")
    diffs.add(Diff.makeAdd(tags,Ref(modelId)))
    job:=Str:Obj?["id":key.id,"kind":"job","name":"FIN 原生设备模型迁移","action":"nativeEquipMigration","status":"applied","enabled":false,"migrationKey":key.id,"processed":edits.size,"lastRun":DateTime.now.toIso]
    diffs.add(Diff.makeAdd(repo.encode(job),key))
    repo.commit(diffs)
    return ["applied":edits.size,"job":FinEnergyRepo.decode(repo.stored(key.id))]
  }

  private [Str:Obj?][] snapshots(Str key)
  { repo.rawRecords(true).findAll |r| { r["action"] == "nativeEquipSnapshot" && r["migrationKey"] == key }.map |r->[Str:Obj?]| { (Str:Obj?)r["snapshot"] } }

  private [Str:Obj?] finalize([Str:Obj?] input)
  {
    job:=repo.stored(input["jobId"].toStr); FinEnergyRepo.checkMod(job,input["mod"])
    if (!active || job["finEnergyKind"] != "job") throw ArgErr("没有可完成的迁移")
    data:=FinEnergyRepo.decode(job)
    if (data["action"] != "nativeEquipMigration" || data["status"] != "applied") throw ArgErr("此迁移状态不可清理")
    if (model?.get("finEnergyMigrationKey") != data["migrationKey"]) throw ArgErr("迁移记录与当前读取模型不匹配")
    snaps:=snapshots(data["migrationKey"].toStr)
    if (snaps.isEmpty) throw ArgErr("恢复材料缺失，不能清理")
    diffs:=Diff[,]
    snaps.findAll |s| { s["type"] == "archive" }.each |s|
    {
      original:=readZinc(s["before"].toStr)
      current:=cx.db.readById(original.id,false)
      if (current == null || Etc.dictToMap(current) != Etc.dictToMap(original)) throw FinEnergyHttpErr(409,"CONFLICT","旧档案已变化，停止清理")
      diffs.add(Diff(current,null,Diff.remove))
    }
    data["status"]="finalized"; diffs.add(Diff(job,repo.encode(data,job)))
    removed:=diffs.size-1
    repo.commit(diffs)
    return ["removed":removed,"job":FinEnergyRepo.decode(repo.stored(job.id.id))]
  }

  private [Str:Obj?] rollback([Str:Obj?] input)
  {
    job:=repo.stored(input["jobId"].toStr); FinEnergyRepo.checkMod(job,input["mod"])
    data:=FinEnergyRepo.decode(job)
    if (!active || data["action"] != "nativeEquipMigration" || !["applied","finalized"].contains(data["status"])) throw ArgErr("此迁移不可回滚")
    if (model?.get("finEnergyMigrationKey") != data["migrationKey"]) throw ArgErr("迁移记录与当前读取模型不匹配")
    snaps:=snapshots(data["migrationKey"].toStr)
    if (snaps.isEmpty) throw ArgErr("恢复材料缺失")
    diffs:=Diff[,]
    snaps.each |s|
    {
      original:=readZinc(s["before"].toStr)
      current:=cx.db.readById(Ref(s["id"].toStr),false)
      if (s["type"] == "equip")
      {
        if (current == null) throw FinEnergyHttpErr(409,"CONFLICT","原生设备已删除，停止回滚")
        after:=readZinc(s["after"].toStr)
        before:=owned(original); expected:=owned(after); currentTags:=owned(current)
        patch:=Str:Obj?[:]
        ownedKeys:=before.keys.dup.addAll(expected.keys).unique
        ownedKeys.each |tag|
        {
          if (["finEnergyUpdatedAt","finEnergyUpdatedBy"].contains(tag)) return
          if (before[tag] == expected[tag]) return
          if (currentTags[tag] != expected[tag]) throw FinEnergyHttpErr(409,"CONFLICT","设备能源标签已有后续修改，停止回滚："+current.dis+" / "+tag)
          patch[tag]=before[tag] ?: Remove.val
        }
        diffs.add(Diff(current,Etc.makeDict(patch)))
      }
      else if (s["type"] == "archive")
      {
        if (current == null)
        {
          tags:=Etc.dictToMap(original); tags.remove("id"); tags.remove("mod")
          diffs.add(Diff.makeAdd(Etc.makeDict(tags),FinEnergyRepo.addId(s["id"].toStr,cx.proj.name)))
        }
        else if (Etc.dictToMap(current) != Etc.dictToMap(original)) throw FinEnergyHttpErr(409,"CONFLICT","旧档案已有后续修改，停止回滚")
      }
      else
      {
        if (current == null) throw FinEnergyHttpErr(409,"CONFLICT","引用配置已删除，停止回滚")
        before:=FinEnergyRepo.decode(original); after:=(Str:Obj?)JsonInStream(s["afterBusiness"].toStr.in).readJson
        now:=FinEnergyRepo.decode(current); restored:=now.dup
        before.keys.dup.addAll(after.keys).unique.each |field|
        {
          if (["id","mod"].contains(field) || before[field] == after[field]) return
          if (now[field] != after[field]) throw FinEnergyHttpErr(409,"CONFLICT","迁移引用已有后续修改，停止回滚")
          if (before[field] == null) restored.remove(field); else restored[field]=before[field]
        }
        diffs.add(Diff(current,repo.encode(restored,current)))
      }
    }
    diffs.add(Diff(model,null,Diff.remove))
    data["status"]="rolledBack"; diffs.add(Diff(job,repo.encode(data,job)))
    repo.commit(diffs)
    return ["rolledBack":snaps.size,"job":FinEnergyRepo.decode(repo.stored(job.id.id))]
  }

  private static Str:Obj? owned(Dict rec)
  { out:=Str:Obj?[:]; FinEnergyNativeEquip.ownedTags.each |tag| { if (rec.has(tag)) out[tag]=rec[tag] }; return out }
  private static Str:Obj? ownedAfter(Dict before, Dict patch)
  { out:=owned(before); patch.each |v,k| { if (v is Remove) out.remove(k); else out[k]=v }; return out }
  private static Str zinc(Dict rec) { ZincWriter.gridToStr(Etc.makeDictsGrid(null,[rec])) }
  private static Dict readZinc(Str text) { ZincReader(text.in).readGrid.first ?: Etc.emptyDict }
}

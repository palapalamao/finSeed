using util
using haystack
using folio
using skyarcd

** FIN identity and Folio storage. No business state is stored outside the project.
class FinEnergyRepo
{
  Context cx
  private Bool revisionRead := false
  private Dict? revision
  internal FinEnergyNativeAliases? cockpitAliases
  internal FinEnergyPreparedOwner? cockpitPreparation
  new make(Context cx) { this.cx = cx }

  static const [Str:Str] refTags := ["parentId":"finEnergyParentRef", "pointId":"finEnergyPointRef", "categoryId":"finEnergyCategoryRef", "subcategoryId":"finEnergySubcategoryRef", "utilityId":"finEnergyUtilityRef", "tariffId":"finEnergyTariffRef", "expressionId":"finEnergyExpressionRef", "numeratorId":"finEnergyNumeratorRef", "denominatorId":"finEnergyDenominatorRef", "nodeId":"finEnergyNodeRef", "spaceId":"finEnergySpaceRef", "areaSpaceId":"finEnergyAreaSpaceRef", "meterParentId":"finEnergyMeterParentRef", "organizationId":"finEnergyOrganizationRef", "canonicalId":"finEnergyCanonicalRef", "nativeAlarmId":"finEnergyNativeAlarmRef", "episodeId":"finEnergyAlarmEpisodeRef", "cleaningProfileId":"finEnergyCleaningProfileRef"]

  Void mustRead()
  {
    if (cx.user.isGuest) throw FinEnergyHttpErr(401, "SESSION", "FIN 会话已失效，请重新登录")
  }

  Void mustWrite()
  {
    mustRead
    if (!cx.user.isAdmin) throw FinEnergyHttpErr(403, "PERMISSION", "当前 FIN 用户没有配置写入权限")
    requireConfigurationAccess
  }

  internal Bool licenseAllowsCalculation()
  { FinEnergyEditionLicense.allowed(cx) && !FinEnergyNamespace.needsMigration(cx.db) }

  internal Void requireLicensedCalculation()
  {
    if (FinEnergyNamespace.needsMigration(cx.db)) throw FinEnergyHttpErr(409,"NAMESPACE_MIGRATION_REQUIRED","namespaceMigrationRequired")
    if (!licenseAllowsCalculation) throw FinEnergyHttpErr(409,"LICENSE_REQUIRED",FinEnergyEditionLicense.calculationReason)
  }

  internal Void requireConfigurationAccess()
  {
    if (FinEnergyNamespace.needsMigration(cx.db)) throw FinEnergyHttpErr(409,"NAMESPACE_MIGRATION_REQUIRED","namespaceMigrationRequired")
    if (!FinEnergyEditionLicense.configurationAllowed(cx)) throw FinEnergyHttpErr(409,"LICENSE_REQUIRED",FinEnergyEditionLicense.calculationReason)
  }

  internal [Str:Obj?] licenseStatus()
  {
    mustRead
    return FinEnergyEditionLicense.status(cx)
  }

  internal Str:Obj? licenseImport(Obj? raw)
  { mustRead;FinEnergyEditionLicense.install(cx,raw);return licenseStatus }

  internal Str:Obj? licenseDelete(Obj? token)
  { mustRead;FinEnergyEditionLicense.remove(cx,token);return licenseStatus }

  private Void readRevision()
  {
    if (revisionRead) return
    revision = FinEnergyNamespace.singleton(cx.db,"finEnergyRevision")
    revisionRead = true
  }

  [Str:Obj?][] records()
  { FinEnergyNativeEquipRepo(this).records(rawRecords) }

  [Str:Obj?][] rawRecords(Bool recovery := false, Bool comparison := false, Bool analysis := false, Bool navigation := false)
  {
    mustRead
    requireConfigurationAccess
    readRevision
    rows:=cx.db.readAllList(Filter.has("finEnergyKind").and(Filter.has("finEnergy").or(Filter.has("equip"))))
    cockpitPreparation?.hold(1);out:=[Str:Obj?][,]
    cockpitPreparation?.watch |->Void| {out.clear}
    rows.each |r|
    {
      if (!comparison && !cx.canRead(r)) return
      if (!recovery && (r["finEnergyConfig"] as Str ?: "").contains("\"action\":\"nativeEquipSnapshot\"")) return
      cockpitPreparation?.hold(2)
      data:=analysis ? FinEnergyCockpitInput.decode(r,cockpitPreparation) : (navigation ? FinEnergyCatalog.decode(r,true) : (cockpitPreparation==null ? decode(r) : decodeOwned(r,cockpitPreparation)))
      if(comparison) data["_comparisonReadable"]=cx.canRead(r)
      out.add(data)
    }
    return out
  }

  [Str:Obj?] catalog(Str mode := "full")
  {
    if(!["full","analysis"].contains(mode)) throw ArgErr("catalogModeInvalid")
    all:=mode=="analysis" ? FinEnergyNativeEquipRepo(this).records(rawRecords(false,false,false,true)) : records
    source:=FinEnergyNativeSpace.load(cx)
    projected:=source.project(all)
    info:=source.info(all)
    projected=FinEnergyCleaningRepo(this).decorate(FinEnergyNativeEquipRepo(this).validateRead(projected))
    sources:=Str:Dict?[:]
    readSource:=|Str id->Dict?|
    {
      if (!sources.containsKey(id))
      {
        record:=cx.db.readById(Ref(id),false)
        sources[id]=record != null && cx.canRead(record) ? record : null
      }
      return sources[id]
    }
    projected=FinEnergyMeterOrigin.decorate(projected,readSource,|Ref ref->Dict?| { readSource(ref.id) })
    owned:=ownedSnapshot
    refs:=FinEnergyMath.maps(owned["budgets"]).dup.addAll(FinEnergyMath.maps(owned["rules"])).findAll |r| {r["validation"] != "invalid"}.map |r->[Str:Obj?]| {["id":r["id"],"mod":r["mod"]]}
    return ["catalogMode":mode,"edition":FinEnergyEditionLicense.edition,"licenseMode":FinEnergyEditionLicense.licenseMode,"version":FinEnergyRepo#.pod.version.toStr, "project":cx.proj.name, "projectRef":cx.proj.id.id,"cockpitConfigRefs":refs,"user":["name":cx.user.username,"canWrite":cx.user.isAdmin], "storageModel":"nativeEquip", "spaceSource":"fin", "nativeTreePath":source.path, "nativeTreeWarnings":info["warnings"], "records":projected]
  }

  Bool nativeModel() { FinEnergyNativeEquipRepo(this).active }

  [Str:Obj?][] liveRecords() { FinEnergyNativeSpace.load(cx).project(records) }

  [Str:Obj?] nativeSpaceInfo() { mustRead; return FinEnergyNativeSpace.load(cx).info(records) }

  Dict stored(Str id)
  {
    mustRead
    r := cx.db.readById(Ref.fromStr(id), false)
    if (r == null || !r.has("finEnergy") || !r.has("finEnergyKind")) throw FinEnergyHttpErr(404,"NOT_FOUND","配置记录不存在")
    if (!cx.canRead(r)) throw FinEnergyHttpErr(403,"PERMISSION","当前 FIN 用户没有此记录的读取权限")
    return r
  }

  [Str:Obj?] save([Str:Obj?] input, Bool systemWrite := false)
  {
    mustWrite
    if (input["areaOnly"] == true) return saveSpaceArea(input)
    if (input["kind"] == "cleaningProfile") return FinEnergyCleaningRepo(this).save(input)
    equipStore:=FinEnergyNativeEquipRepo(this)
    if (FinEnergyRelations.meterKinds.contains(input["kind"])) input=equipStore.prepareWrite([input]).first
    all := liveRecords
    if (nativeModel && input["kind"] == "group") throw ArgErr("旧分析分组仅供历史报告读取，不再维护")
    if (FinEnergyRelations.meterKinds.contains(input["kind"]))
    {
      if (input["id"] == null && input["createNative"] == true) return equipStore.createNative(input)
      if (input["id"] == null && input["createVirtual"] == true) return equipStore.createVirtual(input)
      rec:=equipStore.prepare(input)
      equipStore.validate(rec,all.findAll |r| { r["id"] != rec["id"] }.dup.add(rec))
      changes:=FinEnergyCleaningRepo(this).configure(rec)
      changes.add(equipStore.write(rec)); commit(changes)
      return decode(stored(rec["id"].toStr))
    }
    FinEnergyNativeSpace.mustEditable(input["id"] as Str,all)
    rec := FinEnergyNativeSpace.clean(input)
    kind := rec["kind"] as Str ?: ""
    if (!systemWrite && ["job","alarm"].contains(kind)) throw ArgErr("任务和报警只能由业务操作产生")
    id := rec["id"] as Str
    Dict? previous := id == null ? null : stored(id)
    if (previous != null)
    {
      checkMod(previous, rec["mod"])
      if (previous["finEnergyKind"] != kind && !(["meter","totalMeter"].contains(previous["finEnergyKind"]) && ["meter","totalMeter"].contains(kind))) throw ArgErr("记录类型不可直接更改，请使用总表/分表切换")
    }
    if (previous == null) rec["id"] = Ref.gen.id
    if (rec["expressionId"] != null && rec["pointId"] != null) throw ArgErr("物理点和表达式不能同时绑定")
    if (rec["expressionId"] != null && !rec.containsKey("includeInTotals")) rec["includeInTotals"] = false
    FinEnergyNativeSpace.placeBinding(rec,previous == null ? null : decode(previous),all)
    FinEnergyConfig.validateNewBinding(rec,previous == null ? null : decode(previous),all)
    FinEnergyConfig.validate(rec, all)
    validatePoint(rec)
    diff := previous == null ? Diff.makeAdd(encode(rec), Ref.fromStr(rec["id"].toStr)) : Diff(previous, encode(rec,previous))
    commit([diff], kind == "job" || kind == "alarm")
    return decode(stored(rec["id"].toStr))
  }

  private [Str:Obj?] saveSpaceArea([Str:Obj?] input)
  {
    all:=liveRecords
    row:=all.find |r| { r["id"] == input["id"] }
    if (row == null || !FinEnergySpaceArea.editable(row)) throw ArgErr("spaceAreaOnly")
    nativeRec:=cx.db.readById(Ref(row["nativeSourceId"].toStr),false)
    if (nativeRec == null || !cx.canRead(nativeRec) || !cx.canWrite(nativeRec)) throw FinEnergyHttpErr(403,"PERMISSION","spaceAreaForbidden")
    checkMod(nativeRec,input["mod"])
    // Only area is committed. Submitted names, placement or source IDs are rejected.
    patch:=FinEnergySpaceArea.tags(input,nativeRec)
    commit([Diff(nativeRec,patch)])
    return liveRecords.find |r| { r["id"] == input["id"] } ?: throw Err("Native space disappeared after area save")
  }

  [Str:Obj?] remove(Str id, Obj? mod)
  {
    mustWrite
    all:=liveRecords
    FinEnergyNativeSpace.mustEditable(id,all)
    prev := stored(id)
    if (prev["finEnergyKind"] == "cleaningProfile") return FinEnergyCleaningRepo(this).remove(id,mod)
    checkMod(prev,mod)
    if(ownedStore.referencesId(id)) throw FinEnergyHttpErr(409,"CONFLICT","cockpitConfigReferenced")
    if (nativeModel && prev["finEnergyKind"] == "group") throw ArgErr("旧分组供历史报表兼容使用，不可删除")
    if (["job","alarm"].contains(prev["finEnergyKind"])) throw ArgErr("任务和报警记录应保留以供追溯")
    FinEnergyConfig.canDelete(id, prev.has("equip") ? all.findAll |r| { r["kind"] != "nativePoint" && r["nativeReadonly"] != true } : all)
    changes:=prev.has("equip") ? FinEnergyCleaningRepo(this).disable(prev) : Diff[,]
    changes.add(prev.has("equip") ? Diff(prev,FinEnergyNativeEquip.clear(prev)) : Diff(prev,null,Diff.remove))
    commit(changes)
    return ["deleted":id]
  }

  ** Atomic engineering operations. A deletion requires an unchanged preview revision.
  [Str:Obj?] manage([Str:Obj?] input)
  {
    mustWrite
    action:=input["action"] as Str ?: ""
    if (action == "save") return saveBatch(FinEnergyMath.maps(input["records"]),liveRecords)
    items:=FinEnergyMath.maps(input["items"])
    if (["assign","move","totals","copy"].contains(action))
    {
      equipStore:=FinEnergyNativeEquipRepo(this)
      copyTarget:=action=="copy" && (input["dimension"] ?: "legacy")!="legacy" ? (input["targetId"] as Str) : null
      items=equipStore.prepareWrite(items,copyTarget)
      input=FinEnergyNativeEquip.rewrite(input,equipStore.mapping)
      if (input["patch"] is Map) input["patch"]=FinEnergyNativeEquip.rewrite((Str:Obj?)input["patch"],equipStore.mapping)
    }
    all:=liveRecords
    ids:=items.map |r->Str| { r["id"]?.toStr ?: "" }
    ids.each |id| { FinEnergyNativeSpace.mustEditable(id,all) }
    FinEnergyTreePlan.roots(all,ids)
    items.each |r| { checkMod(stored(r["id"].toStr),r["mod"]) }
    dimension:=input["dimension"] as Str ?: "legacy"
    if (!FinEnergyRelations.dimensions.contains(dimension)) throw ArgErr("无效的树维度")
    if (action == "assign")
    {
      patch:=input["patch"] as Map ?: throw ArgErr("缺少批量归属设置")
      allowed:=["spaceId","meterParentId","organizationId","utilityId","categoryId","includeInTotals"]
      if (patch.isEmpty || patch.keys.any |key| { !allowed.contains(key) }) throw ArgErr("批量归属字段无效")
      edits:=ids.map |id->[Str:Obj?]|
      {
        r:=all.find |r| { r["id"] == id }.dup
        if (!FinEnergyRelations.meterKinds.contains(r["kind"]) || r["canonicalId"] != null) throw ArgErr("请选择计量主档案")
        patch.each |val,key| { if (val == null) r.remove(key); else r[key]=val }
        return r
      }
      return saveBatch(edits,all)
    }
    if (action == "move" && dimension != "legacy") return saveBatch(FinEnergyRelations.move(all,ids,input["parentId"] as Str,dimension),all)
    if (action == "copy" && dimension != "legacy")
    {
      if (items.size != 1) throw ArgErr("每次复制一个对象")
      old:=all.find |r| { r["id"] == ids.first }
      if (FinEnergyRelations.meterKinds.contains(old["kind"]) || input["targetId"] != null)
      {
        target:=FinEnergyNativeEquipRepo(this).equipment(input["targetId"] as Str ?: throw ArgErr("请选择已有目标设备"))
        if (target.has("finEnergyKind")) throw ArgErr("目标设备已经纳入能源分析")
        copy:=old.dup; copy["id"]=target.id.id; copy["mod"]=input["targetMod"]; copy["name"]=target.dis; copy["useAlias"]=false
        copy.remove("pointId"); copy.remove("expressionId"); copy.remove("canonicalId")
        copy["pointId"]=input["pointId"]
        return ["records":[save(copy)]]
      }
      copy:=old.dup; copy.remove("id"); copy.remove("mod"); copy.remove("pointId"); copy.remove("canonicalId"); copy.remove("expressionId")
      copy["name"]=old["name"].toStr+" 副本 "+DateTime.nowTicks.toStr
      copy["includeInTotals"]=false
      return saveBatch([copy],all)
    }
    if (action == "previewDelete" || action == "delete")
    {
      // Unenrollment never cascades through a native physical hierarchy.
      deleteScope:=all.findAll |r| { r["kind"] != "nativePoint" && r["nativeReadonly"] != true }
      plan:=FinEnergyTreePlan.deletion(deleteScope,ids)
      selected:=FinEnergyMath.maps(plan["records"])
      selected.each |r| { FinEnergyNativeSpace.mustEditable(r["id"] as Str,all) }
      if(selected.any |r| {ownedStore.referencesId(r["id"].toStr)}) throw FinEnergyHttpErr(409,"CONFLICT","cockpitConfigReferenced")
      rev:=iso(revision?.get("mod")) ?: ""
      if (action == "previewDelete")
      {
        plan["revision"]=rev
        plan["records"]=selected.map |r->[Str:Obj?]| { ["id":r["id"],"kind":r["kind"],"name":r["name"]] }
        return plan
      }
      if (input["revision"] != rev) throw FinEnergyHttpErr(409,"CONFLICT","配置已变化，请重新查看删除预览")
      if (!((List)plan["blockers"]).isEmpty) throw ArgErr("仍被模板、公式或其他配置引用，请先解除预览中列出的关联")
      diffs:=selected.map |r->Diff| { prev:=stored(r["id"].toStr); checkMod(prev,r["mod"]); return prev.has("equip") ? Diff(prev,FinEnergyNativeEquip.clear(prev)) : Diff(prev,null,Diff.remove) }
      selected.each |r| { prev:=stored(r["id"].toStr); if (prev.has("equip")) diffs.addAll(FinEnergyCleaningRepo(this).disable(prev)) }
      commit(diffs)
      return ["deleted":selected.map |r->Str| { r["id"].toStr }]
    }
    edits:=[Str:Obj?][,]
    if (action == "move") edits=FinEnergyTreePlan.move(all,ids,input["parentId"] as Str)
    else if (action == "totals")
    {
      if (input["included"] isnot Bool) throw ArgErr("请选择是否计入合计")
      edits=all.findAll |r| { ids.contains(r["id"]) }.map |r->[Str:Obj?]| { copy:=r.dup; if (!["meter","totalMeter"].contains(r["kind"])) throw ArgErr("仅表计支持计入合计设置"); copy["includeInTotals"]=input["included"]; return copy }
    }
    else throw ArgErr("不支持的批量操作")
    return saveBatch(edits,all)
  }

  private [Str:Obj?] saveBatch([Str:Obj?][] input, [Str:Obj?][] all)
  {
    if (input.isEmpty || input.size > 200) throw ArgErr("单次请保存 1 至 200 个对象")
    equipStore:=FinEnergyNativeEquipRepo(this)
    input=equipStore.prepareWrite(input)
    all=liveRecords
    edits:=[Str:Obj?][,]; diffs:=Diff[,]; ids:=Str[,]
    input.each |data|
    {
      if (FinEnergyRelations.meterKinds.contains(data["kind"]))
      {
        rec:=equipStore.prepare(data); id:=rec["id"].toStr
        if (ids.contains(id)) throw ArgErr("每台 FIN 设备只允许一个主能耗点，请明确选择")
        ids.add(id); edits.add(rec)
        return
      }
      FinEnergyNativeSpace.mustEditable(data["id"] as Str,all)
      rec:=FinEnergyNativeSpace.clean(data)
      if (!FinEnergyConfig.nodeKinds.contains(rec["kind"])) throw ArgErr("批量操作只支持计量树对象")
      id:=rec["id"] as Str
      if (id != null)
      {
        prev:=stored(id); checkMod(prev,rec["mod"])
        if (prev["finEnergyKind"] != rec["kind"]) throw ArgErr("批量操作不可更改对象类型")
      }
      else rec["id"]=Ref.gen.id
      id=rec["id"].toStr
      if (ids.contains(id)) throw ArgErr("同一批次包含重复对象")
      FinEnergyNativeSpace.placeBinding(rec,all.find |r| { r["id"] == id },all)
      ids.add(id); edits.add(rec)
    }
    candidate:=all.findAll |r| { !ids.contains(r["id"]) }.dup.addAll(edits)
    edits.each |rec|
    {
      if (rec["nativeEquip"] == true)
      {
        equipStore.validate(rec,candidate)
        diffs.addAll(FinEnergyCleaningRepo(this).configure(rec))
        diffs.add(equipStore.write(rec))
        return
      }
      if (rec["pointId"] != null && rec["expressionId"] != null) throw ArgErr("物理点和表达式不能同时绑定")
      FinEnergyConfig.validateNewBinding(rec,all.find |r| { r["id"] == rec["id"] },candidate)
      FinEnergyConfig.validate(rec,candidate); validatePoint(rec)
      if (["meter","totalMeter"].contains(rec["kind"]) && rec["pointId"] != null)
      {
        point:=cx.db.readById(Ref(rec["pointId"].toStr))
        category:=candidate.find |r| { r["id"] == rec["categoryId"] }
        if (FinEnergyMath.unitFactor(point["unit"]?.toStr ?: "",category?.get("unit")?.toStr ?: "") == null) throw ArgErr("FIN 点单位与所选能源类型不兼容，请分别加入不同能源的点")
      }
      id:=rec["id"].toStr; old:=all.find |r| { r["id"] == id }
      if (old == null && rec["pointId"] != null && candidate.any |r| { r["id"] != id && r["parentId"] == rec["parentId"] && r["pointId"] == rec["pointId"] && r["canonicalId"] == null }) throw ArgErr("所选分组已经绑定该 FIN 点，请勿重复加入")
      if (old == null) diffs.add(Diff.makeAdd(encode(rec),Ref(id)))
      else { prev:=stored(id); checkMod(prev,rec["mod"]); diffs.add(Diff(prev,encode(rec,prev))) }
    }
    commit(diffs)
    return ["records":edits.map |r->[Str:Obj?]| { decode(stored(r["id"].toStr)) }]
  }

  [Str:Obj?] tree(Str action, Str id, Str? parent, Obj? mod)
  {
    mustWrite
    all := liveRecords
    if (nativeModel && action != "toggle") throw ArgErr("请使用三树归属设置；复制配置需选择已有目标设备")
    FinEnergyNativeSpace.mustEditable(id,all)
    prev := stored(id)
    checkMod(prev,mod)
    rec := decode(prev)
    if (!FinEnergyConfig.nodeKinds.contains(rec["kind"])) throw ArgErr("仅管理树节点支持此操作")
    if (action == "move" || action == "toggle")
    {
      if (action == "move") rec["parentId"] = parent
      else
      {
        if (!["meter","totalMeter"].contains(rec["kind"])) throw ArgErr("仅表计可切换总分表")
        rec["kind"] = rec["kind"] == "meter" ? "totalMeter" : "meter"
      }
      FinEnergyConfig.validate(rec, all)
      if (FinEnergyRelations.meterKinds.contains(rec["kind"])) return ["records":[save(rec)]]
      commit([Diff(prev,encode(rec,prev))])
      return ["records":[decode(stored(id))]]
    }
    if (action != "copy") throw ArgErr("无效树操作")
    selected := [rec]
    for (i:=0; i<selected.size; ++i)
    {
      nodeId := selected[i]["id"]
      FinEnergyNativeSpace.mustEditable(nodeId as Str,all)
      all.findAll |r| { r["parentId"] == nodeId }.each |r| { selected.add(r) }
      if (selected.size > 5000) throw ArgErr("复制范围过大")
    }
    if (selected.any |r| { FinEnergyRelations.meterKinds.contains(r["kind"]) }) throw ArgErr("请使用三树归属设置；复制配置需选择已有目标设备")
    ids := Str:Str[:]
    selected.each |r| { ids[r["id"].toStr] = Ref.gen.id }
    copies := [Str:Obj?][,]
    diffs := Diff[,]
    selected.each |old,i|
    {
      r := old.dup
      r.remove("mod")
      r["id"] = ids[old["id"].toStr]
      r["parentId"] = i == 0 ? parent : ids[old["parentId"].toStr]
      if (FinEnergyRelations.meterKinds.contains(r["kind"]))
      {
        r.remove("pointId"); r.remove("expressionId"); r.remove("canonicalId")
        r["includeInTotals"]=false
      }
      originalName := old["name"].toStr
      base := (originalName.size > 145 ? originalName[0..<145] : originalName) + " 副本"
      name := base
      n := 1
      while (all.any |a| { a["name"] == name } || copies.any |a| { a["name"] == name }) name = base + " " + (++n)
      r["name"] = name
      FinEnergyConfig.validate(r,all.dup.addAll(copies))
      copies.add(r)
      diffs.add(Diff.makeAdd(encode(r),Ref.fromStr(r["id"].toStr)))
    }
    commit(diffs)
    return ["records":copies.map |r->[Str:Obj?]| { decode(stored(r["id"].toStr)) }]
  }

  [Str:Obj?] points(Str query := "", Int offset := 0, Int limit := 200, Str? equipId := null)
  {
    mustRead
    return FinEnergyPointCatalog.page(cx.db,|Dict r->Bool| {cx.canRead(r)},query,offset,limit,equipId)
  }

  [Str:Obj?] resolvePoints(Str:Obj? body)
  {mustRead;return FinEnergyPointCatalog.resolve(cx.db,|Dict r->Bool| {cx.canRead(r)},body)}

  [Str:Obj?] report([Str:Obj?] input,[Str:Int]? timing := null)
  {
    started:=Duration.nowTicks
    prepared:=prepareReport(input)
    request:=(Str:Obj?)prepared["request"]; all:=([Str:Obj?][])prepared["records"]
    request=FinEnergyProfileFirst.activate(request,all)
    preparedAt:=Duration.nowTicks
    histories:=FinEnergyHistory.load(cx,request,all,null,null,timing)
    loadedAt:=Duration.nowTicks
    result:=FinEnergyHistory.report(request,all,histories)
    if(request["_profileFirst"]==true)
    {
      finishedAt:=Duration.nowTicks
      extra:=(Str:Obj?)result["extra"]
      extra["profileDelivery"]=["mode":"chart","diagnostics":"deferred","snapshotId":Uuid().toStr,"sourceCount":histories.size,
        "phaseMs":["prepare":(preparedAt-started)/1ms.ticks,"history":(loadedAt-preparedAt)/1ms.ticks,"calculate":(finishedAt-loadedAt)/1ms.ticks,"total":(finishedAt-started)/1ms.ticks]]
    }
    if (FinEnergyComparisonScope.active(request) || request["kind"] == "energyFlow")
    {
      readable:=Str:Bool[:]
      result=(Str:Obj?)FinEnergyComparisonScope.readableSources(result) |id->Bool|
      {
        if (!readable.containsKey(id))
        {
          source:=cx.db.readById(Ref(id),false)
          readable[id]=source != null && cx.canRead(source)
        }
        return readable[id]
      }
    }
    if(timing!=null)
    {
      finished:=Duration.nowTicks
      timing["prepareMs"]=(preparedAt-started)/1ms.ticks
      timing["historyMs"]=(loadedAt-preparedAt)/1ms.ticks
      timing["calculateMs"]=(finished-loadedAt)/1ms.ticks
      timing["totalMs"]=(finished-started)/1ms.ticks
    }
    return result
  }

  [Str:Obj?] cockpit([Str:Obj?] input) {cockpitScoped(input)}
  internal [Str:Obj?] cockpitScoped([Str:Obj?] input,FinEnergyCockpitRequestScope? scope := null)
  {
    mustRead
    if(scope==null) FinEnergyCockpitGate.enter(cx.proj.name,cx.user.username)
    else scope.checkContext(cx.proj.name,cx.user.username)
    started:=Duration.nowTicks
    deadline:=scope?.deadline ?: FinEnergyCockpitDeadline()
    FinEnergyCockpitSourceSession? session;Err? failure
    try
    {
      if(scope!=null) cockpitPreparation=scope.preparationWorkspace
      now:=DateTime.now
      tz:=TimeZone.fromStr(cx.proj.meta["tz"]?.toStr ?: "Shanghai")
      prepared:=prepareReport(FinEnergyCockpit.query(input,cx.proj.name,tz,now),true)
      owned:=ownedSnapshot
      owned["modelComplete"]=true;owned["modelRecords"]=prepared["scopeRecords"]
      all:=([Str:Obj?][])prepared["records"]
      if (FinEnergyMath.strings(input["modules"]).contains("balance")) all=flowRecords(all,([Str:Obj?][])prepared["sourceRecords"])
      normalized:=input.dup
      normalized["reportScope"]=((Map)input["reportScope"]).dup.set("nodeIds",((Map)prepared["request"])["nodeIds"])
      cockpitPreparation=null;cockpitAliases=null
      result:=FinEnergyCockpit.execute(normalized,all,|q,rs->[Str:Obj?][]|
      {
        if(scope==null) return FinEnergyHistory.loadPrepared(cx,q,rs)
        session=FinEnergyHistory.sourceSession(cx,q,rs,scope.stream,scope)
        return session.load
      },cx.proj.name,tz,now,cx.user.isAdmin,null,|->[Str:Obj?][]|
      {
        return FinEnergyCockpitIssues.readableEvents(FinEnergyNativeAlarms(this).list,cx.proj.name) |id->Bool|
        {source:=cx.db.readById(Ref(id),false);return source != null && cx.canRead(source)}
      },null,deadline,owned,
      scope==null ? null : |Str key,Str:Obj? q->Str:Obj?| {session.read(key,q)},
      scope==null ? null : |Str id,Str:Obj? q->Str:Obj?| {session.copData(id,q)},
      scope==null ? null : |Str id,Str:Obj? q->Str:Obj?| {session.ruleData(id,q)},scope)
      if (Duration.nowTicks-started > 30sec.ticks) throw FinEnergyHttpErr(504,"QUERY_TIMEOUT","cockpitQueryTimeout")
      return result
    }
    catch(Err e) {failure=e;throw e}
    finally
    {
      closeCockpitSource(session,failure)
      cockpitPreparation=null;cockpitAliases=null
      if(scope==null) FinEnergyCockpitGate.leave(cx.proj.name,cx.user.username)
    }
  }

  private static Void closeCockpitSource(FinEnergyCockpitSourceSession? session,Err? failure)
  {
    try {session?.close}
    catch(Err cleanup) {if(failure==null) throw cleanup;Log.get("finEnergy").err("Cockpit source cleanup failed after an earlier failure",cleanup)}
  }

  [Str:Obj?] cockpitBudgets() {mustRead;return ownedStore.list("budget").set("projectRef",cx.proj.id.id)}
  [Str:Obj?] saveCockpitBudget(Str:Obj? body) {mustWrite;return ownedStore.save("budget",body)}
  [Str:Obj?] deleteCockpitBudget(Str:Obj? body) {mustWrite;checkOwnedDelete(body);return ownedStore.remove("budget",body["id"].toStr,body["mod"])}
  [Str:Obj?] cockpitRuleProfiles() {mustRead;return ownedStore.list("rule").set("projectRef",cx.proj.id.id)}
  [Str:Obj?] saveCockpitRuleProfile(Str:Obj? body) {mustWrite;return ownedStore.save("rule",body)}
  [Str:Obj?] deleteCockpitRuleProfile(Str:Obj? body) {mustWrite;checkOwnedDelete(body);return ownedStore.remove("rule",body["id"].toStr,body["mod"])}
  [Str:Obj?] cockpitConfigAudit(Str id) {mustRead;return ownedStore.history(id)}
  private Void checkOwnedDelete(Str:Obj? b) {if(b.keys.any |k| {k != "id" && k != "mod"} || b["id"] isnot Str || b["mod"] isnot Str) throw ArgErr("cockpitConfigFields")}
  private FinEnergyCockpitConfigStore ownedStore()
  {FinEnergyCockpitConfigStore(cx.db,cx.proj.name,cx.proj.id,cx.user.username,cx.user.isAdmin,|Dict r->Bool| {cx.canRead(r)},|Dict r->Bool| {cx.canWrite(r)})}
  private Str:Obj? ownedSnapshot()
  {
    before:=FinEnergyNamespace.singleton(cx.db,"finEnergyRevision")
    store:=ownedStore;b:=store.capture("budget",cockpitPreparation);r:=store.capture("rule",cockpitPreparation)
    after:=FinEnergyNamespace.singleton(cx.db,"finEnergyRevision")
    if(before?.get("mod") != after?.get("mod")) throw FinEnergyHttpErr(409,"CONFLICT","cockpitConfigConflict")
    return ["projectRef":cx.proj.id.id,"budgets":b["records"],"budgetsComplete":b["complete"],"budgetAttribution":b["attribution"],"rules":r["records"],"rulesComplete":r["complete"],"ruleAttribution":r["attribution"]]
  }

  ** Existing report and cockpit share native mapping and configuration preparation.
  private [Str:Obj?] prepareReport([Str:Obj?] input, Bool cockpit := false)
  {
    mustRead
    requireLicensedCalculation
    request := input.dup
    request.remove("_profileFirst")
    request.remove("_cockpitDiagnosticCapture")
    if(!cockpit) request.remove("_cockpitExactMeterSet")
    now:=DateTime.now
    cutoff:=input["asOf"] == null ? now : FinEnergyKnownUsage.cutoff(input)
    request["asOf"]=(cutoff < now ? cutoff : now.toTimeZone(cutoff.tz)).toIso
    request["tz"] = cx.proj.meta["tz"] ?: "Shanghai"
    FinEnergyForecast.validate(request)
    request.remove("legacyMembership")
    request.remove("meterHistorySegments")
    request.remove("leakSegment")
    request.remove("_comparisonScope")
    if (nativeModel) request=FinEnergyNativeEquip.request(request,FinEnergyNativeEquipRepo(this).mapping)
    all:=[Str:Obj?][,];scopeRecords:=[Str:Obj?][,];sourceRecords:=[Str:Obj?][,]
    if (cockpit)
    {
      source:=FinEnergyNativeEquipRepo(this).records(rawRecords(false,true,true));sourceRecords=source
      all=FinEnergyNativeSpace.loadAnalysis(cx,source,cockpitPreparation).project(FinEnergyCockpitEfficiency.visible(source.findAll |r| {r["_comparisonReadable"] != false},source))
      FinEnergyCockpit.guardVisibleScope(request,all,source)
      // Private completeness proof; never serialized. Preserve hidden/unplaced
      // members so a readable subset cannot masquerade as a project budget.
      cockpitPreparation?.hold(4+source.size+all.size)
      index:=Str:[Str:Obj?][:];source.each |r| {index[r["id"].toStr]=r};all.each |r| {index[r["id"].toStr]=r}
      scopeRecords=index.vals.map |r->[Str:Obj?]|
      {
        cockpitPreparation?.hold(3+r.size)
        out:=r.dup;pointId:=r["pointId"] as Str
        if(pointId != null) {point:=cx.db.readById(Ref(pointId),false);if(point == null || !cx.canRead(point)) out["_comparisonPointReadable"]=false}
        return out
      }
    }
    else all=input["perArea"] == true || ((input["dimension"] == "space" || input["scopeDimension"] == "space") && input["spaceSource"] == "fin") ? liveRecords : records
    all=FinEnergyNativeEquipRepo(this).validateRead(all)
    if (request["kind"] == "energyFlow") all=flowRecords(all)
    if (FinEnergyComparisonScope.active(request)) request["_comparisonScope"]=comparisonScope(request,all)
    request=FinEnergyEngine.flowScope(request,all)
    return ["request":request,"records":all,"scopeRecords":scopeRecords,"sourceRecords":sourceRecords]
  }

  private [Str:Obj?][] flowRecords([Str:Obj?][] visible,[Str:Obj?][]? captured := null)
  {
    all:=captured ?: FinEnergyNativeEquipRepo(this).records(rawRecords(false,true))
    out:=FinEnergyEnergyFlow.visible(visible,all)
    out.each |r|
    {
      ["pointId"].each |key|
      {
        id:=r[key] as Str
        if (id == null) return
        point:=cx.db.readById(Ref(id),false)
        if (point == null || !cx.canRead(point)) r["_comparisonPointReadable"]=false
      }
    }
    return out
  }

  ** Preview is read-only. The report resolves and checks this scope again.
  [Str:Obj?] comparisonScopes(Str nodeIds)
  {
    mustRead
    Str[] ids:=nodeIds.split(',').map |id->Str| {id.trim}
    ids=ids.findAll |id| {!id.isEmpty}.unique
    if (ids.isEmpty || ids.size > 200) throw ArgErr("comparisonMasterRequired")
    req:=Str:Obj?["kind":"leak","comparisonBasis":"physicalBoundary","nodeIds":ids]
    if (nativeModel) req=FinEnergyNativeEquip.request(req,FinEnergyNativeEquipRepo(this).mapping)
    return ["scopes":comparisonScope(req).snapshots]
  }

  private FinEnergyComparisonScope comparisonScope(Str:Obj? request,[Str:Obj?][] visible := [Str:Obj?][,])
  {
    // Resolve hidden boundaries internally, returning only an opaque limitation.
    // Neither preview nor report may silently treat an unreadable child as absent.
    all:=FinEnergyNativeEquipRepo(this).records(rawRecords(false,true))
    points:=Str:Bool[:]
    all.each |r|
    {
      if (r["_comparisonReadable"] == false) return
      ["pointId"].each |key|
      {
        id:=r[key] as Str
        if (id == null) return
        if (!points.containsKey(id))
        {
          source:=cx.db.readById(Ref(id),false)
          points[id]=source != null && cx.canRead(source)
        }
        if (points[id] == false) r["_comparisonPointReadable"]=false
      }
      target:=visible.find |v| {v["id"] == r["id"]}
      if (target != null && r["_comparisonPointReadable"] == false) target["_comparisonPointReadable"]=false
    }
    return FinEnergyComparisonScope(request,all)
  }

  [Str:Obj?] treeView(Str dimension)
  {
    mustRead
    if (!FinEnergyRelations.dimensions.contains(dimension)) throw ArgErr("无效的树维度")
    all:=dimension == "space" ? liveRecords : records
    containerKind:=dimension == "metering" ? "category" : dimension
    return ["dimension":dimension,"spaceSource":dimension == "space" ? "fin" : null,"records":dimension == "legacy" ? all.findAll |r| { ["group","meter","totalMeter","sensor"].contains(r["kind"]) } : all.findAll |r| { r["canonicalId"] == null && (r["kind"] == containerKind || (dimension == "space" && r["kind"] == "nativePoint") || FinEnergyRelations.meterKinds.contains(r["kind"])) }]
  }

  ** Preview, atomic apply and guarded rollback modify FinEnergy configuration only.
  [Str:Obj?] migration([Str:Obj?] input)
  {
    mustWrite
    if (input["target"] != "threeTree") return FinEnergyNativeEquipRepo(this).migrate(input)
    all:=records
    action:=input["action"] as Str ?: "preview"
    if (action == "rollback") return rollbackMigration(input,all)
    sources:=migrationSources(all)
    plan:=FinEnergyMigration.plan(all,sources)
    plan["revision"]=iso(revision?.get("mod")) ?: ""
    plan["sourceRevision"]=JsonOutStream.writeJsonToStr(sources).hash.toHex
    if (action == "preview")
    {
      if (input["summary"] == true)
      {
        compact:=plan.dup
        compact["records"]=FinEnergyMath.maps(plan["records"]).map |r->[Str:Obj?]| { ["id":r["id"],"kind":r["kind"],"name":r["name"]] }
        compact["suggestions"]=FinEnergyMath.maps(plan["suggestions"]).map |s->[Str:Obj?]|
        {
          item:=s.dup; item.remove("records"); item.remove("patches"); return item
        }
        return compact
      }
      return plan
    }
    if (action != "apply") throw ArgErr("无效迁移操作")
    if (input["revision"] != plan["revision"] || input["sourceRevision"] != plan["sourceRevision"]) throw FinEnergyHttpErr(409,"CONFLICT","配置或 FIN 来源已变化，请重新预览")
    accepted:=FinEnergyMath.strings(input["acceptedSuggestionIds"])
    suggestions:=FinEnergyMath.maps(plan["suggestions"])
    if (accepted.any |id| { !suggestions.any |s| { s["id"] == id } }) throw ArgErr("迁移建议不存在，请重新预览")
    edits:=Str:[Str:Obj?][:]
    FinEnergyMath.maps(plan["records"]).each |r| { edits[r["id"].toStr]=r.dup }
    suggestions.findAll |s| { accepted.contains(s["id"]) }.each |s|
    {
      FinEnergyMath.maps(s["records"]).each |r|
      {
        id:=r["id"].toStr
        if (!all.any |a| { a["id"] == id } && !edits.containsKey(id)) edits[id]=r.dup
      }
      FinEnergyMath.maps(s["patches"]).each |p|
      {
        id:=p["id"].toStr
        r:=edits[id]
        if (r == null) r=all.find |a| { a["id"] == id }
        if (r == null) throw ArgErr("建议引用对象不存在")
        r=r.dup
        p.each |val,key| { if (key != "id") { if (val == null) r.remove(key); else r[key]=val } }
        edits[id]=r
      }
    }
    Map placements:=(input["placements"] as Map) ?: Str:Obj?[:]
    positioned:=Str:Str[:]
    placements.each |target,key|
    {
      suggestion:=suggestions.find |s| { s["id"] == key && s["placementRequired"] == true }
      if (suggestion == null) throw ArgErr("空间归属建议不存在")
      targetId:=target as Str ?: throw ArgErr("请选择空间")
      space:=edits[targetId] ?: all.find |r| { r["id"] == targetId }
      if (space == null || space["kind"] != "space") throw ArgErr("目标空间不存在")
      FinEnergyMath.strings(suggestion["recordIds"]).each |meterId|
      {
        if (positioned.containsKey(meterId) && positioned[meterId] != targetId) throw ArgErr("空间建议范围重叠，请为同一表计选择一致的空间")
        positioned[meterId]=targetId
        meter:=edits[meterId]
        if (meter == null) meter=all.find |r| { r["id"] == meterId }
        if (meter == null || !FinEnergyRelations.meterKinds.contains(meter["kind"])) throw ArgErr("空间建议中的表计不存在")
        copy:=meter.dup; copy["spaceId"]=targetId; edits[meterId]=copy
      }
    }
    selected:=edits.vals.findAll |r|
    {
      old:=all.find |a| { a["id"] == r["id"] }
      return old == null || business(old) != business(r)
    }
    if (selected.isEmpty) return ["applied":0,"job":null]
    if (selected.size > 5000) throw ArgErr("迁移范围超过5000条，请缩小范围")
    changedIds:=selected.map |r->Str| { r["id"].toStr }
    candidate:=all.findAll |r| { !changedIds.contains(r["id"]) }.dup.addAll(selected)
    diffs:=Diff[,]
    before:=[Str:Obj?][,]
    selected.each |r|
    {
      old:=all.find |a| { a["id"] == r["id"] }
      FinEnergyConfig.validate(r,candidate); validatePoint(r)
      if (old == null) diffs.add(Diff.makeAdd(encode(r),addId(r["id"].toStr,cx.proj.name)))
      else { prev:=stored(r["id"].toStr); checkMod(prev,r["mod"]); before.add(old); diffs.add(Diff(prev,encode(r,prev))) }
    }
    key:=DateTime.nowTicks.toStr
    job:=Str:Obj?["id":Ref.gen.id,"kind":"job","name":"三树配置迁移","action":"treeMigration","status":"applied","enabled":false,"migrationKey":key,"processed":selected.size,"lastRun":DateTime.now.toIso]
    for (start:=0;start<selected.size;start+=8)
    {
      chunk:=selected[start..<((start+8).min(selected.size))]
      chunkIds:=chunk.map |r->Str| { r["id"].toStr }
      snapshot:=Str:Obj?["kind":"job","name":"三树迁移快照 "+key+" "+start,"action":"treeMigrationSnapshot","status":"retained","enabled":false,"migrationKey":key,"before":before.findAll |r| { chunkIds.contains(r["id"]) },"after":chunk]
      diffs.add(Diff.makeAdd(encode(snapshot)))
    }
    diffs.add(Diff.makeAdd(encode(job),Ref(job["id"].toStr)))
    commit(diffs)
    return ["applied":selected.size,"job":decode(stored(job["id"].toStr))]
  }

  private [Str:Obj?] rollbackMigration([Str:Obj?] input, [Str:Obj?][] all)
  {
    id:=input["jobId"] as Str ?: throw ArgErr("缺少迁移记录")
    prev:=stored(id); checkMod(prev,input["mod"])
    job:=decode(prev)
    if (job["action"] != "treeMigration" || job["status"] != "applied") throw ArgErr("此迁移不可回滚")
    snapshots:=all.findAll |r| { r["action"] == "treeMigrationSnapshot" && r["migrationKey"] == job["migrationKey"] }
    after:=[Str:Obj?][,]; before:=[Str:Obj?][,]
    snapshots.each |s| { after.addAll(FinEnergyMath.maps(s["after"])); before.addAll(FinEnergyMath.maps(s["before"])) }
    if (after.isEmpty) throw ArgErr("迁移快照不完整")
    after.each |r|
    {
      current:=all.find |a| { a["id"] == r["id"] }
      if (current == null || business(current) != business(r)) throw FinEnergyHttpErr(409,"CONFLICT","迁移后配置已被修改，不能自动回滚")
    }
    ids:=after.map |r->Str| { r["id"].toStr }
    candidate:=all.findAll |r| { !ids.contains(r["id"]) }.dup.addAll(before)
    removed:=ids.findAll |key| { !before.any |r| { r["id"] == key } }
    removed.each |key| {if(ownedStore.referencesId(key)) throw FinEnergyHttpErr(409,"CONFLICT","cockpitConfigReferenced");FinEnergyConfig.canDelete(key,candidate)}
    candidate.findAll |r| { !["job","alarm"].contains(r["kind"]) }.each |r| { FinEnergyConfig.validate(r,candidate) }
    diffs:=after.map |r->Diff|
    {
      original:=before.find |a| { a["id"] == r["id"] }
      current:=stored(r["id"].toStr)
      return original == null ? Diff(current,null,Diff.remove) : Diff(current,encode(original,current))
    }
    job["status"]="rolledBack"; job["lastRun"]=DateTime.now.toIso
    diffs.add(Diff(prev,encode(job,prev)))
    commit(diffs)
    return ["rolledBack":after.size,"job":decode(stored(id))]
  }

  private static [Str:Obj?] business([Str:Obj?] record)
  { copy:=record.dup; copy.remove("mod"); return copy }

  ** Folio additions take local IDs; preview, snapshots and references stay qualified.
  internal static Ref addId(Str id, Str project)
  {
    prefix:="p:"+project+":r:"
    key:=id.startsWith(prefix) ? id[prefix.size..-1] : id
    if (key.contains(":")) throw ArgErr("新增配置不能使用其他项目的记录标识")
    return Ref(key)
  }

  private [Str:Obj?][] migrationSources([Str:Obj?][] all)
  {
    out:=[Str:Obj?][,]
    cx.db.readAllList(Filter.has("site")).findAll |site| { cx.canRead(site) }.sort |a,b| { a.id.id <=> b.id.id }.each |site|
    {
      out.add(["id":site.id.id,"siteRef":site.id.id,"siteName":site.dis])
    }
    all.findAll |r| { FinEnergyRelations.meterKinds.contains(r["kind"]) && r["pointId"] != null }.map |r->Str| { r["pointId"].toStr }.unique.sort.each |Str id|
    {
      point:=cx.db.readById(Ref(id),false)
      if (point == null || !cx.canRead(point)) return
      equip:=cx.db.readById(point["equipRef"] as Ref ?: Ref("finEnergy-no-equip"),false)
      source:=Str:Obj?["id":id,"pointId":id]
      ["site","floor","equip"].each |part|
      {
        ref:=point[part+"Ref"] as Ref
        if (ref == null) ref=equip?.get(part+"Ref") as Ref
        if (ref == null) return
        rec:=cx.db.readById(ref,false)
        if (rec != null && cx.canRead(rec)) { source[part+"Ref"]=ref.id; source[part+"Name"]=rec.dis }
      }
      upstream:=point["submeterOf"] ?: equip?.get("submeterOf")
      if (upstream is Ref) source["submeterOf"]=((Ref)upstream).id
      else if (upstream is List) source["submeterOf"]=((List)upstream).findAll |v| { v is Ref }.map |v->Str| { ((Ref)v).id }
      out.add(source)
    }
    return out
  }

  [Str:Obj?] acknowledge(Str id, Obj? mod, Str note)
  {
    mustWrite
    r := decode(stored(id))
    if (r["kind"] != "alarm") throw ArgErr("记录不是报警")
    checkMod(stored(id),mod)
    if (r["nativeAlarmId"] != null || r["state"] != "acknowledged")
    {
      r=FinEnergyNativeAlarms(this).acknowledge(r,note.size > 2000 ? note[0..<2000] : note)
      return save(r,true)
    }
    return r
  }

  [Str:Obj?][] alarms() { mustRead; return FinEnergyNativeAlarms(this).list }
  Str:Obj? alarmPage(Int offset,Int limit,Str state,Str? target) {mustRead;return FinEnergyNativeAlarms(this).page(offset,limit,state,target)}
  Str:Obj? alarmDetail(Str id) {mustRead;return FinEnergyNativeAlarms(this).detail(id)}

  [Str:Obj?] changeMessages(Int offset:=0, Int limit:=30)
  {
    mustRead
    return FinEnergyChangeMessages.page(cx.db,|Dict r->Bool| { cx.canRead(r) },cx.user.isAdmin,offset,limit)
  }

  private Void validatePoint([Str:Obj?] rec)
  {
    point := rec["pointId"] as Str
    if (point == null || point.isEmpty)
    {
      if (["meter","totalMeter"].contains(rec["kind"])) throw ArgErr("所有表计必须指定主能耗点，缺测不会由归档或公式替代")
      return
    }
    r := cx.db.readById(Ref.fromStr(point),false)
    if (r == null || !r.has("point") || r.has("finEnergyComputed")) throw ArgErr("请选择当前 FIN 项目的原始点位")
    if (!cx.canRead(r)) throw FinEnergyHttpErr(403,"PERMISSION","当前 FIN 用户没有该点位的读取权限")
    if (!r.has("his")) throw ArgErr("点位尚未启用 FIN 历史记录")
    if (rec["autoSum"] == true && FinEnergyMeterRollup.collected(r)) throw ArgErr("有采集源的实测点不能按分表覆盖当前值")
  }

  internal Void commit(Diff[] changes, Bool event := false)
  {
    FinEnergyHistorySafety.metadata(cx.db,changes)
    guardConfiguration:=!event || FinEnergyEditionLicense.requiresRevision(cx,changes)
    if (guardConfiguration)
    {
      readRevision
      FinEnergyEditionLicense.checkWrite(cx,changes)
      FinEnergyCleaningRepo(this).validateSaves(changes)
      changes.addAll(FinEnergyMeterTimeline.capture(cx.db,changes,DateTime.now,cx.user.username))
      // A shared optimistic revision serializes uniqueness/cycle checks across requests.
      key := Ref("finEnergy-config-revision")
      prior := revision
      tags := Etc.makeDict(["finEnergyRevision":Number(DateTime.nowTicks),"finEnergyUpdatedBy":cx.user.username])
      changes.add(prior == null ? Diff.makeAdd(tags,key) : Diff(prior,tags))
    }
    try { cx.db.commitAll(changes) }
    catch (Err e)
    {
      if (["ConcurrentChangeErr","DuplicateRecErr"].contains(e.typeof.name)) throw FinEnergyHttpErr(409,"CONFLICT","配置已被修改，请刷新后重试")
      throw e
    }
    revisionRead = false
  }

  internal static Void checkMod(Dict previous, Obj? mod)
  {
    if (mod == null || iso(previous["mod"]) != mod.toStr) throw FinEnergyHttpErr(409,"CONFLICT","配置已被修改，请刷新后重试")
  }

  internal Dict encode([Str:Obj?] rec, Dict? old := null)
  {
    if (old?.has("equip") == true) return FinEnergyNativeEquip.tags(rec,old,cx.user.username)
    data := FinEnergyNativeSpace.clean(rec)
    data.remove("id"); data.remove("mod")
    tags := Str:Obj?["finEnergy":Marker.val,"finEnergyKind":rec["kind"],"dis":rec["name"],"finEnergyUpdatedBy":cx.user.username,"finEnergyUpdatedAt":DateTime.now]
    refTags.each |tag,key|
    {
      val := data.remove(key) as Str
      if (val != null && !val.isEmpty) tags[tag] = Ref.fromStr(val)
      else if (old?.has(tag) == true) tags[tag] = Remove.val
    }
    // Persist expression and template dependencies as equipStore Folio Ref lists too.
    refs := Ref[,]
    vars := data["variables"] as Map
    if (vars != null) vars.each |v| { refs.add(Ref.fromStr(v.toStr)) }
    template := data["request"] as Map
    if (template != null)
    {
      ["nodeIds","referenceIds"].each |key|
      {
        values := template[key] as List
        if (values != null) values.each |v| { refs.add(Ref.fromStr(v.toStr)) }
      }
      ["xId","yId","baselineId","categoryId"].each |key| { if (template[key] != null) refs.add(Ref.fromStr(template[key].toStr)) }
    }
    if (!refs.isEmpty) tags["finEnergyDependencyRefs"] = refs.unique
    else if (old?.has("finEnergyDependencyRefs") == true) tags["finEnergyDependencyRefs"] = Remove.val
    json := JsonOutStream.writeJsonToStr(data)
    if (json.size > 30000) throw ArgErr("单条配置超过30000字符，请缩小模板或规则范围")
    tags["finEnergyConfig"] = json
    return Etc.makeDict(tags)
  }

  static [Str:Obj?] decode(Dict rec)
  {
    if (rec.has("equip")) return FinEnergyNativeEquip.decode(rec)
    data := (Str:Obj?)JsonInStream((rec["finEnergyConfig"] as Str ?: "{}").in).readJson
    refTags.each |tag,key| { if (rec[tag] is Ref) data[key] = ((Ref)rec[tag]).id }
    data["id"] = rec.id.id
    data["mod"] = iso(rec["mod"])
    data["kind"] = rec["finEnergyKind"]
    data["name"] = rec.dis
    return data
  }

  internal static Str:Obj? decodeOwned(Dict rec,FinEnergyPreparedOwner owner)
  {
    if(rec.has("equip"))
    {
      owner.hold(11+refTags.size+FinEnergyNativeEquip.scalars.size);Map? result
      owner.watch |->Void| {result?.clear;result=null}
      result=FinEnergyNativeEquip.decode(rec);return result
    }
    data:=(Str:Obj?)FinEnergyOwnedJson.parse(rec["finEnergyConfig"] as Str ?: "{}",owner)
    owner.hold(refTags.size+4)
    refTags.each |tag,key| {if(rec[tag] is Ref) data[key]=((Ref)rec[tag]).id}
    data["id"]=rec.id.id;data["mod"]=iso(rec["mod"]);data["kind"]=rec["finEnergyKind"];data["name"]=rec.dis
    return data
  }

  static Str? iso(Obj? v) { v is DateTime ? ((DateTime)v).toIso : v?.toStr }
}

const class FinEnergyHttpErr : Err
{
  const Int status
  const Str code
  new make(Int status, Str code, Str msg) : super(msg) { this.status=status; this.code=code }
}

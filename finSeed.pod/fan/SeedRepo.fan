using util
using haystack
using folio
using skyarcd

** FIN identity and Folio storage. No business state is stored outside the project.
class SeedRepo
{
  Context cx
  private Bool revisionRead := false
  private Dict? revision
  new make(Context cx) { this.cx = cx }

  static const [Str:Str] refTags := ["parentId":"seedParentRef", "pointId":"seedPointRef", "categoryId":"seedCategoryRef", "subcategoryId":"seedSubcategoryRef", "utilityId":"seedUtilityRef", "tariffId":"seedTariffRef", "expressionId":"seedExpressionRef", "numeratorId":"seedNumeratorRef", "denominatorId":"seedDenominatorRef", "nodeId":"seedNodeRef", "spaceId":"seedSpaceRef", "meterParentId":"seedMeterParentRef", "organizationId":"seedOrganizationRef", "canonicalId":"seedCanonicalRef"]

  Void mustRead()
  {
    if (cx.user.isGuest) throw SeedHttpErr(401, "SESSION", "FIN 会话已失效，请重新登录")
  }

  Void mustWrite()
  {
    mustRead
    if (!cx.user.isAdmin) throw SeedHttpErr(403, "PERMISSION", "当前 FIN 用户没有配置写入权限")
  }

  [Str:Obj?][] records()
  { SeedNativeEquipRepo(this).records(rawRecords) }

  [Str:Obj?][] rawRecords(Bool recovery := false)
  {
    mustRead
    if (!revisionRead)
    {
      revision = cx.db.readById(Ref("finseed-config-revision"),false)
      revisionRead = true
    }
    return cx.db.readAllList(Filter.has("seedKind").and(Filter.has("seed").or(Filter.has("equip")))).findAll |r|
    {
      if (!cx.canRead(r)) return false
      // Recovery bodies are not application data. Avoid parsing every archived
      // snapshot on every report/catalog read; rollback opts in explicitly.
      return recovery || !(r["seedConfig"] as Str ?: "").contains("\"action\":\"nativeEquipSnapshot\"")
    }.map |r->[Str:Obj?]| { decode(r) }
  }

  [Str:Obj?] catalog()
  {
    all:=records
    source:=SeedNativeSpace.load(cx)
    projected:=source.project(all)
    info:=source.info(all)
    if (nativeModel) projected=SeedNativeEquipRepo(this).validateRead(projected)
    return ["version":SeedRepo#.pod.version.toStr, "project":cx.proj.name, "user":["name":cx.user.username,"canWrite":cx.user.isAdmin], "storageModel":nativeModel ? "nativeEquip" : "legacy", "spaceSource":"fin", "nativeTreePath":source.path, "nativeTreeWarnings":info["warnings"], "records":projected]
  }

  Bool nativeModel() { SeedNativeEquipRepo(this).active }

  [Str:Obj?][] liveRecords() { SeedNativeSpace.load(cx).project(records) }

  [Str:Obj?] nativeSpaceInfo() { mustRead; return SeedNativeSpace.load(cx).info(records) }

  Dict stored(Str id)
  {
    mustRead
    r := cx.db.readById(Ref.fromStr(id), false)
    if (r == null || !r.has("seed") || !r.has("seedKind")) throw SeedHttpErr(404,"NOT_FOUND","配置记录不存在")
    if (!cx.canRead(r)) throw SeedHttpErr(403,"PERMISSION","当前 FIN 用户没有此记录的读取权限")
    return r
  }

  [Str:Obj?] save([Str:Obj?] input, Bool systemWrite := false)
  {
    mustWrite
    all := liveRecords
    if (nativeModel && input["kind"] == "group") throw ArgErr("旧分析分组仅供历史报告读取，不再维护")
    if (nativeModel && SeedRelations.meterKinds.contains(input["kind"]))
    {
      equipStore:=SeedNativeEquipRepo(this)
      if (input["id"] == null && input["createVirtual"] == true) return equipStore.createVirtual(input)
      rec:=equipStore.prepare(input)
      equipStore.validate(rec,all.findAll |r| { r["id"] != rec["id"] }.dup.add(rec))
      commit([equipStore.write(rec)])
      return decode(stored(rec["id"].toStr))
    }
    SeedNativeSpace.mustEditable(input["id"] as Str,all)
    rec := SeedNativeSpace.clean(input)
    kind := rec["kind"] as Str ?: ""
    if (!systemWrite && ["job","alarm"].contains(kind)) throw ArgErr("任务和报警只能由业务操作产生")
    id := rec["id"] as Str
    Dict? previous := id == null ? null : stored(id)
    if (previous != null)
    {
      checkMod(previous, rec["mod"])
      if (previous["seedKind"] != kind && !(["meter","totalMeter"].contains(previous["seedKind"]) && ["meter","totalMeter"].contains(kind))) throw ArgErr("记录类型不可直接更改，请使用总表/分表切换")
    }
    if (previous == null) rec["id"] = Ref.gen.id
    if (rec["expressionId"] != null && rec["pointId"] != null) throw ArgErr("物理点和表达式不能同时绑定")
    if (rec["expressionId"] != null && !rec.containsKey("includeInTotals")) rec["includeInTotals"] = false
    SeedNativeSpace.placeBinding(rec,previous == null ? null : decode(previous),all)
    SeedConfig.validateNewBinding(rec,previous == null ? null : decode(previous),all)
    SeedConfig.validate(rec, all)
    validatePoint(rec)
    diff := previous == null ? Diff.makeAdd(encode(rec), Ref.fromStr(rec["id"].toStr)) : Diff(previous, encode(rec,previous))
    commit([diff], kind == "job" || kind == "alarm")
    return decode(stored(rec["id"].toStr))
  }

  [Str:Obj?] remove(Str id, Obj? mod)
  {
    mustWrite
    all:=liveRecords
    SeedNativeSpace.mustEditable(id,all)
    prev := stored(id)
    checkMod(prev,mod)
    if (nativeModel && prev["seedKind"] == "group") throw ArgErr("旧分组供历史报表兼容使用，不可删除")
    if (["job","alarm"].contains(prev["seedKind"])) throw ArgErr("任务和报警记录应保留以供追溯")
    SeedConfig.canDelete(id, prev.has("equip") ? all.findAll |r| { r["kind"] != "nativePoint" && r["nativeReadonly"] != true } : all)
    commit([prev.has("equip") ? Diff(prev,SeedNativeEquip.clear(prev)) : Diff(prev,null,Diff.remove)])
    return ["deleted":id]
  }

  ** Atomic engineering operations. A deletion requires an unchanged preview revision.
  [Str:Obj?] manage([Str:Obj?] input)
  {
    mustWrite
    action:=input["action"] as Str ?: ""
    all:=liveRecords
    if (action == "save") return saveBatch(SeedMath.maps(input["records"]),all)
    items:=SeedMath.maps(input["items"])
    ids:=items.map |r->Str| { r["id"]?.toStr ?: "" }
    ids.each |id| { SeedNativeSpace.mustEditable(id,all) }
    SeedTreePlan.roots(all,ids)
    items.each |r| { checkMod(stored(r["id"].toStr),r["mod"]) }
    dimension:=input["dimension"] as Str ?: "legacy"
    if (!SeedRelations.dimensions.contains(dimension)) throw ArgErr("无效的树维度")
    if (action == "assign")
    {
      patch:=input["patch"] as Map ?: throw ArgErr("缺少批量归属设置")
      allowed:=["spaceId","meterParentId","organizationId","utilityId","categoryId","includeInTotals"]
      if (patch.isEmpty || patch.keys.any |key| { !allowed.contains(key) }) throw ArgErr("批量归属字段无效")
      edits:=ids.map |id->[Str:Obj?]|
      {
        r:=all.find |r| { r["id"] == id }.dup
        if (!SeedRelations.meterKinds.contains(r["kind"]) || r["canonicalId"] != null) throw ArgErr("请选择计量主档案")
        patch.each |val,key| { if (val == null) r.remove(key); else r[key]=val }
        return r
      }
      return saveBatch(edits,all)
    }
    if (action == "move" && dimension != "legacy") return saveBatch(SeedRelations.move(all,ids,input["parentId"] as Str,dimension),all)
    if (action == "copy" && dimension != "legacy")
    {
      if (items.size != 1) throw ArgErr("每次复制一个对象")
      old:=all.find |r| { r["id"] == ids.first }
      if (nativeModel)
      {
        target:=SeedNativeEquipRepo(this).equipment(input["targetId"] as Str ?: throw ArgErr("请选择已有目标设备"))
        if (target.has("seedKind")) throw ArgErr("目标设备已经纳入能源分析")
        copy:=old.dup; copy["id"]=target.id.id; copy["mod"]=input["targetMod"]; copy["name"]=target.dis
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
      deleteScope:=nativeModel ? all.findAll |r| { r["kind"] != "nativePoint" && r["nativeReadonly"] != true } : all
      plan:=SeedTreePlan.deletion(deleteScope,ids)
      selected:=SeedMath.maps(plan["records"])
      selected.each |r| { SeedNativeSpace.mustEditable(r["id"] as Str,all) }
      rev:=iso(revision?.get("mod")) ?: ""
      if (action == "previewDelete")
      {
        plan["revision"]=rev
        plan["records"]=selected.map |r->[Str:Obj?]| { ["id":r["id"],"kind":r["kind"],"name":r["name"]] }
        return plan
      }
      if (input["revision"] != rev) throw SeedHttpErr(409,"CONFLICT","配置已变化，请重新查看删除预览")
      if (!((List)plan["blockers"]).isEmpty) throw ArgErr("仍被模板、公式或其他配置引用，请先解除预览中列出的关联")
      diffs:=selected.map |r->Diff| { prev:=stored(r["id"].toStr); checkMod(prev,r["mod"]); return prev.has("equip") ? Diff(prev,SeedNativeEquip.clear(prev)) : Diff(prev,null,Diff.remove) }
      commit(diffs)
      return ["deleted":selected.map |r->Str| { r["id"].toStr }]
    }
    edits:=[Str:Obj?][,]
    if (action == "move") edits=SeedTreePlan.move(all,ids,input["parentId"] as Str)
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
    if (nativeModel && input.any |r| { SeedRelations.meterKinds.contains(r["kind"]) })
    {
      if (input.any |r| { !SeedRelations.meterKinds.contains(r["kind"]) }) throw ArgErr("设备配置请与其他配置分别保存")
      equipStore:=SeedNativeEquipRepo(this)
      [Str:Obj?][] edits:=input.map |r->[Str:Obj?]| { equipStore.prepare(r) }
      ids:=edits.map |r->Str| { r["id"].toStr }
      if (ids.unique.size != ids.size) throw ArgErr("每台 FIN 设备只允许一个主能耗点，请明确选择")
      candidate:=all.findAll |r| { !ids.contains(r["id"]) }.dup.addAll(edits)
      edits.each |[Str:Obj?] r| { equipStore.validate(r,candidate) }
      commit(edits.map |r->Diff| { equipStore.write(r) })
      return ["records":ids.map |id->[Str:Obj?]| { decode(stored(id)) }]
    }
    edits:=[Str:Obj?][,]; diffs:=Diff[,]; ids:=Str[,]
    input.each |data|
    {
      SeedNativeSpace.mustEditable(data["id"] as Str,all)
      rec:=SeedNativeSpace.clean(data)
      if (!SeedConfig.nodeKinds.contains(rec["kind"])) throw ArgErr("批量操作只支持计量树对象")
      id:=rec["id"] as Str
      if (id != null)
      {
        prev:=stored(id); checkMod(prev,rec["mod"])
        if (prev["seedKind"] != rec["kind"]) throw ArgErr("批量操作不可更改对象类型")
      }
      else rec["id"]=Ref.gen.id
      id=rec["id"].toStr
      if (ids.contains(id)) throw ArgErr("同一批次包含重复对象")
      SeedNativeSpace.placeBinding(rec,all.find |r| { r["id"] == id },all)
      ids.add(id); edits.add(rec)
    }
    candidate:=all.findAll |r| { !ids.contains(r["id"]) }.dup.addAll(edits)
    edits.each |rec|
    {
      if (rec["pointId"] != null && rec["expressionId"] != null) throw ArgErr("物理点和表达式不能同时绑定")
      SeedConfig.validateNewBinding(rec,all.find |r| { r["id"] == rec["id"] },candidate)
      SeedConfig.validate(rec,candidate); validatePoint(rec)
      if (["meter","totalMeter"].contains(rec["kind"]) && rec["pointId"] != null)
      {
        point:=cx.db.readById(Ref(rec["pointId"].toStr))
        category:=candidate.find |r| { r["id"] == rec["categoryId"] }
        if (SeedMath.unitFactor(point["unit"]?.toStr ?: "",category?.get("unit")?.toStr ?: "") == null) throw ArgErr("FIN 点单位与所选能源类型不兼容，请分别加入不同能源的点")
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
    SeedNativeSpace.mustEditable(id,all)
    prev := stored(id)
    checkMod(prev,mod)
    rec := decode(prev)
    if (!SeedConfig.nodeKinds.contains(rec["kind"])) throw ArgErr("仅管理树节点支持此操作")
    if (action == "move" || action == "toggle")
    {
      if (action == "move") rec["parentId"] = parent
      else
      {
        if (!["meter","totalMeter"].contains(rec["kind"])) throw ArgErr("仅表计可切换总分表")
        rec["kind"] = rec["kind"] == "meter" ? "totalMeter" : "meter"
      }
      SeedConfig.validate(rec, all)
      if (nativeModel && prev.has("equip")) return ["records":[save(rec)]]
      commit([Diff(prev,encode(rec,prev))])
      return ["records":[decode(stored(id))]]
    }
    if (action != "copy") throw ArgErr("无效树操作")
    selected := [rec]
    for (i:=0; i<selected.size; ++i)
    {
      nodeId := selected[i]["id"]
      SeedNativeSpace.mustEditable(nodeId as Str,all)
      all.findAll |r| { r["parentId"] == nodeId }.each |r| { selected.add(r) }
      if (selected.size > 5000) throw ArgErr("复制范围过大")
    }
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
      if (SeedRelations.meterKinds.contains(r["kind"]))
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
      SeedConfig.validate(r,all.dup.addAll(copies))
      copies.add(r)
      diffs.add(Diff.makeAdd(encode(r),Ref.fromStr(r["id"].toStr)))
    }
    commit(diffs)
    return ["records":copies.map |r->[Str:Obj?]| { decode(stored(r["id"].toStr)) }]
  }

  [Str:Obj?] points(Str query := "", Int offset := 0, Int limit := 200)
  {
    mustRead
    if (offset < 0 || limit < 1 || limit > 500) throw ArgErr("分页范围无效")
    q := query.lower
    list := cx.db.readAllList(Filter.has("point")).findAll |r| { cx.canRead(r) && !r.has("seedComputed") && (q.isEmpty || r.dis.lower.contains(q) || r.id.id.lower.contains(q)) }
    end := (offset+limit).min(list.size)
    items := [Str:Obj?][,]
    if (offset < end) list[offset..<end].each |r|
    {
      equip:=r["equipRef"] as Ref
      eq:=equip == null ? null : cx.db.readById(equip,false)
      if (eq != null && !cx.canRead(eq)) eq=null
      floor:=(r["floorRef"] as Ref) ?: (eq?.get("floorRef") as Ref)
      site:=(r["siteRef"] as Ref) ?: (eq?.get("siteRef") as Ref)
      floorRec:=floor == null ? null : cx.db.readById(floor,false)
      siteRec:=site == null ? null : cx.db.readById(site,false)
      if (floorRec != null && !cx.canRead(floorRec)) floorRec=null
      if (siteRec != null && !cx.canRead(siteRec)) siteRec=null
      energyTags:=["elec","water","gas","steam","heat","chilledWater","hotWater","fuelOil"].findAll |tag| { r[tag] is Marker || eq?.get(tag) is Marker }
      items.add(["id":r.id.id,"name":r.dis,"navName":r["navName"] as Str,"unit":r["unit"],"kind":r["kind"],"his":r.has("his"),"hisMode":r["hisMode"],"source":r["connRef"]?.toStr,"hisStart":iso(r["hisStart"]),"hisEnd":iso(r["hisEnd"]),"curStatus":r["curStatus"],"hisStatus":r["hisStatus"],"hisErr":r["hisErr"],"hisLastCollect":iso(r["hisCollectLastTime"]),"equipName":eq?.dis,"equipNavName":eq?.get("navName") as Str,"floorName":floorRec?.dis,"siteName":siteRec?.dis,"energyTags":energyTags,"equipId":eq?.id?.id,"floorId":floorRec?.id?.id,"siteId":siteRec?.id?.id])
    }
    return ["items":items,"total":list.size,"offset":offset,"limit":limit]
  }

  [Str:Obj?] report([Str:Obj?] input)
  {
    mustRead
    request := input.dup
    request["tz"] = cx.proj.meta["tz"] ?: "Shanghai"
    SeedForecast.validate(request)
    if (nativeModel) request=SeedNativeEquip.request(request,SeedNativeEquipRepo(this).mapping)
    all := input["dimension"] == "space" && input["spaceSource"] == "fin" ? liveRecords : records
    if (nativeModel) all=SeedNativeEquipRepo(this).validateRead(all)
    return SeedEngine.report(request,all,SeedHistory.load(cx,request,all))
  }

  [Str:Obj?] treeView(Str dimension)
  {
    mustRead
    if (!SeedRelations.dimensions.contains(dimension)) throw ArgErr("无效的树维度")
    all:=dimension == "space" ? liveRecords : records
    containerKind:=dimension == "metering" ? "category" : dimension
    return ["dimension":dimension,"spaceSource":dimension == "space" ? "fin" : null,"records":dimension == "legacy" ? all.findAll |r| { ["group","meter","totalMeter","sensor"].contains(r["kind"]) } : all.findAll |r| { r["canonicalId"] == null && (r["kind"] == containerKind || (dimension == "space" && r["kind"] == "nativePoint") || SeedRelations.meterKinds.contains(r["kind"])) }]
  }

  ** Preview, atomic apply and guarded rollback modify Seed configuration only.
  [Str:Obj?] migration([Str:Obj?] input)
  {
    mustWrite
    if (input["target"] != "threeTree") return SeedNativeEquipRepo(this).migrate(input)
    all:=records
    action:=input["action"] as Str ?: "preview"
    if (action == "rollback") return rollbackMigration(input,all)
    sources:=migrationSources(all)
    plan:=SeedMigration.plan(all,sources)
    plan["revision"]=iso(revision?.get("mod")) ?: ""
    plan["sourceRevision"]=JsonOutStream.writeJsonToStr(sources).hash.toHex
    if (action == "preview")
    {
      if (input["summary"] == true)
      {
        compact:=plan.dup
        compact["records"]=SeedMath.maps(plan["records"]).map |r->[Str:Obj?]| { ["id":r["id"],"kind":r["kind"],"name":r["name"]] }
        compact["suggestions"]=SeedMath.maps(plan["suggestions"]).map |s->[Str:Obj?]|
        {
          item:=s.dup; item.remove("records"); item.remove("patches"); return item
        }
        return compact
      }
      return plan
    }
    if (action != "apply") throw ArgErr("无效迁移操作")
    if (input["revision"] != plan["revision"] || input["sourceRevision"] != plan["sourceRevision"]) throw SeedHttpErr(409,"CONFLICT","配置或 FIN 来源已变化，请重新预览")
    accepted:=SeedMath.strings(input["acceptedSuggestionIds"])
    suggestions:=SeedMath.maps(plan["suggestions"])
    if (accepted.any |id| { !suggestions.any |s| { s["id"] == id } }) throw ArgErr("迁移建议不存在，请重新预览")
    edits:=Str:[Str:Obj?][:]
    SeedMath.maps(plan["records"]).each |r| { edits[r["id"].toStr]=r.dup }
    suggestions.findAll |s| { accepted.contains(s["id"]) }.each |s|
    {
      SeedMath.maps(s["records"]).each |r|
      {
        id:=r["id"].toStr
        if (!all.any |a| { a["id"] == id } && !edits.containsKey(id)) edits[id]=r.dup
      }
      SeedMath.maps(s["patches"]).each |p|
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
      SeedMath.strings(suggestion["recordIds"]).each |meterId|
      {
        if (positioned.containsKey(meterId) && positioned[meterId] != targetId) throw ArgErr("空间建议范围重叠，请为同一表计选择一致的空间")
        positioned[meterId]=targetId
        meter:=edits[meterId]
        if (meter == null) meter=all.find |r| { r["id"] == meterId }
        if (meter == null || !SeedRelations.meterKinds.contains(meter["kind"])) throw ArgErr("空间建议中的表计不存在")
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
      SeedConfig.validate(r,candidate); validatePoint(r)
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
    snapshots.each |s| { after.addAll(SeedMath.maps(s["after"])); before.addAll(SeedMath.maps(s["before"])) }
    if (after.isEmpty) throw ArgErr("迁移快照不完整")
    after.each |r|
    {
      current:=all.find |a| { a["id"] == r["id"] }
      if (current == null || business(current) != business(r)) throw SeedHttpErr(409,"CONFLICT","迁移后配置已被修改，不能自动回滚")
    }
    ids:=after.map |r->Str| { r["id"].toStr }
    candidate:=all.findAll |r| { !ids.contains(r["id"]) }.dup.addAll(before)
    removed:=ids.findAll |key| { !before.any |r| { r["id"] == key } }
    removed.each |key| { SeedConfig.canDelete(key,candidate) }
    candidate.findAll |r| { !["job","alarm"].contains(r["kind"]) }.each |r| { SeedConfig.validate(r,candidate) }
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
    all.findAll |r| { SeedRelations.meterKinds.contains(r["kind"]) && r["pointId"] != null }.map |r->Str| { r["pointId"].toStr }.unique.sort.each |Str id|
    {
      point:=cx.db.readById(Ref(id),false)
      if (point == null || !cx.canRead(point)) return
      equip:=cx.db.readById(point["equipRef"] as Ref ?: Ref("finseed-no-equip"),false)
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
    if (r["state"] == "acknowledged") return r
    r["mod"] = mod
    r["state"] = "acknowledged"
    r["ackBy"] = cx.user.username
    r["ackAt"] = DateTime.now.toIso
    r["ackNote"] = note.size > 2000 ? note[0..<2000] : note
    return save(r,true)
  }

  private Void validatePoint([Str:Obj?] rec)
  {
    point := rec["pointId"] as Str
    if (point == null || point.isEmpty) return
    r := cx.db.readById(Ref.fromStr(point),false)
    if (r == null || !r.has("point") || r.has("seedComputed")) throw ArgErr("请选择当前 FIN 项目的原始点位")
    if (!cx.canRead(r)) throw SeedHttpErr(403,"PERMISSION","当前 FIN 用户没有该点位的读取权限")
    if (!r.has("his")) throw ArgErr("点位尚未启用 FIN 历史记录")
  }

  internal Void commit(Diff[] changes, Bool event := false)
  {
    if (!event)
    {
      // A shared optimistic revision serializes uniqueness/cycle checks across requests.
      key := Ref("finseed-config-revision")
      prior := revision
      tags := Etc.makeDict(["seedRevision":Number(DateTime.nowTicks),"seedUpdatedBy":cx.user.username])
      changes.add(prior == null ? Diff.makeAdd(tags,key) : Diff(prior,tags))
    }
    try { cx.db.commitAll(changes) }
    catch (Err e)
    {
      if (["ConcurrentChangeErr","DuplicateRecErr"].contains(e.typeof.name)) throw SeedHttpErr(409,"CONFLICT","配置已被修改，请刷新后重试")
      throw e
    }
    revisionRead = false
  }

  internal static Void checkMod(Dict previous, Obj? mod)
  {
    if (mod == null || iso(previous["mod"]) != mod.toStr) throw SeedHttpErr(409,"CONFLICT","配置已被修改，请刷新后重试")
  }

  internal Dict encode([Str:Obj?] rec, Dict? old := null)
  {
    if (old?.has("equip") == true) return SeedNativeEquip.tags(rec,old,cx.user.username)
    data := SeedNativeSpace.clean(rec)
    data.remove("id"); data.remove("mod")
    tags := Str:Obj?["seed":Marker.val,"seedKind":rec["kind"],"dis":rec["name"],"seedUpdatedBy":cx.user.username,"seedUpdatedAt":DateTime.now]
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
      ["xId","yId","baselineId"].each |key| { if (template[key] != null) refs.add(Ref.fromStr(template[key].toStr)) }
    }
    if (!refs.isEmpty) tags["seedDependencyRefs"] = refs.unique
    else if (old?.has("seedDependencyRefs") == true) tags["seedDependencyRefs"] = Remove.val
    json := JsonOutStream.writeJsonToStr(data)
    if (json.size > 30000) throw ArgErr("单条配置超过30000字符，请缩小模板或规则范围")
    tags["seedConfig"] = json
    return Etc.makeDict(tags)
  }

  static [Str:Obj?] decode(Dict rec)
  {
    if (rec.has("equip")) return SeedNativeEquip.decode(rec)
    data := (Str:Obj?)JsonInStream((rec["seedConfig"] as Str ?: "{}").in).readJson
    refTags.each |tag,key| { if (rec[tag] is Ref) data[key] = ((Ref)rec[tag]).id }
    data["id"] = rec.id.id
    data["mod"] = iso(rec["mod"])
    data["kind"] = rec["seedKind"]
    data["name"] = rec.dis
    return data
  }

  static Str? iso(Obj? v) { v is DateTime ? ((DateTime)v).toIso : v?.toStr }
}

const class SeedHttpErr : Err
{
  const Int status
  const Str code
  new make(Int status, Str code, Str msg) : super(msg) { this.status=status; this.code=code }
}

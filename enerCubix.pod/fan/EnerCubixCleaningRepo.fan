using haystack
using folio
using skyarcd

** Native profile storage and reversible ownership of computed-history tags.
** Every mutation is returned to the caller's atomic equipment/config commit.
class EnerCubixCleaningRepo
{
  EnerCubixRepo repo
  private Context cx() { repo.cx }
  new make(EnerCubixRepo repo) { this.repo=repo }

  static const Str functionName := "enerCubixCleanHis"
  static const Str[] historyTags := ["hisFunc","hisFuncConfig","hisFuncWritable"]
  static const Str[] ownershipTags := ["enerCubixCleaningOwned","enerCubixCleaningProfileRef","enerCubixCleaningProfileVersion","enerCubixCleaningEquipRef","enerCubixCleaningOriginal","enerCubixCleaningApplied","enerCubixCleaningRollover"]

  [Str:Obj?] save([Str:Obj?] input)
  {
    repo.mustWrite
    all:=repo.rawRecords
    id:=input["id"] as Str
    previous:=id == null ? null : repo.stored(id)
    if (previous != null)
    {
      if (previous["enerCubixKind"] != "cleaningProfile") throw ArgErr("记录不是清洗方案")
      EnerCubixRepo.checkMod(previous,input["mod"])
    }
    profile:=profileRecord(input,previous == null ? null : EnerCubixRepo.decode(previous))
    if (all.any |r| { r["kind"] == "cleaningProfile" && r["id"] != id && (r["name"]?.toStr ?: "").trim.lower == profile["name"].toStr.lower }) throw ArgErr("清洗方案名称已存在")
    if (id == null) { id=Ref.gen.id; profile["id"]=id }
    diffs:=Diff[,]
    // Validate every reference first; a bad unit or changed source aborts the
    // profile update and every point update together.
    referenced(id).each |equip|
    {
      readable(equip)
      point:=pointFor(equip)
      validatePoint(point,equip)
      config:=configFor(profile,point)
      if (equip.has("enerCubixCleaningEnabled")) diffs.add(Diff(point,install(point,equip.id,config)))
    }
    diffs.add(previous == null ? Diff.makeAdd(repo.encode(profile),Ref(id)) : Diff(previous,repo.encode(profile,previous)))
    repo.commit(diffs)
    return EnerCubixRepo.decode(repo.stored(id))
  }

  [Str:Obj?] remove(Str id, Obj? mod)
  {
    repo.mustWrite
    repo.rawRecords
    previous:=repo.stored(id)
    if (previous["enerCubixKind"] != "cleaningProfile") throw ArgErr("记录不是清洗方案")
    EnerCubixRepo.checkMod(previous,mod)
    if (!referenced(id).isEmpty || cx.db.readAllList(Filter.has("enerCubixCleaningOwned")).any |p| { (p["enerCubixCleaningProfileRef"] as Ref)?.id == id })
      throw ArgErr("清洗方案仍被设备或历史点引用，请先解除关联")
    repo.commit([Diff(previous,null,Diff.remove)])
    return ["deleted":id]
  }

  ** Called after equipment validation and before the equipment's own Diff.
  ** Point changes restore cleaning ownership and mark the selected energy counter
  ** in the same commit as its equipment binding.
  Diff[] configure([Str:Obj?] record)
  {
    repo.mustWrite
    if (record["cleaningEnabled"] != null && record["cleaningEnabled"] isnot Bool) throw ArgErr("cleaningEnabled 必须为布尔值")
    id:=record["id"] as Str ?: throw ArgErr("缺少设备标识")
    equip:=cx.db.readById(Ref(id),false) ?: throw ArgErr("FIN 设备不存在")
    readable(equip)
    if (!equip.has("equip")) throw ArgErr("清洗仅支持 FIN 原生设备")
    EnerCubixRepo.checkMod(equip,record["mod"])
    enabled:=record["cleaningEnabled"] == true
    pointId:=record["pointId"] as Str
    Dict? selectedPoint:=pointId != null ? cx.db.readById(Ref(pointId),false) : null
    diffs:=Diff[,]
    ownedPoints(equip.id).each |point|
    {
      readable(point)
      if (!enabled || point.id != selectedPoint?.id)
      {
        tags:=Etc.dictToMap(restore(point))
        diffs.add(Diff(point,Etc.makeDict(tags)))
      }
    }
    if (!enabled) return diffs
    if (record["expressionId"] != null || record["canonicalId"] != null) throw ArgErr("公式或别名档案不能配置点位清洗")
    if (record["historyMode"] != null && !["auto","cumulative"].contains(record["historyMode"])) throw ArgErr("清洗需要累计历史数据")
    profileId:=record["cleaningProfileId"] as Str ?: throw ArgErr("请选择清洗方案")
    profile:=loadProfile(profileId)
    point:=selectedPoint
    if (point == null) throw ArgErr("请选择当前设备的主历史点")
    validatePoint(point,equip,record["historyMode"] as Str)
    tags:=Etc.dictToMap(install(point,equip.id,configFor(profile,point)))
    diffs.add(Diff(selectedPoint,Etc.makeDict(tags)))
    return diffs
  }

  ** Use during unenrollment in the same commit as clearing equipment tags.
  Diff[] disable(Dict equip)
  {
    repo.mustWrite
    readable(equip)
    return ownedPoints(equip.id).map |p->Diff| { readable(p); return Diff(p,restore(p)) }
  }

  ** Current profile is authoritative for new reads. Report snapshots contain
  ** their own full configuration and do not call this method on replay.
  Dict currentConfig(Dict point, Str:Dict? pending := Str:Dict?[:])
  {
    repo.mustRead
    readable(point)
    if (!managed(point)) throw ArgErr("历史点不由 EnerCubix 清洗管理")
    if (point["hisFuncWritable"] !== Marker.val || point["enerCubixCleaningProfileVersion"] isnot Number) throw ArgErr("清洗点位原生标签类型无效")
    equipRef:=point["enerCubixCleaningEquipRef"] as Ref ?: throw ArgErr("清洗设备归属缺失")
    equip:=pendingRecord(equipRef,pending) ?: throw ArgErr("清洗设备不存在")
    readable(equip)
    if (equip["enerCubixCleaningEnabled"] !== Marker.val || equip["enerCubixPointRef"] != point.id || equip["enerCubixCleaningProfileRef"] != point["enerCubixCleaningProfileRef"])
      throw ArgErr("清洗点位与设备配置不一致")
    validatePoint(point,equip)
    profileRef:=point["enerCubixCleaningProfileRef"] as Ref ?: throw ArgErr("清洗方案引用缺失")
    profileRecord:=pendingRecord(profileRef,pending) ?: throw ArgErr("清洗方案不存在")
    if (!profileRecord.has("enerCubix") || profileRecord["enerCubixKind"] != "cleaningProfile") throw ArgErr("清洗方案不存在")
    readable(profileRecord)
    profile:=EnerCubixRepo.decode(profileRecord)
    config:=configFor(profile,point)
    if (point["enerCubixCleaningProfileVersion"] != config["enerCubixProfileVersion"] || point["enerCubixCleaningRollover"] != config["hisTotalizedRollover"]) throw ArgErr("清洗点位版本或回绕属性与方案不一致")
    if (point["hisFuncConfig"] isnot Dict || !same((Dict)point["hisFuncConfig"],config)) throw ArgErr("清洗点位配置与当前方案不一致")
    return config
  }

  ** Check the proposed atomic state, including batch edits, without reading history.
  Void validateSaves(Diff[] changes)
  {
    before:=Str:Dict?[:]
    changes.each |d| { before[d.id.id]=d.isAdd ? null : cx.db.readById(d.id,false) }
    if (!changes.any |d| { before[d.id.id]?.has("equip") == true || before[d.id.id]?.has("point") == true || d.changes.has("equip") || d.changes.has("point") }) return
    pending:=Str:Dict?[:]
    changes.each |diff|
    {
      if (diff.isRemove) { pending[diff.id.id]=null; return }
      tags:=Etc.dictToMap(pending[diff.id.id] ?: (before[diff.id.id] ?: Etc.emptyDict))
      diff.changes.each |v,k| { if (v is Remove) tags.remove(k); else tags[k]=v }
      pending[diff.id.id]=Etc.makeDict(tags.set("id",diff.id))
    }
    equips:=Str:Dict[:]
    cx.db.readAllList(Filter("equip and enerCubixKind")).each |e| { equips[e.id.id]=e }
    pending.each |e,id| { if (e?.has("equip") == true) equips[id]=e; else if (equips.containsKey(id)) equips.remove(id) }
    lookup:=|Ref id->Dict?| { r:=pendingRecord(id,pending); return r != null && cx.canRead(r) ? r : null }
    equips.each |equip,id|
    {
      pointRef:=equip["enerCubixPointRef"] as Ref
      if (!equip.has("enerCubixCleaningEnabled")) return
      // A meter's own cleaning remains valid when its current descendants are
      // added, removed, unavailable or configured with a different profile.
      if (!pending.containsKey(id) && !pending.containsKey(pointRef?.id ?: "")) return
      readable(equip)
      problems:=sourceProblems(equip,lookup,|Dict p| { currentConfig(p,pending) })
      if (!problems.isEmpty) throw ArgErr("清洗点位与设备配置不一致")
    }
  }

  private Dict? pendingRecord(Ref id, Str:Dict? pending)
  { pending.containsKey(id.id) ? pending[id.id] : cx.db.readById(id,false) }

  internal static Str[] sourceProblems(Dict owner, |Ref->Dict?| lookup, |Dict->Void| validate)
  {
    problems:=Str[,]
    checkSource(owner,lookup,validate,problems)
    return problems.unique
  }

  private static Void checkSource(Dict owner, |Ref->Dict?| lookup, |Dict->Void| validate, Str[] problems)
  {
    name:=sourceName(owner)
    ref:=owner["enerCubixPointRef"] as Ref
    point:=ref == null ? null : lookup(ref)
    if (point == null || !point.has("point") || !point.has("his") || point["kind"] != "Number" || point["equipRef"] != owner.id)
    { problems.add("“"+name+"”：主能耗点需要属于本设备且已启用数值历史"); return }
    if (point["hisFunc"] == functionName)
    {
      try { validate(point) }
      catch (Err e) { problems.add("“"+name+"”：清洗配置无效，请检查清洗方案、累计读数类型和单位"); return }
    }
    else if (point["hisFunc"] == "hfTotalized" || (point.has("hisFunc") && owner["enerCubixHistoryMode"] == "interval")) return
    else
    {
      problems.add(point.has("hisFunc") ? "“"+name+"”：历史函数未输出可识别的区间用量" : "“"+name+"”：尚未启用清洗或未选择清洗方案")
      return
    }
  }

  private static Str sourceName(Dict equip)
  { (equip["enerCubixAlias"] as Str) ?: ((equip["navName"] as Str) ?: equip.dis) }

  [Str:Obj?][] decorate([Str:Obj?][] records)
  {
    repo.mustRead
    records.findAll |r| { r["nativeEquip"] == true }.each |r|
    {
      pointId:=r["pointId"] as Str
      point:=pointId == null ? null : cx.db.readById(Ref(pointId),false)
      if (point != null && !cx.canRead(point)) { r["cleaningStatus"]="forbidden"; return }
      if (point != null && external(point)) { r["cleaningStatus"]="externalFunctionManaged"; return }
      if (r["cleaningEnabled"] != true) { r["cleaningStatus"]="disabled"; return }
      profileId:=r["cleaningProfileId"] as Str
      profile:=profileId == null ? null : cx.db.readById(Ref(profileId),false)
      if (profile == null || profile["enerCubixKind"] != "cleaningProfile") { r["cleaningStatus"]="missingProfile"; return }
      try
      {
        if (point == null) throw ArgErr("清洗历史点不存在")
        currentConfig(point)
        r["cleaningStatus"]="managed"
        r["cleaningProfileVersion"]=EnerCubixRepo.decode(profile)["version"]
      }
      catch (Err e) { r["cleaningStatus"]="sourceFault"; r["cleaningError"]=e.msg }
    }
    return records
  }

  ** Read-only, explicitly bounded comparison. Raw history is never written.
  [Str:Obj?] preview([Str:Obj?] request)
  {
    repo.mustRead
    nodeId:=request["nodeId"] as Str
    node:=nodeId == null ? null : cx.db.readById(Ref(nodeId),false)
    if (node != null) readable(node)
    pointId:=request["pointId"] as Str
    if (pointId == null) pointId=(node?.get("enerCubixPointRef") as Ref)?.id
    if (pointId == null) throw ArgErr("请选择历史点")
    point:=cx.db.readById(Ref(pointId),false) ?: throw ArgErr("历史点不存在")
    readable(point)
    if (external(point)) return ["pointId":pointId,"unit":point["unit"],"status":"externalFunctionManaged","raw":Obj?[,],"cleaned":Obj?[,],"details":Obj?[,],"summary":["status":"externalFunctionManaged"]]
    equip:=cx.db.readById(point["equipRef"] as Ref ?: throw ArgErr("历史点没有设备归属"),false) ?: throw ArgErr("FIN 设备不存在")
    readable(equip); validatePoint(point,equip)
    from:=DateTime.fromIso(request["from"]?.toStr ?: "")
    to:=DateTime.fromIso(request["to"]?.toStr ?: "")
    if (to <= from || to-from > 31day) throw ArgErr("预览范围必须大于零且不超过31天")
    profileId:=request["profileId"] as Str ?: (equip["enerCubixCleaningProfileRef"] as Ref)?.id
    profile:=request["profile"] is Map ? profileRecord((Str:Obj?)request["profile"],null) : loadProfile(profileId ?: throw ArgErr("请选择清洗方案"))
    config:=configFor(profile,point)
    result:=EnerCubixHistory.cleanRead(cx,point,Span.makeAbs(from,to),Etc.makeDict(["enerCubixCleaningPreview":Marker.val]),config)
    raw:=sampleJson(result.rawItems,from,to)
    cleaned:=sampleJson(EnerCubixHistory.nativeItems(result),from,to)
    [Str:Obj?][] details:=result.details.map |d->[Str:Obj?]| { EnerCubixHistory.nativeDetail(d) }
    details=details.findAll |d| { ts:=DateTime.fromIso(d["ts"].toStr); return ts >= from && ts < to }
    evidence:=EnerCubixHistory.cleaningEvidence(point,result,from,to)
    if (result.summary.containsKey("sources")) details.addAll(EnerCubixMath.maps(evidence["details"]).findAll |d| { d["pointId"] != point.id.id })
    summary:=result.summary.dup
    summary["inputCount"]=raw.size; summary["outputCount"]=cleaned.size
    summary["validCount"]=cleaned.findAll |s| { s["valueType"] == "number" }.size
    summary["nullCount"]=cleaned.findAll |s| { s["valueType"] == "null" }.size
    summary["naCount"]=cleaned.findAll |s| { s["valueType"] == "na" }.size
    summary.setAll(evidence); summary.remove("details")
    summary["detailsTruncated"]=result.summary.containsKey("sources") && evidence["detailsTruncated"] == true
    return ["pointId":pointId,"status":"ok","from":from.toIso,"to":to.toIso,"unit":point["unit"],"outputMode":"interval","raw":raw,"cleaned":cleaned,"details":details,"summary":summary,"config":EnerCubixCleaning.jsonConfig(config),"profileSnapshot":profile]
  }

  internal static [Str:Obj?] profileRecord([Str:Obj?] input, [Str:Obj?]? previous)
  {
    if (input["kind"] != "cleaningProfile") throw ArgErr("记录不是清洗方案")
    name:=(input["name"] as Str)?.trim ?: ""
    if (name.isEmpty || name.size > 200) throw ArgErr("请输入不超过200字符的清洗方案名称")
    mode:=input["mode"] as Str ?: "drop"
    if (!["drop","replace","rollover"].contains(mode)) throw ArgErr("无效的清洗模式")
    Str:Obj? parameters:=(input["parameters"] as Map) ?: Str:Obj?["deltaMin":0,"timeMax":"1h","defNull":true]
    if (input["parameters"] != null && input["parameters"] isnot Map) throw ArgErr("清洗参数必须为对象")
    unit:="kWh"
    // Rate limits have different dimensions from the cumulative point. Prefer
    // a cumulative quantity when selecting the unit for unbound validation.
    ["deltaMin","deltaMax","defVal","hisTotalizedRollover"].each |key|
    {
      v:=parameters[key] as Map
      if (v != null && v["type"] == "number" && v["unit"] is Str) unit=v["unit"]
    }
    if (unit == "kWh" && !["deltaMin","deltaMax","defVal","hisTotalizedRollover"].any |key| { parameters[key] is Map })
    {
      Map? rate:=parameters["derivMin"] as Map
      if (rate == null) rate=parameters["derivMax"] as Map
      rateUnit:=rate?.get("unit") as Str
      if (rateUnit != null)
      {
        energy:=["W":"Wh","kW":"kWh","MW":"MWh","BTU/h":"BTU","kBTU/h":"kBTU","gal/min":"gal","L/min":"L"]
        unit=energy[rateUnit] ?: unit
      }
    }
    checked:=EnerCubixCleaning.config((Str:Obj?)parameters,unit)
    validateMode(mode,checked)
    prior:=previous == null ? 0 : version(previous["version"])
    if (previous != null && version(input["version"]) != prior) throw EnerCubixHttpErr(409,"CONFLICT","清洗方案版本已变化，请刷新后重试")
    out:=Str:Obj?["kind":"cleaningProfile","name":name,"mode":mode,"parameters":parameters.dup,"version":prior+1]
    if (input["id"] != null) out["id"]=input["id"]
    if (input["mod"] != null) out["mod"]=input["mod"]
    return out
  }

  internal static Dict configFor([Str:Obj?] profile, Dict point)
  {
    parameters:=profile["parameters"] as Map ?: throw ArgErr("清洗方案参数缺失")
    tags:=Etc.dictToMap(EnerCubixCleaning.config((Str:Obj?)parameters,point["unit"]?.toStr ?: ""))
    validateMode(profile["mode"] as Str ?: "",Etc.makeDict(tags))
    tags["enerCubixMode"]=profile["mode"]
    if (profile["id"] != null) tags["enerCubixProfileRef"]=Ref(profile["id"].toStr)
    tags["enerCubixProfileVersion"]=Number(version(profile["version"]))
    return Etc.makeDict(tags)
  }

  internal static Bool managed(Dict point) { point["enerCubixCleaningOwned"] === Marker.val && point["hisFunc"] == functionName }
  internal static Bool external(Dict point) { point.has("hisFunc") && !managed(point) }

  internal static Dict install(Dict point, Ref equip, Dict config)
  {
    if (external(point)) throw ArgErr("externalFunctionManaged")
    if (point.has("enerCubixCleaningOwned") && !managed(point)) throw ArgErr("清洗点位所有权与历史函数不一致")
    if (managed(point) && point["enerCubixCleaningEquipRef"] != equip) throw EnerCubixHttpErr(409,"CONFLICT","清洗点位已由其他设备管理")
    if (config["enerCubixProfileRef"] isnot Ref || config["enerCubixProfileVersion"] isnot Number) throw ArgErr("清洗方案原生引用或版本无效")
    original:=point["enerCubixCleaningOriginal"] as Dict
    if (!point.has("enerCubixCleaningOwned"))
    {
      prior:=Str:Obj?[:]
      historyTags.each |tag| { if (point.has(tag)) prior[tag]=point[tag] }
      original=Etc.makeDict(prior)
    }
    if (original == null) throw ArgErr("清洗原始配置快照缺失")
    applied:=Etc.makeDict(["hisFunc":functionName,"hisFuncConfig":config,"hisFuncWritable":Marker.val])
    if (managed(point) && (point["enerCubixCleaningApplied"] isnot Dict || !same((Dict)point["enerCubixCleaningApplied"],Etc.makeDict(historyValues(point))))) throw EnerCubixHttpErr(409,"CONFLICT","历史函数配置已在外部修改")
    out:=Etc.dictToMap(applied)
    out["enerCubixCleaningOwned"]=Marker.val
    out["enerCubixCleaningEquipRef"]=equip
    out["enerCubixCleaningProfileRef"]=config["enerCubixProfileRef"]
    out["enerCubixCleaningProfileVersion"]=config["enerCubixProfileVersion"]
    if (config.has("hisTotalizedRollover")) out["enerCubixCleaningRollover"]=config["hisTotalizedRollover"]
    else if (point.has("enerCubixCleaningRollover")) out["enerCubixCleaningRollover"]=Remove.val
    out["enerCubixCleaningOriginal"]=original
    out["enerCubixCleaningApplied"]=applied
    return Etc.makeDict(out)
  }

  internal static Dict restore(Dict point)
  {
    if (point["enerCubixCleaningOwned"] !== Marker.val) return Etc.emptyDict
    out:=Str:Obj?[:]
    original:=point["enerCubixCleaningOriginal"] as Dict ?: throw ArgErr("清洗原始配置快照缺失")
    applied:=point["enerCubixCleaningApplied"] as Dict ?: throw ArgErr("清洗安装配置快照缺失")
    // If another owner replaced the function, preserve all its function tags.
    if (point["hisFunc"] == functionName)
      historyTags.each |tag| { if (point[tag] == applied[tag] || (point[tag] is Dict && applied[tag] is Dict && same((Dict)point[tag],(Dict)applied[tag]))) out[tag]=original[tag] ?: Remove.val }
    ownershipTags.each |tag| { if (point.has(tag)) out[tag]=Remove.val }
    return Etc.makeDict(out)
  }

  private [Str:Obj?] loadProfile(Str id)
  {
    profile:=repo.stored(id)
    if (profile["enerCubixKind"] != "cleaningProfile") throw ArgErr("清洗方案不存在")
    return EnerCubixRepo.decode(profile)
  }

  private Dict[] referenced(Str id)
  { cx.db.readAllList(Filter.has("equip").and(Filter.has("enerCubixCleaningProfileRef"))).findAll |e| { (e["enerCubixCleaningProfileRef"] as Ref)?.id == id } }

  private Dict[] ownedPoints(Ref equip)
  { cx.db.readAllList(Filter.has("point").and(Filter.has("enerCubixCleaningOwned"))).findAll |p| { p["enerCubixCleaningEquipRef"] == equip } }

  private Dict pointFor(Dict equip)
  { cx.db.readById(equip["enerCubixPointRef"] as Ref ?: throw ArgErr("清洗设备没有主历史点"),false) ?: throw ArgErr("清洗主历史点不存在") }

  private Void readable(Dict record)
  { if (!cx.canRead(record)) throw EnerCubixHttpErr(403,"PERMISSION","没有清洗配置源记录的读取权限") }

  private Void validatePoint(Dict point, Dict equip, Str? overrideMode := null)
  {
    readable(point)
    if (!point.has("point") || !point.has("his") || point["kind"] != "Number") throw ArgErr("清洗需要已启用历史的数值点")
    if (point["equipRef"] != equip.id) throw ArgErr("主历史点必须属于当前 FIN 设备")
    mode:=overrideMode ?: equip["enerCubixHistoryMode"]?.toStr
    if (mode == "interval") throw ArgErr("清洗需要累计历史数据")
    if (!(mode == "cumulative" || point.has("hisTotalized") || point["hisMode"] == "cumulative")) throw ArgErr("缺少 hisTotalized 累计读数标记，无法配置清洗策略")
    unit:=point["unit"] as Str ?: ""
    if (unit.isEmpty || Unit.fromStr(unit,false) == null) throw ArgErr("清洗点位需要有效单位")
  }

  private static Int version(Obj? value)
  {
    n:=value is Int ? ((Int)value).toFloat : value as Float
    if (n == null || n < 1f || n > 2147483647f || n.floor != n) throw ArgErr("清洗方案版本必须为正整数")
    return n.toInt
  }

  private static Void validateMode(Str mode, Dict config)
  {
    expected:=config.has("defNull") ? "drop" : (config.has("defVal") ? "replace" : "rollover")
    if (mode != expected) throw ArgErr("清洗模式与参数不一致")
  }

  private static Str:Obj? historyValues(Dict point)
  { out:=Str:Obj?[:]; historyTags.each |tag| { if (point.has(tag)) out[tag]=point[tag] }; return out }

  private static Bool same(Dict a, Dict b)
  {
    left:=Str[,]; right:=Str[,]
    a.each |v,k| { left.add(k) }; b.each |v,k| { right.add(k) }
    if (left.sort != right.sort) return false
    return left.all |key| { sameValue(a[key],b[key]) }
  }

  private static Bool sameValue(Obj? a, Obj? b)
  {
    if (a === b) return true
    if (a == null || b == null) return false
    if (a is Dict && b is Dict) return same((Dict)a,(Dict)b)
    if (a is Ref && b is Ref) return ((Ref)a).id == ((Ref)b).id
    if (a is List && b is List)
    {
      left:=(List)a; right:=(List)b
      if (left.size != right.size) return false
      for (i:=0;i<left.size;i++) if (!sameValue(left[i],right[i])) return false
      return true
    }
    return a == b
  }

  private static [Str:Obj?][] sampleJson(HisItem[] items, DateTime from, DateTime to)
  { items.findAll |s| { s.ts >= from && s.ts < to }.map |s->[Str:Obj?]| { ["ts":s.ts.toIso,"value":s.val is Number ? ((Number)s.val).toFloat : null,"valueType":s.val == NA.val ? "na" : (s.val == null ? "null" : "number")] } }
}

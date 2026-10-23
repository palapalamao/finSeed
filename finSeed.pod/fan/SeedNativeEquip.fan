using haystack
using util

** The only fields Seed owns on an existing FIN equipment record.
const class SeedNativeEquip
{
  static const [Str:Str] scalars := ["name":"seedAlias", "unit":"seedUnit", "area":"seedArea", "maximum":"seedMaximum", "historyMode":"seedHistoryMode", "includeInTotals":"seedIncludeInTotals", "autoSum":"seedAutoSum", "alarmEnabled":"seedAlarmEnabled", "alarmLimit":"seedAlarmLimit", "actualEfficiency":"seedActualEfficiency", "baselineEfficiency":"seedBaselineEfficiency", "location":"seedLocation", "description":"seedDescription"]

  static Str[] ownedTags()
  { ["seed","seedKind","seedUpdatedAt","seedUpdatedBy"].addAll(SeedRepo.refTags.vals).addAll(scalars.vals).unique }

  ** Order and cached Ref display text cannot change a semantic source revision.
  static Str sourceRevision(Dict[] equips, Dict[] points)
  {
    rows:=Str[,]
    equips.each |eq| { rows.add(sourceRow(eq,ownedTags.dup.addAll(["id","equip","siteRef","floorRef","equipRef"]))) }
    points.each |p| { rows.add(sourceRow(p,["id","point","equipRef","unit","kind","his","hisMode","hisTotalized","hisFunc"])) }
    return rows.sort.join("\n").toBuf.toDigest("SHA-256").toHex
  }

  private static Str sourceRow(Dict record, Str[] fields)
  {
    values:=Obj?[,]
    fields.unique.sort.each |field|
    {
      v:=record[field]
      text:=v is Ref ? ((Ref)v).id : v?.toStr
      values.add([field,v?.typeof?.qname,text])
    }
    return JsonOutStream.writeJsonToStr(values)
  }

  static Dict tags([Str:Obj?] data, Dict old, Str user)
  {
    out:=Str:Obj?["seed":Marker.val,"seedKind":data["kind"],"seedUpdatedBy":user,"seedUpdatedAt":DateTime.now]
    SeedRepo.refTags.each |tag,key| { value:=data[key] as Str; if (value != null && !value.isEmpty) out[tag]=Ref(value); else if (old.has(tag)) out[tag]=Remove.val }
    scalars.each |tag,key|
    {
      value:=data[key]
      if (value is Float) value=Number((Float)value)
      if (value is Int) value=Number((Int)value)
      if (value != null) out[tag]=value
      else if (old.has(tag)) out[tag]=Remove.val
    }
    return Etc.makeDict(out)
  }

  static Dict clear(Dict old)
  {
    tags:=Str:Obj?[:]
    ownedTags.each |tag| { if (old.has(tag)) tags[tag]=Remove.val }
    return Etc.makeDict(tags)
  }

  static [Str:Obj?] decode(Dict equip)
  {
    name:=equip["seedAlias"] as Str ?: ((equip["navName"] as Str) ?: equip.dis)
    out:=Str:Obj?["id":equip.id.id,"mod":SeedRepo.iso(equip["mod"]),"kind":equip["seedKind"],"name":name,"nativeEquip":true,"nativeDis":equip.dis]
    SeedRepo.refTags.each |tag,key|
    {
      if (equip[tag] is Ref) out[key]=((Ref)equip[tag]).id
      else if (equip.has(tag)) out["configurationError"]=tag+" 必须是 FIN Ref 类型"
    }
    scalars.each |tag,key| { value:=equip[tag]; if (value != null) out[key]=value is Number ? ((Number)value).toFloat : value }
    return out
  }

  static Void validateSource([Str:Obj?] data, Dict equip, Dict? point, [Str:Obj?][] all)
  {
    if (!equip.has("equip")) throw ArgErr("能源业务对象必须是本项目 FIN 原生设备")
    ["includeInTotals","alarmEnabled","autoSum"].each |field| { if (data[field] != null && data[field] isnot Bool) throw ArgErr(field+" 必须为布尔值") }
    if (data["expressionId"] != null)
    {
      if (data["autoSum"] == true) throw ArgErr("分表合计与计算公式不能同时启用")
      if (!equip.has("seedVirtual")) throw ArgErr("表达式仅可绑定 FIN 虚拟设备")
      if (data["pointId"] != null) throw ArgErr("主能耗点和表达式不可同时设置")
      return
    }
    if (point == null || !point.has("point") || !point.has("his") || point.has("seedComputed")) throw ArgErr("请选择本设备下已开启历史的主能耗点")
    if (point["equipRef"] != equip.id) throw ArgErr("主能耗点必须属于当前 FIN 设备")
    if (data["autoSum"] == true && SeedMeterRollup.collected(point)) throw ArgErr("有采集源的实测点不能按分表覆盖当前值")
    category:=all.find |r| { r["id"] == data["categoryId"] }
    if (data["kind"] != "sensor" && SeedMath.unitFactor(point["unit"]?.toStr ?: "",category?.get("unit")?.toStr ?: "") == null) throw ArgErr("主能耗点单位与能源类型不兼容")
  }

  ** Rewrite business references only: history point IDs and sourceIds never change.
  static [Str:Obj?] rewrite([Str:Obj?] record, Str:Str mapping)
  {
    out:=record.dup
    ["id","parentId","meterParentId","canonicalId","nodeId","numeratorId","denominatorId"].each |key| { value:=out[key] as Str; if (value != null && mapping.containsKey(value)) out[key]=mapping[value] }
    if (out["variables"] is Map)
    {
      vars:=((Map)out["variables"]).dup
      vars.each |value,key| { if (value is Str && mapping.containsKey(value)) vars[key]=mapping[value] }
      out["variables"]=vars
    }
    if (out["request"] is Map) out["request"]=request((Str:Obj?)out["request"],mapping)
    return out
  }

  static [Str:Obj?] request([Str:Obj?] input, Str:Str mapping)
  {
    out:=input.dup
    ["nodeIds","referenceIds"].each |key|
    {
      if (out[key] isnot List) return
      prior:=SeedMath.strings(out[key])
      current:=prior.map |id->Str| { mapping[id] ?: id }.unique
      if (current != prior) out[key]=current
    }
    ["xId","yId","baselineId"].each |key| { id:=out[key] as Str; if (id != null) out[key]=mapping[id] ?: id }
    return out
  }

  static [Str:Obj?] preview([Str:Obj?][] records, Dict[] equips, Dict[] points)
  {
    mapping:=Str:Str[:]; conflicts:=Str[,]; rows:=[Str:Obj?][,]
    meters:=records.findAll |r| { SeedRelations.meterKinds.contains(r["kind"]) && r["nativeEquip"] != true }
    meters.each |old|
    {
      point:=points.find |p| { p.id.id == old["pointId"] }
      equip:=equips.find |e| { e.id == point?.get("equipRef") }
      if (equip == null) { conflicts.add(old["name"].toStr+"：没有唯一可用的 FIN 原生设备"); return }
      if (mapping.vals.contains(equip.id.id)) { conflicts.add(old["name"].toStr+"：同一设备对应多份计量档案，请明确主能耗点"); return }
      if (equip.has("seedKind")) { conflicts.add(equip.dis+"：原生设备已有能源配置，不能覆盖"); return }
      mapping[old["id"].toStr]=equip.id.id
    }
    meters.each |old|
    {
      target:=mapping[old["id"].toStr]
      if (target == null) return
      row:=rewrite(old,mapping); row.remove("mod"); row["nativeEquip"]=true
      row["legacyId"]=old["id"]; row["legacyParentId"]=old["parentId"]
      eq:=equips.find |e| { e.id.id == target }
      row["mod"]=SeedRepo.iso(eq["mod"])
      changes:=Str:Obj?[:]
      tags(row,eq,"migrationPreview").each |value,tag|
      {
        if (["seedUpdatedBy","seedUpdatedAt"].contains(tag)) return
        before:=eq[tag]; after:=value is Remove ? null : value
        if (before == after) return
        changes[tag]=["before":before?.toStr,"after":after?.toStr]
      }
      row["tagChanges"]=changes
      try { validateSource(row,eq,points.find |p| { p.id.id == row["pointId"] },records) }
      catch (Err e) { conflicts.add(old["name"].toStr+"："+e.msg) }
      rows.add(row)
    }
    return ["target":"nativeEquip","records":rows,"mapping":mapping,"conflicts":conflicts,"warnings":Str[,],"suggestions":[Str:Obj?][,],"counts":["added":0,"updated":rows.size,"canonicalAliases":mapping.size,"spaces":0,"suggestions":0,"unboundMeters":conflicts.size]]
  }
}

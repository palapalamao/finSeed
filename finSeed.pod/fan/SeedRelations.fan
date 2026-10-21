** Independent coverage, upstream meter and accounting ownership relationships.
const class SeedRelations
{
  static const Str[] dimensions := ["space","metering","organization","legacy"]
  static const Str[] meterKinds := ["meter","totalMeter","sensor"]

  static Void validate([Str:Obj?] rec, [Str:Obj?][] all)
  {
    id:=rec["id"] as Str ?: ""
    refs:=["spaceId":["space"],"organizationId":["organization"],"meterParentId":["meter","totalMeter"],"canonicalId":["meter","totalMeter","sensor"]]
    refs.each |expected,key|
    {
      target:=rec[key] as Str
      if (target == null || target.isEmpty) return
      if (!meterKinds.contains(rec["kind"])) throw ArgErr("仅计量对象可以设置归属关系")
      other:=all.find |r| { r["id"] == target }
      if (other == null || !expected.contains(other["kind"])) throw ArgErr("引用的归属对象不存在或类型不符")
      if (key == "meterParentId" || key == "canonicalId")
      {
        if (other["canonicalId"] != null) throw ArgErr("请选择计量主档案，不可引用兼容别名")
        seen:=[id]; current:=target
        while (!current.isEmpty)
        {
          if (seen.contains(current)) throw ArgErr("计量关系不能形成循环")
          seen.add(current)
          current=all.find |r| { r["id"] == current }?.get(key) as Str ?: ""
        }
        if (other["categoryId"] != rec["categoryId"]) throw ArgErr("上下级表及兼容引用必须是同一种能源")
      }
      if (key == "canonicalId" && (other["pointId"] != rec["pointId"] || other["expressionId"] != rec["expressionId"])) throw ArgErr("兼容引用必须指向同一个数据来源")
    }
    modern:=rec["parentId"] == null || ["spaceId","meterParentId","organizationId","canonicalId"].any |key| { rec[key] != null }
    all.findAll |r| { r["id"] != id && (r["meterParentId"] == id || r["canonicalId"] == id) }.each |r|
    {
      if (r["categoryId"] != rec["categoryId"]) throw ArgErr("已有下级表或兼容引用，能源类型必须保持一致")
      if (r["canonicalId"] == id && (r["pointId"] != rec["pointId"] || r["expressionId"] != rec["expressionId"])) throw ArgErr("已有兼容引用，不可改变主档案的数据来源")
    }
    duplicates:=all.findAll |r| { r["id"] != id && meterKinds.contains(r["kind"]) && r["pointId"] == rec["pointId"] && r["canonicalId"] == null }
    modernDuplicate:=duplicates.any |r| { r["parentId"] == null || ["spaceId","meterParentId","organizationId"].any |key| { r[key] != null } }
    if ((modern || modernDuplicate) && meterKinds.contains(rec["kind"]) && rec["canonicalId"] == null && rec["pointId"] != null && !duplicates.isEmpty) throw ArgErr("该 FIN 点已有计量主档案，请定位并复用已有表计")
  }

  static [Str:Obj?][] move([Str:Obj?][] all, Str[] ids, Str? parent, Str dimension)
  {
    if (!dimensions.contains(dimension) || dimension == "legacy") throw ArgErr("无效的树维度")
    if (ids.isEmpty) throw ArgErr("请选择对象")
    return ids.unique.map |id->[Str:Obj?]|
    {
      r:=all.find |r| { r["id"] == id } ?: throw ArgErr("配置对象不存在")
      copy:=r.dup
      relationKey:=""
      if (meterKinds.contains(r["kind"])) relationKey=dimension == "space" ? "spaceId" : (dimension == "metering" ? "meterParentId" : "organizationId")
      else if (r["kind"] == dimension && dimension != "metering") relationKey="parentId"
      else throw ArgErr("此对象不能在当前树中移动")
      if (parent == null || parent.isEmpty) copy.remove(relationKey)
      else copy[relationKey]=parent
      return copy
    }
  }
}

using haystack
using folio

** Normal work appends; historical replacement requires a separate explicit request.
internal class EnerCubixHistorySafety
{
  static Bool repairRequested(Str:Obj? request, Bool automatic:=false)
  {
    if (automatic) return false
    if (request["confirmHistoryRewrite"] != true || request["from"] as Str == null || request["to"] as Str == null)
      throw ArgErr("重算会改写所选区间的已有派生历史，须明确确认")
    return true
  }

  static Void metadata(Folio db, Diff[] changes)
  {
    changes.each |d|
    {
      if (d.changes.has("trash") && d.changes["trash"] isnot Remove)
        throw ArgErr("能源魔方禁止自动添加 trash 标记")
      old:=db.readById(d.id,false)
      if (d.isRemove && old != null && ["point","his","enerCubixIntervalBatch","enerCubixMeterGeneration","enerCubixIntervalCorrection"].any |tag| {old.has(tag)})
        throw ArgErr("能源魔方配置操作不能删除历史点或已发布历史")
    }
  }

  ** The caller checks computed-point ownership. Preflight the entire batch before writing.
  static HisItem[] write(Folio db, Dict point, HisItem[] items, Bool repair:=false, Bool skipExisting:=false, Duration timeout:=30sec)
  {
    pending:=pending(db,point,items,repair,skipExisting)
    if (!pending.isEmpty) db.his.write(point.id,pending,null).get(timeout)
    return pending
  }

  private static HisItem[] pending(Folio db, Dict point, HisItem[] items, Bool repair, Bool skipExisting)
  {
    if (items.isEmpty) return items
    if (!point.has("enerCubixComputed") || !point.has("point") || !point.has("his") || point.has("trash") || EnerCubixMeterRollup.collected(point))
      throw ArgErr("历史写入仅允许能源魔方所属派生点")
    pending:=items
    if (!repair)
    {
      ordered:=items.dup.sort |a,b| {a.ts <=> b.ts}
      existing:=Int:Obj?[:]
      db.his.read(point.id,Span.makeAbs(ordered.first.ts,ordered.last.ts+1ms),null) |item| {existing[item.ts.ticks]=item.val}
      pending=items.findAll |item|
      {
        if (!existing.containsKey(item.ts.ticks)) return true
        if (!skipExisting && existing[item.ts.ticks] != item.val)
          throw ArgErr("已有历史与新增结果不同，未获明确授权不能改写")
        return false
      }
    }
    return pending
  }
}

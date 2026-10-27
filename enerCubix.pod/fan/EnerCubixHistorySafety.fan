using haystack
using folio

** Normal work appends; historical replacement requires a separate explicit request.
internal class EnerCubixHistorySafety
{
  static Bool repairRequested(Str:Obj? request, Bool automatic:=false)
  { throw ArgErr("报表只读主能耗点，不再创建或重算派生归档") }

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

  static HisItem[] write(Folio db, Dict point, HisItem[] items, Bool repair:=false, Bool skipExisting:=false, Duration timeout:=30sec)
  { throw ArgErr("报表只读主能耗点，不再创建或重算派生归档") }
}

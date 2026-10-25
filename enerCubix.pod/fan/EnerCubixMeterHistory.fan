using haystack
using folio
using skyarcd
using util

** Meter-owned interval publication. Values and quality share a Folio publication.
** The companion native history is a mirror; readers never mix uncommitted mirrors.
internal class EnerCubixMeterHistory
{
  static [Str:Obj?]? load(Context cx, Dict point, DateTime from, DateTime to)
  {
    if (!cx.canRead(point)) throw ArgErr("forbidden")
    return loadDb(cx.db,point,from,to)
  }

  static Dict? legacyConfig(Context cx, Dict point)
  {
    if (!cx.canRead(point)) throw ArgErr("forbidden")
    state:=cx.db.readById(stateId(point.id),false)
    return state?.get("enerCubixGenerationLegacyConfig") as Dict
  }

  internal static [Str:Obj?]? loadDb(Folio db, Dict point, DateTime from, DateTime to)
  {
    state:=db.readById(stateId(point.id),false)
    cutover:=state?.get("enerCubixGenerationStart") as DateTime
    if (state == null || cutover == null || to <= cutover) return null
    left:=from > cutover ? from : cutover
    intervals:=[Str:Obj?][,]
    query:=Filter.has("enerCubixIntervalBatch").and(Filter.eq("enerCubixMainRef",point.id)).and(Filter.ge("enerCubixBatchHour",EnerCubixMath.floorHour(left.toTimeZone(TimeZone.utc)))).and(Filter.lt("enerCubixBatchHour",to))
    batches:=db.readAllList(query)
    batches.each |batch|
    {
      hour:=batch["enerCubixBatchHour"] as DateTime
      if (hour == null || hour+1hr <= left || hour >= to) return
      EnerCubixMath.maps(JsonInStream(batch["enerCubixIntervals"].toStr.in).readJson).each |row|
      {
        a:=DateTime.fromIso(row["from"].toStr); b:=DateTime.fromIso(row["to"].toStr)
        if (b > left && a < to) intervals.add(row)
      }
    }
    intervals.sort |a,b| { DateTime.fromIso(a["from"].toStr).ticks <=> DateTime.fromIso(b["from"].toStr).ticks }
    // Explicit gaps prevent post-cutover fallback to a current cumulative sum.
    filled:=[Str:Obj?][,]; cursor:=left
    intervals.each |row|
    {
      a:=DateTime.fromIso(row["from"].toStr); b:=DateTime.fromIso(row["to"].toStr)
      if (a > cursor) filled.add(gap(cursor,a,point.id.id))
      filled.add(row)
      if (b > cursor) cursor=b
    }
    if (cursor < to) filled.add(gap(cursor,to,point.id.id))
    unit:=state["enerCubixArchiveUnit"]?.toStr ?: (point["unit"]?.toStr ?: "")
    return ["pointId":point.id.id,"unit":unit,"mode":"interval","quality":"derived","rawQuality":"ok","cutover":cutover.toIso,"intervals":filled,"sourceIds":[point.id.id],"samples":Obj?[,]]
  }

  internal static Ref stateId(Ref point) { Ref("enerCubix-generation-"+point.id.toBuf.toDigest("SHA-256").toHex[0..<24]) }
  ** Project equipment and its archived formula point share one Ref namespace.
  internal static Ref formulaId(Ref meter)
  {
    point:=Ref("enerCubix-formula-"+meter.id.toBuf.toDigest("SHA-256").toHex[0..<24])
    if (!meter.isProjRec) return point
    prefix:=meter.id[0..<(meter.id.size-meter.toProjRel.id.size)]
    return point.toAbs(prefix)
  }
  internal static Ref usageId(Ref point) { Ref("enerCubix-usage-"+point.id.toBuf.toDigest("SHA-256").toHex[0..<24]) }
  internal static Ref batchId(Ref point, DateTime hour) { Ref("enerCubix-interval-"+(point.id+"|"+hour.ticks).toBuf.toDigest("SHA-256").toHex[0..<24]) }
  internal static Ref minuteBatchId(Ref point, DateTime from) { Ref("enerCubix-interval-minute-"+(point.id+"|"+from.ticks).toBuf.toDigest("SHA-256").toHex[0..<24]) }
  internal static DateTime floorMinute(DateTime at) { DateTime.makeTicks(at.ticks-at.ticks%1min.ticks,at.tz) }
  internal static [Str:Obj?] gap(DateTime from, DateTime to, Str point) { ["from":from.toIso,"to":to.toIso,"value":null,"valueType":"null","quality":"missing","sourceIds":[point]] }
}

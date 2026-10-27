using haystack
using folio
using skyarcd
using util

** Meter-owned interval publication. Values and quality share a Folio publication.
** The companion native history is a mirror; readers never mix uncommitted mirrors.
internal class EnerCubixMeterHistory
{
  ** Legacy archive data is preserved but never used as a report source.
  static [Str:Obj?]? load(Context cx, Dict point, DateTime from, DateTime to) { null }
  static Dict? legacyConfig(Context cx, Dict point) { null }
  internal static [Str:Obj?]? loadDb(Folio db, Dict point, DateTime from, DateTime to) { null }

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

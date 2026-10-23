** Pure business-report boundary. All history access is supplied by the caller.
** Interval histories are start-stamped hourly use; cumulative histories are counters.
class SeedEngine
{
  static Str:Obj? report(Str:Obj? request, [Str:Obj?][] records, [Str:Obj?][] histories)
  {
    SeedForecast.validate(request)
    from:=DateTime.fromIso(request["from"]?.toStr ?: "")
    to:=DateTime.fromIso(request["to"]?.toStr ?: "")
    tzName:=request["tz"]?.toStr
    tz:=tzName == null ? from.tz : TimeZone.fromStr(tzName)
    from=from.toTimeZone(tz); to=to.toTimeZone(tz)
    if (to <= from) throw ArgErr("to must be later than from")
    if ((to-from).ticks/1hr.ticks > 100000) throw ArgErr("Report range exceeds 100000 hours")
    kind:=request["kind"]?.toStr ?: "profile"
    period:=request["period"]?.toStr ?: "day"
    metric:=request["metric"]?.toStr ?: "energy"
    if (!["hour","day","week","month","year"].contains(period)) throw ArgErr("Invalid period")
    if (!["energy","cost","coal","co2","rawcoal","oil"].contains(metric)) throw ArgErr("Invalid metric")
    if (!["profile","ranking","proportion","utility","daily","comparison","primary","cop","leak","workingHours","workingDays","regression","forecast","trend","dashboard"].contains(kind)) throw ArgErr("Invalid report kind")
    if (kind == "forecast") histories=SeedForecast.clip(histories,to)
    if (kind == "comparison" && request["comparisonAlignment"] != null)
    {
      alignment:=request["comparisonAlignment"].toStr
      if (!["duration","calendarMonth"].contains(alignment)) throw ArgErr("Invalid comparison alignment")
      otherFrom:=DateTime.fromIso(request["otherFrom"]?.toStr ?: "").toTimeZone(tz)
      otherTo:=DateTime.fromIso(request["otherTo"]?.toStr ?: "").toTimeZone(tz)
      if (otherTo <= otherFrom || (otherTo-otherFrom).ticks/1hr.ticks > 100000) throw ArgErr("Invalid comparison range")
      if (alignment == "duration")
      {
        if (to-from != otherTo-otherFrom) throw ArgErr("两期必须等长，请重新选择对比开始日期")
        if (!["hour","day","week"].contains(period)) throw ArgErr("等长区间请选择小时、日或周汇总；按月请使用整月对比")
      }
      else if (period != "month" || from != SeedMath.bucket(from,"month") || otherFrom != SeedMath.bucket(otherFrom,"month") || to != SeedMath.nextBucket(from,"month") || otherTo != SeedMath.nextBucket(otherFrom,"month")) throw ArgErr("整月对比必须选择两个完整月份，并按月汇总")
    }
    SeedDimension? dimension:=null
    if (SeedDimension.active(request))
    {
      dimension=SeedDimension(request["dimension"].toStr,records,request["spaceSource"] == "fin")
      records=dimension.records; request=dimension.normalizeRequest(request)
    }
    ctx:=SeedContext(records,histories,tz,dimension)
    if (dimension?.nativeSpace == true) records.findAll |r| { r["nativeSourceMissing"] == true }.each |r| { label:=r["name"] ?: r["id"]; ctx.warn("$label : nativeSourceMissing") }
    selected:=SeedMath.strings(request["nodeIds"]).unique
    if (kind == "comparison" && request["otherFrom"] == null && request["otherTo"] == null) selected=selected.dup.addAll(SeedMath.strings(request["referenceIds"])).unique
    if (selected.isEmpty && kind == "dashboard")
    {
      selected=dimension == null ? records.findAll |r| { r["kind"] == "group" && r["parentId"] == null }.map |r->Str| { r["id"].toStr } : dimension.roots
      if (selected.isEmpty && dimension == null) selected=records.findAll |r| { ctx.included(r) && r["kind"] != "group" && r["parentId"] == null }.map |r->Str| { r["id"].toStr }
    }
    report:=SeedReport(ctx,request,from,to,kind,period,metric)
    if (kind == "trend") return report.trend(selected)
    if (kind == "regression") return report.regression(selected)
    lines:=SeedLine[,]
    selected.each |id|
    {
      record:=ctx.byId[id]
      if (record == null)
      {
        if (kind == "comparison" && ctx.byPoint.containsKey(id)) lines.add(report.referenceLine(id))
        else ctx.warn("Unknown selected node: $id")
        return
      }
      if (record["kind"] == "nativePoint") throw ArgErr("FIN 原生点位仅用于空间浏览，请先绑定计量档案")
      if (kind == "forecast" && ["sensor","cop","binding"].contains(record["kind"]?.toStr ?: "")) throw ArgErr("请选择能耗表计或空间、组织范围进行预测")
      if (dimension != null && ["space","organization","group"].contains(record["kind"]?.toStr ?: "") && !dimension.scope(id)) throw ArgErr("Selected node does not belong to the report dimension")
      if (kind == "utility")
      {
        if (dimension != null)
        {
          if (!dimension.utilityAllowed(id)) throw ArgErr("Utility analysis supports only root and first-level dimension scopes")
        }
        else
        {
          if (record["kind"] != "group") throw ArgErr("Utility analysis requires a group")
          parent:=ctx.byId[record["parentId"]?.toStr ?: ""]
          if (parent != null && parent["parentId"] != null) throw ArgErr("Utility analysis supports only root and first-level groups")
        }
      }
      if (dimension != null && kind == "leak" && !["meter","totalMeter"].contains(record["kind"]?.toStr ?: "")) throw ArgErr("Leak analysis requires a master meter")
      cats:=ctx.categories(id)
      if (cats.isEmpty) cats=[""]
      cats.each |cat|
      {
        if (kind == "utility")
        {
          utilities:=ctx.utilities(id,cat)
          utilities.each |u| { lines.add(report.line(id,cat,u)) }
        }
        else lines.add(report.line(id,cat))
      }
    }
    if (kind == "profile") SeedMath.strings(request["referenceIds"]).unique.each |id| { lines.add(report.referenceLine(id,true)) }
    if (kind == "forecast") return report.forecast(lines)
    return report.finish(lines)
  }
}

internal class SeedTick
{
  new make(DateTime ts, DateTime end, SeedValue value, SeedValue? numerator := null, SeedValue? denominator := null)
  { this.ts=ts; this.end=end; this.value=value; this.numerator=numerator; this.denominator=denominator }
  DateTime ts
  DateTime end
  SeedValue value
  SeedValue? numerator
  SeedValue? denominator
}

internal class SeedLine
{
  new make(Str id, Str nodeId, Str name, Str category, Str unit)
  { this.id=id; this.nodeId=nodeId; this.name=name; this.category=category; this.unit=unit }
  Str id
  Str nodeId
  Str name
  Str category
  Str unit
  Bool gauge := false
  Bool ratio := false
  Bool leak := false
  Bool reference := false
  SeedTick[] ticks := [,]

  SeedValue total(SeedTick[] values := ticks)
  {
    if (ratio) return SeedValue.divide(SeedValue.sum(values.map |t->SeedValue| { t.numerator ?: SeedValue() }),SeedValue.sum(values.map |t->SeedValue| { t.denominator ?: SeedValue() }))
    if (gauge && !values.isEmpty)
    {
      duration:=0f
      weighted:=values.map |t->SeedValue| { duration+=(t.end-t.ts).ticks.toFloat; return t.value.scale((t.end-t.ts).ticks.toFloat) }
      return SeedValue.sum(weighted).scale(1f/duration)
    }
    return SeedValue.sum(values.map |t->SeedValue| { t.value })
  }
}



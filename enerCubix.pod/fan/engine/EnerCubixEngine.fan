** Pure business-report boundary. All history access is supplied by the caller.
** Interval histories are start-stamped hourly use; cumulative histories are counters.
class EnerCubixEngine
{
  static Str:Obj? report(Str:Obj? request, [Str:Obj?][] records, [Str:Obj?][] histories)
  {
    current:=request.dup
    ["meterHistorySegments","legacyMembership","leakSegment"].each |key| { current.remove(key) }
    return run(current,records,histories,false)
  }

  internal static Str:Obj? reportSection(Str:Obj? request, [Str:Obj?][] records, [Str:Obj?][] histories)
  { run(request,records,histories,true) }

  private static Str:Obj? run(Str:Obj? request, [Str:Obj?][] records, [Str:Obj?][] histories, Bool section)
  {
    // One cutoff is shared by all nested reports and temporal sections. Query
    // bounds remain the user's selection, including missing and future buckets.
    cutoff:=EnerCubixKnownUsage.cutoff(request)
    frozen:=request.dup.set("asOf",cutoff.toIso)
    if (EnerCubixComparisonScope.active(frozen)) frozen["_comparisonScope"]=EnerCubixComparisonScope.of(frozen,records)
    clipped:=EnerCubixKnownUsage.clip(histories,cutoff)
    result:=calculate(frozen,records,clipped,section)
    if (frozen["kind"] == "leak" && !section && EnerCubixDimension.active(frozen))
      EnerCubixLeakUsage.attach(result,frozen,records,clipped)
    extra:=(Str:Obj?)(result["extra"] ?: Str:Obj?[:])
    extra["relationBasis"]="current"
    comparison:=frozen["_comparisonScope"] as EnerCubixComparisonScope
    if (comparison != null) extra["comparisonScopes"]=comparison.snapshots
    result["extra"]=extra
    result["asOf"]=cutoff.toIso
    return result
  }

  private static Str:Obj? calculate(Str:Obj? request, [Str:Obj?][] records, [Str:Obj?][] histories, Bool section)
  {
    if (request["kind"] == "energyFlow") records=EnerCubixEnergyFlow.normalizeRecords(records)
    request=flowScope(request,records)
    EnerCubixForecast.validate(request)
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
    if (!["profile","ranking","proportion","utility","daily","comparison","primary","cop","leak","workingHours","workingDays","regression","forecast","trend","dashboard","energyFlow"].contains(kind)) throw ArgErr("Invalid report kind")
    if (request["flowMode"] != null && !["relations","endUse"].contains(request["flowMode"])) throw ArgErr("endUseInvalidMode")
    if (kind == "forecast") histories=EnerCubixForecast.clip(histories,to)
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
      else if (period != "month" || from != EnerCubixMath.bucket(from,"month") || otherFrom != EnerCubixMath.bucket(otherFrom,"month") || to != EnerCubixMath.nextBucket(from,"month") || otherTo != EnerCubixMath.nextBucket(otherFrom,"month")) throw ArgErr("整月对比必须选择两个完整月份，并按月汇总")
    }
    EnerCubixDimension? dimension:=null
    if (EnerCubixDimension.active(request))
    {
      dimension=EnerCubixDimension(request["dimension"].toStr,records,request["spaceSource"] == "fin")
      records=dimension.records; request=dimension.normalizeRequest(request)
    }
    ctx:=EnerCubixContext(records,histories,tz,dimension)
    ctx.comparison=request["_comparisonScope"] as EnerCubixComparisonScope
    if (kind == "energyFlow") return EnerCubixEnergyFlow(ctx,request,from,to,histories).report
    if (dimension?.nativeSpace == true) records.findAll |r| { r["nativeSourceMissing"] == true }.each |r| { label:=r["name"] ?: r["id"]; ctx.warn("$label : nativeSourceMissing") }
    selected:=EnerCubixMath.strings(request["nodeIds"]).unique
    if (kind == "comparison" && request["otherFrom"] == null && request["otherTo"] == null) selected=selected.dup.addAll(EnerCubixMath.strings(request["referenceIds"])).unique
    if (selected.isEmpty && kind == "dashboard")
    {
      selected=dimension == null ? records.findAll |r| { r["kind"] == "group" && r["parentId"] == null }.map |r->Str| { r["id"].toStr } : dimension.roots
      if (selected.isEmpty && dimension == null) selected=records.findAll |r| { ctx.included(r) && r["kind"] != "group" && r["parentId"] == null }.map |r->Str| { r["id"].toStr }
    }
    report:=EnerCubixReport(ctx,request,from,to,kind,period,metric)
    if (kind == "trend") return report.trend(selected)
    if (kind == "regression") return report.regression(selected)
    lines:=EnerCubixLine[,]
    if (kind == "utility")
    {
      EnerCubixEndUse.resolve(ctx,selected).each |meter| {lines.add(report.line(meter["id"].toStr,meter["categoryId"] as Str ?: ""))}
      return report.finish(lines)
    }
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
      if (dimension != null && kind == "leak" && !["meter","totalMeter"].contains(record["kind"]?.toStr ?: "")) throw ArgErr("Leak analysis requires a master meter")
      cats:=ctx.categories(id)
      if (cats.isEmpty) cats=[""]
      cats.each |cat|
      {
        lines.add(report.line(id,cat))
      }
    }
    if (kind == "profile") EnerCubixMath.strings(request["referenceIds"]).unique.each |id| { lines.add(report.referenceLine(id,true)) }
    if (kind == "forecast") return report.forecast(lines)
    return report.finish(lines)
  }

  internal static Str:Obj? flowScope(Str:Obj? request, [Str:Obj?][] records)
  {
    if (request["kind"] != "energyFlow" || request["scopeNodeIds"] isnot List) return request
    ids:=EnerCubixMath.strings(request["scopeNodeIds"])
    out:=request.dup; out.remove("scopeNodeIds"); out.remove("scopeDimension")
    if (ids.isEmpty) return out
    dimension:=request["scopeDimension"] as Str ?: "metering"
    if (!["metering","space","organization"].contains(dimension)) throw ArgErr("Invalid report dimension")
    out["dimension"]=dimension
    out["nodeIds"]=ids
    out["selectionScope"]=["dimension":dimension,"nodeIds":ids]
    return out
  }
}

internal class EnerCubixTick
{
  new make(DateTime ts, DateTime end, EnerCubixValue value, EnerCubixValue? numerator := null, EnerCubixValue? denominator := null)
  { this.ts=ts; this.end=end; this.value=value; this.numerator=numerator; this.denominator=denominator }
  DateTime ts
  DateTime end
  EnerCubixValue value
  EnerCubixValue? numerator
  EnerCubixValue? denominator
  EnerCubixValue? known
}

internal class EnerCubixLine
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
  Str balanceMode := "independent"
  Bool reference := false
  Str? utility
  EnerCubixTick[] ticks := [,]

  EnerCubixValue knownTotal(EnerCubixTick[] values := ticks)
  { EnerCubixKnownUsage.combine(values.map |t->EnerCubixValue| { t.known ?: EnerCubixValue() }) }

  EnerCubixValue total(EnerCubixTick[] values := ticks)
  {
    if (ratio) return EnerCubixValue.divide(EnerCubixValue.sum(values.map |t->EnerCubixValue| { t.numerator ?: EnerCubixValue() }),EnerCubixValue.sum(values.map |t->EnerCubixValue| { t.denominator ?: EnerCubixValue() }))
    if (gauge && !values.isEmpty)
    {
      incomplete:=values.find |t| { !t.value.reliable }
      if (incomplete != null) return EnerCubixValue(null,incomplete.value.quality,incomplete.value.sources)
      duration:=0f
      weighted:=values.map |t->EnerCubixValue| { duration+=(t.end-t.ts).ticks.toFloat; return t.value.scale((t.end-t.ts).ticks.toFloat) }
      return EnerCubixValue.sum(weighted).scale(1f/duration)
    }
    return EnerCubixValue.sum(values.map |t->EnerCubixValue| { t.value })
  }
}



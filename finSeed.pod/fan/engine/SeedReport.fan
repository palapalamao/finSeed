internal class SeedReport
{
  new make(SeedContext ctx, Str:Obj? request, DateTime from, DateTime to, Str kind, Str period, Str metric)
  { this.ctx=ctx; this.request=request; this.from=from; this.to=to; this.kind=kind; this.period=period; this.metric=metric }
  private SeedContext ctx
  private Str:Obj? request
  private DateTime from
  private DateTime to
  private Str kind
  private Str period
  private Str metric
  private [Str:Obj?][] series := [,]
  private [Str:Obj?][] rows := [,]
  private Str:Obj? summary := [:]
  private Str:Obj? extra := [:]

  SeedLine line(Str id, Str category, Str? utility := null, DateTime start := from, DateTime end := to)
  {
    r:=ctx.byId[id]
    name:=r?.get("name")?.toStr ?: id
    if (utility != null) name+=" / "+(ctx.byId[utility]?.get("name")?.toStr ?: (ctx.dimension == null ? "Unassigned" : "未指定用途"))
    out:=SeedLine("$id|$category"+(utility == null ? "" : "|$utility"),id,name,category,ctx.unit(id,category,metric))
    out.gauge=r?.get("kind") == "sensor"
    out.ratio=kind == "cop" || r?.get("kind") == "cop"
    out.leak=kind == "leak"
    if (out.ratio) out.unit="COP"
    Str? directQuality:=null
    if (ctx.dimension != null && out.leak) directQuality=ctx.dimension.leakQuality(id)
    else if (ctx.dimension?.dimension == "organization" && r != null && ["meter","totalMeter"].contains(r["kind"]?.toStr ?: "")) directQuality=ctx.dimension.quality([r])
    cursor:=start
    while (cursor < end)
    {
      next:=SeedMath.floorHour(cursor)+1hr
      if (next > end) next=end
      SeedValue value := SeedValue()
      SeedValue? numerator:=null; SeedValue? denominator:=null
      if (out.ratio)
      {
        if (r?.get("kind") != "cop") value=SeedValue(null,"missingCopDefinition")
        else
        {
          numerator=ctx.nodeTotal(r["numeratorId"]?.toStr ?: "",cursor,next)
          denominator=ctx.nodeTotal(r["denominatorId"]?.toStr ?: "",cursor,next)
          value=SeedValue.divide(numerator,denominator)
        }
      }
      else if (out.leak)
      {
        if (ctx.dimension != null)
        {
          members:=ctx.dimension.directChildren(id).findAll |m| { (m["categoryId"]?.toStr ?: "") == category }
          numerator=ctx.node(id,category,cursor,next,metric)
          denominator=members.isEmpty ? SeedValue(null,"missingBranches") : SeedValue.sum(members.map |m->SeedValue| { ctx.node(m["id"].toStr,category,cursor,next,metric) })
          value=SeedValue.sum([numerator,denominator.scale(-1f)])
          if (directQuality != null) value=SeedValue(null,directQuality,value.sources)
        }
        else if (r?.get("kind") != "group") value=SeedValue(null,"groupRequired")
        else
        {
          masters:=(ctx.children[id] ?: [Str:Obj?][,]).findAll |m| { m["kind"] == "totalMeter" && (m["categoryId"]?.toStr ?: "") == category && ctx.included(m) }
          numerator=masters.size == 1 ? ctx.node(masters.first["id"].toStr,category,cursor,next,metric) : SeedValue(null,masters.isEmpty ? "missingMaster" : "ambiguousMaster")
          denominator=ctx.branch(id,category,cursor,next,metric)
          value=SeedValue.sum([numerator,denominator.scale(-1f)])
        }
      }
      else
      {
        value=ctx.node(id,category,cursor,next,metric,Str[,],utility)
        if (directQuality != null) value=SeedValue(null,directQuality,value.sources)
      }
      if (request["perArea"] == true)
      {
        area:=SeedMath.num(r?.get("area"))
        if (out.ratio) ctx.warn("COP is a ratio; per-area normalization does not apply")
      else if (area == null || area <= 0f)
      {
        value=SeedValue(null,"missingArea",value.sources)
        if (numerator != null) numerator=SeedValue(null,"missingArea",numerator.sources)
        if (denominator != null) denominator=SeedValue(null,"missingArea",denominator.sources)
      }
        else
        {
          value=value.scale(1f/area)
          numerator=numerator?.scale(1f/area); denominator=denominator?.scale(1f/area)
        }
      }
      if (value.value == null) ctx.warn("${out.name}: ${value.quality}")
      out.ticks.add(SeedTick(cursor,next,value,numerator,denominator)); cursor=next
    }
    if (request["perArea"] == true && !out.ratio) out.unit+="/m²"
    return out
  }

  SeedLine referenceLine(Str id, Bool raw := false)
  {
    record:=ctx.byId[id]
    point:=record?.get("pointId")?.toStr ?: id
    history:=ctx.byPoint[point]
    out:=SeedLine(id+(raw ? "|reference" : ""),id,ctx.displayName(id),"",history?.unit ?: "")
    out.gauge=raw || history == null || history.mode == "sampled" || history.mode == "cov"
    out.reference=raw
    cursor:=from
    while (cursor < to)
    {
      next:=SeedMath.floorHour(cursor)+1hr; if (next > to) next=to
      value:=history?.read(cursor,next,raw) ?: SeedValue()
      if (value.value == null) ctx.warn("${out.name}: ${value.quality}")
      out.ticks.add(SeedTick(cursor,next,value)); cursor=next
    }
    return out
  }

  Str:Obj? finish(SeedLine[] lines)
  {
    if (kind == "ranking" || kind == "proportion") totals(lines)
    else if (kind == "workingHours" || kind == "workingDays") working(lines)
    else if (kind == "daily") daily(lines)
    else
    {
      lines.each |l| { append(l,period) }
      if (kind == "utility") utilityShares(lines)
      if (kind == "comparison") comparePeriods(lines)
      if (kind == "dashboard") dashboard(lines)
    }
    summary["totals"]=lines.findAll |l| { !l.reference }.map |l->[Str:Obj?]|
    {
      value:=l.total
      return ["id":l.id,"name":l.name,"categoryId":l.category,"value":value.value,"quality":value.quality,"unit":l.unit,"sourceIds":value.sources]
    }
    if (ctx.dimension != null) dimensionDetails(lines)
    return result
  }

  private Void dimensionDetails(SeedLine[] lines)
  {
    details:=[Str:Obj?][,]; seen:=Str[,]
    lines.each |l|
    {
      if (l.reference) return
      members:=ctx.dimension.members(l.nodeId)
      own:=ctx.byId[l.nodeId]
      if (members.isEmpty && own != null && ["meter","totalMeter"].contains(own["kind"]?.toStr ?: "")) members=[own]
      if (kind == "leak")
      {
        members=ctx.dimension.directChildren(l.nodeId).dup
        if (own != null) members.insert(0,own)
      }
      counted:=(kind == "utility" ? ctx.dimension.usageFrontier(members) : ctx.dimension.frontier(members)).map |m->Str| { m["id"].toStr }
      members.each |m|
      {
        id:=m["id"].toStr; key:="${l.nodeId}|$id"
        if (seen.contains(key)) return
        seen.add(key)
        category:=m["categoryId"]?.toStr ?: ""
        value:=meterTotal(id,category)
        details.add(["scopeId":l.nodeId,"nodeId":id,"name":ctx.displayName(id),"categoryId":category,"value":value.value,"quality":value.quality,"unit":ctx.unit(id,category,metric),"sourceIds":value.sources,"counted":counted.contains(id)])
      }
    }
    extra["details"]=details
  }

  private SeedValue meterTotal(Str id, Str category)
  {
    values:=SeedValue[,]; cursor:=from
    while (cursor < to)
    {
      end:=SeedMath.floorHour(cursor)+1hr; if (end > to) end=to
      values.add(ctx.node(id,category,cursor,end,metric)); cursor=end
    }
    return SeedValue.sum(values)
  }

  private Void utilityShares(SeedLine[] lines)
  {
    grouped:=Str:SeedValue[][:]
    lines.each |l|
    {
      key:="${l.nodeId}|${l.category}|${l.unit}"
      if (!grouped.containsKey(key)) grouped[key]=SeedValue[,]
      grouped[key].add(l.total)
    }
    shares:=[Str:Obj?][,]
    lines.each |l|
    {
      key:="${l.nodeId}|${l.category}|${l.unit}"
      value:=l.total
      percentage:=SeedValue.divide(value,SeedValue.sum(grouped[key])).scale(100f)
      shares.add(["id":l.id,"name":l.name,"nodeId":l.nodeId,"categoryId":l.category,"unit":l.unit,"value":value.value,"percentage":percentage.value,"quality":SeedValue.worse(value.quality,percentage.quality),"sourceIds":value.sources])
    }
    extra["utilityShares"]=shares
    if (ctx.dimension != null)
    {
      scopeTotals:=[Str:Obj?][,]
      grouped.each |values,key|
      {
        representative:=lines.find |l| { "${l.nodeId}|${l.category}|${l.unit}" == key }
        if (representative == null) return
        total:=meterTotal(representative.nodeId,representative.category)
        if (request["perArea"] == true)
        {
          area:=SeedMath.num(ctx.byId[representative.nodeId]?.get("area"))
          total=area == null || area <= 0f ? SeedValue(null,"missingArea",total.sources) : total.scale(1f/area)
        }
        measured:=SeedValue.sum(values)
        if (total.value == null || measured.value == null || (total.value-measured.value).abs > 0.000001f) ctx.warn("${ctx.displayName(representative.nodeId)}: 分项覆盖不完整")
        scopeTotals.add(["nodeId":representative.nodeId,"categoryId":representative.category,"value":total.value,"quality":total.quality,"unit":representative.unit,"sourceIds":total.sources])
      }
      extra["scopeTotals"]=scopeTotals
    }
  }

  private Void append(SeedLine l, Str gran)
  {
    grouped:=Str:SeedTick[][:]; order:=Str[,]; timestamps:=Str:DateTime[:]
    l.ticks.each |t|
    {
      at:=SeedMath.bucket(t.ts,gran); key:=at.toIso
      if (!grouped.containsKey(key)) { grouped[key]=SeedTick[,]; order.add(key); timestamps[key]=at }
      grouped[key].add(t)
    }
    points:=[Str:Obj?][,]
    order.each |key|
    {
      ticks:=grouped[key]; v:=l.total(ticks); at:=timestamps[key]
      p:=v.point(at); points.add(p)
      row:=baseRow(l,key,v); row["ts"]=key
      if (l.leak)
      {
        total:=SeedValue.sum(ticks.map |t->SeedValue| { t.numerator ?: SeedValue() })
        sub:=SeedValue.sum(ticks.map |t->SeedValue| { t.denominator ?: SeedValue() })
        row["total"]=total.value; row["submeter"]=sub.value; row["difference"]=v.value
        row["percentage"]=SeedValue.divide(v,total).scale(100f).value
      }
      rows.add(row)
    }
    series.add(seriesMap(l,points))
  }

  private Void totals(SeedLine[] lines)
  {
    order:=lines.dup.sort |a,b| { (b.total.value ?: Float.negInf) <=> (a.total.value ?: Float.negInf) }
    totals:=Str:SeedValue[][:]
    lines.each |l|
    {
      key:="${l.category}|${l.unit}"
      if (!totals.containsKey(key)) totals[key]=SeedValue[,]
      totals[key].add(l.total)
    }
    ranks:=Str:Int[:]
    order.each |l|
    {
      v:=l.total; key:="${l.category}|${l.unit}"
      denom:=SeedValue.sum(totals[key]); rank:=(ranks[key] ?: 0)+1; ranks[key]=rank
      row:=baseRow(l,"total",v); row["rank"]=rank
      row["percentage"]=SeedValue.divide(v,denom).scale(100f).value
      rows.add(row)
      series.add(seriesMap(l,[v.point(from)]))
    }
  }

  private Void daily(SeedLine[] lines)
  {
    calendar:=ctx.calendar
    if (calendar == null) ctx.warn("未配置日历，无法划分峰谷平时段")
    bandOf:=|Int hour->Str|
    {
      if (calendar == null) return "unknown"
      if (SeedMath.containsNum(calendar["peakHours"],hour)) return "peak"
      if (SeedMath.containsNum(calendar["valleyHours"],hour)) return "valley"
      return "flat"
    }
    loadBands:=[Str:Obj?][,]
    lines.each |l|
    {
      grouped:=Int:SeedTick[][:]
      l.ticks.each |t| { if (!grouped.containsKey(t.ts.hour)) grouped[t.ts.hour]=SeedTick[,]; grouped[t.ts.hour].add(t) }
      points:=[Str:Obj?][,]
      (0..23).each |hour|
      {
        ticks:=grouped[hour] ?: SeedTick[,]
        v:=l.total(ticks)
        if (!l.ratio && !l.gauge && !ticks.isEmpty) v=v.scale(1f/ticks.size.toFloat)
        at:=from.date.toDateTime(Time(hour,0),ctx.tz)
        band:=bandOf(hour)
        point:=v.point(at); point["band"]=band; points.add(point)
        row:=baseRow(l,"hour:$hour",v); row["hour"]=hour; row["ts"]=at.toIso; row["samples"]=ticks.size; row["band"]=band; rows.add(row)
      }
      series.add(seriesMap(l,points))
      bands:=calendar == null ? ["unknown"] : ["peak","valley","flat"]
      bands.each |band|
      {
        ticks:=l.ticks.findAll |t| { bandOf(t.ts.hour) == band }
        total:=ticks.isEmpty ? SeedValue(0f,"ok") : SeedValue.sum(ticks.map |t->SeedValue| { t.value })
        if (!ticks.isEmpty && (l.gauge || l.ratio))
        {
          total=SeedValue(null,"invalidMetric",total.sources)
          ctx.warn("${l.name}: 峰谷平区间总量需要能耗计量数据")
        }
        row:=baseRow(l,"band:$band",total); row["band"]=band; loadBands.add(row)
      }
    }
    extra["aggregation"]="mean energy for each hour of day"
    extra["loadBands"]=loadBands
    extra["loadBandsAggregation"]="intervalTotal"
  }

  private Void working(SeedLine[] lines)
  {
    available:=kind == "workingHours" ? (request["workHours"] ?: ctx.calendar?.get("workHours")) != null : ctx.calendar?.get("workDays") != null
    if (!available) ctx.warn("Work calendar is required")
    lines.each |l|
    {
      work:=l.ticks.findAll |t| { ctx.working(t.ts,kind == "workingHours",request["workHours"]) }
      off:=l.ticks.findAll |t| { !ctx.working(t.ts,kind == "workingHours",request["workHours"]) }
      a:=!available ? SeedValue(null,"missingCalendar") : l.total(work)
      b:=!available ? SeedValue(null,"missingCalendar") : l.total(off)
      if (available && work.isEmpty) a=SeedValue(0f,"ok")
      if (available && off.isEmpty) b=SeedValue(0f,"ok")
      row:=baseRow(l,"working",l.total); row["working"]=a.value; row["nonworking"]=b.value
      row["workingPercentage"]=SeedValue.divide(a,SeedValue.sum([a,b])).scale(100f).value
      row["workingQuality"]=a.quality; row["nonworkingQuality"]=b.quality
      rows.add(row)
      points:=[a.point(from),b.point(from)]
      points[0]["label"]="working"; points[1]["label"]="nonworking"
      series.add(seriesMap(l,points))
    }
  }

  private Void comparePeriods(SeedLine[] lines)
  {
    otherFrom:=request["otherFrom"]?.toStr; otherTo:=request["otherTo"]?.toStr
    if (otherFrom == null && otherTo == null)
    {
      comparisons:=[Str:Obj?][,]
      if (!lines.isEmpty)
      {
        base:=lines.first
        lines.each |l,i|
        {
          if (i == 0 || l.unit != base.unit || l.category != base.category) return
          current:=l.total; previous:=base.total; diff:=SeedValue.sum([current,previous.scale(-1f)])
          comparisons.add(["id":l.id,"name":l.name,"referenceName":base.name,"current":current.value,"reference":previous.value,"difference":diff.value,"percentage":SeedValue.divide(diff,previous).scale(100f).value,"quality":diff.quality,"unit":l.unit])
        }
      }
      extra["comparisons"]=comparisons
      return
    }
    if (otherFrom == null || otherTo == null) throw ArgErr("Both comparison boundaries are required")
    start:=DateTime.fromIso(otherFrom).toTimeZone(ctx.tz); end:=DateTime.fromIso(otherTo).toTimeZone(ctx.tz)
    if (end <= start) throw ArgErr("Invalid comparison range")
    comparisons:=[Str:Obj?][,]
    lines.each |l|
    {
      base:=line(l.nodeId,l.category,null,start,end)
      current:=l.total; previous:=base.total
      diff:=SeedValue.sum([current,previous.scale(-1f)])
      comparisons.add(["id":l.id,"name":l.name,"current":current.value,"reference":previous.value,"difference":diff.value,"percentage":SeedValue.divide(diff,previous).scale(100f).value,"quality":diff.quality,"unit":l.unit])
      base.id+="|reference"; base.name+=" (reference)"; append(base,period)
    }
    extra["comparisons"]=comparisons
  }

  private Void dashboard(SeedLine[] lines)
  {
    totals:=Str:SeedValue[][:]
    byUnit:=Str:SeedValue[][:]
    lines.each |l|
    {
      key:="${l.category}|${l.unit}"
      if (!totals.containsKey(key)) totals[key]=SeedValue[,]
      if (!byUnit.containsKey(l.unit)) byUnit[l.unit]=SeedValue[,]
      value:=l.total
      totals[key].add(value); byUnit[l.unit].add(value)
    }
    if (ctx.dimension != null)
    {
      // Independent scope series may overlap; their overall total uses one union.
      candidates:=[Str:Obj?][,]; seen:=Str[,]
      lines.each |l|
      {
        own:=ctx.byId[l.nodeId]
        members:=ctx.dimension.scope(l.nodeId) ? ctx.dimension.members(l.nodeId) : (own == null || !["meter","totalMeter"].contains(own["kind"]?.toStr ?: "") || !ctx.included(own) ? [Str:Obj?][,] : [own])
        members.each |m| { id:=m["id"].toStr; if (!seen.contains(id)) { seen.add(id); candidates.add(m) } }
      }
      totals=Str:SeedValue[][:]; byUnit=Str:SeedValue[][:]
      SeedValue? area:=null
      if (request["perArea"] == true)
      {
        area=ctx.dimension.selectionArea(lines.findAll |l| { !l.reference }.map |l->Str| { l.nodeId })
        extra["normalizationArea"]=["value":area.value,"quality":area.quality,"unit":"m²"]
        if (area.value == null) ctx.warn("所选对象合计: ${area.quality}")
      }
      cats:=candidates.map |m->Str| { m["categoryId"]?.toStr ?: "" }.unique.sort
      cats.each |category|
      {
        members:=candidates.findAll |m| { (m["categoryId"]?.toStr ?: "") == category }
        values:=ctx.dimension.frontier(members).map |m->SeedValue| { meterTotal(m["id"].toStr,category) }
        value:=SeedValue.sum(values); quality:=ctx.dimension.quality(members)
        if (quality != null) { value=SeedValue(null,quality,value.sources); ctx.warn("所选对象合计: $quality") }
        unit:=ctx.unit(members.first["id"].toStr,category,metric)
        if (area != null)
        {
          value=area.value == null ? SeedValue(null,area.quality,value.sources) : value.scale(1f/area.value)
          unit+="/m²"
        }
        key:="$category|$unit"
        totals[key]=[value]
        if (!byUnit.containsKey(unit)) byUnit[unit]=SeedValue[,]
        byUnit[unit].add(value)
      }
    }
    overview:=[Str:Obj?][,]
    totals.each |values,key| { v:=SeedValue.sum(values); overview.add(["key":key,"value":v.value,"quality":v.quality,"sourceIds":v.sources]) }
    extra["overview"]=overview
    name:=metric == "cost" ? "总费用" : (metric == "co2" ? "总CO₂" : "所选对象合计")
    grandTotals:=[Str:Obj?][,]
    byUnit.keys.sort.each |unit|
    {
      value:=SeedValue.sum(byUnit[unit])
      grandTotals.add(["key":"$metric|$unit","name":name,"unit":unit,"value":value.value,"quality":value.quality,"sourceIds":value.sources])
    }
    extra["grandTotals"]=grandTotals
    if (request["otherFrom"] != null) comparePeriods(lines)
  }

  Str:Obj? trend(Str[] selected)
  {
    ids:=selected.dup.addAll(SeedMath.strings(request["referenceIds"])).unique
    ids.each |id|
    {
      r:=ctx.byId[id]
      point:=r?.get("pointId")?.toStr ?: id
      h:=ctx.byPoint[point]
      name:=ctx.displayName(id)
      rawUnit:=r?.get("unit")?.toStr ?: (h?.unit ?: "")
      l:=SeedLine(id,id,name,r?.get("categoryId")?.toStr ?: "",rawUnit)
      points:=[Str:Obj?][,]
      if (h == null || h.samples.isEmpty) ctx.warn("$name: missing history")
      else h.samples.each |s|
      {
        if (s.ts < from || s.ts >= to) return
        q:=s.value == null ? "missing" : h.quality
        available:=q == "ok" || q == "derived" || q == "estimated"
        v:=SeedValue(available ? s.value : null,q,[point]); p:=v.point(s.ts.toTimeZone(ctx.tz)); points.add(p)
        row:=baseRow(l,s.ts.toIso,v); row["ts"]=p["ts"]; rows.add(row)
      }
      series.add(seriesMap(l,points))
    }
    extra["aggregation"]="raw samples"
    return result
  }

  Str:Obj? regression(Str[] selected)
  {
    x:=request["xId"]?.toStr; y:=request["yId"]?.toStr
    if (x == null || y == null) { ctx.warn("Regression requires xId and yId"); return result }
    xs:=Float[,]; ys:=Float[,]; points:=[Str:Obj?][,]
    cursor:=from
    while (cursor < to)
    {
      end:=SeedMath.nextBucket(SeedMath.bucket(cursor,period),period); if (end > to) end=to
      a:=regressionBucket(x,cursor,end); b:=regressionBucket(y,cursor,end)
      if (a.value != null && b.value != null)
      {
        xs.add(a.value); ys.add(b.value)
        point:=b.point(cursor); point["x"]=a.value; point["quality"]=SeedValue.worse(a.quality,b.quality); point["sourceIds"]=a.sources.dup.addAll(b.sources).unique
        points.add(point)
        rows.add(["key":cursor.toIso,"ts":cursor.toIso,"x":a.value,"y":b.value,"value":b.value,"quality":point["quality"],"sourceIds":point["sourceIds"]])
      }
      else ctx.warn("Regression omitted incomplete pair: ${cursor.toIso}")
      cursor=end
    }
    extra=SeedMath.regression(xs,ys)
    xName:=ctx.displayName(x); yName:=ctx.displayName(y)
    extra["xName"]=xName; extra["yName"]=yName
    fitLine:=[Str:Obj?][,]
    slope:=SeedMath.num(extra["slope"]); intercept:=SeedMath.num(extra["intercept"])
    if (slope != null && intercept != null && !xs.isEmpty)
    {
      low:=(Float)xs.min; high:=(Float)xs.max
      lowY:=SeedMath.num(slope*low+intercept); highY:=SeedMath.num(slope*high+intercept)
      if (high > low && lowY != null && highY != null) fitLine.add(["x":low,"y":lowY]).add(["x":high,"y":highY])
    }
    extra["fitLine"]=fitLine
    if (extra["slope"] == null) ctx.warn("Regression requires at least two valid pairs with varying x")
    series.add(["id":"regression","name":"$yName vs $xName","unit":"","points":points])
    return result
  }

  private SeedValue regressionValue(Str id, DateTime start, DateTime end)
  {
    if (ctx.byId.containsKey(id))
    {
      value:=ctx.nodeTotal(id,start,end)
      r:=ctx.byId[id]
      if (ctx.dimension?.dimension == "organization" && ["meter","totalMeter"].contains(r["kind"]?.toStr ?: ""))
      {
        quality:=ctx.dimension.quality([r]); if (quality != null) return SeedValue(null,quality,value.sources)
      }
      return value
    }
    return ctx.byPoint[id]?.read(start,end,true) ?: SeedValue()
  }

  private SeedValue regressionBucket(Str id, DateTime start, DateTime end)
  {
    values:=SeedValue[,]; cursor:=start
    while (cursor < end)
    {
      next:=SeedMath.floorHour(cursor)+1hr; if (next > end) next=end
      values.add(regressionValue(id,cursor,next)); cursor=next
    }
    total:=SeedValue.sum(values)
    isGauge:=!ctx.byId.containsKey(id) || ctx.byId[id]["kind"] == "sensor"
    return isGauge && !values.isEmpty ? total.scale(1f/values.size.toFloat) : total
  }

  private Str:Obj? seriesMap(SeedLine l, [Str:Obj?][] points)
  { ["id":l.id,"nodeId":l.nodeId,"name":l.name,"categoryId":l.category,"unit":l.unit,"points":points] }

  private Str:Obj? baseRow(SeedLine l, Str key, SeedValue v)
  { ["key":"${l.id}|$key","nodeId":l.nodeId,"name":l.name,"categoryId":l.category,"unit":l.unit,"value":v.value,"quality":v.quality,"sourceIds":v.sources] }

  private Str:Obj? result()
  {
    if (ctx.dimension != null) extra["dimension"]=ctx.dimension.dimension
    return ["kind":kind,"from":from.toIso,"to":to.toIso,"period":period,"series":series,"rows":rows,"warnings":ctx.warnings,"summary":summary,"extra":extra]
  }
}





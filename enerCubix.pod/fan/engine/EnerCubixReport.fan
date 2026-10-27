internal class EnerCubixReport
{
  new make(EnerCubixContext ctx, Str:Obj? request, DateTime from, DateTime to, Str kind, Str period, Str metric)
  {
    this.ctx=ctx; this.request=request; this.from=from; this.to=to; this.kind=kind; this.period=period; this.metric=metric
    dataCutoff=EnerCubixKnownUsage.cutoff(request)
    if (EnerCubixKnownUsage.supported(kind,metric))
    {
      knownCtx=EnerCubixContext.known(ctx,to < dataCutoff ? to : dataCutoff)
    }
  }
  private EnerCubixContext ctx
  private EnerCubixContext? knownCtx
  private DateTime dataCutoff
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

  EnerCubixLine line(Str id, Str category, Str? utility := null, DateTime start := from, DateTime end := to)
  {
    r:=ctx.byId[id]
    name:=r?.get("name")?.toStr ?: id
    if (utility != null) name+=" / "+(ctx.byId[utility]?.get("name")?.toStr ?: (ctx.dimension == null ? "Unassigned" : "未指定分项"))
    out:=EnerCubixLine("$id|$category"+(utility == null ? "" : "|$utility"),id,name,category,ctx.unit(id,category,metric))
    out.utility=utility
    activeKnown:=knownCtx
    if (knownCtx != null && end != to) activeKnown=EnerCubixContext.known(ctx,end < dataCutoff ? end : dataCutoff)
    out.gauge=r?.get("kind") == "sensor"
    out.ratio=kind == "cop" || r?.get("kind") == "cop"
    out.leak=kind == "leak"
    if (out.leak && ctx.dimension != null) out.balanceMode=EnerCubixBalance.mode(ctx,id)
    if (out.ratio) out.unit="COP"
    Str? directQuality:=null
    if (ctx.dimension != null && out.leak) directQuality=ctx.comparison == null ? ctx.dimension.leakQuality(id) : ctx.comparison.quality(id)
    else if (kind != "utility" && ctx.dimension?.dimension == "organization" && r != null && ["meter","totalMeter"].contains(r["kind"]?.toStr ?: "")) directQuality=ctx.dimension.quality([r])
    cursor:=start
    while (cursor < end)
    {
      next:=kind == "comparison" && request["comparisonAlignment"] == "duration" ? cursor+1hr : EnerCubixMath.floorHour(cursor)+1hr
      if (next > end) next=end
      EnerCubixValue value := EnerCubixValue()
      EnerCubixValue? numerator:=null; EnerCubixValue? denominator:=null
      EnerCubixValue? known:=null
      if (out.ratio)
      {
        if (r?.get("kind") != "cop") value=EnerCubixValue(null,"missingCopDefinition")
        else
        {
          numerator=ctx.nodeTotal(r["numeratorId"]?.toStr ?: "",cursor,next)
          denominator=ctx.nodeTotal(r["denominatorId"]?.toStr ?: "",cursor,next)
          value=EnerCubixValue.divide(numerator,denominator)
        }
      }
      else if (out.leak)
      {
        if (ctx.dimension != null)
        {
          members:=leakMembers(id,category)
          numerator=ctx.node(id,category,cursor,next,metric)
          denominator=members.isEmpty ? EnerCubixValue(null,"missingBranches") : EnerCubixValue.sum(members.map |m->EnerCubixValue| { ctx.node(m["id"].toStr,category,cursor,next,metric) })
          value=EnerCubixValue.sum([numerator,denominator.scale(-1f)])
          if (directQuality != null) value=EnerCubixValue(null,directQuality,value.sources)
        }
        else if (r?.get("kind") != "group") value=EnerCubixValue(null,"groupRequired")
        else
        {
          masters:=(ctx.children[id] ?: [Str:Obj?][,]).findAll |m| { m["kind"] == "totalMeter" && (m["categoryId"]?.toStr ?: "") == category && ctx.included(m) }
          numerator=masters.size == 1 ? ctx.node(masters.first["id"].toStr,category,cursor,next,metric) : EnerCubixValue(null,masters.isEmpty ? "missingMaster" : "ambiguousMaster")
          denominator=ctx.branch(id,category,cursor,next,metric)
          value=EnerCubixValue.sum([numerator,denominator.scale(-1f)])
        }
      }
      else
      {
        value=ctx.node(id,category,cursor,next,metric,Str[,],utility)
        if (directQuality != null) value=EnerCubixValue(null,directQuality,value.sources)
        if (activeKnown != null && !out.gauge)
        {
          known=activeKnown.node(id,category,cursor,next,metric,Str[,],utility)
          if (kind == "utility" && value.value == null && value.quality == "missing" && known.quality == "na") value=EnerCubixValue(null,"na",value.sources)
        }
      }
      if (out.leak && (numerator?.reliable == false || denominator?.reliable == false))
        value=EnerCubixValue(null,EnerCubixValue.worse(numerator?.quality ?: "missing",denominator?.quality ?: "missing"),value.sources)
      if (request["perArea"] == true)
      {
        area:=EnerCubixMath.num(r?.get("area"))
        if (out.ratio) ctx.warn("COP is a ratio; per-area normalization does not apply")
      else if (area == null || area <= 0f)
      {
        value=EnerCubixValue(null,"missingArea",value.sources)
        if (known != null) known=EnerCubixValue(null,"missingArea",known.sources)
        if (numerator != null) numerator=EnerCubixValue(null,"missingArea",numerator.sources)
        if (denominator != null) denominator=EnerCubixValue(null,"missingArea",denominator.sources)
      }
        else
        {
          value=value.scale(1f/area)
          known=known?.scale(1f/area)
          numerator=numerator?.scale(1f/area); denominator=denominator?.scale(1f/area)
        }
      }
      if (value.value == null) ctx.warn("${out.name}: ${value.quality}")
      tick:=EnerCubixTick(cursor,next,value,numerator,denominator); tick.known=known
      out.ticks.add(tick); cursor=next
    }
    if (request["perArea"] == true && !out.ratio) out.unit+="/m²"
    if (activeKnown != null && activeKnown !== knownCtx) knownCtx.knownReads.setAll(activeKnown.knownReads)
    return out
  }

  Str:Obj? forecast(EnerCubixLine[] lines)
  {
    forecasts:=[Str:Obj?][,]; backtests:=[Str:Obj?][,]; scores:=[Str:Obj?][,]
    horizon:=(EnerCubixMath.num(request["forecastDays"]) ?: 7f).toInt
    lines.each |line| {
      dates:=DateTime[,]; values:=Float?[,]; historyPoints:=[Str:Obj?][,]; sources:=Str[,]
      cursor:=from
      while (cursor < to)
      {
        end:=EnerCubixMath.nextBucket(cursor,"day")
        value:=line.total(line.ticks.findAll |t| { t.ts >= cursor && t.ts < end })
        if (value.value != null && value.value < 0f) value=EnerCubixValue(null,"negative",value.sources)
        dates.add(cursor); values.add(value.reliable ? value.value : null); sources.addAll(value.sources)
        point:=value.point(cursor); historyPoints.add(point)
        rows.add(point.dup.setAll(["id":line.id,"nodeId":line.nodeId,"name":line.name,"categoryId":line.category,"unit":line.unit,"phase":"history"]))
        cursor=end
      }
      fit:=EnerCubixForecast.fit(values,horizon)
      simulated:=sources.unique.any |id| { ctx.byPoint[id]?.simulated == true }
      meta:=fit.dup
      ["predictions","backtests","modelScores"].each |key| { meta.remove(key) }
      meta.setAll(["id":line.id,"nodeId":line.nodeId,"name":line.name,"categoryId":line.category,"unit":line.unit,"forecastDays":horizon,"trainingEnd":to.toIso,"simulated":simulated])
      series.add(["id":line.id+"|history","nodeId":line.nodeId,"name":line.name+" · 历史","categoryId":line.category,"unit":line.unit,"role":"history","points":historyPoints])
      if (simulated) ctx.warn("${line.name}：数据来源包含模拟历史，回测误差不能代表真实运行预测能力")
      if (fit["status"] != "ok")
      {
        meta["predictedTotal"]=null
        status:=fit["status"]
        reason:=["insufficientHistory":"有效历史不足","insufficientBacktest":"回测范围不足","invalidForecast":"预测计算异常"][status?.toStr ?: ""] ?: "暂不能预测"
        ctx.warn("${line.name}：$reason，至少需要 28 个有效日、80% 完整率和最近 7 天完整数据；长周期预测还需要足够的历史回测范围")
      }
      else
      {
        predictions:=(Float[])fit["predictions"]; spread:=(Float)fit["errorRange"]
        futurePoints:=[Str:Obj?][,]; total:=0f; future:=to
        predictions.each |value| {
          point:=[Str:Obj?]["ts":future.toIso,"value":value,"quality":"predicted","sourceIds":sources.unique,"lower":(value-spread).max(0f),"upper":value+spread]
          futurePoints.add(point)
          rows.add(point.dup.setAll(["id":line.id,"nodeId":line.nodeId,"name":line.name,"categoryId":line.category,"unit":line.unit,"phase":"forecast","model":fit["model"]]))
          total+=value; future=EnerCubixMath.nextBucket(future,"day")
        }
        meta["predictedTotal"]=total
        series.add(["id":line.id+"|forecast","nodeId":line.nodeId,"name":line.name+" · 预测","categoryId":line.category,"unit":line.unit,"role":"forecast","points":futurePoints])
        EnerCubixMath.maps(fit["backtests"]).each |pair| { backtests.add(pair.dup.setAll(["id":line.id,"categoryId":line.category,"unit":line.unit,"name":line.name,"ts":dates[(Int)pair["index"]].toIso,"trainingEnd":dates[(Int)pair["origin"]].toIso])) }
        EnerCubixMath.maps(fit["modelScores"]).each |score| { scores.add(score.dup.setAll(["id":line.id,"categoryId":line.category,"unit":line.unit,"name":line.name])) }
      }
      forecasts.add(meta)
    }
    extra["forecasts"]=forecasts; extra["backtests"]=backtests; extra["modelScores"]=scores
    extra["forecastFrom"]=to.toIso
    extra["algorithm"]="weekly-selection-v1"
    return result
  }

  EnerCubixLine referenceLine(Str id, Bool raw := false)
  {
    record:=ctx.byId[id]
    point:=record?.get("pointId")?.toStr ?: id
    history:=ctx.byPoint[point]
    out:=EnerCubixLine(id+(raw ? "|reference" : ""),id,ctx.displayName(id),"",history?.unit ?: "")
    out.gauge=raw || history == null || history.mode == "sampled" || history.mode == "cov"
    out.reference=raw
    cursor:=from
    while (cursor < to)
    {
      next:=EnerCubixMath.floorHour(cursor)+1hr; if (next > to) next=to
      value:=history?.read(cursor,next,raw) ?: EnerCubixValue()
      if (value.value == null) ctx.warn("${out.name}: ${value.quality}")
      out.ticks.add(EnerCubixTick(cursor,next,value)); cursor=next
    }
    return out
  }

  Str:Obj? finish(EnerCubixLine[] lines)
  {
    if (!["cop","leak"].contains(kind)) summary["selectionTotals"]=kind == "utility" ? utilityTotals(lines) : selectionTotals(lines)
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
      return ["id":l.id,"name":l.name,"categoryId":l.category,"value":value.value,"valueType":value.valueType,"quality":value.quality,"unit":l.unit,"sourceIds":value.sources]
    }
    if (knownCtx != null)
    {
      extra["selectionTotals"]=summary["selectionTotals"]
      summary["knownTotals"]=lines.findAll |l| { !l.reference && !l.ratio && !l.gauge }.map |l->[Str:Obj?]|
      {
        value:=l.knownTotal
        return ["id":l.id,"name":l.name,"categoryId":l.category,"unit":l.unit,"value":value.value,"valueType":value.valueType,"quality":value.quality,"sourceIds":value.sources]
      }
      extra["usageBasis"]="knownUsage"
      extra["usageCoverage"]=lines.findAll |l| {!l.reference && !l.ratio && !l.gauge}.map |l->[Str:Obj?]| {coverage(l)}
      reads:=EnerCubixKnownUsage.evidence(knownCtx.knownReads.vals)
      extra["knownUsage"]=["basis":"closedSourceIntervals","asOf":dataCutoff.toIso,"sourceUsage":reads,"detailsTruncated":reads.any |row| { row["detailsTruncated"] == true }]
    }
    if (kind == "leak") leakTotals(lines)
    if (kind == "utility") extra["details"]=extra["utilityMembers"]
    else if (ctx.dimension != null) dimensionDetails(lines)
    return result
  }

  private Void dimensionDetails(EnerCubixLine[] lines)
  {
    details:=[Str:Obj?][,]; seen:=Str[,]
    lines.each |l|
    {
      if (l.reference) return
      members:=kind == "utility" ? ctx.dimension.usageMembers(l.nodeId) : ctx.dimension.members(l.nodeId)
      own:=ctx.byId[l.nodeId]
      if (members.isEmpty && own != null && ["meter","totalMeter"].contains(own["kind"]?.toStr ?: "")) members=[own]
      if (kind == "leak")
      {
        members=leakMembers(l.nodeId,l.category).dup
        if (own != null) members.insert(0,own)
      }
      countedMembers:=members
      if (kind != "leak") countedMembers=kind == "utility" ? ctx.dimension.usageFrontier(members) : ctx.dimension.frontier(members)
      counted:=countedMembers.map |m->Str| { m["id"].toStr }
      members.each |m|
      {
        id:=m["id"].toStr; key:="${l.nodeId}|$id"
        if (seen.contains(key)) return
        seen.add(key)
        category:=m["categoryId"]?.toStr ?: ""
        value:=meterTotal(id,category)
        row:=Str:Obj?["scopeId":l.nodeId,"nodeId":id,"name":ctx.displayName(id),"categoryId":category,"value":value.value,"quality":value.quality,"unit":ctx.unit(id,category,metric),"sourceIds":value.sources,"counted":counted.contains(id)]
        if (knownCtx != null) row.setAll(EnerCubixKnownUsage.fields(meterTotal(id,category,true)))
        details.add(row)
      }
    }
    extra["details"]=details
  }

  private EnerCubixValue meterTotal(Str id, Str category, Bool known := false)
  {
    values:=EnerCubixValue[,]; cursor:=from
    while (cursor < to)
    {
      end:=EnerCubixMath.floorHour(cursor)+1hr; if (end > to) end=to
      values.add((known ? knownCtx : ctx).node(id,category,cursor,end,metric)); cursor=end
    }
    return known ? EnerCubixKnownUsage.combine(values) : EnerCubixValue.sum(values)
  }

  private Bool displaysKnown(EnerCubixLine line)
  { knownCtx != null && !line.reference && !line.gauge && !line.ratio && !line.leak }

  private EnerCubixValue available(EnerCubixLine line)
  { displaysKnown(line) ? line.knownTotal : line.total }

  private [Str:Obj?][] selectionTotals(EnerCubixLine[] lines)
  {
    out:=[Str:Obj?][,]
    lines.findAll |l| {!l.reference && !l.gauge && !l.ratio}.map |l->Str| {l.category}.unique.sort.each |Str category|
    {
      selected:=lines.findAll |l| {!l.reference && l.category == category}
      candidates:=selected.map |l->[Str:Obj?][]| {ctx.scopeMeters(l.nodeId,category,Str[,],l.utility)}.flatten
      meters:=ctx.selectionMeters(candidates)
      strict:=EnerCubixValue.sum(meters.map |m->EnerCubixValue| {meterTotal(m["id"].toStr,category)})
      known:=knownCtx == null ? null : EnerCubixKnownUsage.combine(meters.map |m->EnerCubixValue| {meterTotal(m["id"].toStr,category,true)})
      quality:=ctx.dimension?.quality(candidates)
      invalid:=selected.find |l| {available(l).value == null && !["missing","incompleteInterval","filtered","substituted","na","reset","negative","maximum","missingArea"].contains(available(l).quality)}
      if (quality == null && invalid != null) quality=available(invalid).quality
      if (quality != null)
      {
        strict=EnerCubixValue(null,quality,strict.sources)
        if (known != null && quality != "accountingIncomplete") known=EnerCubixValue(null,quality,known.sources)
      }
      unit:=selected.first?.unit ?: ""
      if (request["perArea"] == true)
      {
        area:=ctx.dimension?.selectionArea(lines.findAll |l| {!l.reference}.map |l->Str| {l.nodeId})
        if (area == null)
        {
          ids:=lines.findAll |l| {!l.reference}.map |l->Str| {l.nodeId}.unique
          scopes:=ids.findAll |Str id->Bool|
          {
            return ["parentId","meterParentId"].all |key->Bool|
            {
              seen:=Str[,]; parent:=ctx.byId[id]?.get(key) as Str
              while (parent != null && !seen.contains(parent))
              {
                if (ids.contains(parent)) return false
                seen.add(parent); parent=ctx.byId[parent]?.get(key) as Str
              }
              return true
            }
          }
          values:=scopes.map |Obj? id->Float?| {EnerCubixMath.num(ctx.byId[id.toStr]?.get("area"))}
          area=values.any |v| {v == null || v <= 0f} ? EnerCubixValue(null,"missingArea") : EnerCubixValue(values.reduce(0f) |Float sum,Float n->Float| {sum+n},"ok")
        }
        extra["normalizationArea"]=["value":area.value,"quality":area.quality,"unit":"m²"]
        if (area.value == null || area.value <= 0f) ctx.warn("所选对象合计: "+area.quality)
        strict=area.value == null || area.value <= 0f ? EnerCubixValue(null,area.quality,strict.sources) : strict.scale(1f/area.value)
        if (known != null) known=area.value == null || area.value <= 0f ? EnerCubixValue(null,area.quality,known.sources) : known.scale(1f/area.value)
      }
      row:=Str:Obj?["id":category+"|"+unit,"categoryId":category,"unit":unit,"value":strict.value,"valueType":strict.valueType,"quality":strict.quality,"scopeQuality":quality,"sourceIds":strict.sources,"meterIds":meters.map |m->Str| {m["id"].toStr}]
      if (known != null) row.setAll(EnerCubixKnownUsage.fields(known))
      out.add(row)
    }
    return out
  }

  private Bool overlapping(EnerCubixLine[] lines)
  {
    seen:=Str[,]; members:=[Str:Obj?][,]
    lines.each |l|
    {
      own:=ctx.scopeMeters(l.nodeId,l.category,Str[,],l.utility)
      members.addAll(own)
      own.each |m| {seen.add(m["id"].toStr)}
    }
    return seen.size != seen.unique.size || ctx.selectionMeters(members).size != seen.unique.size
  }

  private Str shareBasis(EnerCubixLine[] lines, EnerCubixValue denominator)
  {
    if (overlapping(lines)) return "overlappingScopes"
    if (lines.any |l| {available(l).value != null && available(l).value < 0f}) return "negativeConsumption"
    if (denominator.value == null) return "noKnownUsage"
    return denominator.value == 0f ? "zeroKnownTotal" : "knownUsage"
  }

  private Str:Obj? coverage(EnerCubixLine line)
  {
    start:=line.ticks.first?.ts ?: from; finish:=line.ticks.last?.end ?: to
    meters:=ctx.scopeMeters(line.nodeId,line.category,Str[,],line.utility)
    Str[] points:=meters.map |m->Str| {m["pointId"] as Str ?: ""}
    points=points.findAll |id| {!id.isEmpty}.unique
    reads:=knownCtx.knownReads.vals.findAll |r| {points.contains(r["pointId"]) && DateTime.fromIso(r["from"].toStr) >= start && DateTime.fromIso(r["to"].toStr) <= finish}
    seconds:=(finish-start).ticks.toFloat/1sec.ticks.toFloat
    covered:=points.map |point->Float|
    {
      total:=0f; reads.findAll |r| {r["pointId"] == point}.each |r| {total+=EnerCubixMath.num(r["coveredSeconds"]) ?: 0f}; return total
    }
    amount:=covered.isEmpty ? 0f : (Float)covered.min
    starts:=reads.findAll |r| {r["intervalStart"] != null}.map |r->DateTime| {DateTime.fromIso(r["intervalStart"].toStr)}
    ends:=reads.findAll |r| {r["intervalEnd"] != null}.map |r->DateTime| {DateTime.fromIso(r["intervalEnd"].toStr)}
    value:=line.knownTotal
    return ["id":line.id,"nodeId":line.nodeId,"name":line.name,"categoryId":line.category,"unit":line.unit,"knownValue":value.value,"knownQuality":value.quality,"coveredSeconds":amount,"expectedSeconds":seconds,"coverage":seconds > 0f ? (amount/seconds).min(1f) : 0f,"coverageStart":starts.isEmpty ? null : ((DateTime)starts.min).toIso,"coverageEnd":ends.isEmpty ? null : ((DateTime)ends.max).toIso,"complete":line.total.value != null && line.total.reliable && amount >= seconds,"meterIds":meters.map |m->Str| {m["id"].toStr}]
  }

  private [Str:Obj?][] utilityTotals(EnerCubixLine[] lines)
  {
    out:=[Str:Obj?][,]
    lines.map |l->Str| {l.category+"|"+l.unit}.unique.sort.each |Str key|
    {
      group:=lines.findAll |l| {l.category+"|"+l.unit == key}
      out.add(utilityAggregate(group).setAll(["id":key,"categoryId":group.first.category,"unit":group.first.unit]))
    }
    return out
  }

  private Str:Obj? utilityAggregate(EnerCubixLine[] group)
  {
    readings:=group.map |l->EnerCubixValue| {l.total}
    meters:=group.map |l->[Str:Obj?]| {ctx.byId[l.nodeId]}
    overlap:=EnerCubixEndUse.overlap(ctx,meters,readings)
    value:=EnerCubixValue.sum(readings)
    known:=EnerCubixKnownUsage.combine(group.map |l->EnerCubixValue| {l.knownTotal})
    if (overlap)
    {
      value=EnerCubixValue(null,"overlappingScopes",value.sources)
      known=EnerCubixValue(null,"overlappingScopes",known.sources)
    }
    else if (request["perArea"] == true)
    {
      value=EnerCubixValue(null,"areaNormalized",value.sources)
      known=EnerCubixValue(null,"areaNormalized",known.sources)
    }
    row:=Str:Obj?["value":value.value,"valueType":value.valueType,"quality":value.quality,"scopeQuality":overlap ? "overlappingScopes" : null,"sourceIds":value.sources,"meterIds":group.map |l->Str| {l.nodeId}]
    if (knownCtx != null) row.setAll(EnerCubixKnownUsage.fields(known))
    return row
  }

  private Void utilityShares(EnerCubixLine[] lines)
  {
    members:=[Str:Obj?][,];shares:=[Str:Obj?][,]
    lines.each |l|
    {
      record:=ctx.byId[l.nodeId]; utility:=record["utilityId"] as Str ?: ""
      value:=l.total
      row:=Str:Obj?["id":l.id,"nodeId":l.nodeId,"name":ctx.displayName(l.nodeId),"utilityId":utility,"utilityName":ctx.byId[utility]?.get("name") ?: "","categoryId":l.category,"unit":l.unit,"value":value.value,"valueType":value.valueType,"quality":value.quality,"sourceIds":value.sources,"counted":true]
      if (knownCtx != null) row.setAll(EnerCubixKnownUsage.fields(l.knownTotal)).setAll(coverage(l))
      members.add(row)
    }
    lines.map |l->Str| {l.category+"|"+l.unit}.unique.sort.each |Str key|
    {
      group:=lines.findAll |l| {l.category+"|"+l.unit == key}
      total:=utilityAggregate(group)
      strict:=EnerCubixMath.num(total["value"]); known:=knownCtx == null ? strict : EnerCubixMath.num(total["knownValue"])
      overlap:=total["scopeQuality"] == "overlappingScopes"
      negative:=group.any |l| {l.total.quality == "negative" || l.knownTotal.quality == "negative" || (l.total.value != null && l.total.value < 0f) || (l.knownTotal.value != null && l.knownTotal.value < 0f)}
      basis:=overlap ? "overlappingScopes" : (request["perArea"] == true ? "areaNormalized" : (negative ? "negativeConsumption" : (known == null ? "noKnownUsage" : (known == 0f ? "zeroKnownTotal" : "knownUsage"))))
      group.map |l->Str| {ctx.byId[l.nodeId]?.get("utilityId") as Str ?: ""}.unique.sort.each |utility|
      {
        subset:=group.findAll |l| {(ctx.byId[l.nodeId]?.get("utilityId") as Str ?: "") == utility}
        row:=utilityAggregate(subset)
        row.setAll(["id":key+"|"+utility,"name":ctx.byId[utility]?.get("name") ?: utility,"utilityId":utility,"categoryId":group.first.category,"unit":group.first.unit,"percentageBasis":basis])
        v:=EnerCubixMath.num(row["value"]);k:=EnerCubixMath.num(row["knownValue"])
        percentage:=EnerCubixValue.divide(EnerCubixValue(v,row["quality"].toStr),EnerCubixValue(strict,total["quality"].toStr)).scale(100f)
        row["percentage"]=basis == "knownUsage" ? percentage.value : null
        row["knownPercentage"]=basis == "knownUsage" && k != null ? k/known*100f : null
        row["percentageQuality"]=basis == "knownUsage" ? percentage.quality : basis
        shares.add(row)
      }
    }
    extra["utilityShares"]=shares;extra["utilityMembers"]=members
    extra["scopeTotals"]=summary["selectionTotals"]
  }

  private Void append(EnerCubixLine l, Str gran)
  {
    grouped:=Str:EnerCubixTick[][:]; order:=Str[,]; timestamps:=Str:DateTime[:]
    l.ticks.each |t|
    {
      at:=EnerCubixMath.bucket(t.ts,gran)
      if (kind == "comparison" && request["comparisonAlignment"] == "duration")
      {
        start:=l.ticks.first.ts
        step:=gran == "hour" ? 1hr.ticks : (gran == "week" ? 7day.ticks : 1day.ticks)
        at=start+Duration((t.ts-start).ticks/step*step)
      }
      key:=at.toIso
      if (!grouped.containsKey(key)) { grouped[key]=EnerCubixTick[,]; order.add(key); timestamps[key]=at }
      grouped[key].add(t)
    }
    points:=[Str:Obj?][,]
    order.each |key|
    {
      ticks:=grouped[key]; v:=l.total(ticks); at:=timestamps[key]
      p:=v.point(at); points.add(p)
      row:=baseRow(l,key,v); row["ts"]=key
      if (knownCtx != null && !l.reference && !l.ratio && !l.gauge)
      {
        known:=l.knownTotal(ticks)
        fields:=["knownValue":known.value,"knownValueType":known.valueType,"knownQuality":known.quality,"bucketEnd":EnerCubixMath.nextBucket(at,gran).toIso]
        p.setAll(fields); row.setAll(fields)
      }
      if (l.leak)
      {
        total:=EnerCubixValue.sum(ticks.map |t->EnerCubixValue| { t.numerator ?: EnerCubixValue() })
        sub:=EnerCubixValue.sum(ticks.map |t->EnerCubixValue| { t.denominator ?: EnerCubixValue() })
        row["total"]=total.value; row["submeter"]=sub.value; row["difference"]=v.value
        row["totalQuality"]=total.quality; row["submeterQuality"]=sub.quality
        row["balanceMode"]=l.balanceMode; row["lossEligible"]=physicalMetric && v.value != null && v.value >= 0f && EnerCubixBalance.eligible(l.balanceMode,total,sub)
        row["percentage"]=physicalMetric && l.balanceMode == "independent" ? EnerCubixValue.divide(v,total).scale(100f).value : null
        if (v.value != null && v.value < 0f) ctx.warn("${l.name}: 分表合计大于总表，差额为负，请核对计量关系与数据")
        branchRows:=extra["leakBranches"] as List
        if (branchRows == null) { branchRows=[Str:Obj?][,]; extra["leakBranches"]=branchRows }
        leakMembers(l.nodeId,l.category).each |branch|
        {
          branchId:=branch["id"].toStr
          branchValue:=EnerCubixValue.sum(ticks.map |t->EnerCubixValue| { ctx.node(branchId,l.category,t.ts,t.end,metric) })
          if (request["perArea"] == true)
          {
            area:=EnerCubixMath.num(ctx.byId[l.nodeId]?.get("area"))
            branchValue=area == null || area <= 0f ? EnerCubixValue(null,"missingArea",branchValue.sources) : branchValue.scale(1f/area)
          }
          branchRows.add(["nodeId":l.nodeId,"branchId":branchId,"name":ctx.displayName(branchId),"categoryId":l.category,"unit":l.unit,"ts":key,"value":branchValue.value,"quality":branchValue.quality,"sourceIds":branchValue.sources])
        }
      }
      rows.add(row)
    }
    series.add(seriesMap(l,points))
  }

  private [Str:Obj?][] leakMembers(Str id, Str category)
  {
    if (ctx.comparison != null) return ctx.comparison.members(id).findAll |m| {(m["categoryId"] as Str ?: "") == category}
    if (ctx.dimension != null) return ctx.dimension.directChildren(id).findAll |m| { (m["categoryId"]?.toStr ?: "") == category }
    return (ctx.children[id] ?: [Str:Obj?][,]).findAll |m| { ctx.included(m) && m["kind"] != "totalMeter" && ctx.categories(m["id"].toStr).contains(category) }
  }

  private Void leakTotals(EnerCubixLine[] lines)
  {
    extra["leakTotals"]=lines.map |l->[Str:Obj?]|
    {
      total:=EnerCubixValue.sum(l.ticks.map |t->EnerCubixValue| { t.numerator ?: EnerCubixValue() })
      sub:=EnerCubixValue.sum(l.ticks.map |t->EnerCubixValue| { t.denominator ?: EnerCubixValue() })
      difference:=l.total
      row:=baseRow(l,"summary",difference)
      row["total"]=total.value; row["submeter"]=sub.value; row["difference"]=difference.value
      row["totalQuality"]=total.quality; row["submeterQuality"]=sub.quality
      row["balanceMode"]=l.balanceMode; row["lossEligible"]=physicalMetric && difference.value != null && difference.value >= 0f && EnerCubixBalance.eligible(l.balanceMode,total,sub)
      row["percentage"]=physicalMetric && l.balanceMode == "independent" ? EnerCubixValue.divide(difference,total).scale(100f).value : null
      return row
    }
  }

  private Bool physicalMetric() {ctx.comparison == null || metric == "energy"}

  private Void totals(EnerCubixLine[] lines)
  {
    order:=lines.dup.sort |a,b| { (available(b).value ?: Float.negInf) <=> (available(a).value ?: Float.negInf) }
    totals:=Str:EnerCubixValue[][:]
    lines.each |l|
    {
      key:="${l.category}|${l.unit}"
      if (!totals.containsKey(key)) totals[key]=EnerCubixValue[,]
      totals[key].add(l.total)
    }
    ranks:=Str:Int[:]
    order.each |l|
    {
      v:=l.total; key:="${l.category}|${l.unit}"
      denom:=EnerCubixValue.sum(totals[key]); rank:=(ranks[key] ?: 0)+1
      if (available(l).value != null) ranks[key]=rank
      row:=baseRow(l,"total",v); row["rank"]=available(l).value == null ? null : rank
      row["percentage"]=EnerCubixValue.divide(v,denom).scale(100f).value
      point:=v.point(from)
      if (displaysKnown(l))
      {
        known:=l.knownTotal
        group:=lines.findAll |member| {member.category == l.category && member.unit == l.unit}
        denominator:=EnerCubixKnownUsage.combine(group.map |member->EnerCubixValue| {available(member)})
        basis:=shareBasis(group,denominator)
        row.setAll(coverage(l)); row.setAll(EnerCubixKnownUsage.fields(known))
        row["knownPercentage"]=basis == "knownUsage" && known.value != null ? known.value/denominator.value*100f : null
        row["percentageBasis"]=basis
        row["rankBasis"]="knownUsage"
        point.setAll(EnerCubixKnownUsage.fields(known))
      }
      rows.add(row)
      series.add(seriesMap(l,[point]))
    }
  }

  private Void daily(EnerCubixLine[] lines)
  {
    calendar:=ctx.calendar
    if (calendar == null) ctx.warn("未配置日历，无法划分峰谷平时段")
    bandOf:=|Int hour->Str|
    {
      if (calendar == null) return "unknown"
      if (EnerCubixMath.containsNum(calendar["peakHours"],hour)) return "peak"
      if (EnerCubixMath.containsNum(calendar["valleyHours"],hour)) return "valley"
      return "flat"
    }
    loadBands:=[Str:Obj?][,]
    lines.each |l|
    {
      grouped:=Int:EnerCubixTick[][:]
      l.ticks.each |t| { if (!grouped.containsKey(t.ts.hour)) grouped[t.ts.hour]=EnerCubixTick[,]; grouped[t.ts.hour].add(t) }
      points:=[Str:Obj?][,]
      (0..23).each |hour|
      {
        ticks:=grouped[hour] ?: EnerCubixTick[,]
        v:=l.total(ticks)
        if (!v.reliable) v=EnerCubixValue(null,v.quality,v.sources)
        if (!l.ratio && !l.gauge && !ticks.isEmpty) v=v.scale(1f/ticks.size.toFloat)
        at:=from.date.toDateTime(Time(hour,0),ctx.tz)
        band:=bandOf(hour)
        point:=v.point(at); point["band"]=band; points.add(point)
        row:=baseRow(l,"hour:$hour",v); row["hour"]=hour; row["ts"]=at.toIso; row["samples"]=ticks.size; row["band"]=band
        if (displaysKnown(l))
        {
          count:=ticks.findAll |tick| {tick.known?.value != null}.size
          known:=l.knownTotal(ticks)
          if (count > 0) known=known.scale(1f/count.toFloat)
          fields:=EnerCubixKnownUsage.fields(known).set("knownSamples",count)
          row.setAll(fields); point.setAll(fields)
        }
        rows.add(row)
      }
      series.add(seriesMap(l,points))
      bands:=calendar == null ? ["unknown"] : ["peak","valley","flat"]
      bands.each |band|
      {
        ticks:=l.ticks.findAll |t| { bandOf(t.ts.hour) == band }
        total:=ticks.isEmpty ? EnerCubixValue(0f,"ok") : EnerCubixValue.sum(ticks.map |t->EnerCubixValue| { t.value })
        if (!ticks.isEmpty && (l.gauge || l.ratio))
        {
          total=EnerCubixValue(null,"invalidMetric",total.sources)
          ctx.warn("${l.name}: 峰谷平区间总量需要能耗计量数据")
        }
        row:=baseRow(l,"band:$band",total); row["band"]=band
        if (displaysKnown(l)) row.setAll(EnerCubixKnownUsage.fields(ticks.isEmpty ? EnerCubixValue(0f,"ok") : l.knownTotal(ticks)))
        loadBands.add(row)
      }
    }
    extra["aggregation"]="mean energy for each hour of day"
    extra["loadBands"]=loadBands
    extra["loadBandsAggregation"]="intervalTotal"
  }

  private Void working(EnerCubixLine[] lines)
  {
    available:=kind == "workingHours" ? (request["workHours"] ?: ctx.calendar?.get("workHours")) != null : ctx.calendar?.get("workDays") != null
    if (!available) ctx.warn("Work calendar is required")
    lines.each |l|
    {
      work:=l.ticks.findAll |t| { ctx.working(t.ts,kind == "workingHours",request["workHours"]) }
      off:=l.ticks.findAll |t| { !ctx.working(t.ts,kind == "workingHours",request["workHours"]) }
      a:=!available ? EnerCubixValue(null,"missingCalendar") : l.total(work)
      b:=!available ? EnerCubixValue(null,"missingCalendar") : l.total(off)
      if (available && work.isEmpty) a=EnerCubixValue(0f,"ok")
      if (available && off.isEmpty) b=EnerCubixValue(0f,"ok")
      row:=baseRow(l,"working",l.total); row["working"]=a.value; row["nonworking"]=b.value
      row["workingPercentage"]=EnerCubixValue.divide(a,EnerCubixValue.sum([a,b])).scale(100f).value
      row["workingQuality"]=a.quality; row["nonworkingQuality"]=b.quality
      rows.add(row)
      points:=[a.point(from),b.point(from)]
      points[0]["label"]="working"; points[1]["label"]="nonworking"
      if (displaysKnown(l))
      {
        knownWork:=!available ? EnerCubixValue(null,"missingCalendar") : (work.isEmpty ? EnerCubixValue(0f,"ok") : l.knownTotal(work))
        knownOff:=!available ? EnerCubixValue(null,"missingCalendar") : (off.isEmpty ? EnerCubixValue(0f,"ok") : l.knownTotal(off))
        row.setAll(EnerCubixKnownUsage.fields(l.knownTotal))
        row["knownWorking"]=knownWork.value; row["knownNonworking"]=knownOff.value
        row["knownWorkingQuality"]=knownWork.quality; row["knownNonworkingQuality"]=knownOff.quality
        row["comparability"]=!available ? "missingCalendar" : (a.value == null || b.value == null || !a.reliable || !b.reliable ? "incompleteCoverage" : "complete")
        points[0].setAll(EnerCubixKnownUsage.fields(knownWork)); points[1].setAll(EnerCubixKnownUsage.fields(knownOff))
      }
      series.add(seriesMap(l,points))
    }
  }

  private Void comparePeriods(EnerCubixLine[] lines)
  {
    otherFrom:=request["otherFrom"]?.toStr; otherTo:=request["otherTo"]?.toStr
    if (otherFrom == null && otherTo == null)
    {
      comparisons:=[Str:Obj?][,]
      baselineId:=request["baselineId"]?.toStr
      if (baselineId != null && !EnerCubixMath.strings(request["nodeIds"]).contains(baselineId)) throw ArgErr("基准对象必须在已选对比对象中")
      bases:=baselineId == null ? (lines.isEmpty ? EnerCubixLine[,] : [lines.first]) : lines.findAll |l| { l.nodeId == baselineId }
      if (baselineId != null && bases.isEmpty) throw ArgErr("基准对象不存在或没有可分析的数据来源")
      if (baselineId != null) { extra["comparisonBaselineId"]=baselineId; extra["comparisonBaselineName"]=ctx.displayName(baselineId) }
      if (!lines.isEmpty)
      {
        lines.each |l|
        {
          if (bases.contains(l)) return
          base:=bases.find |b| { b.unit == l.unit && b.category == l.category }
          if (base == null)
          {
            if (baselineId == null) return
            ctx.warn("${l.name}: 与基准 ${ctx.displayName(baselineId)} 的能源类型或单位不一致，保留柱图，不计算差值及变化率")
            comparisons.add(["id":l.id,"name":l.name,"categoryId":l.category,"referenceId":baselineId,"referenceName":ctx.displayName(baselineId),"current":l.total.value,"reference":null,"knownCurrent":available(l).value,"knownReference":null,"difference":null,"percentage":null,"quality":"incompatibleBaseline","comparability":"incompatibleBaseline","unit":l.unit])
            return
          }
          current:=l.total; previous:=base.total; diff:=EnerCubixValue.sum([current,previous.scale(-1f)])
          comparable:=current.value != null && previous.value != null && current.reliable && previous.reliable
          if (displaysKnown(l)) comparable=comparable && coverage(l)["complete"] == true && coverage(base)["complete"] == true
          if (!comparable) diff=EnerCubixValue(null,"incompleteCoverage",diff.sources)
          percentage:=EnerCubixValue.divide(diff,previous).scale(100f)
          row:=Str:Obj?["id":l.id,"name":l.name,"categoryId":l.category,"referenceId":base.nodeId,"referenceName":base.name,"current":current.value,"reference":previous.value,"difference":diff.value,"percentage":percentage.value,"quality":diff.quality,"percentageQuality":percentage.quality,"unit":l.unit,"comparability":comparable ? "complete" : "incompleteCoverage"]
          if (displaysKnown(l)) row.setAll(["knownCurrent":available(l).value,"knownReference":available(base).value,"currentCoverage":coverage(l)["coverage"],"referenceCoverage":coverage(base)["coverage"]])
          comparisons.add(row)
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
      diff:=EnerCubixValue.sum([current,previous.scale(-1f)])
      comparable:=current.value != null && previous.value != null && current.reliable && previous.reliable
          if (displaysKnown(l)) comparable=comparable && coverage(l)["complete"] == true && coverage(base)["complete"] == true
          if (!comparable) diff=EnerCubixValue(null,"incompleteCoverage",diff.sources)
      row:=Str:Obj?["id":l.id,"name":l.name,"current":current.value,"reference":previous.value,"difference":diff.value,"percentage":EnerCubixValue.divide(diff,previous).scale(100f).value,"percentageQuality":EnerCubixValue.divide(diff,previous).quality,"quality":diff.quality,"unit":l.unit,"comparability":comparable ? "complete" : "incompleteCoverage"]
      if (displaysKnown(l)) row.setAll(["knownCurrent":available(l).value,"knownReference":available(base).value,"currentCoverage":coverage(l)["coverage"],"referenceCoverage":coverage(base)["coverage"]])
      comparisons.add(row)
      base.id+="|reference"; base.name+=" (reference)"; append(base,period)
    }
    extra["comparisons"]=comparisons
  }

  private Void dashboard(EnerCubixLine[] lines)
  {
    totals:=EnerCubixMath.maps(summary["selectionTotals"])
    extra["overview"]=totals.map |row->[Str:Obj?]| {row.dup.set("key",row["id"])}
    grouped:=Str:[Str:Obj?][][:]
    totals.each |row|
    {
      unit:=row["unit"].toStr
      if (!grouped.containsKey(unit)) grouped[unit]=[Str:Obj?][,]
      grouped[unit].add(row)
    }
    name:=metric == "cost" ? "总费用" : (metric == "co2" ? "总CO₂" : "所选对象合计")
    grandTotals:=[Str:Obj?][,]
    grouped.keys.sort.each |unit|
    {
      parts:=grouped[unit]
      strict:=EnerCubixValue.sum(parts.map |p->EnerCubixValue| {EnerCubixValue(EnerCubixMath.num(p["value"]),p["quality"].toStr,EnerCubixMath.strings(p["sourceIds"]))})
      row:=Str:Obj?["key":"$metric|$unit","name":name,"unit":unit,"value":strict.value,"quality":strict.quality,"sourceIds":strict.sources]
      if (knownCtx != null)
      {
        known:=EnerCubixKnownUsage.combine(parts.map |p->EnerCubixValue| {EnerCubixValue(EnerCubixMath.num(p["knownValue"]),p["knownQuality"].toStr,EnerCubixMath.strings(p["sourceIds"]))})
        row.setAll(EnerCubixKnownUsage.fields(known))
      }
      grandTotals.add(row)
    }
    extra["grandTotals"]=grandTotals
    if (request["otherFrom"] != null) comparePeriods(lines)
  }

  Str:Obj? trend(Str[] selected)
  {
    ids:=selected.dup.addAll(EnerCubixMath.strings(request["referenceIds"])).unique
    ids.each |id|
    {
      r:=ctx.byId[id]
      point:=r?.get("pointId")?.toStr ?: id
      h:=ctx.byPoint[point]
      name:=ctx.displayName(id)
      rawUnit:=r?.get("unit")?.toStr ?: (h?.unit ?: "")
      l:=EnerCubixLine(id,id,name,r?.get("categoryId")?.toStr ?: "",rawUnit)
      points:=[Str:Obj?][,]
      if (h == null || h.samples.isEmpty) ctx.warn("$name: missing history")
      else h.samples.each |s|
      {
        if (s.ts < from || s.ts >= to) return
        q:=s.valueType == "na" ? "na" : (s.value == null ? "missing" : h.quality)
        if (h.cleaning != null && s.quality != "ok") q=s.quality
        available:=["ok","derived","estimated","cleaned","corrected","filtered","substituted"].contains(q)
        v:=EnerCubixValue(available ? s.value : null,q,h.sources); p:=v.point(s.ts.toTimeZone(ctx.tz)); points.add(p)
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
      end:=EnerCubixMath.nextBucket(EnerCubixMath.bucket(cursor,period),period); if (end > to) end=to
      a:=regressionBucket(x,cursor,end); b:=regressionBucket(y,cursor,end)
      if (a.value != null && b.value != null)
      {
        xs.add(a.value); ys.add(b.value)
        point:=b.point(cursor); point["x"]=a.value; point["quality"]=EnerCubixValue.worse(a.quality,b.quality); point["sourceIds"]=a.sources.dup.addAll(b.sources).unique
        points.add(point)
        rows.add(["key":cursor.toIso,"ts":cursor.toIso,"x":a.value,"y":b.value,"value":b.value,"quality":point["quality"],"sourceIds":point["sourceIds"]])
      }
      else ctx.warn("Regression omitted incomplete pair: ${cursor.toIso}")
      cursor=end
    }
    extra=EnerCubixMath.regression(xs,ys)
    xName:=ctx.displayName(x); yName:=ctx.displayName(y)
    extra["xName"]=xName; extra["yName"]=yName
    fitLine:=[Str:Obj?][,]
    slope:=EnerCubixMath.num(extra["slope"]); intercept:=EnerCubixMath.num(extra["intercept"])
    if (slope != null && intercept != null && !xs.isEmpty)
    {
      low:=(Float)xs.min; high:=(Float)xs.max
      lowY:=EnerCubixMath.num(slope*low+intercept); highY:=EnerCubixMath.num(slope*high+intercept)
      if (high > low && lowY != null && highY != null) fitLine.add(["x":low,"y":lowY]).add(["x":high,"y":highY])
    }
    extra["fitLine"]=fitLine
    if (extra["slope"] == null) ctx.warn("Regression requires at least two valid pairs with varying x")
    series.add(["id":"regression","name":"$yName vs $xName","unit":"","points":points])
    return result
  }

  private EnerCubixValue regressionValue(Str id, DateTime start, DateTime end)
  {
    if (ctx.byId.containsKey(id))
    {
      value:=ctx.nodeTotal(id,start,end)
      r:=ctx.byId[id]
      if (ctx.dimension?.dimension == "organization" && ["meter","totalMeter"].contains(r["kind"]?.toStr ?: ""))
      {
        quality:=ctx.dimension.quality([r]); if (quality != null) return EnerCubixValue(null,quality,value.sources)
      }
      return value
    }
    return ctx.byPoint[id]?.read(start,end,true) ?: EnerCubixValue()
  }

  private EnerCubixValue regressionBucket(Str id, DateTime start, DateTime end)
  {
    values:=EnerCubixValue[,]; cursor:=start
    while (cursor < end)
    {
      next:=EnerCubixMath.floorHour(cursor)+1hr; if (next > end) next=end
      values.add(regressionValue(id,cursor,next)); cursor=next
    }
    total:=EnerCubixValue.sum(values)
    isGauge:=!ctx.byId.containsKey(id) || ctx.byId[id]["kind"] == "sensor"
    return isGauge && !values.isEmpty ? total.scale(1f/values.size.toFloat) : total
  }

  private Str:Obj? seriesMap(EnerCubixLine l, [Str:Obj?][] points)
  { ["id":l.id,"nodeId":l.nodeId,"name":l.name,"categoryId":l.category,"unit":l.unit,"points":points] }

  private Str:Obj? baseRow(EnerCubixLine l, Str key, EnerCubixValue v)
  { ["key":"${l.id}|$key","nodeId":l.nodeId,"name":l.name,"categoryId":l.category,"unit":l.unit,"value":v.value,"valueType":v.valueType,"quality":v.quality,"sourceIds":v.sources] }

  private Str:Obj? result()
  {
    if (ctx.dimension != null) extra["dimension"]=ctx.dimension.dimension
    if (knownCtx == null && !["trend"].contains(kind)) extra["usagePolicy"]=metric == "cost" ? "billingRequiresCompleteCoverage" : (kind == "forecast" ? "completeTrainingHistoryRequired" : (kind == "regression" ? "completePairsRequired" : "comparableCoverageRequired"))
    return ["kind":kind,"from":from.toIso,"to":to.toIso,"asOf":dataCutoff.toIso,"period":period,"series":series,"rows":rows,"warnings":ctx.warnings,"summary":summary,"extra":extra]
  }
}





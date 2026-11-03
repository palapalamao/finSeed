internal class EnerCubixReport
{
  new make(EnerCubixContext ctx, Str:Obj? request, DateTime from, DateTime to, Str kind, Str period, Str metric,EnerCubixPreparedOwner? catalogOwner := null,Bool summaryFrames := false)
  {
    if(summaryFrames && (catalogOwner == null || kind != "profile" || metric != "energy" || request["perArea"] == true)) throw ArgErr("summaryFramePlan")
    this.summaryFrames=summaryFrames
    this.ctx=ctx; this.request=request; this.from=from; this.to=to; this.kind=kind; this.period=period; this.metric=metric
    sharedAreas=ctx.sharedCatalog!=null
    if(sharedAreas && catalogOwner==null) throw ArgErr("sharedReportNeedsOwner")
    if(catalogOwner != null)
    {
      if(!ctx.ownedCatalog(catalogOwner.budget)) throw ArgErr("reportCatalogOwner")
      catalogOwner.hold(sharedAreas ? 40 : 40+3*ctx.byId.size);this.catalogOwner=catalogOwner
      catalogOwner.watch |->Void| {if(!sharedAreas) areas.clear;this.catalogOwner=null}
    }
    areas=ctx.sharedCatalog?.areas ?: EnerCubixArea(ctx.byId.vals)
    dataCutoff=EnerCubixKnownUsage.cutoff(request)
    if (EnerCubixKnownUsage.supported(kind,metric))
    {
      knownCtx=EnerCubixContext.known(ctx,to < dataCutoff ? to : dataCutoff)
    }
  }
  private EnerCubixArea areas
  private Bool sharedAreas := false
  private EnerCubixPreparedOwner? catalogOwner
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
  private Str:Str:Obj? consumedPeriods := [:]
  private [Str:EnerCubixValue]? consumedMeters
  private [Str:[Str:Obj?]]? consumedCoverage
  private [Str:Obj?]? consumedEvidence
  private Str:[Str:Obj?] consumedDaily := [:]
  private Str:[Str:Obj?][] consumedWorking := [:]
  private Str:[Str:Obj?][] finalScopes := [:]
  private Str:[Str:Obj?][] finalDetails := [:]
  private Str:Str[] finalCounted := [:]
  private Str:Str:Obj? finalSelections := [:]
  private Bool finalMetadataFrozen := false
  private Int finalDepth := 0
  private EnerCubixPreparedOwner? metadataPlanOwner
  private EnerCubixLine[] metadataPlanLines := [,]
  private [Str:Int]? metadataPlanShape
  internal const Bool summaryFrames

  ** Membership, topology quality and service area depend only on the frozen
  ** catalog. Resolve them before consuming history, rather than rebuilding
  ** whole-catalog candidate/area graphs at the simultaneous output peak.
  internal Str:Int freezeFrameMetadata(EnerCubixLine[] lines,EnerCubixPreparedOwner output)
  {
    if(catalogOwner==null || output.budget!==catalogOwner.budget) throw ArgErr("frameMetadataPlan")
    if(metadataPlanShape!=null)
    {
      if(metadataPlanOwner!==output || metadataPlanLines.size!=lines.size || !lines.all |line,i| {line===metadataPlanLines[i]}) throw ArgErr("frameMetadataPlan")
      return metadataPlanShape
    }
    if(finalMetadataFrozen) throw ArgErr("frameMetadataPlan")
    scratch:=EnerCubixPreparedOwner(output.budget)
    try
    {
      ctx.deadline?.check
      scratch.hold(64*(ctx.byId.size+lines.size+1))
      shape:=frameShape(lines)
      if(summaryFrames) return rememberFrameMetadata(shape,lines,output)
      scratch.hold(64*(shape["members"]+shape["details"]+lines.size+1))
      output.hold(8)
      lines.each |line|
      {
        ctx.deadline?.check
        scope:=ctx.scopeMeters(line.nodeId,line.category,Str[,],line.utility)
        output.hold(2+scope.size);finalScopes[line.id]=scope.dup
        if(ctx.dimension!=null && kind!="utility")
        {
          details:=detailMembers(line)
          counted:=kind=="leak" ? details : ctx.dimension.frontier(details)
          output.hold(4+details.size+counted.size)
          finalDetails[line.id]=details.dup;finalCounted[line.id]=counted.map |r->Str| {r["id"].toStr}
        }
        ids:=[line.nodeId];scope.each |r| {ids.add(r["id"].toStr)}
        finalDetails[line.id]?.each |r| {ids.add(r["id"].toStr)}
        ids.each |id|
        {
          seen:=Str[,];Str? cursor:=id
          while(cursor!=null && !seen.contains(cursor)) {ctx.deadline?.check;seen.add(cursor);cursor=ctx.byId[cursor]?.get("meterParentId") as Str}
          finalDepth=finalDepth.max(seen.size)
        }
      }
      if(!["cop","leak","utility"].contains(kind)) lines.findAll |l| {!l.reference && !l.gauge && !l.ratio}.map |l->Str| {l.category}.unique.sort.each |Str category|
      {
        ctx.deadline?.check
        raw:=selectionGroup(lines,category);selected:=(EnerCubixLine[])raw["selected"];candidates:=([Str:Obj?][])raw["candidates"];meters:=([Str:Obj?][])raw["meters"]
        quality:=ctx.dimension?.quality(metric=="cost" ? candidates.unique : candidates)
        Map? area
        if(request["perArea"]==true) {area=areas.selection(selected.map |l->Str| {l.nodeId},ctx.dimension,meters.map |m->Str| {m["id"].toStr});output.hold(metadataCells(area))}
        output.hold(16+selected.size+candidates.size+meters.size)
        finalSelections[category]=["selected":selected.dup,"candidates":candidates.dup,"meters":meters.dup,"quality":quality,"area":area]
      }
      ctx.deadline?.check;finalMetadataFrozen=true;return rememberFrameMetadata(shape,lines,output)
    }
    finally {scratch.close}
  }
  private Str:Int rememberFrameMetadata(Str:Int shape,EnerCubixLine[] lines,EnerCubixPreparedOwner output)
  {
    output.hold(7+lines.size);metadataPlanOwner=output;metadataPlanLines=lines.dup;metadataPlanShape=shape
    output.watch |->Void| {metadataPlanLines.clear;metadataPlanShape?.clear;metadataPlanShape=null;metadataPlanOwner=null}
    return shape
  }
  internal Int frameFinalDepth() {finalMetadataFrozen ? finalDepth : ctx.byId.size}
  internal [Str:Obj?][] frameScope(EnerCubixLine line)
  {finalMetadataFrozen ? finalScopes[line.id] : ctx.scopeMeters(line.nodeId,line.category,Str[,],line.utility)}
  private Int metadataCells(Obj? value)
  {
    if(value isnot Map && value isnot List) return 0
    cells:=1+(value is Map ? ((Map)value).size : ((List)value).size)
    if(value is Map) ((Map)value).each |child| {cells+=metadataCells(child)}
    else ((List)value).each |child| {cells+=metadataCells(child)}
    return cells
  }
  private Void clearFrameMetadata()
  {
    finalScopes.each |rows| {rows.clear};finalScopes.clear;finalDetails.each |rows| {rows.clear};finalDetails.clear;finalCounted.each |ids| {ids.clear};finalCounted.clear
    finalSelections.each |g| {((List)g["selected"]).clear;((List)g["candidates"]).clear;((List)g["meters"]).clear;area:=g["area"] as Map;if(area!=null) EnerCubixArea.clearResult(area);g.clear};finalSelections.clear;finalMetadataFrozen=false;finalDepth=0
  }

  internal Bool acceptsFrames()
  { ["profile","primary","ranking","proportion","dashboard","daily","utility","workingHours","workingDays"].contains(kind) && request["otherFrom"] == null && EnerCubixMath.strings(request["referenceIds"]).isEmpty }
  internal Bool frameSharesBase(EnerCubixLine line) {request["perArea"]!=true && !line.gauge && !line.ratio && !line.leak && !line.reference}
  internal Bool dailyFrames() {kind == "daily"}
  internal Bool workingFrames() {["workingHours","workingDays"].contains(kind)}
  internal Bool frameWorking(EnerCubixTick tick) {ctx.working(tick.ts,kind == "workingHours",request["workHours"])}
  internal Str frameBand(EnerCubixLine line,EnerCubixTick tick)
  {ctx.timeBand(line.nodeId,line.category,tick.ts,tick.end,line.utility)}
  internal Bool ownedFrameCatalog(EnerCubixPreparedOwner owner) {catalogOwner === owner}
  internal [Str:Obj?][] frameReads() {knownCtx?.knownReads?.vals ?: [Str:Obj?][,]}
  internal Bool frameEmptyOmitted() {knownCtx?.emptyEvidenceOmitted ?: false}
  internal Bool frameUnpreparedOmitted() {knownCtx?.unpreparedEvidenceOmitted ?: false}
  internal EnerCubixValue frameMeter(Str id,Str category,DateTime start,DateTime end,Bool known)
  { (known ? knownCtx : ctx).node(id,category,start,end,metric) }
  internal Bool constantEmptyMeters() {ctx.timeInvariantEmpty(metric)}
  internal Void eachFrameOutputRoot(|Obj?| visit)
  {visit(consumedPeriods);visit(consumedMeters);visit(consumedCoverage);visit(consumedEvidence);visit(consumedDaily);visit(consumedWorking)}
  internal Str:Obj? finishFrames(EnerCubixLine[] lines,Str:Str:Obj? periods,Str:EnerCubixValue meters,Str:[Str:Obj?] coverage,Str:Obj? evidence,Str:[Str:Obj?] daily := [:],Str:[Str:Obj?][] working := [:])
  {
    consumedPeriods=periods;consumedMeters=meters;consumedCoverage=coverage;consumedEvidence=evidence;consumedDaily=daily;consumedWorking=working
    if(summaryFrames)
    {
      // Space focus reads these three groups only. Keep their original line
      // folds and coverage; no period series, selection totals or details exist.
      summary["totals"]=lines.map |l->[Str:Obj?]|
      {v:=l.total;return ["id":l.id,"name":l.name,"categoryId":l.category,"value":v.value,"valueType":v.valueType,"quality":v.quality,"unit":l.unit,"sourceIds":v.sources]}
      summary["knownTotals"]=lines.map |l->[Str:Obj?]|
      {v:=l.knownTotal;return ["id":l.id,"name":l.name,"categoryId":l.category,"unit":l.unit,"value":v.value,"valueType":v.valueType,"quality":v.quality,"sourceIds":v.sources]}
      extra["usageCoverage"]=lines.map |l->[Str:Obj?]| {this.coverage(l)}
      return Str:Obj?["summary":summary,"extra":extra]
    }
    return finish(lines)
  }
  internal Void clearFrames()
  {consumedPeriods.clear;consumedMeters?.clear;consumedCoverage?.clear;consumedEvidence?.clear;consumedDaily.clear;consumedWorking.clear;series.clear;rows.clear;summary.clear;extra.clear;clearFrameMetadata;if(!sharedAreas) areas.clear}

  internal Void beginFrame(EnerCubixPreparedOwner owner,Str:EnerCubixHistoryData histories,Bool constantEmpty := false)
  {ctx.beginFrame(owner,histories,constantEmpty);knownCtx?.beginFrame(owner,histories,constantEmpty)}

  EnerCubixLine line(Str id, Str category, Str? utility := null, DateTime start := from, DateTime end := to)
  {
    cursor:=openLine(id,category,utility,start,end)
    while(cursor.more) cursor.line.ticks.add(cursor.next)
    return cursor.finish
  }

  internal EnerCubixLineCursor openLine(Str id,Str category,Str? utility := null,DateTime start := from,DateTime end := to)
  {
    needsArea:=catalogOwner==null || request["perArea"]==true
    if(catalogOwner != null)
    {
      // Retain the cursor/definition envelope separately from optional area
      // graphs. Non-normalized owned reports never consume those graphs.
      catalogOwner.hold(64)
      if(needsArea)
      {
        members:=ctx.dimension?.dimension == "organization" && ctx.dimension.scope(id) ? ctx.scopeMeters(id,category).size : 0
        catalogOwner.hold(64+64*members)
      }
    }
    r:=ctx.byId[id]
    name:=r?.get("name")?.toStr ?: id
    if (utility != null) name+=" / "+(ctx.byId[utility]?.get("name")?.toStr ?: (ctx.dimension == null ? "Unassigned" : "未指定分项"))
    out:=EnerCubixLine("$id|$category"+(utility == null ? "" : "|$utility"),id,name,category,ctx.unit(id,category,metric))
    out.utility=utility
    if(needsArea)
    {
      out.normalizationArea=areas.node(id)
      if (ctx.dimension?.dimension == "organization" && ctx.dimension.scope(id))
        out.normalizationArea=areas.selection([id],ctx.dimension,ctx.selectionMeters(ctx.scopeMeters(id,category)).map |m->Str| {m["id"].toStr})
      catalogOwner?.watch |->Void| {if(!out.outputOwnsArea) EnerCubixArea.clearResult(out.normalizationArea)}
    }
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
    read:=|DateTime cursor,DateTime next->EnerCubixTick|
    {
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
      baseValue:=value; baseKnown:=known; baseNumerator:=numerator; baseDenominator:=denominator
      if (request["perArea"] == true)
      {
        if (out.ratio) ctx.warn("COP is a ratio; per-area normalization does not apply")
        else
        {
          value=EnerCubixArea.scale(value,out.normalizationArea)
          if (known != null) known=EnerCubixArea.scale(known,out.normalizationArea)
          if (numerator != null) numerator=EnerCubixArea.scale(numerator,out.normalizationArea)
          if (denominator != null) denominator=EnerCubixArea.scale(denominator,out.normalizationArea)
        }
      }
      if (value.value == null) ctx.warn("${out.name}: ${value.quality}")
      tick:=EnerCubixTick(cursor,next,value,numerator,denominator); tick.known=known
      tick.baseValue=baseValue;tick.baseKnown=baseKnown;tick.baseNumerator=baseNumerator;tick.baseDenominator=baseDenominator
      return tick
    }
    if (request["perArea"] == true && !out.ratio) out.unit+="/m²"
    return EnerCubixLineCursor(out,start,end,kind == "comparison" && request["comparisonAlignment"] == "duration",read,|->Void|
    {if(activeKnown != null && activeKnown !== knownCtx) knownCtx.mergeKnown(activeKnown)})
  }

  Str:Obj? forecast(EnerCubixLine[] lines)
  {
    forecasts:=[Str:Obj?][,]; backtests:=[Str:Obj?][,]; scores:=[Str:Obj?][,]
    meterFits:=Str:[Str:Obj?][:]
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
      if (metric == "cost")
      {
        members:=ctx.scopeMeters(line.nodeId,line.category)
        fits:=members.map |meter->[Str:Obj?]|
        {
          id:=meter["id"].toStr
          if (!meterFits.containsKey(id))
          {
            own:=this.line(id,line.category); daily:=Float?[,]; day:=from
            while (day < to)
            {
              end:=EnerCubixMath.nextBucket(day,"day")
              amount:=own.total(own.ticks.findAll |tick| {tick.ts >= day && tick.ts < end})
              daily.add(amount.reliable ? amount.value : null);day=end
            }
            meterFits[id]=EnerCubixForecast.fit(daily,horizon)
          }
          return meterFits[id]
        }
        fit=EnerCubixCostForecast.combine(fits,values,horizon)
      }
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
    if (metric == "cost")
    {
      members:=ctx.selectionMeters(meterFits.keys.map |id->[Str:Obj?]| {ctx.byId[id]})
      ids:=members.map |meter->Str| {meter["id"].toStr}
      [Str:Obj?][] fits:=ids.map |id->[Str:Obj?]| {meterFits[id]}
      valid:=!fits.isEmpty && fits.all |fit| {fit["status"] == "ok"}
      total:=0f
      if (valid) fits.each |fit| {((Float[])fit["predictions"]).each |value| {total+=value}}
      summary["forecastTotals"]=[["meterIds":ids,"unit":"元","value":valid && EnerCubixMath.num(total) != null ? total : null,"quality":valid ? "predicted" : "insufficientHistory"]]
      extra["forecastBasis"]="historicalMeterCostPatterns";extra["forecastMeterIds"]=ids
    }
    recordLineAreas(lines)
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
      extra["knownUsage"]=(consumedEvidence ?: knownCtx.knownEvidence).set("asOf",dataCutoff.toIso)
    }
    recordLineAreas(lines)
    if (kind == "leak") leakTotals(lines)
    if (kind == "utility") extra["details"]=extra["utilityMembers"]
    else if (ctx.dimension != null) dimensionDetails(lines)
    return result
  }

  private Void recordLineAreas(EnerCubixLine[] lines)
  {
    if (request["perArea"] == true) lines.findAll |l| {!l.reference && !l.gauge && !l.ratio}.each |l|
    {
      base:=displaysKnown(l) ? l.baseKnownTotal : l.baseTotal
      recordArea(l.nodeId,l.name,l.category,base,l.baseUnit,available(l),l.unit,l.normalizationArea,l.leak ? "difference" : "ownUsage")
    }
  }

  private Void recordArea(Str id, Str? name, Str category, EnerCubixValue base, Str baseUnit, EnerCubixValue value, Str unit, Str:Obj? area, Str basis)
  {
    list:=extra["areaBasis"] as List
    if (list == null) {list=[Str:Obj?][,];extra["areaBasis"]=list}
    row:=Str:Obj?["nodeId":id,"categoryId":category,"baseValue":base.value,"baseUnit":baseUnit,"value":value.value,"unit":unit,"area":area,"basis":basis]
    if (name != null) row["name"]=name
    list.add(row)
  }

  private Str:Obj? leakBase(EnerCubixLine line, EnerCubixTick[] ticks)
  {
    total:=EnerCubixValue.sum(ticks.map |t->EnerCubixValue| {t.baseNumerator ?: EnerCubixValue()})
    sub:=EnerCubixValue.sum(ticks.map |t->EnerCubixValue| {t.baseDenominator ?: EnerCubixValue()})
    difference:=EnerCubixValue.sum(ticks.map |t->EnerCubixValue| {t.baseValue ?: t.value})
    return ["total":total.value,"submeter":sub.value,"difference":difference.value,"unit":line.baseUnit]
  }

  private Void dimensionDetails(EnerCubixLine[] lines)
  {
    details:=[Str:Obj?][,]; seen:=Str[,]
    lines.each |l|
    {
      if (l.reference) return
      members:=detailMembers(l)
      Str[] counted:=Str[,]
      if(finalMetadataFrozen) counted=finalCounted[l.id]
      else {countedMembers:=members;if(kind!="leak") countedMembers=kind=="utility" ? ctx.dimension.usageFrontier(members) : ctx.dimension.frontier(members);counted=countedMembers.map |m->Str| {m["id"].toStr}}
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

  private [Str:Obj?][] detailMembers(EnerCubixLine line)
  {
    if(finalMetadataFrozen) return finalDetails[line.id]
    members:=kind == "utility" ? ctx.dimension.usageMembers(line.nodeId) : ctx.dimension.members(line.nodeId)
    own:=ctx.byId[line.nodeId]
    if(members.isEmpty && own != null && ["meter","totalMeter"].contains(own["kind"]?.toStr ?: "")) members=[own]
    if(kind == "leak")
    {
      members=leakMembers(line.nodeId,line.category).dup
      if(own != null) members.insert(0,own)
    }
    return members
  }

  private Str:Obj? selectionGroup(EnerCubixLine[] lines,Str category)
  {
    if(finalMetadataFrozen) return finalSelections[category]
    selected:=lines.findAll |line| {!line.reference && line.category == category}
    candidates:=selected.map |line->[Str:Obj?][]| {frameScope(line)}.flatten
    return ["selected":selected,"candidates":candidates,"meters":ctx.selectionMeters(candidates)]
  }

  ** Own-meter totals used after line consumption. Reuse the same selection and
  ** detail membership as normal finalization; this is not a history read plan.
  internal [Str:Obj?][] frameLedger(EnerCubixLine[] lines)
  {
    // Focus summaries consume line totals and coverage only; they never read
    // selection/detail meter totals from finishFrames.
    if(summaryFrames) return [Str:Obj?][,]
    out:=[Str:Obj?][,];seen:=Str:Bool[:];order:=0
    add:=|Str id,Str category,Int phase|
    {
      key:="$id|$category"
      if(seen.containsKey(key)) return
      seen[key]=true;out.add(["id":id,"category":category,"phase":phase,"order":order++])
    }
    if(!["cop","leak","utility"].contains(kind))
      lines.findAll |line| {!line.reference && !line.gauge && !line.ratio}.map |line->Str| {line.category}.unique.sort.each |Str category,Int categoryIndex|
      {order=categoryIndex*(ctx.byId.size+1);EnerCubixMath.maps(selectionGroup(lines,category)["meters"]).each |meter| {add(meter["id"].toStr,category,1)}}
    order=0
    if(!summaryFrames && ctx.dimension != null && kind != "utility") lines.findAll |line| {!line.reference}.each |line|
    {detailMembers(line).each |meter| {add(meter["id"].toStr,meter["categoryId"] as Str ?: "",3)}}
    return out
  }

  ** Bounds count occurrences, not globally unique meters: one member can occur
  ** in several scope rows. Duplicate-category lines may over-reserve safely.
  internal Str:Int frameShape(EnerCubixLine[] lines)
  {
    members:=0;details:=0;maxMembers:=0
    lines.findAll |line| {!line.reference}.each |line|
    {
      n:=frameScope(line).size
      members+=n;maxMembers=maxMembers.max(n)
      if(!summaryFrames && ctx.dimension != null && kind != "utility") details+=detailMembers(line).size
    }
    return ["members":members,"details":details,"maxMembers":maxMembers]
  }

  private EnerCubixValue meterTotal(Str id, Str category, Bool known := false)
  {
    if(consumedMeters != null) return consumedMeters["$id|$category|$known"] ?: throw ArgErr("consumedMeterNotPlanned")
    values:=EnerCubixValue[,]; cursor:=from
    while (cursor < to)
    {
      end:=EnerCubixMath.floorHour(cursor)+1hr; if (end > to) end=to
      active:=known ? knownCtx : ctx
      value:=active.node(id,category,cursor,end,metric)
      values.add(value)
      constant:=value.value == null ? active.constantEnd(id,category,cursor,to,metric) : null
      cursor=constant ?: end
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
    lines.findAll |l| {!l.reference && !l.gauge && !l.ratio}.map |l->Str| {l.category}.unique.sort.each |Str category,Int categoryIndex|
    {
      group:=selectionGroup(lines,category)
      selected:=(EnerCubixLine[])group["selected"]
      candidates:=([Str:Obj?][])group["candidates"]
      meters:=([Str:Obj?][])group["meters"]
      strict:=EnerCubixValue.sum(meters.map |m->EnerCubixValue| {meterTotal(m["id"].toStr,category)})
      known:=knownCtx == null ? null : EnerCubixKnownUsage.combine(meters.map |m->EnerCubixValue| {meterTotal(m["id"].toStr,category,true)})
      quality:=finalMetadataFrozen ? (group["quality"] as Str) : ctx.dimension?.quality(request["metric"] == "cost" ? candidates.unique : candidates)
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
        area:=finalMetadataFrozen ? ((Str:Obj?)group["area"]) : areas.selection(selected.map |l->Str| {l.nodeId},ctx.dimension,meters.map |m->Str| {m["id"].toStr})
        if (lines.findAll |l| {!l.reference}.map |l->Str| {l.category}.unique.size == 1) extra["normalizationArea"]=area
        if (area["value"] == null)
        {
          if(consumedMeters != null) ctx.warningScope(1,categoryIndex*(ctx.byId.size+1)+ctx.byId.size,Int.maxVal)
          ctx.warn(area["quality"].toStr)
        }
        base:=known ?: strict
        strict=EnerCubixArea.scale(strict,area)
        if (known != null) known=EnerCubixArea.scale(known,area)
        recordArea("__selection__",null,category,base,selected.first?.baseUnit ?: "",known ?: strict,unit,area,"selection")
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
      own:=frameScope(l)
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
    if(consumedCoverage != null) return consumedCoverage[line.id] ?: throw ArgErr("consumedCoverageNotPlanned")
    start:=line.ticks.first?.ts ?: from; finish:=line.ticks.last?.end ?: to
    meters:=frameScope(line)
    Str[] points:=meters.map |m->Str| {m["pointId"] as Str ?: ""}
    points=points.findAll |id| {!id.isEmpty}.unique
    reads:=knownCtx.knownReads.vals.findAll |r| {points.contains(r["pointId"]) && DateTime.fromIso(r["from"].toStr) >= start && DateTime.fromIso(r["to"].toStr) <= finish}
    reads=EnerCubixKnownUsage.coverageOrder(reads)
    seconds:=(finish-start).ticks.toFloat/1sec.ticks.toFloat
    covered:=points.map |point->Float|
    {
      total:=0f; reads.findAll |r| {r["pointId"] == point}.each |r| {total+=EnerCubixMath.num(r["coveredSeconds"]) ?: 0f}; return total
    }
    amount:=covered.isEmpty ? 0f : (Float)covered.min
    starts:=reads.findAll |r| {r["intervalStart"] != null}.map |r->DateTime| {DateTime.fromIso(r["intervalStart"].toStr)}
    ends:=reads.findAll |r| {r["intervalEnd"] != null}.map |r->DateTime| {DateTime.fromIso(r["intervalEnd"].toStr)}
    return frameCoverage(line,["coveredSeconds":amount,"expectedSeconds":seconds,"coverage":seconds > 0f ? (amount/seconds).min(1f) : 0f,"coverageStart":starts.isEmpty ? null : ((DateTime)starts.min).toIso,"coverageEnd":ends.isEmpty ? null : ((DateTime)ends.max).toIso])
  }

  internal Str:Obj? frameCoverage(EnerCubixLine line,Str:Obj? stats)
  {
    value:=line.knownTotal
    meters:=frameScope(line)
    return Str:Obj?["id":line.id,"nodeId":line.nodeId,"name":line.name,"categoryId":line.category,"unit":line.unit,"knownValue":value.value,"knownQuality":value.quality,"complete":line.total.value != null && line.total.reliable && (Float)stats["coveredSeconds"] >= (Float)stats["expectedSeconds"],"meterIds":meters.map |m->Str| {m["id"].toStr}].setAll(stats)
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
        if (knownCtx != null) row["knownPercentage"]=basis == "knownUsage" && k != null ? k/known*100f : null
        row["percentageQuality"]=basis == "knownUsage" ? percentage.quality : basis
        shares.add(row)
      }
    }
    extra["utilityShares"]=shares;extra["utilityMembers"]=members
    extra["scopeTotals"]=summary["selectionTotals"]
  }

  private Void append(EnerCubixLine l, Str gran)
  {
    if(consumedPeriods.containsKey(l.id))
    {
      points:=[Str:Obj?][,]
      EnerCubixMath.maps(consumedPeriods[l.id]["rows"]).each |item|
      {
        at:=DateTime.fromIso(item["ts"].toStr);value:=(EnerCubixValue)item["value"]
        point:=value.point(at);row:=baseRow(l,at.toIso,value);row["ts"]=at.toIso
        if(displaysKnown(l))
        {
          known:=(EnerCubixValue)item["known"]
          fields:=EnerCubixKnownUsage.fields(known).set("bucketEnd",EnerCubixMath.nextBucket(at,gran).toIso)
          point.setAll(fields);row.setAll(fields)
        }
        points.add(point);rows.add(row)
      }
      series.add(seriesMap(l,points));return
    }
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
        if (request["perArea"] == true) row["baseUsage"]=leakBase(l,ticks)
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
            branchValue=EnerCubixArea.scale(branchValue,l.normalizationArea)
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
      if (request["perArea"] == true) row["baseUsage"]=leakBase(l,l.ticks)
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
    loadBands:=[Str:Obj?][,]
    lines.each |l,i|
    {
      if(consumedMeters != null) ctx.warningScope(2,i,0)
      frozen:=consumedDaily[l.id]
      bandOf:=|EnerCubixTick tick->Str| {ctx.timeBand(l.nodeId,l.category,tick.ts,tick.end,l.utility)}
      grouped:=Int:EnerCubixTick[][:]
      l.ticks.each |t| { if (!grouped.containsKey(t.ts.hour)) grouped[t.ts.hour]=EnerCubixTick[,]; grouped[t.ts.hour].add(t) }
      points:=[Str:Obj?][,]
      (0..23).each |hour|
      {
        ticks:=grouped[hour] ?: EnerCubixTick[,]
        data:=frozen == null ? null : EnerCubixMath.maps(frozen["hours"])[hour]
        count:=data == null ? ticks.size : (Int)data["samples"]
        v:=data == null ? l.total(ticks) : (EnerCubixValue)data["value"]
        if (!v.reliable) v=EnerCubixValue(null,v.quality,v.sources)
        if (!l.ratio && !l.gauge && count>0) v=v.scale(1f/count.toFloat)
        at:=from.date.toDateTime(Time(hour,0),ctx.tz)
        distinct:=ticks.map |tick->Str| {bandOf(tick)}.unique
        band:=data != null ? data["band"].toStr : (distinct.size == 1 ? distinct.first : (distinct.isEmpty ? "unknown" : "mixed"))
        point:=v.point(at); point["band"]=band; points.add(point)
        row:=baseRow(l,"hour:$hour",v); row["hour"]=hour; row["ts"]=at.toIso; row["samples"]=count; row["band"]=band
        if (displaysKnown(l))
        {
          knownCount:=data == null ? ticks.findAll |tick| {tick.known?.value != null}.size : (Int)data["knownSamples"]
          known:=data == null ? l.knownTotal(ticks) : (EnerCubixValue)data["known"]
          if (knownCount > 0) known=known.scale(1f/knownCount.toFloat)
          fields:=EnerCubixKnownUsage.fields(known).set("knownSamples",knownCount)
          row.setAll(fields); point.setAll(fields)
        }
        rows.add(row)
      }
      series.add(seriesMap(l,points))
      classified:=frozen == null ? l.ticks.map |tick->Str| {bandOf(tick)}.unique : EnerCubixMath.strings(frozen["classified"])
      bands:=classified == ["unknown"] ? ["unknown"] : ["sharp","peak","flat","valley","mixed","unknown"]
      if (classified.contains("unknown")) ctx.warn("部分时段未配置尖峰谷平分类，保留为未分类")
      bands.each |band|
      {
        ticks:=l.ticks.findAll |t| { bandOf(t) == band }
        data:=frozen == null ? null : ((Map)frozen["bands"])[band] as Map
        count:=data == null ? ticks.size : (Int)data["samples"]
        total:=count == 0 ? EnerCubixValue(0f,"ok") : (data == null ? EnerCubixValue.sum(ticks.map |t->EnerCubixValue| { t.value }) : (EnerCubixValue)data["value"])
        if (count>0 && (l.gauge || l.ratio))
        {
          total=EnerCubixValue(null,"invalidMetric",total.sources)
          ctx.warn("${l.name}: 尖峰谷平区间总量需要能耗计量数据")
        }
        row:=baseRow(l,"band:$band",total); row["band"]=band
        if (displaysKnown(l)) row.setAll(EnerCubixKnownUsage.fields(count == 0 ? EnerCubixValue(0f,"ok") : (data == null ? l.knownTotal(ticks) : (EnerCubixValue)data["known"])))
        loadBands.add(row)
      }
    }
    extra["aggregation"]="mean energy for each hour of day"
    extra["loadBands"]=loadBands
    extra["loadBandsAggregation"]="intervalTotal"
  }

  private Void working(EnerCubixLine[] lines)
  {
    if(consumedMeters != null) ctx.warningScope(2,-1,0)
    available:=kind == "workingHours" ? (request["workHours"] ?: ctx.calendar?.get("workHours")) != null : ctx.calendar?.get("workDays") != null
    if (!available) ctx.warn("Work calendar is required")
    lines.each |l|
    {
      work:=l.ticks.findAll |t| { ctx.working(t.ts,kind == "workingHours",request["workHours"]) }
      off:=l.ticks.findAll |t| { !ctx.working(t.ts,kind == "workingHours",request["workHours"]) }
      frozen:=consumedWorking[l.id]
      a:=!available ? EnerCubixValue(null,"missingCalendar") : (frozen == null ? l.total(work) : (EnerCubixValue)frozen[0]["value"])
      b:=!available ? EnerCubixValue(null,"missingCalendar") : (frozen == null ? l.total(off) : (EnerCubixValue)frozen[1]["value"])
      if (available && frozen == null && work.isEmpty) a=EnerCubixValue(0f,"ok")
      if (available && frozen == null && off.isEmpty) b=EnerCubixValue(0f,"ok")
      row:=baseRow(l,"working",l.total); row["working"]=a.value; row["nonworking"]=b.value
      row["workingPercentage"]=EnerCubixValue.divide(a,EnerCubixValue.sum([a,b])).scale(100f).value
      row["workingQuality"]=a.quality; row["nonworkingQuality"]=b.quality
      rows.add(row)
      points:=[a.point(from),b.point(from)]
      points[0]["label"]="working"; points[1]["label"]="nonworking"
      if (displaysKnown(l))
      {
        knownWork:=!available ? EnerCubixValue(null,"missingCalendar") : (frozen == null ? (work.isEmpty ? EnerCubixValue(0f,"ok") : l.knownTotal(work)) : (EnerCubixValue)frozen[0]["known"])
        knownOff:=!available ? EnerCubixValue(null,"missingCalendar") : (frozen == null ? (off.isEmpty ? EnerCubixValue(0f,"ok") : l.knownTotal(off)) : (EnerCubixValue)frozen[1]["known"])
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
    if (metric == "cost")
    {
      extra["costBasis"]="closedIntervalsAtStartTariff"
      tariffs:=ctx.usedTariffs.dup
      if (knownCtx != null) tariffs.setAll(knownCtx.usedTariffs)
      extra["tariffSnapshot"]=tariffs.keys.sort.map |id->[Str:Obj?]| {tariffs[id]}
    }
    if (knownCtx == null && !["trend"].contains(kind)) extra["usagePolicy"]=kind == "forecast" ? "completeTrainingHistoryRequired" : (metric == "cost" ? "billingRequiresCompleteCoverage" : (kind == "regression" ? "completePairsRequired" : "comparableCoverageRequired"))
    warnings:=ctx.orderedWarnings
    return ["kind":kind,"from":from.toIso,"to":to.toIso,"asOf":dataCutoff.toIso,"period":period,"series":series,"rows":rows,"warnings":consumedMeters == null ? warnings : warnings.dup,"summary":summary,"extra":extra]
  }
}





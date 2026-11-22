internal class FinEnergyReport
{
  new make(FinEnergyContext ctx, Str:Obj? request, DateTime from, DateTime to, Str kind, Str period, Str metric,FinEnergyPreparedOwner? catalogOwner := null,Bool summaryFrames := false)
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
    areas=ctx.sharedCatalog?.areas ?: FinEnergyArea(ctx.byId.vals)
    dataCutoff=FinEnergyKnownUsage.cutoff(request)
    if (FinEnergyKnownUsage.supported(kind,metric))
    {
      knownCtx=FinEnergyContext.known(ctx,to < dataCutoff ? to : dataCutoff)
    }
  }
  private FinEnergyArea areas
  private Bool sharedAreas := false
  private FinEnergyPreparedOwner? catalogOwner
  private FinEnergyContext ctx
  private FinEnergyContext? knownCtx
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
  private [Str:FinEnergyValue]? consumedMeters
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
  private FinEnergyPreparedOwner? metadataPlanOwner
  private FinEnergyLine[] metadataPlanLines := [,]
  private [Str:Int]? metadataPlanShape
  internal const Bool summaryFrames

  ** Membership, topology quality and service area depend only on the frozen
  ** catalog. Resolve them before consuming history, rather than rebuilding
  ** whole-catalog candidate/area graphs at the simultaneous output peak.
  internal Str:Int freezeFrameMetadata(FinEnergyLine[] lines,FinEnergyPreparedOwner output)
  {
    if(catalogOwner==null || output.budget!==catalogOwner.budget) throw ArgErr("frameMetadataPlan")
    if(metadataPlanShape!=null)
    {
      if(metadataPlanOwner!==output || metadataPlanLines.size!=lines.size || !lines.all |line,i| {line===metadataPlanLines[i]}) throw ArgErr("frameMetadataPlan")
      return metadataPlanShape
    }
    if(finalMetadataFrozen) throw ArgErr("frameMetadataPlan")
    scratch:=FinEnergyPreparedOwner(output.budget)
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
        raw:=selectionGroup(lines,category);selected:=(FinEnergyLine[])raw["selected"];candidates:=([Str:Obj?][])raw["candidates"];meters:=([Str:Obj?][])raw["meters"]
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
  private Str:Int rememberFrameMetadata(Str:Int shape,FinEnergyLine[] lines,FinEnergyPreparedOwner output)
  {
    output.hold(7+lines.size);metadataPlanOwner=output;metadataPlanLines=lines.dup;metadataPlanShape=shape
    output.watch |->Void| {metadataPlanLines.clear;metadataPlanShape?.clear;metadataPlanShape=null;metadataPlanOwner=null}
    return shape
  }
  internal Int frameFinalDepth() {finalMetadataFrozen ? finalDepth : ctx.byId.size}
  internal Int frameMemberCount() {metadataPlanShape?.get("members") ?: 0}
  internal [Str:Obj?][] frameScope(FinEnergyLine line)
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
    finalSelections.each |g| {((List)g["selected"]).clear;((List)g["candidates"]).clear;((List)g["meters"]).clear;area:=g["area"] as Map;if(area!=null) FinEnergyArea.clearResult(area);g.clear};finalSelections.clear;finalMetadataFrozen=false;finalDepth=0
  }

  internal Bool acceptsFrames()
  { ["profile","primary","ranking","proportion","dashboard","daily","utility","workingHours","workingDays"].contains(kind) && request["otherFrom"] == null && FinEnergyMath.strings(request["referenceIds"]).isEmpty }
  internal Bool frameSharesBase(FinEnergyLine line) {request["perArea"]!=true && !line.gauge && !line.ratio && !line.leak && !line.reference}
  internal Bool dailyFrames() {kind == "daily"}
  internal Bool canSizeUtilityOutput()
  {kind=="utility" && metric=="energy" && request["perArea"]!=true && finalMetadataFrozen}
  internal Bool canSizeDailyOutput()
  {
    if(!dailyFrames || metric!="energy" || request["perArea"]==true || !finalMetadataFrozen) return false
    // Each category's selection row is covered by its existing meter ledger
    // allowance. Empty categories keep the unchanged general envelope.
    return finalSelections.all |group| {meters:=group["meters"] as List;return meters!=null && !meters.isEmpty}
  }
  // Fixed result/maps/list heads and field links, plus the final warnings copy
  // and at most one new unclassified-band warning for physical energy lines.
  internal Int dailyOutputCommonEntries() {64+ctx.warnings.size+2}
  internal Bool workingFrames() {["workingHours","workingDays"].contains(kind)}
  internal Bool frameWorking(FinEnergyTick tick) {ctx.working(tick.ts,kind == "workingHours",request["workHours"])}
  internal Str frameBand(FinEnergyLine line,FinEnergyTick tick)
  {ctx.timeBand(line.nodeId,line.category,tick.ts,tick.end,line.utility)}
  internal Bool ownedFrameCatalog(FinEnergyPreparedOwner owner) {catalogOwner === owner}
  internal [Str:Obj?][] frameReads() {knownCtx?.knownReads?.vals ?: [Str:Obj?][,]}
  internal Bool frameEmptyOmitted() {knownCtx?.emptyEvidenceOmitted ?: false}
  internal Bool frameUnpreparedOmitted() {knownCtx?.unpreparedEvidenceOmitted ?: false}
  internal FinEnergyValue frameMeter(Str id,Str category,DateTime start,DateTime end,Bool known)
  { (known ? knownCtx : ctx).node(id,category,start,end,metric) }
  internal Bool constantEmptyMeters() {ctx.timeInvariantEmpty(metric)}
  internal Void eachFrameOutputRoot(|Obj?| visit)
  {visit(consumedPeriods);visit(consumedMeters);visit(consumedCoverage);visit(consumedEvidence);visit(consumedDaily);visit(consumedWorking)}
  internal Str:Obj? finishFrames(FinEnergyLine[] lines,Str:Str:Obj? periods,Str:FinEnergyValue meters,Str:[Str:Obj?] coverage,Str:Obj? evidence,Str:[Str:Obj?] daily := [:],Str:[Str:Obj?][] working := [:])
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

  internal Void beginFrame(FinEnergyPreparedOwner owner,Str:FinEnergyHistoryData histories,Bool constantEmpty := false)
  {ctx.beginFrame(owner,histories,constantEmpty);knownCtx?.beginFrame(owner,histories,constantEmpty)}

  FinEnergyLine line(Str id, Str category, Str? utility := null, DateTime start := from, DateTime end := to)
  {
    cursor:=openLine(id,category,utility,start,end)
    while(cursor.more) cursor.line.ticks.add(cursor.next)
    return cursor.finish
  }

  internal FinEnergyLineCursor openLine(Str id,Str category,Str? utility := null,DateTime start := from,DateTime end := to)
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
    out:=FinEnergyLine("$id|$category"+(utility == null ? "" : "|$utility"),id,name,category,ctx.unit(id,category,metric))
    out.utility=utility
    if(needsArea)
    {
      out.normalizationArea=areas.node(id)
      if (ctx.dimension?.dimension == "organization" && ctx.dimension.scope(id))
        out.normalizationArea=areas.selection([id],ctx.dimension,ctx.selectionMeters(ctx.scopeMeters(id,category)).map |m->Str| {m["id"].toStr})
      catalogOwner?.watch |->Void| {if(!out.outputOwnsArea) FinEnergyArea.clearResult(out.normalizationArea)}
    }
    activeKnown:=knownCtx
    if (knownCtx != null && end != to) activeKnown=FinEnergyContext.known(ctx,end < dataCutoff ? end : dataCutoff)
    out.gauge=r?.get("kind") == "sensor"
    out.ratio=kind == "cop" || r?.get("kind") == "cop"
    out.leak=kind == "leak"
    if (out.leak && ctx.dimension != null) out.balanceMode=FinEnergyBalance.mode(ctx,id)
    if (out.ratio) out.unit="COP"
    Str? directQuality:=null
    if (ctx.dimension != null && out.leak) directQuality=ctx.comparison == null ? ctx.dimension.leakQuality(id) : ctx.comparison.quality(id)
    else if (kind != "utility" && ctx.dimension?.dimension == "organization" && r != null && ["meter","totalMeter"].contains(r["kind"]?.toStr ?: "")) directQuality=ctx.dimension.quality([r])
    read:=|DateTime cursor,DateTime next->FinEnergyTick|
    {
      FinEnergyValue value := FinEnergyValue()
      FinEnergyValue? numerator:=null; FinEnergyValue? denominator:=null
      FinEnergyValue? known:=null
      if (out.ratio)
      {
        if (r?.get("kind") != "cop") value=FinEnergyValue(null,"missingCopDefinition")
        else
        {
          numerator=ctx.nodeTotal(r["numeratorId"]?.toStr ?: "",cursor,next)
          denominator=ctx.nodeTotal(r["denominatorId"]?.toStr ?: "",cursor,next)
          value=FinEnergyValue.divide(numerator,denominator)
        }
      }
      else if (out.leak)
      {
        if (ctx.dimension != null)
        {
          members:=leakMembers(id,category)
          numerator=ctx.node(id,category,cursor,next,metric)
          denominator=members.isEmpty ? FinEnergyValue(null,"missingBranches") : FinEnergyValue.sum(members.map |m->FinEnergyValue| { ctx.node(m["id"].toStr,category,cursor,next,metric) })
          value=FinEnergyValue.sum([numerator,denominator.scale(-1f)])
          if (directQuality != null) value=FinEnergyValue(null,directQuality,value.sources)
        }
        else if (r?.get("kind") != "group") value=FinEnergyValue(null,"groupRequired")
        else
        {
          masters:=(ctx.children[id] ?: [Str:Obj?][,]).findAll |m| { m["kind"] == "totalMeter" && (m["categoryId"]?.toStr ?: "") == category && ctx.included(m) }
          numerator=masters.size == 1 ? ctx.node(masters.first["id"].toStr,category,cursor,next,metric) : FinEnergyValue(null,masters.isEmpty ? "missingMaster" : "ambiguousMaster")
          denominator=ctx.branch(id,category,cursor,next,metric)
          value=FinEnergyValue.sum([numerator,denominator.scale(-1f)])
        }
      }
      else
      {
        value=ctx.node(id,category,cursor,next,metric,Str#.emptyList,utility)
        if (directQuality != null) value=FinEnergyValue(null,directQuality,value.sources)
        if (activeKnown != null && !out.gauge)
        {
          known=activeKnown.node(id,category,cursor,next,metric,Str#.emptyList,utility)
          if (kind == "utility" && value.value == null && value.quality == "missing" && known.quality == "na") value=FinEnergyValue(null,"na",value.sources)
        }
      }
      if (out.leak && (numerator?.reliable == false || denominator?.reliable == false))
        value=FinEnergyValue(null,FinEnergyValue.worse(numerator?.quality ?: "missing",denominator?.quality ?: "missing"),value.sources)
      baseValue:=value; baseKnown:=known; baseNumerator:=numerator; baseDenominator:=denominator
      if (request["perArea"] == true)
      {
        if (out.ratio) ctx.warn("COP is a ratio; per-area normalization does not apply")
        else
        {
          value=FinEnergyArea.scale(value,out.normalizationArea)
          if (known != null) known=FinEnergyArea.scale(known,out.normalizationArea)
          if (numerator != null) numerator=FinEnergyArea.scale(numerator,out.normalizationArea)
          if (denominator != null) denominator=FinEnergyArea.scale(denominator,out.normalizationArea)
        }
      }
      if (value.value == null) ctx.warnLine(out.name,value.quality)
      tick:=FinEnergyTick(cursor,next,value,numerator,denominator); tick.known=known
      tick.baseValue=baseValue;tick.baseKnown=baseKnown;tick.baseNumerator=baseNumerator;tick.baseDenominator=baseDenominator
      return tick
    }
    if (request["perArea"] == true && !out.ratio) out.unit+="/m²"
    return FinEnergyLineCursor(out,start,end,kind == "comparison" && request["comparisonAlignment"] == "duration",read,|->Void|
    {if(activeKnown != null && activeKnown !== knownCtx) knownCtx.mergeKnown(activeKnown)})
  }

  Str:Obj? forecast(FinEnergyLine[] lines)
  {
    forecasts:=[Str:Obj?][,]; backtests:=[Str:Obj?][,]; scores:=[Str:Obj?][,]
    meterFits:=Str:[Str:Obj?][:]
    horizon:=(FinEnergyMath.num(request["forecastDays"]) ?: 7f).toInt
    lines.each |line| {
      dates:=DateTime[,]; values:=Float?[,]; historyPoints:=[Str:Obj?][,]; sources:=Str[,]
      forecastDailyTotals(line).each |amount,cursor|
      {
        value:=amount
        if (value.value != null && value.value < 0f) value=FinEnergyValue(null,"negative",value.sources)
        dates.add(cursor); values.add(value.reliable ? value.value : null); sources.addAll(value.sources)
        point:=value.point(cursor); historyPoints.add(point)
        rows.add(point.dup.setAll(["id":line.id,"nodeId":line.nodeId,"name":line.name,"categoryId":line.category,"unit":line.unit,"phase":"history"]))
      }
      fit:=Str:Obj?[:]
      if (metric == "cost")
      {
        members:=ctx.scopeMeters(line.nodeId,line.category)
        fits:=members.map |meter->[Str:Obj?]|
        {
          id:=meter["id"].toStr
          if (!meterFits.containsKey(id))
          {
            own:=this.line(id,line.category)
            daily:=forecastDailyTotals(own).vals.map |amount->Float?| {amount.reliable ? amount.value : null}
            meterFits[id]=FinEnergyForecast.fit(daily,horizon)
          }
          return meterFits[id]
        }
        fit=FinEnergyCostForecast.combine(fits,values,horizon)
      }
      else fit=FinEnergyForecast.fit(values,horizon)
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
          total+=value; future=FinEnergyMath.nextBucket(future,"day")
        }
        meta["predictedTotal"]=total
        series.add(["id":line.id+"|forecast","nodeId":line.nodeId,"name":line.name+" · 预测","categoryId":line.category,"unit":line.unit,"role":"forecast","points":futurePoints])
        FinEnergyMath.maps(fit["backtests"]).each |pair| { backtests.add(pair.dup.setAll(["id":line.id,"categoryId":line.category,"unit":line.unit,"name":line.name,"ts":dates[(Int)pair["index"]].toIso,"trainingEnd":dates[(Int)pair["origin"]].toIso])) }
        FinEnergyMath.maps(fit["modelScores"]).each |score| { scores.add(score.dup.setAll(["id":line.id,"categoryId":line.category,"unit":line.unit,"name":line.name])) }
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
      summary["forecastTotals"]=[["meterIds":ids,"unit":"元","value":valid && FinEnergyMath.num(total) != null ? total : null,"quality":valid ? "predicted" : "insufficientHistory"]]
      extra["forecastBasis"]="historicalMeterCostPatterns";extra["forecastMeterIds"]=ids
    }
    recordLineAreas(lines)
    return result
  }

  private DateTime:FinEnergyValue forecastDailyTotals(FinEnergyLine line)
  {
    result:=DateTime:FinEnergyValue[:] {ordered=true}
    ticks:=line.ticks
    index:=0
    cursor:=from
    while(cursor<to)
    {
      end:=FinEnergyMath.nextBucket(cursor,"day")
      fold:=FinEnergyLineFold(line,"value")
      while(index<ticks.size && ticks[index].ts<end)
      {
        tick:=ticks[index++]
        if(tick.ts>=cursor) fold.add(tick)
      }
      result[cursor]=fold.finish
      cursor=end
    }
    return result
  }

  FinEnergyLine referenceLine(Str id, Bool raw := false)
  {
    record:=ctx.byId[id]
    point:=record?.get("pointId")?.toStr ?: id
    history:=ctx.byPoint[point]
    out:=FinEnergyLine(id+(raw ? "|reference" : ""),id,ctx.displayName(id),"",history?.unit ?: "")
    out.gauge=raw || history == null || history.mode == "sampled" || history.mode == "cov"
    out.reference=raw
    cursor:=from
    while (cursor < to)
    {
      next:=FinEnergyMath.floorHour(cursor)+1hr; if (next > to) next=to
      value:=history?.read(cursor,next,raw) ?: FinEnergyValue()
      if (value.value == null) ctx.warn("${out.name}: ${value.quality}")
      out.ticks.add(FinEnergyTick(cursor,next,value)); cursor=next
    }
    return out
  }

  Str:Obj? finish(FinEnergyLine[] lines)
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
      if(request["_profileFirst"]!=true) extra["knownUsage"]=(consumedEvidence ?: knownCtx.knownEvidence).set("asOf",dataCutoff.toIso)
    }
    recordLineAreas(lines)
    if (kind == "leak") leakTotals(lines)
    if (kind == "utility") extra["details"]=extra["utilityMembers"]
    else if (ctx.dimension != null && request["_profileFirst"]!=true) dimensionDetails(lines)
    return result
  }

  private Void recordLineAreas(FinEnergyLine[] lines)
  {
    if (request["perArea"] == true) lines.findAll |l| {!l.reference && !l.gauge && !l.ratio}.each |l|
    {
      base:=displaysKnown(l) ? l.baseKnownTotal : l.baseTotal
      recordArea(l.nodeId,l.name,l.category,base,l.baseUnit,available(l),l.unit,l.normalizationArea,l.leak ? "difference" : "ownUsage")
    }
  }

  private Void recordArea(Str id, Str? name, Str category, FinEnergyValue base, Str baseUnit, FinEnergyValue value, Str unit, Str:Obj? area, Str basis)
  {
    list:=extra["areaBasis"] as List
    if (list == null) {list=[Str:Obj?][,];extra["areaBasis"]=list}
    row:=Str:Obj?["nodeId":id,"categoryId":category,"baseValue":base.value,"baseUnit":baseUnit,"value":value.value,"unit":unit,"area":area,"basis":basis]
    if (name != null) row["name"]=name
    list.add(row)
  }

  private Str:Obj? leakBase(FinEnergyLine line, FinEnergyTick[] ticks)
  {
    total:=FinEnergyValue.sum(ticks.map |t->FinEnergyValue| {t.baseNumerator ?: FinEnergyValue()})
    sub:=FinEnergyValue.sum(ticks.map |t->FinEnergyValue| {t.baseDenominator ?: FinEnergyValue()})
    difference:=FinEnergyValue.sum(ticks.map |t->FinEnergyValue| {t.baseValue ?: t.value})
    return ["total":total.value,"submeter":sub.value,"difference":difference.value,"unit":line.baseUnit]
  }

  private Void dimensionDetails(FinEnergyLine[] lines)
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
        if (knownCtx != null) row.setAll(FinEnergyKnownUsage.fields(meterTotal(id,category,true)))
        details.add(row)
      }
    }
    extra["details"]=details
  }

  private [Str:Obj?][] detailMembers(FinEnergyLine line)
  {
    category:=FinEnergyDimension.cockpitRangeCategory(request)
    if(finalMetadataFrozen) return finalDetails[line.id]
    members:=kind == "utility" ? ctx.dimension.usageMembers(line.nodeId) : ctx.dimension.members(line.nodeId)
    own:=ctx.byId[line.nodeId]
    if(members.isEmpty && own != null && ["meter","totalMeter"].contains(own["kind"]?.toStr ?: "")) members=[own]
    if(kind == "leak")
    {
      members=leakMembers(line.nodeId,line.category).dup
      if(own != null) members.insert(0,own)
    }
    if(category!=null && ctx.dimension?.scope(line.nodeId)==true) members=members.findAll |m| {m["categoryId"]==category}
    return members
  }

  private Str:Obj? selectionGroup(FinEnergyLine[] lines,Str category)
  {
    if(finalMetadataFrozen) return finalSelections[category]
    selected:=lines.findAll |line| {!line.reference && line.category == category}
    candidates:=selected.map |line->[Str:Obj?][]| {frameScope(line)}.flatten
    return ["selected":selected,"candidates":candidates,"meters":ctx.selectionMeters(candidates)]
  }

  ** Own-meter totals used after line consumption. Reuse the same selection and
  ** detail membership as normal finalization; this is not a history read plan.
  internal [Str:Obj?][] frameLedger(FinEnergyLine[] lines)
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
      {order=categoryIndex*(ctx.byId.size+1);FinEnergyMath.maps(selectionGroup(lines,category)["meters"]).each |meter| {add(meter["id"].toStr,category,1)}}
    order=0
    if(!summaryFrames && ctx.dimension != null && kind != "utility") lines.findAll |line| {!line.reference}.each |line|
    {detailMembers(line).each |meter| {add(meter["id"].toStr,meter["categoryId"] as Str ?: "",3)}}
    return out
  }

  ** Bounds count occurrences, not globally unique meters: one member can occur
  ** in several scope rows. Duplicate-category lines may over-reserve safely.
  internal Str:Int frameShape(FinEnergyLine[] lines)
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

  private FinEnergyValue meterTotal(Str id, Str category, Bool known := false)
  {
    if(consumedMeters != null) return consumedMeters["$id|$category|$known"] ?: throw ArgErr("consumedMeterNotPlanned")
    values:=FinEnergyValue[,]; cursor:=from
    while (cursor < to)
    {
      end:=FinEnergyMath.floorHour(cursor)+1hr; if (end > to) end=to
      active:=known ? knownCtx : ctx
      value:=active.node(id,category,cursor,end,metric)
      values.add(value)
      constant:=value.value == null ? active.constantEnd(id,category,cursor,to,metric) : null
      cursor=constant ?: end
    }
    return known ? FinEnergyKnownUsage.combine(values) : FinEnergyValue.sum(values)
  }

  private Bool displaysKnown(FinEnergyLine line)
  { knownCtx != null && !line.reference && !line.gauge && !line.ratio && !line.leak }

  private FinEnergyValue available(FinEnergyLine line)
  { displaysKnown(line) ? line.knownTotal : line.total }

  private [Str:Obj?][] selectionTotals(FinEnergyLine[] lines)
  {
    out:=[Str:Obj?][,]
    lines.findAll |l| {!l.reference && !l.gauge && !l.ratio}.map |l->Str| {l.category}.unique.sort.each |Str category,Int categoryIndex|
    {
      group:=selectionGroup(lines,category)
      selected:=(FinEnergyLine[])group["selected"]
      candidates:=([Str:Obj?][])group["candidates"]
      meters:=([Str:Obj?][])group["meters"]
      strict:=FinEnergyValue.sum(meters.map |m->FinEnergyValue| {meterTotal(m["id"].toStr,category)})
      known:=knownCtx == null ? null : FinEnergyKnownUsage.combine(meters.map |m->FinEnergyValue| {meterTotal(m["id"].toStr,category,true)})
      quality:=finalMetadataFrozen ? (group["quality"] as Str) : ctx.dimension?.quality(request["metric"] == "cost" ? candidates.unique : candidates)
      invalid:=selected.find |l| {available(l).value == null && !["missing","incompleteInterval","filtered","substituted","na","reset","negative","maximum","missingArea"].contains(available(l).quality)}
      if (quality == null && invalid != null) quality=available(invalid).quality
      if (quality != null)
      {
        strict=FinEnergyValue(null,quality,strict.sources)
        if (known != null && quality != "accountingIncomplete") known=FinEnergyValue(null,quality,known.sources)
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
        strict=FinEnergyArea.scale(strict,area)
        if (known != null) known=FinEnergyArea.scale(known,area)
        recordArea("__selection__",null,category,base,selected.first?.baseUnit ?: "",known ?: strict,unit,area,"selection")
      }
      row:=Str:Obj?["id":category+"|"+unit,"categoryId":category,"unit":unit,"value":strict.value,"valueType":strict.valueType,"quality":strict.quality,"scopeQuality":quality,"sourceIds":strict.sources,"meterIds":meters.map |m->Str| {m["id"].toStr}]
      if (known != null) row.setAll(FinEnergyKnownUsage.fields(known))
      out.add(row)
    }
    return out
  }

  private Bool overlapping(FinEnergyLine[] lines)
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

  private Str shareBasis(FinEnergyLine[] lines, FinEnergyValue denominator)
  {
    if (overlapping(lines)) return "overlappingScopes"
    if (lines.any |l| {available(l).value != null && available(l).value < 0f}) return "negativeConsumption"
    if (denominator.value == null) return "noKnownUsage"
    return denominator.value == 0f ? "zeroKnownTotal" : "knownUsage"
  }

  private Str:Obj? coverage(FinEnergyLine line)
  {
    if(consumedCoverage != null) return consumedCoverage[line.id] ?: throw ArgErr("consumedCoverageNotPlanned")
    start:=line.ticks.first?.ts ?: from; finish:=line.ticks.last?.end ?: to
    meters:=frameScope(line)
    Str[] points:=meters.map |m->Str| {m["pointId"] as Str ?: ""}
    points=points.findAll |id| {!id.isEmpty}.unique
    reads:=knownCtx.knownReads.vals.findAll |r| {points.contains(r["pointId"]) && DateTime.fromIso(r["from"].toStr) >= start && DateTime.fromIso(r["to"].toStr) <= finish}
    reads=FinEnergyKnownUsage.coverageOrder(reads)
    seconds:=(finish-start).ticks.toFloat/1sec.ticks.toFloat
    covered:=points.map |point->Float|
    {
      total:=0f; reads.findAll |r| {r["pointId"] == point}.each |r| {total+=FinEnergyMath.num(r["coveredSeconds"]) ?: 0f}; return total
    }
    amount:=covered.isEmpty ? 0f : (Float)covered.min
    starts:=reads.findAll |r| {r["intervalStart"] != null}.map |r->DateTime| {DateTime.fromIso(r["intervalStart"].toStr)}
    ends:=reads.findAll |r| {r["intervalEnd"] != null}.map |r->DateTime| {DateTime.fromIso(r["intervalEnd"].toStr)}
    return frameCoverage(line,["coveredSeconds":amount,"expectedSeconds":seconds,"coverage":seconds > 0f ? (amount/seconds).min(1f) : 0f,"coverageStart":starts.isEmpty ? null : ((DateTime)starts.min).toIso,"coverageEnd":ends.isEmpty ? null : ((DateTime)ends.max).toIso])
  }

  internal Str:Obj? frameCoverage(FinEnergyLine line,Str:Obj? stats)
  {
    value:=line.knownTotal
    meters:=frameScope(line)
    return Str:Obj?["id":line.id,"nodeId":line.nodeId,"name":line.name,"categoryId":line.category,"unit":line.unit,"knownValue":value.value,"knownQuality":value.quality,"complete":line.total.value != null && line.total.reliable && (Float)stats["coveredSeconds"] >= (Float)stats["expectedSeconds"],"meterIds":meters.map |m->Str| {m["id"].toStr}].setAll(stats)
  }

  private [Str:Obj?][] utilityTotals(FinEnergyLine[] lines)
  {
    out:=[Str:Obj?][,]
    lines.map |l->Str| {l.category+"|"+l.unit}.unique.sort.each |Str key|
    {
      group:=lines.findAll |l| {l.category+"|"+l.unit == key}
      out.add(utilityAggregate(group).setAll(["id":key,"categoryId":group.first.category,"unit":group.first.unit]))
    }
    return out
  }

  private Str:Obj? utilityAggregate(FinEnergyLine[] group)
  {
    readings:=group.map |l->FinEnergyValue| {l.total}
    meters:=group.map |l->[Str:Obj?]| {ctx.byId[l.nodeId]}
    overlap:=FinEnergyEndUse.overlap(ctx,meters,readings)
    value:=FinEnergyValue.sum(readings)
    known:=FinEnergyKnownUsage.combine(group.map |l->FinEnergyValue| {l.knownTotal})
    if (overlap)
    {
      value=FinEnergyValue(null,"overlappingScopes",value.sources)
      known=FinEnergyValue(null,"overlappingScopes",known.sources)
    }
    else if (request["perArea"] == true)
    {
      value=FinEnergyValue(null,"areaNormalized",value.sources)
      known=FinEnergyValue(null,"areaNormalized",known.sources)
    }
    row:=Str:Obj?["value":value.value,"valueType":value.valueType,"quality":value.quality,"scopeQuality":overlap ? "overlappingScopes" : null,"sourceIds":value.sources,"meterIds":group.map |l->Str| {l.nodeId}]
    if (knownCtx != null) row.setAll(FinEnergyKnownUsage.fields(known))
    return row
  }

  private Void utilityShares(FinEnergyLine[] lines)
  {
    members:=[Str:Obj?][,];shares:=[Str:Obj?][,]
    lines.each |l|
    {
      record:=ctx.byId[l.nodeId]; utility:=record["utilityId"] as Str ?: ""
      value:=l.total
      row:=Str:Obj?["id":l.id,"nodeId":l.nodeId,"name":ctx.displayName(l.nodeId),"utilityId":utility,"utilityName":ctx.byId[utility]?.get("name") ?: "","categoryId":l.category,"unit":l.unit,"value":value.value,"valueType":value.valueType,"quality":value.quality,"sourceIds":value.sources,"counted":true]
      if (knownCtx != null) row.setAll(FinEnergyKnownUsage.fields(l.knownTotal)).setAll(coverage(l))
      members.add(row)
    }
    lines.map |l->Str| {l.category+"|"+l.unit}.unique.sort.each |Str key|
    {
      group:=lines.findAll |l| {l.category+"|"+l.unit == key}
      total:=utilityAggregate(group)
      strict:=FinEnergyMath.num(total["value"]); known:=knownCtx == null ? strict : FinEnergyMath.num(total["knownValue"])
      overlap:=total["scopeQuality"] == "overlappingScopes"
      negative:=group.any |l| {l.total.quality == "negative" || l.knownTotal.quality == "negative" || (l.total.value != null && l.total.value < 0f) || (l.knownTotal.value != null && l.knownTotal.value < 0f)}
      basis:=overlap ? "overlappingScopes" : (request["perArea"] == true ? "areaNormalized" : (negative ? "negativeConsumption" : (known == null ? "noKnownUsage" : (known == 0f ? "zeroKnownTotal" : "knownUsage"))))
      group.map |l->Str| {ctx.byId[l.nodeId]?.get("utilityId") as Str ?: ""}.unique.sort.each |utility|
      {
        subset:=group.findAll |l| {(ctx.byId[l.nodeId]?.get("utilityId") as Str ?: "") == utility}
        row:=utilityAggregate(subset)
        row.setAll(["id":key+"|"+utility,"name":ctx.byId[utility]?.get("name") ?: utility,"utilityId":utility,"categoryId":group.first.category,"unit":group.first.unit,"percentageBasis":basis])
        v:=FinEnergyMath.num(row["value"]);k:=FinEnergyMath.num(row["knownValue"])
        percentage:=FinEnergyValue.divide(FinEnergyValue(v,row["quality"].toStr),FinEnergyValue(strict,total["quality"].toStr)).scale(100f)
        row["percentage"]=basis == "knownUsage" ? percentage.value : null
        if (knownCtx != null) row["knownPercentage"]=basis == "knownUsage" && k != null ? k/known*100f : null
        row["percentageQuality"]=basis == "knownUsage" ? percentage.quality : basis
        shares.add(row)
      }
    }
    extra["utilityShares"]=shares;extra["utilityMembers"]=members
    extra["scopeTotals"]=summary["selectionTotals"]
  }

  private Void append(FinEnergyLine l, Str gran)
  {
    if(consumedPeriods.containsKey(l.id))
    {
      points:=[Str:Obj?][,]
      FinEnergyMath.maps(consumedPeriods[l.id]["rows"]).each |item|
      {
        at:=DateTime.fromIso(item["ts"].toStr);value:=(FinEnergyValue)item["value"]
        point:=value.point(at);row:=baseRow(l,at.toIso,value);row["ts"]=at.toIso
        if(displaysKnown(l))
        {
          known:=(FinEnergyValue)item["known"]
          fields:=FinEnergyKnownUsage.fields(known).set("bucketEnd",FinEnergyMath.nextBucket(at,gran).toIso)
          point.setAll(fields);row.setAll(fields)
        }
        points.add(point);rows.add(row)
      }
      series.add(seriesMap(l,points));return
    }
    grouped:=Str:FinEnergyTick[][:]; order:=Str[,]; timestamps:=Str:DateTime[:]
    l.ticks.each |t|
    {
      at:=FinEnergyMath.bucket(t.ts,gran)
      if (kind == "comparison" && request["comparisonAlignment"] == "duration")
      {
        start:=l.ticks.first.ts
        step:=gran == "hour" ? 1hr.ticks : (gran == "week" ? 7day.ticks : 1day.ticks)
        at=start+Duration((t.ts-start).ticks/step*step)
      }
      key:=at.toIso
      if (!grouped.containsKey(key)) { grouped[key]=FinEnergyTick[,]; order.add(key); timestamps[key]=at }
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
        fields:=["knownValue":known.value,"knownValueType":known.valueType,"knownQuality":known.quality,"bucketEnd":FinEnergyMath.nextBucket(at,gran).toIso]
        p.setAll(fields); row.setAll(fields)
      }
      if (l.leak)
      {
        total:=FinEnergyValue.sum(ticks.map |t->FinEnergyValue| { t.numerator ?: FinEnergyValue() })
        sub:=FinEnergyValue.sum(ticks.map |t->FinEnergyValue| { t.denominator ?: FinEnergyValue() })
        row["total"]=total.value; row["submeter"]=sub.value; row["difference"]=v.value
        if (request["perArea"] == true) row["baseUsage"]=leakBase(l,ticks)
        row["totalQuality"]=total.quality; row["submeterQuality"]=sub.quality
        row["balanceMode"]=l.balanceMode; row["lossEligible"]=physicalMetric && v.value != null && v.value >= 0f && FinEnergyBalance.eligible(l.balanceMode,total,sub)
        row["percentage"]=physicalMetric && l.balanceMode == "independent" ? FinEnergyValue.divide(v,total).scale(100f).value : null
        if (v.value != null && v.value < 0f) ctx.warn("${l.name}: 分表合计大于总表，差额为负，请核对计量关系与数据")
        branchRows:=extra["leakBranches"] as List
        if (branchRows == null) { branchRows=[Str:Obj?][,]; extra["leakBranches"]=branchRows }
        leakMembers(l.nodeId,l.category).each |branch|
        {
          branchId:=branch["id"].toStr
          branchValue:=FinEnergyValue.sum(ticks.map |t->FinEnergyValue| { ctx.node(branchId,l.category,t.ts,t.end,metric) })
          if (request["perArea"] == true)
          {
            branchValue=FinEnergyArea.scale(branchValue,l.normalizationArea)
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

  private Void leakTotals(FinEnergyLine[] lines)
  {
    extra["leakTotals"]=lines.map |l->[Str:Obj?]|
    {
      total:=FinEnergyValue.sum(l.ticks.map |t->FinEnergyValue| { t.numerator ?: FinEnergyValue() })
      sub:=FinEnergyValue.sum(l.ticks.map |t->FinEnergyValue| { t.denominator ?: FinEnergyValue() })
      difference:=l.total
      row:=baseRow(l,"summary",difference)
      row["total"]=total.value; row["submeter"]=sub.value; row["difference"]=difference.value
      if (request["perArea"] == true) row["baseUsage"]=leakBase(l,l.ticks)
      row["totalQuality"]=total.quality; row["submeterQuality"]=sub.quality
      row["balanceMode"]=l.balanceMode; row["lossEligible"]=physicalMetric && difference.value != null && difference.value >= 0f && FinEnergyBalance.eligible(l.balanceMode,total,sub)
      row["percentage"]=physicalMetric && l.balanceMode == "independent" ? FinEnergyValue.divide(difference,total).scale(100f).value : null
      return row
    }
  }

  private Bool physicalMetric() {ctx.comparison == null || metric == "energy"}

  private Void totals(FinEnergyLine[] lines)
  {
    strict:=FinEnergyValue[,]
    usage:=FinEnergyValue[,]
    groups:=Str:Int[][:]
    lines.each |l,index|
    {
      value:=l.total
      strict.add(value)
      usage.add(displaysKnown(l) ? l.knownTotal : value)
      key:="${l.category}|${l.unit}"
      if(!groups.containsKey(key)) groups[key]=Int[,]
      groups[key].add(index)
    }
    order:=lines.map |l,index->Int| {index}
    order.sort |a,b| {(usage[b].value ?: Float.negInf) <=> (usage[a].value ?: Float.negInf)}
    denominators:=Str:FinEnergyValue[:]
    knownDenominators:=Str:FinEnergyValue[:]
    bases:=Str:Str[:]
    groups.each |group,key|
    {
      denominators[key]=FinEnergyValue.sum(group.map |index->FinEnergyValue| {strict[index]})
      if(group.any |index| {displaysKnown(lines[index])})
      {
        knownDenominators[key]=FinEnergyKnownUsage.combine(group.map |index->FinEnergyValue| {usage[index]})
        bases[key]=shareBasis(group.map |index->FinEnergyLine| {lines[index]},knownDenominators[key])
      }
    }
    ranks:=Str:Int[:]
    order.each |index|
    {
      l:=lines[index];v:=strict[index]; key:="${l.category}|${l.unit}"
      rank:=(ranks[key] ?: 0)+1
      if (usage[index].value != null) ranks[key]=rank
      row:=baseRow(l,"total",v); row["rank"]=usage[index].value == null ? null : rank
      row["percentage"]=FinEnergyValue.divide(v,denominators[key]).scale(100f).value
      point:=v.point(from)
      if (displaysKnown(l))
      {
        known:=usage[index]
        denominator:=knownDenominators[key]
        basis:=bases[key]
        row.setAll(coverage(l)); row.setAll(FinEnergyKnownUsage.fields(known))
        row["knownPercentage"]=basis == "knownUsage" && known.value != null ? known.value/denominator.value*100f : null
        row["percentageBasis"]=basis
        row["rankBasis"]="knownUsage"
        point.setAll(FinEnergyKnownUsage.fields(known))
      }
      rows.add(row)
      series.add(seriesMap(l,[point]))
    }
  }

  private Void daily(FinEnergyLine[] lines)
  {
    loadBands:=[Str:Obj?][,]
    lines.each |l,i|
    {
      if(consumedMeters != null) ctx.warningScope(2,i,0)
      frozen:=consumedDaily[l.id]
      grouped:=Int:FinEnergyTick[][:]
      hourBands:=Int:Str[][:]
      bandTicks:=Str:FinEnergyTick[][:] {ordered=true}
      hours:=FinEnergyMath.maps(frozen?.get("hours"))
      if(frozen==null) l.ticks.each |tick|
      {
        hour:=tick.ts.hour
        band:=ctx.timeBand(l.nodeId,l.category,tick.ts,tick.end,l.utility)
        if(!grouped.containsKey(hour)) {grouped[hour]=FinEnergyTick[,];hourBands[hour]=Str[,]}
        if(!bandTicks.containsKey(band)) bandTicks[band]=FinEnergyTick[,]
        grouped[hour].add(tick)
        if(!hourBands[hour].contains(band)) hourBands[hour].add(band)
        bandTicks[band].add(tick)
      }
      points:=[Str:Obj?][,]
      (0..23).each |hour|
      {
        ticks:=grouped[hour] ?: FinEnergyTick[,]
        data:=frozen == null ? null : hours[hour]
        count:=data == null ? ticks.size : (Int)data["samples"]
        v:=data == null ? l.total(ticks) : (FinEnergyValue)data["value"]
        if (!v.reliable) v=FinEnergyValue(null,v.quality,v.sources)
        if (!l.ratio && !l.gauge && count>0) v=v.scale(1f/count.toFloat)
        at:=from.date.toDateTime(Time(hour,0),ctx.tz)
        distinct:=hourBands[hour] ?: Str[,]
        band:=data != null ? data["band"].toStr : (distinct.size == 1 ? distinct.first : (distinct.isEmpty ? "unknown" : "mixed"))
        point:=v.point(at); point["band"]=band; points.add(point)
        row:=baseRow(l,"hour:$hour",v); row["hour"]=hour; row["ts"]=at.toIso; row["samples"]=count; row["band"]=band
        if (displaysKnown(l))
        {
          knownCount:=data == null ? ticks.findAll |tick| {tick.known?.value != null}.size : (Int)data["knownSamples"]
          known:=data == null ? l.knownTotal(ticks) : (FinEnergyValue)data["known"]
          if (knownCount > 0) known=known.scale(1f/knownCount.toFloat)
          fields:=FinEnergyKnownUsage.fields(known).set("knownSamples",knownCount)
          row.setAll(fields); point.setAll(fields)
        }
        rows.add(row)
      }
      series.add(seriesMap(l,points))
      classified:=frozen == null ? bandTicks.keys : FinEnergyMath.strings(frozen["classified"])
      bands:=classified == ["unknown"] ? ["unknown"] : ["sharp","peak","flat","valley","mixed","unknown"]
      if (classified.contains("unknown")) ctx.warn("部分时段未配置尖峰谷平分类，保留为未分类")
      bands.each |band|
      {
        ticks:=bandTicks[band] ?: FinEnergyTick[,]
        data:=frozen == null ? null : ((Map)frozen["bands"])[band] as Map
        count:=data == null ? ticks.size : (Int)data["samples"]
        total:=count == 0 ? FinEnergyValue(0f,"ok") : (data == null ? FinEnergyValue.sum(ticks.map |t->FinEnergyValue| { t.value }) : (FinEnergyValue)data["value"])
        if (count>0 && (l.gauge || l.ratio))
        {
          total=FinEnergyValue(null,"invalidMetric",total.sources)
          ctx.warn("${l.name}: 尖峰谷平区间总量需要能耗计量数据")
        }
        row:=baseRow(l,"band:$band",total); row["band"]=band
        if (displaysKnown(l)) row.setAll(FinEnergyKnownUsage.fields(count == 0 ? FinEnergyValue(0f,"ok") : (data == null ? l.knownTotal(ticks) : (FinEnergyValue)data["known"])))
        loadBands.add(row)
      }
    }
    extra["aggregation"]="mean energy for each hour of day"
    extra["loadBands"]=loadBands
    extra["loadBandsAggregation"]="intervalTotal"
  }

  private Void working(FinEnergyLine[] lines)
  {
    if(consumedMeters != null) ctx.warningScope(2,-1,0)
    available:=kind == "workingHours" ? (request["workHours"] ?: ctx.calendar?.get("workHours")) != null : ctx.calendar?.get("workDays") != null
    if (!available) ctx.warn("Work calendar is required")
    lines.each |l|
    {
      frozen:=consumedWorking[l.id]
      work:=FinEnergyTick[,];off:=FinEnergyTick[,]
      if(frozen==null) l.ticks.each |tick|
      {
        if(ctx.working(tick.ts,kind == "workingHours",request["workHours"])) work.add(tick)
        else off.add(tick)
      }
      a:=!available ? FinEnergyValue(null,"missingCalendar") : (frozen == null ? l.total(work) : (FinEnergyValue)frozen[0]["value"])
      b:=!available ? FinEnergyValue(null,"missingCalendar") : (frozen == null ? l.total(off) : (FinEnergyValue)frozen[1]["value"])
      if (available && frozen == null && work.isEmpty) a=FinEnergyValue(0f,"ok")
      if (available && frozen == null && off.isEmpty) b=FinEnergyValue(0f,"ok")
      row:=baseRow(l,"working",l.total); row["working"]=a.value; row["nonworking"]=b.value
      row["workingPercentage"]=FinEnergyValue.divide(a,FinEnergyValue.sum([a,b])).scale(100f).value
      row["workingQuality"]=a.quality; row["nonworkingQuality"]=b.quality
      rows.add(row)
      points:=[a.point(from),b.point(from)]
      points[0]["label"]="working"; points[1]["label"]="nonworking"
      if (displaysKnown(l))
      {
        knownWork:=!available ? FinEnergyValue(null,"missingCalendar") : (frozen == null ? (work.isEmpty ? FinEnergyValue(0f,"ok") : l.knownTotal(work)) : (FinEnergyValue)frozen[0]["known"])
        knownOff:=!available ? FinEnergyValue(null,"missingCalendar") : (frozen == null ? (off.isEmpty ? FinEnergyValue(0f,"ok") : l.knownTotal(off)) : (FinEnergyValue)frozen[1]["known"])
        row.setAll(FinEnergyKnownUsage.fields(l.knownTotal))
        row["knownWorking"]=knownWork.value; row["knownNonworking"]=knownOff.value
        row["knownWorkingQuality"]=knownWork.quality; row["knownNonworkingQuality"]=knownOff.quality
        row["comparability"]=!available ? "missingCalendar" : (a.value == null || b.value == null || !a.reliable || !b.reliable ? "incompleteCoverage" : "complete")
        points[0].setAll(FinEnergyKnownUsage.fields(knownWork)); points[1].setAll(FinEnergyKnownUsage.fields(knownOff))
      }
      series.add(seriesMap(l,points))
    }
  }

  private Void comparePeriods(FinEnergyLine[] lines)
  {
    otherFrom:=request["otherFrom"]?.toStr; otherTo:=request["otherTo"]?.toStr
    if (otherFrom == null && otherTo == null)
    {
      comparisons:=[Str:Obj?][,]
      baselineId:=request["baselineId"]?.toStr
      if (baselineId != null && !FinEnergyMath.strings(request["nodeIds"]).contains(baselineId)) throw ArgErr("基准对象必须在已选对比对象中")
      bases:=baselineId == null ? (lines.isEmpty ? FinEnergyLine[,] : [lines.first]) : lines.findAll |l| { l.nodeId == baselineId }
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
          current:=l.total; previous:=base.total; diff:=FinEnergyValue.sum([current,previous.scale(-1f)])
          Str:Obj? currentCoverage:=displaysKnown(l) ? coverage(l) : [:]
          Str:Obj? referenceCoverage:=displaysKnown(l) ? coverage(base) : [:]
          comparable:=current.value != null && previous.value != null && current.reliable && previous.reliable
          if (displaysKnown(l)) comparable=comparable && currentCoverage["complete"] == true && referenceCoverage["complete"] == true
          if (!comparable) diff=FinEnergyValue(null,"incompleteCoverage",diff.sources)
          percentage:=FinEnergyValue.divide(diff,previous).scale(100f)
          row:=Str:Obj?["id":l.id,"name":l.name,"categoryId":l.category,"referenceId":base.nodeId,"referenceName":base.name,"current":current.value,"reference":previous.value,"difference":diff.value,"percentage":percentage.value,"quality":diff.quality,"percentageQuality":percentage.quality,"unit":l.unit,"comparability":comparable ? "complete" : "incompleteCoverage"]
          if (displaysKnown(l)) row.setAll(["knownCurrent":available(l).value,"knownReference":available(base).value,"currentCoverage":currentCoverage["coverage"],"referenceCoverage":referenceCoverage["coverage"]])
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
      diff:=FinEnergyValue.sum([current,previous.scale(-1f)])
      Str:Obj? currentCoverage:=displaysKnown(l) ? coverage(l) : [:]
      Str:Obj? referenceCoverage:=displaysKnown(l) ? coverage(base) : [:]
      comparable:=current.value != null && previous.value != null && current.reliable && previous.reliable
      if (displaysKnown(l)) comparable=comparable && currentCoverage["complete"] == true && referenceCoverage["complete"] == true
      if (!comparable) diff=FinEnergyValue(null,"incompleteCoverage",diff.sources)
      percentage:=FinEnergyValue.divide(diff,previous)
      row:=Str:Obj?["id":l.id,"name":l.name,"current":current.value,"reference":previous.value,"difference":diff.value,"percentage":percentage.scale(100f).value,"percentageQuality":percentage.quality,"quality":diff.quality,"unit":l.unit,"comparability":comparable ? "complete" : "incompleteCoverage"]
      if (displaysKnown(l)) row.setAll(["knownCurrent":available(l).value,"knownReference":available(base).value,"currentCoverage":currentCoverage["coverage"],"referenceCoverage":referenceCoverage["coverage"]])
      comparisons.add(row)
      base.id+="|reference"; base.name+=" (reference)"; append(base,period)
    }
    extra["comparisons"]=comparisons
  }

  private Void dashboard(FinEnergyLine[] lines)
  {
    totals:=FinEnergyMath.maps(summary["selectionTotals"])
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
      strict:=FinEnergyValue.sum(parts.map |p->FinEnergyValue| {FinEnergyValue(FinEnergyMath.num(p["value"]),p["quality"].toStr,FinEnergyMath.strings(p["sourceIds"]))})
      row:=Str:Obj?["key":"$metric|$unit","name":name,"unit":unit,"value":strict.value,"quality":strict.quality,"sourceIds":strict.sources]
      if (knownCtx != null)
      {
        known:=FinEnergyKnownUsage.combine(parts.map |p->FinEnergyValue| {FinEnergyValue(FinEnergyMath.num(p["knownValue"]),p["knownQuality"].toStr,FinEnergyMath.strings(p["sourceIds"]))})
        row.setAll(FinEnergyKnownUsage.fields(known))
      }
      grandTotals.add(row)
    }
    extra["grandTotals"]=grandTotals
    if (request["otherFrom"] != null) comparePeriods(lines)
  }

  Str:Obj? trend(Str[] selected)
  {
    ids:=selected.dup.addAll(FinEnergyMath.strings(request["referenceIds"])).unique
    ids.each |id|
    {
      r:=ctx.byId[id]
      point:=r?.get("pointId")?.toStr ?: id
      h:=ctx.byPoint[point]
      name:=ctx.displayName(id)
      rawUnit:=r?.get("unit")?.toStr ?: (h?.unit ?: "")
      l:=FinEnergyLine(id,id,name,r?.get("categoryId")?.toStr ?: "",rawUnit)
      points:=[Str:Obj?][,]
      if (h == null || h.samples.isEmpty) ctx.warn("$name: missing history")
      else h.samples.each |s|
      {
        if (s.ts < from || s.ts >= to) return
        q:=s.valueType == "na" ? "na" : (s.value == null ? "missing" : h.quality)
        if (h.cleaning != null && s.quality != "ok") q=s.quality
        available:=["ok","derived","estimated","cleaned","corrected","filtered","substituted"].contains(q)
        v:=FinEnergyValue(available ? s.value : null,q,h.sources); p:=v.point(s.ts.toTimeZone(ctx.tz)); points.add(p)
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
      end:=FinEnergyMath.nextBucket(FinEnergyMath.bucket(cursor,period),period); if (end > to) end=to
      a:=regressionBucket(x,cursor,end); b:=regressionBucket(y,cursor,end)
      if (a.value != null && b.value != null)
      {
        xs.add(a.value); ys.add(b.value)
        point:=b.point(cursor); point["x"]=a.value; point["quality"]=FinEnergyValue.worse(a.quality,b.quality); point["sourceIds"]=a.sources.dup.addAll(b.sources).unique
        points.add(point)
        rows.add(["key":cursor.toIso,"ts":cursor.toIso,"x":a.value,"y":b.value,"value":b.value,"quality":point["quality"],"sourceIds":point["sourceIds"]])
      }
      else ctx.warn("Regression omitted incomplete pair: ${cursor.toIso}")
      cursor=end
    }
    extra=FinEnergyMath.regression(xs,ys)
    xName:=ctx.displayName(x); yName:=ctx.displayName(y)
    extra["xName"]=xName; extra["yName"]=yName
    fitLine:=[Str:Obj?][,]
    slope:=FinEnergyMath.num(extra["slope"]); intercept:=FinEnergyMath.num(extra["intercept"])
    if (slope != null && intercept != null && !xs.isEmpty)
    {
      low:=(Float)xs.min; high:=(Float)xs.max
      lowY:=FinEnergyMath.num(slope*low+intercept); highY:=FinEnergyMath.num(slope*high+intercept)
      if (high > low && lowY != null && highY != null) fitLine.add(["x":low,"y":lowY]).add(["x":high,"y":highY])
    }
    extra["fitLine"]=fitLine
    if (extra["slope"] == null) ctx.warn("Regression requires at least two valid pairs with varying x")
    series.add(["id":"regression","name":"$yName vs $xName","unit":"","points":points])
    return result
  }

  private FinEnergyValue regressionValue(Str id, DateTime start, DateTime end)
  {
    if (ctx.byId.containsKey(id))
    {
      value:=ctx.nodeTotal(id,start,end)
      r:=ctx.byId[id]
      if (ctx.dimension?.dimension == "organization" && ["meter","totalMeter"].contains(r["kind"]?.toStr ?: ""))
      {
        quality:=ctx.dimension.quality([r]); if (quality != null) return FinEnergyValue(null,quality,value.sources)
      }
      return value
    }
    return ctx.byPoint[id]?.read(start,end,true) ?: FinEnergyValue()
  }

  private FinEnergyValue regressionBucket(Str id, DateTime start, DateTime end)
  {
    values:=FinEnergyValue[,]; cursor:=start
    while (cursor < end)
    {
      next:=FinEnergyMath.floorHour(cursor)+1hr; if (next > end) next=end
      values.add(regressionValue(id,cursor,next)); cursor=next
    }
    total:=FinEnergyValue.sum(values)
    isGauge:=!ctx.byId.containsKey(id) || ctx.byId[id]["kind"] == "sensor"
    return isGauge && !values.isEmpty ? total.scale(1f/values.size.toFloat) : total
  }

  private Str:Obj? seriesMap(FinEnergyLine l, [Str:Obj?][] points)
  { ["id":l.id,"nodeId":l.nodeId,"name":l.name,"categoryId":l.category,"unit":l.unit,"points":points] }

  private Str:Obj? baseRow(FinEnergyLine l, Str key, FinEnergyValue v)
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





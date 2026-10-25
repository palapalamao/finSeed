** A read-only metering graph. Values are actual interval totals, never allocations.
internal class EnerCubixEnergyFlow
{
  new make(EnerCubixContext ctx, Str:Obj? request, DateTime from, DateTime to)
  {
    this.ctx=ctx; this.request=request; this.from=from; this.to=to
    this.dim=ctx.dimension ?: throw ArgErr("能流图仅支持计量视角")
    this.category=request["categoryId"]?.toStr ?: ""
    this.unit=ctx.unit("",category,"energy")
    cutoff:=EnerCubixKnownUsage.cutoff(request)
    knownCtx=EnerCubixContext.known(ctx,to < cutoff ? to : cutoff)
  }
  private EnerCubixContext ctx
  private EnerCubixContext knownCtx
  private Str:EnerCubixValue knownValues := [:]
  private EnerCubixDimension dim
  private Str:Obj? request
  private DateTime from
  private DateTime to
  private Str category
  private Str unit
  private Str:EnerCubixValue values := [:]
  private [Str:Obj?][] nodes := [,]
  private [Str:Obj?][] links := [,]
  private [Str:Obj?][] eligible := [,]
  private Str[] seen := [,]

  ** Shared selection with native history planning; no histories are read here.
  static Str:Obj? scope(Str:Obj? req, EnerCubixDimension dim)
  {
    if (req["dimension"] != "metering" || req["metric"] != "energy" || req["perArea"] == true)
      throw ArgErr("能流图仅支持计量视角的区间能耗，不支持费用或面积归一化")
    category:=req["categoryId"]?.toStr ?: ""
    cat:=dim.records.find |r| { r["id"] == category && r["kind"] == "category" }
    if (cat == null || (cat["unit"]?.toStr ?: "").isEmpty) throw ArgErr("能流图请选择有计量单位的能源类型")
    ids:=EnerCubixMath.strings(req["nodeIds"]).unique
    meters:=dim.records.findAll |r| { included(r) && r["categoryId"] == category && !excludedAncestor(r,dim) }
    masters:=meters.findAll |r| { r["kind"] == "totalMeter" && r["meterParentId"] == null }.sort |a,b| { a["id"].toStr <=> b["id"].toStr }
    roots:=masters
    if (!ids.isEmpty)
    {
      selected:=meters.findAll |r| {ids.contains(r["id"])}
      if (selected.size != ids.size) throw ArgErr("能流图对象必须是所选能源的计量表")
      roots=dim.frontier(selected)
    }
    reachable:=Str[,]; queue:=roots.map |r->Str| { r["id"].toStr }
    for (i:=0;i<queue.size;i++)
    {
      id:=queue[i]; if (reachable.contains(id)) continue
      reachable.add(id)
      queue.addAll(meters.findAll |r| { r["meterParentId"] == id }.map |r->Str| { r["id"].toStr })
    }
    unassigned:=ids.isEmpty ? meters.findAll |r| { !reachable.contains(r["id"].toStr) } : [Str:Obj?][,]
    return ["meters":meters,"roots":roots,"selected":meters.findAll |r| { reachable.contains(r["id"].toStr) },"unassigned":unassigned]
  }

  Str:Obj? report()
  {
    plan:=scope(request,dim)
    eligible=EnerCubixMath.maps(plan["meters"])
    roots:=EnerCubixMath.maps(plan["roots"])
    selected:=EnerCubixMath.maps(plan["selected"])
    unassigned:=EnerCubixMath.maps(plan["unassigned"])
    selected.dup.addAll(unassigned).each |r| { usage(r["id"].toStr) }
    summaryId:="__energyFlow__:$category"
    overview:=EnerCubixMath.strings(request["nodeIds"]).isEmpty || roots.size > 1
    focusId:=overview ? summaryId : roots.first["id"].toStr
    EnerCubixValue? aggregate:=null
    if (overview)
    {
      aggregate=EnerCubixValue.sum(roots.map |r->EnerCubixValue| { aggregatable(usage(r["id"].toStr)) })
      quality:=dim.quality(eligible)
      if (!unassigned.isEmpty || selected.any |r| { !validChain(r) }) quality="topologyIncomplete"
      // Two nominally independent roots must not read the same physical source.
      sources:=Str[,]
      roots.each |r|
      {
        own:=usage(r["id"].toStr).sources
        if (own.any |id| { sources.contains(id) }) quality="topologyIncomplete"
        sources.addAll(own)
      }
      if (quality != null) aggregate=EnerCubixValue(null,quality,aggregate.sources)
      summary:=base(summaryId,ctx.byId[category]?.get("name")?.toStr ?: category,"summary",null,aggregate)
      summary["hasChildren"]=!roots.isEmpty
      summary["submeter"]=aggregate.value; summary["difference"]=aggregate.value == null ? null : 0f
      summary["balanceQuality"]=aggregate.quality
      nodes.add(summary)
    }
    roots.each |root|
    {
      id:=root["id"].toStr
      build(id,overview ? summaryId : null,overview ? aggregate : null)
      if (overview && good(aggregate) && good(usage(id)) && usage(id).value > 0f)
        addLink(summaryId,id,usage(id),aggregate)
    }
    orphans:=unassigned.map |r->[Str:Obj?]|
    {
      row:=base(r["id"].toStr,ctx.displayName(r["id"].toStr),"meter",null,usage(r["id"].toStr))
      row["balanceQuality"]="topologyIncomplete"; return row
    }
    if (!orphans.isEmpty) ctx.warn("存在待确认计量关系的表计，未作为能源入口计入合计")
    rows:=nodes.dup
    series:=nodes.map |n->[Str:Obj?]|
    {
      point:=Str:Obj?["ts":from.toIso,"value":n["value"],"quality":n["quality"],"sourceIds":n["sourceIds"]]
      if (n.containsKey("knownValue")) point.setAll(["knownValue":n["knownValue"],"knownValueType":n["knownValueType"],"knownQuality":n["knownQuality"]])
      return ["id":n["id"],"nodeId":n["id"],"name":n["name"],"categoryId":category,"unit":unit,
        "points":[point]]
    }
    flow:=["categoryId":category,"unit":unit,"focusId":focusId,
      "rootIds":roots.map |r->Str| { r["id"].toStr },"nodes":nodes,"links":links,"unassigned":orphans]
    complete:=EnerCubixValue.sum(roots.map |r->EnerCubixValue| {usage(r["id"].toStr)})
    observed:=EnerCubixKnownUsage.combine(roots.map |r->EnerCubixValue| {knownUsage(r["id"].toStr)})
    scopeQuality:=dim.quality(roots)
    if (scopeQuality != null) observed=EnerCubixValue(null,scopeQuality,observed.sources)
    total:=Str:Obj?["id":category+"|"+unit,"categoryId":category,"unit":unit,"value":complete.value,"quality":complete.quality,"meterIds":roots.map |r->Str| {r["id"].toStr},"sourceIds":observed.sources,"scopeQuality":scopeQuality]
    total.setAll(EnerCubixKnownUsage.fields(observed))
    return ["kind":"energyFlow","from":from.toIso,"to":to.toIso,"period":"day",
      "series":series,"rows":rows,"warnings":ctx.warnings,"summary":["value":nodes.first?.get("value"),"unit":unit,"selectionTotals":[total]],
      "extra":["energyFlow":flow,"selectionTotals":[total],"usageBasis":"knownUsage","knownUsage":["basis":"closedSourceIntervals","sourceUsage":EnerCubixKnownUsage.evidence(knownCtx.knownReads.vals)]]]
  }

  private Void build(Str id, Str? parent, EnerCubixValue? parentValue)
  {
    if (seen.contains(id)) return
    seen.add(id)
    value:=usage(id)
    row:=base(id,ctx.displayName(id),"meter",parent,value)
    row["percentage"]=percentage(value,parentValue)
    nodes.add(row)
    children:=eligible.findAll |r| { r["meterParentId"] == id }.sort |a,b| { a["id"].toStr <=> b["id"].toStr }
    row["hasChildren"]=!children.isEmpty
    if (children.isEmpty) return
    subtotal:=EnerCubixValue.sum(children.map |r->EnerCubixValue| { aggregatable(usage(r["id"].toStr)) })
    src:=value.sources.dup.addAll(subtotal.sources).unique
    Float? difference:=value.value == null || subtotal.value == null ? null : value.value-subtotal.value
    quality:=EnerCubixValue.worse(value.quality,subtotal.quality)
    if (!validChain(ctx.byId[id])) quality="topologyIncomplete"
    else
    {
      topo:=dim.leakQuality(id)
      if (topo != null) quality=topo
    }
    if (!good(value) || !good(subtotal) || !["ok","good","estimated","derived","cleaned","corrected"].contains(quality)) difference=null
    if (difference != null && difference < 0f && difference.abs <= (value.value.abs+1f)*0.000000001f) difference=0f
    if (difference != null && difference < 0f)
    {
      quality="negativeBalance"
      ctx.warn(ctx.displayName(id)+": 分表合计大于总表，差额为负，请核对计量关系与数据")
    }
    row["submeter"]=subtotal.value; row["difference"]=difference; row["balanceQuality"]=quality
    mode:=EnerCubixBalance.mode(ctx,id)
    row["balanceMode"]=mode; row["lossEligible"]=["ok","good","derived","cleaned","corrected"].contains(quality) && EnerCubixBalance.eligible(mode,value,subtotal)
    children.each |r|
    {
      child:=r["id"].toStr
      build(child,id,value)
      if (["ok","estimated","derived","cleaned","corrected"].contains(quality) && good(value) && good(usage(child)) && usage(child).value > 0f)
        addLink(id,child,usage(child),value)
    }
    if (["ok","estimated","derived","cleaned","corrected"].contains(quality) && difference != null && difference > 0f)
    {
      diffId:="__energyFlowDifference__:$id"
      v:=EnerCubixValue(difference,quality,src)
      gap:=base(diffId,"","difference",id,v); gap["percentage"]=percentage(v,value)
      gap["balanceMode"]=mode; gap["lossEligible"]=row["lossEligible"]
      nodes.add(gap); addLink(id,diffId,v,value)
    }
  }

  private Str:Obj? base(Str id,Str name,Str type,Str? parent,EnerCubixValue v)
  {
    row:=["id":id,"nodeId":id,"name":name,"nodeType":type,"categoryId":category,"unit":unit,
      "value":v.value,"quality":v.quality,"sourceIds":v.sources,"submeter":null,"difference":null,
      "balanceQuality":v.quality,"hasChildren":false,"percentage":null]
    if (parent != null) row["parentId"]=parent
    if (type == "meter") row.setAll(EnerCubixKnownUsage.fields(knownUsage(id)))
    return row
  }

  private EnerCubixValue knownUsage(Str id)
  {
    if (knownValues.containsKey(id)) return knownValues[id]
    pieces:=EnerCubixValue[,]; cursor:=from
    while (cursor < to)
    {
      end:=EnerCubixMath.floorHour(cursor)+1hr; if (end > to) end=to
      pieces.add(knownCtx.node(id,category,cursor,end)); cursor=end
    }
    value:=EnerCubixKnownUsage.combine(pieces)
    knownValues[id]=value; return value
  }

  private Void addLink(Str source,Str target,EnerCubixValue v,EnerCubixValue? parent)
  {
    links.add(["source":source,"target":target,"value":v.value,"quality":v.quality,
      "sourceIds":v.sources,"percentage":percentage(v,parent)])
  }

  private EnerCubixValue usage(Str id)
  {
    if (values.containsKey(id)) return values[id]
    pieces:=EnerCubixValue[,]; cursor:=from
    while (cursor < to)
    {
      end:=EnerCubixMath.floorHour(cursor)+1hr; if (end > to) end=to
      pieces.add(ctx.node(id,category,cursor,end)); cursor=end
    }
    result:=EnerCubixValue.sum(pieces)
    if (result.value != null && result.value < 0f) result=EnerCubixValue(result.value,"negative",result.sources)
    values[id]=result; return result
  }

  private Bool validChain(Str:Obj? r)
  {
    chain:=Str[,]; current:=r
    while (true)
    {
      id:=current["id"].toStr; if (chain.contains(id)) return false
      chain.add(id); parent:=current["meterParentId"]?.toStr
      if (parent == null) return true
      next:=ctx.byId[parent]
      if (next == null || next["categoryId"] != category || !included(next)) return false
      current=next
    }
    return false
  }
  private static Bool included(Str:Obj? r)
  { ["meter","totalMeter"].contains(r["kind"]?.toStr ?: "") && ((Bool?)r["includeInTotals"] ?: (r["expressionId"] == null)) }
  private static Bool excludedAncestor(Str:Obj? r,EnerCubixDimension dim)
  {
    seen:=Str[,]; parent:=r["meterParentId"]?.toStr
    while (parent != null && !seen.contains(parent))
    {
      seen.add(parent); next:=dim.records.find |n| { n["id"] == parent }
      if (next == null) return false
      if (["meter","totalMeter"].contains(next["kind"]?.toStr ?: "") && !included(next)) return true
      parent=next["meterParentId"]?.toStr
    }
    return false
  }
  private static Bool good(EnerCubixValue? v)
  { v?.value != null && v.value >= 0f && ["ok","estimated","derived","cleaned","corrected"].contains(v.quality) }
  private static EnerCubixValue aggregatable(EnerCubixValue v)
  { good(v) ? v : EnerCubixValue(null,v.quality,v.sources) }
  private static Float? percentage(EnerCubixValue v,EnerCubixValue? parent)
  { v.reliable && parent?.reliable == true && v.value != null && v.value > 0f && parent?.value != null && parent.value > 0f ? v.value/parent.value*100f : null }
}

** Current relationships describe independent object graphs. Stored readings are
** never replaced by child sums; known subtotals remain drawable.
internal class EnerCubixEnergyFlow
{
  new make(EnerCubixContext ctx, Str:Obj? request, DateTime from, DateTime to, [Str:Obj?][] histories := [Str:Obj?][,])
  {
    this.ctx=ctx; this.request=request; this.from=from; this.to=to; this.histories=histories
    dim=ctx.dimension ?: throw ArgErr("Invalid report dimension")
    category=request["categoryId"]?.toStr ?: ""
    unit=ctx.unit("",category,"energy")
    cutoff:=EnerCubixKnownUsage.cutoff(request)
    knownCtx=EnerCubixContext.known(ctx,to < cutoff ? to : cutoff)
  }
  private EnerCubixContext ctx
  private EnerCubixContext knownCtx
  private EnerCubixDimension dim
  private Str:Obj? request
  private DateTime from
  private DateTime to
  private Str category
  private Str unit
  private [Str:Obj?][] histories
  private Str:EnerCubixValue values:=[:]
  private Str:EnerCubixValue knownValues:=[:]
  private [Str:Obj?][] nodes:=[,]
  private [Str:Obj?][] links:=[,]
  private Str graphId:=""
  private Str[] allowed:=Str[,]

  internal static [Str:Obj?][] normalizeRecords([Str:Obj?][] records)
  {
    return records.map |r->[Str:Obj?]|
    {
      if (r["nativeEquip"] == true || !meter(r) || r["canonicalId"] != null || r["pointId"] == null) return r
      matches:=records.findAll |m| {m["nativeEquip"] == true && meter(m) && m["pointId"] == r["pointId"]}
      return matches.size == 1 ? r.dup.set("canonicalId",matches.first["id"]) : r
    }
  }

  ** Hidden records only mark incomplete boundaries; no hidden identity or name
  ** enters the public graph. Missing children cannot become invented losses.
  internal static [Str:Obj?][] visible([Str:Obj?][] visible,[Str:Obj?][] all)
  {
    index:=Str:[Str:Obj?][:];all.each |r| {index[r["id"].toStr]=r}
    [Str:Obj?][] out:=visible.map |r->[Str:Obj?]| {r.dup}
    all.findAll |r| {r["_comparisonReadable"] == false && meter(r)}.each |hidden|
    {
      ["meterParentId","spaceId","organizationId"].each |key|
      {
        seen:=Str[,];cursor:=hidden[key] as Str
        while (cursor != null && !seen.contains(cursor))
        {
          seen.add(cursor);target:=out.find |r| {r["id"] == cursor}
          if (target != null) target["_flowBoundaryUnavailable"]=true
          next:=index[cursor]
          cursor=next?.get(key == "meterParentId" ? key : "parentId") as Str
        }
      }
    }
    return out
  }

  ** Explicit objects ignore automatic inclusion. Group membership preserves it.
  static Str:Obj? scope(Str:Obj? req, EnerCubixDimension dim)
  {
    if (!["metering","space","organization"].contains(req["dimension"]) || req["metric"] != "energy" || req["perArea"] == true)
      throw ArgErr("能流图仅支持区间能耗，不支持费用或面积归一化")
    category:=req["categoryId"]?.toStr ?: ""
    cat:=dim.records.find |r| {r["id"] == category && r["kind"] == "category"}
    if (cat == null || (cat["unit"]?.toStr ?: "").isEmpty) throw ArgErr("能流图请选择有计量单位的能源类型")
    meters:=dim.records.findAll |r| {meter(r) && r["categoryId"] == category}
    automatic:=meters.findAll |r| {included(r) && !excludedAncestor(r,dim)}
    ids:=EnerCubixMath.strings(req["nodeIds"]).map |id->Str| {dim.canonical(id)}.unique
    roots:=[Str:Obj?][,]
    if (ids.isEmpty)
      roots=dim.dimension == "metering" ? automatic.findAll |r| {r["kind"] == "totalMeter" && r["meterParentId"] == null} : dim.records.findAll |r| {dim.scope(r["id"].toStr) && r["parentId"] == null}
    else ids.each |id|
    {
      r:=dim.byId[id]
      if (r == null || (!dim.scope(id) && (!meter(r) || r["categoryId"] != category))) throw ArgErr("能流图对象必须是所选能源的表计或当前视角范围")
      roots.add(r)
    }
    reachable:=Str[,]
    roots.each |root|
    {
      id:=root["id"].toStr
      if (dim.scope(id)) reachable.addAll(dim.members(id).findAll |r| {r["categoryId"] == category}.map |r->Str| {r["id"].toStr})
      else closure(id,dim,category,reachable)
    }
    reachable=reachable.unique
    unassigned:=ids.isEmpty && dim.dimension == "metering" ? automatic.findAll |r| {!reachable.contains(r["id"].toStr)} : [Str:Obj?][,]
    return ["meters":automatic,"roots":roots.sort |a,b| {a["id"].toStr <=> b["id"].toStr},"selected":meters.findAll |r| {reachable.contains(r["id"].toStr)},"unassigned":unassigned]
  }

  private static Void closure(Str id,EnerCubixDimension dim,Str category,Str[] found)
  {
    if (found.contains(id)) return
    r:=dim.byId[id]
    if (r == null || !meter(r) || r["categoryId"] != category || r["_comparisonReadable"] == false) return
    found.add(id)
    refs:=Str[,]
    if (r["expressionId"] != null)
    {
      expr:=dim.byId[r["expressionId"].toStr]
      if (expr?.get("_comparisonReadable") == false) return
      vars:=expr?.get("variables") as Map
      if (vars != null) vars.vals.each |ref| {if (ref != null) refs.add(dim.canonical(ref.toStr))}
    }
    else refs=dim.directChildren(id).map |m->Str| {m["id"].toStr}
    refs.unique.each |ref| {closure(ref,dim,category,found)}
  }

  Str:Obj? report()
  {
    plan:=scope(request,dim); roots:=EnerCubixMath.maps(plan["roots"])
    ownIds:=EnerCubixMath.maps(plan["selected"]).dup.addAll(EnerCubixMath.maps(plan["unassigned"])).map |r->Str| {r["id"].toStr}.unique
    overview:=EnerCubixFlowOverview.build(request,dim.records,histories,ownIds)
    graphs:=[Str:Obj?][,]
    roots.each |root|
    {
      id:=root["id"].toStr; graphId=dim.dimension+"|"+id; nodes=[Str:Obj?][,]; links=[Str:Obj?][,]
      grouped:=dim.scope(id)
      allowed=grouped ? dim.members(id).findAll |r| {r["categoryId"] == category}.map |r->Str| {r["id"].toStr} : ownIds
      build(id,null,null,Str[,],grouped)
      boundary:=grouped ? boundaries(id) : contribution(id,Str[,])
      basis:=grouped ? dim.dimension : (derived(root) ? "calculation" : "metering")
      graphs.add(["graphId":graphId,"objectId":id,"basis":basis,"categoryId":category,"unit":unit,"focusId":id,"rootIds":[id],"nodes":nodes,"links":links,"unassigned":[Str:Obj?][,],"contributionMemberIds":EnerCubixMath.strings(boundary["members"]),"sharedMemberIds":Str[,],"additive":boundary["additive"] == true,"boundaryQuality":boundary["quality"] ?: "ok"])
    }
    accounting:=account(graphs,EnerCubixMath.maps(plan["unassigned"]))
    strictTotal:=EnerCubixValue.sum(EnerCubixMath.strings(accounting["memberIds"]).map |id->EnerCubixValue| {usage(id)})
    knownTotal:=EnerCubixValue(EnerCubixMath.num(accounting["unionValue"]),accounting["unionQuality"].toStr)
    if (accounting["basis"] == "unavailable") strictTotal=EnerCubixValue(null,accounting["unionQuality"].toStr)
    total:=Str:Obj?["id":category+"|"+unit,"categoryId":category,"unit":unit,"value":strictTotal.value,"quality":strictTotal.quality,"meterIds":accounting["memberIds"],"sourceIds":strictTotal.sources]
    total.setAll(EnerCubixKnownUsage.fields(knownTotal))
    overview["selectionTotals"]=[total]
    rows:=[Str:Obj?][,];series:=[Str:Obj?][,]
    graphs.each |g|
    {
      EnerCubixMath.maps(g["nodes"]).each |n|
      {
        row:=n.dup
        own:=EnerCubixMath.maps(overview["rows"]).find |r| {r["id"] == n["nodeId"]}
        if (own != null) row.setAll(own).set("id",n["id"]).set("graphId",g["graphId"])
        rows.add(row)
        point:=Str:Obj?["ts":from.toIso,"value":n["value"],"quality":n["quality"],"sourceIds":n["sourceIds"],"knownValue":n["knownValue"],"knownValueType":n["knownValueType"],"knownQuality":n["knownQuality"]]
        series.add(["id":n["id"],"nodeId":n["nodeId"],"graphId":g["graphId"],"name":n["name"],"categoryId":category,"unit":unit,"points":[point]])
      }
    }
    flow:=compatible(graphs,roots,plan,total)
    return ["kind":"energyFlow","from":from.toIso,"to":to.toIso,"period":request["period"] ?: "day","series":series,"rows":rows,"warnings":ctx.warnings,
      "summary":["value":strictTotal.value,"unit":unit,"selectionTotals":[total]],
      "extra":["energyFlow":flow,"energyFlowGraphs":graphs,"energyFlowAccounting":accounting,"energyFlowOverview":overview,"selectionTotals":[total],"usageBasis":"knownUsage","knownUsage":overview["knownUsage"]]]
  }

  private Void build(Str id,Str? parent,EnerCubixValue? parentValue,Str[] path,Bool grouping)
  {
    r:=ctx.byId[id]
    if (r == null || path.contains(id) || r["_comparisonReadable"] == false) return
    occurrence:=nodes.any |n| {n["id"] == id} ? id+"|"+nodes.size : id
    value:=usage(id);known:=knownUsage(id)
    row:=base(occurrence,id,ctx.displayName(id),dim.scope(id) ? dim.dimension : "meter",parent,value,known)
    row["percentage"]=percentage(value,parentValue);nodes.add(row)
    children:=Str[,];relation:=grouping ? "grouping" : (r["expressionId"] != null ? "calculation" : "metering")
    if (grouping && dim.scope(id))
    {
      children.addAll(dim.records.findAll |n| {dim.scope(n["id"].toStr) && n["parentId"] == id}.map |n->Str| {n["id"].toStr})
      children.addAll(dim.records.findAll |n| {allowed.contains(n["id"].toStr) && membership(n) == id}.map |n->Str| {n["id"].toStr})
    }
    else if (!grouping)
    {
      if (r["expressionId"] != null)
      {
        expr:=ctx.byId[r["expressionId"].toStr];vars:=expr?.get("variables") as Map
        if (expr?.get("_comparisonReadable") != false && vars != null) children.addAll(vars.vals.map |ref->Str| {ref?.toStr ?: ""})
      }
      else children.addAll(dim.directChildren(id).map |n->Str| {n["id"].toStr})
    }
    children=children.unique.findAll |child| {c:=ctx.byId[child];return c != null && !path.contains(child) && child != id && c["_comparisonReadable"] != false && (dim.scope(child) || (meter(c) && c["categoryId"] == category && allowed.contains(child)))}.sort
    row["hasChildren"]=!children.isEmpty
    suppressed:=Str[,];seenPoints:=Str[,]
    children.each |child|
    {
      c:=ctx.byId[child]
      if (!meter(c) || derived(c)) return
      physical:=physicalId(c)
      if (seenPoints.contains(physical)) suppressed.add(child)
      else seenPoints.add(physical)
      if (grouping && children.any |other| {other != child && (dim.scope(other) ? EnerCubixMath.strings(boundaries(other)["members"]) : [other]).any |member| {ancestor(child,member)}}) suppressed.add(child)
    }
    displayed:=children.findAll |child| {!suppressed.contains(child)}
    inputSafe:=relation != "calculation" || contribution(id,Str[,])["additive"] == true
    subtotal:=inputSafe ? EnerCubixValue.sum(displayed.map |child->EnerCubixValue| {usage(child)}) : EnerCubixValue(null,"comparisonNonAdditive")
    knownSubtotal:=inputSafe ? EnerCubixKnownUsage.combine(displayed.map |child->EnerCubixValue| {knownUsage(child)}) : EnerCubixValue(null,"comparisonNonAdditive")
    mode:=grouping ? "consistency" : EnerCubixBalance.mode(ctx,id)
    quality:=EnerCubixValue.worse(value.quality,subtotal.quality)
    Float? difference:=!grouping && relation == "metering" && good(value) && good(subtotal) ? value.value-subtotal.value : null
    if (r["_flowBoundaryUnavailable"] == true) {quality="comparisonUnavailable";difference=null}
    else if (!grouping && relation == "metering")
    {
      topology:=validChain(id) ? dim.leakQuality(id) : "topologyIncomplete"
      if (topology != null) {quality=topology;difference=null}
    }
    if (grouping && !suppressed.isEmpty) quality="overlappingScopes"
    if (difference != null && difference < 0f && difference.abs <= (value.value.abs+1f)*0.000000001f) difference=0f
    if (difference != null && difference < 0f) {quality="negativeBalance";ctx.warn(ctx.displayName(id)+": 分表合计大于总表，差额为负，请核对计量关系与数据")}
    row["submeter"]=subtotal.value;row["knownSubmeter"]=knownSubtotal.value;row["knownSubmeterQuality"]=knownSubtotal.quality;row["difference"]=difference;row["balanceQuality"]=quality
    row["balanceMode"]=mode;row["lossEligible"]=!grouping && ["ok","estimated","derived","cleaned","corrected"].contains(quality) && EnerCubixBalance.eligible(mode,value,subtotal)
    children.each |child|
    {
      before:=nodes.size;build(child,occurrence,value,path.dup.add(id),grouping)
      if (nodes.size == before) return
      target:=nodes[before]["id"].toStr;amount:=knownUsage(child)
      if (!suppressed.contains(child) && amount.value != null && amount.value > 0f) addLink(occurrence,target,amount,known,relation)
    }
    if (difference != null && difference > 0f && good(value) && good(subtotal))
    {
      diffId:="__energyFlowDifference__:$occurrence";v:=EnerCubixValue(difference,quality,value.sources.dup.addAll(subtotal.sources).unique)
      gap:=base(diffId,diffId,"","difference",occurrence,v,v);gap["percentage"]=percentage(v,value);gap["balanceMode"]=mode;gap["lossEligible"]=row["lossEligible"]
      nodes.add(gap);addLink(occurrence,diffId,v,value,"metering")
    }
  }

  private Str:Obj? boundaries(Str id)
  {
    members:=dim.frontier(dim.members(id).findAll |r| {r["categoryId"] == category}).map |r->Str| {derived(r) ? r["id"].toStr : physicalId(r)}.unique.sort
    return ["members":members,"additive":members.all |m| {!derived(ctx.byId[m])},"quality":ctx.byId[id]?.get("_flowBoundaryUnavailable") == true ? "comparisonUnavailable" : (dim.quality(dim.members(id)) ?: "ok")]
  }

  ** This describes contributions; it never evaluates or changes the formula.
  private Str:Obj? contribution(Str id,Str[] path)
  {
    r:=ctx.byId[id]
    if (r == null || !meter(r) || path.contains(id) || r["_flowBoundaryUnavailable"] == true || r["_comparisonReadable"] == false || r["_comparisonPointReadable"] == false || r["categoryId"] != category || EnerCubixMath.unitFactor(r["unit"] as Str ?: unit,unit) == null)
      return ["members":Str[,],"additive":false,"quality":"comparisonUnresolved"]
    if (!derived(r)) return ["members":[physicalId(r)],"additive":true,"quality":"ok"]
    expr:=ctx.byId[r["expressionId"]?.toStr ?: ""]
    refs:=r["expressionId"] != null ? EnerCubixComparisonScope.additive(expr) : dim.directChildren(id).map |c->Str| {c["id"].toStr}
    if (refs == null || refs.isEmpty) return ["members":Str[,],"additive":false,"quality":"comparisonNonAdditive"]
    members:=Str[,];complete:=true
    refs.each |ref|
    {
      c:=contribution(ref,path.dup.add(id));child:=EnerCubixMath.strings(c["members"])
      if (c["additive"] != true || child.any |m| {members.contains(m)}) complete=false
      members.addAll(child)
    }
    return ["members":members.unique.sort,"additive":complete,"quality":complete ? "ok" : "comparisonUnresolved"]
  }

  private Str:Obj? account([Str:Obj?][] graphs,[Str:Obj?][] unassigned)
  {
    owners:=Str:Str[][:]
    graphs.each |g| {EnerCubixMath.strings(g["contributionMemberIds"]).each |id| {if (!owners.containsKey(id)) owners[id]=Str[,];owners[id].add(g["objectId"].toStr)}}
    shared:=owners.keys.findAll |id| {owners[id].size > 1}.sort
    graphs.each |g| {g["sharedMemberIds"]=EnerCubixMath.strings(g["contributionMemberIds"]).findAll |id| {shared.contains(id)}}
    allVirtual:=!graphs.isEmpty && graphs.all |g| {g["basis"] == "calculation"}
    mixed:=graphs.any |g| {g["basis"] == "calculation"} && !allVirtual
    members:=owners.keys.sort
    frontier:=dim.frontier(members.map |id->[Str:Obj?]| {ctx.byId[id]}).map |r->Str| {r["id"].toStr}.sort
    contains:=frontier.size != members.size
    safe:=!graphs.isEmpty && !mixed && graphs.all |g| {g["additive"] == true && g["boundaryQuality"] == "ok"} && unassigned.isEmpty
    if (allVirtual && contains) safe=false
    if (!allVirtual) members=frontier
    topo:=dim.quality(members.map |id->[Str:Obj?]| {ctx.byId[id]})
    if (!allVirtual && topo != null) safe=false
    known:=EnerCubixKnownUsage.combine(members.map |id->EnerCubixValue| {knownUsage(id)})
    return ["canAdd":safe && shared.isEmpty && !contains,"memberIds":members,"sharedMemberIds":shared,"sharedMembers":shared.map |id->[Str:Obj?]| {["meterId":id,"objectIds":owners[id]]},"unionValue":safe ? known.value : null,"unionQuality":safe ? known.quality : (!unassigned.isEmpty ? "topologyIncomplete" : (topo ?: "overlappingScopes")),"basis":safe ? (allVirtual ? "classificationUnion" : "physicalBoundary") : "unavailable"]
  }

  private Str:Obj? compatible([Str:Obj?][] graphs,[Str:Obj?][] roots,Str:Obj? plan,Str:Obj? total)
  {
    if (graphs.size == 1) return graphs.first
    summaryId:="__energyFlow__:$category"
    v:=EnerCubixValue(EnerCubixMath.num(total["value"]),total["quality"].toStr,EnerCubixMath.strings(total["sourceIds"]))
    summary:=base(summaryId,summaryId,ctx.byId[category]?.get("name")?.toStr ?: category,"summary",null,v,EnerCubixValue(EnerCubixMath.num(total["knownValue"]),total["knownQuality"].toStr))
    ns:=[summary];ls:=[Str:Obj?][,]
    graphs.each |g|
    {
      ns.addAll(EnerCubixMath.maps(g["nodes"]));ls.addAll(EnerCubixMath.maps(g["links"]))
      root:=EnerCubixMath.maps(g["nodes"]).first
      if (good(v) && root != null && EnerCubixMath.num(root["knownValue"]) != null && (Float)root["knownValue"] > 0f)
        ls.add(["source":summaryId,"target":root["id"],"value":root["knownValue"],"quality":root["knownQuality"],"relationKind":"metering","sourceIds":root["sourceIds"],"percentage":null])
    }
    unassigned:=EnerCubixMath.maps(plan["unassigned"]).map |r->[Str:Obj?]| {id:=r["id"].toStr;return base(id,id,ctx.displayName(id),"meter",null,usage(id),knownUsage(id))}
    return ["categoryId":category,"unit":unit,"focusId":summaryId,"rootIds":roots.map |r->Str| {r["id"].toStr},"nodes":ns,"links":ls,"unassigned":unassigned]
  }

  private Str:Obj? base(Str occurrence,Str id,Str name,Str type,Str? parent,EnerCubixValue value,EnerCubixValue known)
  {
    row:=Str:Obj?["id":occurrence,"nodeId":id,"graphId":graphId,"name":name,"nodeType":type,"categoryId":category,"unit":unit,"value":value.value,"quality":value.quality,"sourceIds":value.sources,"submeter":null,"difference":null,"balanceQuality":value.quality,"hasChildren":false,"percentage":null]
    row.setAll(EnerCubixKnownUsage.fields(known));if (parent != null) row["parentId"]=parent
    return row
  }

  private EnerCubixValue usage(Str id) {read(id,false)}
  private EnerCubixValue knownUsage(Str id) {read(id,true)}
  private EnerCubixValue read(Str id,Bool known)
  {
    cache:=known ? knownValues : values
    if (cache.containsKey(id)) return cache[id]
    if (dim.scope(id))
    {
      pieces:=EnerCubixMath.strings(boundaries(id)["members"]).map |m->EnerCubixValue| {read(m,known)}
      value:=known ? EnerCubixKnownUsage.combine(pieces) : EnerCubixValue.sum(pieces)
      cache[id]=value;return value
    }
    pieces:=EnerCubixValue[,];cursor:=from
    while (cursor < to)
    {
      end:=EnerCubixMath.floorHour(cursor)+1hr;if (end > to) end=to
      pieces.add((known ? knownCtx : ctx).node(id,category,cursor,end));cursor=end
    }
    value:=known ? EnerCubixKnownUsage.combine(pieces) : EnerCubixValue.sum(pieces)
    if (value.value != null && value.value < 0f) value=EnerCubixValue(value.value,"negative",value.sources)
    cache[id]=value;return value
  }

  private Void addLink(Str source,Str target,EnerCubixValue value,EnerCubixValue? parent,Str relation)
  {links.add(["source":source,"target":target,"value":value.value,"quality":value.quality,"sourceIds":value.sources,"percentage":relation == "calculation" ? null : percentage(value,parent),"relationKind":relation])}
  private Str? membership(Str:Obj? r)
  {
    if (dim.dimension == "organization") return r["organizationId"] as Str
    if (dim.nativeSpace && r["pointId"] != null && r["expressionId"] == null) return r["nativeSpaceId"] as Str
    return r["spaceId"] as Str
  }
  private Str physicalId(Str:Obj? r)
  {
    point:=(r["historyPointId"] ?: r["pointId"]) as Str
    if (point == null) return r["id"].toStr
    matches:=dim.records.findAll |m| {meter(m) && !derived(m) && m["categoryId"] == category && (m["historyPointId"] ?: m["pointId"]) == point && m["_comparisonReadable"] != false}
    return matches.map |m->Str| {m["id"].toStr}.sort.first ?: r["id"].toStr
  }
  private Bool ancestor(Str parent,Str child)
  {
    seen:=Str[,];cursor:=ctx.byId[child]?.get("meterParentId") as Str
    while (cursor != null && !seen.contains(cursor))
    {
      if (cursor == parent) return true
      seen.add(cursor);cursor=ctx.byId[cursor]?.get("meterParentId") as Str
    }
    return false
  }
  private Bool validChain(Str id)
  {
    seen:=Str[,];cursor:=id
    while (!seen.contains(cursor))
    {
      seen.add(cursor);r:=ctx.byId[cursor]
      if (r == null || !meter(r) || r["categoryId"] != category) return false
      parent:=r["meterParentId"] as Str
      if (parent == null) return true
      cursor=parent
    }
    return false
  }
  private static Bool derived(Str:Obj? r) {r["autoSum"] == true || r["expressionId"] != null || (r["meterOrigin"] as Map)?.get("type") == "virtual"}
  private static Bool meter(Str:Obj? r) {["meter","totalMeter"].contains(r["kind"])}
  private static Bool included(Str:Obj? r) {meter(r) && ((Bool?)r["includeInTotals"] ?: (r["expressionId"] == null))}
  private static Bool excludedAncestor(Str:Obj? r,EnerCubixDimension dim)
  {
    seen:=Str[,];parent:=r["meterParentId"] as Str
    while (parent != null && !seen.contains(parent))
    {
      seen.add(parent);next:=dim.byId[parent]
      if (next == null) return false
      if (meter(next) && !included(next)) return true
      parent=next["meterParentId"] as Str
    }
    return false
  }
  private static Bool good(EnerCubixValue? v) {v?.value != null && v.value >= 0f && ["ok","estimated","derived","cleaned","corrected"].contains(v.quality)}
  private static Float? percentage(EnerCubixValue v,EnerCubixValue? parent) {good(v) && good(parent) && v.value > 0f && parent.value > 0f ? v.value/parent.value*100f : null}
}

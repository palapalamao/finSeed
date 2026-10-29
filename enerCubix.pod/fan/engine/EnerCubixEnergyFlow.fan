** Current relationships describe independent object graphs. Stored readings are
** never replaced by child sums; known subtotals remain drawable.
internal class EnerCubixEnergyFlow
{
  new make(EnerCubixContext ctx, Str:Obj? request, DateTime from, DateTime to, [Str:Obj?][] histories := [Str:Obj?][,])
  {
    this.ctx=ctx; this.request=request; this.from=from; this.to=to; this.histories=histories
    dim=ctx.dimension ?: throw ArgErr("Invalid report dimension")
    category=request["categoryId"]?.toStr ?: ""
    unit=ctx.unit("",category,request["metric"] as Str ?: "energy")
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
  private Bool calculationGraph:=false
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
    if (!["metering","space","organization"].contains(req["dimension"]) || !["energy","cost"].contains(req["metric"]) || req["perArea"] == true)
      throw ArgErr("能流图支持能耗或费用，不支持面积归一化")
    category:=req["categoryId"]?.toStr ?: ""
    cat:=dim.records.find |r| {r["id"] == category && r["kind"] == "category"}
    if (cat == null || (cat["unit"]?.toStr ?: "").isEmpty) throw ArgErr("能流图请选择有计量单位的能源类型")
    if (req["flowMode"] != null && !["relations","endUse"].contains(req["flowMode"])) throw ArgErr("endUseInvalidMode")
    if (req["flowMode"] == "endUse") return endUseScope(req,dim)
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
    covered:=roots.findAll |root| {id:=root["id"].toStr;return dim.scope(id) && roots.any |other| {other != root && scopeAncestor(other["id"].toStr,id,dim)}}
    roots=roots.findAll |root| {!covered.contains(root)}
    reachable:=Str[,]
    roots.each |root|
    {
      id:=root["id"].toStr
      if (dim.scope(id)) reachable.addAll(dim.members(id).findAll |r| {r["categoryId"] == category}.map |r->Str| {r["id"].toStr})
      else closure(id,dim,category,reachable)
    }
    reachable=reachable.unique
    unassigned:=ids.isEmpty && dim.dimension == "metering" ? automatic.findAll |r| {!reachable.contains(r["id"].toStr)} : [Str:Obj?][,]
    return ["meters":automatic,"roots":roots.sort |a,b| {a["id"].toStr <=> b["id"].toStr},"selected":meters.findAll |r| {reachable.contains(r["id"].toStr)},"unassigned":unassigned,"coveredScopes":covered.map |r->[Str:Obj?]| {["id":r["id"],"name":r["name"]]}]
  }

  private static Bool scopeAncestor(Str parent,Str child,EnerCubixDimension dim)
  {
    if (!dim.scope(parent) || !dim.scope(child)) return false
    seen:=[child];cursor:=dim.byId[child]?.get("parentId") as Str
    while (cursor != null)
    {
      if (seen.contains(cursor) || !dim.scope(cursor)) return false
      seen.add(cursor);cursor=dim.byId[cursor]?.get("parentId") as Str
    }
    return seen.contains(parent)
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
    if (request["flowMode"] == "endUse") return endUseReport(plan)
    ownIds:=EnerCubixMath.maps(plan["selected"]).dup.addAll(EnerCubixMath.maps(plan["unassigned"])).map |r->Str| {r["id"].toStr}.unique
    overview:=EnerCubixFlowOverview.build(request,dim.records,histories,ownIds)
    graphs:=[Str:Obj?][,]
    roots.each |root|
    {
      id:=root["id"].toStr; graphId=dim.dimension+"|"+id; nodes=[Str:Obj?][,]; links=[Str:Obj?][,]
      grouped:=dim.scope(id)
      calculationGraph=!grouped && derived(root)
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
        if (own != null)
        {
          ["coverage","coveredSeconds","activeSeconds","complete","completeValue","completeQuality"].each |key| {n[key]=own[key]}
          row.setAll(own).set("id",n["id"]).set("graphId",g["graphId"])
        }
        rows.add(row)
        point:=Str:Obj?["ts":from.toIso,"value":n["value"],"quality":n["quality"],"sourceIds":n["sourceIds"],"knownValue":n["knownValue"],"knownValueType":n["knownValueType"],"knownQuality":n["knownQuality"]]
        series.add(["id":n["id"],"nodeId":n["nodeId"],"graphId":g["graphId"],"name":n["name"],"categoryId":category,"unit":unit,"points":[point]])
      }
    }
    flow:=compatible(graphs,roots,plan,total)
    return ["kind":"energyFlow","from":from.toIso,"to":to.toIso,"period":request["period"] ?: "day","series":series,"rows":rows,"warnings":ctx.warnings,
      "summary":["value":strictTotal.value,"unit":unit,"selectionTotals":[total]],
      "extra":["energyFlow":flow,"energyFlowGraphs":graphs,"energyFlowAccounting":accounting,"energyFlowOverview":overview,"energyFlowCoveredScopes":plan["coveredScopes"],"selectionTotals":[total],"usageBasis":"knownUsage","knownUsage":overview["knownUsage"]]]
  }

  ** Reuse the physical-boundary resolver directly; this is not a leak report.
  private static Str:Obj? endUseScope(Str:Obj? req,EnerCubixDimension dim)
  {
    category:=req["categoryId"].toStr
    ids:=EnerCubixMath.strings(req["nodeIds"]).map |id->Str| {dim.canonical(id)}.unique
    if (ids.isEmpty) ids=dim.records.findAll |r| {meter(r) && r["kind"] == "totalMeter" && r["categoryId"] == category && r["meterParentId"] == null && included(r)}.map |r->Str| {r["id"].toStr}
    ids.each |id|
    {
      r:=dim.byId[id]
      if (r == null || !meter(r) || r["categoryId"] != category || r["_comparisonReadable"] == false)
        throw ArgErr("endUseMeterRequired")
    }
    if (ids.isEmpty) return ["roots":[Str:Obj?][,],"selected":[Str:Obj?][,],"unassigned":[Str:Obj?][,]]
    checked:=dim.records.map |r->[Str:Obj?]| {r["_flowBoundaryUnavailable"] == true ? r.dup.set("_comparisonUnavailable",true) : r}
    boundary:=EnerCubixComparisonScope(req.dup.set("nodeIds",ids),checked)
    own:=ids.dup.addAll(boundary.memberIds).unique
    return ["roots":ids.sort.map |id->[Str:Obj?]| {dim.byId[id]},"selected":dim.records.findAll |r| {own.contains(r["id"])},"unassigned":[Str:Obj?][,],"boundary":boundary]
  }

  private Str:Obj? endUseReport(Str:Obj? plan)
  {
    roots:=EnerCubixMath.maps(plan["roots"])
    boundary:=plan["boundary"] as EnerCubixComparisonScope
    ctx.comparison=boundary;knownCtx.comparison=boundary
    ownIds:=EnerCubixMath.maps(plan["selected"]).map |r->Str| {r["id"].toStr}.unique
    overviewRecords:=dim.records.map |r->[Str:Obj?]|
    {
      copy:=r.dup
      if (r["_comparisonReadable"] == false || r["_comparisonPointReadable"] == false) copy.remove("pointId")
      return copy
    }
    overview:=EnerCubixFlowOverview.build(request,overviewRecords,histories,ownIds)
    EnerCubixMath.maps(overview["rows"]).each |row|
    {
      r:=ctx.byId[row["nodeId"].toStr]
      if (r?.get("_comparisonReadable") == false || r?.get("_comparisonPointReadable") == false)
        row.setAll(["value":null,"valueType":"null","quality":"forbidden","completeValue":null,"completeQuality":"forbidden","sourceIds":Str[,],"periods":[Str:Obj?][,],"coverage":0f,"coveredSeconds":0f,"complete":false])
    }
    graphs:=[Str:Obj?][,]
    roots.each |root|
    {
      id:=root["id"].toStr; graphId="endUse|"+id; nodes=[Str:Obj?][,];links=[Str:Obj?][,]
      members:=boundary.members(id)
      own:=usage(id);known:=knownUsage(id)
      readings:=members.map |m->EnerCubixValue| {usage(m["id"].toStr)}
      observed:=members.map |m->EnerCubixValue| {knownUsage(m["id"].toStr)}
      overlap:=EnerCubixEndUse.overlap(ctx,members,readings)
      quality:=overlap ? "overlappingScopes" : (boundary.quality(id) ?: "ok")
      subtotal:=EnerCubixValue.sum(readings);knownSubtotal:=EnerCubixKnownUsage.combine(observed)
      if (members.isEmpty) {subtotal=EnerCubixValue(null,"missingBranches");knownSubtotal=EnerCubixValue(null,"missingBranches")}
      if (overlap) {subtotal=EnerCubixValue(null,quality,subtotal.sources);knownSubtotal=EnerCubixValue(null,quality,knownSubtotal.sources)}
      mode:=derived(root) ? "consistency" : EnerCubixBalance.mode(ctx,id)
      // Provenance shared by root and members is a consistency comparison.
      if (own.sources.any |source| {subtotal.sources.contains(source)}) mode="consistency"
      Float? difference:=quality == "ok" && good(own) && good(subtotal) ? own.value-subtotal.value : null
      if (difference != null && difference < 0f && difference.abs <= (own.value.abs+1f)*0.000000001f) difference=0f
      balanceQuality:=quality == "ok" ? EnerCubixValue.worse(own.quality,subtotal.quality) : quality
      if (difference != null && difference < 0f) balanceQuality="negativeBalance"
      negative:=own.quality == "negative" || known.quality == "negative" || readings.dup.addAll(observed).any |EnerCubixValue v->Bool| {v.quality == "negative" || (v.value != null && v.value < 0f)}
      knownOverflow:=nonnegative(known) && nonnegative(knownSubtotal) && knownSubtotal.value > known.value+(known.value.abs+1f)*0.000000001f
      weightedSafe:=quality == "ok" && !members.isEmpty && !negative && nonnegative(known) && observed.all |v| {nonnegative(v)} && nonnegative(knownSubtotal) && !knownOverflow
      if (negative) balanceQuality="negative"
      else if (knownOverflow) balanceQuality="negativeBalance"
      strictComplete:=good(own) && readings.all |v| {good(v)} && [id].dup.addAll(members.map |m->Str| {m["id"].toStr}).all |meterId| {EnerCubixMath.maps(overview["rows"]).find |r| {r["id"] == meterId}?.get("complete") == true}
      row:=base(id,id,ctx.displayName(id),"meter",null,own,known)
      row.setAll(["hasChildren":!members.isEmpty,"submeter":subtotal.value,"knownSubmeter":knownSubtotal.value,"knownSubmeterQuality":knownSubtotal.quality,"difference":difference,"balanceQuality":balanceQuality,"balanceMode":mode,"lossEligible":request["metric"] != "cost" && weightedSafe && strictComplete && EnerCubixBalance.eligible(mode,own,subtotal)])
      nodes.add(row)
      members.map |m->Str| {m["utilityId"] as Str ?: ""}.unique.sort.each |utility|
      {
        subset:=members.findAll |m| {(m["utilityId"] as Str ?: "") == utility}
        strict:=EnerCubixValue.sum(subset.map |m->EnerCubixValue| {usage(m["id"].toStr)})
        available:=EnerCubixKnownUsage.combine(subset.map |m->EnerCubixValue| {knownUsage(m["id"].toStr)})
        if (EnerCubixEndUse.overlap(ctx,subset,subset.map |m->EnerCubixValue| {usage(m["id"].toStr)}))
        {strict=EnerCubixValue(null,"overlappingScopes",strict.sources);available=EnerCubixValue(null,"overlappingScopes",available.sources)}
        utilityNode:="__energyFlowUtility__:"+id+"|"+utility
        classified:=base(utilityNode,utilityNode,ctx.byId[utility]?.get("name")?.toStr ?: utility,"utility",id,strict,available)
        classified.setAll(["utilityId":utility,"memberIds":subset.map |m->Str| {m["id"].toStr},"hasChildren":true,"percentage":weightedSafe ? percentage(strict,own) : null])
        nodes.add(classified)
        if (weightedSafe && available.value != null && available.value > 0f) addLink(id,utilityNode,available,known,"classification")
        subset.each |member|
        {
          memberId:=member["id"].toStr
          v:=usage(memberId);k:=knownUsage(memberId)
          n:=base(memberId,memberId,ctx.displayName(memberId),"meter",utilityNode,v,k)
          n.setAll(["utilityId":utility,"percentage":weightedSafe ? percentage(v,strict) : null])
          nodes.add(n)
          if (weightedSafe && k.value != null && k.value > 0f) addLink(utilityNode,memberId,k,available,"classification")
        }
      }
      if (difference != null && difference > 0f && row["lossEligible"] == true)
      {
        residualId:="__energyFlowDifference__:"+id
        residual:=EnerCubixValue(difference,balanceQuality,own.sources.dup.addAll(subtotal.sources).unique)
        n:=base(residualId,residualId,"","difference",id,residual,residual)
        n["percentage"]=percentage(residual,own);nodes.add(n);addLink(id,residualId,residual,own,"classification")
      }
      if (quality != "ok") ctx.warn(quality == "comparisonEmpty" ? "endUseBoundaryEmpty" : quality)
      if (balanceQuality == "negativeBalance") ctx.warn("negativeBalance")
      graphs.add(["graphId":graphId,"objectId":id,"basis":"endUse","categoryId":category,"unit":unit,"focusId":id,"rootIds":[id],"nodes":nodes,"links":links,"unassigned":[Str:Obj?][,],"contributionMemberIds":members.map |m->Str| {m["id"].toStr},"sharedMemberIds":Str[,],"additive":!overlap,"boundaryQuality":quality])
    }
    // Each root remains a separate measured object. Shared branches or parent
    // selections forbid an aggregate, while preserving every own reading.
    owners:=Str:Str[][:]
    graphs.each |g| {EnerCubixMath.strings(g["contributionMemberIds"]).each |id| {if (!owners.containsKey(id)) owners[id]=Str[,];owners[id].add(g["objectId"].toStr)}}
    memberIds:=owners.keys.sort
    for (i:=0;i<memberIds.size;i++) for (j:=i+1;j<memberIds.size;j++)
    {
      a:=memberIds[i];b:=memberIds[j]
      cross:=owners[a].any |root| {owners[b].any |other| {root != other}}
      if (cross && EnerCubixEndUse.overlap(ctx,[ctx.byId[a],ctx.byId[b]],[usage(a),usage(b)]))
      {
        combined:=owners[a].dup.addAll(owners[b]).unique
        owners[a]=combined;owners[b]=combined
      }
    }
    shared:=owners.keys.findAll |id| {owners[id].size > 1}.sort
    graphs.each |g| {g["sharedMemberIds"]=EnerCubixMath.strings(g["contributionMemberIds"]).findAll |id| {shared.contains(id)}}
    rootOverlap:=EnerCubixEndUse.overlap(ctx,roots,roots.map |r->EnerCubixValue| {usage(r["id"].toStr)})
    safe:=!graphs.isEmpty && shared.isEmpty && !rootOverlap && graphs.all |g| {g["additive"] == true && g["boundaryQuality"] == "ok"}
    strictTotal:=EnerCubixValue.sum(roots.map |r->EnerCubixValue| {usage(r["id"].toStr)})
    knownTotal:=EnerCubixKnownUsage.combine(roots.map |r->EnerCubixValue| {knownUsage(r["id"].toStr)})
    accountingQuality:=!shared.isEmpty || rootOverlap ? "overlappingScopes" : (graphs.find |g| {g["boundaryQuality"] != "ok"}?.get("boundaryQuality") as Str ?: "comparisonEmpty")
    if (!safe) {strictTotal=EnerCubixValue(null,accountingQuality,strictTotal.sources);knownTotal=EnerCubixValue(null,accountingQuality,knownTotal.sources)}
    branchUnion:=EnerCubixKnownUsage.combine(owners.keys.sort.map |id->EnerCubixValue| {knownUsage(id)})
    accounting:=Str:Obj?["canAdd":safe,"basis":safe ? "physicalBoundary" : "unavailable","memberIds":owners.keys.sort,"sharedMemberIds":shared,"sharedMembers":shared.map |id->[Str:Obj?]| {["meterId":id,"objectIds":owners[id]]},"unionValue":safe ? branchUnion.value : null,"unionQuality":safe ? branchUnion.quality : accountingQuality]
    total:=Str:Obj?["id":category+"|"+unit,"categoryId":category,"unit":unit,"value":strictTotal.value,"quality":strictTotal.quality,"meterIds":roots.map |r->Str| {r["id"].toStr},"sourceIds":strictTotal.sources]
    total.setAll(EnerCubixKnownUsage.fields(knownTotal));overview["selectionTotals"]=[total]
    rows:=[Str:Obj?][,];series:=[Str:Obj?][,]
    graphs.each |g|
    {
      EnerCubixMath.maps(g["nodes"]).each |n|
      {
        own:=EnerCubixMath.maps(overview["rows"]).find |r| {r["id"] == n["nodeId"]}
        if (own != null) ["coverage","coveredSeconds","activeSeconds","complete","completeValue","completeQuality"].each |key| {n[key]=own[key]}
        rows.add(n.dup)
        series.add(["id":g["graphId"].toStr+"|"+n["id"].toStr,"nodeId":n["nodeId"],"graphId":g["graphId"],"name":n["name"],"categoryId":category,"unit":unit,"points":[["ts":from.toIso,"value":n["value"],"quality":n["quality"],"sourceIds":n["sourceIds"],"knownValue":n["knownValue"],"knownValueType":n["knownValueType"],"knownQuality":n["knownQuality"]]]])
      }
    }
    return ["kind":"energyFlow","from":from.toIso,"to":to.toIso,"period":request["period"] ?: "day","series":series,"rows":rows,"warnings":ctx.warnings,
      "summary":["value":strictTotal.value,"unit":unit,"selectionTotals":[total]],
      "extra":["energyFlow":compatible(graphs,roots,plan,total).set("basis","endUse"),"energyFlowGraphs":graphs,"energyFlowAccounting":accounting,"energyFlowOverview":overview,"selectionTotals":[total],"usageBasis":"knownUsage","knownUsage":overview["knownUsage"]]]
  }

  private Void build(Str id,Str? parent,EnerCubixValue? parentValue,Str[] path,Bool grouping)
  {
    r:=ctx.byId[id]
    if (r == null || path.contains(id) || r["_comparisonReadable"] == false) return
    occurrence:=nodes.any |n| {n["id"] == id} ? id+"|"+nodes.size : id
    value:=usage(id);known:=knownUsage(id)
    row:=base(occurrence,id,ctx.displayName(id),dim.scope(id) ? dim.dimension : "meter",parent,value,known)
    row["percentage"]=calculationGraph ? null : percentage(value,parentValue);nodes.add(row)
    children:=Str[,];relation:=grouping ? "grouping" : (derived(r) ? "calculation" : "metering")
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
    groupingBoundaries:=Str:Str[][:]
    if (grouping) children.each |child| {groupingBoundaries[child]=groupingMembers(child)}
    suppressed:=Str[,];seenPoints:=Str[,]
    children.each |child|
    {
      c:=ctx.byId[child]
      if (grouping)
      {
        members:=groupingBoundaries[child]
        if (!members.isEmpty && members.all |member| {children.any |other| {other != child && groupingBoundaries[other].any |otherMember| {ancestor(member,otherMember) || (member == otherMember && other < child)}}}) suppressed.add(child)
        return
      }
      if (!meter(c)) return
      if (!derived(c))
      {
        physical:=physicalId(c)
        if (seenPoints.contains(physical)) suppressed.add(child)
        else seenPoints.add(physical)
      }
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
    distributionSafe:=true
    if (grouping)
    {
      seenMembers:=Str[,]
      displayed.each |child|
      {
        members:=groupingBoundaries[child]
        if (members.any |m| {seenMembers.any |other| {m == other || ancestor(m,other) || ancestor(other,m)}}) distributionSafe=false
        seenMembers.addAll(members)
      }
      if (!distributionSafe) quality="overlappingScopes"
      distributionSafe=distributionSafe && known.value != null && known.value >= 0f && knownSubtotal.value != null && knownSubtotal.value >= 0f && knownSubtotal.value <= known.value+(known.value.abs+1f)*0.000000001f && displayed.all |child| {v:=knownUsage(child);return v.value != null && v.value >= 0f}
      row["distributionComparable"]=distributionSafe
    }
    if (difference != null && difference < 0f && difference.abs <= (value.value.abs+1f)*0.000000001f) difference=0f
    if (difference != null && difference < 0f) {quality="negativeBalance";ctx.warn(ctx.displayName(id)+": 分表合计大于总表，差额为负，请核对计量关系与数据")}
    row["submeter"]=subtotal.value;row["knownSubmeter"]=knownSubtotal.value;row["knownSubmeterQuality"]=knownSubtotal.quality;row["difference"]=difference;row["balanceQuality"]=quality
    row["balanceMode"]=mode;row["lossEligible"]=request["metric"] != "cost" && !grouping && ["ok","estimated","derived","cleaned","corrected"].contains(quality) && EnerCubixBalance.eligible(mode,value,subtotal)
    children.each |child|
    {
      before:=nodes.size;build(child,occurrence,value,path.dup.add(id),grouping)
      if (nodes.size == before) return
      target:=nodes[before]["id"].toStr;amount:=knownUsage(child)
      if (suppressed.contains(child)) {nodes[before]["percentage"]=null;if (grouping) nodes[before]["referenceOnly"]=true}
      if (grouping && !distributionSafe) nodes[before]["percentage"]=null
      if (!suppressed.contains(child) && distributionSafe && amount.value != null && amount.value > 0f) addLink(occurrence,target,amount,known,relation)
    }
    if (difference != null && difference > 0f && good(value) && good(subtotal))
    {
      diffId:="__energyFlowDifference__:$occurrence";v:=EnerCubixValue(difference,quality,value.sources.dup.addAll(subtotal.sources).unique)
      gap:=base(diffId,diffId,"","difference",occurrence,v,v);gap["percentage"]=percentage(v,value);gap["balanceMode"]=mode;gap["lossEligible"]=row["lossEligible"]
      nodes.add(gap);addLink(occurrence,diffId,v,value,"metering")
    }
  }

  private Str[] groupingMembers(Str id)
  {
    if (dim.scope(id)) return EnerCubixMath.strings(boundaries(id)["members"])
    r:=ctx.byId[id]
    return r == null ? Str[,] : [derived(r) ? id : physicalId(r)]
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
    if (request["flowMode"] == "endUse" && (ctx.byId[id]?.get("_comparisonReadable") == false || ctx.byId[id]?.get("_comparisonPointReadable") == false)) return EnerCubixValue(null,"forbidden")
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
      pieces.add((known ? knownCtx : ctx).node(id,category,cursor,end,request["metric"] as Str ?: "energy"));cursor=end
    }
    value:=known ? EnerCubixKnownUsage.combine(pieces) : EnerCubixValue.sum(pieces)
    if (!known && request["flowMode"] == "endUse" && value.value == null && value.quality == "missing" && knownUsage(id).quality == "na") value=EnerCubixValue(null,"na",value.sources)
    if (value.value != null && value.value < 0f) value=EnerCubixValue(value.value,"negative",value.sources)
    cache[id]=value;return value
  }

  private Void addLink(Str source,Str target,EnerCubixValue value,EnerCubixValue? parent,Str relation)
  {links.add(["source":source,"target":target,"value":value.value,"quality":value.quality,"sourceIds":value.sources,"percentage":relation == "calculation" ? null : percentage(value,parent),"relationKind":relation])}
  private Str? membership(Str:Obj? r)
  {
    if (dim.dimension == "organization") return r["organizationId"] as Str
    if (dim.nativeSpace && r["nativeEquip"] == true)
    {
      coverage:=r["spaceId"] as Str
      return coverage != null && coverage != r["id"] ? coverage : r["nativeTreeParentId"] as Str
    }
    if (dim.nativeSpace && r["pointId"] != null && r["expressionId"] == null) return r["nativeSpaceId"] as Str
    return r["spaceId"] as Str
  }
  private Str physicalId(Str:Obj? r)
  {
    point:=r["pointId"] as Str
    if (point == null) return r["id"].toStr
    matches:=dim.records.findAll |m| {meter(m) && !derived(m) && m["categoryId"] == category && m["pointId"] == point && m["_comparisonReadable"] != false}
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
  private static Bool nonnegative(EnerCubixValue v) {EnerCubixMath.num(v.value) != null && v.value >= 0f}
  private static Float? percentage(EnerCubixValue v,EnerCubixValue? parent) {good(v) && good(parent) && v.value > 0f && parent.value > 0f ? v.value/parent.value*100f : null}
}

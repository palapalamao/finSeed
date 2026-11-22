** Current relationships describe independent object graphs. Stored readings are
** never replaced by child sums; known subtotals remain drawable.
internal class FinEnergyEnergyFlow
{
  new make(FinEnergyContext ctx, Str:Obj? request, DateTime from, DateTime to, [Str:Obj?][] histories := [Str:Obj?][,])
  {
    this.ctx=ctx; this.request=request; this.from=from; this.to=to; this.histories=histories
    dim=ctx.dimension ?: throw ArgErr("Invalid report dimension")
    category=request["categoryId"]?.toStr ?: ""
    unit=ctx.unit("",category,request["metric"] as Str ?: "energy")
    cutoff:=FinEnergyKnownUsage.cutoff(request)
    knownCtx=FinEnergyContext.known(ctx,to < cutoff ? to : cutoff)
  }
  private FinEnergyContext ctx
  private FinEnergyContext knownCtx
  private FinEnergyDimension dim
  private Str:Obj? request
  private DateTime from
  private DateTime to
  private Str category
  private Str unit
  private [Str:Obj?][] histories
  private Str:FinEnergyValue values:=[:]
  private Str:FinEnergyValue knownValues:=[:]
  private [Str:Obj?][] nodes:=[,]
  private [Str:Obj?][] links:=[,]
  private Str graphId:=""
  private Bool calculationGraph:=false
  private Str[] allowed:=Str[,]
  private |Str,Bool->FinEnergyValue|? preparedValue
  private [Str:Obj?]? preparedOverview
  private FinEnergyPreparedOwner? projectionOwner
  private FinEnergyPreparedOwner? projectionState
  private Obj[] projectionRoots := [,]

  ** Pure current-relationship energy projection. The provider owns each
  ** device's independently folded primary value and replays that device's
  ** strict warnings in visitation order. There is no history fallback.
  internal static Str:Obj? projectPrepared(FinEnergyContext ctx,Str:Obj? request,DateTime from,DateTime to,|Str,Bool->FinEnergyValue| value,Str:Obj? overview,FinEnergyPreparedOwner? output := null)
  {
    if(request["metric"]!="energy" || request["flowMode"]=="endUse" || request["meterHistorySegments"]!=null) throw ArgErr("preparedFlowProjectionPlan")
    if(output!=null && !ctx.ownedCatalog(output.budget)) throw ArgErr("preparedFlowProjectionOwner")
    output?.hold(24)
    flow:=FinEnergyEnergyFlow(ctx,request,from,to)
    flow.preparedValue=value;flow.preparedOverview=overview
    flow.projectionOwner=output
    if(output!=null)
    {
      output.watch |->Void| {flow.projectionRoots.each |root| {if(root is Map) ((Map)root).clear;else ((List)root).clear};flow.projectionRoots.clear}
      flow.projectionState=FinEnergyPreparedOwner(output.budget)
    }
    try {return flow.report}
    finally
    {
      flow.values.clear;flow.knownValues.clear;flow.allowed=Str[,]
      flow.preparedValue=null;flow.preparedOverview=null;flow.projectionState?.close
    }
  }
  // Every newly retained container is charged before construction. Only these
  // roots are cleared; primary-value source arrays and overview rows are borrowed.
  private Void outputHold(Int cells) {projectionOwner?.hold(cells)}
  private Void remember(Obj value) {if(projectionOwner!=null) projectionRoots.add(value)}
  private FinEnergyPreparedOwner? workspace(Int cells)
  {
    if(projectionOwner==null) return null
    lease:=FinEnergyPreparedOwner(projectionOwner.budget)
    try {lease.hold(cells);return lease} catch(Err e) {lease.close;throw e}
  }

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
  static Str:Obj? scope(Str:Obj? req, FinEnergyDimension dim,FinEnergyPreparedOwner? work := null)
  {
    work?.budget?.deadline?.check
    work?.hold(32+12*dim.records.size)
    if (!["metering","space","organization"].contains(req["dimension"]) || !["energy","cost"].contains(req["metric"]) || req["perArea"] == true)
      throw ArgErr("能流图支持能耗或费用，不支持面积归一化")
    category:=req["categoryId"]?.toStr ?: ""
    cat:=dim.records.find |r| {r["id"] == category && r["kind"] == "category"}
    if (cat == null || (cat["unit"]?.toStr ?: "").isEmpty) throw ArgErr("能流图请选择有计量单位的能源类型")
    if (req["flowMode"] != null && !["relations","endUse"].contains(req["flowMode"])) throw ArgErr("endUseInvalidMode")
    if (req["flowMode"] == "endUse") return endUseScope(req,dim)
    meters:=dim.records.findAll |r| {meter(r) && r["categoryId"] == category}
    automatic:=meters.findAll |r| {included(r) && !excludedAncestor(r,dim)}
    ids:=FinEnergyMath.strings(req["nodeIds"]).map |id->Str| {dim.canonical(id)}.unique
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
    if (req["_cockpitExplicitObjects"] == true) covered=[Str:Obj?][,]
    else roots=roots.findAll |root| {!covered.contains(root)}
    reachable:=Str[,]
    roots.each |root|
    {
      id:=root["id"].toStr
      work?.budget?.deadline?.check
      if (dim.scope(id)) {members:=dim.members(id).findAll |r| {r["categoryId"] == category};work?.hold(members.size);reachable.addAll(members.map |r->Str| {r["id"].toStr})}
      else closure(id,dim,category,reachable,work)
    }
    reachable=reachable.unique
    unassigned:=ids.isEmpty && dim.dimension == "metering" ? automatic.findAll |r| {!reachable.contains(r["id"].toStr)} : [Str:Obj?][,]
    return ["meters":automatic,"roots":roots.sort |a,b| {a["id"].toStr <=> b["id"].toStr},"selected":meters.findAll |r| {reachable.contains(r["id"].toStr)},"unassigned":unassigned,"coveredScopes":covered.map |r->[Str:Obj?]| {["id":r["id"],"name":r["name"]]}]
  }

  private static Bool scopeAncestor(Str parent,Str child,FinEnergyDimension dim)
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

  private static Void closure(Str id,FinEnergyDimension dim,Str category,Str[] found,FinEnergyPreparedOwner? work := null)
  {
    work?.budget?.deadline?.check
    if (found.contains(id)) return
    r:=dim.byId[id]
    if (r == null || !meter(r) || r["categoryId"] != category || r["_comparisonReadable"] == false) return
    work?.hold(3);found.add(id)
    refs:=Str[,]
    if (r["expressionId"] != null)
    {
      expr:=dim.byId[r["expressionId"].toStr]
      if (expr?.get("_comparisonReadable") == false) return
      vars:=expr?.get("variables") as Map
      work?.hold(2+3*(vars?.size ?: 0))
      if (vars != null) vars.vals.each |ref| {if (ref != null) refs.add(dim.canonical(ref.toStr))}
    }
    else
    {
      if(work!=null) {n:=0;dim.records.each |candidate| {if(included(candidate) && candidate["meterParentId"]==id) n++};work.hold(2+3*n)}
      refs=dim.directChildren(id).map |m->Str| {m["id"].toStr}
    }
    refs.unique.each |ref| {closure(ref,dim,category,found,work)}
  }

  Str:Obj? report()
  {
    scratch:=workspace(64)
    try
    {
    plan:=scope(request,dim,scratch); roots:=FinEnergyMath.maps(plan["roots"])
    if (request["flowMode"] == "endUse") return endUseReport(plan)
    ownIds:=FinEnergyMath.maps(plan["selected"]).dup.addAll(FinEnergyMath.maps(plan["unassigned"])).map |r->Str| {r["id"].toStr}.unique
    overview:=preparedOverview ?: FinEnergyFlowOverview.build(request,dim.records,histories,ownIds)
    outputHold(2+roots.size);graphs:=[Str:Obj?][,];remember(graphs)
    roots.each |root|
    {
      ctx.deadline?.check
      id:=root["id"].toStr; graphId=dim.dimension+"|"+id
      outputHold(4);nodes=[Str:Obj?][,];links=[Str:Obj?][,];remember(nodes);remember(links)
      grouped:=dim.scope(id)
      calculationGraph=!grouped && derived(root)
      allowed=grouped ? dim.members(id).findAll |r| {r["categoryId"] == category}.map |r->Str| {r["id"].toStr} : ownIds
      build(id,null,null,Str[,],grouped)
      boundary:=grouped ? boundaries(id,scratch) : contribution(id,Str[,],scratch)
      basis:=grouped ? dim.dimension : (derived(root) ? "calculation" : "metering")
      memberCount:=((List)boundary["members"]).size
      outputHold(25+memberCount)
      members:=FinEnergyMath.strings(boundary["members"]);rootIds:=[id];unassigned:=[Str:Obj?][,];shared:=Str[,]
      graph:=Str:Obj?["graphId":graphId,"objectId":id,"basis":basis,"categoryId":category,"unit":unit,"focusId":id,"rootIds":rootIds,"nodes":nodes,"links":links,"unassigned":unassigned,"contributionMemberIds":members,"sharedMemberIds":shared,"additive":boundary["additive"] == true,"boundaryQuality":boundary["quality"] ?: "ok"]
      remember(members);remember(rootIds);remember(unassigned);remember(shared);remember(graph);graphs.add(graph)
    }
    accounting:=account(graphs,FinEnergyMath.maps(plan["unassigned"]))
    totalSources:=0;if(projectionOwner!=null) FinEnergyMath.strings(accounting["memberIds"]).each |id| {totalSources+=usage(id).sources.size}
    scratch?.hold(16+4*totalSources+2*((List)accounting["memberIds"]).size)
    outputHold(2+totalSources)
    strictTotal:=FinEnergyValue.sum(FinEnergyMath.strings(accounting["memberIds"]).map |id->FinEnergyValue| {usage(id)})
    remember(strictTotal.sources)
    knownTotal:=FinEnergyValue(FinEnergyMath.num(accounting["unionValue"]),accounting["unionQuality"].toStr)
    if (accounting["basis"] == "unavailable") strictTotal=FinEnergyValue(null,accounting["unionQuality"].toStr)
    outputHold(12);total:=Str:Obj?["id":category+"|"+unit,"categoryId":category,"unit":unit,"value":strictTotal.value,"quality":strictTotal.quality,"meterIds":accounting["memberIds"],"sourceIds":strictTotal.sources];remember(total)
    total.setAll(FinEnergyKnownUsage.fields(knownTotal))
    if (request["metric"] == "cost") total=costScopeTotal(roots.dup.addAll(FinEnergyMath.maps(plan["unassigned"])),accounting)
    outputHold(3);selection:=[total];remember(selection);overview["selectionTotals"]=selection
    outputHold(4);rows:=[Str:Obj?][,];series:=[Str:Obj?][,];remember(rows);remember(series)
    graphs.each |g|
    {
      FinEnergyMath.maps(g["nodes"]).each |n|
      {
        ctx.deadline?.check
        own:=FinEnergyMath.maps(overview["rows"]).find |r| {r["id"] == n["nodeId"]}
        rowCount:=n.size;if(own!=null) own.each |v,k| {if(!n.containsKey(k)) rowCount++}
        outputHold(3+rowCount);row:=n.dup;remember(row)
        if (own != null)
        {
          ["coverage","coveredSeconds","activeSeconds","complete","completeValue","completeQuality"].each |key| {n[key]=own[key]}
          row.setAll(own).set("id",n["id"]).set("graphId",g["graphId"])
        }
        rows.add(row)
        outputHold(22)
        point:=Str:Obj?["ts":from.toIso,"value":n["value"],"quality":n["quality"],"sourceIds":n["sourceIds"],"knownValue":n["knownValue"],"knownValueType":n["knownValueType"],"knownQuality":n["knownQuality"]]
        points:=[point];line:=Str:Obj?["id":n["id"],"nodeId":n["nodeId"],"graphId":g["graphId"],"name":n["name"],"categoryId":category,"unit":unit,"points":points]
        remember(point);remember(points);remember(line);series.add(line)
      }
    }
    flow:=compatible(graphs,roots,plan,total)
    outputHold(29+ctx.warnings.size+((List)plan["coveredScopes"]).size*5)
    warnings:=ctx.warnings.dup;summary:=Str:Obj?["value":total["value"],"unit":unit,"selectionTotals":[total]]
    extra:=Str:Obj?["energyFlow":flow,"energyFlowGraphs":graphs,"energyFlowAccounting":accounting,"energyFlowOverview":overview,"energyFlowCoveredScopes":plan["coveredScopes"],"selectionTotals":[total],"usageBasis":"knownUsage","knownUsage":overview["knownUsage"]]
    result:=Str:Obj?["kind":"energyFlow","from":from.toIso,"to":to.toIso,"period":request["period"] ?: "day","series":series,"rows":rows,"warnings":warnings,"summary":summary,"extra":costEvidence(extra)]
    remember(warnings);remember(summary);remember(extra);remember(result);remember(summary["selectionTotals"]);remember(extra["selectionTotals"]);remember(plan["coveredScopes"]);((List)plan["coveredScopes"]).each |row| {remember(row)}
    return result
    }
    finally {scratch?.close}
  }

  ** Reuse the physical-boundary resolver directly; this is not a leak report.
  private static Str:Obj? endUseScope(Str:Obj? req,FinEnergyDimension dim)
  {
    category:=req["categoryId"].toStr
    ids:=FinEnergyMath.strings(req["nodeIds"]).map |id->Str| {dim.canonical(id)}.unique
    if (ids.isEmpty) ids=dim.records.findAll |r| {meter(r) && r["kind"] == "totalMeter" && r["categoryId"] == category && r["meterParentId"] == null && included(r)}.map |r->Str| {r["id"].toStr}
    ids.each |id|
    {
      r:=dim.byId[id]
      if (r == null || !meter(r) || r["categoryId"] != category || r["_comparisonReadable"] == false)
        throw ArgErr("endUseMeterRequired")
    }
    if (ids.isEmpty) return ["roots":[Str:Obj?][,],"selected":[Str:Obj?][,],"unassigned":[Str:Obj?][,]]
    checked:=dim.records.map |r->[Str:Obj?]| {r["_flowBoundaryUnavailable"] == true ? r.dup.set("_comparisonUnavailable",true) : r}
    boundary:=FinEnergyComparisonScope(req.dup.set("nodeIds",ids),checked)
    own:=ids.dup.addAll(boundary.memberIds).unique
    return ["roots":ids.sort.map |id->[Str:Obj?]| {dim.byId[id]},"selected":dim.records.findAll |r| {own.contains(r["id"])},"unassigned":[Str:Obj?][,],"boundary":boundary]
  }

  private Str:Obj? endUseReport(Str:Obj? plan)
  {
    roots:=FinEnergyMath.maps(plan["roots"])
    boundary:=plan["boundary"] as FinEnergyComparisonScope
    ctx.comparison=boundary;knownCtx.comparison=boundary
    ownIds:=FinEnergyMath.maps(plan["selected"]).map |r->Str| {r["id"].toStr}.unique
    overviewRecords:=dim.records.map |r->[Str:Obj?]|
    {
      copy:=r.dup
      if (r["_comparisonReadable"] == false || r["_comparisonPointReadable"] == false) copy.remove("pointId")
      return copy
    }
    overview:=FinEnergyFlowOverview.build(request,overviewRecords,histories,ownIds)
    FinEnergyMath.maps(overview["rows"]).each |row|
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
      readings:=members.map |m->FinEnergyValue| {usage(m["id"].toStr)}
      observed:=members.map |m->FinEnergyValue| {knownUsage(m["id"].toStr)}
      overlap:=FinEnergyEndUse.overlap(ctx,members,readings)
      quality:=overlap ? "overlappingScopes" : (boundary.quality(id) ?: "ok")
      subtotal:=FinEnergyValue.sum(readings);knownSubtotal:=FinEnergyKnownUsage.combine(observed)
      if (members.isEmpty) {subtotal=FinEnergyValue(null,"missingBranches");knownSubtotal=FinEnergyValue(null,"missingBranches")}
      if (overlap) {subtotal=FinEnergyValue(null,quality,subtotal.sources);knownSubtotal=FinEnergyValue(null,quality,knownSubtotal.sources)}
      mode:=derived(root) ? "consistency" : FinEnergyBalance.mode(ctx,id)
      // Provenance shared by root and members is a consistency comparison.
      if (own.sources.any |source| {subtotal.sources.contains(source)}) mode="consistency"
      Float? difference:=quality == "ok" && good(own) && good(subtotal) ? own.value-subtotal.value : null
      if (difference != null && difference < 0f && difference.abs <= (own.value.abs+1f)*0.000000001f) difference=0f
      balanceQuality:=quality == "ok" ? FinEnergyValue.worse(own.quality,subtotal.quality) : quality
      if (difference != null && difference < 0f) balanceQuality="negativeBalance"
      negative:=own.quality == "negative" || known.quality == "negative" || readings.dup.addAll(observed).any |FinEnergyValue v->Bool| {v.quality == "negative" || (v.value != null && v.value < 0f)}
      knownOverflow:=nonnegative(known) && nonnegative(knownSubtotal) && knownSubtotal.value > known.value+(known.value.abs+1f)*0.000000001f
      weightedSafe:=quality == "ok" && !members.isEmpty && !negative && nonnegative(known) && observed.all |v| {nonnegative(v)} && nonnegative(knownSubtotal) && !knownOverflow
      if (negative) balanceQuality="negative"
      else if (knownOverflow) balanceQuality="negativeBalance"
      strictComplete:=good(own) && readings.all |v| {good(v)} && [id].dup.addAll(members.map |m->Str| {m["id"].toStr}).all |meterId| {FinEnergyMath.maps(overview["rows"]).find |r| {r["id"] == meterId}?.get("complete") == true}
      row:=base(id,id,ctx.displayName(id),"meter",null,own,known)
      row.setAll(["hasChildren":!members.isEmpty,"submeter":subtotal.value,"knownSubmeter":knownSubtotal.value,"knownSubmeterQuality":knownSubtotal.quality,"difference":difference,"balanceQuality":balanceQuality,"balanceMode":mode,"lossEligible":request["metric"] != "cost" && weightedSafe && strictComplete && FinEnergyBalance.eligible(mode,own,subtotal)])
      nodes.add(row)
      members.map |m->Str| {m["utilityId"] as Str ?: ""}.unique.sort.each |utility|
      {
        subset:=members.findAll |m| {(m["utilityId"] as Str ?: "") == utility}
        strict:=FinEnergyValue.sum(subset.map |m->FinEnergyValue| {usage(m["id"].toStr)})
        available:=FinEnergyKnownUsage.combine(subset.map |m->FinEnergyValue| {knownUsage(m["id"].toStr)})
        if (FinEnergyEndUse.overlap(ctx,subset,subset.map |m->FinEnergyValue| {usage(m["id"].toStr)}))
        {strict=FinEnergyValue(null,"overlappingScopes",strict.sources);available=FinEnergyValue(null,"overlappingScopes",available.sources)}
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
        residual:=FinEnergyValue(difference,balanceQuality,own.sources.dup.addAll(subtotal.sources).unique)
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
    graphs.each |g| {FinEnergyMath.strings(g["contributionMemberIds"]).each |id| {if (!owners.containsKey(id)) owners[id]=Str[,];owners[id].add(g["objectId"].toStr)}}
    memberIds:=owners.keys.sort
    for (i:=0;i<memberIds.size;i++) for (j:=i+1;j<memberIds.size;j++)
    {
      a:=memberIds[i];b:=memberIds[j]
      cross:=owners[a].any |root| {owners[b].any |other| {root != other}}
      if (cross && FinEnergyEndUse.overlap(ctx,[ctx.byId[a],ctx.byId[b]],[usage(a),usage(b)]))
      {
        combined:=owners[a].dup.addAll(owners[b]).unique
        owners[a]=combined;owners[b]=combined
      }
    }
    shared:=owners.keys.findAll |id| {owners[id].size > 1}.sort
    graphs.each |g| {g["sharedMemberIds"]=FinEnergyMath.strings(g["contributionMemberIds"]).findAll |id| {shared.contains(id)}}
    rootOverlap:=FinEnergyEndUse.overlap(ctx,roots,roots.map |r->FinEnergyValue| {usage(r["id"].toStr)})
    safe:=!graphs.isEmpty && shared.isEmpty && !rootOverlap && graphs.all |g| {g["additive"] == true && g["boundaryQuality"] == "ok"}
    strictTotal:=FinEnergyValue.sum(roots.map |r->FinEnergyValue| {usage(r["id"].toStr)})
    knownTotal:=FinEnergyKnownUsage.combine(roots.map |r->FinEnergyValue| {knownUsage(r["id"].toStr)})
    accountingQuality:=!shared.isEmpty || rootOverlap ? "overlappingScopes" : (graphs.find |g| {g["boundaryQuality"] != "ok"}?.get("boundaryQuality") as Str ?: "comparisonEmpty")
    if (!safe) {strictTotal=FinEnergyValue(null,accountingQuality,strictTotal.sources);knownTotal=FinEnergyValue(null,accountingQuality,knownTotal.sources)}
    branchUnion:=FinEnergyKnownUsage.combine(owners.keys.sort.map |id->FinEnergyValue| {knownUsage(id)})
    accounting:=Str:Obj?["canAdd":safe,"basis":safe ? "physicalBoundary" : "unavailable","memberIds":owners.keys.sort,"sharedMemberIds":shared,"sharedMembers":shared.map |id->[Str:Obj?]| {["meterId":id,"objectIds":owners[id]]},"unionValue":safe ? branchUnion.value : null,"unionQuality":safe ? branchUnion.quality : accountingQuality]
    total:=Str:Obj?["id":category+"|"+unit,"categoryId":category,"unit":unit,"value":strictTotal.value,"quality":strictTotal.quality,"meterIds":roots.map |r->Str| {r["id"].toStr},"sourceIds":strictTotal.sources]
    total.setAll(FinEnergyKnownUsage.fields(knownTotal))
    if (request["metric"] == "cost") total=costScopeTotal(roots,accounting)
    overview["selectionTotals"]=[total]
    rows:=[Str:Obj?][,];series:=[Str:Obj?][,]
    graphs.each |g|
    {
      FinEnergyMath.maps(g["nodes"]).each |n|
      {
        own:=FinEnergyMath.maps(overview["rows"]).find |r| {r["id"] == n["nodeId"]}
        if (own != null) ["coverage","coveredSeconds","activeSeconds","complete","completeValue","completeQuality"].each |key| {n[key]=own[key]}
        rows.add(n.dup)
        series.add(["id":g["graphId"].toStr+"|"+n["id"].toStr,"nodeId":n["nodeId"],"graphId":g["graphId"],"name":n["name"],"categoryId":category,"unit":unit,"points":[["ts":from.toIso,"value":n["value"],"quality":n["quality"],"sourceIds":n["sourceIds"],"knownValue":n["knownValue"],"knownValueType":n["knownValueType"],"knownQuality":n["knownQuality"]]]])
      }
    }
    return ["kind":"energyFlow","from":from.toIso,"to":to.toIso,"period":request["period"] ?: "day","series":series,"rows":rows,"warnings":ctx.warnings,
      "summary":["value":total["value"],"unit":unit,"selectionTotals":[total]],
      "extra":costEvidence(["energyFlow":compatible(graphs,roots,plan,total).set("basis","endUse"),"energyFlowGraphs":graphs,"energyFlowAccounting":accounting,"energyFlowOverview":overview,"selectionTotals":[total],"usageBasis":"knownUsage","knownUsage":overview["knownUsage"]])]
  }

  private Str:Obj? costEvidence(Str:Obj? extra)
  {
    if (request["metric"] != "cost") return extra
    tariffs:=ctx.usedTariffs.dup.setAll(knownCtx.usedTariffs)
    extra["tariffSnapshot"]=tariffs.keys.sort.map |id->[Str:Obj?]| {tariffs[id]}
    extra["costBasis"]="closedIntervalsAtStartTariff"
    return extra
  }

  ** Cost scope uses the same primary-meter frontier as other reports. Graph
  ** contribution references cannot replace, invalidate, or add to these readings.
  private Str:Obj? costScopeTotal([Str:Obj?][] roots,Str:Obj? accounting)
  {
    candidates:=roots.map |root->[Str:Obj?][]| {ctx.scopeMeters(root["id"].toStr,category)}.flatten
    meters:=ctx.selectionMeters(candidates)
    ids:=meters.map |m->Str| {m["id"].toStr}
    strict:=FinEnergyValue.sum(ids.map |id->FinEnergyValue| {usage(id)})
    known:=FinEnergyKnownUsage.combine(ids.map |id->FinEnergyValue| {knownUsage(id)})
    quality:=dim.quality(candidates.unique)
    if (quality != null)
    {
      strict=FinEnergyValue(null,quality,strict.sources)
      if (quality != "accountingIncomplete") known=FinEnergyValue(null,quality,known.sources)
    }
    accounting.setAll(["basis":"meterCostScope","memberIds":ids,"canAdd":quality == null && candidates.size == meters.size,"unionValue":known.value,"unionQuality":known.quality])
    total:=Str:Obj?["id":category+"|"+unit,"categoryId":category,"unit":unit,"value":strict.value,"quality":strict.quality,"scopeQuality":quality,"meterIds":ids,"sourceIds":strict.sources]
    return total.setAll(FinEnergyKnownUsage.fields(known))
  }

  private Void build(Str id,Str? parent,FinEnergyValue? parentValue,Str[] path,Bool grouping)
  {
    ctx.deadline?.check
    r:=ctx.byId[id]
    if (r == null || path.contains(id) || r["_comparisonReadable"] == false) return
    scratch:=workspace(32)
    try
    {
    occurrence:=nodes.any |n| {n["id"] == id} ? id+"|"+nodes.size : id
    value:=usage(id);known:=knownUsage(id)
    row:=base(occurrence,id,ctx.displayName(id),dim.scope(id) ? dim.dimension : "meter",parent,value,known)
    row["percentage"]=calculationGraph ? null : percentage(value,parentValue);outputHold(1);nodes.add(row)
    vars:=ctx.byId[r["expressionId"] as Str ?: ""]?.get("variables") as Map
    childBound:=0
    if(projectionOwner!=null)
    {
      if(grouping && dim.scope(id)) dim.records.each |n| {if(dim.scope(n["id"].toStr) && n["parentId"]==id) childBound++;if(allowed.contains(n["id"].toStr) && membership(n)==id) childBound++}
      else if(r["expressionId"]!=null) childBound=vars?.size ?: 0
      else dim.records.each |n| {if(included(n) && n["meterParentId"]==id) childBound++}
    }
    scratch?.hold(20+8*childBound)
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
        expr:=ctx.byId[r["expressionId"].toStr];references:=expr?.get("variables") as Map
        if (expr?.get("_comparisonReadable") != false && references != null) children.addAll(references.vals.map |ref->Str| {ref?.toStr ?: ""})
      }
      else children.addAll(dim.directChildren(id).map |n->Str| {n["id"].toStr})
    }
    children=children.unique.findAll |child| {c:=ctx.byId[child];return c != null && !path.contains(child) && child != id && c["_comparisonReadable"] != false && (dim.scope(child) || (meter(c) && c["categoryId"] == category && allowed.contains(child)))}.sort
    row["hasChildren"]=!children.isEmpty
    groupingBoundaries:=Str:Str[][:]
    if (grouping) children.each |child| {groupingBoundaries[child]=groupingMembers(child,scratch)}
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
    inputSafe:=relation != "calculation" || contribution(id,Str[,],scratch)["additive"] == true
    sourceBound:=0;if(projectionOwner!=null) displayed.each |child| {sourceBound+=usage(child).sources.size+knownUsage(child).sources.size}
    scratch?.hold(32+8*sourceBound+2*displayed.size)
    subtotal:=inputSafe ? FinEnergyValue.sum(displayed.map |child->FinEnergyValue| {usage(child)}) : FinEnergyValue(null,"comparisonNonAdditive")
    knownSubtotal:=inputSafe ? FinEnergyKnownUsage.combine(displayed.map |child->FinEnergyValue| {knownUsage(child)}) : FinEnergyValue(null,"comparisonNonAdditive")
    mode:=grouping ? "consistency" : FinEnergyBalance.mode(ctx,id)
    quality:=FinEnergyValue.worse(value.quality,subtotal.quality)
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
        scratch?.hold(members.size);seenMembers.addAll(members)
      }
      if (!distributionSafe) quality="overlappingScopes"
      distributionSafe=distributionSafe && known.value != null && known.value >= 0f && knownSubtotal.value != null && knownSubtotal.value >= 0f && knownSubtotal.value <= known.value+(known.value.abs+1f)*0.000000001f && displayed.all |child| {v:=knownUsage(child);return v.value != null && v.value >= 0f}
      row["distributionComparable"]=distributionSafe
    }
    if (difference != null && difference < 0f && difference.abs <= (value.value.abs+1f)*0.000000001f) difference=0f
    if (difference != null && difference < 0f) {quality="negativeBalance";ctx.warn(ctx.displayName(id)+": 分表合计大于总表，差额为负，请核对计量关系与数据")}
    row["submeter"]=subtotal.value;row["knownSubmeter"]=knownSubtotal.value;row["knownSubmeterQuality"]=knownSubtotal.quality;row["difference"]=difference;row["balanceQuality"]=quality
    row["balanceMode"]=mode;row["lossEligible"]=request["metric"] != "cost" && !grouping && ["ok","estimated","derived","cleaned","corrected"].contains(quality) && FinEnergyBalance.eligible(mode,value,subtotal)
    children.each |child|
    {
      before:=nodes.size
      childPath:=workspace(2+path.size+1)
      try {build(child,occurrence,value,path.dup.add(id),grouping)}
      finally {childPath?.close}
      if (nodes.size == before) return
      target:=nodes[before]["id"].toStr;amount:=knownUsage(child)
      if (suppressed.contains(child)) {nodes[before]["percentage"]=null;if (grouping) nodes[before]["referenceOnly"]=true}
      if (grouping && !distributionSafe) nodes[before]["percentage"]=null
      if (!suppressed.contains(child) && distributionSafe && amount.value != null && amount.value > 0f) addLink(occurrence,target,amount,known,relation)
    }
    if (difference != null && difference > 0f && good(value) && good(subtotal))
    {
      sourceCount:=value.sources.size+subtotal.sources.size
      scratch?.hold(8+3*sourceCount);outputHold(2+sourceCount)
      diffId:="__energyFlowDifference__:$occurrence";v:=FinEnergyValue(difference,quality,value.sources.dup.addAll(subtotal.sources).unique);remember(v.sources)
      gap:=base(diffId,diffId,"","difference",occurrence,v,v);gap["percentage"]=percentage(v,value);gap["balanceMode"]=mode;gap["lossEligible"]=row["lossEligible"]
      outputHold(1);nodes.add(gap);addLink(occurrence,diffId,v,value,"metering")
    }
    }
    finally {scratch?.close}
  }

  private Str[] groupingMembers(Str id,FinEnergyPreparedOwner? target := null)
  {
    if (dim.scope(id)) {boundary:=boundaries(id,target);target?.hold(2+2*((List)boundary["members"]).size);return FinEnergyMath.strings(boundary["members"])}
    target?.hold(2)
    r:=ctx.byId[id]
    return r == null ? Str[,] : [derived(r) ? id : physicalId(r)]
  }

  private Str:Obj? boundaries(Str id,FinEnergyPreparedOwner? target := null)
  {
    scratch:=workspace(32+8*dim.records.size)
    try
    {
    frontier:=dim.frontier(dim.members(id).findAll |r| {r["categoryId"] == category})
    target?.hold(6+frontier.size)
    members:=frontier.map |r->Str| {derived(r) ? r["id"].toStr : physicalId(r)}.unique.sort
    return ["members":members,"additive":members.all |m| {!derived(ctx.byId[m])},"quality":ctx.byId[id]?.get("_flowBoundaryUnavailable") == true ? "comparisonUnavailable" : (dim.quality(dim.members(id)) ?: "ok")]
    }
    finally {scratch?.close}
  }

  ** This describes contributions; it never evaluates or changes the formula.
  private Str:Obj? contribution(Str id,Str[] path,FinEnergyPreparedOwner? target := null)
  {
    ctx.deadline?.check
    target?.hold(6)
    r:=ctx.byId[id]
    if (r == null || !meter(r) || path.contains(id) || r["_flowBoundaryUnavailable"] == true || r["_comparisonReadable"] == false || r["_comparisonPointReadable"] == false || r["categoryId"] != category || FinEnergyMath.unitFactor(r["unit"] as Str ?: unit,unit) == null)
      return ["members":Str[,],"additive":false,"quality":"comparisonUnresolved"]
    if (!derived(r)) {target?.hold(1);return ["members":[physicalId(r)],"additive":true,"quality":"ok"]}
    scratch:=workspace(32+path.size)
    try
    {
    expr:=ctx.byId[r["expressionId"]?.toStr ?: ""]
    childCount:=0;if(projectionOwner!=null) dim.records.each |c| {if(included(c) && c["meterParentId"]==id) childCount++}
    scratch?.hold(8+3*(expr?.get("formula")?.toStr?.size ?: 0)+2*childCount)
    refs:=r["expressionId"] != null ? FinEnergyComparisonScope.additive(expr) : dim.directChildren(id).map |c->Str| {c["id"].toStr}
    if (refs == null || refs.isEmpty) return ["members":Str[,],"additive":false,"quality":"comparisonNonAdditive"]
    members:=Str[,];complete:=true
    refs.each |ref|
    {
      scratch?.hold(2+path.size+1)
      c:=contribution(ref,path.dup.add(id),scratch)
      scratch?.hold(2+3*((List)c["members"]).size);child:=FinEnergyMath.strings(c["members"])
      if (c["additive"] != true || child.any |m| {members.contains(m)}) complete=false
      members.addAll(child)
    }
    target?.hold(members.size)
    return ["members":members.unique.sort,"additive":complete,"quality":complete ? "ok" : "comparisonUnresolved"]
    }
    finally {scratch?.close}
  }

  private Str:Obj? account([Str:Obj?][] graphs,[Str:Obj?][] unassigned)
  {
    associations:=0;graphs.each |g| {associations+=((List)g["contributionMemberIds"]).size}
    scratch:=workspace(48+12*associations+4*dim.records.size)
    try
    {
    owners:=Str:Str[][:]
    graphs.each |g| {FinEnergyMath.strings(g["contributionMemberIds"]).each |id| {if (!owners.containsKey(id)) owners[id]=Str[,];owners[id].add(g["objectId"].toStr)}}
    shared:=owners.keys.findAll |id| {owners[id].size > 1}.sort
    graphs.each |g| {outputHold(2+((List)g["contributionMemberIds"]).size);ids:=FinEnergyMath.strings(g["contributionMemberIds"]).findAll |id| {shared.contains(id)};remember(ids);g["sharedMemberIds"]=ids}
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
    known:=FinEnergyKnownUsage.combine(members.map |id->FinEnergyValue| {knownUsage(id)})
    outputHold(15+members.size+2*shared.size+associations+6*shared.size)
    sharedMembers:=shared.map |id->[Str:Obj?]|
    {
      ids:=owners[id].dup;row:=Str:Obj?["meterId":id,"objectIds":ids];remember(ids);remember(row);return row
    }
    result:=Str:Obj?["canAdd":safe && shared.isEmpty && !contains,"memberIds":members,"sharedMemberIds":shared,"sharedMembers":sharedMembers,"unionValue":safe ? known.value : null,"unionQuality":safe ? known.quality : (!unassigned.isEmpty ? "topologyIncomplete" : (topo ?: "overlappingScopes")),"basis":safe ? (allVirtual ? "classificationUnion" : "physicalBoundary") : "unavailable"]
    remember(members);remember(shared);remember(sharedMembers);remember(result);return result
    }
    finally {scratch?.close}
  }

  private Str:Obj? compatible([Str:Obj?][] graphs,[Str:Obj?][] roots,Str:Obj? plan,Str:Obj? total)
  {
    if (graphs.size == 1) return graphs.first
    nodeCount:=0;linkCount:=0;graphs.each |g| {nodeCount+=((List)g["nodes"]).size;linkCount+=((List)g["links"]).size}
    scratch:=workspace(32+3*(nodeCount+linkCount)+2*((List)plan["unassigned"]).size+2*((List)total["sourceIds"]).size)
    try
    {
    summaryId:="__energyFlow__:$category"
    outputHold(2+((List)total["sourceIds"]).size)
    v:=FinEnergyValue(FinEnergyMath.num(total["value"]),total["quality"].toStr,FinEnergyMath.strings(total["sourceIds"]))
    remember(v.sources)
    summary:=base(summaryId,summaryId,ctx.byId[category]?.get("name")?.toStr ?: category,"summary",null,v,FinEnergyValue(FinEnergyMath.num(total["knownValue"]),total["knownQuality"].toStr))
    outputHold(5+nodeCount+linkCount);ns:=[summary];ls:=[Str:Obj?][,];remember(ns);remember(ls)
    graphs.each |g|
    {
      ns.addAll(FinEnergyMath.maps(g["nodes"]));ls.addAll(FinEnergyMath.maps(g["links"]))
      root:=FinEnergyMath.maps(g["nodes"]).first
      if (good(v) && root != null && FinEnergyMath.num(root["knownValue"]) != null && (Float)root["knownValue"] > 0f)
      {
        outputHold(10);link:=Str:Obj?["source":summaryId,"target":root["id"],"value":root["knownValue"],"quality":root["knownQuality"],"relationKind":"metering","sourceIds":root["sourceIds"],"percentage":null];remember(link);ls.add(link)
      }
    }
    outputHold(2+((List)plan["unassigned"]).size)
    unassigned:=FinEnergyMath.maps(plan["unassigned"]).map |r->[Str:Obj?]| {id:=r["id"].toStr;return base(id,id,ctx.displayName(id),"meter",null,usage(id),knownUsage(id))}
    outputHold(11+roots.size);rootIds:=roots.map |r->Str| {r["id"].toStr};result:=Str:Obj?["categoryId":category,"unit":unit,"focusId":summaryId,"rootIds":rootIds,"nodes":ns,"links":ls,"unassigned":unassigned]
    remember(unassigned);remember(rootIds);remember(result);return result
    }
    finally {scratch?.close}
  }

  private Str:Obj? base(Str occurrence,Str id,Str name,Str type,Str? parent,FinEnergyValue value,FinEnergyValue known)
  {
    // Includes fields subsequently attached by build and the own-history row.
    outputHold(38)
    row:=Str:Obj?["id":occurrence,"nodeId":id,"graphId":graphId,"name":name,"nodeType":type,"categoryId":category,"unit":unit,"value":value.value,"quality":value.quality,"sourceIds":value.sources,"submeter":null,"difference":null,"balanceQuality":value.quality,"hasChildren":false,"percentage":null]
    row.setAll(FinEnergyKnownUsage.fields(known));if (parent != null) row["parentId"]=parent
    remember(row);return row
  }

  private FinEnergyValue usage(Str id) {read(id,false)}
  private FinEnergyValue knownUsage(Str id) {read(id,true)}
  private FinEnergyValue read(Str id,Bool known)
  {
    ctx.deadline?.check
    cache:=known ? knownValues : values
    if (cache.containsKey(id)) return cache[id]
    if (request["flowMode"] == "endUse" && (ctx.byId[id]?.get("_comparisonReadable") == false || ctx.byId[id]?.get("_comparisonPointReadable") == false)) return FinEnergyValue(null,"forbidden")
    if (dim.scope(id))
    {
      scratch:=workspace(32+6*dim.records.size)
      try
      {
      pieces:=FinEnergyMath.strings(boundaries(id,scratch)["members"]).map |m->FinEnergyValue| {read(m,known)}
      sourceCount:=0;pieces.each |FinEnergyValue v| {sourceCount+=v.sources.size}
      scratch?.hold(16+4*sourceCount);outputHold(2+sourceCount)
      value:=known ? FinEnergyKnownUsage.combine(pieces) : FinEnergyValue.sum(pieces)
      projectionState?.hold(7);remember(value.sources)
      cache[id]=value;return value
      }
      finally {scratch?.close}
    }
    value:=FinEnergyValue()
    if(preparedValue!=null) value=preparedValue(id,known)
    else
    {
      values:=known ? FinEnergyValueFold.known : FinEnergyValueFold.strict
      cursor:=from
      while (cursor < to)
      {
        end:=FinEnergyMath.floorHour(cursor)+1hr;if (end > to) end=to
        values.add((known ? knownCtx : ctx).node(id,category,cursor,end,request["metric"] as Str ?: "energy"));cursor=end
      }
      value=values.finish
    }
    if (!known && request["flowMode"] == "endUse" && value.value == null && value.quality == "missing" && knownUsage(id).quality == "na") value=FinEnergyValue(null,"na",value.sources)
    if (value.value != null && value.value < 0f) {projectionState?.hold(6);value=FinEnergyValue(value.value,"negative",value.sources)}
    projectionState?.hold(1)
    cache[id]=value;return value
  }

  private Void addLink(Str source,Str target,FinEnergyValue value,FinEnergyValue? parent,Str relation)
  {outputHold(10);link:=Str:Obj?["source":source,"target":target,"value":value.value,"quality":value.quality,"sourceIds":value.sources,"percentage":relation == "calculation" ? null : percentage(value,parent),"relationKind":relation];remember(link);links.add(link)}
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
    count:=0;if(projectionOwner!=null) dim.records.each |m| {if(meter(m) && !derived(m) && m["categoryId"]==category && m["pointId"]==point && m["_comparisonReadable"]!=false) count++}
    scratch:=workspace(4+3*count)
    try
    {
    matches:=dim.records.findAll |m| {meter(m) && !derived(m) && m["categoryId"] == category && m["pointId"] == point && m["_comparisonReadable"] != false}
    return matches.map |m->Str| {m["id"].toStr}.sort.first ?: r["id"].toStr
    }
    finally {scratch?.close}
  }
  private Bool ancestor(Str parent,Str child)
  {
    scratch:=workspace(4)
    try
    {
    seen:=Str[,];cursor:=ctx.byId[child]?.get("meterParentId") as Str
    while (cursor != null && !seen.contains(cursor))
    {
      if (cursor == parent) return true
      ctx.deadline?.check;scratch?.hold(1);seen.add(cursor);cursor=ctx.byId[cursor]?.get("meterParentId") as Str
    }
    return false
    }
    finally {scratch?.close}
  }
  private Bool validChain(Str id)
  {
    scratch:=workspace(4)
    try
    {
    seen:=Str[,];cursor:=id
    while (!seen.contains(cursor))
    {
      ctx.deadline?.check;scratch?.hold(1);seen.add(cursor);r:=ctx.byId[cursor]
      if (r == null || !meter(r) || r["categoryId"] != category) return false
      parent:=r["meterParentId"] as Str
      if (parent == null) return true
      cursor=parent
    }
    return false
    }
    finally {scratch?.close}
  }
  private static Bool derived(Str:Obj? r) {r["autoSum"] == true || r["expressionId"] != null || (r["meterOrigin"] as Map)?.get("type") == "virtual"}
  private static Bool meter(Str:Obj? r) {["meter","totalMeter"].contains(r["kind"])}
  private static Bool included(Str:Obj? r) {meter(r) && ((Bool?)r["includeInTotals"] ?: (r["expressionId"] == null))}
  private static Bool excludedAncestor(Str:Obj? r,FinEnergyDimension dim)
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
  private static Bool good(FinEnergyValue? v) {v?.value != null && v.value >= 0f && ["ok","estimated","derived","cleaned","corrected"].contains(v.quality)}
  private static Bool nonnegative(FinEnergyValue v) {FinEnergyMath.num(v.value) != null && v.value >= 0f}
  private static Float? percentage(FinEnergyValue v,FinEnergyValue? parent) {good(v) && good(parent) && v.value > 0f && parent.value > 0f ? v.value/parent.value*100f : null}
}

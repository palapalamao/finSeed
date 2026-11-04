** Private metadata-first report registry. This seam deliberately refuses modules
** whose bounded adapters are not yet installed; it never falls back to a whole
** history report. All work shares one source clock and one diagnostic row pool.
internal class EnerCubixCockpitRegistry
{
  new make(Str:Obj? q,[Str:Obj?][] records,Str:Obj? boundary,Str[] enabled,Str:Obj? comparison,Str? auxiliary,Str:Obj? owned,EnerCubixStreamBudget budget,Str:Str units,Str[] loadedPoints,Str:[Str:Obj?] cleaningPlan := [:],Str:Obj? flowPlan := [:],Str:Obj? efficiencyPlan := [:],EnerCubixCockpitCatalog? sharedCatalog := null)
  {
    this.budget=budget
    model=EnerCubixPreparedOwner(budget.state);metadata=EnerCubixPreparedOwner(budget.state);diagnosticOwner=EnerCubixPreparedOwner(budget.state)
    generation:=EnerCubixPreparedOwner(budget.state)
    flowEnabled:=enabled.contains("balance") && flowPlan["error"]!=true
    copEnabled:=enabled.contains("efficiency") && efficiencyPlan["error"]!=true
    try
    {
      generation.hold(64+2*(q.size+8))
      if(!q.isImmutable || !records.isImmutable || !boundary.isImmutable || enabled.any |id| {!["kpis","trend","space","time","endUse","organization","balance","efficiency","issues"].contains(id)}) throw ArgErr("cockpitRegistryPlan")
      if(enabled.contains("issues") && !owned.isImmutable) throw ArgErr("cockpitRegistryRulePlan")
      if(enabled.contains("balance") && (!flowPlan.isImmutable || (flowEnabled && (flowPlan["canonicalRecords"] isnot List || flowPlan["request"] isnot Map)))) throw ArgErr("cockpitRegistryFlowPlan")
      if(enabled.contains("efficiency") && (!efficiencyPlan.isImmutable || (copEnabled && (efficiencyPlan["records"] isnot List || efficiencyPlan["request"] isnot Map || efficiencyPlan["items"] isnot List)))) throw ArgErr("cockpitRegistryCopPlan")
      metadata.watch |->Void| {works.clear;queries.each |v| {v.clear};queries.clear;space.clear;currentPoints.clear;tariffs.clear;billing.clear;attachedCleaning.clear;flowMeters.clear;flowPeriods.clear;copWorks.clear;copKeys.clear;ruleWorks.clear;diagnostics=Str:Obj?[:];planning=null;flowCatalog=null;copCatalog=null}
      metadata.hold(32+loadedPoints.size);currentPoints=loadedPoints.dup
      if(sharedCatalog!=null && (sharedCatalog.owner.budget!==budget.state || sharedCatalog.tz!=TimeZone(q["tz"].toStr))) throw ArgErr("cockpitRegistryCatalog")
      catalog=sharedCatalog ?: EnerCubixCockpitCatalog(records,TimeZone(q["tz"].toStr),model,units)
      planning=EnerCubixContext.shared(catalog,q["dimension"].toStr,q["spaceSource"]=="fin",metadata)
      if(flowEnabled)
      {
        fq:=(Str:Obj?)flowPlan["request"]
        if(["from","to","asOf","tz","dimension"].any |key| {fq[key]!=q[key]} || fq["kind"]!="energyFlow" || fq["metric"]!="energy" || fq["categoryId"]!=q["_cockpitCategoryId"]) throw ArgErr("cockpitRegistryFlowPlan")
        flowModel=EnerCubixPreparedOwner(budget.state)
        proposed:=EnerCubixCockpitCatalog(([Str:Obj?][])flowPlan["canonicalRecords"],catalog.tz,flowModel,units)
        // ACL boundary markers or inferred aliases require a distinct model.
        if(same(proposed.records,catalog.records)) {flowModel.close;flowModel=null;flowCatalog=catalog}
        else flowCatalog=proposed
        scratch:=EnerCubixPreparedOwner(budget.state)
        try
        {
          scope:=EnerCubixEnergyFlow.scope(fq,flowCatalog.view(fq["dimension"].toStr,fq["spaceSource"]=="fin"),scratch)
          scratch.hold(8+8*flowCatalog.records.size)
          meters:=EnerCubixMath.maps(scope["selected"]).dup.addAll(EnerCubixMath.maps(scope["unassigned"])).unique
          metadata.hold(1+4*meters.size);flowMeters=meters.dup
          meters.each |m| {id:=m["id"].toStr;flowPeriods[id]="flow-period|"+id}
        }
        finally {scratch.close}
        add("energy-flow",fq)
      }
      if(copEnabled)
      {
        cq:=(Str:Obj?)efficiencyPlan["request"]
        if(["from","to","asOf","tz","dimension"].any |key| {cq[key]!=q[key]} || ((List)efficiencyPlan["items"]).size>20) throw ArgErr("cockpitRegistryCopPlan")
        generation.hold(4+2*((List)efficiencyPlan["items"]).size)
        items:=EnerCubixMath.maps(efficiencyPlan["items"])
        if(!items.isEmpty)
        {
          copModel=EnerCubixPreparedOwner(budget.state)
          proposed:=EnerCubixCockpitCatalog(([Str:Obj?][])efficiencyPlan["records"],catalog.tz,copModel,units,true)
          if(same(proposed.records,catalog.records)) {copModel.close;copModel=null;copCatalog=catalog}
          else copCatalog=proposed
          metadata.hold(2+2*items.size);copKeys=items.map |item->Str| {((Map)item["config"])["id"].toStr}.sort
          if(copKeys.unique.size!=items.size) throw ArgErr("cockpitRegistryCopPlan")
          items.each |item|
          {id:=((Map)item["config"])["id"].toStr;metadata.hold(20);copWorks[id]=EnerCubixCockpitCopWork(cq,item,copCatalog,budget);add("cop:"+id,EnerCubixCockpitReports.copQuery(cq,id))}
        }
      }
      if(enabled.contains("issues") && owned["rulesComplete"]!=false)
      {
        generation.hold(2+((owned["rules"] as List)?.size ?: 0))
        EnerCubixMath.maps(owned["rules"]).each |profile|
        {
          threshold:=EnerCubixMath.num(profile["threshold"])
          if(profile["ruleType"]!="nonWorkingHighUsage" || profile["enabled"]!=true || profile["validation"]=="invalid" || profile["categoryRef"]!=q["_cockpitCategoryId"] || threshold==null || threshold<0f) return
          id:=profile["id"].toStr
          if(ruleWorks.containsKey(id)) throw ArgErr("cockpitRegistryRulePlan")
          metadata.hold(12);ruleWorks[id]=EnerCubixCockpitRuleWork(q,profile,records,boundary,catalog,budget)
        }
      }
      add("profile-energy",q)
      if(enabled.contains("kpis"))
      {
        metrics(q,"",auxiliary)
        if(comparison["mode"]!="none")
        {
          reference:=q.dup.setAll((Map)comparison["referenceRange"])
          add("reference-profile-energy",reference);metrics(reference,"reference-",auxiliary)
        }
      }
      if((enabled.contains("kpis") || enabled.contains("issues")) && !EnerCubixMath.maps(owned["budgets"]).isEmpty) add("budget-canonical-cost",EnerCubixCockpitReports.budgetQuery(q,boundary))
      if(enabled.any |id| {["time","endUse","organization"].contains(id)})
      {
        add("face-meter-profile",EnerCubixCockpitReports.faceQuery(q,boundary,"face-meter-profile"))
        if(enabled.contains("endUse")) add("face-endUse",EnerCubixCockpitReports.faceQuery(q,boundary,"face-endUse"))
        if(enabled.contains("time"))
        {
          add("face-daily",EnerCubixCockpitReports.faceQuery(q,boundary,"face-daily"))
          add("face-heatmap",EnerCubixCockpitReports.faceQuery(q,boundary,"face-heatmap"))
          ["workingHours","workingDays"].each |kind|
          {if(planning.calendar?.get(kind=="workingHours" ? "workHours" : "workDays") is List) add("face-"+kind,EnerCubixCockpitReports.faceQuery(q,boundary,"face-"+kind))}
        }
      }
      if(enabled.contains("space"))
      {
        // Bound temporary candidate/ancestor/member vectors before resolving
        // them; only the detached scope table remains under metadata ownership.
        scratch:=EnerCubixPreparedOwner(budget.state)
        try
        {
          scratch.hold(32+8*records.size)
          sourceCtx:=EnerCubixContext.shared(catalog,q["dimension"].toStr,true,metadata)
          spaceCtx:=EnerCubixContext.shared(catalog,"space",true,metadata)
          space=EnerCubixCockpitSpace.prepare(q,records,currentPoints,currentPoints,sourceCtx,spaceCtx,metadata)
          if(!((Map)space["query"]).isEmpty) add("space-summary",(Str:Obj?)space["query"])
        }
        finally {scratch.close}
      }
      if(queries.any |query| {query["metric"]=="cost"}) catalog.records.each |record|
      {
        if(!["meter","totalMeter"].contains(record["kind"]) || record["categoryId"]!=q["_cockpitCategoryId"]) return
        if(!["monthlyBlock","yearlyBlock"].contains(planning.tariff(record)?.get("mode") as Str ?: "")) return
        metadata.hold(1);billing.add(record)
      }
      scratch:=EnerCubixPreparedOwner(budget.state)
      try
      {
      scratch.hold(32+queries.size*(20+records.size)+cleaningPlan.size)
      spec:=Str:[Str:Obj?][:]
      queries.each |query,key|
      {
        if(key=="face-heatmap" || key=="space-summary" || query["kind"]=="cop") return
        spec[key]=["kind":"sourceUsage","grain":"sourceRead","objectIds":query["nodeIds"],"sourceIds":sources(query),"sourceIdsComplete":true,"requestRange":["from":query["from"],"to":query["to"],"asOf":query["asOf"]],"reportRefs":[key]]
      }
      cleaningPlan.each |entry,key|
      {
        if(entry["kind"]!="cleaningEvents" || entry["requestRange"] isnot Map) throw ArgErr("cockpitRegistryCleaningPlan")
        scratch.hold(8+entry.size+3*queries.size)
        range:=(Map)entry["requestRange"];a:=DateTime.fromIso(range["from"].toStr);b:=DateTime.fromIso(range["to"].toStr)
        refs:=queries.keys.findAll |ref|
        {query:=queries[ref];return ref!="face-heatmap" && ref!="space-summary" && query["kind"]!="cop" && DateTime.fromIso(query["from"].toStr)<b && DateTime.fromIso(query["to"].toStr)>a}
        spec[key]=entry.dup.set("reportRefs",refs.sort)
      }
      scratch.hold(24+20*flowMeters.size)
      flowMeters.each |m|
      {id:=m["id"].toStr;point:=m["pointId"] as Str;spec[flowPeriods[id]]=["kind":"coveragePeriods","grain":"hour","objectIds":[id],"sourceIds":point==null ? Str[,] : [point],"sourceIdsComplete":true,"requestRange":["from":q["from"],"to":q["to"],"asOf":q["asOf"]],"reportRefs":["energy-flow"]]}
      // Descriptors are cloned/charged by Capture; construction scratch expires.
      pool=EnerCubixCockpitCapture(spec,diagnosticOwner)
      }
      finally {scratch.close}
      if(budget.diagnosticCapture!=null) throw ArgErr("cockpitRegistryDiagnosticPool")
      budget.diagnosticCapture=pool
      metadata.hold(cleaningPlan.size);cleaningKeys=cleaningPlan.keys
      queries.each |query,key| {if(key=="energy-flow" || query["kind"]=="cop") return;metadata.hold(22);works[key]=EnerCubixCockpitReportWork(key,query,catalog,budget,pool,tariffs)}
      if(flowEnabled) {metadata.hold(22);flowWork=EnerCubixCockpitFlowWork((Str:Obj?)flowPlan["request"],flowCatalog,budget,pool,flowPeriods,flowMeters)}
    }
    catch(Err e) {close;throw e}
    finally {generation.close}
  }
  private EnerCubixStreamBudget budget
  private EnerCubixPreparedOwner model
  private EnerCubixPreparedOwner metadata
  private EnerCubixPreparedOwner diagnosticOwner
  private EnerCubixCockpitCatalog? catalog
  private EnerCubixPreparedOwner? flowModel
  private EnerCubixCockpitCatalog? flowCatalog
  private EnerCubixCockpitFlowWork? flowWork
  private EnerCubixPreparedOwner? copModel
  private EnerCubixCockpitCatalog? copCatalog
  private Str:EnerCubixCockpitCopWork copWorks := [:]
  private Str[] copKeys := [,]
  private Str:EnerCubixCockpitRuleWork ruleWorks := [:]
  private [Str:Obj?][] flowMeters := [,]
  private Str:Str flowPeriods := [:]
  private EnerCubixCockpitCapture? pool
  internal EnerCubixContext? planning {private set}
  private Str:Str:Obj? queries := [:]
  private Str:EnerCubixCockpitReportWork works := [:]
  private Str:EnerCubixTariffCursor tariffs := [:]
  private [Str:Obj?][] billing := [,]
  internal Str:Obj? space := [:] {private set}
  internal Str:Obj? diagnostics := [:] {private set}
  private Str[] cleaningKeys := [,]
  private Str[] currentPoints := [,]
  private Str:Bool attachedCleaning := [:]
  private Bool done := false
  private Bool closed := false
  private Bool planningRetired := false
  private Bool closing := false
  private DateTime? watermark
  private Err? failure
  Str[] keys() {check;return queries.keys}
  Str:Obj? publishDiagnostics(Str:Obj? reports)
  {check;if(!done) throw ArgErr("cockpitRegistryReportNotPrepared");return pool.publish(reports)}

  private Void metrics(Str:Obj? q,Str prefix,Str? auxiliary)
  {["cost","co2",auxiliary==null ? "area" : "auxiliary"].each |id| {add(prefix+"profile-"+id,EnerCubixCockpitReports.metricQuery(q,id,auxiliary))}}
  private Void add(Str key,Str:Obj? q)
  {metadata.hold(34+q.size);queries[key]=q.dup}
  private Str[] sources(Str:Obj? q)
  {
    if(q["kind"]=="energyFlow") return flowMeters.map |m->Str| {m["pointId"] as Str ?: ""}.findAll |Str id->Bool| {!id.isEmpty}.unique.sort
    ctx:=EnerCubixContext.shared(catalog,q["dimension"].toStr,q["spaceSource"]=="fin",metadata)
    out:=Str[,]
    EnerCubixMath.strings(ctx.dimension.normalizeRequest(q)["nodeIds"]).each |id| {ctx.categories(id).each |category| {if(q["_cockpitCategoryId"]!=null && q["_cockpitCategoryId"]!=category) return;ctx.scopeMeters(id,category).each |m| {point:=m["pointId"] as Str;if(point!=null && !out.contains(point)) out.add(point)}}}
    return out.sort
  }

  ** a/b describe one real, aligned producer frame. Query cuts may be partial;
  ** prefix-only source hours do not fabricate report points or diagnostics.
  Void addFrame(DateTime a,DateTime b,Str:EnerCubixHistoryData histories,EnerCubixPreparedOwner frame)
  {
    check
    if(done || frame.budget!==budget.state || a!=EnerCubixMath.floorHour(a) || b!=a+1hr || (watermark!=null && a<watermark)) throw ArgErr("cockpitRegistryFrame")
    try
    {
      // The preceding producer frame has expired. Finish an elapsed reference
      // period before opening current-period state; its output remains owned.
      works.each |work| {work.finishReady}
      flowWork?.finishReady
      planning.beginFrame(frame,histories)
      billing.each |record|
      {
        id:=record["id"].toStr
        if(!["meter","totalMeter"].contains(record["kind"]) || record["categoryId"]!=queries["profile-energy"]["_cockpitCategoryId"] || !histories.containsKey(record["pointId"] as Str ?: "")) return
        mode:=planning.tariff(record)?.get("mode") as Str
        if(!["monthlyBlock","yearlyBlock"].contains(mode)) return
        if(!tariffs.containsKey(id))
        {
          cycle:=EnerCubixMath.bucket(a,mode=="monthlyBlock" ? "month" : "year")
          if(a!=cycle) throw ArgErr("cockpitRegistryTariffPrefix")
          metadata.hold(1);tariffs[id]=EnerCubixTariffCursor(planning,id,cycle,metadata)
        }
        tariffs[id].align(a)
      }
      // Source readers remain borrowed from the producer's outer frame. Each
      // consumer's derived caches expire as soon as its folds have copied the
      // hour, before the next consumer opens. Persistent reductions and output
      // keep their own owners; this never releases source or peer ownership.
      works.each |work| {withConsumerFrame |local| {work.addFrame(a,b,histories,local)}}
      if(flowWork!=null) withConsumerFrame |local| {flowWork.addFrame(a,b,histories,local)}
      copWorks.each |work| {withConsumerFrame |local| {work.addFrame(a,b,histories,local)}}
      ruleWorks.each |work| {withConsumerFrame |local| {work.addFrame(a,b,histories,local)}}
      tariffs.each |cursor,id| {if(histories.containsKey(catalog.byId[id]["pointId"] as Str ?: "")) cursor.consumeHour}
      watermark=b
    }
    catch(Err e) {failure=e;throw e}
  }
  Void prepareMetadata()
  {check;works.each |work| {work.prepareMetadata}}
  Bool canGroupEmpty() {check;return billing.isEmpty}
  Void addEmptyFrames(DateTime a,DateTime b,Str:EnerCubixHistoryData histories,EnerCubixPreparedOwner frame)
  {
    check
    if(!canGroupEmpty || done || frame.budget!==budget.state || a!=EnerCubixMath.floorHour(a) || b<=a || b>a+24hr || b!=EnerCubixMath.floorHour(b) || (watermark!=null && a<watermark)) throw ArgErr("cockpitRegistryEmptyFrames")
    try
    {
      works.each |work| {work.finishReady};flowWork?.finishReady
      works.each |work| {withConsumerFrame |local| {work.addFrames(a,b,histories,local,true)}}
      if(flowWork!=null) withConsumerFrame |local| {flowWork.addFrames(a,b,histories,local,true)}
      at:=a
      while(at<b)
      {
        budget.check;end:=at+1hr
        copWorks.each |work| {withConsumerFrame |local| {work.addFrame(at,end,histories,local)}}
        ruleWorks.each |work| {withConsumerFrame |local| {work.addFrame(at,end,histories,local)}}
        at=end
      }
      watermark=b
    }
    catch(Err e) {failure=e;throw e}
  }
  private Void withConsumerFrame(|EnerCubixPreparedOwner| consume)
  {
    local:=EnerCubixPreparedOwner(budget.state,pool)
    try {consume(local)} finally {local.close}
  }
  Void finish()
  {
    check;if(done) return
    try
    {
      flowWork?.finish
      scratch:=EnerCubixPreparedOwner(budget.state)
      try
      {
        scratch.hold(2+2*works.size)
        works.vals.sort |a,b| {b.stateEntries <=> a.stateEntries}.each |work| {work.finish}
      }
      finally {scratch.close}
      Str[] copWarnings:=Str[,]
      copKeys.each |id| {copWorks[id].finish(copWarnings);copWarnings=(Str[])((Map)copWorks[id].result["report"])["warnings"]}
      ruleWorks.each |work| {work.finish}
      cleaningKeys.each |key| {pool.seal(key)}
      diagnostics=pool.freeze;pool.bind(metadata);flowWork?.project;done=true
    }
    catch(Err e) {failure=e;throw e}
  }
  ** Called inside the source's borrowed metadata callback, after the shared
  ** sample pool freezes. Counters/configuration detach; sample rows stay shared.
  Void cleaning(Str pointId,DateTime from,DateTime to,Str:Obj? meta,EnerCubixCockpitRequestScope? scope := null)
  {
    check
    key:=EnerCubixCockpitStream.diagnosticKey(pointId,from,to)
    if(!done || !cleaningKeys.contains(key) || attachedCleaning.containsKey(key) || meta["details"] !== pool.rows(key)) throw ArgErr("cockpitRegistryCleaningPlan")
    if(scope!=null && scope.stream.state!==budget.state) throw ArgErr("cockpitRegistryCleaningPlan")
    EnerCubixPreparedOwner? work;Map? wrapper
    try
    {
      metadata.hold(1);attachedCleaning[key]=true
      shared:=meta
      if(scope!=null)
      {
        work=EnerCubixPreparedOwner(budget.state);work.hold(4+meta.size);wrapper=meta.dup
        ["parameters","summary"].each |field|
        {
          value:=meta[field]
          if(value is Map || value is List)
          {
            frozen:=scope.freezeCleaningFact(value)
            // Output cleanup and later report transfer already protect these
            // same pool roots. Their quota belongs to the longer scope owner.
            if(!pool.protectedRoots.any |root| {root===frozen}) {diagnosticOwner.hold(1);pool.protectedRoots.add(frozen)}
            wrapper[field]=frozen
          }
        }
        shared=wrapper
      }
      works.each |item| {item.cleaning(pointId,from,to,shared,pool.diagnosticId(key))}
      flowWork?.cleaning(pointId,from,to,shared,pool.diagnosticId(key))
    }
    catch(Err e) {failure=e;throw e}
    finally {wrapper?.clear;work?.close}
  }
  ** A recognizable source configuration failure has no cleaning report in the
  ** original reader. Seal the declared group without fabricating one.
  Void omitCleaning(Str pointId,DateTime from,DateTime to)
  {
    check;key:=EnerCubixCockpitStream.diagnosticKey(pointId,from,to)
    if(done || !cleaningKeys.contains(key) || attachedCleaning.containsKey(key)) throw ArgErr("cockpitRegistryCleaningPlan")
    pool.seal(key,true);metadata.hold(1);attachedCleaning[key]=true
  }
  Str:Obj? read(Str key,Str:Obj? query)
  {
    validateReport(key,query)
    result:=key.startsWith("cop:") ? (Str:Obj?)copWorks[key[4..-1]].result["report"] : (key=="energy-flow" ? flowWork.result : works[key].result)
    if(result.isEmpty) throw ArgErr("cockpitRegistryReportReleased")
    return result
  }
  Void validateReport(Str key,Str:Obj? query)
  {
    check
    if(!done || attachedCleaning.size!=cleaningKeys.size || !queries.containsKey(key)) throw ArgErr("cockpitRegistryReportNotPrepared")
    expectQuery(query,queries[key],"cockpitRegistryReportNotPrepared")
  }
  Void releaseReport(Str key)
  {
    check
    if(!done || !queries.containsKey(key) || key.startsWith("cop:")) throw ArgErr("cockpitRegistryReportNotPrepared")
    if(key=="energy-flow") flowWork.close
    else works[key].close
  }
  Str:Obj? freezeReport(Str key,Str:Obj? query,EnerCubixCockpitRequestScope scope)
  {
    source:=read(key,query)
    if(key.startsWith("cop:")) throw ArgErr("cockpitRegistryReportNotPrepared")
    result:=key=="energy-flow" ? flowWork.freezeReport(scope) : works[key].freezeReport(scope)
    releaseReport(key);return result
  }
  Void prepareReportBorrows(EnerCubixCockpitRequestScope scope)
  {
    check
    if(!done || attachedCleaning.size!=cleaningKeys.size) throw ArgErr("cockpitRegistryReportNotPrepared")
    scope.prepareReportBorrows(catalog.protectedRoots,pool.protectedRoots)
    // Projection/cleaning are complete. Retire flow's numerical lookup objects
    // before transferring the other reports, retaining its full public DAG.
    flowWork?.retainPublic(scope)
  }
  ** After publication planning has no remaining producer/output borrower. Keep
  ** the diagnostic owner alive: the snapshot still borrows its public graph.
  Bool retirePlanning()
  {
    check
    if(planningRetired) return true
    if(!done || !copWorks.isEmpty || !ruleWorks.isEmpty || works.any |work,key| {!work.released} || (flowWork!=null && !flowWork.released)) return false
    metadata.close;flowWork=null;flowMeters.clear;flowPeriods.clear
    flowModel?.close;copModel?.close;model.close;planningRetired=true
    return true
  }
  private Void expectQuery(Str:Obj? query,Str:Obj? registered,Str error)
  {
    scratch:=EnerCubixPreparedOwner(budget.state)
    try
    {
      scratch.hold(4+query.size+registered.size)
      if(!same(signature(query),signature(registered))) throw ArgErr(error)
    }
    finally {scratch.close}
  }
  Str:Obj? copData(Str id,Str:Obj? query)
  {read("cop:"+id,query);return copWorks[id].result}
  Str:Obj? ruleData(Str id,Str:Obj? query)
  {
    check
    if(!done || attachedCleaning.size!=cleaningKeys.size || !ruleWorks.containsKey(id)) throw ArgErr("cockpitRegistryRuleNotPrepared")
    expectQuery(query,queries["profile-energy"],"cockpitRegistryRuleNotPrepared");return ruleWorks[id].result
  }
  private Str:Obj? signature(Str:Obj? q)
  {q.findAll |v,k| {k!="_cockpitDeadline" && k!="_cockpitDiagnosticCapture" && k!="_cockpitPointIds"}}
  // Container type parameters can differ after native JSON/DTO conversion.
  // Compare fields and ordered values; a changed bound/metric/member still fails.
  private Bool same(Obj? a,Obj? b)
  {
    if(a is Map && b is Map)
    {left:=(Map)a;right:=(Map)b;return left.size==right.size && left.all |v,k| {right.containsKey(k) && same(v,right[k])}}
    if(a is List && b is List)
    {left:=(List)a;right:=(List)b;return left.size==right.size && left.all |v,i| {same(v,right[i])}}
    return a==b
  }
  private Void check() {if(closed || closing) throw ArgErr("cockpitRegistryClosed");if(failure!=null) throw failure;budget.check}
  Void close()
  {
    if(closed) return
    closing=true
    flowWork?.close
    copWorks.each |work| {work.close}
    ruleWorks.each |work| {work.close}
    works.each |work| {work.close}
    if(budget.diagnosticCapture===pool) budget.diagnosticCapture=null
    metadata.close;diagnosticOwner.close;flowModel?.close;copModel?.close;model.close;catalog=null;pool=null;flowWork=null;cleaningKeys.clear;closed=true
  }
}

** One registered report owns state until its last query hour, and keeps only
** its admitted output until the complete snapshot has finished consuming it.
internal class EnerCubixCockpitReportWork
{
  new make(Str key,Str:Obj? q,EnerCubixCockpitCatalog catalog,EnerCubixStreamBudget budget,EnerCubixCockpitCapture pool,Str:EnerCubixTariffCursor tariffs)
  {this.key=key;this.q=q;this.catalog=catalog;this.budget=budget;this.pool=pool;this.tariffs=tariffs;from=DateTime.fromIso(q["from"].toStr).toTimeZone(catalog.tz);to=DateTime.fromIso(q["to"].toStr).toTimeZone(catalog.tz);next=from}
  private Str key
  private Str:Obj? q
  private EnerCubixCockpitCatalog catalog
  private EnerCubixStreamBudget budget
  private EnerCubixCockpitCapture pool
  private Str:EnerCubixTariffCursor tariffs
  private DateTime from
  private DateTime to
  private DateTime next
  private EnerCubixPreparedOwner? state
  private EnerCubixPreparedOwner? output
  private EnerCubixContext? context
  private EnerCubixReport? report
  private EnerCubixReportConsumer? consumer
  private EnerCubixLineCursor[] cursors := [,]
  private EnerCubixHeatmapConsumer[] heatmaps := [,]
  internal Str:Obj? result := [:] {private set}
  private Bool done := false
  private Bool transferReady := false

  private Void open(Bool metadataOnly := false)
  {
    state=EnerCubixPreparedOwner(budget.state,pool);output=EnerCubixPreparedOwner(budget.state,pool)
    state.watch |->Void| {cursors.clear;report=null;consumer=null;context=null}
    state.hold(10);output.hold(4)
    ctx:=EnerCubixContext.shared(catalog,q["dimension"].toStr,q["spaceSource"]=="fin",state);context=ctx;ctx.orderWarnings
    if(q["metric"]=="cost") tariffs.each |cursor,id| {ctx.bindTariffCursor(id,cursor,state)}
    if(ctx.dimension.nativeSpace) ctx.byId.each |r| {if(r["nativeSourceMissing"]==true) {label:=r["name"] ?: r["id"];ctx.warn("$label : nativeSourceMissing")}}
    state.hold(4+q.size+2*EnerCubixMath.strings(q["nodeIds"]).size)
    request:=ctx.dimension.normalizeRequest(q)
    kind:=request["kind"] as Str ?: "profile";period:=request["period"] as Str ?: "day";metric:=request["metric"] as Str ?: "energy"
    report=EnerCubixReport(ctx,request,from,to,kind,period,metric,state,key=="space-summary")
    created:=report;output.watch |->Void| {created.clearFrames}
    selected:=EnerCubixMath.strings(request["nodeIds"]).unique
    if(kind=="utility") EnerCubixEndUse.resolve(ctx,selected,EnerCubixDimension.cockpitRangeCategory(request)).each |meter| {state.hold(1);cursors.add(report.openLine(meter["id"].toStr,meter["categoryId"] as Str ?: ""))}
    else selected.each |id|
    {
      record:=ctx.byId[id]
      if(record==null) {ctx.warn("Unknown selected node: $id");return}
      if(record["kind"]=="nativePoint" || (["space","organization","group"].contains(record["kind"]) && !ctx.dimension.scope(id))) throw ArgErr("cockpitRegistrySelectedNode")
      categories:=ctx.categories(id)
      if(request["_cockpitCategoryId"]!=null) categories=categories.findAll |category| {category==request["_cockpitCategoryId"]}
      if(categories.isEmpty) categories=[""]
      categories.each |category| {state.hold(1);cursors.add(report.openLine(id,category))}
    }
    if(key=="face-heatmap")
    {
      output.hold(4);catalog.bind(output)
      cursors.each |cursor| {state.hold(1);heatmaps.add(EnerCubixHeatmapConsumer(cursor.line,from,to,DateTime.fromIso(request["asOf"].toStr),state,output))}
    }
    else if(metadataOnly) report.freezeFrameMetadata(cursors.map |c->EnerCubixLine| {c.line},output)
    else consumer=EnerCubixReportConsumer(ctx,report,cursors,from,to,period,state,output,key=="space-summary" ? null : pool,key=="space-summary" ? null : key)
    output.watch |->Void| {result.clear;heatmaps.clear}
  }
  Void prepareMetadata() {if(state==null) open(true)}
  private Void activate()
  {
    if(state==null) open
    if(key!="face-heatmap" && consumer==null)
    {
      try {consumer=EnerCubixReportConsumer(context,report,cursors,from,to,q["period"] as Str ?: "day",state,output,key=="space-summary" ? null : pool,key=="space-summary" ? null : key)}
      catch(EnerCubixHttpErr e) {Log.get("enerCubix").err("Cockpit report activation rejected: $key (state=${state.entries}, output=${output.entries})",e);throw e}
    }
  }
  Void addFrame(DateTime a,DateTime b,Str:EnerCubixHistoryData histories,EnerCubixPreparedOwner frame)
  {addFrames(a,b,histories,frame)}
  Void addFrames(DateTime a,DateTime b,Str:EnerCubixHistoryData histories,EnerCubixPreparedOwner frame,Bool constantEmpty := false)
  {
    if(done || next>=to || next>=b || next<a) return
    activate
    if(key=="face-heatmap")
    {
      report.beginFrame(frame,histories,constantEmpty)
      while(next<to && next<b)
      {cursors.each |cursor,i| {heatmaps[i].add(cursor.next)};next=EnerCubixMath.floorHour(next)+1hr;if(next>to) next=to}
    }
    else {consumer.addFrames(histories,frame,b,constantEmpty);next=b<to ? b : to}
    // State is closed by the next call/finish, after the borrowed frame expires.
  }
  Void finish()
  {
    if(done) return
    if(next!=to) throw ArgErr("cockpitRegistryIncomplete")
    activate
    if(key=="face-heatmap")
    {
      cells:=[Str:Obj?][,];excluded:=[Str:Obj?][,]
      heatmaps.each |heatmap| {data:=heatmap.finish;output.hold(((List)data["heatmap"]).size+((List)data["excludedDays"]).size);cells.addAll(EnerCubixMath.maps(data["heatmap"]));excluded.addAll(EnerCubixMath.maps(data["excludedDays"]))}
      output.hold(5);result=Str:Obj?["_cockpitHeatmapData":["heatmap":cells,"excludedDays":excluded]]
      output.watch |->Void| {cells.clear;excluded.clear}
    }
    else
    {
      try {result=consumer.finish}
      catch(EnerCubixHttpErr e) {Log.get("enerCubix").err("Cockpit report finish rejected: $key (state=${stateEntries}, output=${output.entries}, remaining=${budget.state.remaining})",e);throw e}
      if(key!="space-summary") {output.hold(2);((Map)result["extra"])["cleaning"]=[Str:Obj?][,]}
    }
    retained:=key=="face-heatmap" ? output.entries : consumer.publicEntries
    done=true;state.close
    if(key=="face-heatmap") {heatmaps.each |h| {h.retirePrivateLinks};heatmaps.clear;retained=output.entries}
    if(key=="face-heatmap" || retained<output.entries)
    {
      // State close severed Work -> consumer/report/cursors. Replace callbacks
      // without running clearFrames, whose containers alias the public result.
      publicResult:=result;catalogRoots:=catalog.protectedRoots;sampleRoots:=pool.protectedRoots
      output.retainPublic(retained) |->Void| {EnerCubixReportConsumer.clearPublic(publicResult,catalogRoots,sampleRoots)}
      transferReady=true
    }
  }
  Str:Obj? freezeReport(EnerCubixCockpitRequestScope scope)
  {
    if(!done || state.entries!=0 || result.isEmpty) throw ArgErr("cockpitReportTransferNotFinished")
    if(transferReady && key=="face-heatmap")
    {
      // Reducer objects and their field-dependent cleanup are retired. Only
      // the completed public cells/excluded-day graph stays under this owner.
      retained:=scope.publicReportEntries(result,output.entries)
      if(retained<output.entries)
      {
        publicResult:=result;catalogRoots:=catalog.protectedRoots;sampleRoots:=pool.protectedRoots
        output.retainPublic(retained) |->Void| {EnerCubixReportConsumer.clearPublic(publicResult,catalogRoots,sampleRoots)}
      }
    }
    return transferReady ? scope.freezeOwnedReport(key,result,output) : scope.freezeReport(key,result)
  }
  Bool released() {done && (state?.entries ?: 0)==0 && (output?.entries ?: 0)==0}
  Int stateEntries() {(state?.entries ?: 0)+(consumer?.childStateEntries ?: 0)}
  Void finishReady() {if(!done && next==to) finish}
  Void cleaning(Str pointId,DateTime a,DateTime b,Str:Obj? meta,Str diagnosticRef)
  {
    if(!done) throw ArgErr("cockpitRegistryIncomplete")
    if(key=="space-summary" || key=="face-heatmap" || from>=b || to<=a) return
    row:=(Str:Obj?)copy(meta);output.hold(4)
    row["pointId"]=pointId;row["sourceIds"]=[pointId];row["detailsDiagnosticRef"]=diagnosticRef
    ((List)((Map)result["extra"])["cleaning"]).add(row)
  }
  private Obj? copy(Obj? value)
  {
    if(pool.protectedRoots.any |root| {root===value}) return value
    if(value is Map)
    {
      source:=(Map)value;output.hold(1+source.size)
      out:=Str:Obj?[:];source.each |v,k| {out[k.toStr]=copy(v)};return out
    }
    if(value is List)
    {
      source:=(List)value;output.hold(1+source.size)
      out:=List(source.of,source.size);source.each |v| {out.add(copy(v))};return out
    }
    if(value!=null && !value.isImmutable) throw ArgErr("cockpitRegistryCleaningScalar")
    return value
  }
  Void close() {state?.close;output?.close}
}


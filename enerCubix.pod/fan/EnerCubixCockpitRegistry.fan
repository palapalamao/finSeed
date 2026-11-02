** Private metadata-first report registry. This seam deliberately refuses modules
** whose bounded adapters are not yet installed; it never falls back to a whole
** history report. All work shares one source clock and one diagnostic row pool.
internal class EnerCubixCockpitRegistry
{
  new make(Str:Obj? q,[Str:Obj?][] records,Str:Obj? boundary,Str[] enabled,Str:Obj? comparison,Str? auxiliary,Str:Obj? owned,EnerCubixStreamBudget budget,Str:Str units,Str[] loadedPoints,Str:[Str:Obj?] cleaningPlan := [:])
  {
    this.budget=budget
    model=EnerCubixPreparedOwner(budget.state);metadata=EnerCubixPreparedOwner(budget.state);diagnosticOwner=EnerCubixPreparedOwner(budget.state)
    generation:=EnerCubixPreparedOwner(budget.state)
    try
    {
      generation.hold(64+2*(q.size+8))
      if(DateTime.fromIso(q["to"].toStr)>DateTime.fromIso(q["asOf"].toStr)) throw ArgErr("cockpitRegistryFuturePlan")
      if(!q.isImmutable || !records.isImmutable || !boundary.isImmutable || enabled.any |id| {!["kpis","trend","space","time","endUse","organization"].contains(id)}) throw ArgErr("cockpitRegistryPlan")
      metadata.watch |->Void| {works.clear;queries.each |v| {v.clear};queries.clear;space.clear;currentPoints.clear;tariffs.clear;billing.clear;attachedCleaning.clear;diagnostics=Str:Obj?[:];planning=null}
      metadata.hold(21+loadedPoints.size);currentPoints=loadedPoints.dup
      catalog=EnerCubixCockpitCatalog(records,TimeZone(q["tz"].toStr),model,units)
      planning=EnerCubixContext.shared(catalog,q["dimension"].toStr,q["spaceSource"]=="fin",metadata)
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
        if(key=="face-heatmap" || key=="space-summary") return
        spec[key]=["kind":"sourceUsage","grain":"sourceRead","objectIds":query["nodeIds"],"sourceIds":sources(query),"sourceIdsComplete":true,"requestRange":["from":query["from"],"to":query["to"],"asOf":query["asOf"]],"reportRefs":[key]]
      }
      spec.setAll(cleaningPlan)
      // Descriptors are cloned/charged by Capture; construction scratch expires.
      pool=EnerCubixCockpitCapture(spec,diagnosticOwner)
      }
      finally {scratch.close}
      if(budget.diagnosticCapture!=null) throw ArgErr("cockpitRegistryDiagnosticPool")
      budget.diagnosticCapture=pool
      metadata.hold(cleaningPlan.size);cleaningKeys=cleaningPlan.keys
      queries.each |query,key| {metadata.hold(22);works[key]=EnerCubixCockpitReportWork(key,query,catalog,budget,pool,tariffs)}
    }
    catch(Err e) {close;throw e}
    finally {generation.close}
  }
  private EnerCubixStreamBudget budget
  private EnerCubixPreparedOwner model
  private EnerCubixPreparedOwner metadata
  private EnerCubixPreparedOwner diagnosticOwner
  private EnerCubixCockpitCatalog? catalog
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
  private Bool closing := false
  private DateTime? watermark
  private Err? failure
  Str[] keys() {check;return queries.keys}

  private Void metrics(Str:Obj? q,Str prefix,Str? auxiliary)
  {["cost","co2",auxiliary==null ? "area" : "auxiliary"].each |id| {add(prefix+"profile-"+id,EnerCubixCockpitReports.metricQuery(q,id,auxiliary))}}
  private Void add(Str key,Str:Obj? q)
  {metadata.hold(34+q.size);queries[key]=q.dup}
  private Str[] sources(Str:Obj? q)
  {
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
      works.each |work| {work.addFrame(a,b,histories,frame)}
      tariffs.each |cursor,id| {if(histories.containsKey(catalog.byId[id]["pointId"] as Str ?: "")) cursor.consumeHour}
      watermark=b
    }
    catch(Err e) {failure=e;throw e}
  }
  Void finish()
  {
    check;if(done) return
    try
    {
      scratch:=EnerCubixPreparedOwner(budget.state)
      try
      {
        scratch.hold(2+2*works.size)
        works.vals.sort |a,b| {b.stateEntries <=> a.stateEntries}.each |work| {work.finish}
      }
      finally {scratch.close}
      cleaningKeys.each |key| {pool.seal(key)}
      diagnostics=pool.freeze;pool.bind(metadata);done=true
    }
    catch(Err e) {failure=e;throw e}
  }
  ** Called inside the source's borrowed metadata callback, after the shared
  ** sample pool freezes. Counters/configuration detach; sample rows stay shared.
  Void cleaning(Str pointId,DateTime from,DateTime to,Str:Obj? meta)
  {
    check
    key:=EnerCubixCockpitStream.diagnosticKey(pointId,from,to)
    if(!done || !cleaningKeys.contains(key) || attachedCleaning.containsKey(key) || meta["details"] !== pool.rows(key)) throw ArgErr("cockpitRegistryCleaningPlan")
    try
    {
      metadata.hold(1);attachedCleaning[key]=true
      works.each |work| {work.cleaning(pointId,from,to,meta,pool.diagnosticId(key))}
    }
    catch(Err e) {failure=e;throw e}
  }
  Str:Obj? read(Str key,Str:Obj? query)
  {
    check
    if(!done || attachedCleaning.size!=cleaningKeys.size || !queries.containsKey(key)) throw ArgErr("cockpitRegistryReportNotPrepared")
    scratch:=EnerCubixPreparedOwner(budget.state)
    try
    {
      scratch.hold(4+query.size+queries[key].size)
      if(!same(signature(query),signature(queries[key]))) throw ArgErr("cockpitRegistryReportNotPrepared")
    }
    finally {scratch.close}
    return works[key].result
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
    works.each |work| {work.close}
    if(budget.diagnosticCapture===pool) budget.diagnosticCapture=null
    metadata.close;diagnosticOwner.close;model.close;catalog=null;pool=null;cleaningKeys.clear;closed=true
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
  private EnerCubixReport? report
  private EnerCubixReportConsumer? consumer
  private EnerCubixLineCursor[] cursors := [,]
  private EnerCubixHeatmapConsumer[] heatmaps := [,]
  internal Str:Obj? result := [:] {private set}
  private Bool done := false

  private Void open()
  {
    state=EnerCubixPreparedOwner(budget.state);output=EnerCubixPreparedOwner(budget.state)
    state.watch |->Void| {cursors.clear;report=null;consumer=null}
    state.hold(10);output.hold(4)
    ctx:=EnerCubixContext.shared(catalog,q["dimension"].toStr,q["spaceSource"]=="fin",state);ctx.orderWarnings
    if(q["metric"]=="cost") tariffs.each |cursor,id| {ctx.bindTariffCursor(id,cursor,state)}
    if(ctx.dimension.nativeSpace) ctx.byId.each |r| {if(r["nativeSourceMissing"]==true) {label:=r["name"] ?: r["id"];ctx.warn("$label : nativeSourceMissing")}}
    state.hold(4+q.size+2*EnerCubixMath.strings(q["nodeIds"]).size)
    request:=ctx.dimension.normalizeRequest(q)
    kind:=request["kind"] as Str ?: "profile";period:=request["period"] as Str ?: "day";metric:=request["metric"] as Str ?: "energy"
    report=EnerCubixReport(ctx,request,from,to,kind,period,metric,state,key=="space-summary")
    selected:=EnerCubixMath.strings(request["nodeIds"]).unique
    if(kind=="utility") EnerCubixEndUse.resolve(ctx,selected).each |meter| {state.hold(1);cursors.add(report.openLine(meter["id"].toStr,meter["categoryId"] as Str ?: ""))}
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
    else consumer=EnerCubixReportConsumer(ctx,report,cursors,from,to,period,state,output,key=="space-summary" ? null : pool,key=="space-summary" ? null : key)
    output.watch |->Void| {result.clear;heatmaps.clear}
  }
  Void addFrame(DateTime a,DateTime b,Str:EnerCubixHistoryData histories,EnerCubixPreparedOwner frame)
  {
    if(done || next>=to || next>=b || next<a) return
    if(state==null) open
    if(key=="face-heatmap")
    {report.beginFrame(frame,histories);cursors.each |cursor,i| {heatmaps[i].add(cursor.next)}}
    else consumer.addFrame(histories,frame)
    next=EnerCubixMath.floorHour(next)+1hr;if(next>to) next=to
    // State is closed by the next call/finish, after the borrowed frame expires.
  }
  Void finish()
  {
    if(done) return
    if(next!=to || state==null) throw ArgErr("cockpitRegistryIncomplete")
    if(key=="face-heatmap")
    {
      cells:=[Str:Obj?][,];excluded:=[Str:Obj?][,]
      heatmaps.each |heatmap| {data:=heatmap.finish;output.hold(((List)data["heatmap"]).size+((List)data["excludedDays"]).size);cells.addAll(EnerCubixMath.maps(data["heatmap"]));excluded.addAll(EnerCubixMath.maps(data["excludedDays"]))}
      output.hold(5);result=Str:Obj?["_cockpitHeatmapData":["heatmap":cells,"excludedDays":excluded]]
      output.watch |->Void| {cells.clear;excluded.clear}
    }
    else
    {
      result=consumer.finish
      if(key!="space-summary") {output.hold(2);((Map)result["extra"])["cleaning"]=[Str:Obj?][,]}
    }
    done=true;state.close
  }
  Int stateEntries() {state?.entries ?: 0}
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


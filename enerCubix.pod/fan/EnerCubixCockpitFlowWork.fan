** Registry-owned numeric and graph lifetimes are separate. The graph is built
** only after the shared diagnostic pool freezes and every producer frame ends.
internal class EnerCubixCockpitFlowWork
{
  new make(Str:Obj? q,EnerCubixCockpitCatalog catalog,EnerCubixStreamBudget budget,EnerCubixCockpitCapture pool,Str:Str periodKeys,[Str:Obj?][]? selectedPlan := null)
  {
    if(!q.isImmutable) throw ArgErr("cockpitFlowWorkPlan")
    this.q=q;this.catalog=catalog;this.budget=budget;this.pool=pool;this.periodKeys=periodKeys;this.selectedPlan=selectedPlan
    from=DateTime.fromIso(q["from"].toStr).toTimeZone(catalog.tz);to=DateTime.fromIso(q["to"].toStr).toTimeZone(catalog.tz);next=from
  }
  private Str:Obj? q
  private EnerCubixCockpitCatalog catalog
  private EnerCubixStreamBudget budget
  private EnerCubixCockpitCapture pool
  private Str:Str periodKeys
  private [Str:Obj?][]? selectedPlan
  private DateTime from
  private DateTime to
  private DateTime next
  private EnerCubixPreparedOwner? state
  private EnerCubixPreparedOwner? numbers
  private EnerCubixPreparedOwner? graph
  private EnerCubixFlowConsumer? consumer
  internal Str:Obj? result := [:] {private set}
  private Bool done := false
  private Bool projected := false

  Void addFrame(DateTime a,DateTime b,Str:EnerCubixHistoryData histories,EnerCubixPreparedOwner frame)
  {
    if(done || next>=to || next>=b || next<a) return
    if(state==null)
    {
      state=EnerCubixPreparedOwner(budget.state);numbers=EnerCubixPreparedOwner(budget.state);graph=EnerCubixPreparedOwner(budget.state)
      consumer=EnerCubixFlowConsumer(q,catalog,state,numbers,pool,"energy-flow",periodKeys,selectedPlan)
    }
    consumer.addFrame(histories,frame)
    next=EnerCubixMath.floorHour(next)+1hr;if(next>to) next=to
  }
  Void finish()
  {
    if(done) return
    if(next!=to || state==null) throw ArgErr("cockpitFlowWorkIncomplete")
    consumer.finish;state.close;done=true
  }
  Void finishReady() {if(!done && next==to) finish}
  Void project()
  {
    if(projected) return
    if(!done || !pool.finalized) throw ArgErr("cockpitFlowWorkIncomplete")
    layout:=EnerCubixPreparedOwner(budget.state)
    try
    {
      ctx:=EnerCubixContext.shared(catalog,q["dimension"].toStr,q["spaceSource"]=="fin",layout)
      consumer.bind(graph)
      result=EnerCubixEnergyFlow.projectPrepared(ctx,q,from,to,|Str id,Bool known->EnerCubixValue| {consumer.value(id,known,ctx)},consumer.overview,graph)
      graph.hold(4);result["asOf"]=q["asOf"];((Map)result["extra"])["relationBasis"]="current"
      cleaning:=[Str:Obj?][,];((Map)result["extra"])["cleaning"]=cleaning
      graph.watch |->Void| {cleaning.each |row| {drop(row)};cleaning.clear;result.clear}
      projected=true
    }
    finally {layout.close}
  }
  Void cleaning(Str pointId,DateTime a,DateTime b,Str:Obj? meta,Str diagnosticRef)
  {
    if(!projected) throw ArgErr("cockpitFlowWorkIncomplete")
    if(from>=b || to<=a) return
    row:=(Str:Obj?)copy(meta);graph.hold(4)
    row["pointId"]=pointId;row["sourceIds"]=[pointId];row["detailsDiagnosticRef"]=diagnosticRef
    ((List)((Map)result["extra"])["cleaning"]).add(row)
  }
  private Obj? copy(Obj? value)
  {
    if(pool.protectedRoots.any |root| {root===value}) return value
    if(value is Map)
    {source:=(Map)value;graph.hold(1+source.size);out:=Str:Obj?[:];source.each |v,k| {out[k.toStr]=copy(v)};return out}
    if(value is List)
    {source:=(List)value;graph.hold(1+source.size);out:=List(source.of,source.size);source.each |v| {out.add(copy(v))};return out}
    if(value!=null && !value.isImmutable) throw ArgErr("cockpitFlowCleaningScalar")
    return value
  }
  private Void drop(Obj? value)
  {
    if(value isnot Map && value isnot List) return
    if(pool.protectedRoots.any |root| {root===value}) return
    if(value is Map) {((Map)value).each |child| {drop(child)};((Map)value).clear}
    else {((List)value).each |child| {drop(child)};((List)value).clear}
  }
  Void close() {state?.close;graph?.close;numbers?.close;consumer=null}
}

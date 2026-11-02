** One COP's current-range state, over the registry's shared source clock.
** Finish is deliberately ordered by configuration id to preserve the ordinary
** COP context's cumulative warning prefix without retaining any yearly ticks.
internal class EnerCubixCockpitCopWork
{
  new make(Str:Obj? q,Str:Obj? item,EnerCubixCockpitCatalog catalog,EnerCubixStreamBudget budget)
  {
    if(!q.isImmutable || !item.isImmutable) throw ArgErr("cockpitCopWorkPlan")
    this.q=q;this.item=item;this.catalog=catalog;this.budget=budget
    from=DateTime.fromIso(q["from"].toStr).toTimeZone(catalog.tz);to=DateTime.fromIso(q["to"].toStr).toTimeZone(catalog.tz);next=from
  }
  private Str:Obj? q
  private Str:Obj? item
  private EnerCubixCockpitCatalog catalog
  private EnerCubixStreamBudget budget
  private DateTime from
  private DateTime to
  private DateTime next
  private EnerCubixPreparedOwner? state
  private EnerCubixPreparedOwner? output
  private EnerCubixCopConsumer? consumer
  internal Str:Obj? result := [:] {private set}
  private Bool done := false

  Void addFrame(DateTime a,DateTime b,Str:EnerCubixHistoryData histories,EnerCubixPreparedOwner frame)
  {
    if(done || next>=to || next>=b || next<a) return
    if(state==null)
    {
      state=EnerCubixPreparedOwner(budget.state);output=EnerCubixPreparedOwner(budget.state)
      consumer=EnerCubixCopConsumer(q,item,catalog,state,output)
    }
    consumer.addFrame(histories,frame)
    next=EnerCubixMath.floorHour(next)+1hr;if(next>to) next=to
  }
  Void finish(Str[] previousWarnings)
  {
    if(done) return
    if(next!=to || state==null) throw ArgErr("cockpitCopWorkIncomplete")
    result=consumer.finish(previousWarnings);done=true;state.close
  }
  Void close() {state?.close;output?.close;consumer=null}
}

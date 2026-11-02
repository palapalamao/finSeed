** One explicitly configured clue over the existing primary source clock.
internal class EnerCubixCockpitRuleWork
{
  new make(Str:Obj? q,Str:Obj? profile,[Str:Obj?][] records,Str:Obj? boundary,EnerCubixCockpitCatalog catalog,EnerCubixStreamBudget budget)
  {
    state=EnerCubixPreparedOwner(budget.state);output=EnerCubixPreparedOwner(budget.state)
    try {consumer=EnerCubixNonWorkingConsumer(q,profile,records,boundary,catalog,state,output)}
    catch(Err e) {close;throw e}
  }
  private EnerCubixPreparedOwner state
  private EnerCubixPreparedOwner output
  private EnerCubixNonWorkingConsumer? consumer
  internal Str:Obj? result := [:] {private set}
  private Bool done := false
  Void addFrame(DateTime a,DateTime b,Str:EnerCubixHistoryData histories,EnerCubixPreparedOwner frame)
  {consumer.addFrame(a,b,histories,frame)}
  Void finish() {if(done) return;result=consumer.finish;done=true;state.close}
  Void close() {state.close;output.close;consumer=null}
}

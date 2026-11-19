** One explicitly configured clue over the existing primary source clock.
internal class FinEnergyCockpitRuleWork
{
  new make(Str:Obj? q,Str:Obj? profile,[Str:Obj?][] records,Str:Obj? boundary,FinEnergyCockpitCatalog catalog,FinEnergyStreamBudget budget)
  {
    state=FinEnergyPreparedOwner(budget.state);output=FinEnergyPreparedOwner(budget.state)
    try {consumer=FinEnergyNonWorkingConsumer(q,profile,records,boundary,catalog,state,output)}
    catch(Err e) {close;throw e}
  }
  private FinEnergyPreparedOwner state
  private FinEnergyPreparedOwner output
  private FinEnergyNonWorkingConsumer? consumer
  internal Str:Obj? result := [:] {private set}
  private Bool done := false
  Void addFrame(DateTime a,DateTime b,Str:FinEnergyHistoryData histories,FinEnergyPreparedOwner frame)
  {consumer.addFrame(a,b,histories,frame)}
  Void finish() {if(done) return;result=consumer.finish;done=true;state.close}
  Void close() {state.close;output.close;consumer=null}
}

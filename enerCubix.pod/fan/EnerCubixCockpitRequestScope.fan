** One admitted request. The gate and envelope outlive final serialization and
** sending; arithmetic and input/projection owners will share this stream state.
internal class EnerCubixCockpitRequestScope
{
  new make(Str project,Str user,EnerCubixStreamBudget? stream := null)
  {
    this.project=project;this.user=user;this.stream=stream ?: EnerCubixStreamBudget()
    try
    {
      deadline.check;EnerCubixCockpitGate.enter(project,user);entered=true
      owner=EnerCubixPreparedOwner(this.stream.state)
      owner.hold(24);owner.watch |->Void| {envelope?.clear;envelope=null;inputs=null}
    }
    catch(Err e)
    {
      try {close} catch(Err cleanup) {Log.get("enerCubix").err("Cockpit request cleanup failed after admission failure",cleanup)}
      throw e
    }
  }
  const Str project
  const Str user
  EnerCubixStreamBudget stream {private set}
  EnerCubixCockpitDeadline deadline() {stream.state.deadline}
  private EnerCubixPreparedOwner? owner
  private [Str:Obj?]? envelope
  private EnerCubixPreparedOwner? inputOwner
  private [Str:Obj?]? inputs
  private Bool entered := false
  private Bool closed := false
  private Bool attempted := false
  private Bool delivering := false
  Bool responseStarted := false {private set}
  Bool canSendError() {!responseStarted}
  Int entries() {(owner?.entries ?: 0)+(inputOwner?.entries ?: 0)}
  Void checkContext(Str project,Str user)
  {if(closed || !entered || this.project!=project || this.user!=user) throw ArgErr("cockpitRequestScopeContext");deadline.check}
  Str:Obj? freezeInputs(Str:Obj? input,Str:Obj? owned,[Str:Obj?][] records)
  {
    checkContext(project,user)
    if(inputs!=null) throw ArgErr("cockpitRequestInputsAlreadyFrozen")
    if(inputOwner==null) inputOwner=EnerCubixPreparedOwner(stream.state)
    scratch:=EnerCubixPreparedOwner(stream.state);Map? bundle
    try
    {
      scratch.hold(4);bundle=["input":input,"owned":owned,"records":records]
      inputs=(Str:Obj?)EnerCubixCockpitFreeze.value(bundle,inputOwner);return inputs
    }
    finally {bundle?.clear;scratch.close}
  }
  Void deliver(Str:Obj? data,|Buf| send)
  {
    checkContext(project,user)
    if(attempted) throw ArgErr("cockpitResponseAlreadyAttempted")
    attempted=true;delivering=true
    try
    {
      owner.hold(3);envelope=["ok":true,"data":data]
      EnerCubixCockpitWire.withBody(envelope,stream.state,|Buf bytes|
      {responseStarted=true;send(bytes)})
    }
    finally {delivering=false}
  }
  Void close()
  {
    if(closed) return
    if(delivering) throw ArgErr("cockpitRequestScopeInUse")
    closed=true
    Err? failure
    try {owner?.close} catch(Err e) {failure=e}
    try {inputOwner?.close} catch(Err e) {if(failure==null) failure=e;else Log.get("enerCubix").err("Cockpit input cleanup also failed",e)}
    if(entered) {entered=false;EnerCubixCockpitGate.leave(project,user)}
    if(failure!=null) throw failure
  }
}

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
      owner.hold(24);owner.watch |->Void| {envelope?.clear;envelope=null}
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
  private Bool entered := false
  private Bool closed := false
  private Bool attempted := false
  private Bool delivering := false
  Bool responseStarted := false {private set}
  Bool canSendError() {!responseStarted}
  Int entries() {owner?.entries ?: 0}
  Void checkContext(Str project,Str user)
  {if(closed || !entered || this.project!=project || this.user!=user) throw ArgErr("cockpitRequestScopeContext");deadline.check}
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
    try {owner?.close}
    finally {if(entered) {entered=false;EnerCubixCockpitGate.leave(project,user)}}
  }
}

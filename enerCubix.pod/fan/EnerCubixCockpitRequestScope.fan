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
      owner.hold(24);owner.watch |->Void| {envelope?.clear;envelope=null;inputs=null;snapshot=null;frozenReports?.clear;frozenReports=null}
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
  private EnerCubixPreparedOwner? snapshotOwner
  private [Str:Obj?]? snapshot
  private EnerCubixPreparedOwner? reportOwner
  private EnerCubixPreparedOwner? payloadOwner
  private [Str:[Str:Obj?]]? frozenReports
  private Bool entered := false
  private Bool closed := false
  private Bool attempted := false
  private Bool delivering := false
  Bool responseStarted := false {private set}
  Bool canSendError() {!responseStarted}
  Int entries() {(owner?.entries ?: 0)+(inputOwner?.entries ?: 0)+(snapshotOwner?.entries ?: 0)+(reportOwner?.entries ?: 0)+(payloadOwner?.entries ?: 0)}
  EnerCubixPreparedOwner payloadOutput()
  {checkContext(project,user);if(payloadOwner==null) payloadOwner=EnerCubixPreparedOwner(stream.state);return payloadOwner}
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
  Str:Obj? freezeSnapshot(Str:Obj? source)
  {
    checkContext(project,user)
    if(snapshot!=null) throw ArgErr("cockpitRequestSnapshotAlreadyFrozen")
    if(snapshotOwner==null) snapshotOwner=EnerCubixPreparedOwner(stream.state)
    snapshot=(Str:Obj?)EnerCubixCockpitFreeze.value(source,snapshotOwner);return snapshot
  }
  [Str:Obj?]? frozenReport(Str key) {checkContext(project,user);return frozenReports?.get(key)}
  Str:Obj? freezeReport(Str key,Str:Obj? source)
  {
    checkContext(project,user)
    cached:=frozenReports?.get(key);if(cached!=null) return cached
    if(reportOwner==null)
    {reportOwner=EnerCubixPreparedOwner(stream.state);reportOwner.hold(1);frozenReports=[:]}
    value:=(Str:Obj?)EnerCubixCockpitFreeze.value(source,reportOwner)
    reportOwner.hold(1);frozenReports[key]=value;return value
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
    try {payloadOwner?.close} catch(Err e) {if(failure==null) failure=e;else Log.get("enerCubix").err("Cockpit payload cleanup also failed",e)}
    try {snapshotOwner?.close} catch(Err e) {if(failure==null) failure=e;else Log.get("enerCubix").err("Cockpit snapshot cleanup also failed",e)}
    try {reportOwner?.close} catch(Err e) {if(failure==null) failure=e;else Log.get("enerCubix").err("Cockpit report cleanup also failed",e)}
    try {inputOwner?.close} catch(Err e) {if(failure==null) failure=e;else Log.get("enerCubix").err("Cockpit input cleanup also failed",e)}
    if(entered) {entered=false;EnerCubixCockpitGate.leave(project,user)}
    if(failure!=null) throw failure
  }
}

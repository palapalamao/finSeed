using [java] java.util::IdentityHashMap

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
      owner.hold(24);owner.watch |->Void| {envelope?.clear;envelope=null;inputs=null;snapshot=null;historyHeaders=null;sourcePlan=null;frozenReports?.clear;frozenReports=null}
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
  private EnerCubixPreparedOwner? preparationOwner
  private EnerCubixPreparedOwner? inputOwner
  private [Str:Obj?]? inputs
  private EnerCubixPreparedOwner? snapshotOwner
  private [Str:Obj?]? snapshot
  private EnerCubixPreparedOwner? reportOwner
  private EnerCubixPreparedOwner? reportBorrowOwner
  private IdentityHashMap? reportBorrows
  private EnerCubixPreparedOwner? payloadOwner
  private EnerCubixPreparedOwner? configurationOwner
  private EnerCubixPreparedOwner? historyOwner
  private EnerCubixPreparedOwner? historyMetadataWork
  private [Str:Obj?][]? historyHeaders
  private EnerCubixPreparedOwner? sourcePlanOwner
  private [Str:Obj?]? sourcePlan
  private EnerCubixPreparedOwner? planningModel
  private EnerCubixPreparedOwner? planningState
  private EnerCubixCockpitCatalog? planningCatalog
  private [Str:Obj?][]? planningRecords
  private [Str:[Str:Obj?]]? frozenReports
  private Bool entered := false
  private Bool closed := false
  private Bool attempted := false
  private Bool delivering := false
  Bool responseStarted := false {private set}
  Bool canSendError() {!responseStarted}
  Int entries() {(owner?.entries ?: 0)+(preparationOwner?.entries ?: 0)+(inputOwner?.entries ?: 0)+(snapshotOwner?.entries ?: 0)+(reportOwner?.entries ?: 0)+(reportBorrowOwner?.entries ?: 0)+(payloadOwner?.entries ?: 0)+(planningModel?.entries ?: 0)+(planningState?.entries ?: 0)+(configurationOwner?.entries ?: 0)+(historyOwner?.entries ?: 0)+(historyMetadataWork?.entries ?: 0)+(sourcePlanOwner?.entries ?: 0)}
  Str:Obj? freezeSourcePlan(Str:Obj? request)
  {
    checkContext(project,user)
    if(sourcePlanOwner!=null) throw ArgErr("cockpitSourcePlanAlreadyFrozen")
    sourcePlanOwner=EnerCubixPreparedOwner(stream.state)
    rows:=(List)(inputs?.get("records") ?: throw ArgErr("cockpitSourcePlanInputs"))
    scratch:=EnerCubixPreparedOwner(stream.state);[Str:Map]? facts
    try
    {
      scratch.hold(1+rows.size);facts=Str:Map[:]
      rows.each |Map row| {id:=row["id"] as Str;if(id!=null && row.isImmutable) facts[id]=row}
      // Reuse only exact copies of a still-owned, frozen business fact. This
      // does not merge arbitrary equal maps or alter ordered containers.
      sourcePlan=(Str:Obj?)EnerCubixCockpitFreeze.value(request,sourcePlanOwner,|Obj value->Obj?|
      {
        row:=value as Map;if(row==null) return null
        id:=row["id"] as Str;fact:=id==null ? null : facts[id]
        return fact!=null && row.typeof==fact.typeof && row.ordered==fact.ordered && row==fact ? fact : null
      })
      return sourcePlan
    }
    finally {facts?.clear;scratch.close}
  }
  EnerCubixPreparedOwner historyOutput()
  {checkContext(project,user);if(historyOwner==null) historyOwner=EnerCubixPreparedOwner(stream.state);return historyOwner}
  [Str:Obj?][] freezeHistoryHeaders([Str:Obj?][] headers)
  {
    checkContext(project,user)
    if(historyHeaders!=null)
    {
      if(headers.size==historyHeaders.size && headers.all |row,i| {row===historyHeaders[i]}) return historyHeaders
      throw ArgErr("cockpitHistoryHeadersAlreadyFrozen")
    }
    historyHeaders=([Str:Obj?][])EnerCubixCockpitFreeze.value(headers,historyOutput);return historyHeaders
  }
  ** The completed source session lends only its private header graph here,
  ** before request metadata/closures are appended. Immutable configuration
  ** facts remain borrowed; the source owner keeps empty headers until close.
  [Str:Obj?][] freezeSourceHeaders([Str:Obj?][] headers,EnerCubixPreparedOwner producer)
  {
    checkContext(project,user)
    if(historyHeaders!=null || producer.budget!==stream.state || producer.entries==0 || headers.isImmutable) throw ArgErr("cockpitSourceHeaderTransfer")
    historyHeaders=([Str:Obj?][])EnerCubixCockpitFreeze.value(headers,historyOutput,null,|Obj value|
    {
      count:=value is Map ? ((Map)value).size : ((List)value).size
      if(value is Map) ((Map)value).clear;else ((List)value).clear
      producer.release(count)
    })
    return historyHeaders
  }
  EnerCubixPreparedOwner metadataWorkspace(Int pointCount)
  {
    checkContext(project,user)
    if(historyMetadataWork!=null) throw ArgErr("cockpitHistoryMetadataAlreadyCreated")
    historyMetadataWork=EnerCubixPreparedOwner(stream.state);historyMetadataWork.hold(17+pointCount)
    return historyMetadataWork
  }
  Void finishMetadata() {historyMetadataWork?.close}
  EnerCubixPreparedOwner configurationOutput()
  {checkContext(project,user);if(configurationOwner==null) configurationOwner=EnerCubixPreparedOwner(stream.state);return configurationOwner}
  EnerCubixContext planningContext([Str:Obj?][] records,TimeZone tz,Str dimension,Bool nativeSpace)
  {
    checkContext(project,user)
    if(planningModel!=null) throw ArgErr("cockpitPlanningAlreadyCreated")
    planningModel=EnerCubixPreparedOwner(stream.state)
    ownedFacts:=inputs?.get("records")===records
    catalog:=EnerCubixCockpitCatalog(records,tz,planningModel,[:],false,ownedFacts,ownedFacts);planningCatalog=catalog;planningRecords=records
    planningState=EnerCubixPreparedOwner(stream.state)
    return EnerCubixContext.shared(catalog,dimension,nativeSpace,planningState)
  }
  EnerCubixCockpitCatalog sourceCatalog([Str:Obj?][] records,TimeZone tz,Str:Str units)
  {
    checkContext(project,user)
    if(planningCatalog==null || planningRecords!==records || planningCatalog.tz!=tz) throw ArgErr("cockpitSourceCatalogContext")
    planningCatalog.prepareUnits(units);return planningCatalog
  }
  Void finishPlanning() {planningState?.close;planningModel?.close;planningCatalog=null;planningRecords=null;sourcePlan=null;sourcePlanOwner?.close}
  ** Only this already-admitted frozen snapshot may lend immutable business
  ** containers to its own payload. Reprojected or foreign inputs use copying.
  Bool canBorrowPayload(Str:Obj? source,EnerCubixPreparedOwner target)
  {checkContext(project,user);return source===snapshot && (snapshotOwner?.entries ?: 0)>0 && target===payloadOwner && target.entries>0 && target.budget===stream.state}
  EnerCubixPreparedOwner payloadOutput()
  {checkContext(project,user);if(payloadOwner==null) payloadOwner=EnerCubixPreparedOwner(stream.state);return payloadOwner}
  Void checkContext(Str project,Str user)
  {if(closed || !entered || this.project!=project || this.user!=user) throw ArgErr("cockpitRequestScopeContext");deadline.check}
  EnerCubixPreparedOwner preparationWorkspace()
  {checkContext(project,user);if(preparationOwner==null) preparationOwner=EnerCubixPreparedOwner(stream.state);return preparationOwner}
  Void finishPreparation() {preparationOwner?.close}
  Str:Obj? freezeInputs(Str:Obj? input,Str:Obj? owned,[Str:Obj?][] records)
  {
    checkContext(project,user)
    if(inputs!=null) throw ArgErr("cockpitRequestInputsAlreadyFrozen")
    if(inputOwner==null) inputOwner=EnerCubixPreparedOwner(stream.state)
    scratch:=EnerCubixPreparedOwner(stream.state);Map? bundle;[Str:Map]? facts;Map? normalizedOwned;List? model
    try
    {
      configuration:=owned;source:=owned["modelRecords"] as List
      if(source!=null && source!==records)
      {
        // Both are private copies of the same catalogue. Only complete typed
        // business facts with matching ID, fields and ordering may be shared.
        scratch.hold(3+records.size+source.size+owned.size)
        facts=Str:Map[:];records.each |r| {id:=r["id"] as Str;if(id!=null) facts[id]=r}
        model=source.dup
        source.each |v,i|
        {
          deadline.check;row:=v as Map;id:=row?.get("id") as Str;fact:=id==null ? null : facts[id]
          if(fact!=null && row.typeof==fact.typeof && row.ordered==fact.ordered && row==fact) model[i]=fact
        }
        normalizedOwned=owned.dup.set("modelRecords",model);configuration=normalizedOwned
      }
      scratch.hold(4);bundle=["input":input,"owned":configuration,"records":records]
      inputs=(Str:Obj?)EnerCubixCockpitFreeze.value(bundle,inputOwner);finishPreparation;return inputs
    }
    finally {bundle?.clear;facts?.clear;model?.clear;normalizedOwned?.clear;scratch.close}
  }
  ** Preserve the legacy byte fingerprint of canonical business map heads.
  ** Only unchanged facts borrowed by the canonical context need its former
  ** shallow dup layout; these small hash-only copies expire immediately.
  Str configurationFingerprint([Str:Obj?][] configuration,[Str:Obj?][] canonicalRows,[Str:Obj?][] refs,Obj? appliedCleaning)
  {
    checkContext(project,user)
    work:=EnerCubixPreparedOwner(stream.state);[Str:Obj?][]? rows;[Str:Obj?][]? copies;Map? root
    try
    {
      work.hold(6+configuration.size);rows=[,];copies=[,]
      configuration.each |row|
      {
        if(row.isImmutable && canonicalRows.any |source| {source===row})
        {work.hold(2+row.size);copy:=row.dup;copies.add(copy);rows.add(copy)}
        else rows.add(row)
      }
      root=Str:Obj?["refs":refs,"configuration":rows,"appliedCleaning":appliedCleaning]
      return EnerCubixCockpitDigest.json(root,deadline,stream.state).sha256
    }
    finally {root?.clear;rows?.clear;copies?.each |copy| {copy.clear};copies?.clear;work.close}
  }
  Str:Obj? freezeSnapshot(Str:Obj? source)
  {
    checkContext(project,user)
    if(snapshot!=null) throw ArgErr("cockpitRequestSnapshotAlreadyFrozen")
    if(snapshotOwner==null) snapshotOwner=EnerCubixPreparedOwner(stream.state)
    snapshot=(Str:Obj?)EnerCubixCockpitFreeze.value(source,snapshotOwner);return snapshot
  }
  [Str:Obj?]? frozenReport(Str key) {checkContext(project,user);return frozenReports?.get(key)}
  Str:Obj? freezeReport(Str key,Str:Obj? source,|Obj|? consume := null)
  {
    checkContext(project,user)
    cached:=frozenReports?.get(key);if(cached!=null) return cached
    if(reportOwner==null)
    {reportOwner=EnerCubixPreparedOwner(stream.state);reportOwner.hold(1);frozenReports=[:]}
    value:=(Str:Obj?)EnerCubixCockpitFreeze.value(source,reportOwner,null,consume)
    reportOwner.hold(1);frozenReports[key]=value;return value
  }
  ** Only a completed registry work may consume its exclusive mutable result.
  ** Protect every descendant of borrowed roots, including direct aliases into
  ** another report's catalog or diagnostic graph.
  Void prepareReportBorrows(Obj[] catalog,Obj[] samples)
  {
    checkContext(project,user)
    if(reportBorrowOwner!=null) throw ArgErr("cockpitReportBorrowsAlreadyPrepared")
    reportBorrowOwner=EnerCubixPreparedOwner(stream.state)
    try
    {
      reportBorrowOwner.hold(8);reportBorrows=IdentityHashMap()
      reportBorrowOwner.watch |->Void| {reportBorrows?.clear;reportBorrows=null}
      catalog.each |root| {protectReportBorrow(root,reportBorrows,reportBorrowOwner)}
      samples.each |root| {protectReportBorrow(root,reportBorrows,reportBorrowOwner)}
    }
    catch(Err e) {releaseReportBorrows;throw e}
  }
  Void releaseReportBorrows() {reportBorrowOwner?.close;reportBorrowOwner=null}
  Str:Obj? freezeOwnedReport(Str key,Str:Obj? source,EnerCubixPreparedOwner producer)
  {
    checkContext(project,user)
    if(producer.budget!==stream.state || producer.entries==0 || source.isImmutable || reportBorrows==null) throw ArgErr("cockpitReportTransferOwner")
    return freezeReport(key,source,|Obj value|
    {
      if(reportBorrows.containsKey(value)) return
      count:=value is Map ? ((Map)value).size : ((List)value).size
      if(value is Map) ((Map)value).clear;else ((List)value).clear
      // Memoization precedes consumption; aliases receive the full target.
      // Keep the empty source header charged until its producer closes.
      producer.release(count)
    })
  }
  private Void protectReportBorrow(Obj? value,IdentityHashMap borrowedGraph,EnerCubixPreparedOwner scratch)
  {
    if(value==null || value.isImmutable || (value isnot Map && value isnot List) || borrowedGraph.containsKey(value)) return
    deadline.check;scratch.hold(3);borrowedGraph.put(value,true)
    if(value is Map) ((Map)value).each |v| {protectReportBorrow(v,borrowedGraph,scratch)}
    else ((List)value).each |v| {protectReportBorrow(v,borrowedGraph,scratch)}
  }
  ** Optional exact private-container compaction. Exhausted scratch retains
  ** the original conservative allowance; it never causes an admission failure.
  ** Mutable catalog/pool descendants are borrowed; immutable containers counted
  ** conservatively here remain charged if their ownership cannot be excluded.
  Int publicReportEntries(Str:Obj? source,Int cap)
  {
    checkContext(project,user)
    if(reportBorrows==null || cap<0) throw ArgErr("cockpitReportTransferOwner")
    // A small valid graph needs no optional compaction workspace.
    if(cap<32 || stream.state.remaining<24) return cap
    scratch:=EnerCubixPreparedOwner(stream.state);IdentityHashMap? seen
    try
    {
      scratch.hold(16)
      // Count a conservative tree first: aliases may overcount but cannot
      // undercount live containers. This uses bounded depth-only workspace,
      // so optional compaction need not allocate an index of the whole DAG.
      tree:=reportTreeEntries(source,cap-32,scratch,0)
      if(tree<cap-32) return tree+32
      seen=IdentityHashMap()
      return (reportEntries(source,cap-32,seen,scratch)+32).min(cap)
    }
    finally {seen?.clear;scratch.close}
  }
  private Int reportTreeEntries(Obj? value,Int cap,EnerCubixPreparedOwner scratch,Int depth)
  {
    if(cap<=0 || value==null || (value isnot Map && value isnot List) || reportBorrows.containsKey(value)) return 0
    deadline.check
    if(depth>=64 || stream.state.remaining<4) return cap
    scratch.hold(4)
    try
    {
      n:=1+(value is Map ? ((Map)value).size : ((List)value).size)
      if(n>=cap) return cap
      if(value is Map) ((Map)value).each |child| {if(n<cap) n+=reportTreeEntries(child,cap-n,scratch,depth+1)}
      else ((List)value).each |child| {if(n<cap) n+=reportTreeEntries(child,cap-n,scratch,depth+1)}
      return n
    }
    finally {scratch.release(4)}
  }
  private Int reportEntries(Obj? value,Int cap,IdentityHashMap seen,EnerCubixPreparedOwner scratch)
  {
    if(cap<=0 || value==null || (value isnot Map && value isnot List) || reportBorrows.containsKey(value) || seen.containsKey(value)) return 0
    deadline.check
    if(stream.state.remaining<3) return cap
    scratch.hold(3);seen.put(value,true)
    n:=1+(value is Map ? ((Map)value).size : ((List)value).size)
    if(n>=cap) return cap
    if(value is Map) ((Map)value).each |child| {if(n<cap) n+=reportEntries(child,cap-n,seen,scratch)}
    else ((List)value).each |child| {if(n<cap) n+=reportEntries(child,cap-n,seen,scratch)}
    return n
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
    try {finishPlanning} catch(Err e) {if(failure==null) failure=e;else Log.get("enerCubix").err("Cockpit planning cleanup also failed",e)}
    try {snapshotOwner?.close} catch(Err e) {if(failure==null) failure=e;else Log.get("enerCubix").err("Cockpit snapshot cleanup also failed",e)}
    try {reportOwner?.close} catch(Err e) {if(failure==null) failure=e;else Log.get("enerCubix").err("Cockpit report cleanup also failed",e)}
    try {releaseReportBorrows} catch(Err e) {if(failure==null) failure=e;else Log.get("enerCubix").err("Cockpit borrowed report index cleanup also failed",e)}
    try {finishMetadata;historyOwner?.close} catch(Err e) {if(failure==null) failure=e;else Log.get("enerCubix").err("Cockpit history metadata cleanup also failed",e)}
    try {configurationOwner?.close} catch(Err e) {if(failure==null) failure=e;else Log.get("enerCubix").err("Cockpit configuration cleanup also failed",e)}
    try {finishPreparation} catch(Err e) {if(failure==null) failure=e;else Log.get("enerCubix").err("Cockpit preparation cleanup also failed",e)}
    try {inputOwner?.close} catch(Err e) {if(failure==null) failure=e;else Log.get("enerCubix").err("Cockpit input cleanup also failed",e)}
    if(entered) {entered=false;EnerCubixCockpitGate.leave(project,user)}
    if(failure!=null) throw failure
  }
}

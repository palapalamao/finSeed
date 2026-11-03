** Current-relationship own-primary folds for flow. Finish owns the overview,
** values and strict warning vectors; pool.freeze precedes graph projection.
** Projection DTO/scratch admission is deliberately a separate lifetime.
internal class EnerCubixFlowConsumer
{
  new make(Str:Obj? q,EnerCubixCockpitCatalog catalog,EnerCubixPreparedOwner state,EnerCubixPreparedOwner output,EnerCubixCockpitCapture pool,Str usageKey,Str:Str periodKeys,[Str:Obj?][]? selectedPlan := null)
  {
    if(!q.isImmutable || state===output || state.budget!==output.budget || state.budget!==catalog.owner.budget || pool.budget!==state.budget || q["kind"]!="energyFlow" || q["metric"]!="energy" || q["flowMode"]=="endUse" || q["meterHistorySegments"]!=null) throw ArgErr("flowConsumerPlan")
    this.q=q;this.state=state;this.output=output;this.pool=pool;this.usageKey=usageKey
    from=DateTime.fromIso(q["from"].toStr).toTimeZone(catalog.tz);to=DateTime.fromIso(q["to"].toStr).toTimeZone(catalog.tz);at=from
    if(to<=from) throw ArgErr("flowConsumerRange")
    calc=EnerCubixPreparedOwner(state.budget)
    try
    {
      state.watch |->Void| {calc.close;devices.clear;this.periodKeys.clear;stateClosed=true}
      state.hold(18+periodKeys.size);this.periodKeys=periodKeys.dup
      output.watch |->Void| {if(bindings.any |owner| {owner.entries!=0}) throw ArgErr("flowValuesStillBorrowed");drop(overviewData);strictValues.each |v| {expire(v)};knownValues.each |v| {expire(v)};maskedValues.each |v| {expire(v)};strictValues.clear;knownValues.clear;maskedValues.clear;warningValues.each |v| {v.clear};warningValues.clear;bindings.clear;borrowed=Obj[,];outputClosed=true}
      output.hold(14);borrowed=catalog.protectedRoots;catalog.bind(output);pool.bind(output)
      pool.expect(usageKey,"sourceUsage")
      scratch:=EnerCubixPreparedOwner(state.budget)
      try
      {
        meters:=[Str:Obj?][,]
        if(selectedPlan==null)
        {
          scratch.hold(32+8*catalog.records.size)
          dim:=catalog.view(q["dimension"].toStr,q["spaceSource"]=="fin")
          scope:=EnerCubixEnergyFlow.scope(dim.normalizeRequest(q),dim,scratch)
          meters=EnerCubixMath.maps(scope["selected"]).dup.addAll(EnerCubixMath.maps(scope["unassigned"])).unique
        }
        else
        {
          // Registry already resolved this exact catalogue before source I/O.
          // Borrow its owned facts; never infer a second scope at output peak.
          scratch.hold(32+4*selectedPlan.size)
          category:=catalog.byId[q["categoryId"] as Str ?: ""]
          if(q["perArea"]==true || !["space","metering","organization"].contains(q["dimension"]) || (q["flowMode"]!=null && q["flowMode"]!="relations") || category?.get("kind")!="category" || (category?.get("unit") as Str ?: "").isEmpty) throw ArgErr("flowConsumerSelectedPlan")
          if(selectedPlan.any |meter| {id:=meter["id"] as Str;return id==null || catalog.byId[id]!==meter || !["meter","totalMeter"].contains(meter["kind"]) || meter["categoryId"]!=q["categoryId"]}) throw ArgErr("flowConsumerSelectedPlan")
          meters=selectedPlan.dup
        }
        meters.sort |a,b| {a["id"].toStr<=>b["id"].toStr}
        if(periodKeys.size!=meters.size || meters.any |m| {!periodKeys.containsKey(m["id"].toStr)}) throw ArgErr("flowConsumerPeriodsPlan")
        meters.each |meter|
        {
          id:=meter["id"].toStr;pool.expect(periodKeys[id],"coveragePeriods")
          calc.hold(14);devices.add(EnerCubixFlowDevice(q,catalog,meter,from,to,calc))
        }
      }
      finally {scratch.close}
    }
    catch(Err e) {calc.close;throw e}
  }
  private Str:Obj? q
  private EnerCubixPreparedOwner state
  private EnerCubixPreparedOwner output
  private EnerCubixPreparedOwner calc
  private EnerCubixCockpitCapture pool
  private Str usageKey
  private Str:Str periodKeys := [:]
  private DateTime from
  private DateTime to
  private DateTime at
  private EnerCubixFlowDevice[] devices := [,]
  private Str:EnerCubixValue strictValues := [:]
  private Str:EnerCubixValue knownValues := [:]
  private Str:EnerCubixValue maskedValues := [:]
  private Str:Str[] warningValues := [:]
  private Str:Obj? overviewData := [:]
  private Obj[] borrowed := [,]
  private EnerCubixPreparedOwner[] bindings := [,]
  private Int reads := 0
  private Int periods := 0
  private Bool emptyOmitted := false
  private Bool unpreparedOmitted := false
  private Bool done := false
  private Bool stateClosed := false
  private Bool outputClosed := false
  private Err? failure

  Void addFrame(Str:EnerCubixHistoryData histories,EnerCubixPreparedOwner frame)
  {
    check
    if(done || stateClosed || at>=to || frame.budget!==state.budget) throw ArgErr("flowConsumerFrame")
    try
    {
      end:=EnerCubixMath.floorHour(at)+1hr;if(end>to) end=to
      devices.each |device|
      {
        frame.hold(2);own:=Str:EnerCubixHistoryData[:]
        h:=histories[device.point];if(h!=null) own[device.point]=h
        device.strict.beginFrame(frame,own);device.known.beginFrame(frame,own)
        device.strict.warningScope(0,0,at.ticks)
        strict:=device.strict.node(device.id,device.category,at,end)
        known:=device.known.node(device.id,device.category,at,end)
        device.strictFold.add(strict);device.knownFold.add(known)
        frame.hold(2+2*device.known.knownReads.size)
        rows:=device.known.knownReads.vals
        device.coverage.addFrame(rows,frame)
        rows.each |row| {pool.put(usageKey,row);reads++}
        emptyOmitted=emptyOmitted || device.known.emptyEvidenceOmitted
        unpreparedOmitted=unpreparedOmitted || device.known.unpreparedEvidenceOmitted
        key:=periodKeys[device.id]
        if(pool.canPutSimple(key))
        {
          scratch:=EnerCubixPreparedOwner(state.budget)
          try {scratch.hold(6);pool.put(key,["from":at.toIso,"to":end.toIso,"value":known.value,"quality":known.quality,"pointId":device.point])}
          finally {scratch.close}
        }
        else pool.skipSimple(key)
      }
      periods++;at=end
    }
    catch(Err e) {failure=e;throw e}
  }
  Void finish()
  {
    check;if(done) return
    if(stateClosed || at!=to) throw ArgErr("flowConsumerIncomplete")
    try
    {
      output.hold(14+devices.size);rows:=[Str:Obj?][,]
      seconds:=(to-from).ticks.toFloat/1sec.ticks.toFloat
      devices.each |device|
      {
        strict:=freezeValue(device.strictFold);known:=freezeValue(device.knownFold)
        strictValues[device.id]=strict;knownValues[device.id]=known
        warnings:=device.strict.orderedWarnings
        output.hold(2+warnings.size);warningValues[device.id]=warnings.dup
        scratch:=EnerCubixPreparedOwner(state.budget)
        try
        {
          scratch.hold(16);coverage:=device.coverage.finish;covered:=(Float)coverage["coveredSeconds"]
          output.hold(32)
          row:=Str:Obj?["id":device.id,"nodeId":device.id,"name":device.record["name"],"categoryId":device.category,"unit":device.strict.unit(device.id,device.category,"energy"),"value":known.value,"valueType":known.valueType,"quality":known.quality,"completeValue":strict.value,"completeQuality":strict.quality,"sourceIds":known.sources,"activeSeconds":seconds,"topologyActiveSeconds":seconds,"coveredSeconds":covered,"coverage":seconds>0f ? (covered/seconds).min(1f) : 0f,"complete":known.value!=null && strict.value!=null && strict.reliable && covered>=seconds,"substituted":known.quality=="substituted","removed":false,"pointId":device.point,"meterIds":[device.id]]
          pool.periodEnvelope(periodKeys[device.id],row,output,periods);pool.seal(periodKeys[device.id]);rows.add(row)
        }
        finally {scratch.close}
      }
      output.hold(5)
      knownUsage:=Str:Obj?["basis":"closedSourceIntervals","asOf":q["asOf"],"sourceUsage":pool.rows(usageKey)]
      pool.knownEnvelope(usageKey,knownUsage,output,reads,emptyOmitted,unpreparedOmitted);pool.seal(usageKey,emptyOmitted || unpreparedOmitted)
      overviewData=Str:Obj?["from":from.toIso,"to":to.toIso,"asOf":q["asOf"],"unknownTopologySeconds":0f,"rows":rows,"basis":"closedSourceIntervals","selectionTotals":[Str:Obj?][,],"knownUsage":knownUsage]
      calc.close;devices.clear;done=true
    }
    catch(Err e) {failure=e;throw e}
  }
  Str:Obj? overview() {check;if(!done || !pool.finalized) throw ArgErr("flowConsumerIncomplete");return overviewData}
  Void bind(EnerCubixPreparedOwner borrower)
  {
    check
    if(!done || !pool.finalized || borrower===output || borrower.budget!==output.budget || borrower.entries==0) throw ArgErr("flowValuesBorrower")
    if(bindings.any |owner| {owner===borrower}) return
    output.hold(6);bindings.add(borrower)
  }
  EnerCubixValue value(Str id,Bool known,EnerCubixContext projection)
  {
    check
    if(!done || !projection.ownedCatalog(output.budget)) throw ArgErr("flowConsumerProjection")
    values:=known ? knownValues : strictValues
    result:=values[id] ?: throw ArgErr("flowOwnValueNotPrepared")
    r:=projection.byId[id]
    if(projection.dimension?.nativeSpace==true && r?.get("nativeSourceMissing")==true && r["configurationError"]==null)
    {
      if(!maskedValues.containsKey(id)) {output.hold(7);maskedValues[id]=EnerCubixValue(null,"nativeSourceMissing",Str[,])}
      if(!known) {label:=r["name"] ?: id;projection.warn("$label : nativeSourceMissing")}
      return maskedValues[id]
    }
    if(!known) warningValues[id].each |warning| {projection.warn(warning)}
    return result
  }
  private EnerCubixValue freezeValue(EnerCubixValueFold fold)
  {
    scratch:=EnerCubixPreparedOwner(state.budget)
    try {scratch.hold(4+3*fold.sourceCount);output.hold(6+fold.sourceCount);return fold.finish}
    finally {scratch.close}
  }
  private Void expire(EnerCubixValue value) {value.sources.clear;value.value=null;value.quality="ownerExpired"}
  private Void drop(Obj? value)
  {
    if(value isnot Map && value isnot List) return
    if(borrowed.any |root| {root===value} || pool.protectedRoots.any |root| {root===value}) return
    if(value is Map) {((Map)value).each |child| {drop(child)};((Map)value).clear}
    else {((List)value).each |child| {drop(child)};((List)value).clear}
  }
  private Void check() {if(failure!=null) throw failure;if(outputClosed || (stateClosed && !done)) throw ArgErr("flowConsumerClosed");state.budget.deadline.check}
}

internal class EnerCubixFlowDevice
{
  new make(Str:Obj? q,EnerCubixCockpitCatalog catalog,Str:Obj? record,DateTime from,DateTime to,EnerCubixPreparedOwner owner)
  {
    this.record=record;id=record["id"].toStr;category=record["categoryId"].toStr;point=record["pointId"] as Str ?: ""
    // The independent own-history overview has no spatial masking. The graph
    // applies native-source metadata separately, as the ordinary path does.
    strict=EnerCubixContext.shared(catalog,"metering",false,owner);strict.orderWarnings
    cutoff:=DateTime.fromIso(q["asOf"].toStr);known=EnerCubixContext.known(strict,to<cutoff ? to : cutoff)
    strictFold=EnerCubixValueFold.strict(owner);knownFold=EnerCubixValueFold.known(owner)
    coverage=EnerCubixCoverageFold(point.isEmpty ? Str[,] : [point],from,to,owner)
  }
  Str:Obj? record
  Str id
  Str category
  Str point
  EnerCubixContext strict
  EnerCubixContext known
  EnerCubixValueFold strictFold
  EnerCubixValueFold knownFold
  EnerCubixCoverageFold coverage
}

using haystack
using util

class FinEnergyFlowConsumerTest : Test
{
  Void testEachPhysicalDeviceWorkspaceExpiresBeforeTheNextDevice()
  {
    a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+1hr
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"]];keys:=Str:Str[:]
    spec:=Str:[Str:Obj?]["energy-flow":["kind":"sourceUsage","grain":"sourceRead","reportRefs":["energy-flow"]]]
    (0..<64).each |i|
    {
      id:="m$i";rs.add(["id":id,"kind":"meter","name":id,"pointId":"p$i","categoryId":"c"])
      key:="period-$id";keys[id]=key;spec[key]=["kind":"coveragePeriods","grain":"hour","reportRefs":["energy-flow"]]
    }
    q:=Str:Obj?["kind":"energyFlow","dimension":"metering","nodeIds":keys.keys,"categoryId":"c","categoryIds":["c"],"period":"day","metric":"energy","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC","_cockpitCategoryId":"c"]
    budget:=FinEnergyStreamBudget();model:=FinEnergyPreparedOwner(budget.state);state:=FinEnergyPreparedOwner(budget.state);output:=FinEnergyPreparedOwner(budget.state);diagnostic:=FinEnergyPreparedOwner(budget.state);frame:=FinEnergyPreparedOwner(budget.state)
    catalog:=FinEnergyCockpitCatalog(rs.toImmutable,TimeZone.utc,model);pool:=FinEnergyCockpitCapture(spec,diagnostic)
    consumer:=FinEnergyFlowConsumer(q.toImmutable,catalog,state,output,pool,"energy-flow",keys,keys.keys.map |id->Str:Obj?| {catalog.byId[id]})
    baseline:=frame.entries
    try
    {
      consumer.addFrame(Str:FinEnergyHistoryData[:],frame)
      verifyEq(frame.entries,baseline,"finished devices cannot retain their derived workspace in the shared source frame")
      consumer.finish;pool.freeze
      rows:=FinEnergyMath.maps(consumer.overview["rows"]);verifyEq(rows.size,64)
      rows.each |row| {verifyEq(row["value"],null);verifyEq(row["coveredSeconds"],0f);verifyEq(row["complete"],false)}
      verifyEq(budget.state.unprepared.val,0);verify(budget.state.peak.val<=200000)
    }
    finally {frame.close;state.close;output.close;diagnostic.close;model.close}
    verifyEq(budget.state.temporary.val,0)
  }

  Void testFlowInitializationReclaimsOnlyOptionalSamplesBeforeBusinessAdmission()
  {
    a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+1hr
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"t","kind":"totalMeter","name":"Total","pointId":"pt","categoryId":"c"]]
    q:=Str:Obj?["kind":"energyFlow","dimension":"metering","nodeIds":["t"],"categoryId":"c","categoryIds":["c"],"period":"day","metric":"energy","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC","_cockpitCategoryId":"c"]
    budget:=FinEnergyStreamBudget();model:=FinEnergyPreparedOwner(budget.state);diagnosticOwner:=FinEnergyPreparedOwner(budget.state);frame:=FinEnergyPreparedOwner(budget.state)
    catalog:=FinEnergyCockpitCatalog(rs.toImmutable,TimeZone.utc,model)
    spec:=Str:[Str:Obj?]["seed":["kind":"cleaningEvents","grain":"cleaningEvent","reportRefs":["energy-flow"]],"energy-flow":["kind":"sourceUsage","grain":"sourceRead","reportRefs":["energy-flow"]],"period-t":["kind":"coveragePeriods","grain":"hour","reportRefs":["energy-flow"]]]
    pool:=FinEnergyCockpitCapture(spec,diagnosticOwner)
    (0..<300).each |i| {pool.put("seed",["pointId":"pt","from":a.toIso,"to":b.toIso,"value":0f])}
    peer:=FinEnergyPreparedOwner(budget.state);peer.hold(budget.state.remaining-32);held:=peer.entries
    work:=FinEnergyCockpitFlowWork(q.toImmutable,catalog,budget,pool,["t":"period-t"],[catalog.byId["t"]])
    try
    {
      work.addFrame(a,b,Str:FinEnergyHistoryData[:],frame)
      verifyEq(pool.retainedRows,0);verifyEq(peer.entries,held);verify(budget.state.peak.val<=200000)
      peer.close;frame.close;work.finish;pool.seal("seed");diag:=pool.freeze
      verifyEq(diag["preparedEntryLimited"],true);verifyEq(FinEnergyMath.maps(diag["entries"]).find |e| {e["kind"]=="cleaningEvents"}["totalCount"],300)
    }
    finally {peer.close;frame.close;work.close;diagnosticOwner.close;model.close}
    verifyEq(budget.state.temporary.val,0)
  }

  Void testRejectedDeviceWorkspaceClosesWithoutReleasingTheSourceOrPeer()
  {
    a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+1hr
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","name":"M","pointId":"p","categoryId":"c"]]
    q:=Str:Obj?["kind":"energyFlow","dimension":"metering","nodeIds":["m"],"categoryId":"c","categoryIds":["c"],"period":"day","metric":"energy","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC","_cockpitCategoryId":"c"]
    budget:=FinEnergyStreamBudget();model:=FinEnergyPreparedOwner(budget.state);state:=FinEnergyPreparedOwner(budget.state);output:=FinEnergyPreparedOwner(budget.state);diagnostic:=FinEnergyPreparedOwner(budget.state);frame:=FinEnergyPreparedOwner(budget.state)
    catalog:=FinEnergyCockpitCatalog(rs.toImmutable,TimeZone.utc,model)
    spec:=Str:[Str:Obj?]["energy-flow":["kind":"sourceUsage","grain":"sourceRead","reportRefs":["energy-flow"]],"period-m":["kind":"coveragePeriods","grain":"hour","reportRefs":["energy-flow"]]]
    pool:=FinEnergyCockpitCapture(spec,diagnostic)
    consumer:=FinEnergyFlowConsumer(q.toImmutable,catalog,state,output,pool,"energy-flow",["m":"period-m"],[catalog.byId["m"]])
    peer:=FinEnergyPreparedOwner(budget.state);peer.hold(budget.state.remaining-12);held:=peer.entries;baseline:=frame.entries
    try
    {
      verifyErr(FinEnergyHttpErr#) {consumer.addFrame(Str:FinEnergyHistoryData[:],frame)}
      verifyEq(frame.entries,baseline);verifyEq(peer.entries,held)
      verifyErr(FinEnergyHttpErr#) {consumer.finish}
      verifyErr(FinEnergyHttpErr#) {consumer.overview}
      verifyEq(budget.state.unprepared.val,0);verify(budget.state.temporary.val<=200000)
    }
    finally {peer.close;frame.close;state.close;output.close;diagnostic.close;model.close}
    verifyEq(budget.state.temporary.val,0)
  }

  Void testBorrowedFramesKeepOwnValuesCoverageWarningsAndWholePeriodBalance()
  {
    (0..<8).each |testCase|
    {
      variant:=testCase%4
      missingVirtual:=variant==1;nativeMissing:=variant>=2
      a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+2hr
      rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"t","kind":"totalMeter","name":"Total","pointId":"pt","categoryId":"c"],["id":"a","kind":"meter","name":"A","pointId":"pa","categoryId":"c","meterParentId":"t"],["id":"b","kind":"meter","name":"B","pointId":"pb","categoryId":"c","meterParentId":"t"],["id":"v","kind":"totalMeter","name":"Virtual","pointId":"pv","categoryId":"c","expressionId":"e"],["id":"e","kind":"expression","expression":"x+y","variables":["x":"a","y":"b"]]]
      q:=Str:Obj?["kind":"energyFlow","dimension":"metering","nodeIds":["t","v"],"categoryId":"c","categoryIds":["c"],"period":"day","metric":"energy","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC","_cockpitExplicitObjects":true,"_cockpitCategoryId":"c","_cockpitDiagnosticCapture":true]
      if(nativeMissing)
      {
        q["dimension"]="space";q["spaceSource"]="fin"
        rs[1]["nativeSourceMissing"]=true
        rs.add(["id":"u","kind":"sensor","name":"Unselected","nativeSourceMissing":true])
        if(variant==3) rs[1]["configurationError"]="invalidPrimaryPoint"
      }
      points:=Str:Dict[:]
      ["pt","pa","pb","pv"].each |id| {points[id]=Etc.makeDict(["id":Ref(id),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])}
      read:=|Dict p,Span span,|HisItem| sink|
      {
        id:=p.id.id;if(missingVirtual && id=="pv") return
        amount:=(Float)Str:Float["pt":10f,"pa":4f,"pb":7f,"pv":9f][id]
        (0..2).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(amount)))}
      }
      expected:=FinEnergyEngine.report(q,rs,FinEnergyCockpitStream.prepare(q,rs,points,Str:Dict[:],read,FinEnergyStreamBudget()))
      budget:=FinEnergyStreamBudget();model:=FinEnergyPreparedOwner(budget.state);state:=FinEnergyPreparedOwner(budget.state);output:=FinEnergyPreparedOwner(budget.state);diagnosticOwner:=FinEnergyPreparedOwner(budget.state);layout:=FinEnergyPreparedOwner(budget.state);graph:=FinEnergyPreparedOwner(budget.state)
      catalog:=FinEnergyCockpitCatalog(rs.toImmutable,TimeZone.utc,model)
      ids:=["a","b","t","v"];periodKeys:=Str:Str[:]
      plan:=Str:[Str:Obj?]["energy-flow":["kind":"sourceUsage","grain":"sourceRead","reportRefs":["energy-flow"]]]
      ids.each |id| {key:="periods|"+id;periodKeys[id]=key;plan[key]=["kind":"coveragePeriods","grain":"hour","reportRefs":["energy-flow"]]}
      pool:=FinEnergyCockpitCapture(plan,diagnosticOwner)
      selectedPlan:=testCase<4 ? null : ids.map |id->Str:Obj?| {catalog.byId[id]}
      if(selectedPlan!=null) diagnosticOwner.hold(1+selectedPlan.size)
      beforePlan:=selectedPlan?.toStr
      consumer:=FinEnergyFlowConsumer(q.toImmutable,catalog,state,output,pool,"energy-flow",periodKeys,selectedPlan)
      planning:=FinEnergyContext.shared(catalog,"metering",false,layout)
      sources:=FinEnergyCockpitStream[,]
      try
      {
        points.keys.sort.each |id| {sources.add(FinEnergyCockpitStream.openCursor(points[id],null,a,b,q,rs,budget,read,planning))}
        (0..<2).each |i|
        {end:=a+1hr*(i+1);sources.each |s| {s.advance(end)};FinEnergyCockpitStream.withFrames(sources,budget.state) |histories,frame| {consumer.addFrame(histories,frame)}}
        sources.each |s| {s.close};consumer.finish
        verifyErr(ArgErr#) {early:=consumer.overview}
        diagnostics:=pool.freeze
        consumer.bind(graph)
        verifyErr(ArgErr#) {output.close}
        ctx:=FinEnergyContext.shared(catalog,"metering",false,layout)
        ctx=FinEnergyContext.shared(catalog,q["dimension"].toStr,nativeMissing,layout)
        result:=FinEnergyEnergyFlow.projectPrepared(ctx,q,a,b,|Str id,Bool known->FinEnergyValue| {consumer.value(id,known,ctx)},consumer.overview,graph)
        result["asOf"]=b.toIso;((Map)result["extra"])["relationBasis"]="current"
        verifyEq(business(result),business(expected))
        verifyEq(consumer.value("t",false,ctx).value,nativeMissing ? null : 20f)
        verifyEq(consumer.value("v",false,ctx).value,missingVirtual ? null : 18f)
        verify((Int)diagnostics["returnedCount"]<=1000);verifyEq(budget.state.unprepared.val,0)
        verifyErr(ArgErr#) {consumer.value("not-planned",false,ctx)}
        state.close
        verifyEq(selectedPlan?.toStr,beforePlan)
        verifyEq(FinEnergyMath.maps(consumer.overview["rows"]).size,4,"numeric state can expire while owned output stays readable")
      }
      finally {sources.each |s| {s.close};state.close;layout.close;graph.close;output.close;diagnosticOwner.close;model.close}
      verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
    }
  }
  private Str:Obj? business(Str:Obj? report)
  {
    copy:=(Str:Obj?)JsonInStream(JsonOutStream.writeJsonToStr(report).in).readJson
    extra:=(Map)copy["extra"];extra.remove("knownUsage")
    overview:=(Map)extra["energyFlowOverview"];overview.remove("knownUsage")
    [FinEnergyMath.maps(copy["rows"]),FinEnergyMath.maps(overview["rows"])].each |rows|
    {rows.each |row| {["periods","periodsCaptureId","periodRecordTotalCount","periodsReturnedCount","periodsTruncated","periodsTruncationReason","periodsDiagnosticRef"].each |key| {row.remove(key)}}}
    return copy
  }
}

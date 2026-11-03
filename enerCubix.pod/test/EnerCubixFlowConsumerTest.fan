using haystack
using util

class EnerCubixFlowConsumerTest : Test
{
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
      expected:=EnerCubixEngine.report(q,rs,EnerCubixCockpitStream.prepare(q,rs,points,Str:Dict[:],read,EnerCubixStreamBudget()))
      budget:=EnerCubixStreamBudget();model:=EnerCubixPreparedOwner(budget.state);state:=EnerCubixPreparedOwner(budget.state);output:=EnerCubixPreparedOwner(budget.state);diagnosticOwner:=EnerCubixPreparedOwner(budget.state);layout:=EnerCubixPreparedOwner(budget.state);graph:=EnerCubixPreparedOwner(budget.state)
      catalog:=EnerCubixCockpitCatalog(rs.toImmutable,TimeZone.utc,model)
      ids:=["a","b","t","v"];periodKeys:=Str:Str[:]
      plan:=Str:[Str:Obj?]["energy-flow":["kind":"sourceUsage","grain":"sourceRead","reportRefs":["energy-flow"]]]
      ids.each |id| {key:="periods|"+id;periodKeys[id]=key;plan[key]=["kind":"coveragePeriods","grain":"hour","reportRefs":["energy-flow"]]}
      pool:=EnerCubixCockpitCapture(plan,diagnosticOwner)
      selectedPlan:=testCase<4 ? null : ids.map |id->Str:Obj?| {catalog.byId[id]}
      if(selectedPlan!=null) diagnosticOwner.hold(1+selectedPlan.size)
      beforePlan:=selectedPlan?.toStr
      consumer:=EnerCubixFlowConsumer(q.toImmutable,catalog,state,output,pool,"energy-flow",periodKeys,selectedPlan)
      planning:=EnerCubixContext.shared(catalog,"metering",false,layout)
      sources:=EnerCubixCockpitStream[,]
      try
      {
        points.keys.sort.each |id| {sources.add(EnerCubixCockpitStream.openCursor(points[id],null,a,b,q,rs,budget,read,planning))}
        (0..<2).each |i|
        {end:=a+1hr*(i+1);sources.each |s| {s.advance(end)};EnerCubixCockpitStream.withFrames(sources,budget.state) |histories,frame| {consumer.addFrame(histories,frame)}}
        sources.each |s| {s.close};consumer.finish
        verifyErr(ArgErr#) {early:=consumer.overview}
        diagnostics:=pool.freeze
        consumer.bind(graph)
        verifyErr(ArgErr#) {output.close}
        ctx:=EnerCubixContext.shared(catalog,"metering",false,layout)
        ctx=EnerCubixContext.shared(catalog,q["dimension"].toStr,nativeMissing,layout)
        result:=EnerCubixEnergyFlow.projectPrepared(ctx,q,a,b,|Str id,Bool known->EnerCubixValue| {consumer.value(id,known,ctx)},consumer.overview,graph)
        result["asOf"]=b.toIso;((Map)result["extra"])["relationBasis"]="current"
        verifyEq(business(result),business(expected))
        verifyEq(consumer.value("t",false,ctx).value,nativeMissing ? null : 20f)
        verifyEq(consumer.value("v",false,ctx).value,missingVirtual ? null : 18f)
        verify((Int)diagnostics["returnedCount"]<=1000);verifyEq(budget.state.unprepared.val,0)
        verifyErr(ArgErr#) {consumer.value("not-planned",false,ctx)}
        state.close
        verifyEq(selectedPlan?.toStr,beforePlan)
        verifyEq(EnerCubixMath.maps(consumer.overview["rows"]).size,4,"numeric state can expire while owned output stays readable")
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
    [EnerCubixMath.maps(copy["rows"]),EnerCubixMath.maps(overview["rows"])].each |rows|
    {rows.each |row| {["periods","periodsCaptureId","periodRecordTotalCount","periodsReturnedCount","periodsTruncated","periodsTruncationReason","periodsDiagnosticRef"].each |key| {row.remove(key)}}}
    return copy
  }
}

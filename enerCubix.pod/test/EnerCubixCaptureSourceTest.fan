using haystack

class EnerCubixCaptureSourceTest : Test
{
  Void testUnplannedSourceAndLegacyWholeModeFailBeforeNativeReads()
  {
    from:=DateTime.fromIso("2026-01-01T00:00:00Z");to:=from+1hr
    cfg:=Etc.makeDict(["defNull":Marker.val])
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"hisFunc":"enerCubixCleanHis","hisFuncConfig":cfg,"unit":"kWh","tz":"UTC"])
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c"]]
    q:=Str:Obj?["from":from.toIso,"to":to.toIso,"asOf":to.toIso,"tz":"UTC","kind":"profile","metric":"energy","nodeIds":["m"]]
    budget:=EnerCubixStreamBudget();owner:=EnerCubixPreparedOwner(budget.state)
    pool:=EnerCubixCockpitCapture(["report":["kind":"sourceUsage","grain":"sourceRead"]],owner);budget.diagnosticCapture=pool
    calls:=0;read:=|Dict p,Span span,|HisItem| sink| {calls++}
    before:=budget.state.temporary.val
    verifyErr(ArgErr#) {EnerCubixCockpitStream.prepare(q,rs,["p":point],["p":cfg],read,budget)}
    verifyErr(ArgErr#) {rejected:=EnerCubixCockpitStream.openCursor(point,cfg,from,to,q,rs,budget,read)}
    verifyEq(calls,0);verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,before)
    foreign:=EnerCubixStreamBudget();foreign.diagnosticCapture=pool
    verifyErr(ArgErr#) {rejected:=EnerCubixCockpitStream.openCursor(point,cfg,from,to,q,rs,foreign,read)}
    verifyEq(calls,0);verifyEq(foreign.state.temporary.val,0)
    owner.close;verifyEq(budget.state.temporary.val,0)
  }
  Void testCleaningAndReportShareQuotaWithoutChangingPrimaryHistoryResults()
  {
    from:=DateTime.fromIso("2026-01-01T00:00:00Z");to:=from+20hr
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m0","kind":"meter","pointId":"p0","categoryId":"c"],["id":"m1","kind":"meter","pointId":"p1","categoryId":"c"]]
    q:=Str:Obj?["kind":"profile","nodeIds":["m0","m1"],"dimension":"metering","metric":"energy","period":"day","from":from.toIso,"to":to.toIso,"asOf":to.toIso,"tz":"UTC"]
    cfg:=Etc.makeDict(["defNull":Marker.val,"deltaMax":Number(1)])
    points:=Str:Dict[:];configs:=Str:Dict[:]
    (0..1).each |i|
    {points["p$i"]=Etc.makeDict(["id":Ref("p$i"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":cfg]);configs["p$i"]=cfg}
    raw:=HisItem[,];amount:=0f
    (0..1200).each |i| {if(i>0) amount+=i%3==0 ? 3f : 0.5f;raw.add(HisItem(from+1min*i,Number(amount)))}
    read:=|Dict p,Span span,|HisItem| sink| {raw.each |r| {if(r.ts>=span.start && r.ts<span.end) sink(r)}}
    whole:=EnerCubixCockpitStream.prepare(q,rs,points,configs,read,EnerCubixStreamBudget())
    expected:=EnerCubixEngine.report(q,rs,whole)
    budget:=EnerCubixStreamBudget();model:=EnerCubixPreparedOwner(budget.state);state:=EnerCubixPreparedOwner(budget.state);output:=EnerCubixPreparedOwner(budget.state);diagnosticOwner:=EnerCubixPreparedOwner(budget.state)
    plan:=Str:[Str:Obj?]["report":["kind":"sourceUsage","grain":"sourceRead"]]
    points.each |p,id| {plan[EnerCubixCockpitStream.diagnosticKey(id,from,to)]=["kind":"cleaningEvents","grain":"cleaningEvent"]}
    pool:=EnerCubixCockpitCapture(plan,diagnosticOwner);budget.diagnosticCapture=pool
    catalog:=EnerCubixCockpitCatalog(rs.toImmutable,TimeZone.utc,model)
    ctx:=EnerCubixContext.shared(catalog,"metering",false,state);ctx.orderWarnings
    report:=EnerCubixReport(ctx,q,from,to,"profile","day","energy",state)
    consumer:=EnerCubixReportConsumer(ctx,report,[report.openLine("m0","c"),report.openLine("m1","c")],from,to,"day",state,output,pool,"report")
    sources:=EnerCubixCockpitStream[,]
    try
    {
      points.keys.sort.each |id| {sources.add(EnerCubixCockpitStream.openCursor(points[id],cfg,from,to,q,rs,budget,read,ctx))}
      (1..20).each |i|
      {
        end:=from+1hr*i;sources.each |s| {s.advance(end)}
        EnerCubixCockpitStream.withFrames(sources,budget.state) |histories,frame| {consumer.addFrame(histories,frame)}
        verify(pool.retainedRows<=1000)
      }
      actual:=consumer.finish
      points.each |p,id| {pool.seal(EnerCubixCockpitStream.diagnosticKey(id,from,to))}
      metadata:=pool.freeze
      ["summary","series","rows","warnings"].each |key| {verifyEq(actual[key],expected[key],key)}
      verify(EnerCubixMath.maps(((Map)actual["summary"])["knownTotals"]).all |r| {r["value"]==400f})
      sources.each |s|
      {
        verify(((List)EnerCubixCockpitStream#.field("diagnostics").get(s)).isEmpty,"no per-source retained sample copy")
        s.withCleaningMetadata |meta|
        {verifyEq(meta["rejectedCount"],400);verifyEq(meta["detailsTruncated"],true);verify(meta["detailsCaptureId"] is Str)}
      }
      entries:=EnerCubixMath.maps(metadata["entries"])
      verifyEq(entries.findAll |e| {e["kind"]=="cleaningEvents"}.size,2)
      verify(entries.findAll |e| {e["kind"]=="cleaningEvents"}.all |e| {e["totalCount"]==400})
      verifyEq(budget.state.unprepared.val,0);verify(budget.state.peak.val<200000)
      echo("POOLED_CLEANING "+budget.evidence)
    }
    finally {sources.each |s| {s.close};state.close;output.close;diagnosticOwner.close;model.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
}

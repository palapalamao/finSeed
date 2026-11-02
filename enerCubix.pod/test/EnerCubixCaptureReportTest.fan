using haystack

** Two real report consumers over the same borrowed source frames; no FIN I/O.
class EnerCubixCaptureReportTest : Test
{
  Void testProfileAndDailyKeepAllBusinessValuesWithOneDiagnosticPool()
  {
    from:=DateTime.fromIso("2026-01-01T00:00:00Z");to:=from+100hr
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space"]]
    ids:=Str[,];hs:=[Str:Obj?][,];samples:=[Str:Obj?][,]
    (0..<100).each |i| {samples.add(["ts":(from+1hr*i).toIso,"value":1f])}
    (0..<18).each |i|
    {
      ids.add("m$i");rs.add(["id":"m$i","kind":"meter","categoryId":"c","pointId":"p$i","spaceId":"s"])
      hs.add(["pointId":"p$i","mode":"interval","unit":"kWh","intervalSeconds":3600f,"samples":samples])
    }
    q:=Str:Obj?["kind":"profile","metric":"energy","nodeIds":["s"],"dimension":"space","period":"day","from":from.toIso,"to":to.toIso,"asOf":to.toIso,"tz":"UTC"]
    dailyQuery:=q.dup.setAll(["kind":"daily","nodeIds":ids,"dimension":"metering","period":"hour"])
    expected:=EnerCubixEngine.report(q,rs,hs);expectedDaily:=EnerCubixEngine.report(dailyQuery,rs,hs)
    budget:=EnerCubixStreamBudget();model:=EnerCubixPreparedOwner(budget.state);diagnosticOwner:=EnerCubixPreparedOwner(budget.state)
    state:=EnerCubixPreparedOwner(budget.state);dailyState:=EnerCubixPreparedOwner(budget.state)
    output:=EnerCubixPreparedOwner(budget.state);dailyOutput:=EnerCubixPreparedOwner(budget.state)
    catalog:=EnerCubixCockpitCatalog(rs.toImmutable,TimeZone.utc,model)
    pool:=EnerCubixCockpitCapture(["profile":["kind":"sourceUsage","grain":"sourceRead","reportRefs":["profile-energy"]],"daily":["kind":"sourceUsage","grain":"sourceRead","reportRefs":["face-daily"]]],diagnosticOwner)
    ctx:=EnerCubixContext.shared(catalog,"space",false,state);ctx.orderWarnings
    dailyCtx:=EnerCubixContext.shared(catalog,"metering",false,dailyState);dailyCtx.orderWarnings
    report:=EnerCubixReport(ctx,q,from,to,"profile","day","energy",state)
    dailyReport:=EnerCubixReport(dailyCtx,dailyQuery,from,to,"daily","hour","energy",dailyState)
    consumer:=EnerCubixReportConsumer(ctx,report,[report.openLine("s","c")],from,to,"day",state,output,pool,"profile")
    daily:=EnerCubixReportConsumer(dailyCtx,dailyReport,ids.map |id->EnerCubixLineCursor| {dailyReport.openLine(id,"c")},from,to,"hour",dailyState,dailyOutput,pool,"daily")
    read:=|Dict point,Span span,|HisItem| sink|
    {(0..100).each |i| {at:=from+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(1)))}}
    sources:=EnerCubixCockpitStream[,]
    try
    {
      (0..<18).each |i|
      {
        point:=Etc.makeDict(["id":Ref("p$i"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])
        sources.add(EnerCubixCockpitStream.openCursor(point,null,from,to,q,rs,budget,read,ctx))
      }
      (1..100).each |i|
      {
        end:=from+1hr*i;sources.each |source| {source.advance(end)}
        EnerCubixCockpitStream.withFrames(sources,budget.state) |histories,frame|
        {consumer.addFrame(histories,frame);daily.addFrame(histories,frame)}
        verify(pool.retainedRows<=1000)
      }
      actual:=consumer.finish;actualDaily:=daily.finish
      known:=(Map)((Map)actual["extra"])["knownUsage"];verifyEq(known["_capturePending"],true)
      metadata:=pool.freeze;verify(!known.containsKey("_capturePending"));verifyEq(known["sourceUsageTruncated"],true)
      verifyEq(known["sourceUsageRowCount"],1800)
      ["summary","series","rows","warnings"].each |key| {verifyEq(actual[key],expected[key],key);verifyEq(actualDaily[key],expectedDaily[key],"daily/"+key)}
      ["usageCoverage","details"].each |key| {verifyEq(((Map)actual["extra"])[key],((Map)expected["extra"])[key],key)}
      ["usageCoverage","details","loadBands"].each |key| {verifyEq(((Map)actualDaily["extra"])[key],((Map)expectedDaily["extra"])[key],"daily/"+key)}
      verifyEq(((Map)EnerCubixReportConsumer#.field("evidence").get(consumer)).size,0)
      verifyEq(((Map)EnerCubixReportConsumer#.field("evidence").get(daily)).size,0)
      verifyEq(budget.state.unprepared.val,0);verify(budget.state.peak.val<200000)
      saved:=pool.rows("profile").size
      sources.each |source| {source.close};state.close;dailyState.close
      output.close;verifyEq(pool.rows("profile").size,saved,"closing a report cannot clear shared diagnostic roots")
      verifyErr(ArgErr#) {diagnosticOwner.close}
      dailyOutput.close;diagnosticOwner.close;model.close
      verify(metadata.isEmpty);verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
      echo("POOLED_REPORTS "+budget.evidence)
    }
    finally {sources.each |source| {source.close};state.close;dailyState.close;output.close;dailyOutput.close;diagnosticOwner.close;model.close}
  }
}

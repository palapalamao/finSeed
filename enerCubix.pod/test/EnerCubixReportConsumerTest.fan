using haystack

** Full report DTOs from original leaf math; controlled sources, not FIN acceptance.
class EnerCubixReportConsumerTest : Test
{
  Void testProfileMixedSelectionAndDetailsMatchOriginalReport()
  {
    [false,true].each |area|
    {
      q:=query.set("perArea",area);rs:=records
      exercise(q,rs)
    }
  }

  Void testRankingAndProportionPreserveOverlapAndKnownCoverage()
  {
    ["ranking","proportion","primary","dashboard"].each |kind| {exercise(query.set("kind",kind),records)}
  }

  Void testDetailOnlyAliasDoesNotChangeEarlierCoverageOrEvidence()
  {rs:=records;rs.last["pointId"]="pa";exercise(query,rs)}

  Void testCoefficientsAndTimedTariffKeepSameOwnMeterCalculation()
  {
    ["coal","co2","cost"].each |metric|
    {
      rs:=records
      rs.add(["id":"sub","kind":"subcategory","categoryId":"c","coalFactor":0.1229f,"co2Factor":0.5257f])
      rs.add(["id":"tariff","kind":"tariff","categoryId":"c","isDefault":true,"mode":"weekly","rate":0.735f,"currency":"CNY","rules":[["startHour":0,"endHour":0.5f,"rate":1f,"band":"valley"],["startHour":0.5f,"endHour":1,"rate":3f,"band":"sharp"]]])
      rs.findAll |r| {["meter","totalMeter"].contains(r["kind"])}.each |r| {r["subcategoryId"]="sub"}
      exercise(query.set("metric",metric),rs)
    }
  }

  Void testIncompleteOutputCannotPublishAndCleanupPreservesPeerOwner()
  {exercise(query,records,true)}

  Void testEmptySourceKeepsMissingCoverageAndEvidenceOmission()
  {exercise(query,records,false,true)}

  Void testMultipleCategoriesKeepAreaAndWarningOrder()
  {
    rs:=records;rs.each |r| {r.remove("area")}
    rs.add(["id":"water","kind":"category","unit":"m³"])
    rs.add(["id":"w","name":"Water","kind":"meter","pointId":"pb","categoryId":"water","spaceId":"s","nativeSpaceId":"s"])
    exercise(query.set("perArea",true),rs)
  }

  Void testCompatibleSourceUnitConversionMatchesOriginalLeafOrder()
  {exercise(query,records,false,false,"Wh")}

  Void test82SourcesRetainFullMonthlyReportAndBoundedEvidence()
  {
    start:=DateTime.fromIso("2026-01-01T00:00:00Z");end:=start+1000hr
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"g","kind":"group"]]
    samples:=[Str:Obj?][,]
    for(i:=0;i<1000;i++) samples.add(["ts":(start+Duration(i*1hr.ticks)).toIso,"value":1f])
    whole:=[Str:Obj?][,]
    for(i:=0;i<82;i++)
    {
      rs.add(["id":"m$i","kind":"meter","pointId":"p$i","parentId":"g","categoryId":"c"])
      whole.add(["pointId":"p$i","mode":"interval","unit":"kWh","samples":samples])
    }
    q:=Str:Obj?["kind":"profile","nodeIds":["g"],"from":start.toIso,"to":end.toIso,"asOf":end.toIso,"tz":"UTC","period":"month","metric":"energy"]
    expected:=EnerCubixEngine.report(q,rs,whole)
    budget:=EnerCubixStreamBudget();state:=EnerCubixPreparedOwner(budget.state);output:=EnerCubixPreparedOwner(budget.state)
    ctx:=EnerCubixContext(rs,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(state);ctx.orderWarnings
    report:=EnerCubixReport(ctx,q,start,end,"profile","month","energy",state)
    consumer:=EnerCubixReportConsumer(ctx,report,[report.openLine("g","c")],start,end,"month",state,output)
    read:=|Dict p,Span span,|HisItem| sink|
    {
      n:=((span.start-start).ticks/1hr.ticks).max(0);ts:=start+Duration(n*1hr.ticks)
      while(ts<span.end && ts<=end) {if(ts>=span.start) sink(HisItem(ts,Number(1)));ts+=1hr}
    }
    sources:=EnerCubixCockpitStream[,]
    for(i:=0;i<82;i++)
    {
      point:=Etc.makeDict(["id":Ref("p$i"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])
      sources.add(EnerCubixCockpitStream.openCursor(point,null,start,end,q,rs,budget,read,ctx))
    }
    retained:=0
    for(i:=0;i<1000;i++)
    {
      finish:=start+Duration((i+1)*1hr.ticks);sources.each |source| {source.advance(finish)}
      EnerCubixCockpitStream.withFrames(sources,budget.state) |histories,frame| {consumer.addFrame(histories,frame)}
      if(i==0) retained=state.entries
      else verifyEq(state.entries,retained)
    }
    actual:=consumer.finish
    ["summary","series","rows","warnings"].each |key| {verifyEq(actual[key],expected[key],key)}
    a:=(Map)actual["extra"];e:=(Map)expected["extra"]
    verifyEq(a["usageCoverage"],e["usageCoverage"])
    known:=(Map)a["knownUsage"];verifyEq(((List)known["sourceUsage"]).size,1000)
    verifyEq(known["sourceUsageRowCount"],82000);verifyEq(known["sourceUsageTruncated"],true)
    verifyEq(budget.state.unprepared.val,0);verify(budget.state.peak.val<200000)
    echo("FULL_REPORT_82 "+budget.evidence.toStr+" state="+budget.state.evidence.toStr)
    sources.each |source| {source.close};state.close
    verifyEq(actual["summary"],expected["summary"]);verifyEq(budget.state.temporary.val,output.entries)
    output.close;verify(actual.isEmpty);verifyEq(budget.state.temporary.val,0)
  }

  private Void exercise(Str:Obj? q,[Str:Obj?][] rs,Bool failFinish := false,Bool empty := false,Str sourceUnit := "kWh")
  {
    inputBefore:=rs.toStr
    points:=Str:Dict[:]
    ["pt","pa","pb"].each |id| {points[id]=Etc.makeDict(["id":Ref(id),"his":Marker.val,"hisTotalized":Marker.val,"unit":sourceUnit,"tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":Etc.makeDict(["defNull":Marker.val])])}
    cfg:=Etc.makeDict(["defNull":Marker.val]);configs:=Str:Dict[:];points.each |p,id| {configs[id]=cfg}
    read:=|Dict p,Span span,|HisItem| sink|
    {
      if(empty) return
      values:=p.id.id == "pt" ? Obj?[0,10000000000000000f,10000000000000000f,10000000000000002f,10000000000000004f] :
        (p.id.id == "pa" ? Obj?[0,10,NA.val,30,40] : Obj?[0,20,40,60,80])
      values.each |value,i| {ts:=at+Duration(i*1hr.ticks);if(ts>=span.start && ts<span.end) sink(HisItem(ts,value is Int ? Number((Int)value) : (value is Float ? Number((Float)value) : value)))}
    }
    whole:=EnerCubixCockpitStream.prepare(q,rs,points,configs,read,EnerCubixStreamBudget())
    expected:=EnerCubixEngine.report(q,rs,whole)
    budget:=EnerCubixStreamBudget();state:=EnerCubixPreparedOwner(budget.state);output:=EnerCubixPreparedOwner(budget.state)
    dimension:=EnerCubixDimension("space",rs,true)
    ctx:=EnerCubixContext(dimension.records,[Str:Obj?][,],TimeZone.utc,dimension);ctx.useOwner(state);ctx.orderWarnings
    report:=EnerCubixReport(ctx,q,at,at+4hr,q["kind"].toStr,"month",q["metric"].toStr,state)
    cursors:=EnerCubixLineCursor[,]
    EnerCubixMath.strings(q["nodeIds"]).each |id| {ctx.categories(id).each |category| {cursors.add(report.openLine(id,category))}}
    consumer:=EnerCubixReportConsumer(ctx,report,cursors,at,at+4hr,"month",state,output)
    sources:=EnerCubixCockpitStream[,]
    points.keys.sort.each |id| {sources.add(EnerCubixCockpitStream.openCursor(points[id],configs[id],at,at+4hr,q,rs,budget,read,ctx))}
    for(i:=0;i<4;i++)
    {
      end:=at+Duration((i+1)*1hr.ticks);sources.each |source| {source.advance(end)}
      EnerCubixCockpitStream.withFrames(sources,budget.state) |histories,frame| {consumer.addFrame(histories,frame)}
      verify(ctx.byPoint.isEmpty)
    }
    if(failFinish)
    {
      peer:=EnerCubixPreparedOwner(budget.state);peer.hold(budget.state.remaining);held:=peer.entries
      verifyErr(EnerCubixHttpErr#) {consumer.finish}
      verifyErr(EnerCubixHttpErr#) {consumer.finish}
      sources.each |source| {source.close};state.close;output.close
      verifyEq(budget.state.temporary.val,held);peer.close;verifyEq(budget.state.temporary.val,0)
      verifyEq(rs.toStr,inputBefore);return
    }
    actual:=consumer.finish
    label:=q["kind"].toStr
    ["summary","series","rows","warnings"].each |key| {verifyEq(actual[key],expected[key],"$label : $key")}
    a:=(Map)actual["extra"];e:=(Map)expected["extra"]
    e.keys.findAll |key| {key != "knownUsage"}.each |key| {verifyEq(a[key],e[key],"$label : extra/$key")}
    actualKnown:=((Map)a["knownUsage"]).dup;expectedKnown:=((Map)e["knownUsage"]).dup
    if(expectedKnown.containsKey("sourceUsageCaptureId"))
    {verify(actualKnown["sourceUsageCaptureId"] is Str);actualKnown.remove("sourceUsageCaptureId");expectedKnown.remove("sourceUsageCaptureId")}
    verifyEq(actualKnown,expectedKnown)
    verifyEq(budget.state.unprepared.val,0)
    cursors.each |cursor| {verify(cursor.line.ticks.isEmpty)}
    escapedRows:=(List)actual["rows"];escapedRow:=(Map)escapedRows.first
    sources.each |source| {source.close};state.close
    verifyEq(actual["summary"],expected["summary"])
    verifyEq(budget.state.temporary.val,output.entries)
    output.close;verify(actual.isEmpty);verify(escapedRows.isEmpty);verify(escapedRow.isEmpty)
    verifyEq(rs.toStr,inputBefore);verifyEq(budget.state.temporary.val,0)
    verifyErr(ArgErr#) {consumer.finish}
  }

  private [Str:Obj?][] records()
  {
    [["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space","nativeSourceKind":"site","area":100f],
     ["id":"t","kind":"totalMeter","pointId":"pt","categoryId":"c","spaceId":"s","nativeSpaceId":"s","area":100f],
     ["id":"a","kind":"meter","pointId":"pa","categoryId":"c","spaceId":"s","nativeSpaceId":"s","meterParentId":"t","area":10f],
     ["id":"b","kind":"meter","pointId":"pb","categoryId":"c","spaceId":"s","nativeSpaceId":"s","meterParentId":"t","area":20f]]
  }
  private Str:Obj? query() {["kind":"profile","nodeIds":["s","a"],"from":at.toIso,"to":(at+4hr).toIso,"asOf":(at+4hr).toIso,"tz":"UTC","period":"month","metric":"energy","dimension":"space","spaceSource":"fin"]}
  private DateTime at() {DateTime.fromIso("2026-01-31T23:00:00Z")}
}

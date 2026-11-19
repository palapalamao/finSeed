using haystack

** Real report leaf math over simultaneous borrowed primary-source frames.
** Controlled data only; no native FIN or complete nine-module acceptance.
class FinEnergyCockpitGroupFrameTest : Test
{
  Void testScopeAndSelectionKeepDifferentOriginalFloatReductionTrees()
  {
    q:=query(2);rs:=records(2);budget:=FinEnergyStreamBudget()
    owner:=FinEnergyPreparedOwner(budget.state);ctx:=FinEnergyContext(rs,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    report:=FinEnergyReport(ctx,q,at,at+2hr,"profile","day","energy");line:=report.openLine("g","c")
    scope:=FinEnergyLineFold(line.line,"value",owner)
    a:=FinEnergyValueFold.strict(owner);b:=FinEnergyValueFold.strict(owner)
    read:=|Dict p,Span span,|HisItem| sink|
    {
      values:=p.id.id == "p0" ? [10000000000000000f,1f,0f] : [2f,0f,0f]
      if(at>=span.start && at<span.end) sink(HisItem(at,Number(0)))
      values.each |value,i| {ts:=at+Duration((i+1)*1hr.ticks);if(ts>=span.start && ts<span.end) sink(HisItem(ts,Number(value)))}
    }
    cursors:=FinEnergyCockpitStream[,]
    (0..1).each |i| {cursors.add(FinEnergyCockpitStream.openCursor(point(i),null,at,at+2hr,q,rs,budget,read,ctx))}
    FinEnergyHistoryData? escaped
    for(i:=0;i<2;i++)
    {
      end:=at+Duration((i+1)*1hr.ticks);cursors.each |cursor| {cursor.advance(end)}
      FinEnergyCockpitStream.withFrames(cursors,budget.state) |histories,frame|
      {
        report.beginFrame(frame,histories);escaped=histories["p0"]
        scope.add(line.next)
        a.add(ctx.node("m0","c",end-1hr,end));b.add(ctx.node("m1","c",end-1hr,end))
      }
      verify(ctx.byPoint.isEmpty);verifyErr(ArgErr#) {escaped.read(end-1hr,end)}
    }
    verify(line.finish.ticks.isEmpty)
    verifyEq(scope.finish.value,10000000000000004f)
    verifyEq(FinEnergyValue.sum([a.finish,b.finish]).value,10000000000000002f)
    verifyEq(scope.finish.sources,["p0","p1"]);verifyEq(budget.state.unprepared.val,0)
    cursors.each |cursor| {cursor.close};owner.close
    verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,0)
  }

  Void test82SourcesAnd1000HoursUseActualScopeLeafAndOwnedFolds()
  {
    q:=query(1000);rs:=records(82);end:=at+1000hr;budget:=FinEnergyStreamBudget()
    owner:=FinEnergyPreparedOwner(budget.state);ctx:=FinEnergyContext(rs,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    report:=FinEnergyReport(ctx,q,at,end,"profile","day","energy");line:=report.openLine("g","c")
    output:=FinEnergyPreparedOwner(budget.state)
    scope:=FinEnergyPeriodConsumer(line.line,at,end,"month",owner,output);meters:=FinEnergyValueFold[,]
    cursors:=FinEnergyCockpitStream[,]
    read:=|Dict p,Span span,|HisItem| sink|
    {
      n:=((span.start-at).ticks/1hr.ticks).max(0);ts:=at+Duration(n*1hr.ticks)
      while(ts<span.end && ts<=end) {if(ts>=span.start) sink(HisItem(ts,Number(1)));n++;ts+=1hr}
    }
    for(i:=0;i<82;i++)
    {
      meters.add(FinEnergyValueFold.strict(owner))
      cursors.add(FinEnergyCockpitStream.openCursor(point(i),null,at,end,q,rs,budget,read,ctx))
    }
    retained:=0
    for(i:=0;i<1000;i++)
    {
      finish:=at+Duration((i+1)*1hr.ticks);cursors.each |cursor| {cursor.advance(finish)}
      FinEnergyCockpitStream.withFrames(cursors,budget.state) |histories,frame|
      {
        report.beginFrame(frame,histories);scope.add(line.next)
        meters.each |fold,j| {fold.add(ctx.node("m$j","c",finish-1hr,finish))}
      }
      if(i == 0) retained=owner.entries
      else verifyEq(owner.entries,retained)
      verify(ctx.byPoint.isEmpty)
    }
    scope.finish
    verify(line.finish.ticks.isEmpty);verifyEq(scope.total("value").value,82000f)
    verifyEq(scope.periods.size,2)
    verifyEq(((FinEnergyValue)scope.periods.first["value"]).value,61008f)
    verifyEq(((FinEnergyValue)scope.periods.last["value"]).value,20992f)
    meters.each |fold| {verifyEq(fold.finish.value,1000f)}
    verifyEq(budget.state.unprepared.val,0);verify(budget.state.peak.val<200000)
    verifyEq(budget.logicalHours,82000)
    echo("GROUP_FRAME_82 "+budget.evidence.toStr+" state="+budget.state.evidence.toStr)
    cursors.each |cursor| {cursor.close};owner.close
    verifyEq(scope.total("value").value,82000f)
    verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,output.entries)
    output.close;verifyEq(budget.state.temporary.val,0)
  }

  Void testCleanedNaPeriodsAndCoverageMatchWholeReportWithoutPromotion()
  {
    q:=query(4);rs:=records(2);end:=at+4hr;cfg:=Etc.makeDict(["defNull":Marker.val])
    points:=Str:Dict[:]
    (0..1).each |i| {points["p$i"]=Etc.makeDict(["id":Ref("p$i"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"finEnergyCleanHis","hisFuncConfig":cfg])}
    read:=|Dict p,Span span,|HisItem| sink|
    {
      values:=p.id.id == "p0" ? Obj?[0,10,NA.val,30,40] : Obj?[0,20,40,60,80]
      values.each |value,i| {ts:=at+Duration(i*1hr.ticks);if(ts>=span.start && ts<span.end) sink(HisItem(ts,value is Int ? Number((Int)value) : value))}
    }
    oracle:=FinEnergyEngine.report(q,rs,FinEnergyCockpitStream.prepare(q,rs,points,["p0":cfg,"p1":cfg],read,FinEnergyStreamBudget()))
    budget:=FinEnergyStreamBudget();owner:=FinEnergyPreparedOwner(budget.state);output:=FinEnergyPreparedOwner(budget.state)
    ctx:=FinEnergyContext(rs,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    report:=FinEnergyReport(ctx,q,at,end,"profile","day","energy");cursor:=report.openLine("g","c")
    consumer:=FinEnergyPeriodConsumer(cursor.line,at,end,"day",owner,output)
    coverage:=FinEnergyCoverageFold(["p0","p1"],at,end,owner)
    known:=(FinEnergyContext)FinEnergyReport#.field("knownCtx").get(report)
    streams:=FinEnergyCockpitStream[,]
    points.keys.sort.each |id| {streams.add(FinEnergyCockpitStream.openCursor(points[id],cfg,at,end,q,rs,budget,read,ctx))}
    for(i:=0;i<4;i++)
    {
      finish:=at+Duration((i+1)*1hr.ticks);streams.each |source| {source.advance(finish)}
      FinEnergyCockpitStream.withFrames(streams,budget.state) |histories,frame|
      {report.beginFrame(frame,histories);consumer.add(cursor.next);coverage.addFrame(known.knownReads.vals,frame)}
    }
    consumer.finish;cursor.finish
    expected:=FinEnergyMath.maps(FinEnergyMath.maps(oracle["series"]).first["points"]).first
    strict:=(FinEnergyValue)consumer.periods.first["value"];observed:=(FinEnergyValue)consumer.periods.first["known"]
    verifyEq(strict.value,expected["value"]);verifyEq(strict.quality,expected["quality"]);verifyEq(strict.sources,expected["sourceIds"])
    verifyEq(observed.value,expected["knownValue"]);verifyEq(observed.quality,expected["knownQuality"])
    verifyNull(consumer.total("value").value);verifyEq(consumer.total("known").value,100f)
    expectedCoverage:=FinEnergyMath.maps(((Map)oracle["extra"])["usageCoverage"]).first
    coverage.finish.each |value,key| {verifyEq(value,expectedCoverage[key])}
    verifyEq(budget.nativeReads,2);verifyEq(budget.scanned,10);verifyEq(budget.state.unprepared.val,0)
    streams.each |source| {source.close};owner.close
    verifyEq(consumer.total("known").value,100f);output.close;verifyEq(budget.state.temporary.val,0)
  }

  Void testGroupFailureDropsContextsBeforeReleasingSourcesAndPreservesPeer()
  {
    q:=query(2);rs:=records(2);budget:=FinEnergyStreamBudget();budget.state.holdOwned(13)
    owner:=FinEnergyPreparedOwner(budget.state);ctx:=FinEnergyContext(rs,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    cursors:=FinEnergyCockpitStream[,]
    read:=|Dict p,Span span,|HisItem| sink| {(0..2).each |i| {ts:=at+Duration(i*1hr.ticks);if(ts>=span.start && ts<span.end) sink(HisItem(ts,Number(1)))}}
    (0..1).each |i| {cursors.add(FinEnergyCockpitStream.openCursor(point(i),null,at,at+2hr,q,rs,budget,read,ctx))}
    cursors.each |cursor| {cursor.advance(at+1hr)}
    verifyErr(ArgErr#) {FinEnergyCockpitStream.withFrames([cursors.first,cursors.first],budget.state) |hs,frame| {fail("duplicate sources")}}
    FinEnergyHistoryData? escaped
    verifyErr(IOErr#)
    {
      FinEnergyCockpitStream.withFrames(cursors,budget.state) |hs,frame|
      {ctx.beginFrame(frame,hs);escaped=hs["p0"];ctx.node("g","c",at,at+1hr);throw IOErr("controlled consumer failure")}
    }
    verify(ctx.byPoint.isEmpty);verifyErr(ArgErr#) {escaped.read(at,at+1hr)}
    cursors.each |cursor| {cursor.close};owner.close
    verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,13)
    budget.state.releaseTemporary(13)
  }

  Void testInvalidPlanningOrTimezoneDoesNotKeepCatalogReservation()
  {
    q:=query(2);rs:=records(2);budget:=FinEnergyStreamBudget()
    read:=|Dict p,Span span,|HisItem| sink| {}
    unowned:=FinEnergyContext(rs,[Str:Obj?][,],TimeZone.utc)
    verifyErr(ArgErr#) {invalid:=FinEnergyCockpitStream.openCursor(point(0),null,at,at+2hr,q,rs,budget,read,unowned)}
    verifyEq(budget.state.temporary.val,0)
    bad:=Etc.makeDict(Etc.dictToMap(point(0)).set("tz","Not_A_Time_Zone"))
    verifyErr(ParseErr#) {invalid:=FinEnergyCockpitStream.openCursor(bad,null,at,at+2hr,q,rs,budget,read)}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.activeCursors,0)
  }

  Void testDifferentWatermarksRejectBeforeBorrowingAndCanThenAlign()
  {
    q:=query(2);rs:=records(2);budget:=FinEnergyStreamBudget()
    read:=|Dict p,Span span,|HisItem| sink| {(0..2).each |i| {ts:=at+Duration(i*1hr.ticks);if(ts>=span.start && ts<span.end) sink(HisItem(ts,Number(1)))}}
    a:=FinEnergyCockpitStream.openCursor(point(0),null,at,at+2hr,q,rs,budget,read)
    b:=FinEnergyCockpitStream.openCursor(point(1),null,at,at+2hr,q,rs,budget,read)
    a.advance(at+1hr);b.advance(at+2hr)
    verifyErr(ArgErr#) {FinEnergyCockpitStream.withFrames([a,b],budget.state) |hs,owner| {fail("different watermarks")}}
    a.advance(at+2hr)
    FinEnergyCockpitStream.withFrames([a,b],budget.state) |hs,owner|
    {verifyEq(hs["p0"].read(at,at+1hr).value,1f);verifyEq(hs["p1"].read(at+1hr,at+2hr).value,1f)}
    a.close;b.close;verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }

  private [Str:Obj?][] records(Int count)
  {
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"g","kind":"group"]]
    for(i:=0;i<count;i++) rs.add(["id":"m$i","kind":"meter","pointId":"p$i","parentId":"g","categoryId":"c"])
    return rs
  }
  private Dict point(Int i) {Etc.makeDict(["id":Ref("p$i"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])}
  private Str:Obj? query(Int hours) {["kind":"profile","nodeIds":["g"],"from":at.toIso,"to":(at+Duration(hours*1hr.ticks)).toIso,"asOf":(at+Duration(hours*1hr.ticks)).toIso,"tz":"UTC","period":"day","metric":"energy"]}
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

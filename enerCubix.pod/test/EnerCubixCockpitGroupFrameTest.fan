using haystack

** Real report leaf math over simultaneous borrowed primary-source frames.
** Controlled data only; no native FIN or complete nine-module acceptance.
class EnerCubixCockpitGroupFrameTest : Test
{
  Void testScopeAndSelectionKeepDifferentOriginalFloatReductionTrees()
  {
    q:=query(2);rs:=records(2);budget:=EnerCubixStreamBudget()
    owner:=EnerCubixPreparedOwner(budget.state);ctx:=EnerCubixContext(rs,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    report:=EnerCubixReport(ctx,q,at,at+2hr,"profile","day","energy");line:=report.openLine("g","c")
    scope:=EnerCubixLineFold(line.line,"value",owner)
    a:=EnerCubixValueFold.strict(owner);b:=EnerCubixValueFold.strict(owner)
    read:=|Dict p,Span span,|HisItem| sink|
    {
      values:=p.id.id == "p0" ? [10000000000000000f,1f,0f] : [2f,0f,0f]
      if(at>=span.start && at<span.end) sink(HisItem(at,Number(0)))
      values.each |value,i| {ts:=at+Duration((i+1)*1hr.ticks);if(ts>=span.start && ts<span.end) sink(HisItem(ts,Number(value)))}
    }
    cursors:=EnerCubixCockpitStream[,]
    (0..1).each |i| {cursors.add(EnerCubixCockpitStream.openCursor(point(i),null,at,at+2hr,q,rs,budget,read,ctx))}
    EnerCubixHistoryData? escaped
    for(i:=0;i<2;i++)
    {
      end:=at+Duration((i+1)*1hr.ticks);cursors.each |cursor| {cursor.advance(end)}
      EnerCubixCockpitStream.withFrames(cursors,budget.state) |histories,frame|
      {
        report.beginFrame(frame,histories);escaped=histories["p0"]
        scope.add(line.next)
        a.add(ctx.node("m0","c",end-1hr,end));b.add(ctx.node("m1","c",end-1hr,end))
      }
      verify(ctx.byPoint.isEmpty);verifyErr(ArgErr#) {escaped.read(end-1hr,end)}
    }
    verify(line.finish.ticks.isEmpty)
    verifyEq(scope.finish.value,10000000000000004f)
    verifyEq(EnerCubixValue.sum([a.finish,b.finish]).value,10000000000000002f)
    verifyEq(scope.finish.sources,["p0","p1"]);verifyEq(budget.state.unprepared.val,0)
    cursors.each |cursor| {cursor.close};owner.close
    verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,0)
  }

  Void test82SourcesAnd1000HoursUseActualScopeLeafAndOwnedFolds()
  {
    q:=query(1000);rs:=records(82);end:=at+1000hr;budget:=EnerCubixStreamBudget()
    owner:=EnerCubixPreparedOwner(budget.state);ctx:=EnerCubixContext(rs,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    report:=EnerCubixReport(ctx,q,at,end,"profile","day","energy");line:=report.openLine("g","c")
    scope:=EnerCubixLineFold(line.line,"value",owner);meters:=EnerCubixValueFold[,]
    cursors:=EnerCubixCockpitStream[,]
    read:=|Dict p,Span span,|HisItem| sink|
    {
      n:=((span.start-at).ticks/1hr.ticks).max(0);ts:=at+Duration(n*1hr.ticks)
      while(ts<span.end && ts<=end) {if(ts>=span.start) sink(HisItem(ts,Number(1)));n++;ts+=1hr}
    }
    for(i:=0;i<82;i++)
    {
      meters.add(EnerCubixValueFold.strict(owner))
      cursors.add(EnerCubixCockpitStream.openCursor(point(i),null,at,end,q,rs,budget,read,ctx))
    }
    retained:=0
    for(i:=0;i<1000;i++)
    {
      finish:=at+Duration((i+1)*1hr.ticks);cursors.each |cursor| {cursor.advance(finish)}
      EnerCubixCockpitStream.withFrames(cursors,budget.state) |histories,frame|
      {
        report.beginFrame(frame,histories);scope.add(line.next)
        meters.each |fold,j| {fold.add(ctx.node("m$j","c",finish-1hr,finish))}
      }
      if(i == 0) retained=owner.entries
      else verifyEq(owner.entries,retained)
      verify(ctx.byPoint.isEmpty)
    }
    verify(line.finish.ticks.isEmpty);verifyEq(scope.finish.value,82000f)
    meters.each |fold| {verifyEq(fold.finish.value,1000f)}
    verifyEq(budget.state.unprepared.val,0);verify(budget.state.peak.val<200000)
    echo("GROUP_FRAME_82 "+budget.evidence.toStr+" state="+budget.state.evidence.toStr)
    cursors.each |cursor| {cursor.close};owner.close
    verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,0)
  }

  Void testGroupFailureDropsContextsBeforeReleasingSourcesAndPreservesPeer()
  {
    q:=query(2);rs:=records(2);budget:=EnerCubixStreamBudget();budget.state.holdOwned(13)
    owner:=EnerCubixPreparedOwner(budget.state);ctx:=EnerCubixContext(rs,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    cursors:=EnerCubixCockpitStream[,]
    read:=|Dict p,Span span,|HisItem| sink| {(0..2).each |i| {ts:=at+Duration(i*1hr.ticks);if(ts>=span.start && ts<span.end) sink(HisItem(ts,Number(1)))}}
    (0..1).each |i| {cursors.add(EnerCubixCockpitStream.openCursor(point(i),null,at,at+2hr,q,rs,budget,read,ctx))}
    cursors.each |cursor| {cursor.advance(at+1hr)}
    verifyErr(ArgErr#) {EnerCubixCockpitStream.withFrames([cursors.first,cursors.first],budget.state) |hs,frame| {fail("duplicate sources")}}
    EnerCubixHistoryData? escaped
    verifyErr(IOErr#)
    {
      EnerCubixCockpitStream.withFrames(cursors,budget.state) |hs,frame|
      {ctx.beginFrame(frame,hs);escaped=hs["p0"];ctx.node("g","c",at,at+1hr);throw IOErr("controlled consumer failure")}
    }
    verify(ctx.byPoint.isEmpty);verifyErr(ArgErr#) {escaped.read(at,at+1hr)}
    cursors.each |cursor| {cursor.close};owner.close
    verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,13)
    budget.state.releaseTemporary(13)
  }

  Void testInvalidPlanningOrTimezoneDoesNotKeepCatalogReservation()
  {
    q:=query(2);rs:=records(2);budget:=EnerCubixStreamBudget()
    read:=|Dict p,Span span,|HisItem| sink| {}
    unowned:=EnerCubixContext(rs,[Str:Obj?][,],TimeZone.utc)
    verifyErr(ArgErr#) {invalid:=EnerCubixCockpitStream.openCursor(point(0),null,at,at+2hr,q,rs,budget,read,unowned)}
    verifyEq(budget.state.temporary.val,0)
    bad:=Etc.makeDict(Etc.dictToMap(point(0)).set("tz","Not_A_Time_Zone"))
    verifyErr(ParseErr#) {invalid:=EnerCubixCockpitStream.openCursor(bad,null,at,at+2hr,q,rs,budget,read)}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.activeCursors,0)
  }

  Void testDifferentWatermarksRejectBeforeBorrowingAndCanThenAlign()
  {
    q:=query(2);rs:=records(2);budget:=EnerCubixStreamBudget()
    read:=|Dict p,Span span,|HisItem| sink| {(0..2).each |i| {ts:=at+Duration(i*1hr.ticks);if(ts>=span.start && ts<span.end) sink(HisItem(ts,Number(1)))}}
    a:=EnerCubixCockpitStream.openCursor(point(0),null,at,at+2hr,q,rs,budget,read)
    b:=EnerCubixCockpitStream.openCursor(point(1),null,at,at+2hr,q,rs,budget,read)
    a.advance(at+1hr);b.advance(at+2hr)
    verifyErr(ArgErr#) {EnerCubixCockpitStream.withFrames([a,b],budget.state) |hs,owner| {fail("different watermarks")}}
    a.advance(at+2hr)
    EnerCubixCockpitStream.withFrames([a,b],budget.state) |hs,owner|
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

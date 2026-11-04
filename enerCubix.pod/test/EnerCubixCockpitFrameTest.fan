using haystack
using concurrent

** Private borrowed-frame lifecycle; not a complete cockpit scheduler.
class EnerCubixCockpitFrameTest : Test
{
  Void testDenseCursorLearnsBoundedReadSpanInsteadOfRepeatingTheSplitTree()
  {denseReadSpan(false)}

  Void testLearnedReadSpanPreservesCleaningAcrossSparseAndDenseTransitions()
  {denseReadSpan(true)}

  private Void denseReadSpan(Bool sparseMiddle)
  {
    budget:=EnerCubixStreamBudget();(0..<31).each |i| {budget.openCursor("peer$i")}
    end:=at+30day;p:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"])
    cfg:=sparseMiddle ? Etc.makeDict(["defNull":Marker.val]) : null
    if(cfg!=null) p=Etc.makeDict(Etc.dictToMap(p).set("hisFunc","enerCubixCleanHis").set("hisFuncConfig",cfg))
    q:=Str:Obj?["from":at.toIso,"to":end.toIso,"asOf":end.toIso,"tz":"UTC"]
    EnerCubixCockpitStream? cursor
    try
    {
      cursor=EnerCubixCockpitStream.openCursor(p,cfg,at,end,q,[["id":"m","kind":"meter","categoryId":"c","pointId":"p"]],budget,|Dict point,Span span,|HisItem| sink|
      {
        n:=((span.start-at).ticks/10sec.ticks).max(0);ts:=at+Duration(n*10sec.ticks)
        while(ts<span.end && ts<=end)
        {
          keep:=!sparseMiddle || ts<at+2day || ts>=at+4day || n%360==0
          if(ts>=span.start && keep) sink(HisItem(ts,Number(n)));n++;ts+=10sec
        }
      })
      (0..<720).each |i|
      {
        left:=at+1hr*i;right:=left+1hr;cursor.advance(right)
        cursor.withFrame |h| {verifyEq(h.read(left,right).value,360f);verifyEq(h.knownUsage(left,right,end)["knownValue"],360f)}
      }
      echo("DENSE_CURSOR_READS sparseMiddle="+sparseMiddle+" native="+budget.nativeReads+" scanned="+budget.scanned+" peakBlock="+budget.peakBlock+" peakHeld="+budget.peakHeld)
      if(!sparseMiddle) verify(budget.nativeReads<=320,"a learned dense span must avoid repeatedly rediscovering the same split tree: ${budget.nativeReads}")
      verify(budget.peakBlock<=2083);verify(budget.peakHeld<=200000);verify(budget.state.peak.val<=200000)
    }
    finally {cursor?.close;(0..<31).each |i| {budget.closeCursor("peer$i")}}
    verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,0)
  }

  Void testConsumedHoursReleaseOnlyOwnedPreparedEntries()
  {
    budget:=EnerCubixStreamBudget();budget.cell(17)
    cursor:=open(budget);fold:=EnerCubixValueFold.strict()
    EnerCubixHistoryData? borrowed
    for(i:=1;i<=48;i++)
    {
      end:=at+Duration(i*1hr.ticks);cursor.advance(end)
      cursor.withFrame |h|
      {
        borrowed=h;v:=h.read(end-1hr,end);verifyEq(v.value,1f);fold.add(v)
        verifyEq(h.knownUsage(end-1hr,end,at+48hr)["knownValue"],1f)
      }
      verifyErr(ArgErr#) {borrowed.read(end-1hr,end)}
      verifyErr(ArgErr#) {borrowed.knownUsage(end-1hr,end,at+48hr)}
      verifyEq(budget.cells,23) // 17 external entries +6 source header entries.
    }
    verifyEq(fold.finish.value,48f);verifyEq(fold.finish.sources,["p"])
    verifyErr(ArgErr#) {borrowed.emptyDomain(at,at+1hr)}
    verifyErr(ArgErr#) {borrowed.unpreparedPair(at,at+1hr,null)}
    verifyErr(ArgErr#) {borrowed.constantEnd(at,at+1hr,null)}
    verifyEq(budget.nativeReads,1);verifyEq(budget.scanned,49)
    cursor.close;verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,0)
  }

  Void testConsumerDeadlineStillExpiresAndReleasesFrame()
  {
    clock:=AtomicInt();deadline:=EnerCubixCockpitDeadline(30sec,|->Int| {clock.val})
    budget:=EnerCubixStreamBudget(50000,200000,20000000,30sec,deadline)
    cursor:=open(budget);cursor.advance(at+1hr)
    EnerCubixHistoryData? borrowed
    try
    {
      cursor.withFrame |h| {borrowed=h;clock.val=31sec.ticks}
      fail("Expected shared request deadline")
    }
    catch(EnerCubixHttpErr e) {verifyEq(e.code,"QUERY_TIMEOUT")}
    verifyErr(ArgErr#) {borrowed.read(at,at+1hr)}
    verifyEq(budget.cells,6)
    cursor.close;verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,0)
  }

  Void testRejectedAdmissionDoesNotOwnOrReleaseOtherEntries()
  {
    state:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline())
    state.reserveOwned(199999);state.holdOwned(1)
    verifyErr(EnerCubixHttpErr#) {state.reserveOwned(1)}
    verifyEq(state.prepared.val,199999);verifyEq(state.temporary.val,1)
    verifyErr(EnerCubixHttpErr#) {state.holdOwned(1)}
    verifyEq(state.prepared.val,199999);verifyEq(state.temporary.val,1)
    state.releaseTemporary(1);state.reserveOwned(1)
    verifyEq(state.prepared.val,200000)
    verifyErr(ArgErr#) {state.releasePrepared(200001)}
    verifyErr(ArgErr#) {state.releasePrepared(-1)}
    verifyEq(state.prepared.val,200000)
  }

  Void testConsumerFailureExpiresFrameWithoutResettingPeerOrExternalState()
  {
    budget:=EnerCubixStreamBudget();budget.cell(11)
    first:=open(budget);peer:=open(budget)
    first.advance(at+1hr);peer.advance(at+1hr)
    peerData:=EnerCubixHistoryData(peer.view);during:=0
    EnerCubixHistoryData? borrowed
    verifyErr(IOErr#)
    {
      first.withFrame |h| {borrowed=h;during=budget.cells;throw IOErr("controlled consumer failure")}
    }
    verify(budget.cells < during);verify(budget.cells > 11)
    verifyEq(peerData.read(at,at+1hr).value,1f)
    verifyErr(ArgErr#) {borrowed.read(at,at+1hr)}
    verifyErr(IOErr#) {first.advance(at+2hr)}
    first.close;peer.close
    verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,0)
  }

  Void testFrameAndEscapedPrefixModesCannotBeMixed()
  {
    budget:=EnerCubixStreamBudget();cursor:=open(budget)
    cursor.advance(at+1hr);cursor.view
    verifyErr(ArgErr#) {cursor.withFrame |h| {fail("escaped prefix cannot expire")}}
    cursor.close
    cursor=open(EnerCubixStreamBudget());cursor.advance(at+1hr)
    cursor.withFrame |h| {verifyEq(h.read(at,at+1hr).value,1f)}
    verifyErr(ArgErr#) {cursor.view}
    verifyErr(ArgErr#) {cursor.withFrame |h| {fail("frame already consumed")}}
    cursor.close
  }

  Void test82SourcesConsume1000HoursWithoutRetainingPreparedYear()
  {
    end:=at+Duration(1000*1hr.ticks)
    q:=Str:Obj?["from":at.toIso,"to":end.toIso,"asOf":end.toIso,"tz":"UTC"]
    cfg:=Etc.makeDict(["defNull":Marker.val]);points:=Str:Dict[:];configs:=Str:Dict[:]
    records:=[Str:Obj?][,]
    for(i:=0;i<82;i++)
    {
      id:="p$i"
      points[id]=Etc.makeDict(["id":Ref(id),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":cfg])
      configs[id]=cfg;records.add(["id":"m$i","kind":"meter","categoryId":"c","pointId":id])
    }
    reader:=|Dict p,Span span,|HisItem| sink|
    {
      n:=((span.start-at).ticks/1hr.ticks).max(0);ts:=at+Duration(n*1hr.ticks)
      while(ts < span.end && ts <= end)
      {if(ts >= span.start) sink(HisItem(ts,Number(n)));n++;ts+=1hr}
    }
    // Controlled data exceeds the existing all-at-once representation limit.
    try
    {
      EnerCubixCockpitStream.prepare(q,records,points,configs,reader,EnerCubixStreamBudget(50000,200000,20000000,30min))
      fail("Expected all-at-once prepared limit")
    }
    catch(EnerCubixHttpErr e) {verifyEq(e.code,"PREPARED_READ_LIMIT")}
    budget:=EnerCubixStreamBudget(50000,200000,20000000,30min)
    // External entries and the test consumer's retained scalar/source folds.
    budget.cell(37+82*10+91)
    cursors:=EnerCubixCockpitStream[,];folds:=EnerCubixValueFold[,]
    points.keys.sort.each |id|
    {
      cursors.add(EnerCubixCockpitStream.openCursor(points[id],cfg,at,end,q,records,budget,reader))
      folds.add(EnerCubixValueFold.strict())
    }
    scope:=EnerCubixValueFold.strict();readers:=EnerCubixHistoryData[,]
    for(i:=1;i<=1000;i++)
    {
      b:=at+Duration(i*1hr.ticks);a:=b-1hr
      cursors.each |cursor| {cursor.advance(b)}
      // Bound temporary Value/source arrays and the cross-source reduction.
      budget.state.hold(400)
      try
      {
        frames(cursors,0,readers) |hs|
        {
          values:=hs.map |h,index->EnerCubixValue|
          {v:=h.read(a,b);folds[index].add(v);return v}
          scope.add(EnerCubixValue.sum(values))
        }
      }
      finally {budget.state.releaseTemporary(400)}
      verifyEq(readers.size,0)
      verifyEq(budget.cells,1440)
    }
    verifyEq(scope.finish.value,82000f);verifyEq(scope.finish.sources.size,82)
    folds.each |fold| {verifyEq(fold.finish.value,1000f)}
    verify(budget.state.peak.val < 200000);verify(budget.peakHeld <= 200000)
    verifyEq(budget.state.unprepared.val,0)
    echo("CONTROLLED_FRAME_82 hours=1000 reports=false streaming=${budget.evidence} prepared=${budget.state.evidence}")
    cursors.each |cursor| {cursor.close}
    verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,0)
  }

  private Void frames(EnerCubixCockpitStream[] cursors,Int index,EnerCubixHistoryData[] readers,|EnerCubixHistoryData[]| consume)
  {
    if(index == cursors.size) {consume(readers);return}
    cursors[index].withFrame |h|
    {
      readers.add(h)
      try {frames(cursors,index+1,readers,consume)}
      finally {readers.removeAt(-1)}
    }
  }

  private EnerCubixCockpitStream open(EnerCubixStreamBudget budget)
  {
    cfg:=Etc.makeDict(["defNull":Marker.val])
    p:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":cfg])
    end:=at+48hr;q:=Str:Obj?["from":at.toIso,"to":end.toIso,"asOf":end.toIso,"tz":"UTC"]
    return EnerCubixCockpitStream.openCursor(p,cfg,at,end,q,[["id":"m","kind":"meter","categoryId":"c","pointId":"p"]],budget,|Dict pt,Span span,|HisItem| sink|
    {
      n:=((span.start-at).ticks/1hr.ticks).max(0)
      ts:=at+Duration(n*1hr.ticks)
      while(ts < span.end && ts <= end)
      {if(ts >= span.start) sink(HisItem(ts,Number(n)));n++;ts+=1hr}
    })
  }
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

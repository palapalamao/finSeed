using haystack
using concurrent

** Controlled producer tests, including concurrent raw-buffer admission.
** Not whole annual reports, Context/output ownership or native FIN I/O proof.
class EnerCubixCockpitCursorTest : Test
{
  Void testLazyCleaningDoesNotValidateAnUnreadEmptyConfiguration()
  {
    cfg:=Etc.makeDict(["defNull":Marker.val,"defVal":Number(2)]);budget:=EnerCubixStreamBudget()
    cursor:=EnerCubixCockpitStream.openCursor(point(cfg),cfg,at,at+2hr,query(at+2hr),records,budget,reader(HisItem[,]))
    try
    {
      cursor.advance(at+1hr);verify(cursor.scanComplete)
      verifyNull(EnerCubixCockpitStream#.field("cursorValidatedConfig").get(cursor))
      verifyEq(EnerCubixHistoryData(cursor.view).read(at,at+1hr).quality,"missing")
    }
    finally {cursor.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
  Void testLazyConfigurationAdmissionAndValidationFailuresPreservePeer()
  {
    [false,true].each |invalid|
    {
      cfg:=invalid ? Etc.makeDict(["defNull":Marker.val,"defVal":Number(2)]) : config
      budget:=EnerCubixStreamBudget();peer:=EnerCubixPreparedOwner(budget.state)
      cursor:=EnerCubixCockpitStream.openCursor(point(cfg),cfg,at,at+2hr,query(at+2hr),records,budget,reader([HisItem(at,Number(0)),HisItem(at+1hr,Number(6))]))
      if(invalid) peer.hold(89);else peer.hold(budget.state.remaining-16)
      held:=peer.entries
      try
      {
        if(invalid) verifyErr(ArgErr#) {cursor.advance(at+1hr)}
        else failure(cursor,"PREPARED_READ_LIMIT")
        verifyEq(peer.entries,held);cursor.close;verifyEq(budget.state.temporary.val,held);verifyEq(budget.residentRaw,0)
      }
      finally {cursor.close;peer.close}
      verifyEq(budget.state.temporary.val,0)
    }
  }

  Void testEmptyYearCursorReadsTheWholeDomainWithBoundedAdaptiveSpans()
  {
    end:=at+365day;q:=query(end);budget:=EnerCubixStreamBudget();spans:=Span[,]
    cursor:=EnerCubixCockpitStream.openCursor(point(config),config,at,end,q,records,budget,|Dict p,Span span,|HisItem| sink| {spans.add(span)})
    try
    {
      cursor.advance(at+1hr);verify(cursor.scanComplete)
      verifyEq(spans.first.start,at-1day);verifyEq(spans.last.end,end+1day)
      spans.each |span,i| {verify(span.end>span.start);verify(span.end-span.start<=64day);if(i>0) verifyEq(span.start,spans[i-1].end)}
      verify(budget.nativeReads<=12,"An actually empty year must not require fixed four-day calls: "+budget.nativeReads)
      history:=EnerCubixHistoryData(cursor.view);verifyEq(history.read(at,at+1hr).quality,"missing")
      known:=history.knownUsage(at,at+1hr,end);verifyNull(known["knownValue"]);verifyEq(known["coveredSeconds"],0f)
    }
    finally {cursor.close}
    verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,0)
  }

  Void testUntaggedIntervalCadenceKeepsOriginalFourDayInferenceAndFailure()
  {
    dense:=at+130day;end:=dense+8day;raw:=HisItem[,]
    (0..2).each |i| {raw.add(HisItem(dense+1hr*i,Number(1)))}
    (0..<100).each |i| {raw.add(HisItem(dense+4day+10min*i,Number(1)))}
    p:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisMode":"consumption","unit":"kWh","tz":"UTC"]);q:=query(end)
    original:=EnerCubixCockpitStream.prepare(q,records,["p":p],Str:Dict[:],reader(raw),EnerCubixStreamBudget()).first
    verifyEq(original["quality"],"streamingUnsupportedConfiguration");verifyEq(original["limitation"],"streamingCadenceChanged")
    budget:=EnerCubixStreamBudget();spans:=Span[,]
    cursor:=EnerCubixCockpitStream.openCursor(p,null,at,end,q,records,budget,|Dict point,Span span,|HisItem| sink| {spans.add(span);raw.each |row| {if(row.ts>=span.start && row.ts<span.end) sink(row)}})
    try
    {
      verifyErr(ArgErr#) {cursor.advance(end)}
      verify(spans.all |span| {span.end-span.start<=4day},"Cadence inference must retain the original sample window")
      verify(!cursor.scanComplete)
    }
    finally {cursor.close}
    verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,0)
  }

  Void testFailureAfterEmptyGrowthNeverCertifiesUnreadHistoryOrReleasesPeer()
  {
    end:=at+365day;budget:=EnerCubixStreamBudget();peer:=EnerCubixPreparedOwner(budget.state);peer.hold(88);held:=peer.entries;calls:=0
    cursor:=EnerCubixCockpitStream.openCursor(point(config),config,at,end,query(end),records,budget,|Dict p,Span span,|HisItem| sink| {if(++calls==3) throw IOErr("failure after empty prefix")})
    try
    {
      verifyErr(IOErr#) {cursor.advance(at+1hr)}
      verifyEq(calls,3);verify(!cursor.scanComplete);verifyErr(IOErr#) {cursor.view};verifyEq(peer.entries,held)
      cursor.close;verifyEq(budget.state.temporary.val,held);verifyEq(budget.residentRaw,0)
    }
    finally {cursor.close;peer.close}
    verifyEq(budget.state.temporary.val,0)
  }

  Void testDenseDirtyTailAfterEmptyPrefixKeepsTheOriginalWholeReader()
  {
    dense:=at+130day;end:=dense+4hr;raw:=HisItem[,]
    (0..240).each |i| {value:=i==30 ? NA.val : (i==31 ? null : Number(i<60 ? i : i-60));raw.add(HisItem(dense+1min*i,value))}
    [TimeZone.utc,TimeZone("New_York")].each |tz|
    {
      q:=query(end).set("tz",tz.name);cfg:=config
      p:=Etc.makeDict(Etc.dictToMap(point(cfg)).setAll(["tz":tz.name,"hisStart":end+100day]))
      whole:=EnerCubixHistoryData(EnerCubixCockpitStream.prepare(q,records,["p":p],["p":cfg],reader(raw),EnerCubixStreamBudget(31)).first)
      budget:=EnerCubixStreamBudget(31);cursor:=EnerCubixCockpitStream.openCursor(p,cfg,at,end,q,records,budget,reader(raw))
      try
      {
        (0..<4).each |i|
        {
          a:=dense+1hr*i;b:=a+1hr;cursor.advance(b)
          actual:=EnerCubixHistoryData(cursor.view);x:=actual.read(a,b);y:=whole.read(a,b)
          verifyEq(x.value,y.value);verifyEq(x.quality,y.quality);verifyEq(x.sources,y.sources)
          av:=actual.knownUsage(a,b,end);ev:=whole.knownUsage(a,b,end)
          ["knownValue","knownValueType","knownQuality","coveredSeconds","intervalCount","intervalStart","intervalEnd"].each |k| {verifyEq(av[k],ev[k],k)}
        }
        verifyEq(cursor.watermark,end);verify(budget.peakBlock<=31);verify(budget.peakHeld<=200000);verify(budget.state.peak.val<=200000)
      }
      finally {cursor.close}
      verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,0)
    }
  }

  Void testLongGapClosesCurrentHourWithoutPreparingFutureYear()
  {
    end:=DateTime.fromIso("2026-11-02T00:00:00Z");september:=DateTime.fromIso("2026-09-01T00:00:00Z")
    raw:=[HisItem(at,Number(0)),HisItem(september,Number(14))]
    cfg:=config;q:=query(end);budget:=EnerCubixStreamBudget()
    cursor:=open(q,raw,cfg,budget)
    cursor.advance(at+1hr)
    verifyEq(cursor.watermark,at+1hr);verifyEq(cursor.scanComplete,false)
    h:=EnerCubixHistoryData(cursor.view)
    verifyEq(h.read(at,at+1hr).quality,"incompleteInterval")
    known:=h.knownUsage(at,at+1hr,end)
    verifyEq(known["knownValue"],14f);verifyEq(known["coveredSeconds"],(september-at).ticks.toFloat/1sec.ticks.toFloat)
    verifyEq(h.read(at+48hr,at+49hr).quality,"streamingReadNotPrepared")
    verify(budget.materializedPairs <= 1);verify(budget.cells < 100)
    cursor.close
  }

  Void testDirtyCursorHoursEqualExistingWholeSourceReader()
  {
    end:=at+8hr;q:=query(end)
    raw:=[HisItem(at,Number(90)),HisItem(at+20min,NA.val),HisItem(at+30min,null),HisItem(at+40min,Number(1)),HisItem(at+50min,Number(8)),HisItem(at+90min,Number(9)),HisItem(at+4hr,Number(2)),HisItem(at+5hr,Number(3)),HisItem(end,Number(4))]
    [config,Etc.makeDict(["defNull":Marker.val,"removeNA":Marker.val,"deltaMax":Number(5),"timeMax":Number.makeDuration(1hr)]),Etc.makeDict(["defVal":Number(2),"deltaMax":Number(5)]),Etc.makeDict(["hisTotalizedRollover":Number(100),"deltaMax":Number(5)])].each |cfg|
    {
      p:=point(cfg)
      whole:=EnerCubixHistoryData(EnerCubixCockpitStream.prepare(q,records,["p":p],["p":cfg],reader(raw),EnerCubixStreamBudget()).first)
      verifyEq(whole.quality,"cleaned")
      cursor:=open(q,raw,cfg,EnerCubixStreamBudget())
      (1..8).each |i|
      {
        finish:=at+Duration(i*1hr.ticks);start:=finish-1hr;cursor.advance(finish)
        h:=EnerCubixHistoryData(cursor.view)
        a:=h.read(start,finish);b:=whole.read(start,finish)
        verifyEq(a.value,b.value);verifyEq(a.quality,b.quality);verifyEq(a.sources,b.sources)
        x:=h.knownUsage(start,finish,end);y:=whole.knownUsage(start,finish,end)
        ["knownValue","knownValueType","knownQuality","coveredSeconds","intervalCount","intervalStart","intervalEnd"].each |k| {verifyEq(x[k],y[k],k)}
      }
      verify(cursor.scanComplete);cursor.close
    }
  }

  Void testOnlyRealPlannedEofCanFinalizeEmptyHour()
  {
    q:=query(at+2hr);budget:=EnerCubixStreamBudget()
    cursor:=open(q,HisItem[,],config,budget);cursor.advance(at+1hr)
    verify(cursor.scanComplete);verifyEq(cursor.watermark,at+1hr)
    h:=EnerCubixHistoryData(cursor.view)
    verifyEq(h.read(at,at+1hr).quality,"missing")
    verifyEq(h.read(at-2hr,at-1hr).quality,"streamingReadNotPrepared")
    cursor.close
    point:=point(config);failed:=EnerCubixCockpitStream.openCursor(point,config,at,at+2hr,q,records,EnerCubixStreamBudget(),|Dict p,Span span,|HisItem| sink| {throw IOErr("controlled read failure")})
    verifyErr(IOErr#) {failed.advance(at+1hr)}
    verifyEq(failed.scanComplete,false);verifyErr(IOErr#) {failed.view}
    failed.close
  }

  Void testConcurrentCursorsShareAndReleaseRawOwnership()
  {
    budget:=EnerCubixStreamBudget();q:=query(at+2hr)
    first:=open(q,HisItem[,],config,budget)
    second:=open(q,HisItem[,],config,budget)
    verifyEq(budget.activeCursors,2)
    verifyErr(ArgErr#) {EnerCubixCockpitStream.prepare(q,records,["p":point(config)],["p":config],reader(HisItem[,]),budget)}
    first.close;verifyEq(budget.activeCursors,1)
    second.close;verifyEq(budget.activeCursors,0)
    verifyEq(budget.residentRaw,0)
    verifyEq(budget.nativeReads,0)
  }

  Void test82CursorsAdmitBoundedChunksBeforeConsumingFirstHour()
  {
    end:=at+4day;q:=query(end);budget:=EnerCubixStreamBudget()
    cursors:=EnerCubixCockpitStream[,]
    for(i:=0;i<82;i++)
    {
      p:=Etc.makeDict(Etc.dictToMap(point(config)).set("id",Ref("p$i")))
      cursors.add(EnerCubixCockpitStream.openCursor(p,config,at,end,q,records,budget,|Dict pt,Span span,|HisItem| sink|
      {
        n:=((span.start-at).ticks/1min.ticks).max(0)
        ts:=at+Duration(n*1min.ticks)
        while(ts < span.end && ts <= end)
        {if(ts >= span.start) sink(HisItem(ts,Number(n)));n++;ts+=1min}
      }))
    }
    verifyEq(budget.activeCursors,82)
    cursors.each |cursor|
    {
      cursor.advance(at+1hr)
      h:=EnerCubixHistoryData(cursor.view)
      verifyEq(h.read(at,at+1hr).value,60f)
      verifyEq(h.knownUsage(at,at+1hr,end)["knownValue"],60f)
      verifyEq(cursor.watermark,at+1hr)
    }
    verify(budget.nativeReads > 82);verify(budget.residentRaw > 0)
    verify(budget.peakHeld <= budget.heldLimit)
    verify(budget.state.peak.val <= 200000)
    echo("CONTROLLED_CURSOR_82 firstHourOnly=true residentRaw=${budget.residentRaw} streaming=${budget.evidence} prepared=${budget.state.evidence}")
    cursors.each |cursor| {cursor.close}
    verifyEq(budget.residentRaw,0);verifyEq(budget.activeCursors,0)
    verifyEq(budget.state.temporary.val,0)
  }

  Void testFailedPeerDoesNotReleaseAnotherCursorsTail()
  {
    q:=query(at+4hr);raw:=HisItem[,]
    for(i:=0;i<=240;i++) raw.add(HisItem(at+Duration(i*1min.ticks),Number(i)))
    budget:=EnerCubixStreamBudget();first:=open(q,raw,config,budget)
    first.advance(at+1hr)
    held:=budget.residentRaw;temporary:=budget.state.temporary.val
    verify(held > 0);verify(temporary > 0)
    failed:=EnerCubixCockpitStream.openCursor(point(config),config,at,at+4hr,q,records,budget,|Dict p,Span span,|HisItem| sink| {throw IOErr("controlled peer failure")})
    verifyErr(IOErr#) {failed.advance(at+1hr)}
    failed.close
    verifyEq(budget.residentRaw,held);verifyEq(budget.state.temporary.val,temporary)
    first.advance(at+2hr)
    verifyEq(EnerCubixHistoryData(first.view).read(at+1hr,at+2hr).value,60f)
    first.close
    verifyEq(budget.residentRaw,0);verifyEq(budget.state.temporary.val,0)
  }

  Void testBufferedDetailsRemainChargedUntilConsumedOrClosed()
  {
    end:=at+8hr;q:=query(end);raw:=HisItem[,]
    for(i:=0;i<=480;i++) raw.add(HisItem(at+Duration(i*1min.ticks),Number(i)))
    budget:=EnerCubixStreamBudget();cursor:=open(q,raw,config,budget)
    cursor.advance(at+1hr)
    h:=EnerCubixHistoryData(cursor.view)
    verifyEq(h.read(at,at+1hr).value,60f)
    verify(budget.state.temporary.val > 0)
    verify(budget.state.peak.val > budget.cells)
    charged:=budget.cells;cursor.close
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.cells,charged)
    cursor.close;verifyEq(budget.cells,charged)
    verifyErr(ArgErr#) {cursor.view}
    verifyErr(ArgErr#) {budget.state.releaseTemporary(1)}
    verifyErr(ArgErr#) {budget.state.releaseTemporary(-1)}
  }

  Void testFailedOpenDoesNotRetainAdmission()
  {
    budget:=EnerCubixStreamBudget();q:=query(at+2hr)
    invalid:=Etc.makeDict(Etc.dictToMap(point(config)).set("tz","Not_A_Timezone"))
    verifyErr(ParseErr#) {EnerCubixCockpitStream.openCursor(invalid,config,at,at+2hr,q,records,budget,reader(HisItem[,]))}
    verifyEq(budget.cursorActive,false)
    cursor:=open(q,HisItem[,],config,budget);cursor.close
    verifyEq(budget.nativeReads,0)
  }

  Void testDeadlineAndCapacityFailuresCannotFinalizeEmptyHistory()
  {
    q:=query(at+2hr);clock:=AtomicInt()
    deadline:=EnerCubixCockpitDeadline(30sec,|->Int| {clock.val})
    budget:=EnerCubixStreamBudget(50000,200000,20000000,30sec,deadline)
    cursor:=EnerCubixCockpitStream.openCursor(point(config),config,at,at+2hr,q,records,budget,|Dict p,Span span,|HisItem| sink|
    {
      clock.val=31sec.ticks
      sink(HisItem(at,Number(0)));sink(HisItem(at+1hr,Number(1)))
    })
    failure(cursor,"QUERY_TIMEOUT");cursor.close
    verifyEq(budget.state.temporary.val,0)
    budget=EnerCubixStreamBudget(50000,2)
    cursor=open(q,[HisItem(at,Number(0))],config,budget)
    failure(cursor,"HISTORY_MEMORY_LIMIT");cursor.close
    budget=EnerCubixStreamBudget();budget.cell(200000)
    verifyEq(budget.state.remaining,0)
    try {cursor=open(q,[HisItem(at,Number(0))],config,budget);fail("Catalog admission must fail before opening a source")}
    catch(EnerCubixHttpErr e) {verifyEq(e.code,"PREPARED_READ_LIMIT")}
    verifyEq(budget.cells,200000);verifyEq(budget.state.temporary.val,0);verifyEq(budget.activeCursors,0)
    budget=EnerCubixStreamBudget(50000,200000,1)
    cursor=open(q,[HisItem(at,Number(0)),HisItem(at+1hr,Number(1))],config,budget)
    failure(cursor,"HISTORY_SCAN_LIMIT");cursor.close
  }

  Void testRawModesAndDensitySplitsKeepHourlyOracle()
  {
    end:=at+4hr;q:=query(end);raw:=HisItem[,]
    for(i:=0;i<=1100;i++) raw.add(HisItem(at-1hr+7sec+Duration(i*20sec.ticks),Number(i < 500 ? i : i-500)))
    [Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"]),Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(20sec),"unit":"kWh","tz":"UTC"])].each |p|
    {
      whole:=EnerCubixHistoryData(EnerCubixCockpitStream.prepare(q,records,["p":p],Str:Dict[:],reader(raw),EnerCubixStreamBudget(31)).first)
      budget:=EnerCubixStreamBudget(31)
      cursor:=EnerCubixCockpitStream.openCursor(p,null,at,end,q,records,budget,reader(raw))
      for(i:=1;i<=4;i++)
      {
        b:=at+Duration(i*1hr.ticks);a:=b-1hr;cursor.advance(b)
        actual:=EnerCubixHistoryData(cursor.view)
        x:=actual.read(a,b);y:=whole.read(a,b)
        verifyEq(x.value,y.value);verifyEq(x.quality,y.quality);verifyEq(x.sources,y.sources)
        known:=actual.knownUsage(a,b,end);expected:=whole.knownUsage(a,b,end)
        ["knownValue","knownValueType","knownQuality","coveredSeconds","intervalCount","intervalStart","intervalEnd"].each |k| {verifyEq(known[k],expected[k],k)}
      }
      verify(budget.nativeReads > 1);verify(budget.peakBlock <= 31)
      cursor.close
    }
  }

  private Void failure(EnerCubixCockpitStream cursor,Str code)
  {
    try {cursor.advance(at+1hr);fail("Expected controlled failure")}
    catch(EnerCubixHttpErr e) {verifyEq(e.code,code)}
    verifyEq(cursor.scanComplete,false)
    verifyErr(EnerCubixHttpErr#) {cursor.view}
  }

  private EnerCubixCockpitStream open(Str:Obj? q,HisItem[] raw,Dict cfg,EnerCubixStreamBudget budget)
  {EnerCubixCockpitStream.openCursor(point(cfg),cfg,at,DateTime.fromIso(q["to"].toStr),q,records,budget,reader(raw))}
  private |Dict,Span,|HisItem|->Void| reader(HisItem[] raw)
  {|Dict p,Span span,|HisItem| sink| {raw.each |row| {if(row.ts >= span.start && row.ts < span.end) sink(row)}}}
  private Dict point(Dict cfg) {Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":cfg])}
  private Dict config() {Etc.makeDict(["defNull":Marker.val,"deltaMin":Number(0),"deltaMax":Number(10000)])}
  private Str:Obj? query(DateTime end) {["from":at.toIso,"to":end.toIso,"asOf":end.toIso,"tz":"UTC","_cockpitReadRanges":[["from":at.toIso,"to":end.toIso]]]}
  private [Str:Obj?][] records() {[["id":"m","kind":"meter","categoryId":"c","pointId":"p"]]}
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

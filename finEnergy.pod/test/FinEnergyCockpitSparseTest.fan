using haystack
using util
using concurrent

class FinEnergyCockpitSparseTest : Test
{
  Void testPointWindowsUnionDoesNotDuplicateOrFillGap()
  {
    r:=Str:Obj?["id":"m","kind":"meter","pointId":"p","categoryId":"c"]
    ctx:=FinEnergyContext([r],[Str:Obj?][,],TimeZone.utc)
    q:=Str:Obj?["from":at.toIso,"to":(at+4hr).toIso,"asOf":(at+10day).toIso,"nodeIds":["m"],"categoryIds":["c"]]
    comparison:=Str:Obj?["mode":"custom","referenceRange":["from":(at+2hr).toIso,"to":(at+6hr).toIso]]
    plan:=FinEnergyCockpitMetrics.plan(q,comparison,ctx,null,false,true,[r,r])
    verifyEq(plan.size,1);verifyEq(plan.first["from"],at.toIso);verifyEq(plan.first["to"],(at+6hr).toIso)
    comparison["referenceRange"]=["from":(at+2day).toIso,"to":(at+3day).toIso]
    plan=FinEnergyCockpitMetrics.plan(q,comparison,ctx,null,false,true,[r])
    verifyEq(plan.size,2);verifyEq(plan.first["to"],(at+4hr).toIso);verifyEq(plan.last["from"],(at+2day).toIso)
  }

  Void test82PrimaryPointsAnnualConfirmedEmptyDomainIsSparse()
  {
    points:=Str:Dict[:];records:=[Str:Obj?][,]
    (0..<82).each |i| {id:="p:zeda:r:"+(0x7f000000+i).toHex(8)+"-1a000001";points[id]=point(id);records.add(["id":"m"+i,"kind":"meter","pointId":id])}
    before:=DateTime("2024-01-01T00:00:00Z UTC");to:=at+365day
    q:=Str:Obj?["from":at.toIso,"to":to.toIso,"asOf":to.toIso,"_cockpitRanges":[["from":before.toIso,"to":at.toIso,"pointIds":points.keys],["from":at.toIso,"to":to.toIso,"pointIds":points.keys]],"_cockpitReadRanges":[["from":before.toIso,"to":at.toIso],["from":at.toIso,"to":to.toIso]]]
    budget:=FinEnergyStreamBudget()
    began:=Duration.nowTicks
    histories:=FinEnergyCockpitStream.prepare(q,records,points,Str:Dict[:],|Dict p,Span span,|HisItem| sink| {},budget)
    verifyEq(histories.size,82);verify(budget.cells < 1000)
    histories.each |h|
    {
      history:=FinEnergyHistoryData(h);a:=DateTime.fromIso(h["_cockpitFrom"].toStr)
      verifyEq(history.read(a,a+1hr).quality,"missing")
      known:=history.knownUsage(a,a+1hr,DateTime.fromIso(h["_cockpitTo"].toStr));verifyEq(known["coveredSeconds"],0f);verifyEq(known["intervalCount"],0)
      verifyEq(history.read(a+11min,a+22min).quality,"streamingReadNotPrepared")
    }
    echo("SPARSE82 elapsedMs=${(Duration.nowTicks-began)/1ms.ticks} evidence=${budget.evidence}")
  }

  Void testCumulativeGapKeepsStrictEstimatedAndKnownWholeInterval()
  {
    p:=point("p");raw:=[HisItem(at,Number(0)),HisItem(at+2hr,Number(20))]
    q:=Str:Obj?["from":at.toIso,"to":(at+4hr).toIso,"asOf":(at+4hr).toIso,"_cockpitReadRanges":[["from":at.toIso,"to":(at+4hr).toIso],["from":at.toIso,"to":(at+90min).toIso],["from":at.toIso,"to":(at+2hr).toIso]]]
    actual:=FinEnergyHistoryData(FinEnergyCockpitStream.prepare(q,[["id":"m","kind":"meter","pointId":"p"]],["p":p],Str:Dict[:],|Dict point,Span span,|HisItem| sink| {raw.each |v| {if(v.ts>=span.start && v.ts<span.end) sink(v)}},FinEnergyStreamBudget()).first)
    expected:=FinEnergyHistoryData(FinEnergyHistory.normalize(p,raw,at,at+4hr))
    (0..<4).each |i|
    {
      a:=at+Duration(i*1hr.ticks);b:=a+1hr
      verifyEq(actual.read(a,b).value,expected.read(a,b).value);verifyEq(actual.read(a,b).quality,expected.read(a,b).quality)
      [at+90min,at+2hr,at+4hr].each |qEnd|
      {
        one:=actual.knownUsage(a,b,qEnd);two:=expected.knownUsage(a,b,qEnd)
        one.remove("value");two.remove("value");verifyEq(one,two)
      }
    }
    verifyEq(actual.read(at,at+1hr).value,10f);verifyEq(actual.read(at,at+1hr).quality,"estimated")
    verifyEq(actual.knownUsage(at,at+1hr,at+2hr)["knownValue"],20f)
    verifyEq(actual.knownUsage(at+1hr,at+2hr,at+2hr)["knownValue"],null)
  }

  Void testClosedLongIntervalKeepsIncompleteQualityWithoutDenseNullHours()
  {
    finish:=at+300day
    raw:=[HisItem(at,Number(10)),HisItem(finish,Number(24))]
    cfg:=Etc.makeDict(["defNull":Marker.val,"deltaMin":Number(0),"deltaMax":Number(10000)])
    points:=Str:Dict[:];configs:=Str:Dict[:];records:=[Str:Obj?][,]
    (0..<82).each |i|
    {
      id:="p"+i
      points[id]=Etc.makeDict(Etc.dictToMap(point(id)).set("hisFunc","finEnergyCleanHis"));configs[id]=cfg
      records.add(["id":"m"+i,"kind":"meter","pointId":id])
    }
    q:=Str:Obj?["from":at.toIso,"to":(finish+2hr).toIso,"asOf":(finish+2hr).toIso]
    budget:=FinEnergyStreamBudget()
    hs:=FinEnergyCockpitStream.prepare(q,records,points,configs,|Dict p,Span span,|HisItem| sink|
      {raw.each |r| {if(r.ts>=span.start && r.ts<span.end) sink(r)}},budget)
    verify(budget.cells < 3000)
    actual:=FinEnergyHistoryData(hs.first)
    whole:=FinEnergyHistory.normalizeClean(points["p0"],FinEnergyCleaning.clean(points["p0"],raw,cfg),at,finish+2hr)
    expected:=FinEnergyHistoryData(whole)
    (0..<300*24+2).each |i|
    {
      a:=at+Duration(i*1hr.ticks);b:=a+1hr
      one:=actual.read(a,b);two:=expected.read(a,b)
      verifyEq(one.value,two.value);verifyEq(one.quality,two.quality)
      av:=actual.knownUsage(a,b,finish+2hr);ev:=expected.knownUsage(a,b,finish+2hr)
      av.remove("value");ev.remove("value");verifyEq(av,ev)
    }
    verifyEq(actual.read(at+1hr,at+2hr).quality,"incompleteInterval")
    verifyEq(actual.knownUsage(at,at+1hr,finish+2hr)["knownValue"],14f)
    verifyEq(actual.knownUsage(at,at+1hr,finish+2hr)["coveredSeconds"],300day.toSec.toFloat)
    verifyNull(actual.knownUsage(at+1hr,at+2hr,finish+2hr)["knownValue"])
    verifyNull(actual.read(finish+1hr,finish+2hr).value)
    verifyEq(actual.read(finish+1hr,finish+2hr).quality,"missing")
    verifyEq(actual.read(finish+2hr,finish+3hr).quality,"streamingReadNotPrepared")
    verifyEq(budget.state.unprepared.val,1)
  }

  Void testPreparedStorageEqualityAndNextEntry()
  {
    budget:=FinEnergyStreamBudget();budget.cells=199998
    budget.cell;verifyEq(budget.cells,199999);budget.cell;verifyEq(budget.cells,200000)
    try {budget.cell;fail("Must reject the next substantive entry")}
    catch(FinEnergyHttpErr e) {verifyEq(e.code,"PREPARED_READ_LIMIT")}
  }

  Void testCombinedPreparedAndCacheLimitAndMonotonicDeadline()
  {
    state:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline())
    state.reserve(199999);state.hold(1);verifyEq(state.peak.val,200000)
    verifyErr(FinEnergyHttpErr#) |->Void| {state.hold(1)}
    ticks:=AtomicInt();deadline:=FinEnergyCockpitDeadline(1sec,|->Int| {ticks.val})
    ticks.val=1sec.ticks;deadline.check
    ticks.increment
    try {deadline.check;fail("Monotonic total request deadline must reject the next tick")}
    catch(FinEnergyHttpErr e) {verifyEq(e.status,504);verifyEq(e.code,"QUERY_TIMEOUT")}
    clock:=AtomicInt()
    codecDeadline:=FinEnergyCockpitDeadline(1ms,|->Int| {clock.addAndGet(1ms.ticks)})
    verifyErr(FinEnergyHttpErr#) |->Void| {FinEnergyCockpitPayload.encode(["reports":(0..<3000).map |i->Obj?| {["n":i]}],codecDeadline)}
  }

  Void testSparsePrefixesTailsAndCleaningRetainCompleteOracleMetadata()
  {
    first:=at+30day
    configs:=[
      Str:Obj?[:],
      Str:Obj?["defNull":Marker.val,"timeMax":Number.makeDuration(30min)],
      Str:Obj?["defVal":Number(2),"deltaMax":Number(10)],
      Str:Obj?["defVal":NA.val,"deltaMax":Number(10)],
      Str:Obj?["defNull":Marker.val,"removeNA":Marker.val],
      Str:Obj?["hisTotalizedRollover":Number(100),"deltaMax":Number(20)]
    ]
    configs.each |params|
    {
      cfg:=Etc.makeDict(params);p:=point("p")
      if(!params.isEmpty) p=Etc.makeDict(Etc.dictToMap(p).set("hisFunc","finEnergyCleanHis").set("hisFuncConfig",cfg))
      raw:=[HisItem(first,Number(90)),HisItem(first+2hr,Number(95)),HisItem(first+3hr,NA.val),HisItem(first+4hr,Number(5)),HisItem(first+5hr,Number(5)),HisItem(first+6hr,null),HisItem(first+7hr,Number(7))]
      q:=Str:Obj?["from":(at+17sec).toIso,"to":(at+365day+23sec).toIso,"asOf":(at+365day+23sec).toIso]
      q["_cockpitReadRanges"]=[q.dup]
      b:=FinEnergyStreamBudget()
      hs:=FinEnergyCockpitStream.prepare(q,[["id":"m","kind":"meter","pointId":"p"]],["p":p],params.isEmpty ? Str:Dict[:] : ["p":cfg],|Dict pt,Span span,|HisItem| sink| {raw.each |row| {if(row.ts>=span.start && row.ts<span.end) sink(row)}},b)
      actual:=FinEnergyHistoryData(hs.first)
      whole:=params.isEmpty ? FinEnergyHistory.normalize(p,raw,at,at+366day) : FinEnergyHistory.normalizeClean(p,FinEnergyCleaning.clean(p,raw,cfg),at,at+366day)
      expected:=FinEnergyHistoryData(whole)
      [at,at+15day,first-1hr,first,first+1hr,first+2hr,first+3hr,first+4hr,first+5hr,first+6hr,first+7hr,first+8hr,at+364day].each |a|
      {
        end:=a+1hr
        verifyEq(actual.read(a,end).value,expected.read(a,end).value)
        verifyEq(actual.read(a,end).quality,expected.read(a,end).quality)
        known:=actual.knownUsage(a,end,DateTime.fromIso(q["to"].toStr));oracle:=expected.knownUsage(a,end,DateTime.fromIso(q["to"].toStr))
        av:=(FinEnergyValue)known.remove("value");ev:=(FinEnergyValue)oracle.remove("value")
        verifyEq(av.value,ev.value);verifyEq(av.quality,ev.quality);verifyEq(av.sources,ev.sources);verifyEq(known,oracle)
      }
      verify(b.cells < 200)
      verifyEq(hs.first["sourceLastObservedAt"],(first+7hr).toIso)
      if(!params.isEmpty)
      {
        clean:=(Map)hs.first["cleaning"]
        verifyEq(clean["inputCount"],raw.size)
        verifyEq(clean["parameters"],FinEnergyCleaning.jsonConfig(cfg))
      }
    }
  }

  Void testPreparedReportsPreserveAuthoritativeCoverageAndKnownTotals()
  {
    raw:=[HisItem(at+2day,Number(0)),HisItem(at+2day+2hr,Number(20)),HisItem(at+2day+3hr,Number(20))]
    p:=point("p");finish:=at+5day
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c","tariffId":"t"],["id":"t","kind":"tariff","mode":"monthlyBlock","blocks":[["limit":10f,"rate":1f],["rate":2f]]]]
    q:=Str:Obj?["kind":"profile","nodeIds":["m"],"categoryIds":["c"],"period":"day","metric":"energy","from":at.toIso,"to":finish.toIso,"asOf":finish.toIso,"_cockpitCategoryId":"c"]
    budget:=FinEnergyStreamBudget()
    hs:=FinEnergyCockpitStream.prepare(q,rs,["p":p],Str:Dict[:],|Dict point,Span span,|HisItem| sink| {raw.each |v| {if(v.ts>=span.start && v.ts<span.end) sink(v)}},budget)
    ["energy","cost"].each |metric|
    {
      query:=q.dup.set("metric",metric)
      actual:=FinEnergyHistory.report(query,rs,hs)
      oracle:=FinEnergyHistory.report(query,rs,[FinEnergyHistory.normalize(p,raw,at,finish)])
      verifyEq(actual["summary"],oracle["summary"]);verifyEq(actual["series"],oracle["series"])
      verifyEq(((Map)actual["extra"])["usageCoverage"],((Map)oracle["extra"])["usageCoverage"])
      evidence:=(Map)((Map)actual["extra"])["knownUsage"]
      verifyEq(evidence["sourceUsageTruncated"],true);verifyNull(evidence["sourceUsageRowCount"])
      verifyEq(budget.state.temporary.val,0)
    }
    verify(budget.state.peakTemporary.val < 1000)
    echo("SPARSE_REPORT evidence=${budget.state.evidence}")
  }

  Void testFastEmptyIsEquivalentForMissingTariffAreaNaAndRealZero()
  {
    finish:=at+3day;p:=point("p")
    ["empty","zero","na"].each |mode|
    {
      raw:=HisItem[,]
      if(mode != "empty") (0..72).each |i| {raw.add(HisItem(at+Duration(i*1hr.ticks),mode == "zero" ? Number(0) : NA.val))}
      [false,true].each |hasTariff|
      {
        rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c","area":10f,"subcategoryId":"sub"],["id":"sub","kind":"subcategory","co2Factor":0.5f]]
        if(hasTariff) {rs[1]["tariffId"]="t";rs.add(["id":"t","kind":"tariff","mode":"flat","rate":2f])}
        q:=Str:Obj?["kind":"profile","nodeIds":["m"],"categoryIds":["c"],"period":"day","from":at.toIso,"to":finish.toIso,"asOf":finish.toIso]
        budget:=FinEnergyStreamBudget()
        hs:=FinEnergyCockpitStream.prepare(q,rs,["p":p],Str:Dict[:],|Dict pt,Span span,|HisItem| sink| {raw.each |row| {if(row.ts>=span.start && row.ts<span.end) sink(row)}},budget)
        ["energy","cost","co2","coal"].each |metric|
        {
          [false,true].each |perArea|
          {
            request:=q.dup.setAll(["metric":metric,"perArea":perArea])
            actual:=FinEnergyHistory.report(request,rs,hs);oracle:=FinEnergyHistory.report(request,rs,[FinEnergyHistory.normalize(p,raw,at,finish)])
            verifyEq(actual["summary"],oracle["summary"]);verifyEq(actual["series"],oracle["series"])
            verifyEq(((Map)actual["extra"])["usageCoverage"],((Map)oracle["extra"])["usageCoverage"])
          }
        }
        if(mode == "empty") verify(budget.state.contextEmptyHits.val > 0)
        else verifyEq(budget.state.contextEmptyHits.val,0)
      }
    }
  }

  Void testCalculationTimeoutPropagatesWithoutKpiDowngrade()
  {
    ticks:=AtomicInt();deadline:=FinEnergyCockpitDeadline(1sec,|->Int| {ticks.val})
    q:=Str:Obj?["schemaVersion":1,"requestId":"deadline","reportScope":["dimension":"metering","nodeIds":["m"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"hour","from":at.toIso,"to":(at+2hr).toIso],"asOf":(at+2hr).toIso,"comparison":["mode":"none"],"modules":["kpis","trend"]]
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c"]]
    loadCalls:=0;projectionCalls:=0
    try
    {
      FinEnergyCockpit.execute(q,rs,|rq,records->[Str:Obj?][]| {loadCalls++;return [["pointId":"p","unit":"kWh","mode":"interval","samples":[["ts":at.toIso,"value":1f]]]]},"test",TimeZone.utc,at+2hr,false,null,null,|rq,records,hs->Str:Obj?| {projectionCalls++;ticks.val=2sec.ticks;return FinEnergyHistory.report(rq,records,hs)},deadline)
      fail("Timeout is global")
    }
    catch(FinEnergyHttpErr e) {verifyEq(e.code,"QUERY_TIMEOUT");verifyEq(e.status,504)}
    verifyEq(loadCalls,1);verifyEq(projectionCalls,1)
  }

  Void testFutureUnpreparedAndUnloadedStayDistinctFromConfirmedEmpty()
  {
    p:=point("p");finish:=at+2day;cutoff:=at+1day
    q:=Str:Obj?["kind":"profile","nodeIds":["m","unloaded"],"categoryIds":["c"],"period":"hour","from":at.toIso,"to":finish.toIso,"asOf":cutoff.toIso,"_cockpitRanges":[["from":at.toIso,"to":cutoff.toIso,"pointIds":["p"]]]]
    q["_cockpitReadRanges"]=[q.dup]
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c"],["id":"unloaded","kind":"meter","pointId":"not-captured","categoryId":"c"]]
    hs:=FinEnergyCockpitStream.prepare(q,rs,["p":p],Str:Dict[:],|Dict point,Span span,|HisItem| sink| {},FinEnergyStreamBudget())
    rows:=Str:Obj?[:];empty:=FinEnergyHistoryData(["pointId":"p","unit":"kWh","mode":"cumulative"])
    (0..<24).each |i|
    {
      a:=at+Duration(i*1hr.ticks);b:=a+1hr;known:=empty.knownUsage(a,b,cutoff);known.remove("value")
      rows[FinEnergyCockpitStream.key(a,b)]=["strict":["value":null,"quality":"missing"],"known":[cutoff.ticks.toStr:known]]
    }
    dense:=Str:Obj?["pointId":"p","unit":"kWh","mode":"cumulative","quality":"ok","dataCutoff":cutoff.toIso,"_preparedReads":rows]
    ["energy","cost"].each |metric|
    {
      request:=q.dup.set("metric",metric)
      actual:=FinEnergyHistory.report(request,rs,hs);oracle:=FinEnergyHistory.report(request,rs,[dense])
      verifyEq(actual["summary"],oracle["summary"]);verifyEq(actual["series"],oracle["series"])
      verifyEq(((Map)actual["extra"])["usageCoverage"],((Map)oracle["extra"])["usageCoverage"])
    }
    history:=FinEnergyHistoryData(hs.first)
    verifyEq(history.read(at,at+1hr).quality,"missing")
    verifyEq(history.read(cutoff,cutoff+1hr).quality,"streamingReadNotPrepared")
    verifyEq(history.knownUsage(at,at+1hr,finish)["value"]->quality,"streamingReadNotPrepared")
    strictOnly:=FinEnergyHistoryData(["pointId":"p","_preparedReads":[FinEnergyCockpitStream.key(at,at+1hr):["strict":["value":0f,"quality":"ok"]]]])
    verifyEq(strictOnly.unpreparedPair(at,at+1hr,finish),true)
  }

  Void testHistoryFailureAndUnsupportedModeDoNotBecomeEmptyDomains()
  {
    q:=Str:Obj?["from":at.toIso,"to":(at+2hr).toIso,"asOf":(at+2hr).toIso]
    rs:=[Str:Obj?][["id":"m","kind":"meter","pointId":"p"]]
    failed:=FinEnergyCockpitStream.prepare(q,rs,["p":point("p")],Str:Dict[:],|Dict p,Span span,|HisItem| sink| {throw Err("controlled read failure")},FinEnergyStreamBudget()).first
    verifyEq(failed["quality"],"historyReadError");verifyNull(failed["_preparedSparse"])
    rs.first["historyMode"]="cov"
    unsupported:=FinEnergyCockpitStream.prepare(q,rs,["p":point("p")],Str:Dict[:],|Dict p,Span span,|HisItem| sink| {},FinEnergyStreamBudget()).first
    verifyEq(unsupported["quality"],"streamingUnsupportedConfiguration");verifyNull(unsupported["_preparedSparse"])
    rs.first.remove("historyMode")
    verifyErr(FinEnergyHttpErr#) |->Void| {FinEnergyCockpitStream.prepare(q,rs,["p":point("p")],Str:Dict[:],|Dict p,Span span,|HisItem| sink| {throw FinEnergyHttpErr(403,"PERMISSION","controlled")},FinEnergyStreamBudget())}
  }

  private Dict point(Str id) {Etc.makeDict(["id":Ref(id),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"])}
  private DateTime at := DateTime("2025-01-01T00:00:00Z UTC")
}

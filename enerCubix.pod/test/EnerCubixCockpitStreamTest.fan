using haystack
using util

class EnerCubixCockpitStreamTest : Test
{
  Void testExecutableStreamingPathExists()
  { verify(Type.find("enerCubix::EnerCubixCockpitStream",false) != null) }

  Void testCrossBlockCleaningMatchesWholeRange()
  {
    configs:=[
      ["defNull":Marker.val,"deltaMin":Number(0),"deltaMax":Number(5),"timeMax":Number.makeDuration(30sec)],
      ["defVal":Number(2),"deltaMin":Number(0),"deltaMax":Number(5),"timeMax":Number.makeDuration(30sec)],
      ["defVal":NA.val,"deltaMin":Number(0),"deltaMax":Number(5)],
      ["defNull":Marker.val,"removeNA":Marker.val,"deltaMin":Number(0),"deltaMax":Number(5)],
      ["hisTotalizedRollover":Number(100),"deltaMax":Number(5)]
    ]
    // 7 second phase makes source pairs cross hour/tariff/query boundaries.
    raw:=HisItem[,]
    for (i:=0;i<2200;i++)
    {
      if (i >= 701 && i <= 710) continue
      Obj? value:=Number((i%100).toFloat)
      if (i == 499 || i == 500) value=NA.val
      if (i == 1001) value=null
      raw.add(HisItem(at+7sec+Duration(i*10sec.ticks),value))
    }
    configs.each |params|
    {
      cfg:=Etc.makeDict(params)
      p:=point(true,cfg)
      q:=query(at+13sec,at+5hr+23sec)
      oracle:=EnerCubixHistoryData(EnerCubixKnownUsage.clip([EnerCubixHistory.normalizeClean(p,EnerCubixCleaning.clean(p,raw,cfg),at,at+6hr)],at+6hr).first)
      budget:=EnerCubixStreamBudget(500,200000,20000000,30min)
      rows:=prepare(p,cfg,q,raw,budget)
      verifyEq(rows.first["quality"],"cleaned")
      actual:=EnerCubixHistoryData(rows.first)
      for (i:=0;i<6;i++)
      {
        a:=at+Duration(i*1hr.ticks);b:=a+1hr
        compareValue(actual.read(a,b),oracle.read(a,b))
        compareKnown(actual.knownUsage(a,b,at+5hr+23sec),oracle.knownUsage(a,b,at+5hr+23sec))
      }
      a:=at+13sec;b:=at+1hr
      compareValue(actual.read(a,b),oracle.read(a,b))
      compareKnown(actual.knownUsage(a,b,at+5hr+23sec),oracle.knownUsage(a,b,at+5hr+23sec))
      verify(budget.nativeReads > 1)
      verify(budget.peakHeld < 200000)
    }
  }

  Void testCumulativeBoundariesAndResetMatchWholeRange()
  {
    raw:=HisItem[,]
    for (i:=0;i<1500;i++) raw.add(HisItem(at+7sec+Duration(i*10sec.ticks),Number((i < 500 ? i : i-500).toFloat)))
    p:=point(false)
    q:=query(at+17sec,at+3hr+37sec)
    oracle:=EnerCubixHistoryData(EnerCubixHistory.normalize(p,raw,at,at+4hr))
    budget:=EnerCubixStreamBudget(137,200000,20000000,30min)
    actual:=EnerCubixHistoryData(prepare(p,null,q,raw,budget).first)
    for (i:=0;i<4;i++)
    {
      a:=at+Duration(i*1hr.ticks);b:=a+1hr
      compareValue(actual.read(a,b),oracle.read(a,b))
      compareKnown(actual.knownUsage(a,b,at+3hr+37sec),oracle.knownUsage(a,b,at+3hr+37sec))
    }
    compareValue(actual.read(at+17sec,at+1hr),oracle.read(at+17sec,at+1hr))
  }

  Void testAnnualTenSecondCurrentAndReferenceCapacity() {annual(false)}
  Void testManagedAnnualTenSecondCurrentAndReferenceCapacity() {annual(true)}

  private Void annual(Bool clean)
  {
    start:=DateTime("2024-01-01T00:00:00Z UTC")
    finish:=DateTime("2026-01-01T00:00:00Z UTC")
    q:=Str:Obj?["from":start.toIso,"to":finish.toIso,"asOf":finish.toIso,
      "_cockpitReadRanges":[["from":start.toIso,"to":(start+366day).toIso],["from":(start+366day).toIso,"to":finish.toIso]]]
    budget:=EnerCubixStreamBudget(50000,200000,20000000,30min)
    began:=Duration.nowTicks
    cfg:=Etc.makeDict(["defNull":Marker.val,"deltaMin":Number(0),"timeMax":Number.makeDuration(1hr)])
    rows:=EnerCubixCockpitStream.prepare(q,[["kind":"meter","id":"m","pointId":"p"]],["p":point(clean,cfg)],clean ? ["p":cfg] : Str:Dict[:],|Dict p,Span span,|HisItem| sink|
    {
      // Independent closed form source: sample at phase 7, a counter increasing
      // by 1 every 10 seconds. Generate only the requested native block.
      origin:=start-1day+(clean ? 0sec : 7sec)
      n:=((span.start-origin).ticks/10sec.ticks).max(0)
      t:=origin+Duration(n*10sec.ticks)
      while (t < span.end) {if (t >= span.start) sink(HisItem(t,Number(n.toFloat)));n++;t+=10sec}
    },budget)
    verifyEq(rows.first["quality"],clean ? "cleaned" : "ok")
    actual:=EnerCubixHistoryData(rows.first)
    cursor:=start;hours:=0
    // Whole-range independent oracle: each hour has exactly 360 closed source
    // pairs owned by start, with its last pair crossing the display boundary.
    while (cursor < finish)
    {
      end:=cursor+1hr
      strict:=actual.read(cursor,end)
      if (clean) {verifyEq(strict.value,360f);verifyEq(strict.quality,"cleaned")}
      else if (end == finish) {verifyNull(strict.value);verifyEq(strict.quality,"missing")}
      else {verify(strict.value.approx(360f,0.00000001f));verifyEq(strict.quality,"estimated")}
      queryEnd:=cursor < start+366day ? start+366day : finish
      known:=actual.knownUsage(cursor,end,queryEnd)
      expected:=!clean && end == queryEnd ? 359f : 360f
      verifyEq(((EnerCubixValue)known["value"]).value,expected)
      verifyEq(((EnerCubixValue)known["value"]).quality,clean ? "cleaned" : "filtered")
      verifyEq(known["coveredSeconds"],expected*10f)
      verifyEq(known["intervalCount"],expected.toInt)
      cursor=end;hours++
    }
    verify(budget.scanned > 6000000)
    verify(budget.peakHeld <= 200000)
    if (clean) verifyAnnualSnapshot(rows,start+366day,finish,start)
    echo("CAPACITY managed=$clean annual10s+reference hours=$hours elapsedMs=${(Duration.nowTicks-began)/1ms.ticks} evidence=${budget.evidence}")
  }

  Void testTariffBoundariesAndBlockBaselinesMatchWholeRange()
  {
    raw:=HisItem[,]
    for (i:=0;i<3*8640;i++) raw.add(HisItem(at+7sec+Duration(i*10sec.ticks),Number(i.toFloat)))
    p:=point(false)
    configs:=[
      ["mode":"monthlyBlock","blocks":[["limit":10000f,"rate":1f],["rate":3f]]],
      ["mode":"yearlyBlock","blocks":[["limit":10000f,"rate":1f],["rate":3f]]],
      ["mode":"timeOfUse","rate":1f,"rules":[["startHour":1.5f,"endHour":3.25f,"rate":2f]]]
    ]
    configs.each |tariff|
    {
      records:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","categoryId":"c","pointId":"p","tariffId":"t"],tariff.dup.setAll(["id":"t","kind":"tariff"]) ]
      q:=Str:Obj?["kind":"profile","nodeIds":["m"],"categoryIds":["c"],"period":"day","metric":"cost","from":(at+1day+13sec).toIso,"to":(at+2day+4hr+23sec).toIso,"asOf":(at+3day).toIso,"_cockpitRanges":[["from":at.toIso,"to":(at+2day+5hr).toIso,"pointIds":["p"]]]]
      q["_cockpitReadRanges"]=[q.dup]
      actual:=EnerCubixCockpitStream.prepare(q,records,["p":p],Str:Dict[:],|Dict pt,Span span,|HisItem| sink| {raw.each |item| {if (item.ts >= span.start && item.ts < span.end) sink(item)}},EnerCubixStreamBudget(500,200000,20000000,30min))
      expected:=[EnerCubixHistory.normalize(p,raw,at,at+3day)]
      result:=EnerCubixEngine.report(q,records,actual)
      oracle:=EnerCubixEngine.report(q,records,expected)
      verifyEq(result["summary"],oracle["summary"])
      verifyEq(result["series"],oracle["series"])
      verifyEq(((Map)result["extra"])["usageCoverage"],((Map)oracle["extra"])["usageCoverage"])
    }
  }

  Void testExactRawBlockLimitAndRecursiveSplit()
  {
    [50000,50001].each |count|
    {
      budget:=EnerCubixStreamBudget(50000,200000,20000000,30min)
      q:=query(at,at+14hr)
      rows:=EnerCubixCockpitStream.prepare(q,[["kind":"meter","id":"m","pointId":"p"]],["p":point(false)],Str:Dict[:],|Dict pt,Span span,|HisItem| sink|
      {
        for (i:=0;i<count;i++) {t:=at+Duration(i*1sec.ticks);if (t >= span.start && t < span.end) sink(HisItem(t,Number(i.toFloat)))}
      },budget)
      verifyEq(rows.first["quality"],"ok")
      verify(budget.peakBlock <= 50000)
      verify(budget.peakHeld <= 200000)
      if (count == 50000) {verifyEq(budget.nativeReads,1);verifyEq(budget.scanned,50000);verifyEq(budget.peakBlock,50000)}
      else verify(budget.nativeReads > 1)
    }
  }

  Void testBudgetsAcceptEqualityAndRejectNextSample()
  {
    b:=EnerCubixStreamBudget(50000,200000,20000000,30min)
    b.scanned=19999999;b.scan;verifyEq(b.scanned,20000000)
    verifyErr(EnerCubixHttpErr#) |->Void| {b.scan}
    b.hold(200000);verifyEq(b.peakHeld,200000)
    verifyErr(EnerCubixHttpErr#) |->Void| {b.hold(200001)}
    b=EnerCubixStreamBudget(50000,200000,20000000,-1sec)
    verifyErr(EnerCubixHttpErr#) |->Void| {b.check}
    EnerCubixCockpitGate.enter("stream-test","a")
    try
    {
      verifyErr(EnerCubixHttpErr#) |->Void| {EnerCubixCockpitGate.enter("stream-test","a")}
      EnerCubixCockpitGate.enter("stream-test","b")
      try {verifyErr(EnerCubixHttpErr#) |->Void| {EnerCubixCockpitGate.enter("stream-test","c")}}
      finally {EnerCubixCockpitGate.leave("stream-test","b")}
    }
    finally {EnerCubixCockpitGate.leave("stream-test","a")}
    EnerCubixCockpitGate.enter("stream-test","a");EnerCubixCockpitGate.leave("stream-test","a")
  }

  Void testDstGapFoldAndDeclaredIntervalModeMatchOracle()
  {
    tz:=TimeZone("New_York")
    [DateTime("2025-03-09T00:00:00-05:00 New_York"),DateTime("2025-11-02T00:00:00-04:00 New_York")].each |start|
    {
      raw:=HisItem[,]
      for (i:=0;i<1200;i++) raw.add(HisItem(start-1hr+Duration(i*10sec.ticks),Number(1f)))
      p:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(10sec),"unit":"Wh","tz":"New_York"])
      q:=Str:Obj?["tz":"New_York","from":start.toIso,"to":(start+2hr+17sec).toIso,"asOf":(start+3hr).toIso]
      actual:=EnerCubixCockpitStream.prepare(q,[["kind":"meter","id":"m","pointId":"p"]],["p":p],Str:Dict[:],|Dict pt,Span span,|HisItem| sink| {raw.each |item| {if (item.ts >= span.start && item.ts < span.end) sink(item)}},EnerCubixStreamBudget(137,200000,20000000,30min))
      oracle:=EnerCubixHistoryData(EnerCubixHistory.normalize(p,raw,start,start+3hr))
      parsed:=EnerCubixHistoryData(actual.first)
      for (i:=0;i<3;i++)
      {
        a:=start+Duration(i*1hr.ticks); b:=a+1hr
        compareValue(parsed.read(a,b),oracle.read(a,b))
        compareKnown(parsed.knownUsage(a,b,start+2hr+17sec),oracle.knownUsage(a,b,start+2hr+17sec))
      }
      verifyEq(actual.first["unit"],"Wh")
    }
  }

  Void testNativePointTimezoneAndSourceUnitMatchProjectOracle()
  {
    raw:=HisItem[,]
    for (i:=0;i<1100;i++) raw.add(HisItem((at+7sec+Duration(i*10sec.ticks)).toTimeZone(TimeZone("Tokyo")),Number(i.toFloat*1000f,Unit("Wh"))))
    cfg:=Etc.makeDict(["defNull":Marker.val,"deltaMin":Number(0),"deltaMax":Number(2)])
    p:=Etc.makeDict(Etc.dictToMap(point(true,cfg)).set("tz","Tokyo"))
    q:=query(at+13sec,at+2hr+37sec)
    actual:=EnerCubixHistoryData(prepare(p,cfg,q,raw,EnerCubixStreamBudget(137,200000,20000000,30min)).first)
    expected:=EnerCubixHistoryData(EnerCubixHistory.normalizeClean(p,EnerCubixCleaning.clean(p,raw,cfg),at,at+3hr))
    for (i:=0;i<3;i++)
    {
      a:=at+Duration(i*1hr.ticks);b:=a+1hr
      compareValue(actual.read(a,b),expected.read(a,b))
      compareKnown(actual.knownUsage(a,b,at+2hr+37sec),expected.knownUsage(a,b,at+2hr+37sec))
    }
  }

  private Void verifyAnnualSnapshot([Str:Obj?][] histories, DateTime from, DateTime to, DateTime refFrom)
  {
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space","nativeSourceId":"s","nativeLevel":"site"],["id":"m","kind":"meter","spaceId":"s","nativeSpaceId":"s","pointId":"p","categoryId":"c","subcategoryId":"sub","tariffId":"t"],["id":"sub","kind":"subcategory","co2Factor":0.5f],["id":"t","kind":"tariff","mode":"flat","rate":2f,"currency":"CNY"]]
    input:=Str:Obj?["schemaVersion":1,"requestId":"annual-capacity","reportScope":["dimension":"space","nodeIds":["s"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"month","from":from.toIso,"to":to.toIso],"asOf":to.toIso,"comparison":["mode":"custom","from":refFrom.toIso,"to":from.toIso],"modules":["kpis","trend"]]
    calls:=0;began:=Duration.nowTicks
    snapshot:=EnerCubixCockpit.execute(input,rs,|q,records->[Str:Obj?][]| {calls++;return histories},"test",TimeZone.utc,to)
    verifyEq(calls,1)
    energy:=EnerCubixMath.maps(((Map)((Map)((Map)snapshot["modules"])["kpis"])["data"])["values"]).find |v| {v["id"] == "energy"}
    verifyEq(energy["value"],(to-from).ticks.toFloat/10sec.ticks.toFloat)
    bytes:=JsonOutStream.writeJsonToStr(snapshot).toBuf.size
    echo("SNAPSHOT annual+reference bytes=$bytes projectionMs=${(Duration.nowTicks-began)/1ms.ticks}")
    verify(bytes <= 8388608)
    ((Map)snapshot["reports"]).each |report|
    {
      usage:=(Map)((Map)((Map)report)["extra"])["knownUsage"]
      verify(usage["sourceUsageRowCount"] > 1000)
      verifyEq(usage["sourceUsageTruncated"],true)
      verifyEq(usage["truncationReason"],"cockpitEvidenceRowLimit")
      verifyEq(EnerCubixMath.maps(usage["sourceUsage"]).size,1000)
    }
  }

  private Void compareValue(EnerCubixValue actual, EnerCubixValue expected)
  {
    verifyEq(actual.value,expected.value)
    verifyEq(actual.quality,expected.quality)
    verifyEq(actual.valueType,expected.valueType)
    verifyEq(actual.sources,expected.sources)
  }
  private Void compareKnown(Str:Obj? actual, Str:Obj? expected)
  {
    compareValue((EnerCubixValue)actual["value"],(EnerCubixValue)expected["value"])
    ["coveredSeconds","intervalCount","intervalStart","intervalEnd"].each |k| {verifyEq(actual[k],expected[k],k)}
  }
  private [Str:Obj?][] prepare(Dict p, Dict? config, Str:Obj? q, HisItem[] raw, EnerCubixStreamBudget budget)
  {
    return EnerCubixCockpitStream.prepare(q,[["kind":"meter","id":"m","pointId":"p"]],["p":p],config == null ? Str:Dict[:] : ["p":config],|Dict pt,Span span,|HisItem| sink|
    {
      // Include SDK leading/trailing rows deliberately. The block owns [start,end).
      raw.each |item| {if (item.ts >= span.start-10sec && item.ts < span.end+10sec) sink(item)}
    },budget)
  }
  private Str:Obj? query(DateTime a, DateTime b)
  { ["from":a.toIso,"to":b.toIso,"asOf":(at+6hr).toIso,"_cockpitReadRanges":[["from":a.toIso,"to":b.toIso]]] }
  private Dict point(Bool clean, Dict? cfg := null)
  {
    m:=Str:Obj?["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"]
    if (clean) {m["hisFunc"]="enerCubixCleanHis";m["hisFuncConfig"]=cfg}
    return Etc.makeDict(m)
  }
  private DateTime at := DateTime("2025-01-01T00:00:00Z UTC")
}

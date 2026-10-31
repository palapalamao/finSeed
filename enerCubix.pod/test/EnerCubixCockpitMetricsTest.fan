using util

class EnerCubixCockpitMetricsTest : Test
{
  Void testFourMetricsAndIndependentExpectedAmounts()
  {
    r:=run(request,records,histories)
    verifyEq(values(r).map |v->Str| {v["id"].toStr},["energy","cost","auxiliaryEnergy","co2"])
    verifyEq(metric(r,"energy")["value"],100f)
    verifyEq(metric(r,"cost")["value"],200f); verifyEq(metric(r,"cost")["unit"],"CNY")
    verifyEq(metric(r,"auxiliaryEnergy")["value"],8f)
    verifyEq(metric(r,"co2")["value"],70f)
    verifyEq(((Map)metric(r,"energy")["comparison"])["reference"],80f)
    verifyEq(((Map)metric(r,"energy")["comparison"])["changeRate"],25f)
    verifyEq(((Map)metric(r,"cost")["comparison"])["changeRate"],25f)
    verifyEq(((Map)metric(r,"co2")["comparison"])["changeRate"],25f)
    verify(((List)((Map)r["provenance"])["configRefs"]).size >= records.size)
    verify(((List)((Map)r["provenance"])["historyPlan"]).size == 2)
    fixture:=Env.cur.vars["ENERCUBIX_COCKPIT_METRICS_FIXTURE"]
    if (fixture != null) File.os(fixture).out.writeChars(JsonOutStream.writeJsonToStr(r)).close
  }

  Void testMissingZeroPartialAndReplacementReferenceSuppressPercentage()
  {
    ["missing","zero","partial","substituted"].each |mode|
    {
      hs:=histories
      h:=hs.first
      rows:=EnerCubixMath.maps(h["samples"])
      if (mode == "missing") rows=rows.findAll |s| {DateTime.fromIso(s["ts"].toStr) >= at}
      if (mode == "zero") rows.findAll |s| {DateTime.fromIso(s["ts"].toStr) < at}.each |s| {s["value"]=0f}
      if (mode == "partial") rows.removeAt(0)
      if (mode == "substituted") h["quality"]="substituted"
      h["samples"]=rows
      c:=(Map)metric(run(request,records,hs),"energy")["comparison"]
      verifyNull(c["changeRate"],mode)
      if (mode == "zero") {verifyEq(c["reference"],0f); verify(((List)c["reasonCodes"]).contains("ZERO_REFERENCE"))}
      if (mode == "partial") verifyEq(c["reference"],40f)
    }
  }

  Void testAuxiliaryFailureAndAreaFallbackKeepEnergy()
  {
    hs:=histories; hs.last["unit"]="kWh"
    r:=run(request,records,hs)
    verifyEq(metric(r,"energy")["value"],100f); verifyNull(metric(r,"auxiliaryEnergy")["value"])
    q:=request;q.remove("auxiliaryCategoryId")
    rs:=records;rs.find |v| {v["id"] == "s"}["area"]=1000f
    r=run(q,rs,histories)
    verifyEq(metric(r,"areaIntensity")["value"],0.1f)
    verifyEq(metric(r,"areaIntensity")["unit"],"kWh/m²")
    rs.find |v| {v["id"] == "s"}["area"]=0f
    r=run(q,rs,histories)
    verifyNull(metric(r,"areaIntensity")["value"]); verifyEq(metric(r,"energy")["value"],100f)
  }

  Void testBlockCostRequiresEarlierCycleHistoryWithoutChangingEnergyRange()
  {
    q:=request;q["comparison"]=["mode":"none"]
    rs:=records;rs.find |r| {r["id"] == "tariff"}.setAll(["mode":"monthlyBlock","blocks":[["limit":100f,"rate":1f],["limit":null,"rate":2f]]])
    q["time"]=["preset":"custom","period":"hour","from":(at+1hr).toIso,"to":(at+2hr).toIso]
    hs:=histories
    hs.first["samples"]=[["ts":at.toIso,"value":60f],["ts":(at+1hr).toIso,"value":60f]]
    calls:=0
    r:=EnerCubixCockpit.execute(q,rs,|Str:Obj? rq,[Str:Obj?][] recs->[Str:Obj?][]| {calls++;return hs},"test",TimeZone.utc,now,false,|->DateTime| {now})
    verifyEq(calls,1);verifyEq(metric(r,"energy")["value"],60f)
    // October 1 is the cycle start; preceding missing days must not be treated as zero.
    verifyNull(metric(r,"cost")["value"])
    q["time"]=["preset":"custom","period":"hour","from":(cycle+1hr).toIso,"to":(cycle+2hr).toIso]
    hs.first["samples"]=[["ts":cycle.toIso,"value":60f],["ts":(cycle+1hr).toIso,"value":60f]]
    r=run(q,rs,hs);verifyEq(metric(r,"energy")["value"],60f);verifyEq(metric(r,"cost")["value"],80f)
  }

  Void testDifferentCurrenciesDoNotBecomeOneTotal()
  {
    rs:=records
    rs.add(["id":"b","kind":"meter","name":"B","categoryId":"c","spaceId":"s","nativeSpaceId":"s","pointId":"pb","tariffId":"usd"])
    rs.add(["id":"usd","kind":"tariff","mode":"flat","rate":3f,"currency":"USD"])
    hs:=histories.add(["pointId":"pb","unit":"kWh","mode":"interval","samples":[["ts":at.toIso,"value":10f],["ts":(at+1hr).toIso,"value":10f]]])
    r:=run(request,rs,hs)
    verifyEq(metric(r,"energy")["value"],120f);verifyNull(metric(r,"cost")["value"])
    verify(((List)metric(r,"cost")["reasonCodes"]).contains("INCOMPATIBLE_CURRENCY"))
  }

  Void testOneLogicalLoadAndSameFrozenConfigurationForBothPeriods()
  {
    q:=request;rs:=records;hs:=histories;calls:=0
    r:=EnerCubixCockpit.execute(q,rs,|Str:Obj? rq,[Str:Obj?][] recs->[Str:Obj?][]|
    {
      calls++;verify(recs.isImmutable);verify(rq.isImmutable)
      verifyEq(((List)rq["_cockpitRanges"]).size,2)
      verifyEq(EnerCubixMath.strings(rq["_cockpitPointIds"]).sort,["p","pw"])
      rs.find |v| {v["id"] == "tariff"}["rate"]=99f
      return hs
    },"test",TimeZone.utc,now,false,|->DateTime| {now})
    verifyEq(calls,1);verifyEq(metric(r,"cost")["value"],200f)
    verifyEq(((Map)metric(r,"cost")["comparison"])["reference"],160f)
    old:=JsonOutStream.writeJsonToStr(r)
    hs.first["samples"]=[Str:Obj?][,]
    verifyEq(JsonOutStream.writeJsonToStr(r),old)
    later:=run(q,rs,hs)
    verify(r["snapshotId"] != later["snapshotId"])
    verify(((Map)r["provenance"])["configFingerprint"] != ((Map)later["provenance"])["configFingerprint"])
  }

  Void testPresetLeapAndDstExposeActualCalendarCutoff()
  {
    q:=request;q.remove("asOf");q["time"]=["preset":"thisYear","period":"month"];q["comparison"]=["mode":"presetDefault"]
    leap:=DateTime.fromIso("2024-02-29T14:37:23Z")
    r:=EnerCubixCockpit.execute(q,records,|rq,rs->[Str:Obj?][]| {[Str:Obj?][,]},"test",TimeZone.utc,leap,false,|->DateTime| {leap})
    c:=(Map)((Map)r["context"])["comparison"]
    verifyEq(((Map)c["referenceRange"])["to"],"2023-02-28T14:37:23Z")
    verify(((List)c["reasonCodes"]).contains("LEAP_DAY_CLAMPED"))
    verifyEq(c["durationDifferenceSeconds"],86400)
    dst:=DateTime.fromIso("2026-03-08T07:37:23Z")
    q["time"]=["preset":"today","period":"hour"]
    r=EnerCubixCockpit.execute(q,records,|rq,rs->[Str:Obj?][]| {[Str:Obj?][,]},"test",TimeZone("New_York"),dst,false,|->DateTime| {dst})
    c=(Map)((Map)r["context"])["comparison"]
    verifyEq(((Map)c["currentRange"])["to"],"2026-03-08T03:37:23-04:00")
    verifyEq(((Map)c["referenceRange"])["to"],"2026-03-07T03:37:23-05:00")
    verifyEq(c["durationDifferenceSeconds"],-3600)
    verify(((List)c["reasonCodes"]).contains("TIMEZONE_OFFSET_CHANGED"))
  }

  Void testDisjointCalendarReadWindowsAndTrendOnlyNeedsNoBillingContext()
  {
    q:=request;q.remove("asOf");q["time"]=["preset":"thisMonth","period":"day"];q["comparison"]=["mode":"presetDefault"]
    stamp:=DateTime.fromIso("2026-10-30T14:37:23Z")
    calls:=0
    r:=EnerCubixCockpit.execute(q,records,|Str:Obj? rq,[Str:Obj?][] rs->[Str:Obj?][]|
    {
      calls++
      ranges:=EnerCubixMath.maps(rq["_cockpitRanges"])
      verifyEq(ranges.size,2)
      verifyEq(ranges.first["from"],"2025-10-01T00:00:00Z")
      verifyEq(ranges.first["to"],"2025-10-30T14:37:23Z")
      verifyEq(ranges.last["from"],"2026-10-01T00:00:00Z")
      verifyEq(ranges.last["to"],"2026-10-30T14:37:23Z")
      return [Str:Obj?][,]
    },"test",TimeZone.utc,stamp,false,|->DateTime| {stamp})
    verifyEq(calls,1)
    verifyEq(((Map)((Map)r["context"])["comparison"])["from"],"2025-10-01T00:00:00Z")
    q=request;q["modules"]=["trend"];q["comparison"]=["mode":"none"]
    rs:=records;rs.find |v| {v["id"] == "tariff"}["mode"]="yearlyBlock"
    EnerCubixCockpit.execute(q,rs,|Str:Obj? rq,[Str:Obj?][] recs->[Str:Obj?][]|
    {
      plan:=EnerCubixMath.maps(rq["_cockpitRanges"])
      verifyEq(plan.size,1);verifyEq(plan.first["from"],at.toIso)
      verifyEq(EnerCubixMath.strings(rq["_cockpitPointIds"]),["p"])
      return histories
    },"test",TimeZone.utc,now,false,|->DateTime| {now})
  }

  Void testActiveEpisodesCountAcknowledgementDoesNotMeanRecoveryAndConclusionPriority()
  {
    rs:=records;rs.find |r| {r["id"] == "sub"}.remove("co2Factor")
    events:=[Str:Obj?][["id":"e","nodeId":"a","categoryId":"c","state":"acknowledged","nativeActive":true],["id":"hour","episodeId":"e","nodeId":"a","categoryId":"c"],["id":"old","nodeId":"a","categoryId":"c","nativeActive":false],["id":"other","nodeId":"w","categoryId":"water","nativeActive":true]]
    r:=EnerCubixCockpit.execute(request,rs,|rq,recs->[Str:Obj?][]| {histories},"test",TimeZone.utc,now,false,|->DateTime| {now},|->[Str:Obj?][]| {events})
    verifyEq(metric(r,"activeAlarms")["value"],1f)
    verifyEq(metric(r,"activeAlarms")["sourceIds"],["e"])
    verifyEq(metric(r,"activeAlarms")["stateObservedAt"],now.toIso)
    conclusions:=EnerCubixMath.maps(((Map)((Map)((Map)r["modules"])["kpis"])["data"])["conclusions"])
    verifyEq(conclusions.map |v->Str| {v["id"].toStr},["activeEvents","comparableChange"])
    rs.find |v| {v["id"] == "tariff"}.remove("rate")
    r=EnerCubixCockpit.execute(request,rs,|rq,recs->[Str:Obj?][]| {histories},"test",TimeZone.utc,now,false,|->DateTime| {now},|->[Str:Obj?][]| {events})
    conclusions=EnerCubixMath.maps(((Map)((Map)((Map)r["modules"])["kpis"])["data"])["conclusions"])
    verifyEq(conclusions.map |v->Str| {v["id"].toStr},["dataQuality","activeEvents"])
    verifyEq(metric(r,"energy")["value"],100f)
    r=EnerCubixCockpit.execute(request,rs,|rq,recs->[Str:Obj?][]| {histories},"test",TimeZone.utc,now,false,|->DateTime| {now},|->[Str:Obj?][]| {throw IOErr("unavailable")})
    verifyNull(metric(r,"activeAlarms")["value"]);verifyEq(metric(r,"energy")["value"],100f)
  }

  Void testTaggedFailureInOnePeriodDoesNotClearOtherPeriodOrOtherEnergy()
  {
    hs:=histories
    hs.first.setAll(["_cockpitFrom":at.toIso,"_cockpitTo":now.toIso,"quality":"historyReadError"])
    hs.add(["pointId":"p","unit":"kWh","mode":"interval","_cockpitFrom":(at-1day).toIso,"_cockpitTo":(now-1day).toIso,"samples":[["ts":(at-1day).toIso,"value":40f],["ts":(at-1day+1hr).toIso,"value":40f]]])
    r:=run(request,records,hs)
    verifyNull(metric(r,"energy")["value"])
    c:=(Map)metric(r,"energy")["comparison"]
    verifyEq(c["reference"],80f);verifyNull(c["changeRate"])
    verifyEq(metric(r,"auxiliaryEnergy")["value"],8f)
  }

  Void testInvalidComparisonAndAuxiliaryAreRejectedBeforeHistory()
  {
    [request.dup.set("auxiliaryCategoryId","c"),request.dup.set("comparison",["mode":"custom","from":at.toIso,"to":(now+1hr).toIso]),request.dup.set("comparison",["mode":"custom","from":5,"to":now.toIso])].each |q|
    {verifyErr(ArgErr#) {EnerCubixCockpit.execute(q,records,|rq,recs->[Str:Obj?][]| {fail("must not read");return histories},"test",TimeZone.utc,now)}}
  }

  Void testDstGapAndFoldRecordNativeResolution()
  {
    q:=request;q.remove("asOf");q["time"]=["preset":"today","period":"hour"];q["comparison"]=["mode":"presetDefault"]
    tz:=TimeZone("New_York");stamp:=DateTime.fromIso("2026-03-09T06:30:00Z")
    context:=EnerCubixCockpitMetrics.comparison(q,EnerCubixCockpit.query(q,"test",tz,stamp),tz)
    verifyEq(context["to"],"2026-03-08T01:30:00-05:00")
    verify(((List)context["reasonCodes"]).contains("LOCAL_TIME_ADJUSTED"))
    adjustment:=EnerCubixMath.maps(context["adjustments"]).first
    verifyEq(adjustment["requestedLocal"],"2026-03-08T02:30:00")
    verifyEq(adjustment["resolved"],context["to"])
    stamp=DateTime.fromIso("2026-11-02T06:30:00Z")
    context=EnerCubixCockpitMetrics.comparison(q,EnerCubixCockpit.query(q,"test",tz,stamp),tz)
    verifyEq(context["to"],"2026-11-01T01:30:00-04:00")
    verify(((List)context["reasonCodes"]).contains("LOCAL_TIME_AMBIGUOUS"))
  }

  Void testCorrectedRolloverRemainsComparableAndBadReferenceIsAConclusionConstraint()
  {
    hs:=histories;hs.first["quality"]="corrected"
    r:=run(request,records,hs)
    verifyEq(((Map)metric(r,"energy")["comparison"])["changeRate"],25f)
    hs.first["samples"]=EnerCubixMath.maps(hs.first["samples"]).findAll |s| {DateTime.fromIso(s["ts"].toStr) >= at}
    r=run(request,records,hs)
    conclusions:=EnerCubixMath.maps(((Map)((Map)((Map)r["modules"])["kpis"])["data"])["conclusions"])
    verifyEq(conclusions.first["ruleId"],"CPT02-dataQuality")
    verify(((List)((Map)conclusions.first["args"])["reasonCodes"]).contains("REFERENCE_UNAVAILABLE"))
  }

  Void testRuntimeEventsAndUnrelatedSettingsDoNotChangeConfigurationFingerprint()
  {
    rs:=records.addAll([["id":"job","kind":"job","mod":"j1"],["id":"alarm","kind":"alarm","mod":"e1"],["id":"unused","kind":"tariff","mode":"flat","rate":99f,"mod":"u1"]])
    first:=(Map)run(request,rs,histories)["provenance"]
    rs.findAll |v| {["job","alarm","unused"].contains(v["id"])}.each |v| {v["mod"]="changed"}
    second:=(Map)run(request,rs,histories)["provenance"]
    verifyEq(first["configFingerprint"],second["configFingerprint"])
    verify(!EnerCubixMath.maps(second["configRefs"]).any |v| {["job","alarm","unused"].contains(v["id"])})
    rs.find |v| {v["id"] == "s"}["area"]=1000f
    verify(first["configFingerprint"] != ((Map)run(request,rs,histories)["provenance"])["configFingerprint"])
  }

  Void testAuxiliaryDuplicateSourcesAreNotDoubledAndMeterLimitCoversBothEnergies()
  {
    rs:=records;rs.add(rs.find |v| {v["id"] == "w"}.dup.set("id","duplicate"))
    r:=run(request,rs,histories)
    verifyEq(metric(r,"energy")["value"],100f)
    verifyNull(metric(r,"auxiliaryEnergy")["value"])
    verify(((List)metric(r,"auxiliaryEnergy")["reasonCodes"]).contains("duplicateSource"))
    rs=records
    (0..<199).each |i| {rs.add(["id":"w$i","kind":"meter","categoryId":"water","spaceId":"s","nativeSpaceId":"s","pointId":"pw$i"])}
    verifyErr(ArgErr#) {EnerCubixCockpit.execute(request,rs,|rq,recs->[Str:Obj?][]| {fail("over limit must not read");return histories},"test",TimeZone.utc,now)}
  }

  Void testLastObservedIncludesAuxiliaryAndExcludesUnplannedOrFutureSamples()
  {
    hs:=histories
    hs.first["rawSamples"]=[["ts":at.toIso,"value":100f]]
    hs.last["rawSamples"]=[["ts":(at+90min).toIso,"value":10f],["ts":(now+1sec).toIso,"value":11f]]
    hs.add(["pointId":"unplanned","mode":"interval","rawSamples":[["ts":now.toIso,"value":99f]],"samples":[Str:Obj?][,]])
    result:=run(request,records,hs)
    verifyEq(((Map)result["provenance"])["sourceLastObservedAt"],(at+90min).toIso)
    verifyEq(metric(result,"energy")["value"],100f)
    verifyEq(metric(result,"auxiliaryEnergy")["value"],8f)
    q:=request; q["time"]=["preset":"custom","period":"hour","from":at.toIso,"to":(at+1hr).toIso]
    result=run(q,records,hs)
    verifyEq(((Map)result["provenance"])["sourceLastObservedAt"],at.toIso)
  }

  Void testKnownDisplayDoesNotPromoteEstimatedStrictValues()
  {
    row:=Str:Obj?["categoryId":"c","unit":"kWh","value":10.92896174872294f,"valueType":"number","quality":"estimated","knownValue":null,"knownValueType":"null","knownQuality":"missing","sourceIds":["p"]]
    report:=Str:Obj?["summary":["selectionTotals":[row]],"extra":["usageCoverage":[["complete":false,"coverage":0f]]]]
    boundary:=Str:Obj?["id":"boundary","aggregateAllowed":true]
    value:=EnerCubixCockpitMetrics.metric(report,"energy","c",boundary)
    verifyNull(value["value"])
    verifyNull(value["completeValue"])
    verifyEq(value["valueType"],"null")
    verifyEq(value["valueBasis"],"unavailable")
    verifyEq(value["quality"],"missing")
    [0f,5f].each |known|
    {
      row["knownValue"]=known;row["knownValueType"]="number";row["knownQuality"]="partial"
      value=EnerCubixCockpitMetrics.metric(report,"energy","c",boundary)
      verifyEq(value["value"],known)
      verifyNull(value["completeValue"])
      verifyEq(value["valueType"],"number")
      verifyEq(value["valueBasis"],"knownSubtotal")
    }
    row["quality"]="ok";row["knownValue"]=null;row["knownValueType"]="null";row["knownQuality"]="missing"
    value=EnerCubixCockpitMetrics.metric(report,"energy","c",boundary)
    verifyNull(value["value"])
  }

  private [Str:Obj?][] values(Str:Obj? r) {EnerCubixMath.maps(((Map)((Map)((Map)r["modules"])["kpis"])["data"])["values"])}
  private Str:Obj? metric(Str:Obj? r,Str id) {values(r).find |m| {m["id"] == id} ?: throw Err("missing metric $id")}
  private Str:Obj? run(Str:Obj? q,[Str:Obj?][] rs,[Str:Obj?][] hs)
  {EnerCubixCockpit.execute(q,rs,|Str:Obj? rq,[Str:Obj?][] recs->[Str:Obj?][]| {hs},"test",TimeZone.utc,now,false,|->DateTime| {now})}
  private DateTime cycle() {DateTime.fromIso("2026-10-01T00:00:00Z")}
  private DateTime at() {DateTime.fromIso("2026-10-03T00:00:00Z")}
  private DateTime now() {at+2hr}
  private Str:Obj? request() {["schemaVersion":1,"requestId":"metrics-test","reportScope":["dimension":"space","nodeIds":["s"],"selectionIntent":"range"],"focusCategoryId":"c","auxiliaryCategoryId":"water","time":["preset":"custom","period":"hour","from":at.toIso,"to":now.toIso],"asOf":now.toIso,"modules":["kpis","trend"],"comparison":["mode":"custom","from":(at-1day).toIso,"to":(now-1day).toIso]]}
  private [Str:Obj?][] records() {[["id":"c","kind":"category","name":"Electricity","unit":"kWh","mod":"c1"],["id":"water","kind":"category","name":"Water","unit":"m³"],["id":"s","kind":"space","name":"Site","nativeSourceId":"s","nativeLevel":"site","mod":"s1"],["id":"a","kind":"meter","name":"A","categoryId":"c","spaceId":"s","nativeSpaceId":"s","pointId":"p","tariffId":"tariff","subcategoryId":"sub","mod":"a1"],["id":"w","kind":"meter","name":"W","categoryId":"water","spaceId":"s","nativeSpaceId":"s","pointId":"pw"],["id":"tariff","kind":"tariff","mode":"flat","rate":2f,"currency":"CNY","mod":"t1"],["id":"sub","kind":"subcategory","co2Factor":0.7f,"mod":"sub1"]]}
  private [Str:Obj?][] histories() {[["pointId":"p","unit":"kWh","mode":"interval","samples":[["ts":(at-1day).toIso,"value":40f],["ts":(at-1day+1hr).toIso,"value":40f],["ts":at.toIso,"value":50f],["ts":(at+1hr).toIso,"value":50f]]],["pointId":"pw","unit":"m³","mode":"interval","samples":[["ts":(at-1day).toIso,"value":2f],["ts":(at-1day+1hr).toIso,"value":2f],["ts":at.toIso,"value":4f],["ts":(at+1hr).toIso,"value":4f]]]]}
}

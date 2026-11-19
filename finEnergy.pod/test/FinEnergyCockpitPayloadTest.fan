using util
using concurrent

class FinEnergyCockpitPayloadTest : Test
{
  Void testOwnedEncodingBorrowsUnchangedImmutableBusinessRowsWithinTheOriginalBudget()
  {
    rows:=[Str:Obj?][,];3000.times |i| {rows.add(["name":"表计"+i,"value":i==1 ? null : i.toFloat,"quality":i==1 ? "na" : "ok","sourceIds":["point"]])}
    scope:=FinEnergyCockpitRequestScope("codec-borrow","a");budget:=scope.stream.state
    source:=scope.freezeSnapshot(["snapshotId":"borrow-immutable","rows":rows,"zero":0f])
    before:=JsonOutStream.writeJsonToStr(source);expected:=JsonInStream(JsonOutStream.writeJsonToStr(FinEnergyCockpitPayload.encode(source)).in).readJson
    output:=scope.payloadOutput;peer:=FinEnergyPreparedOwner(budget);peer.hold(budget.remaining-2000);held:=peer.entries
    try
    {
      // An immutable source without this scope's proof must still copy and be
      // rejected here. The permitted same-snapshot path then fits unchanged.
      verifyErr(FinEnergyHttpErr#) {FinEnergyCockpitPayload.encode(source,budget.deadline,budget,output)}
      actual:=FinEnergyCockpitPayload.encode(source,budget.deadline,budget,output,scope)
      verify(actual.isImmutable);verifyEq(JsonInStream(JsonOutStream.writeJsonToStr(actual).in).readJson,expected)
      verify(((Map)actual["snapshot"])["rows"]===source["rows"])
      verify(output.entries<100);verifyEq(JsonOutStream.writeJsonToStr(source),before);verifyEq(peer.entries,held)
      verifyEq(budget.temporary.val,scope.entries+held);output.close;verifyEq(budget.temporary.val,scope.entries+held)
    }
    finally {scope.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testBorrowedUnsortedBusinessMapsKeepExactLegacyEvidenceHashes()
  {
    rows:=[Str:Obj?][,]
    100.times |i|
    {
      nested:=Str:Obj?[:];nested.ordered=true;nested["z"]="中文 😀\n\"\\";nested["a"]=null
      row:=Str:Obj?[:];row.ordered=true;row["z"]="quoted\"";row["a"]=i==1 ? null : i.toFloat;row["nested"]=nested;rows.add(row)
    }
    scope:=FinEnergyCockpitRequestScope("codec-ordered-hash","a");source:=scope.freezeSnapshot(["sourceUsage":rows,"zero":0f])
    before:=JsonOutStream.writeJsonToStr(source);legacy:=FinEnergyCockpitPayload.encode(source)
    try
    {
      actual:=FinEnergyCockpitPayload.encode(source,scope.deadline,scope.stream.state,scope.payloadOutput,scope)
      verifyEq(JsonInStream(JsonOutStream.writeJsonToStr(actual).in).readJson,JsonInStream(JsonOutStream.writeJsonToStr(legacy).in).readJson)
      verifyEq(((Map)actual["evidence"]).keys.sort,((Map)legacy["evidence"]).keys.sort)
      id:=((Map)actual["evidence"]).keys.first
      verify(((Map)actual["evidence"])[id]===source["sourceUsage"])
      verifyEq(JsonOutStream.writeJsonToStr(source),before);verifyEq(scope.stream.state.temporary.val,scope.entries)
    }
    finally {scope.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testImmutableBorrowingKeepsLegacyReferencesTablesAndLiteralControlKeys()
  {
    literal:=Str:Obj?["\$cockpitRef":"user data","\$cockpitTable":["name":"business value"],"__proto__":["safe":true]]
    rows:=[Str:Obj?][,];100.times |i| {rows.add(["value":i==1 ? null : i.toFloat,"quality":i==1 ? "na" : "ok","metadata":literal,"pointId":"中文 🌍"])}
    scope:=FinEnergyCockpitRequestScope("codec-controls","a");source:=scope.freezeSnapshot(["periods":rows,"sourceUsage":rows,"literal":literal,"zero":0f,"nonString":Int:Str[1:"one"]])
    expected:=JsonInStream(JsonOutStream.writeJsonToStr(FinEnergyCockpitPayload.encode(source)).in).readJson
    budget:=scope.stream.state;output:=scope.payloadOutput
    try
    {
      actual:=FinEnergyCockpitPayload.encode(source,budget.deadline,budget,output,scope)
      verifyEq(JsonInStream(JsonOutStream.writeJsonToStr(actual).in).readJson,expected)
      verify(((Map)((Map)actual["snapshot"])["literal"]).containsKey("\$cockpitLiteral"));verifyEq(((Map)source["literal"])["\$cockpitRef"],"user data")
      verifyEq(budget.temporary.val,scope.entries)
    }
    finally {scope.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testEqualDetachedEvidenceDoesNotRetainDiscardedDuplicateBuilders()
  {
    source:=Str:Obj?[:]
    6.times |copy|
    {
      rows:=[Str:Obj?][,]
      500.times |i| {rows.add(["nodeId":"m","pointId":"p","from":"2026-10-01T00:00:00Z","to":"2026-10-01T01:00:00Z","unit":"kWh","knownValue":i.toFloat,"knownQuality":"filtered","coveredSeconds":900f,"expectedSeconds":3600f,"sourceIds":["p"],"intervals":Obj?[,]])}
      source["report$copy"]=["sourceUsage":rows.toImmutable]
    }
    source=source.toImmutable;before:=JsonOutStream.writeJsonToStr(source)
    expected:=JsonOutStream.writeJsonToStr(FinEnergyCockpitPayload.encode(source))
    budget:=FinEnergyStreamBudget().state;output:=FinEnergyPreparedOwner(budget);peer:=FinEnergyPreparedOwner(budget);peer.hold(160000)
    try
    {
      actual:=FinEnergyCockpitPayload.encode(source,budget.deadline,budget,output)
      verifyEq(JsonOutStream.writeJsonToStr(actual),expected);verifyEq(JsonOutStream.writeJsonToStr(source),before)
      verifyEq(((Map)actual["evidence"]).size,1);verify(budget.peak.val<=200000)
      verifyEq(budget.temporary.val,output.entries+peer.entries);output.close;verifyEq(budget.temporary.val,peer.entries)
    }
    finally {output.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testOwnedEncodingReusesOnlyTheSameFrozenSharedValueAndField()
  {
    rows:=[Str:Obj?][,];100.times |i| {rows.add(["index":i,"value":i==1 ? null : i.toFloat])}
    immutable:=rows.toImmutable
    source:=Str:Obj?["a":["sourceUsage":immutable],"b":["sourceUsage":immutable],"periods":immutable,"sourceUsage":immutable].toImmutable
    expected:=JsonOutStream.writeJsonToStr(FinEnergyCockpitPayload.encode(source));budget:=FinEnergyStreamBudget().state;output:=FinEnergyPreparedOwner(budget)
    try
    {
      actual:=FinEnergyCockpitPayload.encode(source,budget.deadline,budget,output)
      verifyEq(JsonOutStream.writeJsonToStr(actual),expected)
      body:=(Map)actual["snapshot"];verify(((Map)body["a"])["sourceUsage"]===((Map)body["b"])["sourceUsage"])
      verifyEq(((List)source["sourceUsage"]).size,100);verifyEq(budget.temporary.val,output.entries)
    }
    finally {output.close}
  }
  Void testFailureDuringCodecTransferPublishesNothingAndPreservesInputAndPeer()
  {
    rows:=[Str:Obj?][,];5000.times |i| {rows.add(["index":i,"value":i.toFloat])}
    source:=Str:Obj?["rows":rows];before:=JsonOutStream.writeJsonToStr(source)
    budget:=FinEnergyStreamBudget().state;output:=FinEnergyPreparedOwner(budget);peer:=FinEnergyPreparedOwner(budget);peer.hold(173000);held:=peer.entries
    try
    {
      verifyErr(FinEnergyHttpErr#) {FinEnergyCockpitPayload.encode(source,budget.deadline,budget,output)}
      verify(output.entries>4);verifyEq(JsonOutStream.writeJsonToStr(source),before);verifyEq(peer.entries,held)
      output.close;verifyEq(budget.temporary.val,held)
    }
    finally {output.close;peer.close}
  }
  Void testOwnedCodecTransfersItsBuilderBeforeDuplicatingTheWholePayload()
  {
    rows:=[Str:Obj?][,];5000.times |i| {rows.add(["index":i,"value":i==1 ? null : i.toFloat])}
    source:=Str:Obj?["rows":rows];before:=JsonOutStream.writeJsonToStr(source)
    expected:=JsonOutStream.writeJsonToStr(FinEnergyCockpitPayload.encode(source))
    budget:=FinEnergyStreamBudget().state;output:=FinEnergyPreparedOwner(budget);peer:=FinEnergyPreparedOwner(budget);peer.hold(149000)
    try
    {
      actual:=FinEnergyCockpitPayload.encode(source,budget.deadline,budget,output)
      verifyEq(JsonOutStream.writeJsonToStr(actual),expected);verifyEq(JsonOutStream.writeJsonToStr(source),before)
      verify(budget.peak.val<=200000);verifyEq(budget.temporary.val,output.entries+peer.entries)
      output.close;verifyEq(budget.temporary.val,peer.entries)
    }
    finally {output.close;peer.close}
  }
  Void testNonSharedCodecObjectsCannotBypassTheRequestBudget()
  {
    source:=Str:Obj?[:];(0..<300).each |i| {source["field$i"]=i}
    budget:=FinEnergyStreamBudget().state;output:=FinEnergyPreparedOwner(budget);peer:=FinEnergyPreparedOwner(budget)
    peer.hold(budget.remaining-24);held:=peer.entries
    try
    {
      verifyErr(FinEnergyHttpErr#) {FinEnergyCockpitPayload.encode(source,budget.deadline,budget,output)}
      verifyEq(peer.entries,held);output.close;verifyEq(budget.temporary.val,held)
      verifyEq(source.size,300)
    }
    finally {output.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testOwnedEncodingMatchesTheExistingWireAndKeepsOnlyItsOutputLease()
  {
    rows:=[Str:Obj?][,];(0..<40).each |i| {rows.add(["from":"2026-10-01T00:00:00Z","value":i==1 ? null : i.toFloat,"quality":i==1 ? "na" : "ok","pointId":"电表 🌍"])}
    source:=Str:Obj?["periods":rows,"heatmap":rows,"sourceUsage":rows,"literal":["\$cockpitRef":"user data"],"trueZero":0f]
    before:=JsonOutStream.writeJsonToStr(source)
    expected:=JsonOutStream.writeJsonToStr(FinEnergyCockpitPayload.encode(source))
    budget:=FinEnergyStreamBudget().state;output:=FinEnergyPreparedOwner(budget);peer:=FinEnergyPreparedOwner(budget);peer.hold(31)
    try
    {
      actual:=FinEnergyCockpitPayload.encode(source,budget.deadline,budget,output)
      verify(actual.isImmutable);verifyEq(JsonOutStream.writeJsonToStr(actual),expected)
      verifyEq(JsonOutStream.writeJsonToStr(source),before)
      verify(output.entries>4);verifyEq(budget.temporary.val,output.entries+peer.entries)
      output.close;verifyEq(budget.temporary.val,peer.entries)
    }
    finally {output.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testOwnedEncodingTimeoutReleasesWorkspaceWithoutChangingInput()
  {
    source:=Str:Obj?[:];(0..<1000).each |i| {source["field$i"]=i}
    calls:=AtomicInt();deadline:=FinEnergyCockpitDeadline(30sec,|->Int| {calls.incrementAndGet>2 ? 31sec.ticks : 0})
    budget:=FinEnergyStreamBudget(50000,200000,20000000,30sec,deadline).state
    output:=FinEnergyPreparedOwner(budget);peer:=FinEnergyPreparedOwner(budget);peer.hold(17)
    try
    {
      try {FinEnergyCockpitPayload.encode(source,deadline,budget,output);fail("Encoder must use the request deadline")}
      catch(FinEnergyHttpErr e) {verifyEq(e.status,504);verifyEq(e.code,"QUERY_TIMEOUT")}
      verifyEq(source.size,1000);verifyEq(budget.temporary.val,output.entries+peer.entries)
      output.close;verifyEq(budget.temporary.val,peer.entries)
    }
    finally {output.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testBusinessControlKeysAreEscapedLiterally()
  {
    business:=Str:Obj?["\$cockpitRef":"business data","\$cockpitTable":["columns":["value"],"rows":[[0f]]],"\$cockpitLiteral":["nested":true]]
    snapshot:=Str:Obj?["snapshotId":"literal-fixture","parameters":business,"periods":[["from":"2026-11-01T01:00:00-04:00","to":"2026-11-01T01:00:00-05:00","value":0f,"quality":"ok","pointId":"p"],["from":"2026-11-01T01:00:00-05:00","to":"2026-11-01T02:00:00-05:00","value":null,"quality":"na","pointId":"p"]]]
    wire:=FinEnergyCockpitPayload.encode(snapshot)
    parameters:=(Map)((Map)wire["snapshot"])["parameters"]
    verify(parameters.containsKey("\$cockpitLiteral"));verifyEq(parameters.size,1)
    verifyEq(((Map)parameters["\$cockpitLiteral"])["\$cockpitRef"],"business data")
    fixture:=Env.cur.vars["FINENERGY_COCKPIT_LITERAL_FIXTURE"]
    if (fixture != null)
    {
      File.os(fixture).out.writeChars(JsonOutStream.writeJsonToStr(snapshot)).close
      File.os(fixture+".wire.json").out.writeChars(JsonOutStream.writeJsonToStr(wire)).close
    }
  }

  Void testEncodingNegotiationAndLegacyReportRemainSeparate()
  {
    test:=FinEnergyCockpitSpaceTest()
    q:=(Str:Obj?)test.typeof.method("request").callOn(test,Obj?[,])
    rs:=([Str:Obj?][])test.typeof.method("records").callOn(test,Obj?[,])
    hs:=([Str:Obj?][])test.typeof.method("histories").callOn(test,Obj?[,])
    end:=DateTime.fromIso("2026-10-01T02:00:00Z")
    q["modules"]=["kpis","trend","time","endUse","organization","balance","efficiency","issues"]
    plain:=FinEnergyCockpit.execute(q,rs,|rq,saved->[Str:Obj?][]| {hs},"test",TimeZone.utc,end)
    verifyEq(((Map)plain["modules"]).size,8);verifyNull(((Map)plain["modules"])["space"])
    q["payloadEncoding"]="compact-v1"
    compact:=FinEnergyCockpit.execute(q,rs,|rq,saved->[Str:Obj?][]| {hs},"test",TimeZone.utc,end)
    verifyEq(compact["payloadEncoding"],"compact-v1");verifyEq(compact["codecVersion"],1)
    verifyEq(((Map)((Map)compact["snapshot"])["provenance"])["configFingerprint"],((Map)plain["provenance"])["configFingerprint"])
    q["payloadEncoding"]="unsupported"
    verifyErr(ArgErr#) {FinEnergyCockpit.execute(q,rs,|rq,saved->[Str:Obj?][]| {fail("must reject before load");return hs},"test",TimeZone.utc,end)}
    report:=FinEnergyHistory.report(["kind":"profile","nodeIds":["a"],"categoryIds":["c"],"from":"2026-10-01T00:00:00Z","to":end.toIso,"asOf":end.toIso,"period":"hour"],rs,hs)
    verifyNull(report["payloadEncoding"]);verifyNotNull(report["rows"])
  }

  Void testAnnualNineMeterNineModuleWireKeepsBusinessResultsAndBoundsDiagnostics()
  {
    from:=DateTime.fromIso("2025-01-01T00:00:00Z");to:=DateTime.fromIso("2026-01-01T00:00:00Z");reference:=DateTime.fromIso("2024-01-01T00:00:00Z")
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space","name":"Site","nativeSourceKind":"site","nativeSourceId":"s"],["id":"f","kind":"space","name":"Floor","nativeSourceKind":"floor","nativeSourceId":"f","parentId":"s"],["id":"sub","kind":"subcategory","categoryId":"c","co2Factor":0.5f],["id":"tariff","kind":"tariff","mode":"flat","rate":2f]]
    hs:=[Str:Obj?][,]
    (0..<9).each |i|
    {
      id:="m$i";point:="p$i"
      r:=Str:Obj?["id":id,"name":id,"kind":i == 0 ? "totalMeter" : "meter","nativeEquip":true,"nativeSourceKind":"equip","nativeTreeParentId":"f","spaceId":"f","pointId":point,"categoryId":"c","subcategoryId":"sub","tariffId":"tariff"]
      if (i > 0) r["meterParentId"]="m0"
      rs.add(r)
      rows:=[Str:Obj?][,];cursor:=reference;hour:=0
      while (cursor < to) {rows.add(["ts":cursor.toIso,"value":i == 0 ? 9f+(hour%3)*0.1f : 1f]);cursor+=1hr;hour++}
      hs.add(["pointId":point,"unit":"kWh","mode":"interval","samples":rows])
    }
    q:=Str:Obj?["schemaVersion":1,"requestId":"annual-nine","reportScope":["dimension":"space","nodeIds":["s"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"month","from":from.toIso,"to":to.toIso],"asOf":to.toIso,"comparison":["mode":"custom","from":reference.toIso,"to":from.toIso],"modules":["kpis","trend","space","time","endUse","organization","balance","efficiency","issues"]]
    calls:=0;began:=Duration.nowTicks
    snapshot:=FinEnergyCockpit.execute(q,rs,|rq,saved->[Str:Obj?][]| {calls++;return hs},"test",TimeZone.utc,to)
    verifyEq(calls,1)
    projectionMs:=(Duration.nowTicks-began)/1ms.ticks
    bytes:=JsonOutStream.writeJsonToStr(["ok":true,"data":snapshot]).toBuf.size
    echo("ANNUAL_NINE logicalBytes=$bytes projectionMs=$projectionMs")
    fixture:=Env.cur.vars["FINENERGY_COCKPIT_ANNUAL_FIXTURE"]
    if (fixture != null) File.os(fixture).out.writeChars(JsonOutStream.writeJsonToStr(snapshot)).close
    codec:=Type.find("finEnergy::FinEnergyCockpitPayload",false)
    verifyNotNull(codec,"compact payload implementation missing")
    // The response limit applies to the negotiated pipeline, not a raw codec
    // invocation over the complete, unnegotiated diagnostic archive.
    bounded:=FinEnergyCockpitDiagnostics.project(snapshot)
    verifyEq(bounded["modules"],snapshot["modules"])
    ((Map)snapshot["reports"]).each |original,key|
    {
      report:=(Map)original;actual:=(Map)((Map)bounded["reports"])[key]
      verifyEq(actual["summary"],report["summary"]);verifyEq(actual["series"],report["series"])
    }
    verify(((Int)((Map)bounded["diagnostics"])["returnedCount"]) <= 1000)
    rawWire:=codec.method("encode").call(snapshot)
    if(fixture != null) File.os(fixture+".raw.wire.json").out.writeChars(JsonOutStream.writeJsonToStr(rawWire)).close
    // Exercise the actual negotiated entry, including producer capture. Keep
    // the unnegotiated fixture above for independent legacy/codec comparison.
    negotiatedBegan:=Duration.nowTicks
    wire:=FinEnergyCockpit.execute(q.dup.set("payloadEncoding","compact-v1"),rs,|rq,saved->[Str:Obj?][]| {calls++;return hs},"test",TimeZone.utc,to)
    verifyEq(calls,2);verifyEq(wire["payloadEncoding"],"compact-v1")
    negotiatedMs:=(Duration.nowTicks-negotiatedBegan)/1ms.ticks
    serializeBegan:=Duration.nowTicks
    wireBytes:=JsonOutStream.writeJsonToStr(["ok":true,"data":wire]).toBuf.size
    echo("ANNUAL_NINE wireBytes=$wireBytes negotiatedExecuteMs=$negotiatedMs serializeMs=${(Duration.nowTicks-serializeBegan)/1ms.ticks}")
    verify(wireBytes <= 8388608)
    if (fixture != null) File.os(fixture+".wire.json").out.writeChars(JsonOutStream.writeJsonToStr(wire)).close
  }
}

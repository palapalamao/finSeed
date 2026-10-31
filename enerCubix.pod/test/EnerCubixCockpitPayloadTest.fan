using util

class EnerCubixCockpitPayloadTest : Test
{
  Void testBusinessControlKeysAreEscapedLiterally()
  {
    business:=Str:Obj?["\$cockpitRef":"business data","\$cockpitTable":["columns":["value"],"rows":[[0f]]],"\$cockpitLiteral":["nested":true]]
    snapshot:=Str:Obj?["snapshotId":"literal-fixture","parameters":business,"periods":[["from":"2026-11-01T01:00:00-04:00","to":"2026-11-01T01:00:00-05:00","value":0f,"quality":"ok","pointId":"p"],["from":"2026-11-01T01:00:00-05:00","to":"2026-11-01T02:00:00-05:00","value":null,"quality":"na","pointId":"p"]]]
    wire:=EnerCubixCockpitPayload.encode(snapshot)
    parameters:=(Map)((Map)wire["snapshot"])["parameters"]
    verify(parameters.containsKey("\$cockpitLiteral"));verifyEq(parameters.size,1)
    verifyEq(((Map)parameters["\$cockpitLiteral"])["\$cockpitRef"],"business data")
    fixture:=Env.cur.vars["ENERCUBIX_COCKPIT_LITERAL_FIXTURE"]
    if (fixture != null)
    {
      File.os(fixture).out.writeChars(JsonOutStream.writeJsonToStr(snapshot)).close
      File.os(fixture+".wire.json").out.writeChars(JsonOutStream.writeJsonToStr(wire)).close
    }
  }

  Void testEncodingNegotiationAndLegacyReportRemainSeparate()
  {
    test:=EnerCubixCockpitSpaceTest()
    q:=(Str:Obj?)test.typeof.method("request").callOn(test,Obj?[,])
    rs:=([Str:Obj?][])test.typeof.method("records").callOn(test,Obj?[,])
    hs:=([Str:Obj?][])test.typeof.method("histories").callOn(test,Obj?[,])
    end:=DateTime.fromIso("2026-10-01T02:00:00Z")
    q["modules"]=["kpis","trend","time","endUse","organization","balance","efficiency","issues"]
    plain:=EnerCubixCockpit.execute(q,rs,|rq,saved->[Str:Obj?][]| {hs},"test",TimeZone.utc,end)
    verifyEq(((Map)plain["modules"]).size,8);verifyNull(((Map)plain["modules"])["space"])
    q["payloadEncoding"]="compact-v1"
    compact:=EnerCubixCockpit.execute(q,rs,|rq,saved->[Str:Obj?][]| {hs},"test",TimeZone.utc,end)
    verifyEq(compact["payloadEncoding"],"compact-v1");verifyEq(compact["codecVersion"],1)
    verifyEq(((Map)((Map)compact["snapshot"])["provenance"])["configFingerprint"],((Map)plain["provenance"])["configFingerprint"])
    q["payloadEncoding"]="unsupported"
    verifyErr(ArgErr#) {EnerCubixCockpit.execute(q,rs,|rq,saved->[Str:Obj?][]| {fail("must reject before load");return hs},"test",TimeZone.utc,end)}
    report:=EnerCubixHistory.report(["kind":"profile","nodeIds":["a"],"categoryIds":["c"],"from":"2026-10-01T00:00:00Z","to":end.toIso,"asOf":end.toIso,"period":"hour"],rs,hs)
    verifyNull(report["payloadEncoding"]);verifyNotNull(report["rows"])
  }

  Void testAnnualNineMeterNineModuleWireKeepsEveryPeriodAndTotal()
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
    snapshot:=EnerCubixCockpit.execute(q,rs,|rq,saved->[Str:Obj?][]| {calls++;return hs},"test",TimeZone.utc,to)
    verifyEq(calls,1)
    projectionMs:=(Duration.nowTicks-began)/1ms.ticks
    bytes:=JsonOutStream.writeJsonToStr(["ok":true,"data":snapshot]).toBuf.size
    echo("ANNUAL_NINE logicalBytes=$bytes projectionMs=$projectionMs")
    fixture:=Env.cur.vars["ENERCUBIX_COCKPIT_ANNUAL_FIXTURE"]
    if (fixture != null) File.os(fixture).out.writeChars(JsonOutStream.writeJsonToStr(snapshot)).close
    codec:=Type.find("enerCubix::EnerCubixCockpitPayload",false)
    verifyNotNull(codec,"compact payload implementation missing")
    encodeBegan:=Duration.nowTicks
    wire:=codec.method("encode").call(snapshot)
    encodeMs:=(Duration.nowTicks-encodeBegan)/1ms.ticks
    serializeBegan:=Duration.nowTicks
    wireBytes:=JsonOutStream.writeJsonToStr(["ok":true,"data":wire]).toBuf.size
    echo("ANNUAL_NINE wireBytes=$wireBytes encodeMs=$encodeMs serializeMs=${(Duration.nowTicks-serializeBegan)/1ms.ticks}")
    verify(wireBytes <= 8388608)
    if (fixture != null) File.os(fixture+".wire.json").out.writeChars(JsonOutStream.writeJsonToStr(wire)).close
  }
}

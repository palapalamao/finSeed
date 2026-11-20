using util

class FinEnergyCockpitTest : Test
{
  Void testOneLoadIndependentTotalAndLegacyReport()
  {
    calls:=0
    recs:=records
    result:=FinEnergyCockpit.execute(request,recs,|q,rs->[Str:Obj?][]|
    {
      calls++
      verify(rs.isImmutable); verify(q.isImmutable)
      verifyEq(FinEnergyHistory.pointIds(q,rs),["pa","pb"])
      return histories
    },"test",TimeZone.utc,now,false,|->DateTime| {now})
    verifyEq(calls,1)
    value:=energy(result)
    // Two independent meters: (3+7) + (11+19), not sum of display rows.
    verifyEq(value["value"],40f); verifyEq(value["completeValue"],40f)
    verifyEq(value["knownValue"],40f); verifyEq(value["valueBasis"],"complete")
    verifyEq(((Map)result["boundary"])["meterIds"],["a","b"])
    verify(result.isImmutable)
    verifyErr(ReadonlyErr#) { result["requestId"]="changed" }
    report:=(Str:Obj?)((Map)result["reports"])["profile-energy"]
    legacy:=FinEnergyHistory.report(flat,recs,histories)
    verifyEq(report,legacy)
    verifyEq(legacy["edition"],FinEnergyEditionLicense.edition)
    verifyEq(legacy["licenseMode"],FinEnergyEditionLicense.licenseMode)
    verifyEq(((Map)result["provenance"])["edition"],FinEnergyEditionLicense.edition)
    verifyEq(((Map)result["provenance"])["licenseMode"],FinEnergyEditionLicense.licenseMode)
    fixture:=Env.cur.vars["FINENERGY_COCKPIT_FIXTURE"]
    if (fixture != null) File.os(fixture).out.writeChars(JsonOutStream.writeJsonToStr(result)).close
  }

  Void testOwnHistoryNeverUsesChildrenFormulaOrAuxiliary()
  {
    recs:=records
    recs.add(["id":"t","kind":"totalMeter","name":"Virtual","categoryId":"c","pointId":"pt","spaceId":"s","expressionId":"expr"])
    recs.findAll |r| {r["id"] == "a" || r["id"] == "b"}.each |r| {r["meterParentId"]="t"}
    recs.add(["id":"expr","kind":"expression","variables":["A":"a","B":"b"],"formula":"A+B"])
    q:=request; ((Map)q["reportScope"])["dimension"]="metering"; ((Map)q["reportScope"])["nodeIds"]=["t"]
    result:=FinEnergyCockpit.execute(q,recs,|rq,rs->[Str:Obj?][]|
    {
      verifyEq(FinEnergyHistory.pointIds(rq,rs),["pt"])
      return histories
    },"test",TimeZone.utc,now,false,|->DateTime| {now})
    verifyNull(energy(result)["value"]); verifyNull(energy(result)["knownValue"])
    verifyEq(energy(result)["valueBasis"],"unavailable")
    verifyEq(((Map)result["boundary"])["sourcePointIds"],["pt"])
  }

  Void testPartialNAAndRealZero()
  {
    hs:=histories; hs.removeAt(1)
    result:=run(request,records,hs)
    verifyNull(energy(result)["completeValue"]); verifyEq(energy(result)["value"],10f)
    verifyEq(energy(result)["valueBasis"],"knownSubtotal")
    verifyEq(((Map)((Map)result["modules"])["kpis"])["status"],"partial")
    q:=request; ((Map)q["reportScope"])["dimension"]="metering"; ((Map)q["reportScope"])["nodeIds"]=["a"]
    h:=histories.first; h["samples"]=[["ts":at.toIso,"value":null,"valueType":"na"],["ts":(at+1hr).toIso,"value":null,"valueType":"na"]]
    verifyEq(energy(run(q,records,[h]))["valueType"],"na")
    h["samples"]=[["ts":at.toIso,"value":0f],["ts":(at+1hr).toIso,"value":0f]]
    verifyEq(energy(run(q,records,[h]))["value"],0f)
  }

  Void testMonthUsesProjectTimezoneExactCurrentInstant()
  {
    q:=request; q.remove("asOf"); q["time"]=["preset":"thisMonth","period":"day"]
    clock:=DateTime.fromIso("2026-10-30T10:37:23Z")
    result:=FinEnergyCockpit.execute(q,records,|rq,rs->[Str:Obj?][]| {histories},"test",TimeZone("Shanghai"),clock,false,|->DateTime| {clock})
    context:=(Map)result["context"]; time:=(Map)context["time"]
    verifyEq(time["from"],"2026-10-01T00:00:00+08:00")
    verifyEq(time["to"],"2026-10-30T18:37:23+08:00")
    verifyEq(context["asOf"],"2026-10-30T18:37:23+08:00")
    verifyEq(((Map)result["provenance"])["sourceLastObservedAt"],(at+1hr).toIso)
    verifyEq(result["generatedAt"],clock.toIso)
  }

  Void testExplicitOverlapPreservesObjectsSuppressesScalar()
  {
    recs:=records; recs.find |r| {r["id"] == "b"}["meterParentId"]="a"
    q:=request; q["reportScope"]=["dimension":"metering","nodeIds":["a","b"],"selectionIntent":"explicitObjects"]
    result:=run(q,recs,histories)
    verifyEq(((Map)result["boundary"])["aggregateAllowed"],false)
    verifyNull(energy(result)["value"]); verifyNull(energy(result)["knownValue"])
    verify(((List)energy(result)["reasonCodes"]).contains("overlappingScopes"))
    report:=(Map)((Map)result["reports"])["profile-energy"]
    verifyEq(((List)report["series"]).size,2)
    verifyEq(((List)((Map)report["summary"])["totals"]).size,2)
  }

  Void testInputValidationBeforeHistoryAndOpaqueForbiddenRefs()
  {
    bads:=[request.dup.set("schemaVersion","1"),request.dup.set("requestId",5),request.dup.set("focusCategoryId","p:other:r:c"),request.dup.set("reportScope",["dimension":"space","nodeIds":[5],"selectionIntent":"range"]),request.dup.set("time",["preset":"custom","period":"hour","from":5,"to":now.toIso]),request.dup.set("modules",["cost"])]
    bads.each |q| { verifyErr(ArgErr#) {run(q,records,histories)} }
    q:=request; ((Map)q["reportScope"])["nodeIds"]=["hidden-secret"]
    try {run(q,records,histories); fail("Expected forbidden")}
    catch (FinEnergyHttpErr e) {verifyEq(e.status,403); verify(!e.msg.contains("hidden-secret"))}
    q=request; q["project"]="other"
    verifyErr(ArgErr#) {run(q,records,histories)}
    q=request; q["time"]=["preset":"custom","period":"hour","from":"2024-01-01T00:00:00Z","to":now.toIso]
    verifyErr(ArgErr#) {run(q,records,histories)}
  }

  Void testReadObservationClockIsSeparateFromLastSampleEvenWithoutSources()
  {
    clock:=now
    result:=FinEnergyCockpit.execute(request,records,|rq,rs->[Str:Obj?][]| {clock+=2sec; return histories},"test",TimeZone.utc,now,false,|->DateTime| {clock})
    p:=(Map)result["provenance"]
    verifyEq(p["historyObservedFrom"],now.toIso); verifyEq(p["historyObservedTo"],(now+2sec).toIso)
    verifyEq(p["sourceLastObservedAt"],(at+1hr).toIso)
    verifyEq(result["generatedAt"],(now+2sec).toIso)
    clock=now
    result=FinEnergyCockpit.execute(request,records,|rq,rs->[Str:Obj?][]| {clock+=1sec; return [Str:Obj?][,]},"test",TimeZone.utc,now,false,|->DateTime| {clock})
    p=(Map)result["provenance"]
    verifyEq(p["historyObservedFrom"],now.toIso); verifyEq(p["historyObservedTo"],(now+1sec).toIso)
    verifyNull(p["sourceLastObservedAt"])
  }

  Void testActualJsonShapeAndRequestedModules()
  {
    q:=(Str:Obj?)JsonInStream(JsonOutStream.writeJsonToStr(request).in).readJson
    q["modules"]=Obj?["trend"]
    result:=run(q,records,histories)
    verifyEq(((Map)result["modules"]).keys,["trend"])
    verifyEq(((List)((Map)result["capabilities"])["availableFaces"]).size,0)
    verifyEq(((List)result["quality"]).size,1)
    verifyEq(((Map)((List)result["quality"]).first)["coveredSeconds"],7200f)
  }

  Void testRequestedEndCutoffAndReadEndRemainDistinct()
  {
    q:=request; ((Map)q["time"])["to"]=(now+3hr).toIso
    result:=FinEnergyCockpit.execute(q,records,|Str:Obj? rq,[Str:Obj?][] rs->[Str:Obj?][]|
    {
      verifyEq(rq["to"],now.toIso)
      return histories
    },"test",TimeZone.utc,now,false,|->DateTime| {now})
    verifyEq(((Map)((Map)result["context"])["time"])["to"],(now+3hr).toIso)
    verifyEq(((Map)result["context"])["asOf"],now.toIso)
    verifyNull(energy(result)["completeValue"])
    verifyEq(energy(result)["knownValue"],40f)
    verify(((List)result["limitations"]).contains("REQUEST_END_AFTER_AS_OF"))
  }

  Void testReplacementAndCorrectionStayDistinctAndReadFailuresAreExplicit()
  {
    q:=request; q["reportScope"]=["dimension":"metering","nodeIds":["a"],"selectionIntent":"range"]
    ["corrected","substituted"].each |quality|
    {
      h:=histories.first; h["quality"]=quality
      result:=run(q,records,[h])
      verifyEq(energy(result)["knownValue"],10f)
      verifyEq(energy(result)["valueBasis"],quality == "substituted" ? "cleanedWithReplacement" : "complete")
      if (quality == "substituted") verifyNull(energy(result)["completeValue"])
    }
    ["historySampleLimit","historyReadError"].each |quality|
    {
      result:=run(q,records,[["pointId":"pa","quality":quality,"mode":"interval","samples":[Str:Obj?][,]]])
      verifyNull(energy(result)["value"])
      verify(((List)result["limitations"]).contains(quality == "historySampleLimit" ? "HISTORY_SAMPLE_LIMIT" : "HISTORY_READ_ERROR"))
    }
  }

  Void testUnreadableMembersDoNotBecomeACompleteVisibleSubtotal()
  {
    hidden:=records.last.dup.set("_comparisonReadable",false)
    verifyErr(FinEnergyHttpErr#) {FinEnergyCockpit.guardVisibleScope(flat,records,[hidden])}
    hidden["categoryId"]="other"
    FinEnergyCockpit.guardVisibleScope(flat,records,[hidden])
    verify(true)
  }

  Void testUntrustedOrganizationBoundaryHasNoScalarButKeepsChart()
  {
    recs:=records
    recs.add(["id":"o1","kind":"organization","name":"Owner 1"])
    recs.add(["id":"o2","kind":"organization","name":"Owner 2"])
    recs.find |r| {r["id"] == "a"}.setAll(["organizationId":"o1","kind":"totalMeter"])
    recs.find |r| {r["id"] == "b"}.setAll(["organizationId":"o2","meterParentId":"a"])
    q:=request; q["reportScope"]=["dimension":"organization","nodeIds":["o1"],"selectionIntent":"range"]
    result:=run(q,recs,histories)
    verifyNull(energy(result)["value"])
    verify(((List)energy(result)["reasonCodes"]).contains("accountingIncomplete"))
    verifyEq(((Map)result["boundary"])["aggregateAllowed"],false)
    verifyEq(((List)((Map)((Map)result["reports"])["profile-energy"])["series"]).size,1)
  }

  private Str:Obj? run(Str:Obj? q, [Str:Obj?][] rs, [Str:Obj?][] hs)
  { FinEnergyCockpit.execute(q,rs,|rq,recs->[Str:Obj?][]| {hs},"test",TimeZone.utc,now,false,|->DateTime| {now}) }
  private Str:Obj? energy(Str:Obj? r) { ((List)((Map)((Map)((Map)r["modules"])["kpis"])["data"])["values"]).first }
  private DateTime at() {DateTime.fromIso("2026-10-03T00:00:00Z")}
  private DateTime now() {at+2hr}
  private Str:Obj? request() { ["schemaVersion":1,"requestId":"cockpit-test","reportScope":["dimension":"space","nodeIds":["s"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"hour","from":at.toIso,"to":now.toIso],"asOf":now.toIso,"modules":["kpis","trend"],"comparison":["mode":"none"]] }
  private Str:Obj? flat() { ["kind":"profile","metric":"energy","dimension":"space","spaceSource":"fin","nodeIds":["s"],"categoryIds":["c"],"period":"hour","from":at.toIso,"to":now.toIso,"asOf":now.toIso,"tz":"UTC"] }
  private [Str:Obj?][] records() { [["id":"c","kind":"category","name":"Electricity","unit":"kWh","mod":"c1"],["id":"s","kind":"space","name":"Site","nativeSourceId":"s","nativeLevel":"site","mod":"s1"],["id":"a","kind":"meter","name":"A","categoryId":"c","spaceId":"s","nativeSpaceId":"s","pointId":"pa","mod":"a1"],["id":"b","kind":"meter","name":"B","categoryId":"c","spaceId":"s","nativeSpaceId":"s","pointId":"pb","mod":"b1"]] }
  private [Str:Obj?][] histories() { [["pointId":"pa","unit":"kWh","mode":"interval","samples":[["ts":at.toIso,"value":3f],["ts":(at+1hr).toIso,"value":7f]]],["pointId":"pb","unit":"kWh","mode":"interval","samples":[["ts":at.toIso,"value":11f],["ts":(at+1hr).toIso,"value":19f]]]] }
}

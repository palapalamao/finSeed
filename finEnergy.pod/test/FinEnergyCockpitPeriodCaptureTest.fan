using util

class FinEnergyCockpitPeriodCaptureTest : Test
{
  Void testCaptureIsFairBoundedAndAllBusinessFieldsStayIdentical()
  {
    legacy:=FinEnergyHistory.report(query,records,histories)
    captured:=FinEnergyHistory.report(query.dup.set("_cockpitDiagnosticCapture",true),records,histories)
    overview:=(Map)((Map)captured["extra"])["energyFlowOverview"]
    rows:=FinEnergyMath.maps(overview["rows"])
    verifyEq(rows.reduce(0) |Int n,r->Int| {n+FinEnergyMath.maps(r["periods"]).size},1000)
    rows.each |r| {verifyEq(r["periodRecordTotalCount"],720);verifyEq(r["periodsReturnedCount"],500);verifyEq(r["periodsTruncated"],true)}
    verifyEq(withoutDiagnosticPeriods(captured),withoutDiagnosticPeriods(legacy))
    packet:=Str:Obj?["context":["asOf":finish.toIso,"reportScope":["nodeIds":["a"]]],"reports":["energy-flow":captured]]
    projected:=FinEnergyCockpitDiagnostics.project(packet)
    diagnostics:=(Map)projected["diagnostics"]
    periods:=FinEnergyMath.maps(diagnostics["entries"]).findAll |e| {e["kind"] == "coveragePeriods"}
    verifyEq(periods.size,2)
    periods.each |e| {verifyEq(e["totalCount"],720);verifyEq(e["truncated"],true);verify(e["returnedCount"] <= 500);verifyEq(e["upstreamReason"],"cockpitPeriodCaptureLimit")}
    projectedRows:=FinEnergyMath.maps(((Map)((Map)((Map)((Map)projected["reports"])["energy-flow"])["extra"])["energyFlowOverview"])["rows"])
    projectedRows.each |r| {verifyEq(r["periodsReturnedCount"],FinEnergyMath.maps(r["periods"]).size)}
  }

  Void testLegacyWithoutExplicitCapturePreservesEveryPeriod()
  {
    normal:=FinEnergyHistory.report(query,records,histories)
    rows:=FinEnergyMath.maps(((Map)((Map)normal["extra"])["energyFlowOverview"])["rows"])
    rows.each |r| {verifyEq(FinEnergyMath.maps(r["periods"]).size,720);verifyEq(r["periodsTruncated"],null)}
    noCapability:=query.dup;noCapability.remove("_cockpitCategoryId");noCapability["_cockpitDiagnosticCapture"]=true
    report:=FinEnergyHistory.report(noCapability,records,histories)
    verifyEq(report["series"],normal["series"])
    FinEnergyMath.maps(((Map)((Map)report["extra"])["energyFlowOverview"])["rows"]).each |r| {verifyEq(FinEnergyMath.maps(r["periods"]).size,720)}
  }

  Void testQuotaAndCaptureEqualityBoundaries()
  {
    [79,116,1001].each |count|
    {
      quotas:=(0..<count).map |position->Int| {FinEnergyFlowOverview.periodQuota(count,position)}
      verifyEq(quotas.reduce(0) |Int n,Int v->Int| {n+v},1000)
      verify(((Int)quotas.max)-((Int)quotas.min) <= 1)
    }
    verifyEq(FinEnergyFlowOverview.periodQuota(1001,1000),0)
    [999,1000,1001].each |hours|
    {
      q:=query.dup.setAll(["to":(start+Duration(hours*1hr.ticks)).toIso,"asOf":(start+Duration(hours*1hr.ticks)).toIso,"_cockpitDiagnosticCapture":true])
      overview:=FinEnergyFlowOverview.build(q,records,[["pointId":"pa","mode":"interval","unit":"kWh"]],["a"])
      row:=FinEnergyMath.maps(overview["rows"]).first
      verifyEq(row["periodRecordTotalCount"],hours);verifyEq(row["periodsReturnedCount"],hours.min(1000));verifyEq(row["periodsTruncated"],hours>1000)
    }
  }

  Void testNegotiationAloneEnablesServerCaptureFlag()
  {
    input:=Str:Obj?["schemaVersion":1,"requestId":"capture","reportScope":["dimension":"metering","nodeIds":["a"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"month","from":start.toIso,"to":finish.toIso],"asOf":finish.toIso,"modules":["balance"],"comparison":["mode":"none"]]
    FinEnergyCockpit.execute(input,records,|Str:Obj? q,[Str:Obj?][] rs->[Str:Obj?][]| {verifyNull(q["_cockpitDiagnosticCapture"]);return histories},"test",TimeZone.utc,finish)
    input["payloadEncoding"]="compact-v1"
    wire:=FinEnergyCockpit.execute(input,records,|Str:Obj? q,[Str:Obj?][] rs->[Str:Obj?][]| {verifyEq(q["_cockpitDiagnosticCapture"],true);return histories},"test",TimeZone.utc,finish)
    verifyEq(wire["payloadEncoding"],"compact-v1")
  }

  private Str:Obj? withoutDiagnosticPeriods(Str:Obj? original)
  {
    r:=(Str:Obj?)JsonInStream(JsonOutStream.writeJsonToStr(original).in).readJson
    remove:=["periods","periodsCaptureId","periodRecordTotalCount","periodsReturnedCount","periodsTruncated","periodsTruncationReason"]
    each:=FinEnergyMath.maps(r["rows"]).dup.addAll(FinEnergyMath.maps(((Map)((Map)r["extra"])["energyFlowOverview"])["rows"]))
    each.each |row| {remove.each |key| {row.remove(key)}}
    stripCaptureIds(r)
    return r
  }
  private Void stripCaptureIds(Obj? value)
  {
    if(value is Map) {m:=(Map)value;m.keys.each |key| {if(key.toStr.endsWith("CaptureId")) m.remove(key);else stripCaptureIds(m[key])}}
    else if(value is List) ((List)value).each |v| {stripCaptureIds(v)}
  }
  private Str:Obj? query() {["kind":"energyFlow","dimension":"metering","nodeIds":["a"],"categoryId":"c","categoryIds":["c"],"metric":"energy","period":"day","from":start.toIso,"to":finish.toIso,"asOf":finish.toIso,"_cockpitCategoryId":"c"]}
  private [Str:Obj?][] records() {[["id":"c","kind":"category","unit":"kWh"],["id":"a","kind":"totalMeter","pointId":"pa","categoryId":"c"],["id":"b","kind":"meter","pointId":"pb","meterParentId":"a","categoryId":"c"]]}
  private [Str:Obj?][] histories() { ["pa","pb"].map |p->[Str:Obj?]| {["pointId":p,"mode":"interval","unit":"kWh","samples":(0..<720).map |i->[Str:Obj?]| {["ts":(start+Duration(i*1hr.ticks)).toIso,"value":(i%3).toFloat]}]} }
  private DateTime start() {DateTime("2025-01-01T00:00:00Z UTC")}
  private DateTime finish() {start+30day}
}

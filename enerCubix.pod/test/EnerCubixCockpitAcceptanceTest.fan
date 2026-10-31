using util

** Cross-module acceptance over one frozen primary-history request.
class EnerCubixCockpitAcceptanceTest : Test
{
  Void testAllSixFacesShareOnePreparedBoundaryAndObservation()
  {
    loads:=0;events:=0
    result:=EnerCubixCockpit.execute(request,records,|Str:Obj? q,[Str:Obj?][] rs->[Str:Obj?][]|
    {
      loads++
      verifyEq(EnerCubixMath.strings(q["_cockpitPointIds"]),["pi","po"])
      return histories
    },"test",TimeZone.utc,end,false,|->DateTime| {end+1hr},|->[Str:Obj?][]|
    {
      events++
      return [["id":"event","nodeId":"in","categoryId":"elec","sourceIds":["pi"],"nativeAlarmId":"event_offNormal","state":"acknowledged","episodeStartTs":(start-5hr).toIso,"lastTs":(start-1hr).toIso,"hourCount":5]]
    })
    verifyEq(loads,1);verifyEq(events,1)
    verifyEq(((Map)result["boundary"])["meterIds"],["in"])
    verifyEq(((Map)result["boundary"])["sourcePointIds"],["pi"])
    modules:=(Map)result["modules"];reports:=(Map)result["reports"]
    values:=EnerCubixMath.maps(((Map)((Map)modules["kpis"])["data"])["values"])
    verifyEq(values.find |m| {m["id"] == "energy"}["value"],300f)
    verifyEq(values.find |m| {m["id"] == "cost"}["value"],150f)
    verifyEq(values.find |m| {m["id"] == "co2"}["value"],60f)
    verifyEq(values.find |m| {m["id"] == "areaIntensity"}["value"],0.3f)
    time:=(Map)((Map)modules["time"])["data"]
    verifyEq(((List)time["heatmap"]).size,24)
    uses:=(Map)reports[((Map)((Map)modules["endUse"])["data"])["reportRef"]]
    share:=EnerCubixMath.maps(((Map)uses["extra"])["utilityShares"]).first
    verifyEq(share["knownValue"],300f);verifyEq(share["knownPercentage"],100f)
    organization:=(Map)((Map)modules["organization"])["data"]
    verifyEq(EnerCubixMath.maps(organization["nodes"]).first["value"],300f)
    cop:=EnerCubixMath.maps(((Map)((Map)modules["efficiency"])["data"])["items"]).first
    verifyEq(((Map)cop["numerator"])["value"],1200f)
    verifyEq(((Map)cop["denominator"])["value"],300f)
    verifyEq(((Map)cop["ratio"])["value"],4f)
    flow:=(Map)reports[((Map)((Map)modules["balance"])["data"])["reportRef"]]
    graph:=EnerCubixMath.maps(((Map)flow["extra"])["energyFlowGraphs"]).first
    verifyEq(EnerCubixMath.maps(graph["nodes"]).find |n| {n["id"] == graph["focusId"]}["knownValue"],300f)
    issues:=(Map)((Map)modules["issues"])["data"]
    verifyEq(issues["activeEventCount"],1f)
    verifyEq(issues["stateObservedAt"],(end+1hr).toIso)
    event:=EnerCubixMath.maps(issues["items"]).find |i| {i["id"] == "event"}
    verifyEq(event["acknowledged"],true);verifyEq(event["hourCount"],5)
    verifyEq(event["evidenceFrom"],(start-5hr).toIso)
    verifyEq(((Map)result["context"])["asOf"],end.toIso)
    verify(JsonOutStream.writeJsonToStr(result).toBuf.size < 8388608)
    fixture:=Env.cur.vars["ENERCUBIX_COCKPIT_COMPLETE_FIXTURE"]
    if (fixture != null) File.os(fixture).out.writeChars(JsonOutStream.writeJsonToStr(result)).close
  }

  Void testUnavailableTariffKeepsOtherModulesAndPrimaryEnergy()
  {
    rs:=records
    rs.find |r| {r["id"] == "tariff"}["rate"]="invalid-native-value"
    result:=run(rs,histories)
    values:=EnerCubixMath.maps(((Map)((Map)((Map)result["modules"])["kpis"])["data"])["values"])
    verifyNull(values.find |m| {m["id"] == "cost"}["value"])
    verifyEq(values.find |m| {m["id"] == "energy"}["value"],300f)
    verifyEq(values.find |m| {m["id"] == "co2"}["value"],60f)
    cop:=EnerCubixMath.maps(((Map)((Map)((Map)result["modules"])["efficiency"])["data"])["items"]).first
    verifyEq(((Map)cop["ratio"])["value"],4f)
    verifyEq(((Map)result["boundary"])["sourcePointIds"],["pi"])
  }

  Void testLateHistoryAndNewConfigurationCreateNewSnapshotsWithoutChangingOld()
  {
    first:=run(records,histories)
    hs:=histories
    ((Map)((List)hs.first["samples"]).last)["value"]=310f
    late:=run(records,hs)
    verify(first["snapshotId"] != late["snapshotId"])
    verifyEq(first["context"],late["context"])
    verifyEq(((Map)first["provenance"])["configFingerprint"],((Map)late["provenance"])["configFingerprint"])
    firstValues:=EnerCubixMath.maps(((Map)((Map)((Map)first["modules"])["kpis"])["data"])["values"])
    lateValues:=EnerCubixMath.maps(((Map)((Map)((Map)late["modules"])["kpis"])["data"])["values"])
    verifyEq(firstValues.find |m| {m["id"] == "energy"}["value"],300f)
    verifyEq(lateValues.find |m| {m["id"] == "energy"}["value"],310f)
    rs:=records
    rs.find |r| {r["id"] == "tariff"}.setAll(["mod":"new-version","rate":0.6f])
    newer:=run(rs,histories)
    verify(((Map)first["provenance"])["configFingerprint"] != ((Map)newer["provenance"])["configFingerprint"])
    nextValues:=EnerCubixMath.maps(((Map)((Map)((Map)newer["modules"])["kpis"])["data"])["values"])
    verifyEq(nextValues.find |m| {m["id"] == "cost"}["value"],180f)
    verifyEq(firstValues.find |m| {m["id"] == "cost"}["value"],150f)
  }

  private Str:Obj? run([Str:Obj?][] rs,[Str:Obj?][] hs)
  {EnerCubixCockpit.execute(request,rs,|q,saved->[Str:Obj?][]| {hs},"test",TimeZone.utc,end)}
  private DateTime start() {DateTime.fromIso("2026-10-01T00:00:00Z")}
  private DateTime end() {start+1day}
  private Str:Obj? request() {["schemaVersion":1,"requestId":"joint-acceptance","reportScope":["dimension":"metering","nodeIds":["in"],"selectionIntent":"range"],"focusCategoryId":"elec","time":["preset":"custom","period":"day","from":start.toIso,"to":end.toIso],"asOf":end.toIso,"comparison":["mode":"none"],"modules":["kpis","trend","time","endUse","organization","balance","efficiency","issues"]]}
  private [Str:Obj?][] records()
  {[
    ["id":"elec","kind":"category","name":"Electricity","unit":"kWh"],
    ["id":"heat","kind":"category","name":"Cooling","unit":"kWh"],
    ["id":"plant","kind":"space","name":"Plant","nativeSourceId":"plant","nativeSourceKind":"floor","area":1000f],
    ["id":"sub","kind":"subcategory","categoryId":"elec","co2Factor":0.2f],
    ["id":"tariff","kind":"tariff","categoryId":"elec","mode":"flat","rate":0.5f],
    ["id":"use","kind":"utility","categoryId":"elec","name":"Service"],
    ["id":"org","kind":"organization","name":"Department"],
    ["id":"in","kind":"meter","name":"输入电表原名","pointId":"pi","categoryId":"elec","spaceId":"plant","nativeSpaceId":"plant","areaSource":"space","areaSpaceId":"plant","subcategoryId":"sub","tariffId":"tariff","utilityId":"use","organizationId":"org"],
    ["id":"out","kind":"meter","name":"供冷表原名","pointId":"po","categoryId":"heat","spaceId":"plant","nativeSpaceId":"plant","areaSource":"space","areaSpaceId":"plant"],
    ["id":"cop","kind":"cop","name":"Plant COP","numeratorId":"out","denominatorId":"in","baselineEfficiency":3.5f]
  ]}
  private [Str:Obj?][] histories()
  {
    return ["pi","po"].map |id,Int index->[Str:Obj?]|
    {
      rows:=[Str:Obj?][,]
      (0..24).each |hour| {rows.add(["ts":(start+1hr*hour).toIso,"value":hour*(index == 0 ? 12.5f : 50f)])}
      return ["pointId":id,"unit":"kWh","mode":"cumulative","intervalSeconds":3600f,"samples":rows]
    }
  }
}

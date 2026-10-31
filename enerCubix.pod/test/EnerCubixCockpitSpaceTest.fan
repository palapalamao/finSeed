using util

class EnerCubixCockpitSpaceTest : Test
{
  Void testReadableAncestorNeverExposesUnreadableSiblingIdentifiers()
  {
    rs:=records;rs.find |r| {r["id"] == "b"}["_comparisonReadable"]=false
    q:=request;q["reportScope"]=["dimension":"metering","nodeIds":["a"],"selectionIntent":"range"]
    result:=EnerCubixCockpit.execute(q,rs,|rq,saved->[Str:Obj?][]| {[histories.first]},"test",TimeZone.utc,end)
    f:=nodes(result).find |n| {n["id"] == "f"}
    verify(!((List)f["meterIds"]).contains("b"));verify(!((List)f["sourceIds"]).contains("pb"))
    verifyNull(f["value"]);verifyEq(f["reasonCodes"],["FOCUS_NOT_LOADED"])
    verifyEq(nodes(result).find |n| {n["id"] == "a"}["value"],10f)
  }
  Void testFocusUsesSamePreparedOwnHistoryAndRealHierarchyWithoutChangingKpis()
  {
    calls:=0
    q:=request;q["modules"]=["kpis","trend","space","time","endUse","organization","balance","efficiency","issues"]
    result:=EnerCubixCockpit.execute(q,records,|Str:Obj? rq,[Str:Obj?][] rs->[Str:Obj?][]| {calls++;verifyEq(rq["_cockpitPointIds"],["pa","pb"]);return histories},"test",TimeZone.utc,end)
    verifyEq(calls,1)
    verifyEq(((Map)result["modules"]).keys.sort,["balance","efficiency","endUse","issues","kpis","organization","space","time","trend"])
    nodes:=nodes(result)
    verifyEq(nodes.find |n| {n["id"] == "f"}["value"],30f)
    verifyEq(nodes.find |n| {n["id"] == "a"}["value"],10f)
    verifyEq(nodes.find |n| {n["id"] == "a"}["basis"],"ownPrimary")
    verifyEq(nodes.find |n| {n["id"] == "f"}["basis"],"scopeAggregate")
    verifyEq(nodes.find |n| {n["id"] == "a"}["parentId"],"f")
    verifyEq(nodes.find |n| {n["id"] == "f"}["parentId"],"s")
    verifyEq(nodes.find |n| {n["id"] == "s"}["parentId"],null)
    verifyEq(nodes.find |n| {n["id"] == "a"}["sourceIds"],["pa"])
    verifyEq(nodes.find |n| {n["id"] == "s"}["nativeId"],"s")
    verifyEq(((Map)((Map)((Map)result["modules"])["space"])["data"])["rootIds"],["s"])
    baseline:=request;baseline["modules"]=["kpis","trend"]
    before:=EnerCubixCockpit.execute(baseline,records,|rq,rs->[Str:Obj?][]| {histories},"test",TimeZone.utc,end)
    verifyEq(energy(before)["value"],energy(result)["value"])
    verifyEq(((Map)before["boundary"])["meterIds"],((Map)result["boundary"])["meterIds"])
    fixture:=Env.cur.vars["ENERCUBIX_COCKPIT_SPACE_FIXTURE"]
    if (fixture != null) File.os(fixture).out.writeChars(JsonOutStream.writeJsonToStr(result)).close
  }

  Void testUnplannedOwnPrimaryIsNotReplacedByChildrenAndUnknownRemainsUnloaded()
  {
    rs:=records;rs.add(["id":"t","kind":"totalMeter","nativeEquip":true,"nativeSourceKind":"equip","name":"Master","pointId":"pt","categoryId":"c","spaceId":"f","nativeTreeParentId":"f"])
    rs.findAll |r| {["a","b"].contains(r["id"])}.each |r| {r["meterParentId"]="t"}
    q:=request;q["reportScope"]=["dimension":"metering","nodeIds":["a","b"],"selectionIntent":"range"]
    result:=EnerCubixCockpit.execute(q,rs,|rq,saved->[Str:Obj?][]| {histories},"test",TimeZone.utc,end)
    // The ancestor floor's own effective scope requires pt, not a child sum.
    f:=nodes(result).find |n| {n["id"] == "f"}
    verifyNull(f["value"]);verifyEq(f["reasonCodes"],["FOCUS_NOT_LOADED"])
    verifyEq(nodes(result).find |n| {n["id"] == "a"}["value"],10f)
    q=request
    result=EnerCubixCockpit.execute(q,rs,|rq,saved->[Str:Obj?][]| {[Str:Obj?][,]},"test",TimeZone.utc,end)
    t:=nodes(result).find |n| {n["id"] == "t"}
    verifyNull(t["value"]);verifyEq(t["basis"],"ownPrimary")
    verifyEq(t["reasonCodes"],["FOCUS_NOT_LOADED"])
  }

  Void testMissingNaZeroAndHiddenNamesRemainDistinct()
  {
    hs:=histories;hs.first["samples"]=[["ts":start.toIso,"value":0f],["ts":(start+1hr).toIso,"value":0f]]
    hs.last["samples"]=[["ts":start.toIso,"value":null,"quality":"na","valueType":"na"],["ts":(start+1hr).toIso,"value":null,"quality":"na","valueType":"na"]]
    rs:=records;rs.add(["id":"hidden","kind":"space","name":"Secret sentinel","nativeSourceKind":"floor","nativeHidden":true])
    result:=EnerCubixCockpit.execute(request,rs,|q,saved->[Str:Obj?][]| {hs},"test",TimeZone.utc,end)
    verifyEq(nodes(result).find |n| {n["id"] == "a"}["value"],0f)
    verifyEq(nodes(result).find |n| {n["id"] == "b"}["valueType"],"na")
    verify(!JsonOutStream.writeJsonToStr(((Map)result["modules"])["space"]).contains("Secret sentinel"))
  }

  Void testUnenrolledNativeEquipmentCannotBorrowContainedChildHistory()
  {
    rs:=records;rs.add(["id":"equipment-folder","kind":"space","name":"Equipment","nativeSourceKind":"equip","parentId":"f"])
    rs.findAll |r| {["a","b"].contains(r["id"])}.each |r| {r["nativeTreeParentId"]="equipment-folder"}
    result:=EnerCubixCockpit.execute(request,rs,|q,saved->[Str:Obj?][]| {histories},"test",TimeZone.utc,end)
    folder:=nodes(result).find |n| {n["id"] == "equipment-folder"}
    verifyEq(folder["basis"],"ownPrimary");verifyNull(folder["value"])
    verifyEq(folder["reasonCodes"],["FOCUS_NOT_LOADED"])
    verifyEq(nodes(result).find |n| {n["id"] == "a"}["value"],10f)
    verifyEq(nodes(result).find |n| {n["id"] == "f"}["value"],30f)
  }

  private [Str:Obj?][] nodes(Str:Obj? r) {EnerCubixMath.maps(((Map)((Map)((Map)r["modules"])["space"])["data"])["nodes"])}
  private Map energy(Str:Obj? r) {(Map)((List)((Map)((Map)((Map)r["modules"])["kpis"])["data"])["values"]).first}
  private DateTime start() {DateTime.fromIso("2026-10-01T00:00:00Z")}
  private DateTime end() {start+2hr}
  private Str:Obj? request() {["schemaVersion":1,"requestId":"space-test","reportScope":["dimension":"space","nodeIds":["s"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"hour","from":start.toIso,"to":end.toIso],"asOf":end.toIso,"comparison":["mode":"none"],"modules":["kpis","trend","space"]]}
  private [Str:Obj?][] records() {[["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space","name":"Site","nativeSourceId":"s","nativeSourceKind":"site"],["id":"f","kind":"space","name":"Floor","nativeSourceId":"f","nativeSourceKind":"floor","parentId":"s"],["id":"a","kind":"meter","nativeEquip":true,"nativeSourceKind":"equip","name":"Meter A","pointId":"pa","categoryId":"c","spaceId":"f","nativeTreeParentId":"f"],["id":"b","kind":"meter","nativeEquip":true,"nativeSourceKind":"equip","name":"Meter B","pointId":"pb","categoryId":"c","spaceId":"f","nativeTreeParentId":"f"]]}
  private [Str:Obj?][] histories() {[["pointId":"pa","unit":"kWh","mode":"interval","samples":[["ts":start.toIso,"value":5f],["ts":(start+1hr).toIso,"value":5f]]],["pointId":"pb","unit":"kWh","mode":"interval","samples":[["ts":start.toIso,"value":10f],["ts":(start+1hr).toIso,"value":10f]]]]}
}

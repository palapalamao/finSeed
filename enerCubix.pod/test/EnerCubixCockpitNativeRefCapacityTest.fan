using util

** Offline full-query fixtures: native-form references and Chinese names are
** synthetic. These are not reads, records or business verification in FIN.
class EnerCubixCockpitNativeRefCapacityTest : Test
{
  Void testAnnualSiteWithNativeFormRefs() {verifyScope("site")}
  Void testAnnualTotalWithNativeFormRefs() {verifyScope("total")}
  Void testAnnualLeafWithNativeFormRefs() {verifyScope("leaf")}

  private Void verifyScope(Str scope)
  {
    tz:=TimeZone("Shanghai")
    from:=DateTime.fromIso("2025-01-01T00:00:00+08:00").toTimeZone(tz)
    to:=DateTime.fromIso("2026-01-01T00:00:00+08:00").toTimeZone(tz)
    reference:=DateTime.fromIso("2024-01-01T00:00:00+08:00").toTimeZone(tz)
    category:=refId(1);sub:=refId(2);tariff:=refId(3);site:=refId(4);floor:=refId(5)
    rs:=[Str:Obj?][["id":category,"kind":"category","name":"电能","unit":"kWh"],["id":site,"kind":"space","name":"离线容量测试园区","nativeSourceKind":"site","nativeSourceId":site],["id":floor,"kind":"space","name":"一号楼一层能源计量区域","nativeSourceKind":"floor","nativeSourceId":floor,"parentId":site],["id":sub,"kind":"subcategory","name":"外购电","categoryId":category,"co2Factor":0.5f],["id":tariff,"kind":"tariff","name":"离线普通费率","mode":"flat","rate":2f]]
    hs:=[Str:Obj?][,]
    (0..<9).each |i|
    {
      id:=refId(100+i);point:=refId(1000+i)
      r:=Str:Obj?["id":id,"name":i == 0 ? "一号楼总电表中文业务名称" : "一号楼一层空调用电分表"+i,"kind":i == 0 ? "totalMeter" : "meter","nativeEquip":true,"nativeSourceKind":"equip","nativeTreeParentId":floor,"spaceId":floor,"pointId":point,"categoryId":category,"subcategoryId":sub,"tariffId":tariff]
      if (i > 0) r["meterParentId"]=refId(100)
      rs.add(r)
      rows:=[Str:Obj?][,];cursor:=reference;hour:=0
      while (cursor < to) {rows.add(["ts":cursor.toIso,"value":i == 0 ? 9f+(hour%3)*0.1f : 1f]);cursor+=1hr;hour++}
      hs.add(["pointId":point,"unit":"kWh","mode":"interval","samples":rows])
    }
    selected:=scope == "site" ? site : refId(scope == "total" ? 100 : 101)
    q:=Str:Obj?["schemaVersion":1,"requestId":"native-shape-"+scope,"reportScope":["dimension":scope == "site" ? "space" : "metering","nodeIds":[selected],"selectionIntent":"range"],"focusCategoryId":category,"time":["preset":"custom","period":"month","from":from.toIso,"to":to.toIso],"asOf":to.toIso,"comparison":["mode":"custom","from":reference.toIso,"to":from.toIso],"modules":["kpis","trend","space","time","endUse","organization","balance","efficiency","issues"]]
    calls:=0;began:=Duration.nowTicks
    snapshot:=EnerCubixCockpit.execute(q,rs,|Str:Obj? rq,[Str:Obj?][] saved->[Str:Obj?][]| {calls++;return hs.findAll |h| {EnerCubixMath.strings(rq["_cockpitPointIds"]).contains(h["pointId"]) }},"cubeTest",tz,to)
    verifyEq(calls,1)
    energy:=EnerCubixMath.maps(((Map)((Map)((Map)snapshot["modules"])["kpis"])["data"])["values"]).find |v| {v["id"] == "energy"}
    expected:=scope == "leaf" ? 8760f : 79716f
    verify((EnerCubixMath.num(energy["value"])-expected).abs < 0.00001f)
    projectionMs:=(Duration.nowTicks-began)/1ms.ticks
    bounded:=EnerCubixCockpitDiagnostics.project(snapshot)
    verifyEq(bounded["context"],snapshot["context"]);verifyEq(bounded["modules"],snapshot["modules"])
    verifyEq(bounded["provenance"],snapshot["provenance"])
    ((Map)snapshot["reports"]).each |original,ref|
    {
      actual:=(Map)((Map)bounded["reports"])[ref];report:=(Map)original
      verifyEq(actual["summary"],report["summary"]);verifyEq(actual["series"],report["series"])
      foreachKey:=["energyFlowGraphs","energyFlowAccounting","energyFlow","usageCoverage","tariffSnapshot","utilityShares","areaBasis"]
      foreachKey.each |field| {verifyEq(((Map)actual["extra"])[field],((Map)report["extra"])[field])}
    }
    wire:=EnerCubixCockpitPayload.encode(bounded)
    bytes:=JsonOutStream.writeJsonToStr(["ok":true,"data":wire]).toBuf.size
    echo("NATIVE_REF_CAPACITY scope=$scope refChars=${category.size} wireBytes=$bytes projectionMs=$projectionMs")
    dir:=Env.cur.vars["ENERCUBIX_NATIVE_REF_FIXTURE_DIR"]
    if (dir != null)
    {
      File.os(dir+"/"+scope+".full.logical.json").out.writeChars(JsonOutStream.writeJsonToStr(snapshot)).close
      File.os(dir+"/"+scope+".logical.json").out.writeChars(JsonOutStream.writeJsonToStr(bounded)).close
      File.os(dir+"/"+scope+".wire.json").out.writeChars(JsonOutStream.writeJsonToStr(wire)).close
    }
    verify(bytes <= 8388608,"Native-form refs and Chinese names must fit the existing full-wire limit")
  }
  private Str refId(Int index) {"p:cubeTest:r:"+(0x7f000000+index).toHex(8)+"-1a000001"}
}

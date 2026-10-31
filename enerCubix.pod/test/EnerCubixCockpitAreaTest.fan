using util
using haystack

** Controlled primary-point histories; no live FIN reads or writes.
class EnerCubixCockpitAreaTest : Test
{
  Void testSerializedSharedFloorResolutionAndFormula()
  {
    snapshot:=run(records,"metering",["lighting","power"])
    r:=serialized(snapshot)
    verifyEq(metric(r,"energy")["value"],300f)
    near(metric(r,"areaIntensity")["value"],0.3f)
    area:=resolution(r)
    verifyEq(area.keys.sort,["status","areaM2","basis","spaceRefs","customBoundaryIds","excludedOverlaps","energyBoundaryId","sourceRevisions","reasonCodes"].sort)
    verifyEq(area["status"],"ok");verifyEq(area["areaM2"],1000f)
    verifyEq(area["basis"],"nativeSpace");verifyEq(area["spaceRefs"],Obj?["floor"])
    verifyEq(area["energyBoundaryId"],((Map)r["boundary"])["id"])
    revisions:=EnerCubixMath.maps(area["sourceRevisions"])
    verifyEq(revisions.size,1);verifyEq(revisions.first["nativeRef"],"floor")
    verifyEq(revisions.first["mod"],at.toIso);verifyEq(revisions.first["area"],1000f)
    verifyEq(((Map)revisions.first["nativeArea"])["value"],1000f)
    verifyEq(((Map)revisions.first["nativeArea"])["unit"],"m²")
    details:=(Map)metric(r,"areaIntensity")["details"]
    formula:=(Map)details["formula"]
    verifyEq(formula["version"],1);verifyEq(formula["expression"],"energy / areaM2")
    verifyEq(((Map)formula["numerator"])["value"],300f)
    verifyEq(((Map)formula["numerator"])["sourceIds"],Obj?["pl","pp"])
    verifyEq(((Map)formula["denominator"])["sourceRevisions"],area["sourceRevisions"])
    near(formula["value"],0.3f)
    verifyNotNull(details["areaBasis"])
    fixture:=Env.cur.vars["ENERCUBIX_COCKPIT_AREA_FIXTURE"]
    if (fixture != null) File.os(fixture).out.writeChars(JsonOutStream.writeJsonToStr(snapshot)).close
  }

  Void testSameEffectiveBoundaryAcrossSpaceMeteringAndOrganization()
  {
    [["space","floor"],["organization","org"],["metering","lighting","power"]].each |Str[] scope|
    {
      r:=run(records,scope.first,scope[1..-1])
      verifyEq(((Map)r["boundary"])["meterIds"],Str["lighting","power"])
      verifyNotNull(metric(r,"areaIntensity")["value"],scope.toStr+" "+metric(r,"areaIntensity"))
      near(metric(r,"areaIntensity")["value"],0.3f)
      verifyEq(resolution(r)["spaceRefs"],Str["floor"])
      verifyEq(resolution(r)["areaM2"],1000f)
    }
  }

  Void testPlacementIsNeverAServiceAreaAndRawEnergySurvives()
  {
    rs:=records
    rs.findAll |r| {r["kind"] == "meter"}.each |r| {r.remove("areaSource");r.remove("areaSpaceId")}
    r:=run(rs,"metering",["lighting","power"])
    verifyEq(metric(r,"energy")["value"],300f)
    verifyNull(metric(r,"areaIntensity")["value"])
    verifyEq(resolution(r)["status"],"ambiguousArea")
    verifyNull(resolution(r)["areaM2"])
    verify(((List)resolution(r)["reasonCodes"]).contains("ambiguousArea"))
    verifyEq(((Map)((Map)metric(r,"areaIntensity")["details"])["formula"])["value"],null)
  }

  Void testContainmentExcludesFloorAndOnlyKeepsParticipatingSource()
  {
    rs:=records;rs.find |r| {r["id"] == "power"}["areaSpaceId"]="site"
    r:=run(rs,"metering",["lighting","power"])
    near(metric(r,"areaIntensity")["value"],0.1f)
    area:=resolution(r)
    verifyEq(area["spaceRefs"],Str["site"]);verifyEq(area["areaM2"],3000f)
    excluded:=EnerCubixMath.maps(area["excludedOverlaps"])
    verifyEq(excluded.size,1);verifyEq(excluded.first["id"],"floor")
    verifyEq(excluded.first["coveredBy"],"site")
    verifyEq(EnerCubixMath.maps(area["sourceRevisions"]).map |s->Str| {s["id"].toStr},Str["site"])
    r=run(rs,"space",["site","floor"])
    verifyEq(resolution(r)["areaM2"],3000f)
    near(metric(r,"areaIntensity")["value"],0.1f)
  }

  Void testUnknownCustomOverlapCannotMakeMixedIntensity()
  {
    rs:=records
    rs.findAll |r| {r["kind"] == "meter"}.each |r| {r["areaSource"]="custom";r["area"]=1000f}
    r:=run(rs,"metering",["lighting","power"])
    verifyEq(metric(r,"energy")["value"],300f);verifyNull(metric(r,"areaIntensity")["value"])
    verifyEq(resolution(r)["status"],"ambiguousArea")
    verifyEq(resolution(r)["customBoundaryIds"],Str["lighting","power"])
    verifyNull(resolution(r)["areaM2"])
    rs.find |v| {v["id"] == "lighting"}["areaSource"]="space"
    r=run(rs,"metering",["lighting","power"])
    verifyNull(metric(r,"areaIntensity")["value"])
    verifyEq(resolution(r)["status"],"ambiguousArea")
  }

  Void testMissingInvalidAndIncompatibleNativeAreaKeepEnergy()
  {
    Obj?[] invalids:=[null,0f,-1f,Float.nan,Float.posInf]
    invalids.each |invalid|
    {
      rs:=records;rs.find |r| {r["id"] == "floor"}["area"]=invalid
      r:=run(rs,"metering",["lighting","power"])
      verifyEq(metric(r,"energy")["value"],300f)
      verifyNull(metric(r,"areaIntensity")["value"])
      verifyEq(resolution(r)["status"],"missingArea")
      verifyNull(resolution(r)["areaM2"])
      serialized(r) // Invalid numeric inputs must not leak NaN/INF into evidence JSON.
    }
  }

  Void testNativeAreaAndModChangesProduceANewFingerprintAndFreezeOldFormula()
  {
    rs:=records
    old:=run(rs,"metering",["lighting","power"])
    saved:=JsonOutStream.writeJsonToStr(old)
    floor:=rs.find |r| {r["id"] == "floor"}
    floor["area"]=2000f;floor["mod"]=(at+1sec).toIso
    floor["nativeArea"]=EnerCubixSpaceArea.provenance(Etc.makeDict(["id":Ref("floor"),"mod":at+1sec,"area":Number(2000f,Unit.fromStr("m²"))]))
    current:=run(rs,"metering",["lighting","power"])
    near(metric(current,"areaIntensity")["value"],0.15f)
    verify(((Map)old["provenance"])["configFingerprint"] != ((Map)current["provenance"])["configFingerprint"])
    verifyEq(JsonOutStream.writeJsonToStr(old),saved)
    verify(old.isImmutable)
    verifyEq(EnerCubixMath.maps(resolution(old)["sourceRevisions"]).first["mod"],at.toIso)
    verifyEq(EnerCubixMath.maps(resolution(current)["sourceRevisions"]).first["mod"],(at+1sec).toIso)
    verifyEq(((Map)EnerCubixMath.maps(resolution(old)["sourceRevisions"]).first["nativeArea"])["value"],1000f)
    before:=((Map)current["provenance"])["configFingerprint"]
    floor["mod"]=(at+2sec).toIso
    verify(before != ((Map)run(rs,"metering",["lighting","power"])["provenance"])["configFingerprint"])
  }

  Void testTotalAndChildrenDoNotAddOrBorrowChildArea()
  {
    rs:=records
    rs.find |r| {r["id"] == "lighting"}.setAll(["kind":"totalMeter","areaSource":"custom","area":2000f])
    rs.find |r| {r["id"] == "power"}["meterParentId"]="lighting"
    r:=run(rs,"metering",["lighting","power"])
    verifyEq(metric(r,"energy")["value"],120f)
    near(metric(r,"areaIntensity")["value"],0.06f)
    verifyEq(resolution(r)["customBoundaryIds"],Str["lighting"])
    q:=request("metering",["lighting","power"])
    q["reportScope"]=["dimension":"metering","nodeIds":["lighting","power"],"selectionIntent":"explicitObjects"]
    r=execute(q,rs)
    verifyNull(metric(r,"areaIntensity")["value"])
    verify(((List)metric(r,"areaIntensity")["reasonCodes"]).contains("overlappingScopes"))
  }

  Void testOtherEnergyAndIncompatibleUnitAreNeverInventedIntoIntensity()
  {
    rs:=records
    rs.add(["id":"water","kind":"category","unit":"m³"])
    rs.add(["id":"w","kind":"meter","categoryId":"water","organizationId":"org","spaceId":"floor","pointId":"pw","areaSource":"custom","area":13f])
    r:=run(rs,"organization",["org"])
    near(metric(r,"areaIntensity")["value"],0.3f)
    hs:=histories;hs.last["unit"]="m³"
    r=execute(request("metering",["lighting","power"]),records,hs)
    verifyNull(metric(r,"areaIntensity")["value"])
    verify(((List)metric(r,"areaIntensity")["reasonCodes"]).contains("incompatibleUnit"))
  }

  Void testNativeProvenanceIsFromOriginalNumberRefAndMod()
  {
    original:=Etc.makeDict(["id":Ref("native-floor"),"floor":Marker.val,"mod":at,"area":Number(1000f,Unit.fromStr("ft²"))])
    proof:=EnerCubixSpaceArea.provenance(original)
    verifyEq(proof["nativeRef"],"native-floor");verifyEq(proof["mod"],at.toIso)
    verifyEq(proof["tag"],"area");verifyEq(proof["value"],1000f);verifyEq(proof["unit"],"ft²")
    verify(((Float)proof["areaM2"]-92.90304f).abs < 0.0001f)
    source:=EnerCubixNativeSpace()
    source.nodes=[["id":"native-floor","sourceKind":"floor","name":"Floor","mod":at.toIso,"area":92.90304f,"nativeArea":proof]]
    projected:=source.project([["id":"overlay","kind":"space","migrationSourceId":"native-floor","area":999f,"mod":"overlay-mod"]])
    area:=EnerCubixArea(projected).node("overlay")
    row:=EnerCubixMath.maps(area["sources"]).first
    verifyEq(row["nativeRef"],"native-floor");verifyEq(row["mod"],at.toIso)
    verifyEq(row["nativeArea"],proof)
    bad:=Etc.makeDict(["id":Ref("native-floor"),"floor":Marker.val,"area":Number(5f,Unit.fromStr("kWh"))])
    verifyNull(EnerCubixSpaceArea.provenance(bad)["areaM2"])
  }

  private Map serialized(Map value) {JsonInStream(JsonOutStream.writeJsonToStr(value).in).readJson}
  private Map metric(Map r,Str id) {((List)((Map)((Map)((Map)r["modules"])["kpis"])["data"])["values"]).find |Map m->Bool| {m["id"] == id}}
  private Map resolution(Map r) {area:=((Map)metric(r,"areaIntensity")["details"])["areaResolution"] as Map;verifyNotNull(area);return area}
  private Void near(Obj? actual,Float expected) {verifyNotNull(actual);verify(((Float)actual).approx(expected,0.000001f))}
  private Str:Obj? run([Str:Obj?][] rs,Str dim,Str[] ids) {execute(request(dim,ids),rs)}
  private Str:Obj? execute(Str:Obj? q,[Str:Obj?][] rs,[Str:Obj?][] hs := histories)
  {EnerCubixCockpit.execute(q,rs,|rq,recs->[Str:Obj?][]| {hs},"test",TimeZone.utc,at+1hr,false,|->DateTime| {at+1hr})}
  private DateTime at() {DateTime.fromIso("2026-10-01T00:00:00Z")}
  private Str:Obj? request(Str dim,Str[] ids) {["schemaVersion":1,"requestId":"area-test","reportScope":["dimension":dim,"nodeIds":ids,"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"hour","from":at.toIso,"to":(at+1hr).toIso],"asOf":(at+1hr).toIso,"modules":["kpis"],"comparison":["mode":"none"]]}
  private [Str:Obj?][] records()
  {
    source:=EnerCubixNativeSpace()
    source.nodes=[nativeNode("site",3000f,"site"),nativeNode("floor",1000f,"floor").set("parentId","site")]
    source.nodes.addAll([["id":"pl","sourceKind":"point","name":"Lighting energy","parentId":"floor","his":true],
      ["id":"pp","sourceKind":"point","name":"Power energy","parentId":"floor","his":true]])
    return source.project([["id":"c","kind":"category","unit":"kWh"],["id":"org","kind":"organization","name":"Organization"],meter("lighting","pl"),meter("power","pp")])
  }
  private Str:Obj? nativeNode(Str id,Float area,Str kind)
  {
    original:=Etc.makeDict(["id":Ref(id),kind:Marker.val,"mod":at,"area":Number(area,Unit.fromStr("m²"))])
    return ["id":id,"sourceKind":kind,"name":id,"mod":at.toIso,"area":area,"nativeArea":EnerCubixSpaceArea.provenance(original)]
  }
  private Str:Obj? meter(Str id,Str point) {["id":id,"kind":"meter","nativeEquip":true,"name":id,"categoryId":"c","pointId":point,"spaceId":"floor","nativeSpaceId":"floor","organizationId":"org","areaSource":"space","areaSpaceId":"floor","mod":id+"-v1"]}
  private [Str:Obj?][] histories() {[["pointId":"pl","unit":"kWh","mode":"interval","samples":[["ts":at.toIso,"value":120f]]],["pointId":"pp","unit":"kWh","mode":"interval","samples":[["ts":at.toIso,"value":180f]]]]}
}

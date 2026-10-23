using haystack

class SeedNativeEquipTest : Test
{
  Void testAutoSumPersistsAndRejectsMeasuredSource()
  {
    eq:=Etc.makeDict(["id":Ref("eq"),"equip":Marker.val])
    data:=meter("eq","p"); data["autoSum"]=true
    tags:=SeedNativeEquip.tags(data,eq,"admin")
    verifyEq(tags["seedAutoSum"],true)
    verifyEq(SeedNativeEquip.decode(Etc.makeDict(Etc.dictToMap(tags).set("id",eq.id)))["autoSum"],true)
    p:=Etc.makeDict(Etc.dictToMap(point("p","eq")).set("modbusConnRef",Ref("conn")))
    verifyErr(ArgErr#) { SeedNativeEquip.validateSource(data,eq,p,[category]) }
    data["autoSum"]=false
    SeedNativeEquip.validateSource(data,eq,p,[category])
  }

  Void testPatchOwnsOnlySeedTagsAndKeepsNativeIdentity()
  {
    equip:=Etc.makeDict(["id":Ref("equip"),"equip":Marker.val,"dis":"FIN 原名","siteRef":Ref("site"),"seedAlias":"旧别名"])
    tags:=SeedNativeEquip.tags(["kind":"meter","name":"短表名","pointId":"point","meterParentId":"master","includeInTotals":true],equip,"admin")
    verifyEq(tags["seedAlias"],"短表名")
    verifyEq(tags["seedPointRef"],Ref("point"))
    verifyEq(tags["seedMeterParentRef"],Ref("master"))
    verifyNull(tags["dis"]); verifyNull(tags["siteRef"]); verifyNull(tags["equipRef"])
    verifyEq(equip["dis"],"FIN 原名")
    clear:=SeedNativeEquip.clear(equip)
    verifyEq(clear["seedAlias"],Remove.val); verifyNull(clear["equip"])
  }

  Void testPreviewRejectsTwoArchivesForOneEquipment()
  {
    eq:=Etc.makeDict(["id":Ref("eq"),"equip":Marker.val])
    p:=point("p","eq"); p2:=point("p2","eq")
    plan:=SeedNativeEquip.preview([meter("a","p"),meter("b","p2"),category],[eq],[p,p2])
    verifyEq(((List)plan["conflicts"]).size,1)
    verifyEq(((Map)plan["mapping"]).size,1)
  }

  Void testPrimaryPointOwnershipHistoryAndEnergy()
  {
    eq:=Etc.makeDict(["id":Ref("eq"),"equip":Marker.val])
    data:=meter("eq","p")
    SeedNativeEquip.validateSource(data,eq,point("p","eq"),[category])
    verifyErr(ArgErr#) { SeedNativeEquip.validateSource(data,eq,point("p","other"),[category]) }
    verifyErr(ArgErr#) { SeedNativeEquip.validateSource(data,eq,Etc.makeDict(["id":Ref("p"),"point":Marker.val,"equipRef":eq.id]),[category]) }
    data["categoryId"]="water"
    verifyErr(ArgErr#) { SeedNativeEquip.validateSource(data,eq,point("p","eq"),[["id":"water","kind":"category","unit":"m³"]]) }
  }

  Void testRemapPreservesHistorySourcesAndLegacyGroups()
  {
    old:=Str:Obj?["id":"a","kind":"meter","name":"分表","parentId":"group","pointId":"p","meterParentId":"b","sourceIds":["p"],"request":["nodeIds":["a"],"referenceIds":["a","rawPoint"],"baselineId":"a"],"variables":["x":"b"]]
    out:=SeedNativeEquip.rewrite(old,["a":"eq-a","b":"eq-b"])
    verifyEq(out["id"],"eq-a"); verifyEq(out["pointId"],"p"); verifyEq(out["sourceIds"],["p"])
    verifyEq(out["parentId"],"group"); verifyEq(out["meterParentId"],"eq-b")
    verifyEq(((Map)out["request"])["nodeIds"],["eq-a"])
    verifyEq(((Map)out["variables"])["x"],"eq-b")
    verifyEq(old["id"],"a")
  }

  Void testNativeProjectionKeepsOneEquipmentAndItsBusinessFields()
  {
    source:=SeedNativeSpace()
    source.nodes=[["id":"site","name":"园区","sourceKind":"site"],["id":"eq","name":"FIN 原名","sourceKind":"equip","parentId":"site"],["id":"p","name":"电量","sourceKind":"point","parentId":"eq","his":true]]
    business:=meter("eq","p"); business["nativeEquip"]=true; business["name"]="短名"
    rows:=source.project([business])
    verifyEq(rows.findAll |r| { r["id"] == "eq" }.size,1)
    eq:=rows.find |r| { r["id"] == "eq" }
    verifyEq(eq["kind"],"meter"); verifyEq(eq["name"],"短名")
    verifyEq(eq["nativeTreeParentId"],"site"); verifyNull(eq["parentId"])
    verifyEq(eq["nativeReadonly"],false)
    verifyEq(rows.find |r| { r["id"] == "p" }["kind"],"nativePoint")
    SeedNativeSpace.mustEditable("eq",rows)
  }

  Void testSourceRevisionIgnoresCollectionUpdatesAndOrdering()
  {
    eq:=Etc.makeDict(["id":Ref("eq","缓存显示"),"equip":Marker.val,"floorRef":Ref("floor","旧显示"),"mod":DateTime.now])
    p:=point("p","eq"); p2:=point("p2","eq")
    signature:=SeedNativeEquip.sourceRevision([eq],[p,p2])
    edited:=Etc.dictToMap(eq); edited["mod"]=DateTime.now+1min; edited["floorRef"]=Ref("floor","新显示")
    verifyEq(SeedNativeEquip.sourceRevision([Etc.makeDict(edited)],[p2,p]),signature)
    edited["seedMaximum"]=Number(100f)
    verifyNotEq(SeedNativeEquip.sourceRevision([Etc.makeDict(edited)],[p,p2]),signature)
    foreign:=point("p","another")
    verifyNotEq(SeedNativeEquip.sourceRevision([eq],[foreign,p2]),signature)
  }

  private [Str:Obj?] category() { ["id":"cat","kind":"category","name":"电","unit":"kWh"] }
  private [Str:Obj?] meter(Str id, Str p) { ["id":id,"kind":"meter","name":id,"pointId":p,"categoryId":"cat"] }
  private Dict point(Str id, Str eq) { Etc.makeDict(["id":Ref(id),"point":Marker.val,"equipRef":Ref(eq),"unit":"kWh","his":Marker.val]) }
}

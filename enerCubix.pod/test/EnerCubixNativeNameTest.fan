using haystack

class EnerCubixNativeNameTest : Test
{
  Void testLegacyAliasDoesNotHideNativeRename()
  {
    source:=Str:Obj?["id":Ref("eq"),"equip":Marker.val,"dis":"总电表","navName":"总电表1F空调用电","enerCubixKind":"totalMeter","enerCubixAlias":"总电表","enerCubixPointRef":Ref("point")]
    record:=EnerCubixNativeEquip.decode(Etc.makeDict(source))
    verifyEq(record["name"],"总电表1F空调用电")
    verifyEq(record["nativeName"],"总电表1F空调用电")
    verifyEq(record["useAlias"],false)
    source["navName"]="总电表2F动力用电"
    refreshed:=EnerCubixNativeEquip.decode(Etc.makeDict(source))
    verifyEq(refreshed["name"],"总电表2F动力用电")
    verifyEq(refreshed["id"],record["id"])
    verifyEq(refreshed["pointId"],record["pointId"])
    verifyEq(source["enerCubixAlias"],"总电表")
  }

  Void testOnlyExplicitAliasOverridesNativeName()
  {
    source:=Str:Obj?["id":Ref("eq"),"dis":"FIN 原名","navName":"FIN 设备树名","enerCubixAlias":"自定义短名","enerCubixUseAlias":true]
    verifyEq(EnerCubixNativeEquip.decode(Etc.makeDict(source))["name"],"自定义短名")
    source["enerCubixUseAlias"]=false
    verifyEq(EnerCubixNativeEquip.decode(Etc.makeDict(source))["name"],"FIN 设备树名")
    source.remove("navName")
    verifyEq(EnerCubixNativeEquip.decode(Etc.makeDict(source))["name"],"FIN 原名")
    source["enerCubixUseAlias"]=true; source["enerCubixAlias"]="  "
    verifyEq(EnerCubixNativeEquip.decode(Etc.makeDict(source))["name"],"FIN 原名")
  }

  Void testSavingDefaultNameNeverCreatesAnImplicitAlias()
  {
    eq:=Etc.makeDict(["id":Ref("eq"),"equip":Marker.val,"navName":"FIN 名称"])
    data:=Str:Obj?["kind":"meter","name":"FIN 名称"]
    verifyNull(EnerCubixNativeEquip.tags(data,eq,"admin")["enerCubixAlias"])
    data["useAlias"]=true; data["name"]="短名称"
    enabled:=EnerCubixNativeEquip.tags(data,eq,"admin")
    verifyEq(enabled["enerCubixAlias"],"短名称")
    verifyEq(enabled["enerCubixUseAlias"],true)
    old:=Etc.makeDict(["id":eq.id,"equip":Marker.val,"enerCubixAlias":"短名称","enerCubixUseAlias":true])
    data["useAlias"]=false
    disabled:=EnerCubixNativeEquip.tags(data,old,"admin")
    verifyEq(disabled["enerCubixAlias"],Remove.val)
    verifyEq(disabled["enerCubixUseAlias"],false)
    verifyNull(disabled["navName"]); verifyNull(disabled["dis"])
    verify(EnerCubixNativeEquip.ownedTags.contains("enerCubixUseAlias"))
    verifyEq(EnerCubixNativeEquip.clear(old)["enerCubixUseAlias"],Remove.val)
  }

  Void testDefaultNativeNamesCanRepeatAcrossEquipment()
  {
    first:=Str:Obj?["id":"eq-a","kind":"meter","name":"电表","nativeEquip":true,"useAlias":false,"categoryId":"cat"]
    second:=first.dup; second["id"]="eq-b"
    all:=[first,second,Str:Obj?["id":"cat","kind":"category","name":"电","unit":"kWh"]]
    EnerCubixConfig.validate(first,all)
    first["useAlias"]=true
    verifyErr(ArgErr#) { EnerCubixConfig.validate(first,all) }
  }
}

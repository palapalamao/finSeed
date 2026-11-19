using haystack

class FinEnergyNativeNameTest : Test
{
  Void testLegacyAliasDoesNotHideNativeRename()
  {
    source:=Str:Obj?["id":Ref("eq"),"equip":Marker.val,"dis":"总电表","navName":"总电表1F空调用电","finEnergyKind":"totalMeter","finEnergyAlias":"总电表","finEnergyPointRef":Ref("point")]
    record:=FinEnergyNativeEquip.decode(Etc.makeDict(source))
    verifyEq(record["name"],"总电表1F空调用电")
    verifyEq(record["nativeName"],"总电表1F空调用电")
    verifyEq(record["useAlias"],false)
    source["navName"]="总电表2F动力用电"
    refreshed:=FinEnergyNativeEquip.decode(Etc.makeDict(source))
    verifyEq(refreshed["name"],"总电表2F动力用电")
    verifyEq(refreshed["id"],record["id"])
    verifyEq(refreshed["pointId"],record["pointId"])
    verifyEq(source["finEnergyAlias"],"总电表")
  }

  Void testOnlyExplicitAliasOverridesNativeName()
  {
    source:=Str:Obj?["id":Ref("eq"),"dis":"FIN 原名","navName":"FIN 设备树名","finEnergyAlias":"自定义短名","finEnergyUseAlias":true]
    verifyEq(FinEnergyNativeEquip.decode(Etc.makeDict(source))["name"],"自定义短名")
    source["finEnergyUseAlias"]=false
    verifyEq(FinEnergyNativeEquip.decode(Etc.makeDict(source))["name"],"FIN 设备树名")
    source.remove("navName")
    verifyEq(FinEnergyNativeEquip.decode(Etc.makeDict(source))["name"],"FIN 原名")
    source["finEnergyUseAlias"]=true; source["finEnergyAlias"]="  "
    verifyEq(FinEnergyNativeEquip.decode(Etc.makeDict(source))["name"],"FIN 原名")
  }

  Void testSavingDefaultNameNeverCreatesAnImplicitAlias()
  {
    eq:=Etc.makeDict(["id":Ref("eq"),"equip":Marker.val,"navName":"FIN 名称"])
    data:=Str:Obj?["kind":"meter","name":"FIN 名称"]
    verifyNull(FinEnergyNativeEquip.tags(data,eq,"admin")["finEnergyAlias"])
    data["useAlias"]=true; data["name"]="短名称"
    enabled:=FinEnergyNativeEquip.tags(data,eq,"admin")
    verifyEq(enabled["finEnergyAlias"],"短名称")
    verifyEq(enabled["finEnergyUseAlias"],true)
    old:=Etc.makeDict(["id":eq.id,"equip":Marker.val,"finEnergyAlias":"短名称","finEnergyUseAlias":true])
    data["useAlias"]=false
    disabled:=FinEnergyNativeEquip.tags(data,old,"admin")
    verifyEq(disabled["finEnergyAlias"],Remove.val)
    verifyEq(disabled["finEnergyUseAlias"],false)
    verifyNull(disabled["navName"]); verifyNull(disabled["dis"])
    verify(FinEnergyNativeEquip.ownedTags.contains("finEnergyUseAlias"))
    verifyEq(FinEnergyNativeEquip.clear(old)["finEnergyUseAlias"],Remove.val)
  }

  Void testDefaultNativeNamesCanRepeatAcrossEquipment()
  {
    first:=Str:Obj?["id":"eq-a","kind":"meter","name":"电表","nativeEquip":true,"useAlias":false,"categoryId":"cat"]
    second:=first.dup; second["id"]="eq-b"
    all:=[first,second,Str:Obj?["id":"cat","kind":"category","name":"电","unit":"kWh"]]
    FinEnergyConfig.validate(first,all)
    first["useAlias"]=true
    verifyErr(ArgErr#) { FinEnergyConfig.validate(first,all) }
  }
}

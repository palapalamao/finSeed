using haystack

class FinEnergySpaceAreaTest : Test
{
  Void testServiceAreaTagsAndValidation()
  {
    equip:=Etc.makeDict(["id":Ref("meter"),"equip":Marker.val])
    tags:=FinEnergyNativeEquip.tags(["kind":"meter","areaSource":"space","areaSpaceId":"floor","area":800f],equip,"admin")
    verifyEq(tags["finEnergyAreaSpaceRef"],Ref("floor"))
    verifyEq(tags["finEnergyAreaSource"],"space")
    decoded:=FinEnergyNativeEquip.decode(Etc.makeDict(Etc.dictToMap(tags).set("id",equip.id)))
    verifyEq(decoded["areaSpaceId"],"floor"); verifyEq(decoded["area"],800f)
    records:=[
      [Str:Obj?]["id":"floor","kind":"space","name":"1F","nativeSourceKind":"floor"],
      [Str:Obj?]["id":"cat","kind":"category","name":"Electricity"],
    ]
    meter:=[Str:Obj?]["id":"m","kind":"meter","name":"Lighting","categoryId":"cat","areaSource":"space","areaSpaceId":"floor"]
    FinEnergyConfig.validate(meter,records)
    meter["areaSpaceId"]="missing"
    verifyErr(ArgErr#) { FinEnergyConfig.validate(meter,records) }
    meter["areaSource"]="custom"; meter["area"]=0f
    verifyErr(ArgErr#) { FinEnergyConfig.validate(meter,records) }
    meter.remove("areaSource"); meter["area"]=1000f
    FinEnergyConfig.validate(meter,records)
  }

  Void testCoveragePlaceholderCannotInvalidateARealServiceSpace()
  {
    source:=Etc.makeDict(["id":Ref("floor"),"floor":Marker.val,"dis":"1F"])
    placeholder:=[Str:Obj?]["id":"floor","kind":"space","name":"1F"]
    authoritative:=FinEnergySpaceArea.referenceRow("floor",source,placeholder)
    meter:=[Str:Obj?]["id":"m","kind":"meter","name":"Lighting","categoryId":"cat","spaceId":"floor","areaSource":"space","areaSpaceId":"floor"]
    records:=[[Str:Obj?]["id":"cat","kind":"category","name":"Electricity"],placeholder]
    verifyErr(ArgErr#) { FinEnergyConfig.validate(meter,records) }
    records[1]=authoritative
    FinEnergyConfig.validate(meter,records)
    verifyEq(authoritative["nativeSourceKind"],"floor")
    verifyErr(ArgErr#) { FinEnergySpaceArea.referenceRow("equip",Etc.makeDict(["id":Ref("equip"),"equip":Marker.val]),placeholder) }
  }

  Void testBrokenAreaReferenceDoesNotInvalidateEnergyHistory()
  {
    equip:=Etc.makeDict(["id":Ref("m"),"equip":Marker.val,"finEnergyKind":"meter","finEnergyAreaSource":"space","finEnergyAreaSpaceRef":"not a Ref"])
    decoded:=FinEnergyNativeEquip.decode(equip)
    verifyNull(decoded["configurationError"])
    verifyEq(decoded["areaConfigurationError"],"invalidAreaSpace")
    verifyNull(FinEnergyNativeSpace.clean(decoded)["areaConfigurationError"])
  }

  Void testAreaOnlyPatchAndNativeUnitConversion()
  {
    site:=Etc.makeDict(["id":Ref("site"),"site":Marker.val,"dis":"Existing site"])
    patch:=FinEnergySpaceArea.tags(["id":"site","kind":"space","mod":"revision","areaOnly":true,"area":1000f],site)
    verifyEq(Etc.dictToMap(patch).keys,["area"])
    verifyEq(patch["area"],Number(1000f,Unit.fromStr("m²")))
    verifyNull(site["area"])
    verifyEq(FinEnergySpaceArea.tags(["id":"site","areaOnly":true,"area":null],site)["area"],Remove.val)
    verifyEq(FinEnergySpaceArea.squareMetres(Number(1000f)),1000f)
    verify(FinEnergySpaceArea.squareMetres(Number(1000f,Unit.fromStr("ft²"))).approx(92.90304f))
    verifyNull(FinEnergySpaceArea.squareMetres(Number(100f,Unit.fromStr("kWh"))))
  }

  Void testAreaSaveRejectsOtherFieldsAndInvalidNumbers()
  {
    floor:=Etc.makeDict(["id":Ref("floor"),"floor":Marker.val])
    ["name","parentId","siteRef","nativeSourceId","pointId"].each |field|
    {
      verifyErr(ArgErr#) { FinEnergySpaceArea.tags(["areaOnly":true,"area":50f,field:"forged"],floor) }
    }
    [0f,-1f,Float.nan,Float.posInf,"1000"].each |value|
    { verifyErr(ArgErr#) { FinEnergySpaceArea.tags(["areaOnly":true,"area":value],floor) } }
    verifyErr(ArgErr#) { FinEnergySpaceArea.tags(["areaOnly":true,"area":50f],Etc.makeDict(["equip":Marker.val])) }
    verifyErr(ArgErr#) { FinEnergySpaceArea.tags(["area":50f],floor) }
  }

  Void testFinAreaOverridesAndClearsLegacyOverlay()
  {
    source:=FinEnergyNativeSpace()
    source.nodes=[[Str:Obj?]["id":"site","sourceKind":"site","name":"Native site","area":1000f]]
    overlay:=[Str:Obj?]["id":"overlay","kind":"space","name":"Old","migrationSourceId":"site","area":800f]
    verifyEq(source.project([overlay]).first["area"],1000f)
    source.nodes.first.remove("area")
    verifyNull(source.project([overlay]).first["area"])
    verifyEq(overlay["area"],800f)
  }
}

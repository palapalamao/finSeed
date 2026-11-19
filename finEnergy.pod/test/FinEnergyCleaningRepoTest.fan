using haystack

class FinEnergyCleaningRepoTest : Test
{
  Void testNativeOwnershipUsesMarkersRefsAndVersionedConfig()
  {
    original:=point
    patch:=FinEnergyCleaningRepo.install(original,Ref("eq"),config)
    verifyEq(patch["hisFunc"],"finEnergyCleanHis")
    verifyEq(patch["hisFuncWritable"],Marker.val)
    verifyEq(patch["finEnergyCleaningOwned"],Marker.val)
    verifyEq(patch["finEnergyCleaningProfileRef"],Ref("profile"))
    verifyEq(patch["finEnergyCleaningProfileVersion"],Number(2))
    verifyEq(patch["finEnergyCleaningEquipRef"],Ref("eq"))
    verifyNull(patch["unit"]); verifyNull(patch["equipRef"]); verifyNull(patch["hisTotalized"])
    verifyNull(original["hisFunc"])
    installed:=apply(original,patch)
    verify(FinEnergyCleaningRepo.managed(installed))
    verify(!FinEnergyCleaningRepo.external(installed))
    restored:=apply(installed,FinEnergyCleaningRepo.restore(installed))
    verifyEq(Etc.dictToMap(restored),Etc.dictToMap(original))
  }

  Void testDisablingRestoresOnlyOriginalHistoryAttributes()
  {
    original:=apply(point,Etc.makeDict(["hisFuncConfig":Etc.makeDict(["existing":"keep"]),"hisFuncWritable":Marker.val,"connectorCustom":"preserve"]))
    installed:=apply(original,FinEnergyCleaningRepo.install(original,Ref("eq"),config))
    updated:=apply(installed,Etc.makeDict(["curVal":Number(500),"dis":"updated native name"]))
    restored:=apply(updated,FinEnergyCleaningRepo.restore(updated))
    verifyNull(restored["hisFunc"])
    verifyEq(Etc.dictToMap((Dict)restored["hisFuncConfig"]),Str:Obj?["existing":"keep"])
    verifyEq(restored["hisFuncWritable"],Marker.val)
    verifyEq(restored["connectorCustom"],"preserve")
    verifyEq(restored["curVal"],Number(500)); verifyEq(restored["dis"],"updated native name")
    FinEnergyCleaningRepo.ownershipTags.each |tag| { verifyNull(restored[tag]) }
  }

  Void testExternalFunctionCannotBeAdoptedEvenWhenNameMatches()
  {
    ["externalHis","finEnergyCleanHis"].each |name|
    {
      external:=apply(point,Etc.makeDict(["hisFunc":name]))
      verify(FinEnergyCleaningRepo.external(external))
      verifyErr(ArgErr#) { FinEnergyCleaningRepo.install(external,Ref("eq"),config) }
      verify(FinEnergyCleaningRepo.restore(external).isEmpty)
    }
  }

  Void testDisablePreservesFunctionInstalledByAnotherOwner()
  {
    installed:=apply(point,FinEnergyCleaningRepo.install(point,Ref("eq"),config))
    externalConfig:=Etc.makeDict(["external":"owned"])
    changed:=apply(installed,Etc.makeDict(["hisFunc":"externalHis","hisFuncConfig":externalConfig,"hisFuncWritable":Remove.val]))
    restored:=apply(changed,FinEnergyCleaningRepo.restore(changed))
    verifyEq(restored["hisFunc"],"externalHis")
    verifyEq(restored["hisFuncConfig"],externalConfig)
    verifyNull(restored["hisFuncWritable"])
    FinEnergyCleaningRepo.ownershipTags.each |tag| { verifyNull(restored[tag]) }
  }

  Void testExternalChangesToManagedConfigRejectReinstallation()
  {
    installed:=apply(point,FinEnergyCleaningRepo.install(point,Ref("eq"),config))
    changed:=apply(installed,Etc.makeDict(["hisFuncConfig":Etc.makeDict(["custom":Number(42)])]))
    verifyErr(FinEnergyHttpErr#) { FinEnergyCleaningRepo.install(changed,Ref("eq"),config) }
    verifyErr(FinEnergyHttpErr#) { FinEnergyCleaningRepo.install(installed,Ref("another"),config) }
  }

  Void testStoredNestedConfigComparesByValueAndRefIdentity()
  {
    installed:=apply(point,FinEnergyCleaningRepo.install(point,Ref("eq"),config))
    // Folio deserializes the two nested Dict occurrences independently and may
    // attach cached display text to Refs. Their content is still identical.
    storedConfig:=Etc.makeDict(Etc.dictToMap(config).set("finEnergyProfileRef",Ref("profile","cached display")))
    stored:=apply(installed,Etc.makeDict(["hisFuncConfig":storedConfig]))
    next:=Etc.makeDict(Etc.dictToMap(config).set("finEnergyProfileVersion",Number(3)))
    patch:=FinEnergyCleaningRepo.install(stored,Ref("eq"),next)
    verifyEq(patch["finEnergyCleaningProfileVersion"],Number(3))
    restored:=apply(stored,FinEnergyCleaningRepo.restore(stored))
    verifyNull(restored["hisFuncConfig"])
    verifyNull(restored["hisFunc"])
  }

  Void testRolloverVisibilityUsesOnlyOwnedTag()
  {
    cfg:=Etc.makeDict(Etc.dictToMap(config).set("hisTotalizedRollover",Number(1000,Unit("kWh"))))
    patch:=FinEnergyCleaningRepo.install(point,Ref("eq"),cfg)
    verifyEq(patch["finEnergyCleaningRollover"],Number(1000,Unit("kWh")))
    verifyNull(patch["hisTotalizedRollover"])
    installed:=apply(point,patch)
    update:=FinEnergyCleaningRepo.install(installed,Ref("eq"),config)
    verifyEq(update["finEnergyCleaningRollover"],Remove.val)
    verifyEq(FinEnergyCleaningRepo.restore(installed)["finEnergyCleaningRollover"],Remove.val)
  }

  Void testProfileVersioningDefaultsAndInvalidModes()
  {
    fresh:=FinEnergyCleaningRepo.profileRecord(["kind":"cleaningProfile","name":"meter default","mode":"drop"],null)
    verifyEq(fresh["version"],1)
    verifyEq(((Map)fresh["parameters"])["deltaMin"],0)
    verifyEq(((Map)fresh["parameters"])["timeMax"],"1h")
    verifyEq(((Map)fresh["parameters"])["defNull"],true)
    verify(!((Map)fresh["parameters"]).containsKey("deltaMax"))
    edit:=fresh.dup; edit["name"]="changed"
    verifyEq(FinEnergyCleaningRepo.profileRecord(edit,fresh)["version"],2)
    edit["version"]=2
    verifyErr(FinEnergyHttpErr#) { FinEnergyCleaningRepo.profileRecord(edit,fresh) }
    verifyErr(ArgErr#) { FinEnergyCleaningRepo.profileRecord(["kind":"cleaningProfile","name":"bad","mode":"guess"],null) }
    verifyErr(ArgErr#) { FinEnergyCleaningRepo.profileRecord(["kind":"meter","name":"wrong"],null) }
  }

  Void testProfileModeAndMixedRateDimensions()
  {
    parameters:=Str:Obj?["deltaMin":["type":"number","value":0,"unit":"kWh"],"derivMax":["type":"number","value":100,"unit":"kW"],"defNull":true]
    profile:=FinEnergyCleaningRepo.profileRecord(["kind":"cleaningProfile","name":"mixed dimensions","mode":"drop","parameters":parameters],null)
    profile["id"]="profile"
    cfg:=FinEnergyCleaningRepo.configFor(profile,point)
    verifyEq(((Number)cfg["deltaMin"]).unit,Unit("kWh"))
    verifyEq(((Number)cfg["derivMax"]).unit,Unit("kW"))
    FinEnergyCleaningRepo.profileRecord(["kind":"cleaningProfile","name":"rate only","mode":"drop","parameters":["derivMax":["type":"number","value":100,"unit":"W"],"defNull":true]],null)
    FinEnergyCleaningRepo.profileRecord(["kind":"cleaningProfile","name":"replacement","mode":"replace","parameters":["defVal":["type":"na"]]],null)
    verifyErr(ArgErr#) { FinEnergyCleaningRepo.profileRecord(["kind":"cleaningProfile","name":"contradictory mode","mode":"drop","parameters":["defVal":["type":"na"]]],null) }
  }

  private Dict point()
  { Etc.makeDict(["id":Ref("point"),"point":Marker.val,"equipRef":Ref("eq"),"his":Marker.val,"hisTotalized":Marker.val,"kind":"Number","unit":"kWh","dis":"native name"]) }

  private Dict config()
  { Etc.makeDict(["deltaMin":Number(0,Unit.fromStr("kWh")),"timeMax":Number(1,Unit.fromStr("hr")),"defNull":Marker.val,"finEnergyMode":"drop","finEnergyProfileRef":Ref("profile"),"finEnergyProfileVersion":Number(2)]) }

  private Dict apply(Dict original, Dict patch)
  { tags:=Etc.dictToMap(original); patch.each |v,k| { if (v is Remove) tags.remove(k); else tags[k]=v }; return Etc.makeDict(tags) }
}

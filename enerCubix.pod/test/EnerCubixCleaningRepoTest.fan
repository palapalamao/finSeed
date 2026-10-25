using haystack

class EnerCubixCleaningRepoTest : Test
{
  Void testNativeOwnershipUsesMarkersRefsAndVersionedConfig()
  {
    original:=point
    patch:=EnerCubixCleaningRepo.install(original,Ref("eq"),config)
    verifyEq(patch["hisFunc"],"enerCubixCleanHis")
    verifyEq(patch["hisFuncWritable"],Marker.val)
    verifyEq(patch["enerCubixCleaningOwned"],Marker.val)
    verifyEq(patch["enerCubixCleaningProfileRef"],Ref("profile"))
    verifyEq(patch["enerCubixCleaningProfileVersion"],Number(2))
    verifyEq(patch["enerCubixCleaningEquipRef"],Ref("eq"))
    verifyNull(patch["unit"]); verifyNull(patch["equipRef"]); verifyNull(patch["hisTotalized"])
    verifyNull(original["hisFunc"])
    installed:=apply(original,patch)
    verify(EnerCubixCleaningRepo.managed(installed))
    verify(!EnerCubixCleaningRepo.external(installed))
    restored:=apply(installed,EnerCubixCleaningRepo.restore(installed))
    verifyEq(Etc.dictToMap(restored),Etc.dictToMap(original))
  }

  Void testDisablingRestoresOnlyOriginalHistoryAttributes()
  {
    original:=apply(point,Etc.makeDict(["hisFuncConfig":Etc.makeDict(["existing":"keep"]),"hisFuncWritable":Marker.val,"connectorCustom":"preserve"]))
    installed:=apply(original,EnerCubixCleaningRepo.install(original,Ref("eq"),config))
    updated:=apply(installed,Etc.makeDict(["curVal":Number(500),"dis":"updated native name"]))
    restored:=apply(updated,EnerCubixCleaningRepo.restore(updated))
    verifyNull(restored["hisFunc"])
    verifyEq(Etc.dictToMap((Dict)restored["hisFuncConfig"]),Str:Obj?["existing":"keep"])
    verifyEq(restored["hisFuncWritable"],Marker.val)
    verifyEq(restored["connectorCustom"],"preserve")
    verifyEq(restored["curVal"],Number(500)); verifyEq(restored["dis"],"updated native name")
    EnerCubixCleaningRepo.ownershipTags.each |tag| { verifyNull(restored[tag]) }
  }

  Void testExternalFunctionCannotBeAdoptedEvenWhenNameMatches()
  {
    ["externalHis","enerCubixCleanHis"].each |name|
    {
      external:=apply(point,Etc.makeDict(["hisFunc":name]))
      verify(EnerCubixCleaningRepo.external(external))
      verifyErr(ArgErr#) { EnerCubixCleaningRepo.install(external,Ref("eq"),config) }
      verify(EnerCubixCleaningRepo.restore(external).isEmpty)
    }
  }

  Void testDisablePreservesFunctionInstalledByAnotherOwner()
  {
    installed:=apply(point,EnerCubixCleaningRepo.install(point,Ref("eq"),config))
    externalConfig:=Etc.makeDict(["external":"owned"])
    changed:=apply(installed,Etc.makeDict(["hisFunc":"externalHis","hisFuncConfig":externalConfig,"hisFuncWritable":Remove.val]))
    restored:=apply(changed,EnerCubixCleaningRepo.restore(changed))
    verifyEq(restored["hisFunc"],"externalHis")
    verifyEq(restored["hisFuncConfig"],externalConfig)
    verifyNull(restored["hisFuncWritable"])
    EnerCubixCleaningRepo.ownershipTags.each |tag| { verifyNull(restored[tag]) }
  }

  Void testExternalChangesToManagedConfigRejectReinstallation()
  {
    installed:=apply(point,EnerCubixCleaningRepo.install(point,Ref("eq"),config))
    changed:=apply(installed,Etc.makeDict(["hisFuncConfig":Etc.makeDict(["custom":Number(42)])]))
    verifyErr(EnerCubixHttpErr#) { EnerCubixCleaningRepo.install(changed,Ref("eq"),config) }
    verifyErr(EnerCubixHttpErr#) { EnerCubixCleaningRepo.install(installed,Ref("another"),config) }
  }

  Void testStoredNestedConfigComparesByValueAndRefIdentity()
  {
    installed:=apply(point,EnerCubixCleaningRepo.install(point,Ref("eq"),config))
    // Folio deserializes the two nested Dict occurrences independently and may
    // attach cached display text to Refs. Their content is still identical.
    storedConfig:=Etc.makeDict(Etc.dictToMap(config).set("enerCubixProfileRef",Ref("profile","cached display")))
    stored:=apply(installed,Etc.makeDict(["hisFuncConfig":storedConfig]))
    next:=Etc.makeDict(Etc.dictToMap(config).set("enerCubixProfileVersion",Number(3)))
    patch:=EnerCubixCleaningRepo.install(stored,Ref("eq"),next)
    verifyEq(patch["enerCubixCleaningProfileVersion"],Number(3))
    restored:=apply(stored,EnerCubixCleaningRepo.restore(stored))
    verifyNull(restored["hisFuncConfig"])
    verifyNull(restored["hisFunc"])
  }

  Void testRolloverVisibilityUsesOnlyOwnedTag()
  {
    cfg:=Etc.makeDict(Etc.dictToMap(config).set("hisTotalizedRollover",Number(1000,Unit("kWh"))))
    patch:=EnerCubixCleaningRepo.install(point,Ref("eq"),cfg)
    verifyEq(patch["enerCubixCleaningRollover"],Number(1000,Unit("kWh")))
    verifyNull(patch["hisTotalizedRollover"])
    installed:=apply(point,patch)
    update:=EnerCubixCleaningRepo.install(installed,Ref("eq"),config)
    verifyEq(update["enerCubixCleaningRollover"],Remove.val)
    verifyEq(EnerCubixCleaningRepo.restore(installed)["enerCubixCleaningRollover"],Remove.val)
  }

  Void testProfileVersioningDefaultsAndInvalidModes()
  {
    fresh:=EnerCubixCleaningRepo.profileRecord(["kind":"cleaningProfile","name":"meter default","mode":"drop"],null)
    verifyEq(fresh["version"],1)
    verifyEq(((Map)fresh["parameters"])["deltaMin"],0)
    verifyEq(((Map)fresh["parameters"])["timeMax"],"1h")
    verifyEq(((Map)fresh["parameters"])["defNull"],true)
    verify(!((Map)fresh["parameters"]).containsKey("deltaMax"))
    edit:=fresh.dup; edit["name"]="changed"
    verifyEq(EnerCubixCleaningRepo.profileRecord(edit,fresh)["version"],2)
    edit["version"]=2
    verifyErr(EnerCubixHttpErr#) { EnerCubixCleaningRepo.profileRecord(edit,fresh) }
    verifyErr(ArgErr#) { EnerCubixCleaningRepo.profileRecord(["kind":"cleaningProfile","name":"bad","mode":"guess"],null) }
    verifyErr(ArgErr#) { EnerCubixCleaningRepo.profileRecord(["kind":"meter","name":"wrong"],null) }
  }

  Void testProfileModeAndMixedRateDimensions()
  {
    parameters:=Str:Obj?["deltaMin":["type":"number","value":0,"unit":"kWh"],"derivMax":["type":"number","value":100,"unit":"kW"],"defNull":true]
    profile:=EnerCubixCleaningRepo.profileRecord(["kind":"cleaningProfile","name":"mixed dimensions","mode":"drop","parameters":parameters],null)
    profile["id"]="profile"
    cfg:=EnerCubixCleaningRepo.configFor(profile,point)
    verifyEq(((Number)cfg["deltaMin"]).unit,Unit("kWh"))
    verifyEq(((Number)cfg["derivMax"]).unit,Unit("kW"))
    EnerCubixCleaningRepo.profileRecord(["kind":"cleaningProfile","name":"rate only","mode":"drop","parameters":["derivMax":["type":"number","value":100,"unit":"W"],"defNull":true]],null)
    EnerCubixCleaningRepo.profileRecord(["kind":"cleaningProfile","name":"replacement","mode":"replace","parameters":["defVal":["type":"na"]]],null)
    verifyErr(ArgErr#) { EnerCubixCleaningRepo.profileRecord(["kind":"cleaningProfile","name":"contradictory mode","mode":"drop","parameters":["defVal":["type":"na"]]],null) }
  }

  private Dict point()
  { Etc.makeDict(["id":Ref("point"),"point":Marker.val,"equipRef":Ref("eq"),"his":Marker.val,"hisTotalized":Marker.val,"kind":"Number","unit":"kWh","dis":"native name"]) }

  private Dict config()
  { Etc.makeDict(["deltaMin":Number(0,Unit.fromStr("kWh")),"timeMax":Number(1,Unit.fromStr("hr")),"defNull":Marker.val,"enerCubixMode":"drop","enerCubixProfileRef":Ref("profile"),"enerCubixProfileVersion":Number(2)]) }

  private Dict apply(Dict original, Dict patch)
  { tags:=Etc.dictToMap(original); patch.each |v,k| { if (v is Remove) tags.remove(k); else tags[k]=v }; return Etc.makeDict(tags) }
}

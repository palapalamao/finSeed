class FinEnergyRelationsTest : Test
{
  Void testIndependentReferences()
  {
    all:=base
    m:=Str:Obj?["id":"m","kind":"meter","name":"左水表","categoryId":"water","spaceId":"floor","organizationId":"org","meterParentId":"master","pointId":"p"]
    FinEnergyConfig.validate(m,all)
    changed:=m.dup; changed["spaceId"]="site"
    FinEnergyConfig.validate(changed,all)
    verifyEq(changed["meterParentId"],"master")
    verifyEq(changed["organizationId"],"org")
  }

  Void testEntityHierarchyAndMeterCycles()
  {
    all:=base
    FinEnergyConfig.validate(all[0],all)
    FinEnergyConfig.validate(all[1],all)
    FinEnergyConfig.validate(all[2],all)
    bad:=all[0].dup; bad["parentId"]="floor"
    verifyErr(ArgErr#) { FinEnergyConfig.validate(bad,all) }
    bad=all[1].dup; bad["parentId"]="org"
    verifyErr(ArgErr#) { FinEnergyConfig.validate(bad,all) }
    m:=Str:Obj?["id":"m","kind":"meter","name":"子表","categoryId":"water","meterParentId":"master"]
    all.add(m)
    bad=all[4].dup; bad["meterParentId"]="m"
    verifyErr(ArgErr#) { FinEnergyConfig.validate(bad,all) }
    m["categoryId"]="elec"
    verifyErr(ArgErr#) { FinEnergyConfig.validate(m,all) }
  }

  Void testCanonicalAndDeletionReferences()
  {
    all:=base
    alias:=Str:Obj?["id":"alias","kind":"meter","name":"兼容引用","categoryId":"water","pointId":"total","canonicalId":"master"]
    FinEnergyConfig.validate(alias,all)
    all.add(alias)
    verifyErr(ArgErr#) { FinEnergyConfig.canDelete("master",all) }
    bad:=alias.dup; bad["pointId"]="other"
    verifyErr(ArgErr#) { FinEnergyConfig.validate(bad,all) }
    dup:=Str:Obj?["id":"dup","kind":"meter","name":"重复物理点","categoryId":"water","pointId":"total","spaceId":"floor"]
    verifyErr(ArgErr#) { FinEnergyConfig.validate(dup,all) }
    all.add(Str:Obj?["id":"legacy","kind":"group","name":"旧分组"])
    dup.remove("spaceId"); dup["parentId"]="legacy"
    verifyErr(ArgErr#) { FinEnergyConfig.validate(dup,all) }
  }

  Void testParentEditsPreserveDependentRelationships()
  {
    all:=base
    all.add(Str:Obj?["id":"child","kind":"meter","name":"分表","categoryId":"water","meterParentId":"master"])
    changed:=all[4].dup; changed["categoryId"]="elec"
    verifyErr(ArgErr#) { FinEnergyConfig.validate(changed,all) }
    all.add(Str:Obj?["id":"alias","kind":"meter","name":"兼容","categoryId":"water","pointId":"total","canonicalId":"master"])
    changed=all[4].dup; changed["pointId"]="replacement"
    verifyErr(ArgErr#) { FinEnergyConfig.validate(changed,all) }
  }

  Void testMigrationAdditionUsesProjectLocalId()
  {
    verifyEq(FinEnergyRepo.addId("p:zeda:r:finEnergy-space-site-12345","zeda").id,"finEnergy-space-site-12345")
    verifyEq(FinEnergyRepo.addId("local-id","zeda").id,"local-id")
    verifyErr(ArgErr#) { FinEnergyRepo.addId("p:other:r:foreign","zeda") }
  }

  Void testNewLegacyBindingsCannotDuplicateExistingPoints()
  {
    first:=Str:Obj?["id":"a","kind":"meter","parentId":"old","pointId":"p"]
    second:=Str:Obj?["id":"b","kind":"meter","parentId":"old","pointId":"p"]
    verifyErr(ArgErr#) { FinEnergyConfig.validateNewBinding(second,null,[first,second]) }
    FinEnergyConfig.validateNewBinding(second,second.dup,[first,second])
    changed:=second.dup; changed["pointId"]="other"
    verifyErr(ArgErr#) { FinEnergyConfig.validateNewBinding(changed,second,[first,second,Str:Obj?["id":"c","kind":"meter","pointId":"other"]]) }
    changed.remove("pointId"); FinEnergyConfig.validateNewBinding(changed,second,[first,second])
    verifyEq(changed["pointId"],null)
  }

  private [Str:Obj?][] base()
  {
    return [
      Str:Obj?["id":"site","kind":"space","name":"园区"],
      Str:Obj?["id":"floor","kind":"space","name":"3F","parentId":"site"],
      Str:Obj?["id":"org","kind":"organization","name":"物业"],
      Str:Obj?["id":"water","kind":"category","name":"水","unit":"m3"],
      Str:Obj?["id":"master","kind":"totalMeter","name":"总水表","categoryId":"water","pointId":"total","spaceId":"site"],
      Str:Obj?["id":"elec","kind":"category","name":"电","unit":"kWh"]
    ]
  }
}

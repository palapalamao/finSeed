using haystack
using folio

class SeedMigrationTest : Test
{
  Void testDeterministicCanonicalAndIdempotent()
  {
    all:=base
    all.add(meter("z-alias","meter","总水兼容","water-point","water-group"))
    all.add(meter("a-master","totalMeter","总水","water-point","totals"))
    all.last["includeInTotals"]=true
    sources:=[source("water-point","site","园区")]
    before:=all.map |r->[Str:Obj?]| { r.dup }
    plan:=SeedMigration.plan(all,sources)
    verifyEq(plan,SeedMigration.plan(all.dup.reverse,sources.dup.reverse))
    verifyEq(all,before)
    edits:=maps(plan["records"])
    alias:=edits.find |r| { r["id"] == id("z-alias") }
    verifyEq(alias["canonicalId"],id("a-master"))
    verifyEq(alias["pointId"],id("water-point"))
    verifyEq(alias["parentId"],id("water-group"))
    master:=edits.find |r| { r["id"] == id("a-master") }
    verifyEq(master["canonicalId"],null)
    verifyEq(master["includeInTotals"],true)
    space:=edits.find |r| { r["kind"] == "space" }
    verify(space["id"].toStr.startsWith("p:test:r:"))
    verifyEq(Ref.fromStr(space["id"].toStr).id,space["id"])
    verifyEq(space["name"],"园区")
    applied:=apply(all,edits)
    verifyEq(maps(SeedMigration.plan(applied,sources)["records"]).size,0)
    applied.findAll |r| { SeedConfig.nodeKinds.contains(r["kind"]) }.each |r| { SeedConfig.validate(r,applied) }
  }

  Void testCanonicalPrefersIncludedActiveMasterThenStableId()
  {
    all:=base
    all.add(meter("a-disabled","totalMeter","停用总表","p","totals")); all.last["active"]=false
    all.add(meter("b-excluded","totalMeter","排除总表","p","water-group")); all.last["includeInTotals"]=false
    all.add(meter("c-included","totalMeter","在用总表","p","other"))
    all.add(meter("d-meter","meter","分表别名","p","other"))
    edits:=maps(SeedMigration.plan(all)["records"])
    verifyEq(edits.size,3)
    edits.each |r| { verifyEq(r["canonicalId"],id("c-included")) }
    all=base.add(meter("z","meter","甲","p","water-group")).add(meter("a","meter","乙","p","water-group"))
    verifyEq(maps(SeedMigration.plan(all)["records"]).first["canonicalId"],id("a"))
  }

  Void testNamesAndLegacyGroupsDoNotAssertTopology()
  {
    all:=base
    all.add(meter("master","totalMeter","1#楼总水表","master-point","water-group"))
    all.add(map(["id":id("wrapper"),"kind":"group","name":"设备包装","parentId":id("water-group")]))
    all.add(meter("sub","meter","1#楼分水表","sub-point","wrapper"))
    all.add(map(["id":id("empty-floor"),"kind":"group","name":"19F"]));
    plan:=SeedMigration.plan(all)
    verifyEq(maps(plan["records"]).size,0)
    suggestions:=maps(plan["suggestions"])
    batch:=suggestions.find |s| { s["type"] == "meterTopology" }
    verifyEq(batch["requiresConfirmation"],true)
    verifyEq(maps(batch["records"]).size,1)
    verifyEq(maps(batch["records"])[0]["meterParentId"],id("master"))
    verifyEq(all.find |r| { r["id"] == id("sub") }?.get("meterParentId"),null)
    verify(!suggestions.any |s| { maps(s["records"]).any |r| { r["kind"] == "space" && r["name"] == "19F" } })
    verify(!suggestions.any |s| { maps(s["records"]).any |r| { r["kind"] == "space" && r["name"] == "总能耗" } })
  }

  Void testNativeFloorRequiresAcceptanceAndNativeTopologyRequiresExactMapping()
  {
    all:=base
    all.add(meter("master","totalMeter","总水","master-point","totals"))
    all.add(meter("sub","meter","支路","sub-point","water-group"))
    child:=source("sub-point","site","园区")
    child["floorRef"]=id("functional-floor"); child["floorName"]="风机盘管"
    child["submeterOf"]=id("master-equip")
    parent:=source("master-point","site","园区"); parent["equipRef"]=id("master-equip")
    plan:=SeedMigration.plan(all,[child,parent])
    edits:=maps(plan["records"])
    sub:=edits.find |r| { r["id"] == id("sub") }
    verifyEq(sub["meterParentId"],id("master"))
    site:=edits.find |r| { r["kind"] == "space" }
    verifyEq(sub["spaceId"],site["id"])
    floor:=maps(plan["suggestions"]).find |s| { s["type"] == "nativeFloor" }
    verifyEq(floor["requiresConfirmation"],true)
    verifyEq(maps(floor["records"]).find |r| { r["kind"] == "space" }?.get("name"),"风机盘管")
    child["submeterOf"]=id("unmapped")
    sub=maps(SeedMigration.plan(all,[child,parent])["records"]).find |r| { r["id"] == id("sub") }
    verifyEq(sub["meterParentId"],null)
  }

  Void testPreservesExplicitPlacementAndRejectsCrossEnergyAlias()
  {
    all:=base
    all.add(map(["id":id("manual"),"kind":"space","name":"人工空间"]))
    all.add(meter("one","totalMeter","总水","p","totals"))
    all.add(meter("two","meter","电表","p","water-group")); all.last["categoryId"]=id("electric")
    all.last["spaceId"]=id("manual"); all.last["organizationId"]=id("org")
    all.add(map(["id":id("electric"),"kind":"category","name":"电","unit":"kWh"]))
    all.add(map(["id":id("org"),"kind":"organization","name":"物业"]))
    plan:=SeedMigration.plan(all,[source("p","site","园区")])
    verify(!maps(plan["records"]).any |r| { r["canonicalId"] != null })
    verify(!maps(plan["records"]).any |r| { r["id"] == id("two") })
    verify(((List)plan["warnings"]).size > 0)
  }

  Void testNativeCyclesAndAmbiguousEquipmentAreNotImported()
  {
    all:=base.add(meter("a","meter","甲","pa","water-group")).add(meter("b","meter","乙","pb","water-group"))
    a:=map(["id":id("pa"),"equipRef":id("shared"),"submeterOf":id("pb")])
    b:=map(["id":id("pb"),"equipRef":id("shared"),"submeterOf":id("pa")])
    plan:=SeedMigration.plan(all,[a,b])
    edits:=maps(plan["records"])
    candidate:=apply(all,edits)
    candidate.findAll |r| { r["kind"] == "meter" }.each |r| { SeedConfig.validate(r,candidate) }
    verify(((List)plan["warnings"]).size > 0)
    all.add(meter("c","meter","丙","pc","water-group"))
    c:=map(["id":id("pc"),"submeterOf":id("shared")])
    verify(!maps(SeedMigration.plan(all,[a,b,c])["records"]).any |r| { r["id"] == id("c") && r["meterParentId"] != null })
  }

  Void testWaterWrapperBatchUsesSamePointCanonicalMaster()
  {
    all:=base
    all.add(meter("main","totalMeter","主总水表","total-point","totals"))
    all.add(meter("total-alias","totalMeter","旧总水引用","total-point","water-group"))
    all.last["includeInTotals"]=false
    for (i:=0;i<36;i++)
    {
      all.add(map(["id":id("wrapper-"+i),"kind":"group","name":"设备 "+i,"parentId":id("water-group")]))
      all.add(meter("sub-"+i,"meter","分水 "+i,"point-"+i,"wrapper-"+i))
    }
    plan:=SeedMigration.plan(all)
    automatic:=maps(plan["records"])
    verifyEq(automatic.size,1)
    verifyEq(automatic.first["canonicalId"],id("main"))
    topology:=maps(plan["suggestions"]).find |s| { s["type"] == "meterTopology" }
    verifyEq(topology["count"],36)
    verifyEq(topology["parentId"],id("main"))
    patches:=maps(topology["patches"])
    verifyEq(patches.size,36)
    patches.each |p| { verifyEq(p.size,2); verifyEq(p["meterParentId"],id("main")) }
    verifyEq(maps(SeedMigration.plan(apply(all,automatic))["records"]).size,0)
  }

  Void testEscapedIdsDoNotCollideAndConflictingMetadataIsNotUsed()
  {
    all:=base.add(meter("a","meter","甲","pa","water-group")).add(meter("b","meter","乙","pb","other"))
    sources:=[source("pa","site a","同名园区"),source("pb","site-a","同名园区")]
    plan:=SeedMigration.plan(all,sources)
    spaces:=maps(plan["records"]).findAll |r| { r["kind"] == "space" }
    verifyEq(spaces.size,2)
    verify(spaces[0]["id"] != spaces[1]["id"])
    verify(spaces[0]["name"] != spaces[1]["name"])
    spaces.each |r| { verifyEq(Ref.fromStr(r["id"].toStr).id,r["id"]) }
    sources.add(source("pa","conflicting","冲突园区"))
    plan=SeedMigration.plan(all,sources)
    verify(!maps(plan["records"]).any |r| { r["id"] == id("a") })
    verify(((List)plan["warnings"]).size > 0)
  }

  Void testSiteOnlySourceInitializesSpaceWithoutImportingMeters()
  {
    all:=base
    before:=all.map |r->[Str:Obj?]| { r.dup }
    sources:=[map(["id":id("native-site"),"siteRef":id("native-site"),"siteName":"原生园区"])]
    plan:=SeedMigration.plan(all,sources)
    edits:=maps(plan["records"])
    verifyEq(edits.size,1)
    verifyEq(edits.first["kind"],"space")
    verifyEq(edits.first["name"],"原生园区")
    verifyEq(edits.first["migrationSourceId"],id("native-site"))
    verifyEq(edits.first["parentId"],null)
    verifyEq(Ref.fromStr(edits.first["id"].toStr).id,edits.first["id"])
    verifyEq(all,before)
    applied:=apply(all,edits)
    SeedConfig.validate(edits.first,applied)
    verify(!applied.any |r| { SeedRelations.meterKinds.contains(r["kind"]) })
    verifyEq(maps(SeedMigration.plan(applied,sources)["records"]).size,0)
  }

  Void testNativePointMetadataWithExplicitNullRelationships()
  {
    all:=base.add(meter("meter","meter","无空间水表","source-point","water-group"))
    source:=map(["id":id("meter"),"pointId":id("source-point"),"siteRef":null,"siteName":null,
      "floorRef":null,"floorName":null,"equipRef":null,"equipName":null,"submeterOf":null])
    before:=source.dup
    plan:=SeedMigration.plan(all,[source])
    verifyEq(maps(plan["records"]).size,0)
    verifyEq(source,before)
    verifyEq(all.last["pointId"],id("source-point"))
  }

  Void testUnboundAndExpressionMetersWithOptionalNativeMetadata()
  {
    all:=base.add(meter("bound","meter","原生水表","source-point","water-group"))
    unbound:=meter("copy","meter","未绑定副本","unused","water-group"); unbound.remove("pointId")
    expression:=meter("virtual","meter","虚拟水表","unused","water-group"); expression.remove("pointId")
    expression["expressionId"]=id("expression"); expression["includeInTotals"]=false
    all.add(unbound).add(expression)
    sources:=[map(["id":id("bound"),"pointId":id("source-point")]),
      map(["id":id("bound"),"pointId":id("source-point"),"siteRef":null,"siteName":null,
        "floorRef":null,"floorName":null,"equipRef":null,"equipName":null,"submeterOf":null])]
    sources.each |source|
    {
      plan:=SeedMigration.plan(all,[source])
      verifyEq(maps(plan["records"]).size,0)
      verifyEq(unbound["pointId"],null)
      verifyEq(expression["expressionId"],id("expression"))
    }
  }

  Void testGeneratedSiteIdsPassFolioAddValidation()
  {
    ["p:zeda:r:","p:a-very-long-project-name-for-qualified-native-refs:r:"].each |prefix|
    {
      nativeId:=prefix+"30eddd86-1da00815"
      all:=[map(["id":prefix+"legacy","kind":"group","name":"旧分析树"])]
      sources:=[map(["id":nativeId,"siteRef":nativeId,"siteName":"原生园区"])]
      plan:=SeedMigration.plan(all,sources)
      generated:=maps(plan["records"]).first
      qualified:=generated["id"].toStr
      verify(qualified.startsWith(prefix))
      localId:=qualified[prefix.size..-1]
      verify(localId.size <= 60)
      diff:=Diff.makeAdd(Etc.makeDict(["dis":generated["name"]]),Ref(localId))
      verifyEq(diff.id.id,localId)
      verifyEq(generated["migrationSourceId"],nativeId)
      verifyEq(plan,SeedMigration.plan(all,sources))
      verifyEq(maps(SeedMigration.plan(apply(all,maps(plan["records"])),sources)["records"]).size,0)
    }
  }

  Void testExistingMigrationSpaceIdentityIsReusedAndDigestCollisionIsBlocked()
  {
    nativeId:=id("30eddd86-1da00815")
    sources:=[map(["id":nativeId,"siteRef":nativeId,"siteName":"原生园区"])]
    original:=base
    generated:=maps(SeedMigration.plan(original,sources)["records"]).first
    existing:=generated.dup
    existing["id"]=id("finseed-space-site-pre-digest-id")
    existing["name"]="保留的旧名称"
    all:=original.dup.add(existing)
    verifyEq(maps(SeedMigration.plan(all,sources)["records"]).size,0)
    verifyEq(existing["name"],"保留的旧名称")
    collision:=generated.dup; collision["migrationSourceId"]=id("different-native-site")
    all=original.dup.add(collision)
    plan:=SeedMigration.plan(all,sources)
    verifyEq(maps(plan["records"]).size,0)
    verify(((Str[])plan["warnings"]).any |warning| { warning.contains("未覆盖") })
    verifyEq(collision["migrationSourceId"],id("different-native-site"))
  }

  private [Str:Obj?][] base()
  {
    [map(["id":id("water"),"kind":"category","name":"水","unit":"m3"]),
     map(["id":id("totals"),"kind":"group","name":"总能耗"]),
     map(["id":id("water-group"),"kind":"group","name":"1#楼水表"]),
     map(["id":id("other"),"kind":"group","name":"风机盘管"])]
  }

  private [Str:Obj?] meter(Str key, Str kind, Str name, Str point, Str parent)
  {
    ["id":id(key),"kind":kind,"name":name,"categoryId":id("water"),"pointId":id(point),"parentId":id(parent),"mod":"2026-10-21T00:00:00Z"]
  }
  private [Str:Obj?] source(Str point, Str site, Str name) { ["id":id(point),"siteRef":id(site),"siteName":name] }
  private Str id(Str name) { "p:test:r:"+name }
  private [Str:Obj?] map([Str:Obj?] m) { m }
  private [Str:Obj?][] maps(Obj? v) { SeedMath.maps(v) }
  private [Str:Obj?][] apply([Str:Obj?][] all, [Str:Obj?][] edits)
  {
    ids:=edits.map |r->Str| { r["id"].toStr }
    return all.findAll |r| { !ids.contains(r["id"]) }.dup.addAll(edits)
  }
}

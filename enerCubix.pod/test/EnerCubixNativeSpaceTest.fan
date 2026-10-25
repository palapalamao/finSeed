using util
using haystack

class EnerCubixNativeSpaceTest : Test
{
  Void testFlatNativeLevelDefersIndentedEquipsToTheirVisibleParent()
  {
    parent:=Etc.makeDict(["id":Ref("parent"),"equip":Marker.val])
    nested:=Etc.makeDict(["id":Ref("nested"),"equip":Marker.val,"equipRef":parent.id])
    deep:=Etc.makeDict(["id":Ref("deep"),"equip":Marker.val,"equipRef":nested.id])
    orphan:=Etc.makeDict(["id":Ref("orphan"),"equip":Marker.val,"equipRef":Ref("unavailable")])
    point:=Etc.makeDict(["id":Ref("point"),"point":Marker.val,"equipRef":parent.id])
    // Native level sorting can put a nested equip before its own parent.
    level:=[nested,point,parent,orphan,deep]
    roots:=EnerCubixNativeSpace.childRoots(level) |r->Ref?| { r.has("equip") ? (r["equipRef"] as Ref) : null }
    verifyEq(roots.map |r->Str| { r.id.id },["point","parent","orphan"])
    verifyEq(level.size,5)
    // The same native child call under the parent retains the direct nested equip.
    roots=EnerCubixNativeSpace.childRoots([deep,nested,point]) |r->Ref?| { r.has("equip") ? (r["equipRef"] as Ref) : null }
    verifyEq(roots.map |r->Str| { r.id.id },["nested","point"])
  }

  Void testNativeIdentityOrderAndPointLeaves()
  {
    source:=fixtureSource
    projected:=source.project(stored)
    visible:=projected.findAll |r| { r["nativeReadonly"] == true }
    verifyEq(visible.map |r->Str| { r["id"].toStr },["enerCubix-site","floor-a","floor-b","equip","nested-equip","point","temperature"])
    verifyEq(find(projected,"floor-a")["parentId"],"enerCubix-site")
    verifyEq(find(projected,"nested-equip")["parentId"],"equip")
    verifyEq(find(projected,"point")["parentId"],"nested-equip")
    verifyEq(find(projected,"point")["kind"],"nativePoint")
    verifyEq(find(projected,"temperature")["kind"],"nativePoint")
    verifyEq(find(projected,"point")["name"],"电能")
    verifyEq(find(projected,"point")["nativeDis"],"园区 一层 空调 电能")
    verifyEq(find(projected,"point")["nativeSourceId"],"point")
    verifyNull(find(projected,"point")["pointId"])
    verifyNull(find(projected,"point")["includeInTotals"])
    verifyEq(find(projected,"enerCubix-site")["area"],900f)
    verifyEq(find(projected,"floor-a")["area"],100f)
    verifyEq(find(projected,"manual-space")["nativeHidden"],true)
  }

  Void testRefreshRenameReparentAndMissingSourcesWithoutChangingStorage()
  {
    raw:=stored
    before:=JsonOutStream.writeJsonToStr(raw)
    source:=fixtureSource
    first:=source.project(raw)
    verifyEq(find(first,"meter")["nativeSpaceId"],"nested-equip")
    source.nodes.find |r| { r["id"] == "equip" }["name"]="新设备名"
    source.nodes.find |r| { r["id"] == "equip" }["parentId"]="floor-b"
    source.nodes.find |r| { r["id"] == "point" }["parentId"]="equip"
    second:=source.project(raw)
    verifyEq(find(second,"equip")["name"],"新设备名")
    verifyEq(find(second,"equip")["parentId"],"floor-b")
    verifyEq(find(second,"meter")["nativeSpaceId"],"equip")
    verifyEq(find(second,"meter")["spaceId"],"manual-space")
    source.nodes=source.nodes.findAll |r| { r["id"] != "point" }
    third:=source.project(raw)
    verifyNull(third.find |r| { r["id"] == "point" })
    verifyNull(find(third,"meter")["nativeSpaceId"])
    verifyEq(find(third,"meter")["nativeSourceMissing"],true)
    verifyEq(JsonOutStream.writeJsonToStr(raw),before)
  }

  Void testIndependentRelationshipsAndLegacyCoverageArePreserved()
  {
    raw:=stored
    meter:=find(raw,"meter")
    meter["parentId"]="legacy-group"; meter["meterParentId"]="upstream"
    meter["organizationId"]="tenant"; meter["utilityId"]="lighting"
    meter["historyMode"]="cumulative"; meter["includeInTotals"]=false
    source:=fixtureSource
    projected:=find(source.project(raw),"meter")
    meter.each |value,key| { verifyEq(projected[key],value) }
    verifyEq(projected["nativeSpaceId"],"nested-equip")
    verifyEq(projected["nativeSpaceReadonly"],true)
    computed:=find(raw,"virtual")
    verifyNull(find(source.project(raw),"virtual")["nativeSpaceId"])
    verifyEq(find(source.project(raw),"virtual"),computed)
  }

  Void testServerGuardsAndSubmittedNativeMetadata()
  {
    projected:=fixtureSource.project(stored)
    ["enerCubix-site","floor-a","equip","point"].each |id| { verifyErr(ArgErr#) { EnerCubixNativeSpace.mustEditable(id,projected) } }
    EnerCubixNativeSpace.mustEditable("meter",projected)
    dirty:=find(projected,"meter").dup
    dirty["nativeReadonly"]=false; dirty["nativeSpaceId"]="forged"
    clean:=EnerCubixNativeSpace.clean(dirty)
    verify(!clean.keys.any |key| { key.startsWith("native") })
    verifyEq(clean["spaceId"],"manual-space")
    verifyEq(clean["pointId"],"point")
  }

  Void testNewBindingUsesNativeParentAndUnrelatedEditKeepsLegacySpace()
  {
    projected:=fixtureSource.project(stored)
    previous:=find(stored,"meter")
    edit:=previous.dup
    EnerCubixNativeSpace.placeBinding(edit,previous,projected)
    verifyEq(edit["spaceId"],"manual-space")
    edit=previous.dup
    EnerCubixNativeSpace.placeBinding(edit,null,projected)
    verifyEq(edit["spaceId"],"nested-equip")
    edit=previous.dup; edit["pointId"]="temperature"
    EnerCubixNativeSpace.placeBinding(edit,previous,projected)
    verifyEq(edit["spaceId"],"equip")
    EnerCubixConfig.validate(edit,projected)
  }

  Void testFinMembershipHistoryAndNoAutomaticEnergyAdmission()
  {
    projected:=fixtureSource.project(stored)
    request:=request
    verifyEq(EnerCubixDimension.dependencies(request,projected)["points"],["point"])
    history:=[Str:Obj?]["pointId":"point","unit":"kWh","mode":"interval","samples":[[Str:Obj?]["ts":"2026-01-01T00:00:00Z","value":5f]]]
    result:=EnerCubixEngine.report(request,projected,[history])
    series:=EnerCubixMath.maps(result["series"])
    verifyEq(EnerCubixMath.maps(series.first["points"]).first["value"],5f)
    verifyEq(EnerCubixDimension("space",projected,true).members("floor-b").size,0)
    verifyEq(EnerCubixDimension("space",projected).members("manual-space").size,1)
    verifyEq(EnerCubixDimension("space",projected,true).members("manual-space").size,0)
    request["nodeIds"]=["temperature"]
    verifyEq(EnerCubixDimension.dependencies(request,projected)["points"],Str[,])
    verifyErr(ArgErr#) { EnerCubixEngine.report(request,projected,[Str:Obj?][,]) }
    request["nodeIds"]=["floor-a"]
    source:=fixtureSource
    source.nodes=source.nodes.findAll |r| { r["id"] != "point" }
    missing:=source.project(stored)
    verifyEq(EnerCubixDimension.dependencies(request,missing)["points"],Str[,])
    result=EnerCubixEngine.report(request,missing,[Str:Obj?][,])
    verify(((Str[])result["warnings"]).any |w| { w.contains("nativeSourceMissing") })
    request["nodeIds"]=["meter"]
    verifyEq(EnerCubixDimension.dependencies(request,missing)["points"],Str[,])
  }

  Void testInfoIsBoundedAndChangesWithNativeSource()
  {
    source:=fixtureSource
    info:=source.info(stored)
    verifyEq(info["containerCount"],5); verifyEq(info["pointCount"],2)
    verifyEq(info["nodeCount"],7); verifyEq(info["missingSourceCount"],0)
    verifyEq(info["nativeTreePath"],"/site/floor/equip/point")
    verify(!info.containsKey("records")); verify(!info.containsKey("nodes"))
    source.nodes.find |r| { r["id"] == "equip" }["name"]="renamed"
    verifyNotEq(source.info(stored)["sourceSignature"],info["sourceSignature"])
  }

  private EnerCubixNativeSpace fixtureSource()
  {
    source:=EnerCubixNativeSpace()
    source.path="/site/floor/equip/point"
    source.nodes=[
      [Str:Obj?]["id":"site","sourceKind":"site","name":"园区"],
      [Str:Obj?]["id":"floor-a","sourceKind":"floor","name":"一层","parentId":"site","area":100f],
      [Str:Obj?]["id":"floor-b","sourceKind":"floor","name":"二层","parentId":"site"],
      [Str:Obj?]["id":"equip","sourceKind":"equip","name":"空调","parentId":"floor-a"],
      [Str:Obj?]["id":"nested-equip","sourceKind":"equip","name":"电表设备","parentId":"equip"],
      [Str:Obj?]["id":"point","sourceKind":"point","name":"电能","parentId":"nested-equip","nativeDis":"园区 一层 空调 电能","unit":"kWh","his":true],
      [Str:Obj?]["id":"temperature","sourceKind":"point","name":"温度","parentId":"equip","unit":"°C","his":true],
    ]
    return source
  }

  private [Str:Obj?][] stored()
  {
    return [
      [Str:Obj?]["id":"enerCubix-site","kind":"space","name":"旧园区名","migrationSourceId":"site","area":900f],
      [Str:Obj?]["id":"manual-space","kind":"space","name":"历史空间"],
      [Str:Obj?]["id":"electric","kind":"category","name":"电","unit":"kWh"],
      [Str:Obj?]["id":"meter","kind":"meter","name":"已绑定电表","pointId":"point","spaceId":"manual-space","categoryId":"electric","unit":"kWh"],
      [Str:Obj?]["id":"virtual","kind":"meter","name":"虚拟表","expressionId":"expression","spaceId":"manual-space","categoryId":"electric"],
    ]
  }

  private Str:Obj? request()
  { ["kind":"profile","dimension":"space","spaceSource":"fin","nodeIds":["floor-a"],"from":"2026-01-01T00:00:00Z","to":"2026-01-01T01:00:00Z","period":"hour","tz":"UTC"] }

  private Str:Obj? find([Str:Obj?][] records, Str id)
  { records.find |r| { r["id"] == id } ?: throw Err("Missing fixture: $id") }
}

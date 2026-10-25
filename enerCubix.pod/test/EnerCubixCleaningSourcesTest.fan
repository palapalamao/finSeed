using haystack

class EnerCubixCleaningSourcesTest : Test
{
  Void testOwnStoredCleaningDoesNotRequireReadyOrExistingBranches()
  {
    root:=equip("main",null,true)
    a:=equip("A","main"); b:=equip("B","main")
    pa:=point("A",null); pb:=point("B","enerCubixCleanHis",["invalid":true])
    issues:=check(root,[root,a,b],[point("main"),pa,pb])
    verify(issues.isEmpty)
    verify(check(root,[root],[point("main")]).isEmpty)
  }

  Void testPhysicalMetersAndRecognizedExternalOutputs()
  {
    root:=equip("main",null,true)
    a:=equip("A","main"); b:=equip("B","main")
    points:=[point("main"),point("A"),point("B","hfTotalized")]
    verify(check(root,[root,a,b],points).isEmpty)
    b=Etc.makeDict(Etc.dictToMap(b).set("enerCubixHistoryMode","interval"))
    points[2]=point("B","externalHis")
    verify(check(root,[root,a,b],points).isEmpty)
    verify(check(a,[root,a,b],points).isEmpty)
    b=equip("B","main")
    verify(check(root,[root,a,b],points).isEmpty)
    verify(check(b,[root,a,b],points).first.contains("历史函数"))
  }

  Void testHistoricalSourceDoesNotDependOnCurrentNestedGraph()
  {
    root:=equip("main",null,true); branch:=equip("branch","main",true)
    leaf:=equip("leaf","branch"); other:=equip("other","main")
    rows:=[root,branch,leaf,other]
    points:=[point("main"),point("branch"),point("leaf",null),point("other",null)]
    issues:=check(root,rows,points)
    verify(issues.isEmpty)
    points[2]=point("leaf"); points[3]=point("other","enerCubixCleanHis",["unit":"L"])
    verify(check(root,rows,points).isEmpty)
    rows[3]=Etc.makeDict(Etc.dictToMap(other).set("enerCubixCategoryRef",Ref("water")))
    verify(check(root,rows,points).isEmpty)
  }

  Void testOwnPointIdentityHistoryAndConfigurationAreStillRequired()
  {
    root:=equip("main",null,true)
    verify(!check(root,[root],Dict[,]).isEmpty)
    invalid:=Etc.makeDict(Etc.dictToMap(point("main")).set("equipRef",Ref("other")))
    verify(!check(root,[root],[invalid]).isEmpty)
    verify(check(root,[root],[point("main","enerCubixCleanHis",["invalid":true])]).first.contains("清洗配置无效"))
    verify(check(root,[root],[point("main","externalHis")]).first.contains("历史函数"))
  }

  private Str[] check(Dict root, Dict[] equips, Dict[] points)
  {
    lookup:=|Ref id->Dict?| { equips.dup.addAll(points).find |r| { r.id == id } }
    validate:=|Dict p| { if (p.has("invalid")) throw ArgErr("invalid configuration") }
    return EnerCubixCleaningRepo.sourceProblems(root,lookup,validate)
  }

  private Dict equip(Str id, Str? parent := null, Bool autoSum := false)
  {
    tags:=Str:Obj?["id":Ref(id),"equip":Marker.val,"dis":id,"enerCubixKind":"totalMeter","enerCubixPointRef":Ref("point-"+id),"enerCubixCategoryRef":Ref("electric"),"enerCubixAutoSum":autoSum]
    if (parent != null) tags["enerCubixMeterParentRef"]=Ref(parent)
    return Etc.makeDict(tags)
  }

  private Dict point(Str id, Str? function := "enerCubixCleanHis", Str:Obj? extra := Str:Obj?[:])
  {
    tags:=Str:Obj?["id":Ref("point-"+id),"point":Marker.val,"his":Marker.val,"kind":"Number","unit":"kWh","equipRef":Ref(id)]
    if (function != null) tags["hisFunc"]=function
    return Etc.makeDict(tags.setAll(extra))
  }
}

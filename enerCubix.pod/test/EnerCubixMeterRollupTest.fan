using haystack
using folio
using util

class EnerCubixMeterRollupTest : Test
{
  Void testDefaultIntervalIsOneSecond()
  {
    verifyEq(EnerCubixMeterRollup.intervalSeconds,1)
    verifyEq(EnerCubixMeterRollup.intervalSeconds(3600),3600)
  }

  Void testProjectIntervalPersistsAndControlsNextRun()
  {
    withDb |db|
    {
      verifyEq(EnerCubixMeterRollup.configuredInterval(db),1)
      config:=Str:Obj?["kind":"settings","name":"settings","rotationSeconds":20,"meterRollupSeconds":30]
      rec:=db.commit(Diff.makeAdd(Etc.makeDict(["enerCubix":Marker.val,"enerCubixKind":"settings","enerCubixConfig":JsonOutStream.writeJsonToStr(config)]),Ref("settings"))).newRec
      verifyEq(EnerCubixMeterRollup.configuredInterval(db),30)
      verify(EnerCubixMeterRollup.isDue(-1,0,30))
      verifyFalse(EnerCubixMeterRollup.isDue(0,29sec.ticks,30))
      verify(EnerCubixMeterRollup.isDue(0,30sec.ticks,30))
      config["meterRollupSeconds"]=1
      db.commit(Diff(rec,Etc.makeDict(["enerCubixConfig":JsonOutStream.writeJsonToStr(config)])))
      verifyEq(EnerCubixMeterRollup.configuredInterval(db),1)
      verify(EnerCubixMeterRollup.isDue(0,2sec.ticks,EnerCubixMeterRollup.configuredInterval(db)))
      verifyFalse(EnerCubixMeterRollup.isDue(2sec.ticks,2500ms.ticks,1))
      verifyEq(EnerCubixRepo.decode(db.readById(Ref("settings")))["rotationSeconds"],20)
      verifyNull(db.readByIdPersistentTags(Ref("settings"))["curVal"])
    }
  }

  Void testSettingsRejectInvalidRollupIntervals()
  {
    [0f,-1f,1.5f,3601f,Float.nan,Float.posInf].each |seconds|
    {
      verifyErr(ArgErr#) { EnerCubixConfig.validate(["kind":"settings","name":"settings","meterRollupSeconds":seconds],[Str:Obj?][,]) }
    }
  }

  Void testBoundNativePointsRollUpWithoutModelMigration()
  {
    withDb |db|
    {
      ["root","a","b"].each |id|
      {
        add(db,Etc.makeDict(["id":Ref(id+"-device"),"equip":Marker.val,"dis":id]))
        tags:=Etc.dictToMap(point(id,id == "root" ? 999f : (id == "a" ? 10f : 5f)))
        tags["equipRef"]=Ref(id+"-device"); add(db,Etc.makeDict(tags))
        add(db,archive(id,id == "root" ? null : "root"))
      }
      original:=db.readById(Ref("root")); device:=db.readById(Ref("root-device"))
      EnerCubixMeterRollup.update(db)
      p:=db.readById(Ref("root-p"))
      verifyEq(p["curVal"],Number(999f,Unit("m³")))
      verifyEq(p["enerCubixRollupRef"],Ref("root"))
      verifyEq(db.readById(Ref("root")),original)
      verifyEq(db.readById(Ref("root-device")),device)
      verifyNull(db.readById(Ref("enerCubix-native-equip-model"),false))
      verifyNull(db.readByIdPersistentTags(p.id)["curVal"])
      db.commit(Diff(db.readById(Ref("a-p")),Etc.makeDict(["curVal":Number(12f,Unit("m³"))]),Diff.transient))
      EnerCubixMeterRollup.update(db)
      verifyEq(db.readById(p.id)["curVal"],Number(1001f,Unit("m³")))
      db.commit(Diff(db.readById(Ref("a-p")),Etc.makeDict(["curVal":Remove.val]),Diff.transient))
      EnerCubixMeterRollup.update(db)
      verifyNull(db.readById(p.id)["curVal"])
      verifyEq(db.readById(p.id)["enerCubixRollupStatus"],"missing")
    }
  }

  Void testBoundConnectedMeterIsNotOverwritten()
  {
    withDb |db|
    {
      [archive("root"),archive("a","root")].each |r| { add(db,r) }
      ["root","a"].each |id|
      {
        add(db,Etc.makeDict(["id":Ref(id+"-device"),"equip":Marker.val]))
        tags:=Etc.dictToMap(point(id,12f)); tags["equipRef"]=Ref(id+"-device")
        if (id == "root") tags["modbusConnRef"]=Ref("conn")
        add(db,Etc.makeDict(tags))
      }
      original:=db.readById(Ref("root-p"))
      EnerCubixMeterRollup.update(db)
      verifyEq(db.readById(original.id),original)
    }
  }

  Void testDuplicateBindingsCannotOverwriteTheSamePoint()
  {
    root:=Etc.dictToMap(archive("root")); duplicate:=root.dup; duplicate["id"]=Ref("duplicate")
    out:=EnerCubixMeterRollup.calculate([Etc.makeDict(root),Etc.makeDict(duplicate),archive("a","root")],
      [Etc.makeDict(Etc.dictToMap(point("root",999f)).set("equipRef",Ref("root-device"))),Etc.makeDict(Etc.dictToMap(point("a",10f)).set("equipRef",Ref("a-device")))])
    verifyEq(out["root"]["status"],"ambiguousPoint")
    verifyNull(out["root"]["val"])
  }

  Void testMeasuredParentIsPreservedAndFormsInputBoundary()
  {
    withDb |db|
    {
      measured:=Etc.dictToMap(equip("measured","root")); measured["enerCubixAutoSum"]=false
      [equip("root"),Etc.makeDict(measured),equip("leaf","measured"),equip("b","root")].each |eq| { add(db,eq) }
      [point("root",0f),point("measured",100f),point("leaf",10f),point("b",5f)].each |p| { add(db,p) }
      original:=db.readById(Ref("measured-p"))
      EnerCubixMeterRollup.update(db)
      verifyEq(db.readById(Ref("root-p"))["curVal"],Number(0f,Unit("m³")))
      verifyEq(db.readById(Ref("measured-p")),original)
      db.commit(Diff(db.readById(original.id),Etc.makeDict(["curVal":Number(105f,Unit("m³"))]),Diff.transient))
      EnerCubixMeterRollup.update(db)
      verifyEq(db.readById(Ref("root-p"))["curVal"],Number(5f,Unit("m³")))
      db.commit(Diff(db.readById(Ref("leaf-p")),Etc.makeDict(["curVal":Remove.val]),Diff.transient))
      EnerCubixMeterRollup.update(db)
      verifyEq(db.readById(Ref("root-p"))["curVal"],Number(5f,Unit("m³")))
    }
  }

  Void testConnectedPointIsNeverOverwrittenEvenWhenEnabled()
  {
    withDb |db|
    {
      [equip("root"),equip("a","root")].each |eq| { add(db,eq) }
      tags:=Etc.dictToMap(point("root",999f)); tags["modbusConnRef"]=Ref("conn")
      [Etc.makeDict(tags),point("a",10f)].each |p| { add(db,p) }
      prior:=db.readById(Ref("root-p"))
      EnerCubixMeterRollup.update(db)
      verifyEq(db.readById(Ref("root-p")),prior)
    }
  }

  Void testOptOutReleasesOnlyMetadataAndPreservesReading()
  {
    withDb |db|
    {
      [equip("root"),equip("a","root")].each |eq| { add(db,eq) }
      [point("root",999f),point("a",10f)].each |p| { add(db,p) }
      EnerCubixMeterRollup.update(db)
      db.commit(Diff(db.readById(Ref("root")),Etc.makeDict(["enerCubixAutoSum":false])))
      db.commit(Diff(db.readById(Ref("root-p")),Etc.makeDict(["curVal":Number(123f,Unit("m³")),"curStatus":"ok"]),Diff.transient))
      EnerCubixMeterRollup.update(db)
      p:=db.readById(Ref("root-p"))
      verifyEq(p["curVal"],Number(123f,Unit("m³")))
      verifyEq(p["curStatus"],"ok"); verifyNull(p["enerCubixRollupRef"])
    }
  }

  Void testNativeTransientUpdatesRecoveryAndDetachment()
  {
    withDb |db|
    {
      [equip("root"),equip("floor","root"),equip("a","floor"),equip("b","root"),equip("unrelated")].each |eq| { add(db,eq) }
      [point("root",999f),point("floor",888f),point("a",10f),point("b",5f),point("unrelated",77f)].each |p| { add(db,p) }
      before:=db.readById(Ref("root-p"))["mod"]
      ts:=DateTime.now
      EnerCubixMeterRollup.update(db,ts)
      verifyEq(db.readById(Ref("root-p"))["curVal"],Number(999f,Unit("m³")))
      verifyEq(db.readById(Ref("floor-p"))["curVal"],Number(888f,Unit("m³")))
      verifyEq(db.readById(Ref("root-p"))["mod"],before)
      verifyEq(db.readById(Ref("root-p"))["enerCubixRollupAt"],ts)
      verifyNull(db.readByIdPersistentTags(Ref("root-p"))["curVal"])
      db.commit(Diff(db.readById(Ref("a-p")),Etc.makeDict(["curVal":Remove.val]),Diff.transient))
      EnerCubixMeterRollup.update(db,ts+30sec)
      verifyNull(db.readById(Ref("root-p"))["curVal"])
      verifyEq(db.readById(Ref("root-p"))["enerCubixRollupStatus"],"missing")
      db.commit(Diff(db.readById(Ref("a-p")),Etc.makeDict(["curVal":Number(12f,Unit("m³"))]),Diff.transient))
      EnerCubixMeterRollup.update(db,ts+60sec)
      verifyEq(db.readById(Ref("root-p"))["curVal"],Number(999f,Unit("m³")))
      verifyEq(db.readById(Ref("root-p"))["enerCubixRollupHasGap"],true)
      db.commit(Diff(db.readById(Ref("a-p")),Etc.makeDict(["curVal":Number(13f,Unit("m³"))]),Diff.transient))
      EnerCubixMeterRollup.update(db,ts+75sec)
      verifyEq(db.readById(Ref("root-p"))["curVal"],Number(1000f,Unit("m³")))
      db.commit(Diff(db.readById(Ref("a")),Etc.makeDict(["enerCubixMeterParentRef":Ref("root")])))
      EnerCubixMeterRollup.update(db,ts+90sec)
      verifyNull(db.readById(Ref("floor-p"))["curVal"])
      verifyNull(db.readById(Ref("root-p"))["curVal"])
      verifyEq(db.readById(Ref("floor-p"))["curStatus"],"fault")
      verifyEq(db.readById(Ref("unrelated-p"))["curVal"],Number(77f,Unit("m³")))
      count:=0
      db.his.read(Ref("root-p"),null,null) |item| { count++ }
      verifyEq(count,0)
    }
  }

  Void testBottomUpAndRecomputeInsteadOfAccumulating()
  {
    equips:=[equip("root"),equip("floor","root"),equip("a","floor"),equip("b","floor"),equip("c","root")]
    points:=[point("root",999f),point("floor",888f),point("a",12f),point("b",8f),point("c",5f)]
    out:=EnerCubixMeterRollup.calculate(equips,points)
    verifyEq(out.keys.sort,["floor","root"])
    verifyEq(out["floor"]["val"],Number(20f,Unit("m³")))
    verifyEq(out["root"]["val"],Number(25f,Unit("m³")))
    points[2]=point("a",13f)
    verifyEq(EnerCubixMeterRollup.calculate(equips,points)["root"]["val"],Number(26f,Unit("m³")))
    verifyEq(points[0]["curVal"],Number(999f,Unit("m³")))
  }

  Void testUnitConversionAndZeroAreValid()
  {
    out:=EnerCubixMeterRollup.calculate([equip("root"),equip("a","root"),equip("b","root")],
      [point("root",0f),point("a",500f,"L"),point("b",0f)])
    verifyEq(out["root"]["status"],"ok")
    verifyEq(out["root"]["val"],Number(0.5f,Unit("m³")))
  }

  Void testMissingBadAndNonFiniteValuesInvalidateAncestors()
  {
    equips:=[equip("root"),equip("floor","root"),equip("a","floor")]
    points:=[point("root",999f),point("floor",888f),point("a",null)]
    out:=EnerCubixMeterRollup.calculate(equips,points)
    verifyEq(out["floor"]["status"],"missing")
    verifyEq(out["root"]["status"],"missing")
    verifyNull(out["root"]["val"])
    [Float.nan,Float.posInf,Float.negInf].each |v|
    {
      points[2]=point("a",v)
      verifyEq(EnerCubixMeterRollup.calculate(equips,points)["root"]["status"],"missing")
    }
    tags:=Etc.dictToMap(point("a",1f)); tags["curStatus"]="fault"
    points[2]=Etc.makeDict(tags)
    verifyEq(EnerCubixMeterRollup.calculate(equips,points)["root"]["status"],"missing")
  }

  Void testUnitsCategoryOwnershipAndCyclesCannotProduceTotals()
  {
    equips:=[equip("root"),equip("a","root")]
    verifyEq(EnerCubixMeterRollup.calculate(equips,[point("root",0f),point("a",1f,"kWh")])["root"]["status"],"incompatibleUnit")
    tags:=Etc.dictToMap(equips[1]); tags["enerCubixCategoryRef"]=Ref("electric")
    verifyEq(EnerCubixMeterRollup.calculate([equips[0],Etc.makeDict(tags)],[point("root",0f),point("a",1f)])["root"]["status"],"incompatibleCategory")
    tags=Etc.dictToMap(point("a",1f)); tags["equipRef"]=Ref("other")
    verifyEq(EnerCubixMeterRollup.calculate(equips,[point("root",0f),Etc.makeDict(tags)])["root"]["status"],"invalidPoint")
    out:=EnerCubixMeterRollup.calculate([equip("root","a"),equip("a","root")],[point("root",0f),point("a",1f)])
    verifyEq(out["root"]["status"],"cycle"); verifyEq(out["a"]["status"],"cycle")
  }

  Void testCanonicalAliasesAndSensorsDoNotDoubleCount()
  {
    alias:=Etc.dictToMap(equip("alias","root")); alias["enerCubixCanonicalRef"]=Ref("a")
    sensor:=Etc.dictToMap(equip("sensor","root")); sensor["enerCubixKind"]="sensor"
    out:=EnerCubixMeterRollup.calculate([equip("root"),equip("a","root"),Etc.makeDict(alias),Etc.makeDict(sensor)],
      [point("root",100f),point("a",5f),point("alias",5f),point("sensor",10f)])
    verifyEq(out["root"]["val"],Number(5f,Unit("m³")))
  }

  Void testRelationshipChangesUseFreshGraph()
  {
    points:=[point("root",0f),point("floor",0f),point("a",5f)]
    verifyEq(EnerCubixMeterRollup.calculate([equip("root"),equip("floor","root"),equip("a","floor")],points)["root"]["val"],Number(5f,Unit("m³")))
    verifyEq(EnerCubixMeterRollup.calculate([equip("root"),equip("floor","root"),equip("a","root")],points)["root"]["val"],Number(5f,Unit("m³")))
    verify(EnerCubixMeterRollup.calculate([equip("root"),equip("floor"),equip("a")],points).isEmpty)
  }

  private Dict equip(Str id, Str? parent:=null)
  {
    tags:=Str:Obj?["id":Ref(id),"equip":Marker.val,"enerCubix":Marker.val,"enerCubixKind":"meter","enerCubixAutoSum":true,"enerCubixPointRef":Ref(id+"-p"),"enerCubixCategoryRef":Ref("water")]
    if (parent != null) tags["enerCubixMeterParentRef"]=Ref(parent)
    return Etc.makeDict(tags)
  }

  private Dict archive(Str id, Str? parent:=null)
  {
    tags:=Str:Obj?["id":Ref(id),"enerCubix":Marker.val,"enerCubixKind":"meter","enerCubixConfig":"{\"kind\":\"meter\",\"autoSum\":true}","enerCubixPointRef":Ref(id+"-p"),"enerCubixCategoryRef":Ref("water")]
    if (parent != null) tags["enerCubixMeterParentRef"]=Ref(parent)
    return Etc.makeDict(tags)
  }

  private Dict point(Str eq, Float? value, Str unit:="m³")
  {
    tags:=Str:Obj?["id":Ref(eq+"-p"),"equipRef":Ref(eq),"point":Marker.val,"his":Marker.val,"unit":unit,"curStatus":"ok"]
    if (value != null) tags["curVal"]=Number(value,Unit(unit))
    return Etc.makeDict(tags)
  }

  private Void withDb(|Folio| work)
  {
    dir:=Env.cur.tempDir+`enerCubix-rollup-test-${Uuid()}/`; dir.create
    db:=(Folio)Type.find("hxFolio::HxFolio").method("open").call(FolioConfig { name="enerCubixRollupTest";it.dir=dir;log=Log.get("enerCubixRollupTest") })
    try { work(db) }
    finally { db.close; if (dir.parent.normalize == Env.cur.tempDir.normalize) dir.delete }
  }

  private Void add(Folio db, Dict rec)
  {
    tags:=Etc.dictToMap(rec); tags.remove("id")
    current:=Str:Obj?[:]
    ["curVal","curStatus"].each |tag| { if (tags.containsKey(tag)) current[tag]=tags.remove(tag) }
    added:=db.commit(Diff.makeAdd(Etc.makeDict(tags),rec.id)).newRec
    if (!current.isEmpty) db.commit(Diff(added,Etc.makeDict(current),Diff.transient))
  }
}

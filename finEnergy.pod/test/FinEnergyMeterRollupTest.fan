using haystack
using folio
using util

class FinEnergyMeterRollupTest : Test
{
  Void testDefaultIntervalIsOneSecond()
  {
    verifyEq(FinEnergyMeterRollup.intervalSeconds,1)
    verifyEq(FinEnergyMeterRollup.intervalSeconds(3600),3600)
  }

  Void testFormulaCurrentValueUsesExplicitPrimaryAndDoesNotChangeHistory()
  {
    withDb |db|
    {
      virtualTags:=Etc.dictToMap(equip("virtual"));virtualTags["finEnergyAutoSum"]=false;virtualTags["finEnergyExpressionRef"]=Ref("formula")
      source:=Etc.dictToMap(equip("source"));source["finEnergyAutoSum"]=false
      expression:=Etc.makeDict(["id":Ref("formula"),"finEnergy":Marker.val,"finEnergyKind":"expression","finEnergyConfig":JsonOutStream.writeJsonToStr(["kind":"expression","formula":"a * 2","variables":["a":"source"]])])
      [Etc.makeDict(virtualTags),Etc.makeDict(source),expression,point("virtual",1f),point("source",10f)].each |r| {add(db,r)}
      before:=db.readAllList(Filter.has("point")).map |r->Str| {r.id.id}.sort
      FinEnergyMeterRollup.update(db)
      verifyEq(db.readById(Ref("virtual-p"))["curVal"],Number(20f,Unit("m³")))
      verifyEq(db.readAllList(Filter.has("point")).map |r->Str| {r.id.id}.sort,before)
      samples:=HisItem[,];db.his.read(Ref("virtual-p"),null,null) |item| {samples.add(item)}
      verify(samples.isEmpty)
      db.commit(Diff(db.readById(Ref("virtual")),Etc.makeDict(["finEnergyPointRef":Remove.val])))
      FinEnergyMeterRollup.update(db)
      verifyNull(db.readById(FinEnergyMeterHistory.formulaId(Ref("virtual")),false))
    }
  }

  Void testFormulaCurrentUnitsAndSensorInputsRemainIndependent()
  {
    target:=Etc.dictToMap(equip("virtual"));target["finEnergyAutoSum"]=false;target["finEnergyExpressionRef"]=Ref("formula");target["finEnergyCategoryRef"]=Ref("energy")
    source:=Etc.dictToMap(equip("source"));source["finEnergyAutoSum"]=false;source["finEnergyCategoryRef"]=Ref("energy")
    expression:=Etc.makeDict(["id":Ref("formula"),"finEnergy":Marker.val,"finEnergyKind":"expression","finEnergyConfig":JsonOutStream.writeJsonToStr(["kind":"expression","formula":"a * 2","variables":["a":"source"]])])
    category:=Etc.makeDict(["id":Ref("energy"),"finEnergyKind":"category","finEnergyConfig":"{\"kind\":\"category\",\"unit\":\"kWh\"}"])
    out:=FinEnergyMeterRollup.calculate([Etc.makeDict(target),Etc.makeDict(source),expression,category],[point("virtual",0f,"Wh"),point("source",5000f,"Wh")])
    verifyEq(out["virtual"]["val"],Number(10000f,Unit("Wh")))
    source["finEnergyKind"]="sensor"
    out=FinEnergyMeterRollup.calculate([Etc.makeDict(target),Etc.makeDict(source),expression],[point("virtual",0f,"m³"),point("source",3f,"m³")])
    verifyEq(out["virtual"]["val"],Number(6f,Unit("m³")))
  }

  Void testProjectIntervalPersistsAndControlsNextRun()
  {
    withDb |db|
    {
      verifyEq(FinEnergyMeterRollup.configuredInterval(db),1)
      config:=Str:Obj?["kind":"settings","name":"settings","rotationSeconds":20,"meterRollupSeconds":30]
      rec:=db.commit(Diff.makeAdd(Etc.makeDict(["finEnergy":Marker.val,"finEnergyKind":"settings","finEnergyConfig":JsonOutStream.writeJsonToStr(config)]),Ref("settings"))).newRec
      verifyEq(FinEnergyMeterRollup.configuredInterval(db),30)
      verify(FinEnergyMeterRollup.isDue(-1,0,30))
      verifyFalse(FinEnergyMeterRollup.isDue(0,29sec.ticks,30))
      verify(FinEnergyMeterRollup.isDue(0,30sec.ticks,30))
      config["meterRollupSeconds"]=1
      db.commit(Diff(rec,Etc.makeDict(["finEnergyConfig":JsonOutStream.writeJsonToStr(config)])))
      verifyEq(FinEnergyMeterRollup.configuredInterval(db),1)
      verify(FinEnergyMeterRollup.isDue(0,2sec.ticks,FinEnergyMeterRollup.configuredInterval(db)))
      verifyFalse(FinEnergyMeterRollup.isDue(2sec.ticks,2500ms.ticks,1))
      verifyEq(FinEnergyRepo.decode(db.readById(Ref("settings")))["rotationSeconds"],20)
      verifyNull(db.readByIdPersistentTags(Ref("settings"))["curVal"])
    }
  }

  Void testSettingsRejectInvalidRollupIntervals()
  {
    [0f,-1f,1.5f,3601f,Float.nan,Float.posInf].each |seconds|
    {
      verifyErr(ArgErr#) { FinEnergyConfig.validate(["kind":"settings","name":"settings","meterRollupSeconds":seconds],[Str:Obj?][,]) }
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
      FinEnergyMeterRollup.update(db)
      p:=db.readById(Ref("root-p"))
      verifyEq(p["curVal"],Number(999f,Unit("m³")))
      verifyEq(p["finEnergyRollupRef"],Ref("root"))
      verifyEq(db.readById(Ref("root")),original)
      verifyEq(db.readById(Ref("root-device")),device)
      verifyNull(db.readById(Ref("finEnergy-native-equip-model"),false))
      verifyNull(db.readByIdPersistentTags(p.id)["curVal"])
      db.commit(Diff(db.readById(Ref("a-p")),Etc.makeDict(["curVal":Number(12f,Unit("m³"))]),Diff.transient))
      FinEnergyMeterRollup.update(db)
      verifyEq(db.readById(p.id)["curVal"],Number(1001f,Unit("m³")))
      db.commit(Diff(db.readById(Ref("a-p")),Etc.makeDict(["curVal":Remove.val]),Diff.transient))
      FinEnergyMeterRollup.update(db)
      verifyNull(db.readById(p.id)["curVal"])
      verifyEq(db.readById(p.id)["finEnergyRollupStatus"],"missing")
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
      FinEnergyMeterRollup.update(db)
      verifyEq(db.readById(original.id),original)
    }
  }

  Void testDuplicateBindingsCannotOverwriteTheSamePoint()
  {
    root:=Etc.dictToMap(archive("root")); duplicate:=root.dup; duplicate["id"]=Ref("duplicate")
    out:=FinEnergyMeterRollup.calculate([Etc.makeDict(root),Etc.makeDict(duplicate),archive("a","root")],
      [Etc.makeDict(Etc.dictToMap(point("root",999f)).set("equipRef",Ref("root-device"))),Etc.makeDict(Etc.dictToMap(point("a",10f)).set("equipRef",Ref("a-device")))])
    verifyEq(out["root"]["status"],"ambiguousPoint")
    verifyNull(out["root"]["val"])
  }

  Void testMeasuredParentIsPreservedAndFormsInputBoundary()
  {
    withDb |db|
    {
      measured:=Etc.dictToMap(equip("measured","root")); measured["finEnergyAutoSum"]=false
      [equip("root"),Etc.makeDict(measured),equip("leaf","measured"),equip("b","root")].each |eq| { add(db,eq) }
      [point("root",0f),point("measured",100f),point("leaf",10f),point("b",5f)].each |p| { add(db,p) }
      original:=db.readById(Ref("measured-p"))
      FinEnergyMeterRollup.update(db)
      verifyEq(db.readById(Ref("root-p"))["curVal"],Number(0f,Unit("m³")))
      verifyEq(db.readById(Ref("measured-p")),original)
      db.commit(Diff(db.readById(original.id),Etc.makeDict(["curVal":Number(105f,Unit("m³"))]),Diff.transient))
      FinEnergyMeterRollup.update(db)
      verifyEq(db.readById(Ref("root-p"))["curVal"],Number(5f,Unit("m³")))
      db.commit(Diff(db.readById(Ref("leaf-p")),Etc.makeDict(["curVal":Remove.val]),Diff.transient))
      FinEnergyMeterRollup.update(db)
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
      FinEnergyMeterRollup.update(db)
      verifyEq(db.readById(Ref("root-p")),prior)
    }
  }

  Void testOptOutReleasesOnlyMetadataAndPreservesReading()
  {
    withDb |db|
    {
      [equip("root"),equip("a","root")].each |eq| { add(db,eq) }
      [point("root",999f),point("a",10f)].each |p| { add(db,p) }
      FinEnergyMeterRollup.update(db)
      db.commit(Diff(db.readById(Ref("root")),Etc.makeDict(["finEnergyAutoSum":false])))
      db.commit(Diff(db.readById(Ref("root-p")),Etc.makeDict(["curVal":Number(123f,Unit("m³")),"curStatus":"ok"]),Diff.transient))
      FinEnergyMeterRollup.update(db)
      p:=db.readById(Ref("root-p"))
      verifyEq(p["curVal"],Number(123f,Unit("m³")))
      verifyEq(p["curStatus"],"ok"); verifyNull(p["finEnergyRollupRef"])
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
      FinEnergyMeterRollup.update(db,ts)
      verifyEq(db.readById(Ref("root-p"))["curVal"],Number(999f,Unit("m³")))
      verifyEq(db.readById(Ref("floor-p"))["curVal"],Number(888f,Unit("m³")))
      verifyEq(db.readById(Ref("root-p"))["mod"],before)
      verifyEq(db.readById(Ref("root-p"))["finEnergyRollupAt"],ts)
      verifyNull(db.readByIdPersistentTags(Ref("root-p"))["curVal"])
      db.commit(Diff(db.readById(Ref("a-p")),Etc.makeDict(["curVal":Remove.val]),Diff.transient))
      FinEnergyMeterRollup.update(db,ts+30sec)
      verifyNull(db.readById(Ref("root-p"))["curVal"])
      verifyEq(db.readById(Ref("root-p"))["finEnergyRollupStatus"],"missing")
      db.commit(Diff(db.readById(Ref("a-p")),Etc.makeDict(["curVal":Number(12f,Unit("m³"))]),Diff.transient))
      FinEnergyMeterRollup.update(db,ts+60sec)
      verifyEq(db.readById(Ref("root-p"))["curVal"],Number(999f,Unit("m³")))
      verifyEq(db.readById(Ref("root-p"))["finEnergyRollupHasGap"],true)
      db.commit(Diff(db.readById(Ref("a-p")),Etc.makeDict(["curVal":Number(13f,Unit("m³"))]),Diff.transient))
      FinEnergyMeterRollup.update(db,ts+75sec)
      verifyEq(db.readById(Ref("root-p"))["curVal"],Number(1000f,Unit("m³")))
      db.commit(Diff(db.readById(Ref("a")),Etc.makeDict(["finEnergyMeterParentRef":Ref("root")])))
      FinEnergyMeterRollup.update(db,ts+90sec)
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
    out:=FinEnergyMeterRollup.calculate(equips,points)
    verifyEq(out.keys.sort,["floor","root"])
    verifyEq(out["floor"]["val"],Number(20f,Unit("m³")))
    verifyEq(out["root"]["val"],Number(25f,Unit("m³")))
    points[2]=point("a",13f)
    verifyEq(FinEnergyMeterRollup.calculate(equips,points)["root"]["val"],Number(26f,Unit("m³")))
    verifyEq(points[0]["curVal"],Number(999f,Unit("m³")))
  }

  Void testUnitConversionAndZeroAreValid()
  {
    out:=FinEnergyMeterRollup.calculate([equip("root"),equip("a","root"),equip("b","root")],
      [point("root",0f),point("a",500f,"L"),point("b",0f)])
    verifyEq(out["root"]["status"],"ok")
    verifyEq(out["root"]["val"],Number(0.5f,Unit("m³")))
  }

  Void testMissingBadAndNonFiniteValuesInvalidateAncestors()
  {
    equips:=[equip("root"),equip("floor","root"),equip("a","floor")]
    points:=[point("root",999f),point("floor",888f),point("a",null)]
    out:=FinEnergyMeterRollup.calculate(equips,points)
    verifyEq(out["floor"]["status"],"missing")
    verifyEq(out["root"]["status"],"missing")
    verifyNull(out["root"]["val"])
    [Float.nan,Float.posInf,Float.negInf].each |v|
    {
      points[2]=point("a",v)
      verifyEq(FinEnergyMeterRollup.calculate(equips,points)["root"]["status"],"missing")
    }
    tags:=Etc.dictToMap(point("a",1f)); tags["curStatus"]="fault"
    points[2]=Etc.makeDict(tags)
    verifyEq(FinEnergyMeterRollup.calculate(equips,points)["root"]["status"],"missing")
  }

  Void testUnitsCategoryOwnershipAndCyclesCannotProduceTotals()
  {
    equips:=[equip("root"),equip("a","root")]
    verifyEq(FinEnergyMeterRollup.calculate(equips,[point("root",0f),point("a",1f,"kWh")])["root"]["status"],"incompatibleUnit")
    tags:=Etc.dictToMap(equips[1]); tags["finEnergyCategoryRef"]=Ref("electric")
    verifyEq(FinEnergyMeterRollup.calculate([equips[0],Etc.makeDict(tags)],[point("root",0f),point("a",1f)])["root"]["status"],"incompatibleCategory")
    tags=Etc.dictToMap(point("a",1f)); tags["equipRef"]=Ref("other")
    verifyEq(FinEnergyMeterRollup.calculate(equips,[point("root",0f),Etc.makeDict(tags)])["root"]["status"],"invalidPoint")
    out:=FinEnergyMeterRollup.calculate([equip("root","a"),equip("a","root")],[point("root",0f),point("a",1f)])
    verifyEq(out["root"]["status"],"cycle"); verifyEq(out["a"]["status"],"cycle")
  }

  Void testCanonicalAliasesAndSensorsDoNotDoubleCount()
  {
    alias:=Etc.dictToMap(equip("alias","root")); alias["finEnergyCanonicalRef"]=Ref("a")
    sensor:=Etc.dictToMap(equip("sensor","root")); sensor["finEnergyKind"]="sensor"
    out:=FinEnergyMeterRollup.calculate([equip("root"),equip("a","root"),Etc.makeDict(alias),Etc.makeDict(sensor)],
      [point("root",100f),point("a",5f),point("alias",5f),point("sensor",10f)])
    verifyEq(out["root"]["val"],Number(5f,Unit("m³")))
  }

  Void testRelationshipChangesUseFreshGraph()
  {
    points:=[point("root",0f),point("floor",0f),point("a",5f)]
    verifyEq(FinEnergyMeterRollup.calculate([equip("root"),equip("floor","root"),equip("a","floor")],points)["root"]["val"],Number(5f,Unit("m³")))
    verifyEq(FinEnergyMeterRollup.calculate([equip("root"),equip("floor","root"),equip("a","root")],points)["root"]["val"],Number(5f,Unit("m³")))
    verify(FinEnergyMeterRollup.calculate([equip("root"),equip("floor"),equip("a")],points).isEmpty)
  }

  private Dict equip(Str id, Str? parent:=null)
  {
    tags:=Str:Obj?["id":Ref(id),"equip":Marker.val,"finEnergy":Marker.val,"finEnergyKind":"meter","finEnergyAutoSum":true,"finEnergyPointRef":Ref(id+"-p"),"finEnergyCategoryRef":Ref("water")]
    if (parent != null) tags["finEnergyMeterParentRef"]=Ref(parent)
    return Etc.makeDict(tags)
  }

  private Dict archive(Str id, Str? parent:=null)
  {
    tags:=Str:Obj?["id":Ref(id),"finEnergy":Marker.val,"finEnergyKind":"meter","finEnergyConfig":"{\"kind\":\"meter\",\"autoSum\":true}","finEnergyPointRef":Ref(id+"-p"),"finEnergyCategoryRef":Ref("water")]
    if (parent != null) tags["finEnergyMeterParentRef"]=Ref(parent)
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
    dir:=Env.cur.tempDir+`finEnergy-rollup-test-${Uuid()}/`; dir.create
    db:=(Folio)Type.find("hxFolio::HxFolio").method("open").call(FolioConfig { name="finEnergyRollupTest";it.dir=dir;log=Log.get("finEnergyRollupTest") })
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

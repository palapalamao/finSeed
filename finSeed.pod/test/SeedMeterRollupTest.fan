using haystack
using folio

class SeedMeterRollupTest : Test
{
  Void testMeasuredParentIsPreservedAndFormsInputBoundary()
  {
    withDb |db|
    {
      measured:=Etc.dictToMap(equip("measured","root")); measured["seedAutoSum"]=false
      [equip("root"),Etc.makeDict(measured),equip("leaf","measured"),equip("b","root")].each |eq| { add(db,eq) }
      [point("root",0f),point("measured",100f),point("leaf",10f),point("b",5f)].each |p| { add(db,p) }
      original:=db.readById(Ref("measured-p"))
      SeedMeterRollup.update(db)
      verifyEq(db.readById(Ref("root-p"))["curVal"],Number(105f,Unit("m³")))
      verifyEq(db.readById(Ref("measured-p")),original)
      db.commit(Diff(db.readById(Ref("leaf-p")),Etc.makeDict(["curVal":Remove.val]),Diff.transient))
      SeedMeterRollup.update(db)
      verifyEq(db.readById(Ref("root-p"))["curVal"],Number(105f,Unit("m³")))
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
      SeedMeterRollup.update(db)
      verifyEq(db.readById(Ref("root-p")),prior)
    }
  }

  Void testOptOutReleasesOnlyMetadataAndPreservesReading()
  {
    withDb |db|
    {
      [equip("root"),equip("a","root")].each |eq| { add(db,eq) }
      [point("root",999f),point("a",10f)].each |p| { add(db,p) }
      SeedMeterRollup.update(db)
      db.commit(Diff(db.readById(Ref("root")),Etc.makeDict(["seedAutoSum":false])))
      db.commit(Diff(db.readById(Ref("root-p")),Etc.makeDict(["curVal":Number(123f,Unit("m³")),"curStatus":"ok"]),Diff.transient))
      SeedMeterRollup.update(db)
      p:=db.readById(Ref("root-p"))
      verifyEq(p["curVal"],Number(123f,Unit("m³")))
      verifyEq(p["curStatus"],"ok"); verifyNull(p["seedRollupRef"])
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
      SeedMeterRollup.update(db,ts)
      verifyEq(db.readById(Ref("root-p"))["curVal"],Number(15f,Unit("m³")))
      verifyEq(db.readById(Ref("floor-p"))["curVal"],Number(10f,Unit("m³")))
      verifyEq(db.readById(Ref("root-p"))["mod"],before)
      verifyEq(db.readById(Ref("root-p"))["seedRollupAt"],ts)
      verifyNull(db.readByIdPersistentTags(Ref("root-p"))["curVal"])
      db.commit(Diff(db.readById(Ref("a-p")),Etc.makeDict(["curVal":Remove.val]),Diff.transient))
      SeedMeterRollup.update(db,ts+30sec)
      verifyNull(db.readById(Ref("root-p"))["curVal"])
      verifyEq(db.readById(Ref("root-p"))["seedRollupStatus"],"missing")
      db.commit(Diff(db.readById(Ref("a-p")),Etc.makeDict(["curVal":Number(12f,Unit("m³"))]),Diff.transient))
      SeedMeterRollup.update(db,ts+60sec)
      verifyEq(db.readById(Ref("root-p"))["curVal"],Number(17f,Unit("m³")))
      db.commit(Diff(db.readById(Ref("a")),Etc.makeDict(["seedMeterParentRef":Ref("root")])))
      SeedMeterRollup.update(db,ts+90sec)
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
    out:=SeedMeterRollup.calculate(equips,points)
    verifyEq(out.keys.sort,["floor","root"])
    verifyEq(out["floor"]["val"],Number(20f,Unit("m³")))
    verifyEq(out["root"]["val"],Number(25f,Unit("m³")))
    points[2]=point("a",13f)
    verifyEq(SeedMeterRollup.calculate(equips,points)["root"]["val"],Number(26f,Unit("m³")))
    verifyEq(points[0]["curVal"],Number(999f,Unit("m³")))
  }

  Void testUnitConversionAndZeroAreValid()
  {
    out:=SeedMeterRollup.calculate([equip("root"),equip("a","root"),equip("b","root")],
      [point("root",0f),point("a",500f,"L"),point("b",0f)])
    verifyEq(out["root"]["status"],"ok")
    verifyEq(out["root"]["val"],Number(0.5f,Unit("m³")))
  }

  Void testMissingBadAndNonFiniteValuesInvalidateAncestors()
  {
    equips:=[equip("root"),equip("floor","root"),equip("a","floor")]
    points:=[point("root",999f),point("floor",888f),point("a",null)]
    out:=SeedMeterRollup.calculate(equips,points)
    verifyEq(out["floor"]["status"],"missing")
    verifyEq(out["root"]["status"],"missing")
    verifyNull(out["root"]["val"])
    [Float.nan,Float.posInf,Float.negInf].each |v|
    {
      points[2]=point("a",v)
      verifyEq(SeedMeterRollup.calculate(equips,points)["root"]["status"],"missing")
    }
    tags:=Etc.dictToMap(point("a",1f)); tags["curStatus"]="fault"
    points[2]=Etc.makeDict(tags)
    verifyEq(SeedMeterRollup.calculate(equips,points)["root"]["status"],"missing")
  }

  Void testUnitsCategoryOwnershipAndCyclesCannotProduceTotals()
  {
    equips:=[equip("root"),equip("a","root")]
    verifyEq(SeedMeterRollup.calculate(equips,[point("root",0f),point("a",1f,"kWh")])["root"]["status"],"incompatibleUnit")
    tags:=Etc.dictToMap(equips[1]); tags["seedCategoryRef"]=Ref("electric")
    verifyEq(SeedMeterRollup.calculate([equips[0],Etc.makeDict(tags)],[point("root",0f),point("a",1f)])["root"]["status"],"incompatibleCategory")
    tags=Etc.dictToMap(point("a",1f)); tags["equipRef"]=Ref("other")
    verifyEq(SeedMeterRollup.calculate(equips,[point("root",0f),Etc.makeDict(tags)])["root"]["status"],"invalidPoint")
    out:=SeedMeterRollup.calculate([equip("root","a"),equip("a","root")],[point("root",0f),point("a",1f)])
    verifyEq(out["root"]["status"],"cycle"); verifyEq(out["a"]["status"],"cycle")
  }

  Void testCanonicalAliasesAndSensorsDoNotDoubleCount()
  {
    alias:=Etc.dictToMap(equip("alias","root")); alias["seedCanonicalRef"]=Ref("a")
    sensor:=Etc.dictToMap(equip("sensor","root")); sensor["seedKind"]="sensor"
    out:=SeedMeterRollup.calculate([equip("root"),equip("a","root"),Etc.makeDict(alias),Etc.makeDict(sensor)],
      [point("root",100f),point("a",5f),point("alias",5f),point("sensor",10f)])
    verifyEq(out["root"]["val"],Number(5f,Unit("m³")))
  }

  Void testRelationshipChangesUseFreshGraph()
  {
    points:=[point("root",0f),point("floor",0f),point("a",5f)]
    verifyEq(SeedMeterRollup.calculate([equip("root"),equip("floor","root"),equip("a","floor")],points)["root"]["val"],Number(5f,Unit("m³")))
    verifyEq(SeedMeterRollup.calculate([equip("root"),equip("floor","root"),equip("a","root")],points)["root"]["val"],Number(5f,Unit("m³")))
    verify(SeedMeterRollup.calculate([equip("root"),equip("floor"),equip("a")],points).isEmpty)
  }

  private Dict equip(Str id, Str? parent:=null)
  {
    tags:=Str:Obj?["id":Ref(id),"equip":Marker.val,"seed":Marker.val,"seedKind":"meter","seedAutoSum":true,"seedPointRef":Ref(id+"-p"),"seedCategoryRef":Ref("water")]
    if (parent != null) tags["seedMeterParentRef"]=Ref(parent)
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
    dir:=Env.cur.tempDir+`finseed-rollup-test-${Uuid()}/`; dir.create
    db:=(Folio)Type.find("hxFolio::HxFolio").method("open").call(FolioConfig { name="seedRollupTest";it.dir=dir;log=Log.get("seedRollupTest") })
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

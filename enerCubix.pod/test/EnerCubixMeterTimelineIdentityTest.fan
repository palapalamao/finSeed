using haystack
using folio
using util

class EnerCubixMeterTimelineIdentityTest : Test
{
  Void testInitialConfigurationUsesTheCommittedProjectIdentity()
  {
    withDb("p:epochIdentity:r:") |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z")
      changes:=[add("profile","cleaningProfile"),add("cat","category"),add("expression","expression")]
      changes.add(Diff.makeAdd(Etc.makeDict(["equip":Marker.val,"enerCubix":Marker.val,"enerCubixKind":"meter","dis":"meter","enerCubixCleaningEnabled":Marker.val,"enerCubixCleaningProfileRef":Ref("profile"),"enerCubixCategoryRef":Ref("cat"),"enerCubixExpressionRef":Ref("expression"),"enerCubixPointRef":Ref("meter-p")]),Ref("meter")))
      changes.addAll(EnerCubixMeterTimeline.capture(db,changes,at)); db.commitAll(changes)
      records:=EnerCubixMeterTimeline.recordsAt(db,at)
      ["profile","cat","expression","meter"].each |key|
      {
        expected:=db.readById(Ref(key)).id.id
        verifyEq(records.findAll |r| {r["id"]==expected}.size,1,key)
      }
      meter:=records.find |r| {r["kind"]=="meter"}
      verifyEq(meter["cleaningProfileId"],"p:epochIdentity:r:profile")
      verifyEq(meter["categoryId"],"p:epochIdentity:r:cat")
      verifyEq(meter["expressionId"],"p:epochIdentity:r:expression")
      verifyEq(meter["pointId"],"p:epochIdentity:r:meter-p")
      verifyEq(((Map)records.find |r| {r["kind"]=="expression"}["variables"])["a"],"p:epochIdentity:r:meter")
      stored:=db.readAllList(Filter.has("enerCubixMeterEpoch"))
      stored.each |epoch|
      {
        cfg:=(Map)JsonInStream(epoch["enerCubixEpochConfig"].toStr.in).readJson
        verifyEq(cfg["id"],((Ref)epoch["enerCubixRecordRef"]).id)
      }
    }
  }

  Void testLegacyLocalIdsAreReadWithoutRewritingEpochs()
  {
    withDb("p:epochIdentity:r:") |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z")
      EnerCubixMeterTimeline.initialize(db,at)
      configs:=[Str:Obj?][["id":"profile","kind":"cleaningProfile","version":1,"parameters":["deltaMax":5]],
        ["id":"expression","kind":"expression","variables":["a":"meter","foreign":"p:elsewhere:r:other"],"formula":"a"],
        ["id":"meter","kind":"meter","pointId":"meter-p","categoryId":"cat","cleaningProfileId":"profile","expressionId":"expression"]]
      configs.add(["id":"virtual","kind":"meter","expressionId":"expression","historyPointId":EnerCubixMeterHistory.formulaId(Ref("virtual")).id])
      originals:=Str:Str[:]
      configs.each |cfg|
      {
        text:=JsonOutStream.writeJsonToStr(cfg)
        epoch:=db.commit(Diff.makeAdd(Etc.makeDict(["enerCubixMeterEpoch":Marker.val,"enerCubixRecordRef":Ref(cfg["id"].toStr),"enerCubixEffectiveFrom":at,"enerCubixEpochSequence":Number(1),"enerCubixEpochConfig":text]))).newRec
        originals[epoch.id.id]=text
      }
      rows:=EnerCubixMeterTimeline.recordsAt(db,at)
      profile:=rows.find |r| {r["kind"]=="cleaningProfile"}
      verifyEq(profile["id"],"p:epochIdentity:r:profile"); verifyEq(profile["version"],1)
      meter:=rows.find |r| {r["pointId"] != null}
      verifyEq(meter["cleaningProfileId"],profile["id"])
      verifyEq(meter["pointId"],"p:epochIdentity:r:meter-p")
      expression:=rows.find |r| {r["kind"]=="expression"}; vars:=(Map)expression["variables"]
      verifyEq(vars["a"],"p:epochIdentity:r:meter");verifyEq(vars["foreign"],"p:elsewhere:r:other")
      virtualConfig:=rows.find |r| {r["id"]=="p:epochIdentity:r:virtual"}
      verifyEq(virtualConfig["historyPointId"],"p:epochIdentity:r:enerCubix-formula-"+"p:epochIdentity:r:virtual".toBuf.toDigest("SHA-256").toHex[0..<24])
      later:=profile.dup.set("version",2).set("parameters",["deltaMax":1000])
      db.commit(Diff.makeAdd(Etc.makeDict(["enerCubixMeterEpoch":Marker.val,"enerCubixRecordRef":Ref("profile"),"enerCubixEffectiveFrom":at+1min,"enerCubixEpochSequence":Number(2),"enerCubixEpochConfig":JsonOutStream.writeJsonToStr(later)])))
      before:=EnerCubixMeterTimeline.recordsAt(db,at+30sec).find |r| {r["kind"]=="cleaningProfile"}
      after:=EnerCubixMeterTimeline.recordsAt(db,at+90sec).findAll |r| {r["kind"]=="cleaningProfile"}
      verifyEq(((Map)before["parameters"])["deltaMax"],5);verifyEq(after.size,1);verifyEq(after.first["version"],2)
      originals.each |text,id| {verifyEq(db.readById(Ref(id))["enerCubixEpochConfig"],text)}
    }
  }

  Void testLocalIdsRemainValidInAnUnprefixedFolio()
  {
    withDb(null) |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z"); changes:=[add("profile","cleaningProfile")]
      changes.addAll(EnerCubixMeterTimeline.capture(db,changes,at)); db.commitAll(changes)
      verifyEq(EnerCubixMeterTimeline.recordsAt(db,at).first["id"],"profile")
    }
  }

  Void testNewProfileIsAvailableToFirstMinuteGeneration()
  {
    withDb("p:epochIdentity:r:") |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z")
      db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","kind":"Number","tz":"UTC","equipRef":Ref("meter")]),Ref("meter-p")))
      changes:=[add("profile","cleaningProfile"),add("cat","category")]
      changes.add(Diff.makeAdd(Etc.makeDict(["equip":Marker.val,"enerCubix":Marker.val,"enerCubixKind":"meter","dis":"meter","enerCubixCleaningEnabled":Marker.val,"enerCubixCleaningProfileRef":Ref("profile"),"enerCubixCategoryRef":Ref("cat"),"enerCubixPointRef":Ref("meter-p"),"enerCubixAutoSum":false]),Ref("meter")))
      changes.addAll(EnerCubixMeterTimeline.capture(db,changes,at));db.commitAll(changes)
      raw:=[HisItem(at,Number(100,Unit("kWh"))),HisItem(at+30sec,Number(107,Unit("kWh"))),HisItem(at+1min,Number(110,Unit("kWh")))]
      db.his.write(Ref("meter-p"),raw,null).get(30sec)
      EnerCubixMeterGeneration.update(db,at);EnerCubixMeterGeneration.update(db,at+3min)
      verifyNull(EnerCubixMeterHistory.loadDb(db,db.readById(Ref("meter-p")),at,at+2min))
      verifyNull(db.readById(EnerCubixMeterHistory.stateId(db.readById(Ref("meter-p")).id),false))
      samples:=HisItem[,];db.his.read(db.readById(Ref("meter-p")).id,null,null) |item| {samples.add(item)}
      verifyEq(samples.size,raw.size)

    }
  }

  Void testProjectFormulaGenerationUsesTheStoredPointIdentity()
  {
    withDb("p:epochIdentity:r:") |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z")
      db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","kind":"Number","tz":"UTC","equipRef":Ref("meter")]),Ref("meter-p")))
      changes:=[add("profile","cleaningProfile"),add("cat","category"),add("expression","expression")]
      changes.add(Diff.makeAdd(Etc.makeDict(["equip":Marker.val,"enerCubix":Marker.val,"enerCubixKind":"meter","dis":"meter","enerCubixCleaningEnabled":Marker.val,"enerCubixCleaningProfileRef":Ref("profile"),"enerCubixCategoryRef":Ref("cat"),"enerCubixPointRef":Ref("meter-p"),"enerCubixAutoSum":false]),Ref("meter")))
      changes.add(Diff.makeAdd(Etc.makeDict(["equip":Marker.val,"enerCubix":Marker.val,"enerCubixVirtual":Marker.val,"enerCubixKind":"meter","dis":"virtual","enerCubixExpressionRef":Ref("expression"),"enerCubixCategoryRef":Ref("cat"),"enerCubixAutoSum":false]),Ref("virtual")))
      changes.addAll(EnerCubixMeterTimeline.capture(db,changes,at));db.commitAll(changes)
      db.his.write(Ref("meter-p"),[HisItem(at,Number(100,Unit("kWh"))),HisItem(at+30sec,Number(107,Unit("kWh"))),HisItem(at+1min,Number(110,Unit("kWh")))],null).get(30sec)
      EnerCubixMeterGeneration.update(db,at);EnerCubixMeterGeneration.update(db,at+3min)
      verifyNull(db.readById(EnerCubixMeterHistory.formulaId(db.readById(Ref("virtual")).id),false))
      verifyNull(EnerCubixNativeEquip.decode(db.readById(Ref("virtual")))["pointId"])

    }
  }

  private Diff add(Str id,Str kind)
  {
    cfg:=Str:Obj?["kind":kind,"name":id,"version":1]
    if(kind=="category")cfg["unit"]="kWh"
    if(kind=="cleaningProfile"){cfg["mode"]="drop";cfg["parameters"]=["deltaMin":0,"deltaMax":1000,"timeMax":"1h","defNull":true]}
    if(kind=="expression"){cfg["formula"]="a";cfg["variables"]=["a":"meter"]}
    return Diff.makeAdd(Etc.makeDict(["enerCubix":Marker.val,"enerCubixKind":kind,"dis":id,"enerCubixConfig":JsonOutStream.writeJsonToStr(cfg)]),Ref(id))
  }
  private Void withDb(Str? prefix,|Folio| work)
  {
    dir:=Env.cur.tempDir+`enerCubix-epoch-identity-${Uuid()}/`;dir.create
    db:=(Folio)Type.find("hxFolio::HxFolio").method("open").call(FolioConfig {name="epochIdentity";it.dir=dir;idPrefix=prefix;log=Log.get("epochIdentity")})
    try{work(db)}finally{db.close;dir.delete}
  }
}

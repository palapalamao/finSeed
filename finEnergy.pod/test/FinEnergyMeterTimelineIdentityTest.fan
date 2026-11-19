using haystack
using folio
using util

class FinEnergyMeterTimelineIdentityTest : Test
{
  Void testInitialConfigurationUsesTheCommittedProjectIdentity()
  {
    withDb("p:epochIdentity:r:") |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z")
      changes:=[add("profile","cleaningProfile"),add("cat","category"),add("expression","expression")]
      changes.add(Diff.makeAdd(Etc.makeDict(["equip":Marker.val,"finEnergy":Marker.val,"finEnergyKind":"meter","dis":"meter","finEnergyCleaningEnabled":Marker.val,"finEnergyCleaningProfileRef":Ref("profile"),"finEnergyCategoryRef":Ref("cat"),"finEnergyExpressionRef":Ref("expression"),"finEnergyPointRef":Ref("meter-p")]),Ref("meter")))
      changes.addAll(FinEnergyMeterTimeline.capture(db,changes,at)); db.commitAll(changes)
      records:=FinEnergyMeterTimeline.recordsAt(db,at)
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
      stored:=db.readAllList(Filter.has("finEnergyMeterEpoch"))
      stored.each |epoch|
      {
        cfg:=(Map)JsonInStream(epoch["finEnergyEpochConfig"].toStr.in).readJson
        verifyEq(cfg["id"],((Ref)epoch["finEnergyRecordRef"]).id)
      }
    }
  }

  Void testLegacyLocalIdsAreReadWithoutRewritingEpochs()
  {
    withDb("p:epochIdentity:r:") |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z")
      FinEnergyMeterTimeline.initialize(db,at)
      configs:=[Str:Obj?][["id":"profile","kind":"cleaningProfile","version":1,"parameters":["deltaMax":5]],
        ["id":"expression","kind":"expression","variables":["a":"meter","foreign":"p:elsewhere:r:other"],"formula":"a"],
        ["id":"meter","kind":"meter","pointId":"meter-p","categoryId":"cat","cleaningProfileId":"profile","expressionId":"expression"]]
      configs.add(["id":"virtual","kind":"meter","expressionId":"expression","historyPointId":FinEnergyMeterHistory.formulaId(Ref("virtual")).id])
      originals:=Str:Str[:]
      configs.each |cfg|
      {
        text:=JsonOutStream.writeJsonToStr(cfg)
        epoch:=db.commit(Diff.makeAdd(Etc.makeDict(["finEnergyMeterEpoch":Marker.val,"finEnergyRecordRef":Ref(cfg["id"].toStr),"finEnergyEffectiveFrom":at,"finEnergyEpochSequence":Number(1),"finEnergyEpochConfig":text]))).newRec
        originals[epoch.id.id]=text
      }
      rows:=FinEnergyMeterTimeline.recordsAt(db,at)
      profile:=rows.find |r| {r["kind"]=="cleaningProfile"}
      verifyEq(profile["id"],"p:epochIdentity:r:profile"); verifyEq(profile["version"],1)
      meter:=rows.find |r| {r["pointId"] != null}
      verifyEq(meter["cleaningProfileId"],profile["id"])
      verifyEq(meter["pointId"],"p:epochIdentity:r:meter-p")
      expression:=rows.find |r| {r["kind"]=="expression"}; vars:=(Map)expression["variables"]
      verifyEq(vars["a"],"p:epochIdentity:r:meter");verifyEq(vars["foreign"],"p:elsewhere:r:other")
      virtualConfig:=rows.find |r| {r["id"]=="p:epochIdentity:r:virtual"}
      verifyEq(virtualConfig["historyPointId"],"p:epochIdentity:r:finEnergy-formula-"+"p:epochIdentity:r:virtual".toBuf.toDigest("SHA-256").toHex[0..<24])
      later:=profile.dup.set("version",2).set("parameters",["deltaMax":1000])
      db.commit(Diff.makeAdd(Etc.makeDict(["finEnergyMeterEpoch":Marker.val,"finEnergyRecordRef":Ref("profile"),"finEnergyEffectiveFrom":at+1min,"finEnergyEpochSequence":Number(2),"finEnergyEpochConfig":JsonOutStream.writeJsonToStr(later)])))
      before:=FinEnergyMeterTimeline.recordsAt(db,at+30sec).find |r| {r["kind"]=="cleaningProfile"}
      after:=FinEnergyMeterTimeline.recordsAt(db,at+90sec).findAll |r| {r["kind"]=="cleaningProfile"}
      verifyEq(((Map)before["parameters"])["deltaMax"],5);verifyEq(after.size,1);verifyEq(after.first["version"],2)
      originals.each |text,id| {verifyEq(db.readById(Ref(id))["finEnergyEpochConfig"],text)}
    }
  }

  Void testLocalIdsRemainValidInAnUnprefixedFolio()
  {
    withDb(null) |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z"); changes:=[add("profile","cleaningProfile")]
      changes.addAll(FinEnergyMeterTimeline.capture(db,changes,at)); db.commitAll(changes)
      verifyEq(FinEnergyMeterTimeline.recordsAt(db,at).first["id"],"profile")
    }
  }

  Void testNewProfileIsAvailableToFirstMinuteGeneration()
  {
    withDb("p:epochIdentity:r:") |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z")
      db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","kind":"Number","tz":"UTC","equipRef":Ref("meter")]),Ref("meter-p")))
      changes:=[add("profile","cleaningProfile"),add("cat","category")]
      changes.add(Diff.makeAdd(Etc.makeDict(["equip":Marker.val,"finEnergy":Marker.val,"finEnergyKind":"meter","dis":"meter","finEnergyCleaningEnabled":Marker.val,"finEnergyCleaningProfileRef":Ref("profile"),"finEnergyCategoryRef":Ref("cat"),"finEnergyPointRef":Ref("meter-p"),"finEnergyAutoSum":false]),Ref("meter")))
      changes.addAll(FinEnergyMeterTimeline.capture(db,changes,at));db.commitAll(changes)
      raw:=[HisItem(at,Number(100,Unit("kWh"))),HisItem(at+30sec,Number(107,Unit("kWh"))),HisItem(at+1min,Number(110,Unit("kWh")))]
      db.his.write(Ref("meter-p"),raw,null).get(30sec)
      FinEnergyMeterGeneration.update(db,at);FinEnergyMeterGeneration.update(db,at+3min)
      verifyNull(FinEnergyMeterHistory.loadDb(db,db.readById(Ref("meter-p")),at,at+2min))
      verifyNull(db.readById(FinEnergyMeterHistory.stateId(db.readById(Ref("meter-p")).id),false))
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
      changes.add(Diff.makeAdd(Etc.makeDict(["equip":Marker.val,"finEnergy":Marker.val,"finEnergyKind":"meter","dis":"meter","finEnergyCleaningEnabled":Marker.val,"finEnergyCleaningProfileRef":Ref("profile"),"finEnergyCategoryRef":Ref("cat"),"finEnergyPointRef":Ref("meter-p"),"finEnergyAutoSum":false]),Ref("meter")))
      changes.add(Diff.makeAdd(Etc.makeDict(["equip":Marker.val,"finEnergy":Marker.val,"finEnergyVirtual":Marker.val,"finEnergyKind":"meter","dis":"virtual","finEnergyExpressionRef":Ref("expression"),"finEnergyCategoryRef":Ref("cat"),"finEnergyAutoSum":false]),Ref("virtual")))
      changes.addAll(FinEnergyMeterTimeline.capture(db,changes,at));db.commitAll(changes)
      db.his.write(Ref("meter-p"),[HisItem(at,Number(100,Unit("kWh"))),HisItem(at+30sec,Number(107,Unit("kWh"))),HisItem(at+1min,Number(110,Unit("kWh")))],null).get(30sec)
      FinEnergyMeterGeneration.update(db,at);FinEnergyMeterGeneration.update(db,at+3min)
      verifyNull(db.readById(FinEnergyMeterHistory.formulaId(db.readById(Ref("virtual")).id),false))
      verifyNull(FinEnergyNativeEquip.decode(db.readById(Ref("virtual")))["pointId"])

    }
  }

  private Diff add(Str id,Str kind)
  {
    cfg:=Str:Obj?["kind":kind,"name":id,"version":1]
    if(kind=="category")cfg["unit"]="kWh"
    if(kind=="cleaningProfile"){cfg["mode"]="drop";cfg["parameters"]=["deltaMin":0,"deltaMax":1000,"timeMax":"1h","defNull":true]}
    if(kind=="expression"){cfg["formula"]="a";cfg["variables"]=["a":"meter"]}
    return Diff.makeAdd(Etc.makeDict(["finEnergy":Marker.val,"finEnergyKind":kind,"dis":id,"finEnergyConfig":JsonOutStream.writeJsonToStr(cfg)]),Ref(id))
  }
  private Void withDb(Str? prefix,|Folio| work)
  {
    dir:=Env.cur.tempDir+`finEnergy-epoch-identity-${Uuid()}/`;dir.create
    db:=(Folio)Type.find("hxFolio::HxFolio").method("open").call(FolioConfig {name="epochIdentity";it.dir=dir;idPrefix=prefix;log=Log.get("epochIdentity")})
    try{work(db)}finally{db.close;dir.delete}
  }
}

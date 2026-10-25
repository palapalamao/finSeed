using haystack
using folio
using util

class EnerCubixChangeMessagesTest : Test
{
  Void testRelationshipBeforeAfterAndInitialSnapshot()
  {
    withDb |db|
    {
      add(db,"old"); add(db,"new"); add(db,"meter",["meterParentId":"old"])
      EnerCubixMeterTimeline.initialize(db,at)
      verifyEq(page(db)["total"],0)
      commit(db,"meter",["meterParentId":"new"],at+1min)
      result:=items(page(db)); verifyEq(result.size,1)
      message:=result.first
      verifyEq(message["action"],"updated"); verifyEq(message["category"],"relationship")
      verifyEq(message["objectId"],"meter"); verifyEq(message["objectName"],"meter")
      delta:=items(message,"changes").first
      verifyEq(delta,Str:Obj?["field":"meterParentId","before":"old","after":"new"])
      verifyFalse(message.containsKey("actor"))
      commit(db,"meter",["meterParentId":"new"],at+2min)
      verifyEq(page(db)["total"],1)
    }
  }

  Void testCreationDeletionAndStablePaging()
  {
    withDb |db|
    {
      EnerCubixMeterTimeline.initialize(db,at)
      changes:=[Diff.makeAdd(tags("a",["autoSum":true]),Ref("a")),Diff.makeAdd(tags("b",["autoSum":true]),Ref("b"))]
      changes.addAll(EnerCubixMeterTimeline.capture(db,changes,at+1min)); db.commitAll(changes)
      removal:=[Diff(db.readById(Ref("a")),null,Diff.remove)]
      removal.addAll(EnerCubixMeterTimeline.capture(db,removal,at+2min)); db.commitAll(removal)
      all:=items(page(db)); verifyEq(all.size,3)
      verifyEq(all.first["action"],"deleted"); verifyEq(all.first["objectId"],"a")
      verifyEq(all.last["action"],"created")
      first:=page(db,true,Str[,],0,1); second:=page(db,true,Str[,],1,1)
      verifyEq(first["total"],3); verifyEq(first["offset"],0); verifyEq(first["limit"],1)
      verifyEq(items(first).first,all[0]); verifyEq(items(second).first,all[1])
      verifyEq(items(page(db,true,Str[,],100,30)).size,0)
      verifyEq(page(db,false)["total"],1) // Missing/deleted objects are admin only.
    }
  }

  Void testCurrentObjectPermissionAndOldReferenceRedaction()
  {
    withDb |db|
    {
      add(db,"hidden"); add(db,"visible"); add(db,"meter",["meterParentId":"hidden"])
      EnerCubixMeterTimeline.initialize(db,at)
      commit(db,"meter",["meterParentId":"visible","maximum":25],at+1min)
      verifyEq(page(db,true,["meter"])["total"],0)
      msg:=items(page(db,false,["hidden"])).first
      verifyEq(msg["detailsRestricted"],true)
      verifyEq(items(msg,"changes").map |c->Str| { c["field"].toStr },["maximum"])
      verifyFalse(JsonOutStream.writeJsonToStr(msg).contains("hidden"))
    }
  }

  Void testNestedVariablesAndSensitiveKeysAreNotExposed()
  {
    withDb |db|
    {
      add(db,"hidden"); add(db,"visible")
      add(db,"formula",["variables":["x":"hidden"],"formula":"x","password":"secret-old"],"expression")
      add(db,"profile",["parameters":["deltaMin":0,"password":"secret-old"]],"cleaningProfile")
      EnerCubixMeterTimeline.initialize(db,at)
      commit(db,"formula",["variables":["x":["pointId":"hidden","name":"Hidden name"]],"formula":"x+1","password":"secret-new"],at+1min)
      commit(db,"profile",["parameters":["deltaMin":2,"password":"secret-new","token":"private"]],at+2min)
      all:=items(page(db,false,["hidden"])); verifyEq(all.size,2)
      text:=JsonOutStream.writeJsonToStr(all)
      verifyFalse(text.contains("secret")); verifyFalse(text.contains("password")); verifyFalse(text.contains("private")); verifyFalse(text.contains("Hidden name")); verifyFalse(text.contains("hidden"))
      formula:=all.find |m| { m["objectId"] == "formula" }
      verifyEq(formula["detailsRestricted"],true)
      verifyEq(items(formula,"changes").map |c->Str| { c["field"].toStr },["formula"])
      params:=items(all.first,"changes").first
      verifyEq(params["before"],Str:Obj?["deltaMin":0]); verifyEq(params["after"],Str:Obj?["deltaMin":2])
    }
  }

  Void testCorruptEpochDoesNotInventChangeOrBreakPage()
  {
    withDb |db|
    {
      add(db,"meter",["maximum":1]); EnerCubixMeterTimeline.initialize(db,at)
      db.commit(Diff.makeAdd(Etc.makeDict(["enerCubixMeterEpoch":Marker.val,"enerCubixRecordRef":Ref("meter"),"enerCubixEffectiveFrom":at+1min,"enerCubixEpochSequence":Number(2),"enerCubixEpochConfig":"broken"])))
      commit(db,"meter",["maximum":3],at+2min)
      // A damaged predecessor makes this object's next old value unknown.
      verifyEq(page(db)["total"],0)
      commit(db,"meter",["maximum":4],at+3min)
      verifyEq(page(db)["total"],1)
      verifyEq(items(items(page(db)).first,"changes").first["before"],3)
    }
  }

  Void testActorIsAuditMetadataAndSensitiveOnlyEditIsNotMessage()
  {
    withDb |db|
    {
      add(db,"meter",["maximum":1,"password":"old"])
      baseline:=EnerCubixMeterTimeline.capture(db,Diff[,],at,"initializer")
      db.commitAll(baseline)
      verifyEq(page(db)["total"],0)
      record:=db.readById(Ref("meter"))
      changes:=[Diff(record,Etc.makeDict(["enerCubixConfig":"{\"maximum\":2,\"password\":\"old\"}"]))]
      changes.addAll(EnerCubixMeterTimeline.capture(db,changes,at+1min,"operator")); db.commitAll(changes)
      message:=items(page(db)).first
      verifyEq(message["actor"],"operator")
      verifyFalse(JsonOutStream.writeJsonToStr(EnerCubixMeterTimeline.current(db)).contains("operator"))
      commit(db,"meter",["password":"new","token":"secret"],at+2min)
      verifyEq(page(db)["total"],1)
    }
  }

  Void testParameterReferenceShapeIsRestrictedAndAlarmReferencesAreChecked()
  {
    withDb |db|
    {
      add(db,"hidden"); add(db,"visible")
      add(db,"profile",["parameters":["deltaMin":0]],"cleaningProfile")
      add(db,"meter",["alarmLimits":[["categoryId":"hidden","limit":1]]])
      EnerCubixMeterTimeline.initialize(db,at)
      commit(db,"profile",["parameters":["deltaMin":["type":"ref","value":"hidden","name":"Hidden name"]]],at+1min)
      commit(db,"meter",["alarmLimits":[["categoryId":"visible","limit":2]]],at+2min)
      all:=items(page(db,false,["hidden"])); verifyEq(all.size,2)
      verify(all.all |m| { m["detailsRestricted"] == true && items(m,"changes").isEmpty })
      verifyFalse(JsonOutStream.writeJsonToStr(all).contains("hidden"))
      verifyErr(ArgErr#) { page(db,true,Str[,],-1) }
      verifyErr(ArgErr#) { page(db,true,Str[,],0,201) }
    }
  }

  Void testNullSnapshotCannotBecomeDeletionAndReadDoesNotWrite()
  {
    withDb |db|
    {
      add(db,"meter",["maximum":1]); EnerCubixMeterTimeline.initialize(db,at)
      db.commit(Diff.makeAdd(Etc.makeDict(["enerCubixMeterEpoch":Marker.val,"enerCubixRecordRef":Ref("meter"),"enerCubixEffectiveFrom":at+1min,"enerCubixEpochSequence":Number(2),"enerCubixEpochConfig":"null"])))
      before:=db.readAllList(Filter.has("enerCubixMeterEpoch")).size
      verifyEq(page(db)["total"],0)
      verifyEq(db.readAllList(Filter.has("enerCubixMeterEpoch")).size,before)
    }
    withDb |db|
    {
      verifyEq(page(db)["total"],0)
      verifyNull(db.readById(EnerCubixMeterTimeline.key,false))
    }
  }

  private static const DateTime at:=DateTime.fromIso("2026-10-26T01:00:00Z")
  private [Str:Obj?] page(Folio db, Bool admin:=true, Str[] hidden:=Str[,], Int offset:=0, Int limit:=30)
  { EnerCubixChangeMessages.page(db,|Dict r->Bool| { !hidden.contains(r.id.id) },admin,offset,limit) }
  private [Str:Obj?][] items([Str:Obj?] result, Str key:="items") { EnerCubixMath.maps(result[key]) }
  private Dict tags(Str name, [Str:Obj?] extra:=Str:Obj?[:], Str kind:="meter")
  { Etc.makeDict(["enerCubix":Marker.val,"enerCubixKind":kind,"dis":name,"enerCubixConfig":JsonOutStream.writeJsonToStr(extra)]) }
  private Void add(Folio db, Str id, [Str:Obj?] config:=Str:Obj?[:], Str kind:="meter") { db.commit(Diff.makeAdd(tags(id,config,kind),Ref(id))) }
  private Void commit(Folio db, Str id, [Str:Obj?] patch, DateTime ts)
  {
    record:=db.readById(Ref(id)); config:=EnerCubixRepo.decode(record).dup.setAll(patch)
    // Mimic Repo.encode for first-class reference tags.
    changed:=Str:Obj?["enerCubixConfig":JsonOutStream.writeJsonToStr(config)]
    EnerCubixRepo.refTags.each |tag,key| { if (patch.containsKey(key)) changed[tag]=patch[key] == null ? Remove.val : Ref(patch[key].toStr) }
    changes:=[Diff(record,Etc.makeDict(changed))]
    changes.addAll(EnerCubixMeterTimeline.capture(db,changes,ts)); db.commitAll(changes)
  }
  private Void withDb(|Folio| work)
  {
    dir:=Env.cur.tempDir+`enerCubix-changes-test-${Uuid()}/`; dir.create
    db:=(Folio)Type.find("hxFolio::HxFolio").method("open").call(FolioConfig {name="changeMessagesTest";it.dir=dir;log=Log.get("changeMessagesTest")})
    try {work(db)} finally {db.close; dir.delete}
  }
}

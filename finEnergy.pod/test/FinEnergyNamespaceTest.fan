using haystack
using util
using alarmExt
using folio
using folio3

class FinEnergyNamespaceTest : Test
{
  Void testAlarmRetainsStateAcknowledgementAndTimes()
  {
    occurred:=DateTime.now-1hr
    acked:=occurred+1min
    original:=Etc.makeDict(["id":Ref("alarm-1"),"state":"offNormal","priority":Number(50),"occurred":occurred,
      "active":Marker.val,"created":occurred+1sec,"sourceRef":Ref("point-1"),"acked":acked,"ackedBy":"operator",
      "ackMessage":"prior business text","ackRequired":Marker.val,"dispatcher":"rule",
      "metadata":Etc.makeDict(["formerEnergyAlarm":Marker.val,"formerEventRef":Ref("event-1")])])
    updated:=FinEnergyNamespace.alarmChange(original,"former","finEnergy")
    verifyEq(updated.id,original.id)
    verifyEq(updated.state,"offNormal"); verify(updated.active)
    verifyEq(updated.priority,Number(50)); verifyEq(updated.occurred,occurred)
    verifyEq(updated.created,occurred+1sec); verifyEq(updated.sourceRef,Ref("point-1"))
    verifyEq(updated.acked,acked); verifyEq(updated.ackedBy,"operator")
    verifyEq(updated.ackMessage,"prior business text"); verify(updated.ackRequired)
    verifyEq(updated.metadata["finEnergyEventRef"],Ref("event-1"))
    verify(!updated.metadata.has("formerEventRef"))
    verifyEq(FinEnergyNamespace.alarmChange(updated,"former","finEnergy"),null)
  }

  Void testTagsAndNestedMetadataKeepIdentityAndBusinessText()
  {
    source:=Ref("source-point")
    record:=Etc.makeDict(["id":Ref("record-1"),"dis":"prior shop","prior":Marker.val,"priorKind":"meter","priorPointRef":source,
      "priorConfig":"{\"name\":\"prior shop\",\"snapshot\":{\"id\":\"original\",\"priorKind\":\"meter\",\"priorPointRef\":\"source-point\"}}",
      "metadata":Etc.makeDict(["priorEventRef":Ref("event-1"),"priorEnergyAlarm":Marker.val])])
    changes:=FinEnergyNamespace.changes(record,"prior","finEnergy")
    verifyEq(changes["prior"],Remove.val)
    verifyEq(changes["finEnergy"],Marker.val)
    verifyEq(changes["finEnergyPointRef"],source)
    verify(!changes.has("id")); verify(!changes.has("dis"))
    config:=(Map)JsonInStream(changes["finEnergyConfig"].toStr.in).readJson
    verifyEq(config["name"],"prior shop")
    snapshot:=(Map)config["snapshot"]
    verifyEq(snapshot["id"],"original")
    verifyEq(snapshot["finEnergyKind"],"meter")
    verify(!snapshot.containsKey("priorKind"))
    meta:=(Dict)changes["metadata"]
    verifyEq(meta["finEnergyEventRef"],Ref("event-1"))
    verify(!meta.has("priorEventRef"))
  }

  Void testConflictFailsBeforeAnyWriteAndRepeatIsEmpty()
  {
    conflict:=Etc.makeDict(["priorKind":"meter","finEnergyKind":"sensor"])
    verifyErr(ArgErr#) { FinEnergyNamespace.changes(conflict,"prior","finEnergy") }
    verifyEq(conflict["priorKind"],"meter")
    verifyEq(FinEnergyNamespace.changes(Etc.makeDict(["finEnergyKind":"meter"]),"prior","finEnergy").isEmpty,true)
    schedule:=FinEnergyNamespace.changes(Etc.makeDict(["jobExpr":"priorScheduled()"]),"prior","finEnergy")
    verifyEq(schedule["jobExpr"],"finEnergyScheduled()")
    custom:=Etc.makeDict(["jobExpr":"customJob(\"enerCubixMeter\")"])
    verify(FinEnergyNamespace.changes(custom,"enerCubix","finEnergy").isEmpty)
  }

  Void testCleanHistoryAndEveryOwnedSnapshotNamespace()
  {
    prior:=Etc.makeDict(["id":Ref("enerCubix-owned-id"),"hisFunc":"enerCubixCleanHis",
      "enerCubixCleaningApplied":Etc.makeDict(["hisFunc":"enerCubixCleanHis","hisFuncConfig":Etc.makeDict(["enerCubixMode":"interval"])]),
      "enerCubixCleaningOriginal":Etc.makeDict(["hisFunc":"priorCustomerFunction"]),
      "enerCubixConfig":"{\"name\":\"enerCubix customer name\",\"nested\":{\"enerCubixMode\":\"counter\",\"hisFunc\":\"enerCubixCleanHis\"}}"])
    edits:=FinEnergyNamespace.changes(prior,"enerCubix","finEnergy")
    verifyEq(edits["hisFunc"],"finEnergyCleanHis")
    verify(!edits.has("id"))
    applied:=(Dict)edits["finEnergyCleaningApplied"]
    verifyEq(applied["hisFunc"],"finEnergyCleanHis")
    verifyEq(((Dict)applied["hisFuncConfig"])["finEnergyMode"],"interval")
    verifyEq(((Dict)edits["finEnergyCleaningOriginal"])["hisFunc"],"priorCustomerFunction")
    config:=(Map)JsonInStream(edits["finEnergyConfig"].toStr.in).readJson
    verifyEq(config["name"],"enerCubix customer name")
    verifyEq(((Map)config["nested"])["finEnergyMode"],"counter")
    verifyEq(((Map)config["nested"])["hisFunc"],"finEnergyCleanHis")
    verifyEq(FinEnergyNamespace.changes(Etc.makeDict(["enercubixKind":"meter"]),"enercubix","finEnergy")["finEnergyKind"],"meter")
  }

  Void testRollbackRetainsIdsAndRefusesLaterEdits()
  {
    before:=Etc.makeDict(["id":Ref("old-id"),"enerCubixKind":"meter","dis":"customer name","pointRef":Ref("raw-point")])
    after:=Etc.makeDict(["id":before.id,"finEnergyKind":"meter","dis":"customer name","pointRef":Ref("raw-point")])
    edits:=FinEnergyNamespace.safeRestore(after,before,after)
    verifyEq(edits["finEnergyKind"],Remove.val)
    verifyEq(edits["enerCubixKind"],"meter")
    verify(!edits.has("id"));verify(!edits.has("pointRef"));verify(!edits.has("dis"))
    verify(FinEnergyNamespace.safeRestore(before,before,after).isEmpty)
    later:=Etc.makeDict(["id":before.id,"finEnergyKind":"meter","dis":"changed later","pointRef":Ref("raw-point")])
    verify(!FinEnergyNamespace.safeRestore(later,before,after).has("dis"))
    changedOwned:=Etc.makeDict(["id":before.id,"finEnergyKind":"sensor","dis":"changed later","pointRef":Ref("raw-point")])
    verifyErr(ArgErr#) {FinEnergyNamespace.safeRestore(changedOwned,before,after)}
    verifyErr(ArgErr#) {FinEnergyNamespace.safeRestore(null,before,after)}
  }

  Void testMarkerLookupRetainsLegacySingletonId()
  {
    home:=Env.cur.tempDir+("finEnergy-namespace-"+Uuid()+"/").toUri
    db:=Folio3.open(FolioConfig {it.dir=home;it.idPrefix="p:test:r:"})
    try
    {
      db.commit(Diff.makeAdd(Etc.makeDict(["finEnergyRevision":Number(1)]),Ref("enerCubix-config-revision")))
      verifyEq(FinEnergyNamespace.singleton(db,"finEnergyRevision").id.id,"p:test:r:enerCubix-config-revision")
      db.commit(Diff.makeAdd(Etc.makeDict(["finEnergyRevision":Number(2)]),Ref("second-revision")))
      verifyErr(ArgErr#) {FinEnergyNamespace.singleton(db,"finEnergyRevision")}
    }
    finally {db.close}
  }

  Void testOwnedAssetPlanVerifiesHashesAndTargetCollision()
  {
    home:=Env.cur.tempDir+("finEnergy-namespace-assets-"+Uuid()+"/").toUri
    name:="0123456789abcdef0123456789abcdef.png"
    source:=home+("enerCubix-private/cockpit-assets/"+name).toUri
    source.parent.create;source.out.print("original asset bytes").close
    hash:=source.readAllBuf.toDigest("SHA-256").toHex
    record:=Etc.makeDict(["enerCubixCockpitAsset":Marker.val,"enerCubixAssetProjectRef":Ref("p:test"),"enerCubixAssetFile":name,"enerCubixAssetHash":hash])
    plan:=FinEnergyNamespace.assetPlan([record],home,Ref("p:test"),"enerCubix","finEnergy")
    verifyEq(plan.size,1);verifyEq(plan.first["hash"],hash);verifyEq(plan.first["created"],true)
    verifyEq(FinEnergyNamespace.assetPlan([record],home,Ref("p:other"),"enerCubix","finEnergy").size,0)
    target:=home+("finEnergy-private/cockpit-assets/"+name).toUri
    target.parent.create;target.out.print("conflicting bytes").close
    verifyErr(ArgErr#) {FinEnergyNamespace.assetPlan([record],home,Ref("p:test"),"enerCubix","finEnergy")}
    verifyEq(source.readAllStr,"original asset bytes")
  }

  Void testMigratedStoresRetainOldManifestAndContinuityIds()
  {
    home:=Env.cur.tempDir+("finEnergy-namespace-owned-"+Uuid()+"/").toUri
    db:=Folio3.open(FolioConfig {it.dir=home+`db/`;it.idPrefix="p:test:r:"})
    try
    {
      db.commitAll([
        Diff.makeAdd(Etc.makeDict(["finEnergyCockpitAssetManifest":Marker.val,"finEnergyAssetProjectRef":Ref("p:test"),"finEnergyAssetRefs":Ref[,]]),Ref("enerCubix-cockpit-assets")),
        Diff.makeAdd(Etc.makeDict(["finEnergyCockpitManifest":Marker.val,"ownedRefs":Ref[,],"version":Number(1)]),Ref("enerCubix-cockpit-owned-config")),
        Diff.makeAdd(Etc.makeDict(["finEnergyMeterTimeline":Marker.val,"finEnergyTimelineStart":DateTime.now]),Ref("enerCubix-meter-timeline")),
        Diff.makeAdd(Etc.makeDict(["finEnergyMeterContinuity":Marker.val,"finEnergyMainRef":Ref("p:test:r:point")]),Ref("enerCubix-continuity-legacy"))])
      assets:=FinEnergyCockpitAssets.withStore(db,home,Ref("p:test"),"test","admin",true,|Dict r->Bool| {true},|Dict r->Bool| {true})
      state:=assets.list
      assets.select(["id":null,"manifestMod":state["manifestMod"]])
      verifyEq(db.readCount(Filter.has("finEnergyCockpitAssetManifest")),1)
      verifyNotNull(db.readById(Ref("enerCubix-cockpit-assets"),false))
      verifyEq(db.readById(Ref("finEnergy-cockpit-assets"),false),null)
      store:=FinEnergyCockpitConfigStore(db,"test",Ref("p:test"),"admin",true)
      verifyEq(((List)store.list("budget")["records"]).size,0)
      FinEnergyMeterTimeline.initialize(db)
      verifyEq(db.readCount(Filter.has("finEnergyMeterTimeline")),1)
      verifyEq(FinEnergyMeterContinuity.stored(db,Ref("p:test:r:point")).id.id,"p:test:r:enerCubix-continuity-legacy")
    }
    finally {db.close}
  }

  Void testRollbackPreservesNativeValuesAndNewAlarmAcknowledgement()
  {
    prior:=Etc.makeDict(["id":Ref("point"),"enerCubixCleaningOwnerRef":Ref("owner"),"curVal":Number(10)])
    next:=Etc.makeDict(["id":prior.id,"finEnergyCleaningOwnerRef":Ref("owner"),"curVal":Number(10)])
    current:=Etc.makeDict(["id":prior.id,"finEnergyCleaningOwnerRef":Ref("owner"),"curVal":Number(25),"curStatus":"ok"])
    patch:=FinEnergyNamespace.safeRestore(current,prior,next)
    verify(!patch.has("curVal"));verify(!patch.has("curStatus"))
    verifyEq(patch["enerCubixCleaningOwnerRef"],Ref("owner"))
    alarmPrior:=Etc.makeDict(["id":Ref("alarm"),"enerCubixEventRef":Ref("event"),"state":"offNormal"])
    alarmNext:=Etc.makeDict(["id":Ref("alarm"),"finEnergyEventRef":Ref("event"),"state":"offNormal"])
    alarmCurrent:=Etc.makeDict(["id":Ref("alarm"),"finEnergyEventRef":Ref("event"),"state":"normal","ackedBy":"operator","acked":DateTime.now])
    restored:=FinEnergyNamespace.safeRestore(alarmCurrent,alarmPrior,alarmNext)
    verify(!restored.has("state"));verify(!restored.has("ackedBy"));verify(!restored.has("acked"))
  }

  Void testRollbackMergesNativeAlarmMetadataRecursively()
  {
    prior:=Etc.makeDict(["id":Ref("alarm"),"metadata":Etc.makeDict(["enerCubixEventRef":Ref("event"),"vendor":"kept"])])
    next:=Etc.makeDict(["id":prior.id,"metadata":Etc.makeDict(["finEnergyEventRef":Ref("event"),"vendor":"kept"])])
    current:=Etc.makeDict(["id":prior.id,"metadata":Etc.makeDict(["finEnergyEventRef":Ref("event"),"vendor":"updated later","nativeAudit":"new"])])
    patch:=FinEnergyNamespace.safeRestore(current,prior,next)
    meta:=(Dict)patch["metadata"]
    verifyEq(meta["enerCubixEventRef"],Ref("event"));verify(!meta.has("finEnergyEventRef"))
    verifyEq(meta["vendor"],"updated later");verifyEq(meta["nativeAudit"],"new")
  }

  Void testPostGraphRejectsDuplicateSchedulerSingletonAndContinuity()
  {
    verifyErr(ArgErr#) {FinEnergyNamespace.validateGraph([Etc.makeDict(["finEnergyRevision":Number(1)]),Etc.makeDict(["finEnergyRevision":Number(2)])],"finEnergy")}
    verifyErr(ArgErr#) {FinEnergyNamespace.validateGraph([Etc.makeDict(["jobExpr":"finEnergyScheduled()"]),Etc.makeDict(["jobExpr":"finEnergyScheduled()"])],"finEnergy")}
    continuity:=Etc.makeDict(["finEnergyMeterContinuity":Marker.val,"finEnergyMainRef":Ref("point")])
    verifyErr(ArgErr#) {FinEnergyNamespace.validateGraph([continuity,continuity],"finEnergy")}
  }

  Void testNativeEquipmentZincSnapshotsRemainRecoverable()
  {
    original:=Etc.makeDict(["id":Ref("archive"),"enerCubixKind":"meter","enerCubixPointRef":Ref("point"),"dis":"enerCubix customer label"])
    zinc:=ZincWriter.gridToStr(Etc.makeDictsGrid(null,[original]))
    json:=JsonOutStream.writeJsonToStr(["action":"nativeEquipSnapshot","snapshot":["type":"equip","id":"archive","before":zinc,"after":zinc,"afterBusiness":"{\"enerCubixMode\":\"counter\"}"]])
    edits:=FinEnergyNamespace.changes(Etc.makeDict(["enerCubixConfig":json]),"enerCubix","finEnergy")
    result:=(Map)JsonInStream(edits["finEnergyConfig"].toStr.in).readJson
    snap:=(Map)result["snapshot"]
    ["before","after"].each |key|
    {
      restored:=ZincReader(snap[key].toStr.in).readGrid.first
      verifyEq(restored.id,original.id);verifyEq(restored.dis,original.dis)
      verifyEq(restored["finEnergyPointRef"],Ref("point"));verify(!restored.has("enerCubixKind"))
    }
    verifyEq(((Map)JsonInStream(snap["afterBusiness"].toStr.in).readJson)["finEnergyMode"],"counter")
  }

  Void testArchiveRecoveryAcceptsOnlyNamespaceClockChange()
  {
    home:=Env.cur.tempDir+("finEnergy-namespace-archive-"+Uuid()+"/").toUri
    db:=Folio3.open(FolioConfig {it.dir=home;it.idPrefix="p:test:r:"})
    try
    {
      before:=db.commit(Diff.makeAdd(Etc.makeDict(["enerCubix":Marker.val,"enerCubixKind":"meter","dis":"customer","area":Number(120)]),Ref("legacy-archive"))).newRec
      patch:=FinEnergyNamespace.changes(before,"enerCubix","finEnergy")
      current:=db.commit(Diff(before,patch)).newRec
      saved:=ZincReader(ZincWriter.gridToStr(Etc.makeDictsGrid(null,[before])).in).readGrid.first
      edits:=FinEnergyNamespace.changes(saved,"enerCubix","finEnergy")
      tags:=Etc.dictToMap(saved)
      edits.each |v,k| {if(v == Remove.val) tags.remove(k);else tags[k]=v}
      snapshot:=Etc.makeDict(tags)
      verify(FinEnergyNativeEquipRepo.sameArchive(current,snapshot))
      changed:=db.commit(Diff(current,Etc.makeDict(["area":Number(200)]))).newRec
      verify(!FinEnergyNativeEquipRepo.sameArchive(changed,snapshot))
    }
    finally {db.close}
  }

  Void testPreviewFingerprintIgnoresLiveCollectionButProtectsOwnedEdits()
  {
    a:=Etc.makeDict(["id":Ref("point"),"mod":DateTime.now,"curVal":Number(10),"hisCur":Number(10),"enerCubixMode":"counter"])
    b:=Etc.makeDict(["id":a.id,"mod":DateTime.now+1sec,"curVal":Number(40),"hisCur":Number(40),"enerCubixMode":"counter"])
    toA:=Etc.makeDict(["id":a.id,"mod":a["mod"],"curVal":Number(10),"hisCur":Number(10),"finEnergyMode":"counter"])
    toB:=Etc.makeDict(["id":b.id,"mod":b["mod"],"curVal":Number(40),"hisCur":Number(40),"finEnergyMode":"counter"])
    verifyEq(FinEnergyNamespace.fingerprint([a],[toA]),FinEnergyNamespace.fingerprint([b],[toB]))
    ownedChanged:=Etc.makeDict(["id":a.id,"enerCubixMode":"interval"])
    targetChanged:=Etc.makeDict(["id":a.id,"finEnergyMode":"interval"])
    verify(FinEnergyNamespace.fingerprint([a],[toA]) != FinEnergyNamespace.fingerprint([ownedChanged],[targetChanged]))
    nestedA:=Etc.makeDict(["id":Ref("alarm"),"metadata":Etc.makeDict(["enerCubixEventRef":Ref("event"),"native":"old"])])
    nestedB:=Etc.makeDict(["id":Ref("alarm"),"metadata":Etc.makeDict(["enerCubixEventRef":Ref("event"),"native":"new"]),"ackedBy":"operator"])
    nextA:=Etc.makeDict(["id":nestedA.id,"metadata":Etc.makeDict(["finEnergyEventRef":Ref("event"),"native":"old"])])
    nextB:=Etc.makeDict(["id":nestedB.id,"metadata":Etc.makeDict(["finEnergyEventRef":Ref("event"),"native":"new"]),"ackedBy":"operator"])
    verifyEq(FinEnergyNamespace.fingerprint([nestedA],[nextA]),FinEnergyNamespace.fingerprint([nestedB],[nextB]))
  }

  Void testLegacyMaintenanceGuardAndResumeDelta()
  {
    home:=Env.cur.tempDir+("finEnergy-legacy-guard-"+Uuid()+"/").toUri
    db:=Folio3.open(FolioConfig {it.dir=home;it.idPrefix="p:test:r:"})
    try
    {
      verify(!FinEnergyNamespace.needsMigration(db))
      FinEnergyMeterTimeline.initialize(db)
      verifyEq(db.readCount(Filter.has("finEnergyMeterTimeline")),1)
      legacy:=db.commit(Diff.makeAdd(Etc.makeDict(["enerCubixKind":"meter","dis":"kept"]),Ref("legacy"))).newRec
      verify(FinEnergyNamespace.needsMigration(db))
      db.commit(Diff(legacy,FinEnergyNamespace.changes(legacy,"enerCubix","finEnergy")))
      verify(!FinEnergyNamespace.needsMigration(db))
    }
    finally {db.close}
    before:=Etc.makeDict(["id":Ref("point"),"enerCubixMode":"counter","curVal":Number(10)])
    after:=Etc.makeDict(["id":before.id,"finEnergyMode":"counter","curVal":Number(10)])
    current:=Etc.makeDict(["id":before.id,"enerCubixMode":"counter","curVal":Number(50)])
    forward:=FinEnergyNamespace.safeRestore(current,after,before)
    verifyEq(forward["finEnergyMode"],"counter");verifyEq(forward["enerCubixMode"],Remove.val)
    verify(!forward.has("curVal"))
    verify(FinEnergyNamespace.safeRestore(after,after,before).isEmpty)
  }
}

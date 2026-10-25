using haystack

class EnerCubixNativeAlarmsTest : Test
{
  Void testNativeAlarmPersistenceSurvivesPresentationCleanup()
  {
    record:=Str:Obj?["kind":"alarm","nativeAlarmId":"event-1_offNormal","nativeAlarmArchive":"original native record","nativeRecoveredAt":"2026-10-23T16:00:00+08:00","nativeActive":false,"nativeReadonly":true]
    stored:=EnerCubixNativeSpace.clean(record)
    verifyEq(stored["nativeAlarmId"],record["nativeAlarmId"])
    verifyEq(stored["nativeAlarmArchive"],record["nativeAlarmArchive"])
    verifyEq(stored["nativeRecoveredAt"],record["nativeRecoveredAt"])
    verifyEq(stored["nativeActive"],null)
    verifyEq(stored["nativeReadonly"],null)
    record["kind"]="meter"
    verifyEq(EnerCubixNativeSpace.clean(record)["nativeAlarmId"],null)
  }

  Void testNativeConfirmationIsAuthoritative()
  {
    local:=Str:Obj?["id":"event-1","state":"acknowledged","ackBy":"old","ackAt":"old","ackNote":"old"]
    nativeRec:=Etc.makeDict(["id":Ref("event-1_offNormal"),"sourceRef":Ref("event-1"),"state":"offNormal","active":Marker.val])
    open:=EnerCubixNativeAlarms.project(local,nativeRec)
    verifyEq(open["state"],"open")
    verifyEq(open["ackBy"],null)
    verifyEq(open["ackAt"],null)
    verifyEq(local["state"],"acknowledged")
    at:=DateTime.now
    confirmed:=EnerCubixNativeAlarms.project(local,Etc.dictSet(Etc.dictSet(Etc.dictSet(nativeRec,"acked",at),"ackedBy","Native operator"),"ackMessage","Checked"))
    verifyEq(confirmed["state"],"acknowledged")
    verifyEq(confirmed["ackBy"],"Native operator")
    verifyEq(confirmed["ackAt"],at.toIso)
    verifyEq(confirmed["ackNote"],"Checked")
  }

  Void testNativeOwnershipAndUnitMetadata()
  {
    event:=Str:Obj?["id":"event-1","nodeId":"meter-1","categoryId":"electric","value":19.390625f,"limit":7f,"unit":"kWh","ts":"2026-10-23T13:00:00+08:00","sourceIds":["point-1"]]
    meta:=EnerCubixNativeAlarms.metadata(event)
    verifyEq(meta["enerCubixEventRef"],Ref("event-1"))
    verifyEq(((Number)meta["sourceValue"]).unit,Unit("kWh"))
    verifyEq(((Number)meta["enerCubixLimit"]).toFloat,7f)
    verifyEq(meta["ackRequired"],Marker.val)
    verifyEq(meta["enerCubixSourceRefs"],Ref[Ref("point-1")])
    owned:=Etc.makeDict(["id":Ref("event-1_offNormal"),"sourceRef":Ref("event-1"),"state":"offNormal","metadata":meta])
    EnerCubixNativeAlarms.checkOwned(event,owned)
    verifyErr(ArgErr#) { EnerCubixNativeAlarms.checkOwned(event,Etc.dictSet(owned,"sourceRef",Ref("another-source"))) }
    verifyErr(ArgErr#) { EnerCubixNativeAlarms.checkOwned(event,Etc.dictSet(owned,"metadata",Etc.emptyDict)) }
    verifyEq(EnerCubixNativeAlarms.nativeId("event-1"),Ref("event-1_offNormal"))
  }
}

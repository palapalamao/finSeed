using haystack
using util
using alarmExt

class EnerCubixNamespaceTest : Test
{
  Void testAlarmRetainsStateAcknowledgementAndTimes()
  {
    occurred:=DateTime.now-1hr
    acked:=occurred+1min
    original:=Etc.makeDict(["id":Ref("alarm-1"),"state":"offNormal","priority":Number(50),"occurred":occurred,
      "active":Marker.val,"created":occurred+1sec,"sourceRef":Ref("point-1"),"acked":acked,"ackedBy":"operator",
      "ackMessage":"prior business text","ackRequired":Marker.val,"dispatcher":"rule",
      "metadata":Etc.makeDict(["formerEnergyAlarm":Marker.val,"formerEventRef":Ref("event-1")])])
    updated:=EnerCubixNamespace.alarmChange(original,"former","enerCubix")
    verifyEq(updated.id,original.id)
    verifyEq(updated.state,"offNormal"); verify(updated.active)
    verifyEq(updated.priority,Number(50)); verifyEq(updated.occurred,occurred)
    verifyEq(updated.created,occurred+1sec); verifyEq(updated.sourceRef,Ref("point-1"))
    verifyEq(updated.acked,acked); verifyEq(updated.ackedBy,"operator")
    verifyEq(updated.ackMessage,"prior business text"); verify(updated.ackRequired)
    verifyEq(updated.metadata["enerCubixEventRef"],Ref("event-1"))
    verify(!updated.metadata.has("formerEventRef"))
    verifyEq(EnerCubixNamespace.alarmChange(updated,"former","enerCubix"),null)
  }

  Void testTagsAndNestedMetadataKeepIdentityAndBusinessText()
  {
    source:=Ref("source-point")
    record:=Etc.makeDict(["id":Ref("record-1"),"dis":"prior shop","prior":Marker.val,"priorKind":"meter","priorPointRef":source,
      "priorConfig":"{\"name\":\"prior shop\",\"snapshot\":{\"id\":\"original\",\"priorKind\":\"meter\",\"priorPointRef\":\"source-point\"}}",
      "metadata":Etc.makeDict(["priorEventRef":Ref("event-1"),"priorEnergyAlarm":Marker.val])])
    changes:=EnerCubixNamespace.changes(record,"prior","enerCubix")
    verifyEq(changes["prior"],Remove.val)
    verifyEq(changes["enerCubix"],Marker.val)
    verifyEq(changes["enerCubixPointRef"],source)
    verify(!changes.has("id")); verify(!changes.has("dis"))
    config:=(Map)JsonInStream(changes["enerCubixConfig"].toStr.in).readJson
    verifyEq(config["name"],"prior shop")
    snapshot:=(Map)config["snapshot"]
    verifyEq(snapshot["id"],"original")
    verifyEq(snapshot["enerCubixKind"],"meter")
    verify(!snapshot.containsKey("priorKind"))
    meta:=(Dict)changes["metadata"]
    verifyEq(meta["enerCubixEventRef"],Ref("event-1"))
    verify(!meta.has("priorEventRef"))
  }

  Void testConflictFailsBeforeAnyWriteAndRepeatIsEmpty()
  {
    conflict:=Etc.makeDict(["priorKind":"meter","enerCubixKind":"sensor"])
    verifyErr(ArgErr#) { EnerCubixNamespace.changes(conflict,"prior","enerCubix") }
    verifyEq(conflict["priorKind"],"meter")
    verifyEq(EnerCubixNamespace.changes(Etc.makeDict(["enerCubixKind":"meter"]),"prior","enerCubix").isEmpty,true)
    schedule:=EnerCubixNamespace.changes(Etc.makeDict(["jobExpr":"priorScheduled()"]),"prior","enerCubix")
    verifyEq(schedule["jobExpr"],"enerCubixScheduled()")
  }
}

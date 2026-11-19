using haystack
using util
using alarmExt

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
  }
}

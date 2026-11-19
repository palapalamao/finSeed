using util

class FinEnergyCockpitHistoryMetaTest : Test
{
  Void testPerHeaderFilteringWorkspaceExpiresBeforeTheNextHeader()
  {
    budget:=FinEnergyStreamBudget().state;work:=FinEnergyPreparedOwner(budget);output:=FinEnergyPreparedOwner(budget);peer:=FinEnergyPreparedOwner(budget)
    collector:=FinEnergyCockpitHistoryMeta(Str[,],at,work,output);peer.hold(budget.remaining-800);held:=peer.entries
    header:=Str:Obj?["pointId":"not-planned","streaming":Str:Obj?["nativeReadCount":17].toImmutable]
    try
    {
      400.times {collector.observe(header)}
      verifyEq(peer.entries,held);verifyEq(budget.temporary.val,work.entries+output.entries+held)
      peer.close;proof:=collector.snapshot;verifyJson(proof["streaming"],[["nativeReadCount":17]])
      work.close;verifyJson(proof["streaming"],[["nativeReadCount":17]])
    }
    finally {work.close;output.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }

  Void testDetachedConfigurationAndCleaningSurviveSourceRelease()
  {
    from:=at-1sec; to:=at+1sec
    parameters:=Str:Obj?["deltaMax":100f,"nested":["mode":"drop"]]
    ref:=Str:Obj?["id":"profile","mod":"v1"]
    history:=Str:Obj?["pointId":"p","configRefs":[ref],"historyConfigObservedFrom":from.toIso,"historyConfigObservedTo":to.toIso,
      "cleaning":["profileId":"profile","profileVersion":2,"parameters":parameters,"details":[["raw":99f]]],
      "_preparedReads":["private-hour":"never retain"],"samples":[["ts":at.toIso,"value":3f]],"limitation":"sourceLimit","streaming":["scannedSamples":2]]
    collector:=FinEnergyCockpitHistoryMeta(["p"],at+2hr)
    collector.observe(history)
    history.clear;ref["mod"]="changed";parameters["deltaMax"]=999f;((Map)parameters["nested"])["mode"]="changed"
    proof:=collector.snapshot
    verify(proof.isImmutable)
    verifyJson(proof["configRefs"],[["id":"profile","mod":"v1"]])
    verifyJson(proof["appliedCleaning"],[["pointId":"p","profileId":"profile","profileVersion":2,"parameters":["deltaMax":100f,"nested":["mode":"drop"]]]])
    verifyEq(proof["historyConfigObservedFrom"],from.toIso);verifyEq(proof["historyConfigObservedTo"],to.toIso)
    verifyJson(proof["historyLimitations"],[["pointId":"p","reason":"sourceLimit"]])
    verifyJson(proof["streaming"],[["scannedSamples":2]])
    verifyEq(proof["sourceLastObservedAt"],at.toIso)
    encoded:=JsonOutStream.writeJsonToStr(proof)
    ["_preparedReads","private-hour","samples","raw","details"].each |key| {verify(!encoded.contains(key))}
  }

  Void testObservationUsesOnlyPlannedSourcesAndBoundedOriginalFallbacks()
  {
    collector:=FinEnergyCockpitHistoryMeta(["p","q"],at+2hr)
    collector.observe(["pointId":"outside","sourceLastObservedAt":(at+2hr).toIso,"samples":[["ts":(at+2hr).toIso]]])
    collector.observe(["pointId":"p","sourceLastObservedAt":(at+4hr).toIso,"rawSamples":[["ts":(at+1hr).toIso],["ts":(at+3hr).toIso]],"samples":[["ts":(at+2hr).toIso]],"intervals":[["to":(at+2hr).toIso]]])
    verifyEq(collector.snapshot["sourceLastObservedAt"],(at+1hr).toIso)
    collector.observe(["pointId":"q","rawSamples":[Str:Obj?][,],"samples":[["ts":(at+5hr).toIso]],"intervals":[["to":(at+90min).toIso],["to":(at+4hr).toIso]]])
    verifyEq(collector.snapshot["sourceLastObservedAt"],(at+90min).toIso)
    verifyEq(collector.snapshot["streaming"],Obj?[,].add(null))
    empty:=FinEnergyCockpitHistoryMeta(["p"],at).snapshot
    verifyNull(empty["sourceLastObservedAt"]);verifyEq(empty["streaming"],Obj?[,]);verifyEq(empty["appliedCleaning"],[Str:Obj?][,])
  }

  private Void verifyJson(Obj? actual, Obj? expected)
  {verifyEq(JsonInStream(JsonOutStream.writeJsonToStr(actual).in).readJson,JsonInStream(JsonOutStream.writeJsonToStr(expected).in).readJson)}

  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

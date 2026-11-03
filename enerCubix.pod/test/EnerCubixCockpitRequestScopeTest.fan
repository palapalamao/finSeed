using util

** Controlled request/gate/wire lifetime, not native HTTP authentication proof.
class EnerCubixCockpitRequestScopeTest : Test
{
  Void testHistoryProofSurvivesMetadataWorkspaceAndRawHeaderCleanup()
  {
    scope:=EnerCubixCockpitRequestScope("history-proof","a");peer:=EnerCubixPreparedOwner(scope.stream.state);peer.hold(31)
    stats:=Str:Obj?["nativeReadCount":2]
    raw:=Str:Obj?["pointId":"p","configRefs":[["id":"profile","mod":"2026-10-01T00:00:00Z"]],"cleaning":["profileId":"profile","profileVersion":1,"parameters":["deltaMin":0f]],"streaming":stats,"sourceLastObservedAt":"2026-10-01T01:00:00Z"]
    try
    {
      headers:=scope.freezeHistoryHeaders([raw,["pointId":"other","streaming":stats]])
      verify(headers.first["streaming"]===headers.last["streaming"])
      work:=scope.metadataWorkspace(1)
      meta:=EnerCubixCockpitHistoryMeta(["p"],DateTime.fromIso("2026-10-01T02:00:00Z"),work,scope.historyOutput)
      headers.each |header| {meta.observe(header)}
      proof:=meta.snapshot;scope.finishMetadata
      verifyEq(work.entries,0);verifyErr(ArgErr#) {meta.observe(headers.first)}
      ((Map)((Map)raw["cleaning"])["parameters"])["deltaMin"]=99f;stats["nativeReadCount"]=999;raw.clear
      verifyEq(((Map)((List)proof["streaming"]).first)["nativeReadCount"],2)
      verifyEq(((Map)((Map)((List)proof["appliedCleaning"]).first)["parameters"])["deltaMin"],0f)
      verifyEq(((Map)((List)proof["configRefs"]).first)["id"],"profile")
      verifyEq(proof["sourceLastObservedAt"],"2026-10-01T01:00:00Z")
      verifyEq(scope.stream.state.temporary.val,scope.entries+peer.entries)
      scope.deliver(proof,|Buf bytes| {verify(bytes.size>0)})
      scope.close;verifyEq(scope.stream.state.temporary.val,peer.entries)
    }
    finally {scope.close;peer.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testThinHeaderCopyCannotBePublishedBeforeItsAdmission()
  {
    scope:=EnerCubixCockpitRequestScope("history-header-limit","a");peer:=EnerCubixPreparedOwner(scope.stream.state)
    peer.hold(scope.stream.state.remaining-24);held:=peer.entries
    headers:=[Str:Obj?][["pointId":"p","configRefs":[["id":"profile","mod":"version"]]]]
    try
    {
      verifyErr(EnerCubixHttpErr#) {scope.freezeHistoryHeaders(headers)}
      verifyEq(headers.first["pointId"],"p");verify(!scope.responseStarted)
      scope.close;verifyEq(scope.stream.state.temporary.val,held)
    }
    finally {scope.close;peer.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testPlanningCatalogCanReleaseItsOwnersWithoutClearingInputRecords()
  {
    scope:=EnerCubixCockpitRequestScope("planning-scope","a");peer:=EnerCubixPreparedOwner(scope.stream.state);peer.hold(31)
    records:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space"],["id":"m","kind":"meter","pointId":"p","categoryId":"c","spaceId":"s"]].toImmutable
    try
    {
      context:=scope.planningContext(records,TimeZone.utc,"space",false)
      verifyErr(ArgErr#) {scope.sourceCatalog(records.dup.toImmutable,TimeZone.utc,[:])}
      catalog:=scope.sourceCatalog(records,TimeZone.utc,["p":"kWh"])
      verifyEq(catalog.primaryUnit("p"),"kWh")
      verifyErr(ArgErr#) {scope.sourceCatalog(records,TimeZone.utc,["p":"Wh"])}
      verifyEq(context.scopeMeters("s","c").first["id"],"m")
      verifyEq(scope.stream.state.temporary.val,scope.entries+peer.entries)
      scope.finishPlanning;scope.finishPlanning
      verifyEq(((Map)records.last)["pointId"],"p");verifyEq(scope.stream.state.temporary.val,scope.entries+peer.entries)
      verifyErr(ArgErr#) {scope.planningContext(records,TimeZone.utc,"space",false)}
      scope.close;verifyEq(scope.stream.state.temporary.val,peer.entries)
    }
    finally {scope.close;peer.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testPlanningCatalogAdmissionFailureDoesNotReleasePeerOrTheGate()
  {
    scope:=EnerCubixCockpitRequestScope("planning-limit","a");peer:=EnerCubixPreparedOwner(scope.stream.state)
    records:=[Str:Obj?][,];(0..<300).each |i| {records.add(["id":"m$i","kind":"meter"])};records=records.toImmutable
    peer.hold(scope.stream.state.remaining-100);held:=peer.entries
    try
    {
      verifyErr(EnerCubixHttpErr#) {scope.planningContext(records,TimeZone.utc,"metering",false)}
      verifyEq(peer.entries,held);verifyEq(scope.stream.nativeReads,0)
      verifyErr(EnerCubixHttpErr#) {EnerCubixCockpitGate.enter("planning-limit","a")}
      scope.close;verifyEq(scope.stream.state.temporary.val,held)
    }
    finally {scope.close;peer.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testFinalSnapshotBorrowsFrozenInputsAndKeepsItsCopyOwnedThroughTheSender()
  {
    scope:=EnerCubixCockpitRequestScope("request-snapshot","a");Map? frozen
    try
    {
      inputs:=scope.freezeInputs(["schemaVersion":1],[:],[["id":"m","kind":"meter"]])
      inputRecord:=(Map)((List)inputs["records"]).first;shared:=Str:Obj?["value":12.5f,"source":inputRecord]
      frozen=scope.freezeSnapshot(["schemaVersion":1,"left":shared,"right":shared])
      verify(frozen.isImmutable);verify(frozen["left"]===frozen["right"]);verify(((Map)frozen["left"])["source"]===inputRecord)
      shared["value"]=999f;verifyEq(((Map)frozen["left"])["value"],12.5f)
      scope.deliver((Str:Obj?)frozen,|Buf bytes| {verify(scope.stream.state.temporary.val>scope.entries)})
      verifyEq(scope.stream.state.temporary.val,scope.entries)
    }
    finally {frozen=null;scope.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testInputBundleSharesFrozenModelRecordsAndKeepsTheirOwnerThroughSending()
  {
    record:=Str:Obj?["id":"m","name":"Original 中文","kind":"meter"]
    records:=[record];owned:=Str:Obj?["modelRecords":records,"modelComplete":true]
    scope:=EnerCubixCockpitRequestScope("request-inputs","a");Map? inputs
    try
    {
      inputs=scope.freezeInputs(["schemaVersion":1],owned,records)
      verify(inputs.isImmutable);model:=(List)((Map)inputs["owned"])["modelRecords"]
      verify(model===inputs["records"]);verify(model.first===((List)inputs["records"]).first)
      record["name"]="later edit";verifyEq(((Map)model.first)["name"],"Original 中文")
      scope.deliver(["schemaVersion":1],|Buf bytes| {verify(scope.stream.state.temporary.val>scope.entries);verify(inputs.isImmutable)})
      verifyEq(scope.stream.state.temporary.val,scope.entries)
    }
    finally {inputs=null;scope.close}
    verifyEq(scope.stream.state.temporary.val,0);verify(!records.isImmutable)
  }
  Void testGateRemainsHeldThroughWireSendingAndAnOldCloseCannotReleaseANewRequest()
  {
    project:="request-scope-success";user:="a";scope:=EnerCubixCockpitRequestScope(project,user);calls:=0
    try
    {
      scope.deliver(["schemaVersion":1,"name":"中文 EN 😀"],|Buf bytes|
      {
        calls++;verify(scope.responseStarted);verify(!scope.canSendError)
        verifyErr(ArgErr#) {scope.close}
        verifyErr(EnerCubixHttpErr#) {unexpected:=EnerCubixCockpitRequestScope(project,user);unexpected.close}
        verifyErr(EnerCubixHttpErr#) {EnerCubixCockpitGate.enter(project,user)}
        parsed:=(Map)JsonInStream(bytes.in).readJson
        verifyEq(parsed["ok"],true);verifyEq(((Map)parsed["data"])["name"],"中文 EN 😀")
      })
      verifyEq(calls,1);verifyEq(scope.stream.state.temporary.val,scope.entries)
    }
    finally {scope.close}
    verifyEq(scope.stream.state.temporary.val,0)
    next:=EnerCubixCockpitRequestScope(project,user)
    try {scope.close;verifyErr(EnerCubixHttpErr#) {EnerCubixCockpitGate.enter(project,user)}}
    finally {next.close}
    EnerCubixCockpitGate.enter(project,user);EnerCubixCockpitGate.leave(project,user)
  }
  Void testSerializationFailureAllowsAnErrorButSendingFailureNeverAllowsASecondResponse()
  {
    project:="request-scope-failure";scope:=EnerCubixCockpitRequestScope(project,"a");calls:=0
    try
    {
      payloadBytes:=8388608
      try {scope.deliver(["text":"x".padl(payloadBytes,'x')],|Buf bytes| {calls++});fail("Expected complete-envelope limit")}
      catch(EnerCubixHttpErr e) {verifyEq(e.status,413)}
      verify(!scope.responseStarted);verify(scope.canSendError);verifyEq(calls,0)
      verifyErr(EnerCubixHttpErr#) {EnerCubixCockpitGate.enter(project,"a")}
    }
    finally {scope.close}
    scope=EnerCubixCockpitRequestScope(project,"a");original:=IOErr("controlled socket write failure");Err? observed
    try
    {
      try {scope.deliver(["value":12.5f],|Buf bytes| {calls++;throw original})}
      catch(Err e) {observed=e}
      verify(observed===original);verifyEq(calls,1);verify(scope.responseStarted);verify(!scope.canSendError)
      verifyErr(ArgErr#) {scope.deliver(["value":99f],|Buf bytes| {calls++})}
      verifyEq(calls,1)
    }
    finally {scope.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testRejectedScopeDoesNotReleaseAnotherRequestOrItsBudget()
  {
    project:="request-scope-admission";scope:=EnerCubixCockpitRequestScope(project,"a")
    stream:=EnerCubixStreamBudget();peer:=EnerCubixPreparedOwner(stream.state);peer.hold(stream.state.remaining);held:=peer.entries
    try
    {
      verifyErr(EnerCubixHttpErr#) {unexpected:=EnerCubixCockpitRequestScope(project,"a",stream);unexpected.close}
      verifyErr(EnerCubixHttpErr#) {EnerCubixCockpitGate.enter(project,"a")}
      verifyErr(EnerCubixHttpErr#) {unexpected:=EnerCubixCockpitRequestScope(project,"b",stream);unexpected.close}
      verifyEq(peer.entries,held);verifyEq(stream.state.temporary.val,held)
      // Failed b construction entered and then rolled back only b's gate slot.
      EnerCubixCockpitGate.enter(project,"b");EnerCubixCockpitGate.leave(project,"b")
    }
    finally {peer.close;scope.close}
    verifyEq(stream.state.temporary.val,0)
  }
}

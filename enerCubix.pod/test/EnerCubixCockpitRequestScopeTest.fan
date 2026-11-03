using util

** Controlled request/gate/wire lifetime, not native HTTP authentication proof.
class EnerCubixCockpitRequestScopeTest : Test
{
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

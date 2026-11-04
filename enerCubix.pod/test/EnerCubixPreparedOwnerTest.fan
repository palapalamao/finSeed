class EnerCubixPreparedOwnerTest : Test
{
  Void testPublicChargeTransferIsAtomicAtTheLimitAndClosesTheDonor()
  {
    budget:=EnerCubixStreamBudget().state;source:=EnerCubixPreparedOwner(budget);target:=EnerCubixPreparedOwner(budget);peer:=EnerCubixPreparedOwner(budget)
    value:=Str:Obj?["value":17f];oldDrop:=false
    source.hold(30);source.watch |->Void| {oldDrop=true;value.clear}
    target.hold(40);target.watch |->Void| {value.clear}
    source.retainPublic(source.entries) |->Void| {};target.retainPublic(target.entries) |->Void| {value.clear}
    n:=source.entries+target.entries;peer.hold(budget.remaining);held:=peer.entries;before:=budget.temporary.val
    try
    {
      source.transferRetainedTo(target)
      verifyEq(budget.temporary.val,before);verifyEq(target.entries,n);verifyEq(source.entries,0);verify(!oldDrop)
      verifyEq(value["value"],17f);verifyEq(peer.entries,held)
      verifyErr(ArgErr#) {source.hold(1)};verifyErr(ArgErr#) {source.watch |->Void| {}};verifyErr(ArgErr#) {source.fork}
      source.close;verifyEq(value["value"],17f);target.close;verify(value.isEmpty);verifyEq(budget.temporary.val,held)
      verify(budget.peak.val<=200000)
    }
    finally {source.close;target.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testPublicChargeTransferRejectsForeignOwnersAndSamplePoolsBeforeChangingCredit()
  {
    budget:=EnerCubixStreamBudget().state;source:=EnerCubixPreparedOwner(budget);target:=EnerCubixPreparedOwner(budget)
    foreign:=EnerCubixPreparedOwner(EnerCubixStreamBudget().state);poolOwner:=EnerCubixPreparedOwner(budget)
    pool:=EnerCubixCockpitCapture(["g":["kind":"cleaningEvents","grain":"event","reportRefs":["r"]]],poolOwner)
    sampled:=EnerCubixPreparedOwner(budget,pool);before:=budget.temporary.val;n:=source.entries
    try
    {
      verifyErr(ArgErr#) {source.transferRetainedTo(source)}
      verifyErr(ArgErr#) {source.transferRetainedTo(foreign)}
      verifyErr(ArgErr#) {source.transferRetainedTo(sampled)}
      verifyEq(budget.temporary.val,before);verifyEq(source.entries,n)
      target.close;verifyErr(ArgErr#) {source.transferRetainedTo(target)}
      source.close;verifyErr(ArgErr#) {source.transferRetainedTo(sampled)}
    }
    finally {source.close;target.close;sampled.close;poolOwner.close;foreign.close}
    verifyEq(budget.temporary.val,0);verifyEq(foreign.budget.temporary.val,0)
  }

  Void testPublicRetirementReplacesOnlyItsOwnCleanupAndCharge()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline())
    peer:=EnerCubixPreparedOwner(budget);peer.hold(23);held:=peer.entries
    owner:=EnerCubixPreparedOwner(budget);owner.hold(100)
    publicResult:=Str:Obj?["value":17f];privateDrop:=false
    owner.watch |->Void| {privateDrop=true;publicResult.clear}
    verifyErr(ArgErr#) {owner.retainPublic(5) |->Void| {}}
    verifyErr(ArgErr#) {owner.retainPublic(200) |->Void| {}}
    owner.retainPublic(32) |->Void| {publicResult.clear}
    verify(!privateDrop);verifyEq(publicResult["value"],17f)
    verifyEq(owner.entries,32);verifyEq(budget.temporary.val,held+32)
    owner.hold(7);verifyEq(budget.temporary.val,held+39)
    owner.close;verify(publicResult.isEmpty);verify(!privateDrop)
    verifyEq(budget.temporary.val,held);owner.close
    verifyErr(ArgErr#) {owner.retainPublic(6) |->Void| {}}
    peer.close;verifyEq(budget.temporary.val,0)
  }

  Void testDropPrecedesReleaseAndPeerChargeIsPreserved()
  {
    state:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state.holdOwned(13)
    owner:=EnerCubixPreparedOwner(state);data:=Str:Obj?["row":7f];dropped:=false
    owner.watch |->Void|
    {
      verifyEq(state.temporary.val,13+owner.entries)
      verify(!data.isEmpty);data.clear;dropped=true
    }
    owner.hold(7);verifyEq(state.temporary.val,13+owner.entries)
    owner.close
    verify(dropped);verify(data.isEmpty);verifyEq(owner.entries,0);verifyEq(state.temporary.val,13)
    owner.close;verifyEq(state.temporary.val,13)
    verifyErr(ArgErr#) {owner.hold(1)}
    verifyErr(ArgErr#) {owner.watch |->Void| {}}
  }

  Void testFailedAdmissionDoesNotCreateOwnedEntries()
  {
    state:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state.holdOwned(13)
    owner:=EnerCubixPreparedOwner(state);before:=owner.entries
    verifyErr(EnerCubixHttpErr#) {owner.hold(200000)}
    verifyEq(owner.entries,before);verifyEq(state.temporary.val,13+before)
    verifyErr(ArgErr#) {owner.hold(-1)}
    owner.close;verifyEq(state.temporary.val,13)
  }

  Void testFailedDropCannotReleaseStillOwnedState()
  {
    state:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(state)
    data:=Str:Obj?["row":1f];blocked:=true
    owner.watch |->Void| {if(blocked) throw IOErr("controlled drop failure");data.clear}
    owner.hold(2);before:=owner.entries
    verifyErr(IOErr#) {owner.close}
    verifyEq(owner.entries,before);verifyEq(state.temporary.val,before);verify(!data.isEmpty)
    blocked=false;owner.close;verify(data.isEmpty);verifyEq(state.temporary.val,0)
  }
}

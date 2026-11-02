class EnerCubixPreparedOwnerTest : Test
{
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

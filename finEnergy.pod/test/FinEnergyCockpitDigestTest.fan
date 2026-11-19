using util
using concurrent

class FinEnergyCockpitDigestTest : Test
{
  Void testUtf8JsonDigestMatchesTheExistingHashWithoutChangingEscapes()
  {
    value:=Str:Obj?["中文":"FIN Energy 🌍\n\t\"\\","nullable":null,"zero":0f,"rows":[["value":1f]]]
    expected:=JsonOutStream.writeJsonToStr(value).toBuf
    budget:=FinEnergyStreamBudget().state
    actual:=digest(value,budget)
    verifyEq(actual->size,expected.size);verifyEq(actual->sha256,expected.toDigest("SHA-256").toHex)
    verifyEq(budget.temporary.val,0)
  }
  Void testInternalHashIsNotLimitedByTheFinalEightMiBEnvelope()
  {
    size:=8388609;value:="x".padl(size,'x')
    budget:=FinEnergyStreamBudget().state;actual:=digest(value,budget)
    verifyEq(actual->size,size+2)
    verifyEq(actual->sha256,JsonOutStream.writeJsonToStr(value).toBuf.toDigest("SHA-256").toHex)
    verifyEq(budget.temporary.val,0)
  }
  Void testHashAdmissionAndDeadlineFailureKeepPeerOwnership()
  {
    budget:=FinEnergyStreamBudget().state;peer:=FinEnergyPreparedOwner(budget)
    peer.hold(budget.remaining-20);held:=peer.entries
    try {verifyErr(FinEnergyHttpErr#) {digest(["value":1],budget)};verifyEq(budget.temporary.val,held)}
    finally {peer.close}
    calls:=AtomicInt();deadline:=FinEnergyCockpitDeadline(30sec,|->Int| {return calls.incrementAndGet>3 ? 31sec.ticks : 0})
    timed:=FinEnergyStreamBudget(50000,200000,20000000,30sec,deadline).state
    size:=20000;value:="x".padl(size,'x')
    verifyErr(FinEnergyHttpErr#) {digest(value,timed)}
    verifyEq(timed.temporary.val,0);verifyEq(budget.temporary.val,0)
  }
  private Obj digest(Obj? value,FinEnergyPreparedBudget budget)
  {Type.find("finEnergy::FinEnergyCockpitDigest").method("json").call(value,budget.deadline,budget)}
}

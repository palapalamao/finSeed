using util
using concurrent

class EnerCubixCockpitDigestTest : Test
{
  Void testUtf8JsonDigestMatchesTheExistingHashWithoutChangingEscapes()
  {
    value:=Str:Obj?["中文":"Energy Cubix 🌍\n\t\"\\","nullable":null,"zero":0f,"rows":[["value":1f]]]
    expected:=JsonOutStream.writeJsonToStr(value).toBuf
    budget:=EnerCubixStreamBudget().state
    actual:=digest(value,budget)
    verifyEq(actual->size,expected.size);verifyEq(actual->sha256,expected.toDigest("SHA-256").toHex)
    verifyEq(budget.temporary.val,0)
  }
  Void testInternalHashIsNotLimitedByTheFinalEightMiBEnvelope()
  {
    size:=8388609;value:="x".padl(size,'x')
    budget:=EnerCubixStreamBudget().state;actual:=digest(value,budget)
    verifyEq(actual->size,size+2)
    verifyEq(actual->sha256,JsonOutStream.writeJsonToStr(value).toBuf.toDigest("SHA-256").toHex)
    verifyEq(budget.temporary.val,0)
  }
  Void testHashAdmissionAndDeadlineFailureKeepPeerOwnership()
  {
    budget:=EnerCubixStreamBudget().state;peer:=EnerCubixPreparedOwner(budget)
    peer.hold(budget.remaining-20);held:=peer.entries
    try {verifyErr(EnerCubixHttpErr#) {digest(["value":1],budget)};verifyEq(budget.temporary.val,held)}
    finally {peer.close}
    calls:=AtomicInt();deadline:=EnerCubixCockpitDeadline(30sec,|->Int| {return calls.incrementAndGet>3 ? 31sec.ticks : 0})
    timed:=EnerCubixStreamBudget(50000,200000,20000000,30sec,deadline).state
    size:=20000;value:="x".padl(size,'x')
    verifyErr(EnerCubixHttpErr#) {digest(value,timed)}
    verifyEq(timed.temporary.val,0);verifyEq(budget.temporary.val,0)
  }
  private Obj digest(Obj? value,EnerCubixPreparedBudget budget)
  {Type.find("enerCubix::EnerCubixCockpitDigest").method("json").call(value,budget.deadline,budget)}
}

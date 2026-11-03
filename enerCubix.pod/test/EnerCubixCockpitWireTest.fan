using concurrent
using util

** UTF-8 wire ownership only; no HTTP/socket or whole-request heap proof.
class EnerCubixCockpitWireTest : Test
{
  Void testUnicodeEnvelopeUsesExactUtf8ByteLimitAndExpiresBorrowedBuffer()
  {
    body:=Str:Obj?["ok":true,"data":["name":"中文 English 😀","escaped":"\"\\\n\t","value":12.5f]]
    expected:=JsonOutStream.writeJsonToStr(body).toBuf
    [-1,0,1].each |offset|
    {
      budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());calls:=0;Buf? escaped
      try
      {
        EnerCubixCockpitWire.withBody(body,budget,|Buf bytes| {calls++;escaped=bytes;verifyEq(bytes.size,expected.size);verifyEq(bytes.toHex,expected.toHex)},expected.size+offset)
        verify(offset>=0);verifyEq(calls,1);verifyEq(escaped.size,0)
      }
      catch(EnerCubixHttpErr e) {verifyEq(offset,-1);verifyEq(e.status,413);verifyEq(e.code,"RESPONSE_LIMIT");verifyEq(calls,0)}
      verifyEq(budget.temporary.val,0)
    }
  }
  Void testWholeEnvelopeAcceptsExactlyEightMiBAndRejectsOneExtraByte()
  {
    suffix:="中文 EN 😀 \"\\\n"
    overhead:=JsonOutStream.writeJsonToStr(["ok":true,"data":suffix]).toBuf.size
    [-1,0,1].each |offset|
    {
      text:="x".padl(8388608-overhead+offset,'x')+suffix
      budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());calls:=0
      try
      {
        EnerCubixCockpitWire.withBody(["ok":true,"data":text],budget,|Buf bytes| {calls++;verifyEq(bytes.size,8388608+offset)})
        verify(offset<=0);verifyEq(calls,1)
      }
      catch(EnerCubixHttpErr e) {verifyEq(offset,1);verifyEq(e.status,413);verifyEq(e.msg,"cockpitResponseLimit");verifyEq(calls,0)}
      verifyEq(budget.temporary.val,0)
    }
  }
  Void testSerializationTimeoutAndAdmissionFailureNeverInvokeTheSender()
  {
    clock:=AtomicInt();deadline:=EnerCubixCockpitDeadline(1ms,|->Int| {clock.incrementAndGet<4 ? 0 : 2ms.ticks})
    budget:=EnerCubixPreparedBudget(deadline);calls:=0
    try {EnerCubixCockpitWire.withBody(["ok":true,"data":"x".padl(20000,'x')],budget,|Buf bytes| {calls++});fail("Expected serialization timeout")}
    catch(EnerCubixHttpErr e) {verifyEq(e.status,504);verifyEq(e.code,"QUERY_TIMEOUT")}
    verifyEq(calls,0);verifyEq(clock.val,4);verifyEq(budget.temporary.val,0)
    other:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());peer:=EnerCubixPreparedOwner(other);peer.hold(other.remaining);held:=peer.entries
    verifyErr(EnerCubixHttpErr#) {EnerCubixCockpitWire.withBody(["ok":true],other,|Buf bytes| {calls++})}
    verifyEq(calls,0);verifyEq(other.temporary.val,held);peer.close;verifyEq(other.temporary.val,0)
  }
  Void testSenderFailureIsPropagatedAndOnlyThisWireAllocationIsReleased()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());peer:=EnerCubixPreparedOwner(budget);peer.hold(37);held:=peer.entries
    original:=IOErr("controlled sender failure");Err? observed;Buf? escaped;calls:=0
    try {EnerCubixCockpitWire.withBody(["ok":true,"data":"Chinese 中文"],budget,|Buf bytes| {calls++;escaped=bytes;throw original})}
    catch(Err e) {observed=e}
    verify(observed===original);verifyEq(calls,1);verifyEq(escaped.size,0);verifyEq(peer.entries,held);verifyEq(budget.temporary.val,held)
    peer.close;verifyEq(budget.temporary.val,0)
  }
}

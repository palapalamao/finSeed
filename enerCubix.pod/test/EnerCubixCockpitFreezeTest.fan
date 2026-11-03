using util
using concurrent

** Copy ownership over already supplied fixture inputs, not complete request heap.
class EnerCubixCockpitFreezeTest : Test
{
  Void testFrozenCopyKeepsSharedIdentityDistinctEqualMapsAndOriginalJson()
  {
    shared:=Str:Obj?["name":"中文 😀","values":[12.5f,null,0f]];equal:=shared.dup
    source:=Str:Obj?[:];source.ordered=true;source["same"]=[shared,shared];source["distinct"]=equal
    source["nil"]=null
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget);Map? frozen
    try
    {
      frozen=(Map)EnerCubixCockpitFreeze.value(source,owner)
      verify(frozen.isImmutable);verify(frozen.ordered)
      same:=(List)frozen["same"];verify(same[0]===same[1]);verify(same[0]!==frozen["distinct"])
      verify(((Map)same[0])["values"]===((Map)frozen["distinct"])["values"])
      verifyEq(JsonOutStream.writeJsonToStr(frozen),JsonOutStream.writeJsonToStr(source.toImmutable))
      shared["name"]="changed";((List)shared["values"])[0]=999f
      verifyEq(((Map)same[0])["name"],"中文 😀");verifyEq(((List)((Map)same[0])["values"])[0],12.5f)
      verify(!source.isImmutable);verify(!shared.isImmutable)
    }
    finally {frozen=null;owner.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testRepeatedLargeEvidenceIsCopiedOnceWithinTheSharedEntryBudget()
  {
    shared:=Str:Obj?["rows":(0..<1000).map |i->Str:Obj?| {["index":i,"value":i.toFloat]}]
    source:=(0..<500).map |i->Obj?| {shared}
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget);List? frozen
    try
    {
      frozen=(List)EnerCubixCockpitFreeze.value(source,owner)
      verifyEq(frozen.size,500);verify(frozen.all |v| {v===frozen.first});verifyEq(((List)((Map)frozen.first)["rows"]).size,1000)
      verify(budget.peak.val<20000,"aliases must not allocate hundreds of duplicate evidence graphs")
      verify(owner.entries>=4500,"actual immutable map/list entries remain charged after workspace expires")
    }
    finally {frozen=null;owner.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testImmutableInputsAreBorrowedWithoutRecloningOrChangingTheirContents()
  {
    source:=Str:Obj?["value":[1,2,3]].toImmutable
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget);before:=owner.entries
    verify(EnerCubixCockpitFreeze.value(source,owner)===source);verifyEq(owner.entries,before)
    owner.close;verifyEq(budget.temporary.val,0)
  }
  Void testCyclesAndMutableOpaqueValuesRejectAndLeaveOriginalInputsUntouched()
  {
    cycle:=Str:Obj?[:];cycle["self"]=cycle
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
    try
    {
      verifyErr(NotImmutableErr#) {EnerCubixCockpitFreeze.value(cycle,owner)}
      verify(cycle["self"]===cycle)
      opaque:=StrBuf().add("original")
      verifyErr(NotImmutableErr#) {EnerCubixCockpitFreeze.value(["opaque":opaque],owner)}
      verifyEq(opaque.toStr,"original")
    }
    finally {cycle.clear;owner.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testRejectedCloneReleasesOnlyItsOwnWorkspaceAndKeepsPeerAllocation()
  {
    source:=(0..<200).map |i->Str:Obj?| {["index":i,"value":i.toFloat]}
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget);peer:=EnerCubixPreparedOwner(budget)
    peer.hold(budget.remaining-500);held:=peer.entries
    verifyErr(EnerCubixHttpErr#) {EnerCubixCockpitFreeze.value(source,owner)}
    verifyEq(source.size,200);verify(!source.isImmutable);verifyEq(peer.entries,held)
    verifyEq(((Map)source.first)["index"],0);verifyEq(((Map)source.last)["value"],199f)
    owner.close;verifyEq(budget.temporary.val,held);peer.close;verifyEq(budget.temporary.val,0)
  }
  Void testOneSharedDeadlineCanAbortDuringCopyWithoutReturningAPartialGraph()
  {
    clock:=AtomicInt();deadline:=EnerCubixCockpitDeadline(1ms,|->Int| {clock.incrementAndGet<4 ? 0 : 2ms.ticks})
    budget:=EnerCubixPreparedBudget(deadline);owner:=EnerCubixPreparedOwner(budget)
    source:=(0..<200).map |i->Str:Obj?| {["index":i,"value":i.toFloat]};Obj? result
    try {result=EnerCubixCockpitFreeze.value(source,owner);fail("Expected a shared deadline failure")}
    catch(EnerCubixHttpErr e) {verifyEq(e.status,504);verifyEq(e.code,"QUERY_TIMEOUT")}
    verifyNull(result);verifyEq(source.size,200);owner.close;verifyEq(budget.temporary.val,0)
  }
}

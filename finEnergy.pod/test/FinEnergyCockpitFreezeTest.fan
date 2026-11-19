using util
using concurrent

** Copy ownership over already supplied fixture inputs, not complete request heap.
class FinEnergyCockpitFreezeTest : Test
{
  Void testCompletedCopiesNotifyOnceAndBorrowHitsDoNotNotifyAgain()
  {
    budget:=FinEnergyStreamBudget().state;output:=FinEnergyPreparedOwner(budget)
    child:=Str:Obj?["value":0f];source:=Str:Obj?["first":child,"alias":child];calls:=0
    try
    {
      frozen:=(Map)FinEnergyCockpitFreeze.value(source,output,null,null,false,|Obj original,Obj copy|
      {verify(copy.isImmutable);verifyEq(original.typeof,copy.typeof);calls++})
      verifyEq(calls,2);verify(frozen["first"]===frozen["alias"])
      calls=0
      again:=(Map)FinEnergyCockpitFreeze.value(source,output,|Obj value->Obj?| {value===child ? frozen["first"] : null},null,false,|Obj original,Obj copy| {calls++})
      verifyEq(calls,1);verify(again["first"]===frozen["first"]);verifyEq(again,frozen)
    }
    finally {output.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testCompletedCallbackFailurePreservesSourceAndReleasesOnlyOwnedFees()
  {
    budget:=FinEnergyStreamBudget().state;output:=FinEnergyPreparedOwner(budget);peer:=FinEnergyPreparedOwner(budget);peer.hold(43);held:=peer.entries
    child:=Str:Obj?["values":Obj?[0f,null,3f]];source:=Str:Obj?["child":child];expected:=source.toImmutable
    try
    {
      verifyErr(ArgErr#) {FinEnergyCockpitFreeze.value(source,output,null,null,false,|Obj original,Obj copy| {throw ArgErr("completedCallbackRejected")})}
      verifyEq(source,expected);verifyEq(peer.entries,held);verifyEq(budget.temporary.val,output.entries+held)
      output.close;verifyEq(budget.temporary.val,held)
    }
    finally {output.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }

  Void testDefaultConsumeRemainsPostorderAndEarlyRetirementRequiresExplicitOptIn()
  {
    [false,true].each |early|
    {
      child:=Str:Obj?["value":12f];source:=Str:Obj?["child":child];expected:=source.toImmutable;order:=Str[,]
      budget:=FinEnergyStreamBudget().state;output:=FinEnergyPreparedOwner(budget)
      try
      {
        result:=FinEnergyCockpitFreeze.value(source,output,null,|Obj value|
        {order.add(value===source ? "parent" : "child");((Map)value).clear},early)
        verifyEq(order,early ? ["parent","child"] : ["child","parent"])
        verifyEq(result,expected);verify(result.isImmutable);verify(source.isEmpty);verify(child.isEmpty)
      }
      finally {output.close}
      verifyEq(budget.temporary.val,0)
    }
    owner:=FinEnergyPreparedOwner(FinEnergyStreamBudget().state)
    try {verifyErr(ArgErr#) {FinEnergyCockpitFreeze.value(["value":1],owner,null,null,true)}}
    finally {owner.close}
    verifyEq(owner.budget.temporary.val,0)
  }

  Void testBorrowedFactsMustBeImmutableAndKeepTheOriginalContainerType()
  {
    budget:=FinEnergyStreamBudget().state;output:=FinEnergyPreparedOwner(budget)
    try
    {
      verifyErr(NotImmutableErr#) {FinEnergyCockpitFreeze.value(["id":"m"],output,|Obj value->Obj?| {Str:Obj?["id":"m"]})}
      verifyErr(NotImmutableErr#) {FinEnergyCockpitFreeze.value(["id":"m"],output,|Obj value->Obj?| {["m"].toImmutable})}
      verifyEq(budget.temporary.val,output.entries)
    }
    finally {output.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testFrozenCopyKeepsSharedIdentityDistinctEqualMapsAndOriginalJson()
  {
    shared:=Str:Obj?["name":"中文 😀","values":[12.5f,null,0f]];equal:=shared.dup
    source:=Str:Obj?[:];source.ordered=true;source["same"]=[shared,shared];source["distinct"]=equal
    source["nil"]=null
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());owner:=FinEnergyPreparedOwner(budget);Map? frozen
    try
    {
      frozen=(Map)FinEnergyCockpitFreeze.value(source,owner)
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
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());owner:=FinEnergyPreparedOwner(budget);List? frozen
    try
    {
      frozen=(List)FinEnergyCockpitFreeze.value(source,owner)
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
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());owner:=FinEnergyPreparedOwner(budget);before:=owner.entries
    verify(FinEnergyCockpitFreeze.value(source,owner)===source);verifyEq(owner.entries,before)
    owner.close;verifyEq(budget.temporary.val,0)
  }
  Void testCyclesAndMutableOpaqueValuesRejectAndLeaveOriginalInputsUntouched()
  {
    cycle:=Str:Obj?[:];cycle["self"]=cycle
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());owner:=FinEnergyPreparedOwner(budget)
    try
    {
      verifyErr(NotImmutableErr#) {FinEnergyCockpitFreeze.value(cycle,owner)}
      verify(cycle["self"]===cycle)
      opaque:=StrBuf().add("original")
      verifyErr(NotImmutableErr#) {FinEnergyCockpitFreeze.value(["opaque":opaque],owner)}
      verifyEq(opaque.toStr,"original")
    }
    finally {cycle.clear;owner.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testRejectedCloneReleasesOnlyItsOwnWorkspaceAndKeepsPeerAllocation()
  {
    source:=(0..<200).map |i->Str:Obj?| {["index":i,"value":i.toFloat]}
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());owner:=FinEnergyPreparedOwner(budget);peer:=FinEnergyPreparedOwner(budget)
    peer.hold(budget.remaining-500);held:=peer.entries
    verifyErr(FinEnergyHttpErr#) {FinEnergyCockpitFreeze.value(source,owner)}
    verifyEq(source.size,200);verify(!source.isImmutable);verifyEq(peer.entries,held)
    verifyEq(((Map)source.first)["index"],0);verifyEq(((Map)source.last)["value"],199f)
    owner.close;verifyEq(budget.temporary.val,held);peer.close;verifyEq(budget.temporary.val,0)
  }
  Void testOneSharedDeadlineCanAbortDuringCopyWithoutReturningAPartialGraph()
  {
    clock:=AtomicInt();deadline:=FinEnergyCockpitDeadline(1ms,|->Int| {clock.incrementAndGet<4 ? 0 : 2ms.ticks})
    budget:=FinEnergyPreparedBudget(deadline);owner:=FinEnergyPreparedOwner(budget)
    source:=(0..<200).map |i->Str:Obj?| {["index":i,"value":i.toFloat]};Obj? result
    try {result=FinEnergyCockpitFreeze.value(source,owner);fail("Expected a shared deadline failure")}
    catch(FinEnergyHttpErr e) {verifyEq(e.status,504);verifyEq(e.code,"QUERY_TIMEOUT")}
    verifyNull(result);verifyEq(source.size,200);owner.close;verifyEq(budget.temporary.val,0)
  }
}

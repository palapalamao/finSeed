using haystack
using util
using concurrent

class FinEnergyOwnedJsonTest : Test
{
  Void testEscapesNestedArraysAndDuplicateKeysKeepTheExistingParserSemantics()
  {
    source:=Str:Obj?["quoted\"name:[],":"中文 🌍 \\\"","rows":[[:],Obj?[,],null,0f,true,false,[1,2]],"object":["a":1]]
    texts:=[JsonOutStream.writeJsonToStr(source),"{\"key\":{},\"key\":[]}","[[],{},[0,null],\"a:b,[x]\"]","null","42","\"plain\""]
    texts.each |text|
    {
      budget:=FinEnergyStreamBudget().state;owner:=FinEnergyPreparedOwner(budget)
      try
      {
        expected:=JsonInStream(text.in).readJson;actual:=FinEnergyOwnedJson.parse(text,owner)
        verifyEq(actual,expected);verify(owner.entries>=graph(actual));verifyEq(budget.temporary.val,owner.entries)
      }
      finally {owner.close}
      verifyEq(budget.temporary.val,0)
    }
  }
  Void testFolioMetadataAndNativeDecodeMatchWithoutClearingSourceFacts()
  {
    records:=[Etc.makeDict(["id":Ref("config"),"finEnergyKind":"calendar","finEnergyConfig":"{\"workHours\":[9,10],\"nested\":{\"value\":0}}"]),Etc.makeDict(["id":Ref("equip"),"equip":Marker.val,"navName":"设备 🌍","finEnergyKind":"meter","finEnergyPointRef":Ref("point")])]
    records.each |record|
    {
      expected:=FinEnergyRepo.decode(record);budget:=FinEnergyStreamBudget().state;owner:=FinEnergyPreparedOwner(budget);Map? actual
      try {actual=FinEnergyRepo.decodeOwned(record,owner);verifyEq(actual,expected);verifyEq(budget.temporary.val,owner.entries)}
      finally {owner.close}
      verify(actual.isEmpty);verifyEq(FinEnergyRepo.decode(record),expected);verifyEq(budget.temporary.val,0)
    }
  }
  Void testSyntaxAndDeadlineFailuresRemainDistinctAndReleaseOnlyTheirWorkspace()
  {
    budget:=FinEnergyStreamBudget().state;owner:=FinEnergyPreparedOwner(budget);peer:=FinEnergyPreparedOwner(budget);peer.hold(31)
    try
    {
      verifyErr(ParseErr#) {FinEnergyOwnedJson.parse("{\"unterminated\":[1,",owner)}
      owner.close;verifyEq(budget.temporary.val,peer.entries)
    }
    finally {owner.close;peer.close}
    calls:=AtomicInt();deadline:=FinEnergyCockpitDeadline(30sec,|->Int| {calls.incrementAndGet>2 ? 31sec.ticks : 0})
    timed:=FinEnergyPreparedOwner(FinEnergyStreamBudget(50000,200000,20000000,30sec,deadline).state)
    size:=30000;text:="x".padl(size,'x')
    try
    {
      try {FinEnergyOwnedJson.parse(text,timed);fail("The pre-scan must observe the shared deadline")}
      catch(FinEnergyHttpErr e) {verifyEq(e.status,504)}
    }
    finally {timed.close}
    verifyEq(timed.budget.temporary.val,0)
  }
  private Int graph(Obj? value)
  {
    if(value is Map) return ((Map)value).reduce(1+((Map)value).size) |Int n,Obj? v->Int| {n+graph(v)}
    if(value is List) return ((Obj?[])value).reduce(1+((List)value).size) |Int n,Obj? v->Int| {n+graph(v)}
    return 0
  }
  Void testFolioDecodeMustAdmitTheJsonTreeBeforeParsingIt()
  {
    source:=Str:Obj?[:];(0..<300).each |i| {source["field$i"]=i}
    record:=Etc.makeDict(["id":Ref("config"),"finEnergyKind":"calendar","finEnergyConfig":JsonOutStream.writeJsonToStr(source)])
    budget:=FinEnergyStreamBudget().state;output:=FinEnergyPreparedOwner(budget);peer:=FinEnergyPreparedOwner(budget)
    peer.hold(budget.remaining-32);held:=peer.entries
    try
    {
      verifyErr(FinEnergyHttpErr#) {FinEnergyRepo.decodeOwned(record,output)}
      verifyEq(peer.entries,held);output.close;verifyEq(budget.temporary.val,held)
      verifyEq(source.size,300)
    }
    finally {output.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }
}

using haystack
using util
using concurrent

class EnerCubixOwnedJsonTest : Test
{
  Void testEscapesNestedArraysAndDuplicateKeysKeepTheExistingParserSemantics()
  {
    source:=Str:Obj?["quoted\"name:[],":"中文 🌍 \\\"","rows":[[:],Obj?[,],null,0f,true,false,[1,2]],"object":["a":1]]
    texts:=[JsonOutStream.writeJsonToStr(source),"{\"key\":{},\"key\":[]}","[[],{},[0,null],\"a:b,[x]\"]","null","42","\"plain\""]
    texts.each |text|
    {
      budget:=EnerCubixStreamBudget().state;owner:=EnerCubixPreparedOwner(budget)
      try
      {
        expected:=JsonInStream(text.in).readJson;actual:=EnerCubixOwnedJson.parse(text,owner)
        verifyEq(actual,expected);verify(owner.entries>=graph(actual));verifyEq(budget.temporary.val,owner.entries)
      }
      finally {owner.close}
      verifyEq(budget.temporary.val,0)
    }
  }
  Void testFolioMetadataAndNativeDecodeMatchWithoutClearingSourceFacts()
  {
    records:=[Etc.makeDict(["id":Ref("config"),"enerCubixKind":"calendar","enerCubixConfig":"{\"workHours\":[9,10],\"nested\":{\"value\":0}}"]),Etc.makeDict(["id":Ref("equip"),"equip":Marker.val,"navName":"设备 🌍","enerCubixKind":"meter","enerCubixPointRef":Ref("point")])]
    records.each |record|
    {
      expected:=EnerCubixRepo.decode(record);budget:=EnerCubixStreamBudget().state;owner:=EnerCubixPreparedOwner(budget);Map? actual
      try {actual=EnerCubixRepo.decodeOwned(record,owner);verifyEq(actual,expected);verifyEq(budget.temporary.val,owner.entries)}
      finally {owner.close}
      verify(actual.isEmpty);verifyEq(EnerCubixRepo.decode(record),expected);verifyEq(budget.temporary.val,0)
    }
  }
  Void testSyntaxAndDeadlineFailuresRemainDistinctAndReleaseOnlyTheirWorkspace()
  {
    budget:=EnerCubixStreamBudget().state;owner:=EnerCubixPreparedOwner(budget);peer:=EnerCubixPreparedOwner(budget);peer.hold(31)
    try
    {
      verifyErr(ParseErr#) {EnerCubixOwnedJson.parse("{\"unterminated\":[1,",owner)}
      owner.close;verifyEq(budget.temporary.val,peer.entries)
    }
    finally {owner.close;peer.close}
    calls:=AtomicInt();deadline:=EnerCubixCockpitDeadline(30sec,|->Int| {calls.incrementAndGet>2 ? 31sec.ticks : 0})
    timed:=EnerCubixPreparedOwner(EnerCubixStreamBudget(50000,200000,20000000,30sec,deadline).state)
    size:=30000;text:="x".padl(size,'x')
    try
    {
      try {EnerCubixOwnedJson.parse(text,timed);fail("The pre-scan must observe the shared deadline")}
      catch(EnerCubixHttpErr e) {verifyEq(e.status,504)}
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
    record:=Etc.makeDict(["id":Ref("config"),"enerCubixKind":"calendar","enerCubixConfig":JsonOutStream.writeJsonToStr(source)])
    budget:=EnerCubixStreamBudget().state;output:=EnerCubixPreparedOwner(budget);peer:=EnerCubixPreparedOwner(budget)
    peer.hold(budget.remaining-32);held:=peer.entries
    try
    {
      verifyErr(EnerCubixHttpErr#) {EnerCubixRepo.decodeOwned(record,output)}
      verifyEq(peer.entries,held);output.close;verifyEq(budget.temporary.val,held)
      verifyEq(source.size,300)
    }
    finally {output.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }
}

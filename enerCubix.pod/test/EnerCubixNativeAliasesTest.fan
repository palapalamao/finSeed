using util

class EnerCubixNativeAliasesTest : Test
{
  Void testMappingIsReadAndAdmittedOnceForAllEquipmentInOneRequest()
  {
    scope:=EnerCubixCockpitRequestScope("alias-map","a");peer:=EnerCubixPreparedOwner(scope.stream.state);peer.hold(31)
    work:=scope.preparationWorkspace;aliases:=EnerCubixNativeAliases(work);calls:=0;json:=Str:Str[:]
    116.times |i| {json["legacy$i"]="native$i"}
    source:=JsonOutStream.writeJsonToStr(json);Map? first;held:=0
    try
    {
      281.times |i|
      {
        value:=aliases.read |->Str| {calls++;return source}
        if(i==0) {first=value;held=work.entries}
        verify(value===first);verifyEq(value["legacy115"],"native115");verifyEq(work.entries,held)
      }
      verifyEq(calls,1)
      frozen:=scope.freezeInputs([:],[:],[["id":"native115","aliases":first]])
      verify(first.isEmpty);verifyEq(((Map)((Map)((List)frozen["records"]).first)["aliases"])["legacy115"],"native115")
      verifyErr(ArgErr#) {aliases.read |->Str| {fail("Closed mapping must not read");return "{}"}}
      scope.close;verifyEq(scope.stream.state.temporary.val,peer.entries)
    }
    finally {scope.close;peer.close}
  }
  Void testAdmissionFailurePrecedesTheNativeConfigurationCallback()
  {
    scope:=EnerCubixCockpitRequestScope("alias-map-limit","a");work:=scope.preparationWorkspace;peer:=EnerCubixPreparedOwner(scope.stream.state);calls:=0
    try
    {
      peer.hold(scope.stream.state.remaining);held:=peer.entries
      verifyErr(EnerCubixHttpErr#) {unexpected:=EnerCubixNativeAliases(work);unexpected.read |->Str| {calls++;return "{}"}}
      verifyEq(calls,0);scope.close;verifyEq(scope.stream.state.temporary.val,held)
    }
    finally {scope.close;peer.close}
  }
}

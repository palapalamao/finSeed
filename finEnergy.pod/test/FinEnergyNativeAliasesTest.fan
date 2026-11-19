using util

class FinEnergyNativeAliasesTest : Test
{
  Void testMappingIsReadAndAdmittedOnceForAllEquipmentInOneRequest()
  {
    scope:=FinEnergyCockpitRequestScope("alias-map","a");peer:=FinEnergyPreparedOwner(scope.stream.state);peer.hold(31)
    work:=scope.preparationWorkspace;aliases:=FinEnergyNativeAliases(work);calls:=0;json:=Str:Str[:]
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
    scope:=FinEnergyCockpitRequestScope("alias-map-limit","a");work:=scope.preparationWorkspace;peer:=FinEnergyPreparedOwner(scope.stream.state);calls:=0
    try
    {
      peer.hold(scope.stream.state.remaining);held:=peer.entries
      verifyErr(FinEnergyHttpErr#) {unexpected:=FinEnergyNativeAliases(work);unexpected.read |->Str| {calls++;return "{}"}}
      verifyEq(calls,0);scope.close;verifyEq(scope.stream.state.temporary.val,held)
    }
    finally {scope.close;peer.close}
  }
}

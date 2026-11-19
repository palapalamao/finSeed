class FinEnergyRestTest : Test
{
  Void testNativeEntryUsesVersionedCockpit()
  {
    verifyEq(FinEnergyExt.appUri("cubeTest").toStr,
      "/pod/finEnergy/res/web/finEnergy/index-${FinEnergyLib#.pod.version}.html#/cockpit?project=cubeTest")
  }

  Void testShortJsonBody()
  {
    text := "{\"名称\":\"能耗\"}"
    verifyEq(FinEnergyRest.readBody(text.in),text)
    verifyEq(FinEnergyRest.readBody("".in),"")
  }
  Void testBoundedBody()
  {
    verifyEq(FinEnergyRest.readBody("abc".in,3),"abc")
    verifyErr(FinEnergyHttpErr#) { FinEnergyRest.readBody("abcd".in,3) }
  }

  Void testOnlyAssetUploadHasLargerByteBoundedTransport()
  {
    verifyEq(FinEnergyRest.bodyLimit("cockpit/assets/upload"),3145728)
    verifyEq(FinEnergyRest.bodyLimit("records"),2097152)
    verifyEq(FinEnergyRest.bodyLimit("cockpit"),2097152)
    verifyEq(FinEnergyRest.readBody("中文".in,6,true),"中文")
    verifyErr(FinEnergyHttpErr#) {FinEnergyRest.readBody("中文".in,5,true)}
    ["cockpit/assets/upload","cockpit/assets/save","cockpit/assets/select","cockpit/assets/delete"].each |route| {verify(!FinEnergyRest.readPost(route))}
  }
  Void testOnlyExplicitReadPostsBypassWritePermission()
  {
    ["report","cockpit","cleaning/preview"].each |route| { verify(FinEnergyRest.readPost(route)) }
    ["records","records/delete","tasks","alarms/ack","tree/manage","cockpit/save","cockpit/budgets/save","cockpit/budgets/delete","cockpit/rule-profiles/save","cockpit/rule-profiles/delete"].each |route| { verify(!FinEnergyRest.readPost(route)) }
  }
}

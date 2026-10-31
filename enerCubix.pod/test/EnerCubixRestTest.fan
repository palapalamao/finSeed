class EnerCubixRestTest : Test
{
  Void testNativeEntryUsesVersionedCockpit()
  {
    verifyEq(EnerCubixExt.appUri("cubeTest").toStr,
      "/pod/enerCubix/res/web/enerCubix/index-${EnerCubixLib#.pod.version}.html#/cockpit?project=cubeTest")
  }

  Void testShortJsonBody()
  {
    text := "{\"名称\":\"能耗\"}"
    verifyEq(EnerCubixRest.readBody(text.in),text)
    verifyEq(EnerCubixRest.readBody("".in),"")
  }
  Void testBoundedBody()
  {
    verifyEq(EnerCubixRest.readBody("abc".in,3),"abc")
    verifyErr(EnerCubixHttpErr#) { EnerCubixRest.readBody("abcd".in,3) }
  }

  Void testOnlyAssetUploadHasLargerByteBoundedTransport()
  {
    verifyEq(EnerCubixRest.bodyLimit("cockpit/assets/upload"),3145728)
    verifyEq(EnerCubixRest.bodyLimit("records"),2097152)
    verifyEq(EnerCubixRest.bodyLimit("cockpit"),2097152)
    verifyEq(EnerCubixRest.readBody("中文".in,6,true),"中文")
    verifyErr(EnerCubixHttpErr#) {EnerCubixRest.readBody("中文".in,5,true)}
    ["cockpit/assets/upload","cockpit/assets/save","cockpit/assets/select","cockpit/assets/delete"].each |route| {verify(!EnerCubixRest.readPost(route))}
  }
  Void testOnlyExplicitReadPostsBypassWritePermission()
  {
    ["report","cockpit","cleaning/preview"].each |route| { verify(EnerCubixRest.readPost(route)) }
    ["records","records/delete","tasks","alarms/ack","tree/manage","cockpit/save"].each |route| { verify(!EnerCubixRest.readPost(route)) }
  }
}

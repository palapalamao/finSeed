class EnerCubixRestTest : Test
{
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

  Void testOnlyExplicitReadPostsBypassWritePermission()
  {
    ["report","cockpit","cleaning/preview"].each |route| { verify(EnerCubixRest.readPost(route)) }
    ["records","records/delete","tasks","alarms/ack","tree/manage","cockpit/save"].each |route| { verify(!EnerCubixRest.readPost(route)) }
  }
}

class SeedRestTest : Test
{
  Void testShortJsonBody()
  {
    text := "{\"名称\":\"能耗\"}"
    verifyEq(SeedRest.readBody(text.in),text)
    verifyEq(SeedRest.readBody("".in),"")
  }
  Void testBoundedBody()
  {
    verifyEq(SeedRest.readBody("abc".in,3),"abc")
    verifyErr(SeedHttpErr#) { SeedRest.readBody("abcd".in,3) }
  }
}

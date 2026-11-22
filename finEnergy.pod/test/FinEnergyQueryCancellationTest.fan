class FinEnergyQueryCancellationTest : Test
{
  Void testOnlyOwnerCanCancelAndClosingReleasesTheId()
  {
    id:="0123456789abcdef0123456789abcdef"
    query:=FinEnergyQueryCancellation.open("one","alice",id)
    try
    {
      verify(!FinEnergyQueryCancellation.cancel("two","alice",id))
      verify(!FinEnergyQueryCancellation.cancel("one","bob",id))
      query.check
      verifyErr(FinEnergyHttpErr#) {FinEnergyQueryCancellation.open("one","alice",id)}
      verify(FinEnergyQueryCancellation.cancel("one","alice",id))
      verifyErr(FinEnergyHttpErr#) {query.check}
    }
    finally {query.close}
    verify(!FinEnergyQueryCancellation.cancel("one","alice",id))
    fresh:=FinEnergyQueryCancellation.open("one","alice",id)
    try {fresh.check}
    finally {fresh.close}
  }

  Void testCancellationAndDeadlineAreIndependent()
  {
    id:="0123456789abcdef0123456789abcdef"
    query:=FinEnergyQueryCancellation.open("two","alice",id)
    try
    {
      guard:=FinEnergyCockpitDeadline(null,|->Int| {Duration.nowTicks},query)
      guard.check
      FinEnergyQueryCancellation.cancel("two","alice",id)
      verifyErr(FinEnergyHttpErr#) {guard.check}
    }
    finally {query.close}
  }
}

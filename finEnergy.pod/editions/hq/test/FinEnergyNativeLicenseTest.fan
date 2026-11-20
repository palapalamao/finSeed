using fin

class FinEnergyNativeLicenseTest : Test
{
  Void testNativeFacetAndFailClosed()
  {
    FinExtMeta meta:=FinEnergyExt#.facet(FinExtMeta#)
    verifyEq(meta.licFeature,FinEnergyNativeLicense.feature)
    verifyEq(meta.licFeature,"fin energy")
    verify(FinEnergyExt#.fits(FinExt#))
    verifyNotNull(FinLicenseChecker.check(meta,FinLicense[,],0))
  }

  Void testReadOnlyStatusClassification()
  {
    verifyEq(FinEnergyNativeLicense.classify(null,true,true),"active")
    verifyEq(FinEnergyNativeLicense.classify(null,false,true),"inactive")
    verifyEq(FinEnergyNativeLicense.classify("expired",true,true),"invalid")
    verifyEq(FinEnergyNativeLicense.classify("feature missing",true,false),"missingFeature")
    verifyEq(FinEnergyNativeLicense.classify(null,false,false),"missingFeature")
  }
}

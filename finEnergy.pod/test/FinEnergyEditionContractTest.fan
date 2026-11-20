class FinEnergyEditionContractTest : Test
{
  Void testEditionIsCompileTimeAndMatchesPackageMetadata()
  {
    edition:=FinEnergyEditionLicense.edition
    verify(["china","hq"].contains(edition))
    verifyEq(FinEnergyEditionLicense.licenseMode,edition=="china" ? "selfManaged" : "finNative")
    verifyEq(FinEnergyExt#.pod.meta["finEnergy.edition"],edition)
    verifyEq(FinEnergyExt#.pod.meta["finEnergy.licenseMode"],FinEnergyEditionLicense.licenseMode)
  }

  Void testOnlyTheSelectedLicenseImplementationIsPackaged()
  {
    china:=FinEnergyEditionLicense.edition=="china"
    verifyEq(FinEnergyExt#.base.qname,china ? "skyarcd::Ext" : "fin::FinExt")
    verifyEq(Type.find("finEnergy::FinEnergyLicenseStore",false)!=null,china)
    verifyEq(Type.find("finEnergy::FinEnergyLicenseGrant",false)!=null,china)
    verifyEq(Type.find("finEnergy::FinEnergyLicenseQuota",false)!=null,china)
    verifyEq(Type.find("finEnergy::FinEnergyNativeLicense",false)!=null,!china)
    verifyEq(FinEnergyExt#.pod.file(`/res/license-keys.json`,false)!=null,china)
  }
}

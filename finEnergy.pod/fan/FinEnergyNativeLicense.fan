using fin
using skyarcd

** FIN owns activation, expiry and feature validation. There is no application
** license file, local trial override or fallback to a legacy RSA grant.
internal class FinEnergyNativeLicense
{
  ** Proposed HQ token: release requires confirmation and a real FIN grant.
  ** Keep this equal to the FinExtMeta facet; changing it requires a new build.
  static const Str feature := "fin energy"

  static Bool allowed(Context cx)
  {
    ext:=cx.proj.ext("finEnergy",false) as FinExt
    return ext != null && allowedExt(ext)
  }

  static Bool allowedExt(FinExt ext)
  {
    if (!ext.isRunning) return false
    try { return FinLicenseChecker.checkExt(ext,StackHubFinLicense.findLicenses(ext)) == null }
    catch (Err e) { return false }
  }

  static Str:Obj? status(Context cx)
  {
    ext:=cx.proj.ext("finEnergy",false) as FinExt
    state:="inactive"
    if (ext != null)
    {
      try
      {
        licenses:=StackHubFinLicense.findLicenses(ext)
        fault:=FinLicenseChecker.checkExt(ext,licenses)
        hasFeature:=licenses.any |license| { (license.prop("features") ?: "").split(',').contains(feature) }
        state=classify(fault,ext.isRunning,hasFeature)
      }
      catch (Err e) { state="invalid" }
    }
    result:=Str:Obj?["source":"fin","status":state,"feature":feature,"canManageFinLicense":cx.user.isSu]
    if (state != "active") result["reason"]="nativeLicenseRequired"
    if (cx.user.isAdmin || cx.user.isSu)
    {
      try { result["hostId"]=cx.sys.host.hostId.toStr }
      catch (Err e) { /* Host identity is optional; activation always fails closed. */ }
    }
    return result
  }

  internal static Str classify(Str? fault,Bool running,Bool hasFeature)
  {
    if (!hasFeature) return "missingFeature"
    if (fault != null) return "invalid"
    return running ? "active" : "inactive"
  }
}

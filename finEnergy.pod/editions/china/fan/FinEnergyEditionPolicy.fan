using folio
using skyarcd

** China edition: the original instance-wide RSA product grant and per-project
** ten-meter allowance. No native FIN feature gate or HQ license fallback.
internal class FinEnergyEditionPolicy
{
  static const Str edition := "china"
  static const Str licenseMode := "selfManaged"
  static const Str calculationReason := "licenseProjectOverLimit"
  static Bool allowed(Context cx) { FinEnergyLicenseQuota.allowed(cx.sys,cx.db) }
  static Bool allowedExt(FinEnergyExt ext)
  { ext.isRunning && FinEnergyLicenseQuota.allowed(ext.proj.sys,ext.rt.db) }
  // An expired/over-quota project must remain administrable, especially for
  // unenrollment. Transactional quota checks still reject any meter increase.
  static Bool configurationAllowed(Context cx) { true }
  static Str:Obj? status(Context cx)
  {
    result:=FinEnergyLicenseStore.forSys(cx.sys).status(FinEnergyLicenseStore.hostId(cx.sys),
      FinEnergyLicenseQuota.used(cx.db),cx.user.isAdmin || cx.user.isSu,cx.user.isSu)
    result["source"]="product"
    return result
  }
  static Void install(Context cx,Obj? raw)
  {
    if (!cx.user.isSu) throw FinEnergyHttpErr(403,"PERMISSION","licenseImportForbidden")
    FinEnergyLicenseStore.forSys(cx.sys).install(raw as Str ?: throw FinEnergyLicenseGrant.invalid,
      FinEnergyLicenseStore.hostId(cx.sys))
  }
  static Void remove(Context cx,Obj? token)
  {
    if (!cx.user.isSu) throw FinEnergyHttpErr(403,"PERMISSION","licenseDeleteForbidden")
    FinEnergyLicenseStore.forSys(cx.sys).remove(token as Str)
  }
  static Bool requiresRevision(Context cx,Diff[] changes) { FinEnergyLicenseQuota.requiresRevision(cx.db,changes) }
  static Void checkWrite(Context cx,Diff[] changes) { FinEnergyLicenseQuota.checkWrite(cx.sys,cx.db,changes) }
  static Void checkMigration(Context cx,[Str:Obj?][] input,Str:Obj? plan)
  { FinEnergyLicenseQuota.checkMigration(cx.sys,cx.db,input,plan) }
}

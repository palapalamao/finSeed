using folio
using skyarcd

** Headquarters edition: native FIN feature validation only. RSA grants and
** ten-meter trial behavior are not compiled into this edition.
internal class FinEnergyEditionPolicy
{
  static const Str edition := "hq"
  static const Str licenseMode := "finNative"
  static const Str calculationReason := "nativeLicenseRequired"
  static Bool allowed(Context cx) { FinEnergyNativeLicense.allowed(cx) }
  static Bool allowedExt(FinEnergyExt ext) { FinEnergyNativeLicense.allowedExt(ext) }
  static Bool configurationAllowed(Context cx) { allowed(cx) }
  static Str:Obj? status(Context cx) { FinEnergyNativeLicense.status(cx) }
  static Void install(Context cx,Obj? raw) { throw FinEnergyHttpErr(403,"LICENSE_MANAGED_BY_FIN","nativeLicenseManaged") }
  static Void remove(Context cx,Obj? token) { throw FinEnergyHttpErr(403,"LICENSE_MANAGED_BY_FIN","nativeLicenseManaged") }
  static Bool requiresRevision(Context cx,Diff[] changes) { false }
  static Void checkWrite(Context cx,Diff[] changes) {}
  static Void checkMigration(Context cx,[Str:Obj?][] input,Str:Obj? plan) {}
}

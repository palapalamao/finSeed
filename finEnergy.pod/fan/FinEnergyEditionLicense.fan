using folio
using skyarcd

** Build-selected policy. The customer cannot change edition through a request,
** project tag, browser preference or a second licensing fallback.
internal class FinEnergyEditionLicense
{
  static Str edition() { FinEnergyEditionPolicy.edition }
  static Str licenseMode() { FinEnergyEditionPolicy.licenseMode }
  static Bool allowed(Context cx) { FinEnergyEditionPolicy.allowed(cx) }
  static Bool allowedExt(FinEnergyExt ext) { FinEnergyEditionPolicy.allowedExt(ext) }
  static Bool configurationAllowed(Context cx) { FinEnergyEditionPolicy.configurationAllowed(cx) }
  static Str calculationReason() { FinEnergyEditionPolicy.calculationReason }
  static Str:Obj? status(Context cx)
  { FinEnergyEditionPolicy.status(cx).set("edition",edition).set("licenseMode",licenseMode) }
  static Void install(Context cx,Obj? raw) { FinEnergyEditionPolicy.install(cx,raw) }
  static Void remove(Context cx,Obj? token) { FinEnergyEditionPolicy.remove(cx,token) }
  static Bool requiresRevision(Context cx,Diff[] changes) { FinEnergyEditionPolicy.requiresRevision(cx,changes) }
  static Void checkWrite(Context cx,Diff[] changes) { FinEnergyEditionPolicy.checkWrite(cx,changes) }
  static Void checkMigration(Context cx,[Str:Obj?][] input,Str:Obj? plan)
  { FinEnergyEditionPolicy.checkMigration(cx,input,plan) }
}

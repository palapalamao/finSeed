using web
using hx
using skyarcd
using concurrent

@ExtMeta { name="enerCubix"; depends=["haystack","finstack"] }
const class EnerCubixExt : Ext, Weblet
{
  const EnerCubixRest rest := EnerCubixRest()
  private const AtomicInt lastRollup := AtomicInt(-1)

  override Duration? houseKeepingFreq() { 1sec }

  override Void onHouseKeeping()
  {
    if (!isRunning) return
    now:=Duration.nowTicks
    if (!EnerCubixMeterRollup.isDue(lastRollup.val,now,EnerCubixMeterRollup.configuredInterval(rt.db))) return
    if (EnerCubixLicenseQuota.allowed(proj.sys,rt.db)) EnerCubixMeterRollup.update(rt.db)
    lastRollup.val=now
  }

  override Void onService()
  {
    cx := Context.cur
    if (cx.user.isGuest) { res.sendErr(401); return }
    path := req.modRel.path
    if (!path.isEmpty && path.first == "v1") { rest.onService; return }
    if (path.isEmpty || path == ["index.html"])
    {
      if (req.method != "GET") { res.sendErr(405); return }
      res.headers["Cache-Control"]="no-store"
      res.redirect(appUri(cx.proj.name),302)
      return
    }
    res.sendErr(404)
  }

  internal static Uri appUri(Str project)
  { ("/pod/enerCubix/res/web/enerCubix/index-${EnerCubixLib#.pod.version}.html#/cockpit?project="+project).toUri }
}

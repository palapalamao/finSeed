using web
using hx
using skyarcd
using concurrent
using fin

@ExtMeta { name="finEnergy"; depends=["haystack","finstack"] }
@FinExtMeta { licFeature="fin energy" }
const class FinEnergyExt : FinExt, Weblet
{
  const FinEnergyRest rest := FinEnergyRest()
  private const AtomicInt lastRollup := AtomicInt(-1)

  override Duration? houseKeepingFreq() { 1sec }

  override Void onHouseKeeping()
  {
    if (!isRunning || !FinEnergyNativeLicense.allowedExt(this)) return
    if (FinEnergyNamespace.needsMigration(rt.db)) return
    now:=Duration.nowTicks
    if (!FinEnergyMeterRollup.isDue(lastRollup.val,now,FinEnergyMeterRollup.configuredInterval(rt.db))) return
    FinEnergyMeterRollup.update(rt.db)
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
  { ("/pod/finEnergy/res/web/finEnergy/index-${FinEnergyLib#.pod.version}.html#/cockpit?project="+project).toUri }
}

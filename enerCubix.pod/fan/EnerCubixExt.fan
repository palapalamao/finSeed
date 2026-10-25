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
    EnerCubixMeterRollup.update(rt.db)
    EnerCubixMeterGeneration.update(rt.db)
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
      res.redirect(("/pod/enerCubix/res/web/enerCubix/index.html#/dashboard?project="+cx.proj.name).toUri,302)
      return
    }
    res.sendErr(404)
  }
}

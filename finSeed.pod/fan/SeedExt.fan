using web
using hx
using skyarcd

@ExtMeta { name="finSeed"; depends=["haystack","finstack"] }
const class SeedExt : Ext, Weblet
{
  const SeedRest rest := SeedRest()

  override Void onService()
  {
    cx := Context.cur
    if (cx.user.isGuest) { res.sendErr(401); return }
    path := req.modRel.path
    if (!path.isEmpty && path.first == "v1") { rest.onService; return }
    if (path.isEmpty || path == ["index.html"])
    {
      if (req.method != "GET") { res.sendErr(405); return }
      res.redirect(("/pod/finSeed/res/web/seed/index.html#/dashboard?project="+cx.proj.name).toUri,302)
      return
    }
    res.sendErr(404)
  }
}

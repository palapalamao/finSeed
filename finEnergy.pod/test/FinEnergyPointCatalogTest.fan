using haystack
using folio

class FinEnergyPointCatalogTest : Test
{
  Void testExactResolutionIsOrderedDeduplicatedAndPermissionSafe()
  {
    withDb |db|
    {
      add(db,"eq",["equip":Marker.val,"dis":"Air handler"])
      add(db,"p",["point":Marker.val,"equipRef":Ref("eq"),"his":Marker.val,"hisMode":"cov","unit":"kWh"])
      db.commit(Diff(db.readById(Ref("p")),Etc.makeDict(["hisStatus":"ok","hisErr":"status detail","hisCollectLastTime":at]),Diff.transient))
      add(db,"hidden",["point":Marker.val,"his":Marker.val])
      add(db,"computed",["point":Marker.val,"finEnergyComputed":Marker.val])
      before:=db.readAllList(Filter.has("point")).size
      items:=FinEnergyMath.maps(FinEnergyPointCatalog.resolve(db,|Dict r->Bool| {r.id.id!="hidden"},["ids":["p","hidden","missing","eq","p","computed"]])["items"])
      verifyEq(items.size,1); p:=items.first
      verifyEq(p["id"],"p"); verifyEq(p["equipId"],"eq"); verifyEq(p["equipName"],"Air handler")
      verifyEq(p["hisMode"],"cov");verifyEq(p["hisStatus"],"ok");verifyEq(p["hisErr"],"status detail")
      verifyEq(p["hisLastCollect"],at.toIso)
      // FIN synthesizes read-only hisStart/hisEnd. Verify projection without
      // trying to persist or fabricate native history in the Folio fixture.
      nativePoint:=Etc.makeDict(Etc.dictToMap(db.readById(Ref("p"))).setAll(["hisStart":at,"hisEnd":at+1day]))
      projected:=FinEnergyPointCatalog(db,|Dict r->Bool| {true}).project(nativePoint)
      verifyEq(projected["hisStart"],at.toIso);verifyEq(projected["hisEnd"],(at+1day).toIso)
      verifyEq(db.readAllList(Filter.has("point")).size,before)
      hiddenOwner:=FinEnergyMath.maps(FinEnergyPointCatalog.resolve(db,|Dict r->Bool| {r.id.id!="eq"},["ids":["p"]])["items"]).first
      verifyNull(hiddenOwner["equipId"]);verifyNull(hiddenOwner["equipName"])
    }
  }
  Void testEquipmentFilterKeepsAllPagesAndExactCandidates()
  {
    withDb |db|
    {
      add(db,"eq",["equip":Marker.val]);add(db,"other",["equip":Marker.val])
      add(db,"a",["point":Marker.val,"equipRef":Ref("eq"),"dis":"Main energy"])
      add(db,"b",["point":Marker.val,"equipRef":Ref("eq"),"dis":"Temperature"])
      add(db,"c",["point":Marker.val,"equipRef":Ref("other")])
      result:=FinEnergyPointCatalog.page(db,|Dict r->Bool| {true},"",0,1,"eq")
      verifyEq(result["total"],2);verifyEq(FinEnergyMath.maps(result["items"]).size,1)
      next:=FinEnergyPointCatalog.page(db,|Dict r->Bool| {true},"",1,1,"eq")
      verifyEq(next["total"],2);verifyNotEq(FinEnergyMath.maps(result["items"]).first["id"],FinEnergyMath.maps(next["items"]).first["id"])
      verifyEq(FinEnergyPointCatalog.page(db,|Dict r->Bool| {true},"Main",0,20,"eq")["total"],1)
      verifyEq(FinEnergyPointCatalog.page(db,|Dict r->Bool| {r.id.id!="eq"},"",0,20,"eq")["total"],0)
    }
  }
  Void testBatchTransportIsBoundedAndRejectsUnexpectedFields()
  {
    withDb |db|
    {
      check:=|Dict r->Bool| {true}
      verifyErr(ArgErr#) {FinEnergyPointCatalog.resolve(db,check,["ids":(0..<201).map |n->Str| {"p$n"}])}
      verifyErr(ArgErr#) {FinEnergyPointCatalog.resolve(db,check,["ids":[1]])}
      verifyErr(ArgErr#) {FinEnergyPointCatalog.resolve(db,check,["ids":["a"],"write":true])}
      verifyEq(FinEnergyMath.maps(FinEnergyPointCatalog.resolve(db,check,["ids":Str[,]])["items"]).size,0)
      verify(FinEnergyRest.readPost("points/resolve"))
    }
  }
  private static const DateTime at:=DateTime.fromIso("2026-11-01T00:00:00Z")
  private Void add(Folio db,Str id,Str:Obj? tags) {db.commit(Diff.makeAdd(Etc.makeDict(tags),Ref(id)))}
  private Void withDb(|Folio| work)
  {
    dir:=Env.cur.tempDir+`finEnergy-points-test-${Uuid()}/`;dir.create
    db:=(Folio)Type.find("hxFolio::HxFolio").method("open").call(FolioConfig {name="pointCatalogTest";it.dir=dir;log=Log.get("pointCatalogTest")})
    try {work(db)} finally {db.close;dir.delete}
  }
}

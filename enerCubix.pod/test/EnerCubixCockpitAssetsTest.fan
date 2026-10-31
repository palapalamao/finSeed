using haystack
using folio
using folio3
using concurrent
using [java] java.util.concurrent::CountDownLatch
using [java] java.util.concurrent::TimeUnit
using [java] javax.imageio::ImageIO
using [java] java.awt.image::BufferedImage
using [java] java.awt::Color
using util
using [java] fanx.interop::Interop

class EnerCubixCockpitAssetsTest : Test
{
  Folio? database
  File? home
  private Folio db() {database}
  private Ref site() {Ref("p:test:r:site")}
  private Ref floor() {Ref("p:test:r:floor")}
  override Void setup()
  {
    home=Env.cur.tempDir+("enerCubix-assets-"+Uuid()+"/").toUri
    database=Folio3.open(FolioConfig {it.dir=home+Uri.fromStr("db/");it.idPrefix="p:test:r:"})
    db.commitAll([Diff.makeAdd(Etc.makeDict(["site":Marker.val,"dis":"真实站点"]),site.toRel("p:test:r:")),Diff.makeAdd(Etc.makeDict(["floor":Marker.val,"siteRef":site,"dis":"真实楼层"]),floor.toRel("p:test:r:")),Diff.makeAdd(Etc.makeDict(["equip":Marker.val,"floorRef":floor,"enerCubixPointRef":Ref("point")]),Ref("equip")),Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"equipRef":Ref("equip")]),Ref("point"))])
  }
  override Void teardown() {database?.close}
  private EnerCubixCockpitAssets store(Bool admin:=true,Str[] hidden:=Str[,],Str[] locked:=Str[,])
  {EnerCubixCockpitAssets.withStore(db,home,Ref("p:test"),"test","su",admin,|Dict r->Bool| {!hidden.contains(r.id.id)},|Dict r->Bool| {!locked.contains(r.id.id)})}
  private Str:Obj? uploadBody(Str:Obj? state:=Str:Obj?[:])
  {["manifestMod":state["manifestMod"],"scopeId":site.id,"name":"测试平面图.png","base64":bitmap.toBase64]}
  private Str:Obj? first(Str:Obj? state) {EnerCubixMath.maps(state["items"]).first}
  private Str:Obj? edit(Str:Obj? state,Obj? spots:=null)
  {r:=first(state);return ["id":r["id"],"mod":r["mod"],"manifestMod":state["manifestMod"],"scopeId":r["scopeId"],"name":r["name"],"hotspots":spots ?: [["spaceId":floor.id,"x":0.25f,"y":0.75f]]]}
  private Buf bitmap(Int width:=13,Int height:=7,Str format:="png")
  {out:=Buf();verify(ImageIO.write(BufferedImage(width,height,BufferedImage.TYPE_INT_RGB),format,Interop.toJava(out.out)));return out.flip}

  Void testSerializedBrowserFixtureKeepsNativeReferencesAndImageHash()
  {
    dir:=Env.cur.tempDir+("enerCubix-assets-browser-"+Uuid()+"/").toUri
    data:=Folio3.open(FolioConfig {it.dir=dir+Uri.fromStr("db/");it.idPrefix="p:testproject:r:"})
    try
    {
      data.commitAll([Diff.makeAdd(Etc.makeDict(["site":Marker.val,"dis":"Site"]),Ref("s")),Diff.makeAdd(Etc.makeDict(["floor":Marker.val,"dis":"Floor","siteRef":Ref("s")]),Ref("f"))])
      api:=EnerCubixCockpitAssets.withStore(data,dir,Ref("p:testproject"),"testproject","su",true,|Dict r->Bool| {true},|Dict r->Bool| {true})
      image:=BufferedImage(1200,600,BufferedImage.TYPE_INT_RGB);g:=image.createGraphics
      g.setColor(Color(235,244,245));g.fillRect(0,0,1200,600);g.setColor(Color(255,255,255));g.fillRect(40,40,520,520);g.fillRect(640,40,520,520);g.setColor(Color(110,155,166));g.drawRect(40,40,520,520);g.drawRect(640,40,520,520);g.dispose
      bytes:=Buf();verify(ImageIO.write(image,"png",Interop.toJava(bytes.out)));bytes.flip
      state:=api.upload(["scopeId":"p:testproject","name":"空间示意.png","base64":bytes.toBase64])
      item:=first(state)
      state=api.save(["id":item["id"],"mod":item["mod"],"manifestMod":state["manifestMod"],"scopeId":item["scopeId"],"name":item["name"],"hotspots":[["spaceId":"p:testproject:r:s","x":0.25f,"y":0.5f],["spaceId":"p:testproject:r:f","x":0.75f,"y":0.5f]]])
      item=first(state);served:=api.image(item["id"].toStr,item["hash"].toStr)
      verifyEq(state["projectId"],"p:testproject");verifyEq(EnerCubixMath.maps(item["hotspots"]).map |row->Str| {row["spaceId"].toStr},["p:testproject:r:s","p:testproject:r:f"])
      verifyEq(((Buf)served["bytes"]).toDigest("SHA-256").toHex,item["hash"])
      output:=Env.cur.vars["ENERCUBIX_ASSET_FIXTURE_DIR"]
      if(output != null)
      {
        folder:=File.os(output);folder.create
        stream:=(folder+Uri.fromStr("cockpit-assets-response.json")).out;try{JsonOutStream(stream).writeJson(state)}finally{stream.close}
        stream=(folder+Uri.fromStr("cockpit-space-asset.png")).out;try{stream.writeBuf((Buf)served["bytes"])}finally{stream.close}
      }
    }
    finally {data.close}
  }
  Void testReadNeverCreatesAttachmentsOrFolioConfiguration()
  {
    before:=db.readAllList(Filter.has("id")).size
    state:=store.list
    verify(EnerCubixMath.maps(state["items"]).isEmpty);verifyNull(state["manifestMod"]);verifyNull(state["selectedId"])
    verify(!(home+Uri.fromStr("enerCubix-private/")).exists)
    verifyEq(db.readAllList(Filter.has("id")).size,before)
  }
  Void testNativeRefHotspotsPersistImageReadAndAuditWithoutBusinessMutations()
  {
    businessBefore:=db.readAllList(Filter("site or floor or equip or point")).map |r| {Etc.dictToMap(r)}
    state:=store.upload(uploadBody);item:=first(state)
    verifyEq(item["width"],13);verifyEq(item["height"],7);verifyEq(item["mime"],"image/png");verifyEq(state["selectedId"],item["id"])
    image:=store.image(item["id"].toStr,item["hash"].toStr);verifyEq(((Buf)image["bytes"]).toDigest("SHA-256").toHex,item["hash"])
    state=store.save(edit(state));item=first(state)
    saved:=db.readById(Ref(item["id"].toStr))
    verifyEq(saved["enerCubixHotspotRefs"],[floor]);verifyEq(saved["enerCubixHotspotX"],[Number(0.25f)])
    verifyEq(EnerCubixMath.maps(item["hotspots"]).first["spaceId"],floor.id)
    verifyEq(db.readAllList(Filter("site or floor or equip or point")).map |r| {Etc.dictToMap(r)},businessBefore)
    audits:=db.readAllList(Filter.has("enerCubixCockpitAssetAudit"));verifyEq(audits.size,2)
    audits.each |r| {verifyEq(r["enerCubixAssetActor"],"su");verify(!r.has("base64"));verify(r["enerCubixAssetNativeRefs"] is List)}
    verifyErr(EnerCubixHttpErr#) {store.image(item["id"].toStr,"wrong-version")}
  }
  Void testPngAndJpegAreReencodedAndTrailingPolyglotIsRemoved()
  {
    ["png","jpeg"].each |format|
    {
      original:=bitmap(13,7,format);raw:=original.dup;raw.seek(raw.size).print("<script>ASSET_SENTINEL</script>")
      image:=EnerCubixCockpitImage(raw.toBase64)
      verifyEq(image.width,13);verifyEq(image.height,7);verifyEq(image.mime,format == "png" ? "image/png" : "image/jpeg")
      verify(!image.bytes.toBase64.contains("QVNTRVRfU0VOVElORUw"))
      verify(image.bytes.size < raw.size);verify(image.bytes.toDigest("SHA-256") != raw.toDigest("SHA-256"))
    }
    ["<svg onload='alert(1)'/>","<html>script</html>","not a bitmap"].each |body| {verifyErr(ArgErr#) {ignored:=EnerCubixCockpitImage(body.toBuf.toBase64)}}
    verifyErr(ArgErr#) {ignored:=EnerCubixCockpitImage(bitmap[0..20].toBase64)}
  }
  Void testByteAndDimensionBoundariesAreEnforcedBeforeDecode()
  {
    raw:=bitmap;raw.seek(raw.size);while(raw.size < EnerCubixCockpitImage.maxBytes)raw.write(0)
    verifyEq(raw.size,2097152);verifyEq(EnerCubixCockpitImage(raw.toBase64).width,13)
    raw.write(0);verifyErr(ArgErr#) {ignored:=EnerCubixCockpitImage(raw.toBase64)}
    verifyEq(EnerCubixCockpitImage(bitmap(4096,1).toBase64).width,4096);EnerCubixCockpitImage.dimensions(4096,1);EnerCubixCockpitImage.dimensions(4000,2000)
    verifyErr(ArgErr#) {EnerCubixCockpitImage.dimensions(4097,1)}
    verifyErr(ArgErr#) {EnerCubixCockpitImage.dimensions(4001,2000)}
    verifyErr(ArgErr#) {EnerCubixCockpitImage.dimensions(1,0)}
    bomb:=bitmap; bomb[16]=127; bomb[17]=255; bomb[18]=255; bomb[19]=255
    verifyErr(ArgErr#) {ignored:=EnerCubixCockpitImage(bomb.toBase64)}
  }
  Void testPermissionsHiddenForeignInvalidRefAndUntrustedPathAreRejected()
  {
    verifyErr(EnerCubixHttpErr#) {store(false).upload(uploadBody)}
    verifyErr(EnerCubixHttpErr#) {store(true,[site.id]).upload(uploadBody)}
    verifyErr(EnerCubixHttpErr#) {store(true,Str[,],[site.id]).upload(uploadBody)}
    ["p:other:r:site","../../outside","p:test:r:point","p:test:r:missing"].each |id| {body:=uploadBody;body["scopeId"]=id;verifyErr(EnerCubixHttpErr#) {store.upload(body)}}
    body:=uploadBody;body["path"]="../../outside.png";verifyErr(ArgErr#) {store.upload(body)}
    state:=store.upload(uploadBody);state=store.save(edit(state));r:=first(state)
    redacted:=EnerCubixMath.maps(store(true,[floor.id]).list["items"]).first
    verifyEq(redacted.keys.sort,["canManage","id","mod","unavailable"]);verifyEq(redacted["unavailable"],true)
    verify(EnerCubixMath.maps(store(false,[floor.id]).list["items"]).isEmpty)
    verifyErr(EnerCubixHttpErr#) {store(true,[floor.id]).image(r["id"].toStr,r["hash"].toStr)}
    verifyErr(EnerCubixHttpErr#) {store(true,Str[,],[r["id"].toStr]).save(edit(state))}
    verifyErr(EnerCubixHttpErr#) {store.remove(["id":"p:test:r:point","mod":"x","manifestMod":state["manifestMod"]])}
  }
  Void testCopiedAssetMarkerCannotAdoptOrDeleteNativeBusinessRecords()
  {
    state:=store.upload(uploadBody);r:=db.readById(Ref(first(state)["id"].toStr))
    tags:=Etc.dictToMap(r);tags.remove("id");tags.remove("mod")
    point:=db.readById(Ref("point"));db.commitAll([Diff(point,Etc.makeDict(tags))])
    point=db.readById(Ref("point"));body:=edit(state,Obj?[,]);body["id"]=point.id.id;body["mod"]=((DateTime)point["mod"]).toIso
    verifyErr(EnerCubixHttpErr#) {store.save(body)}
    verifyErr(EnerCubixHttpErr#) {store.remove(["id":point.id.id,"mod":body["mod"],"manifestMod":state["manifestMod"]])}
    verifyEq(EnerCubixMath.maps(store.list["items"]).size,1)
    verify(db.readById(point.id).has("point"));verify(db.readById(point.id).has("his"))
  }
  Void testManifestAndAssetOptimisticModProtectQuotaAndConcurrentWriters()
  {
    firstBody:=uploadBody;state:=store.upload(firstBody)
    verifyErr(EnerCubixHttpErr#) {store.upload(firstBody)}
    old:=edit(state);state=store.save(old);verifyErr(EnerCubixHttpErr#) {store.save(old)}
    while(EnerCubixMath.maps(state["items"]).size < 10)state=store.upload(uploadBody(state))
    verifyEq(EnerCubixMath.maps(state["items"]).size,10)
    verifyErr(ArgErr#) {store.upload(uploadBody(state))}
    verifyEq(db.readAllList(Filter.has("enerCubixCockpitAsset")).size,10)
    files:=(home+Uri.fromStr("enerCubix-private/cockpit-assets/")).list
    verifyEq(files.size,10);verify(!files.any |f| {f.name.endsWith(".pending")})
  }
  Void testConcurrentNinthToTenthSlotUsesOneAtomicManifestAndCleansOnlyLoserTemp()
  {
    state:=store.upload(uploadBody)
    while(EnerCubixMath.maps(state["items"]).size < 9)state=store.upload(uploadBody(state))
    body:=uploadBody(state);pool:=ActorPool {it.name="asset-race"};ready:=CountDownLatch(2);start:=CountDownLatch(1)
    try
    {
      workers:=[Actor(pool,|Obj? msg->Obj?| {race(msg)}),Actor(pool,|Obj? msg->Obj?| {race(msg)})]
      futures:=workers.map |worker->Future| {worker.send(Unsafe([db,home,ready,start,body.dup]))}
      verify(ready.await(5,TimeUnit.SECONDS));start.countDown
      results:=futures.map |Future future->Str| {future.get(20sec).toStr}.sort
      verifyEq(results,["conflict","ok"])
      verifyEq(EnerCubixMath.maps(store.list["items"]).size,10)
      files:=(home+Uri.fromStr("enerCubix-private/cockpit-assets/")).list
      verifyEq(files.size,10);verify(!files.any |f| {f.name.endsWith(".pending")})
      verifyEq(db.readAllList(Filter.has("enerCubixCockpitAssetAudit")).size,10)
    }
    finally {start.countDown;pool.stop;pool.join(20sec)}
  }
  private static Obj? race(Obj? message)
  {
    args:=(List)((Unsafe)message).val
    ready:=(CountDownLatch)args[2];start:=(CountDownLatch)args[3]
    ready.countDown;start.await
    api:=EnerCubixCockpitAssets.withStore((Folio)args[0],(File)args[1],Ref("p:test"),"test","su",true,|Dict r->Bool| {true},|Dict r->Bool| {true})
    try {api.upload((Str:Obj?)args[4]);return "ok"}
    catch(EnerCubixHttpErr e) {if(e.status == 409)return "conflict";throw e}
  }
  Void testTenUnavailableAssetsHaveOnlyRedactedDeletionHandlesAndCanReleaseQuota()
  {
    state:=store.upload(uploadBody)
    while(EnerCubixMath.maps(state["items"]).size < 10)state=store.upload(uploadBody(state))
    hidden:=store(true,[site.id]);state=hidden.list
    rows:=EnerCubixMath.maps(state["items"]);verifyEq(rows.size,10)
    rows.each |r| {verifyEq(r.keys.sort,["canManage","id","mod","unavailable"])}
    verify(EnerCubixMath.maps(store(false,[site.id]).list["items"]).isEmpty)
    item:=rows.first
    verifyErr(EnerCubixHttpErr#) {hidden.image(item["id"].toStr,"anything")}
    state=hidden.remove(["id":item["id"],"mod":item["mod"],"manifestMod":state["manifestMod"]])
    verifyEq(EnerCubixMath.maps(state["items"]).size,9)
    state=store.upload(uploadBody(state));verifyEq(EnerCubixMath.maps(state["items"]).size,10)
    verify(db.readById(site).has("site"));verify(db.readById(Ref("point")).has("his"))
  }
  Void testOneHundredNativeRefHotspotsAcceptBoundaryCoordinatesAndRejectOneHundredOne()
  {
    changes:=Diff[,];spots:=[Str:Obj?][,]
    101.times |i| {id:="asset-floor-"+i;changes.add(Diff.makeAdd(Etc.makeDict(["floor":Marker.val,"siteRef":site]),Ref(id)));spots.add(["spaceId":"p:test:r:"+id,"x":i.toFloat/100f,"y":1f])}
    db.commitAll(changes)
    state:=store.upload(uploadBody);state=store.save(edit(state,spots[0..<100]))
    returned:=EnerCubixMath.maps(first(state)["hotspots"]);verifyEq(returned.size,100);verifyEq(returned.first["x"],0f);verifyEq(returned.last["y"],1f)
    verifyErr(ArgErr#) {store.save(edit(state,spots))}
    verifyEq(EnerCubixMath.maps(first(store.list)["hotspots"]).size,100)
  }
  Void testDeletionAfterMetadataCommitNeverDeletesAnotherRequestsPendingFile()
  {
    uploader:=store
    uploader.beforePublish=|->Void|
    {
      state:=store.list;item:=first(state)
      verifyEq(EnerCubixMath.maps(state["items"]).size,1)
      store.remove(["id":item["id"],"mod":item["mod"],"manifestMod":state["manifestMod"]])
      // The deleted version was committed, but its temporary file still belongs to uploader.
      verify((home+Uri.fromStr("enerCubix-private/cockpit-assets/")).list.any |file| {file.name.endsWith(".pending")})
    }
    state:=uploader.upload(uploadBody)
    verify(EnerCubixMath.maps(state["items"]).isEmpty)
    verify((home+Uri.fromStr("enerCubix-private/cockpit-assets/")).list.isEmpty)
    verifyEq(db.readAllList(Filter.has("enerCubixCockpitAssetAudit")).size,2)
    verify(db.readById(Ref("point")).has("his"))
  }
  Void testReplacementAfterMetadataCommitRetainsWinnerImageAndOnlyDiscardsOwnCandidate()
  {
    uploader:=store;Str? winnerMod
    uploader.beforePublish=|->Void|
    {
      state:=store.list;old:=first(state);request:=uploadBody(state)
      request["id"]=old["id"];request["mod"]=old["mod"];request["clearHotspots"]=true
      state=store.upload(request);winnerMod=first(state)["mod"].toStr
      verify((home+Uri.fromStr("enerCubix-private/cockpit-assets/")).list.any |file| {file.name.endsWith(".pending")})
    }
    state:=uploader.upload(uploadBody);item:=first(state)
    verifyEq(item["mod"],winnerMod)
    verifyEq((home+Uri.fromStr("enerCubix-private/cockpit-assets/")).list.size,1)
    verifyEq(((Buf)store.image(item["id"].toStr,item["hash"].toStr)["bytes"]).toDigest("SHA-256").toHex,item["hash"])
    verifyEq(db.readAllList(Filter.has("enerCubixCockpitAssetAudit")).size,2)
  }
  Void testUnavailableCorruptOwnedMetadataCanBeRemovedWithoutFollowingForeignPaths()
  {
    state:=store.upload(uploadBody);id:=Ref(first(state)["id"].toStr);r:=db.readById(id)
    sentinel:=home+Uri.fromStr("outside.png");sentinel.out.print("OUTSIDE_SENTINEL").close
    db.commitAll([Diff(r,Etc.makeDict(["enerCubixAssetScopeRef":Ref("missing"),"enerCubixHotspotRefs":["invalid-ref-type"],"enerCubixAssetFile":"../../outside.png"]))])
    state=store.list;item:=first(state);verifyEq(item.keys.sort,["canManage","id","mod","unavailable"])
    state=store.remove(["id":item["id"],"mod":item["mod"],"manifestMod":state["manifestMod"]])
    verify(EnerCubixMath.maps(state["items"]).isEmpty);verifyEq(sentinel.readAllStr,"OUTSIDE_SENTINEL");verify(db.readById(Ref("point")).has("his"))
  }
  Void testHotspotBoundsReplacementConfirmationUnbindAndDeletionOnlyOwnAttachments()
  {
    state:=store.upload(uploadBody);state=store.save(edit(state))
    [Float.nan,-0.01f,1.01f].each |x| {verifyErr(ArgErr#) {store.save(edit(state,[["spaceId":floor.id,"x":x,"y":0f]]))}}
    verifyErr(ArgErr#) {store.save(edit(state,[["spaceId":floor.id,"x":0f,"y":1f],["spaceId":floor.id,"x":0.5f,"y":0.5f]]))}
    old:=first(state);replace:=uploadBody(state);replace["id"]=old["id"];replace["mod"]=old["mod"]
    verifyErr(ArgErr#) {store.upload(replace)}
    replace["clearHotspots"]=true;state=store.upload(replace);verify(EnerCubixMath.maps(first(state)["hotspots"]).isEmpty)
    state=store.save(edit(state));state=store.save(edit(state,Obj?[,]));verify(EnerCubixMath.maps(first(state)["hotspots"]).isEmpty)
    r:=first(state);state=store.remove(["id":r["id"],"mod":r["mod"],"manifestMod":state["manifestMod"]])
    verify(EnerCubixMath.maps(state["items"]).isEmpty);verifyNull(state["selectedId"])
    verify(db.readById(site,false) != null);verify(db.readById(Ref("point"),false).has("his"));verifyEq(db.readById(Ref("equip"))["enerCubixPointRef"],Ref("p:test:r:point"))
    verify((home+Uri.fromStr("enerCubix-private/cockpit-assets/")).list.isEmpty)
  }
}

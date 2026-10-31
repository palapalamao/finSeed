using haystack
using folio
using skyarcd
using [java] fanx.interop::Interop
using [java] java.io::File as JavaFile

** Project-private presentation attachments. Never writes energy objects, points or history.
class EnerCubixCockpitAssets
{
  private Folio db
  private File directory
  private Str projectPath
  private Ref projectRef
  private Str project
  private Str actor
  private Bool admin
  private |Dict->Bool| canRead
  private |Dict->Bool| canWrite
  private Ref manifestId
  private Bool commitUnknown := false
  // Controlled test seam for the Folio/file publication boundary; never supplied by HTTP.
  internal |->Void|? beforePublish
  static const Int maxAssets := 10
  static const Int maxHotspots := 100
  new make(EnerCubixRepo repo) : this.withStore(repo.cx.db,repo.cx.proj.dir,repo.cx.proj.id,repo.cx.proj.name,repo.cx.user.username,repo.cx.user.isAdmin,|Dict r->Bool| {repo.cx.canRead(r)},|Dict r->Bool| {repo.cx.canWrite(r)}) { repo.mustRead }
  internal new withStore(Folio db,File projectDir,Ref projectRef,Str project,Str actor,Bool admin,|Dict->Bool| canRead,|Dict->Bool| canWrite)
  {
    this.db=db; this.directory=(projectDir+Uri.fromStr("enerCubix-private/cockpit-assets/")).normalize
    this.projectPath=Interop.toJava(projectDir).getCanonicalPath+JavaFile.separator
    this.projectRef=projectRef; this.project=project; this.actor=actor; this.admin=admin; this.canRead=canRead; this.canWrite=canWrite
    this.manifestId=Ref("enerCubix-cockpit-assets").toAbs("p:"+project+":r:")
  }
  Str:Obj? list()
  {
    manifest:=readManifest
    items:=[Str:Obj?][,]
    db.readAllList(Filter.has("enerCubixCockpitAsset")).each |r| {if(readable(r))items.add(dto(r));else if(admin && ownedAsset(r) && canRead(r) && canWrite(r))items.add(["id":r.id.id,"mod":mod(r),"unavailable":true,"canManage":true])}
    selected:=(manifest?.get("enerCubixSelectedAssetRef") as Ref)?.id
    return ["projectId":projectRef.id,"items":items,"manifestMod":mod(manifest),"selectedId":items.any |r| {r["id"] == selected} ? selected : null,"limits":["maxBytes":EnerCubixCockpitImage.maxBytes,"maxDimension":4096,"maxPixels":EnerCubixCockpitImage.maxPixels,"maxHotspots":maxHotspots,"maxAssets":maxAssets]]
  }
  Str:Obj? upload(Str:Obj? input)
  {
    mustWrite
    fields(input,["id","mod","manifestMod","name","scopeId","base64","clearHotspots"])
    prior:=input["id"] == null ? null : stored(text(input,"id"),true)
    if (prior != null) EnerCubixRepo.checkMod(prior,input["mod"])
    manifest:=writeManifest(input["manifestMod"])
    all:=assets
    if (prior == null && all.size >= maxAssets) throw ArgErr("assetQuota")
    if (prior != null && !refs(prior,"enerCubixHotspotRefs").isEmpty && input["clearHotspots"] != true) throw ArgErr("assetReplaceConfirm")
    coverage:=scope(text(input,"scopeId"),true)
    name:=displayName(text(input,"name"))
    image:=EnerCubixCockpitImage(text(input,"base64"))
    id:=prior?.id ?: Ref.gen.toAbs("p:"+project+":r:")
    token:=Uuid().toStr.replace("-","")
    filename:=token+"."+image.extension
    finalFile:=ownedFile(filename)
    temp:=directory+(filename+".pending").toUri
    directory.create
    if (finalFile.exists || temp.exists) throw IOErr("assetRandomNameCollision")
    committed:=false
    try
    {
      image.bytes.seek(0); stream:=temp.out; try {stream.writeBuf(image.bytes)} finally {stream.close}
      hash:=image.bytes.toDigest("SHA-256").toHex
      if (temp.readAllBuf.toDigest("SHA-256").toHex != hash) throw IOErr("assetWriteVerification")
      tags:=Str:Obj?["enerCubixCockpitAsset":Marker.val,"enerCubixAssetProjectRef":projectRef,"dis":name,"enerCubixAssetScopeRef":coverage,"enerCubixAssetFile":filename,"enerCubixAssetHash":hash,"enerCubixAssetMime":image.mime,"enerCubixAssetWidth":Number(image.width),"enerCubixAssetHeight":Number(image.height),"enerCubixAssetSize":Number(image.bytes.size),"enerCubixHotspotRefs":Ref[,],"enerCubixHotspotX":Number[,],"enerCubixHotspotY":Number[,],"enerCubixAssetOperation":token,"enerCubixAssetUpdatedAt":DateTime.now,"enerCubixAssetUpdatedBy":actor]
      diff:=prior == null ? Diff.makeAdd(Etc.makeDict(tags),id.toRel("p:"+project+":r:")) : Diff(prior,Etc.makeDict(tags))
      next:=all.map |r->Ref| {r.id}; if(prior == null) next.add(id)
      selected:=manifest?.get("enerCubixSelectedAssetRef") as Ref
      commit([diff,manifestDiff(manifest,next,selected ?: id,token),audit(prior == null ? "upload" : "replace",id,hash,[coverage],token)],token)
      committed=true
      beforePublish?.call
      if(assets.any |r| {r["enerCubixAssetFile"] == filename})temp.moveTo(finalFile)
      else if(temp.exists)temp.delete
      // A later committed replacement/deletion may win while this file is publishing.
      if(finalFile.exists && !assets.any |r| {r["enerCubixAssetFile"] == filename})finalFile.delete
      if (prior != null) cleanup(prior)
      return list
    }
    finally { if (!committed && !commitUnknown && temp.exists) temp.delete }
  }
  Str:Obj? save(Str:Obj? input)
  {
    mustWrite; fields(input,["id","mod","manifestMod","name","scopeId","hotspots"])
    prior:=stored(text(input,"id"),true); EnerCubixRepo.checkMod(prior,input["mod"])
    manifest:=writeManifest(input["manifestMod"])
    coverage:=scope(text(input,"scopeId"),true)
    spots:=input["hotspots"] as List ?: throw ArgErr("assetHotspots")
    if (spots.size > maxHotspots) throw ArgErr("assetHotspots")
    targets:=Ref[,]; xs:=Number[,]; ys:=Number[,]
    spots.each |item|
    {
      h:=item as Map ?: throw ArgErr("assetHotspots")
      fields(h,["spaceId","x","y"])
      target:=scope(text(h,"spaceId"),true,false)
      if (targets.contains(target)) throw ArgErr("assetHotspots")
      targets.add(target); xs.add(coordinate(h["x"])); ys.add(coordinate(h["y"]))
    }
    token:=Uuid().toStr
    patch:=Etc.makeDict(["dis":displayName(text(input,"name")),"enerCubixAssetScopeRef":coverage,"enerCubixHotspotRefs":targets,"enerCubixHotspotX":xs,"enerCubixHotspotY":ys,"enerCubixAssetOperation":token,"enerCubixAssetUpdatedAt":DateTime.now,"enerCubixAssetUpdatedBy":actor])
    commit([Diff(prior,patch),manifestDiff(manifest,assets.map |r->Ref| {r.id},manifest?.get("enerCubixSelectedAssetRef") as Ref,token),audit("save",prior.id,prior["enerCubixAssetHash"].toStr,[coverage].addAll(targets),token)],token)
    return list
  }
  Str:Obj? select(Str:Obj? input)
  {
    mustWrite; fields(input,["id","manifestMod"])
    manifest:=writeManifest(input["manifestMod"])
    selected:=input["id"] == null ? null : stored(text(input,"id"),true)
    token:=Uuid().toStr
    commit([manifestDiff(manifest,assets.map |r->Ref| {r.id},selected?.id,token),audit("select",selected?.id ?: manifestId,selected?.get("enerCubixAssetHash")?.toStr ?: "",selected == null ? Ref[,] : [scope(selected["enerCubixAssetScopeRef"].toStr,true)],token)],token)
    return list
  }
  Str:Obj? remove(Str:Obj? input)
  {
    mustWrite; fields(input,["id","mod","manifestMod"])
    prior:=deletable(text(input,"id")); EnerCubixRepo.checkMod(prior,input["mod"])
    manifest:=writeManifest(input["manifestMod"]); token:=Uuid().toStr
    ids:=assets.findAll |r| {r.id != prior.id}.map |r->Ref| {r.id}
    selected:=manifest?.get("enerCubixSelectedAssetRef") as Ref
    commit([Diff(prior,null,Diff.remove),manifestDiff(manifest,ids,selected == prior.id ? null : selected,token),audit("delete",prior.id,prior["enerCubixAssetHash"].toStr,linkedRefs(prior),token)],token)
    cleanup(prior)
    return list
  }
  Str:Obj? image(Str id,Str hash)
  {
    r:=stored(id)
    if (r["enerCubixAssetHash"] != hash) throw EnerCubixHttpErr(409,"CONFLICT","assetImageChanged")
    file:=ownedFile(r["enerCubixAssetFile"].toStr)
    if (!file.exists || file.size > EnerCubixCockpitImage.maxBytes) throw EnerCubixHttpErr(404,"NOT_FOUND","assetUnavailable")
    data:=file.readAllBuf
    if (data.toDigest("SHA-256").toHex != hash) throw EnerCubixHttpErr(404,"NOT_FOUND","assetUnavailable")
    return ["bytes":data,"mime":r["enerCubixAssetMime"]]
  }
  private Dict? readManifest() {r:=db.readById(manifestId,false); return r?.has("enerCubixCockpitAssetManifest") == true && canRead(r) && !businessRecord(r) && r["enerCubixAssetProjectRef"] == projectRef ? r : null}
  private Dict? writeManifest(Obj? version)
  {
    r:=readManifest
    if (r != null) { if (!canRead(r) || !canWrite(r)) denied; EnerCubixRepo.checkMod(r,version) }
    else if(version != null) throw EnerCubixHttpErr(409,"CONFLICT","assetConflict")
    return r
  }
  private Dict[] assets() {db.readAllList(Filter.has("enerCubixCockpitAsset")).findAll |r| {ownedAsset(r)}}
  private Bool ownedAsset(Dict r) {r.has("enerCubixCockpitAsset") && !businessRecord(r) && !r.has("enerCubixCockpitAssetManifest") && !r.has("enerCubixCockpitAssetAudit") && r["enerCubixAssetProjectRef"] == projectRef}
  private Dict deletable(Str id) {checkRef(id);r:=db.readById(Ref(id),false);if(r == null || !ownedAsset(r) || !canRead(r) || !canWrite(r))denied;return r}
  private Dict stored(Str id,Bool write:=false)
  { checkRef(id); r:=db.readById(Ref(id),false); if (r == null || !readable(r) || (write && !canWrite(r))) denied; return r }
  private Bool readable(Dict r)
  {
    if (!ownedAsset(r) || !canRead(r)) return false
    try
    {
      scope(r["enerCubixAssetScopeRef"].toStr)
      targets:=refs(r,"enerCubixHotspotRefs")
      xs:=r["enerCubixHotspotX"] as List; ys:=r["enerCubixHotspotY"] as List
      if (xs == null || ys == null || xs.size != targets.size || ys.size != targets.size || targets.size > maxHotspots || !["image/png","image/jpeg"].contains(r["enerCubixAssetMime"]) || !Regex<|[0-9a-f]{64}|>.matches(r["enerCubixAssetHash"].toStr)) return false
      targets.each |ref,i| {scope(ref.id,false,false); coordinate(xs[i]); coordinate(ys[i])}
      ownedFile(r["enerCubixAssetFile"].toStr)
      return true
    }
    catch (Err e) {return false}
  }
  private Ref scope(Str id,Bool write:=false,Bool allowProject:=true)
  {
    if (allowProject && id == projectRef.id) return projectRef
    checkRef(id)
    r:=db.readById(Ref(id),false)
    if (r == null || (!r.has("site") && !r.has("floor")) || !canRead(r) || (write && !canWrite(r))) denied
    return r.id
  }
  private Void checkRef(Str id) {if(id.isEmpty || id.size > 300 || id.trim != id || id.contains("/") || id.contains("\\") || (id.startsWith("p:") && !id.startsWith("p:"+project+":r:"))) denied}
  private static Bool businessRecord(Dict r) {["site","floor","equip","point","his","enerCubixKind","alarm","conn","ext","user"].any |tag| {r.has(tag)}}
  private Void mustWrite() {if(!admin) denied}
  private static Void denied() {throw EnerCubixHttpErr(403,"PERMISSION","assetForbidden")}
  private Diff manifestDiff(Dict? previous,Ref[] ids,Ref? selected,Str token)
  {
    tags:=Str:Obj?["enerCubixCockpitAssetManifest":Marker.val,"enerCubixAssetProjectRef":projectRef,"enerCubixAssetRefs":ids,"enerCubixAssetOperation":token,"enerCubixAssetUpdatedBy":actor]
    tags["enerCubixSelectedAssetRef"]=selected ?: Remove.val
    if(previous == null) {tags.remove("enerCubixSelectedAssetRef"); if(selected != null)tags["enerCubixSelectedAssetRef"]=selected;return Diff.makeAdd(Etc.makeDict(tags),manifestId.toRel("p:"+project+":r:"))}
    return Diff(previous,Etc.makeDict(tags))
  }
  private static Ref[] linkedRefs(Dict r) {List values:=r["enerCubixHotspotRefs"] as List ?: Obj?[,];out:=values.findAll |v| {v is Ref}.map |v->Ref| {(Ref)v};scope:=r["enerCubixAssetScopeRef"] as Ref;if(scope != null)out.add(scope);return out.unique}
  private Diff audit(Str action,Ref id,Str hash,Ref[] nativeRefs,Str token)
  {Diff.makeAdd(Etc.makeDict(["enerCubixCockpitAssetAudit":Marker.val,"enerCubixAssetProjectRef":projectRef,"enerCubixAssetRef":id,"enerCubixAssetAction":action,"enerCubixAssetHash":hash,"enerCubixAssetNativeRefs":nativeRefs.unique,"enerCubixAssetActor":actor,"enerCubixAssetAt":DateTime.now,"enerCubixAssetOperation":token]))}
  private Void commit(Diff[] changes,Str token)
  {
    EnerCubixHistorySafety.metadata(db,changes)
    try {db.commitAll(changes)}
    catch(Err e)
    {
      if (["ConcurrentChangeErr","DuplicateRecErr"].contains(e.typeof.name)) throw EnerCubixHttpErr(409,"CONFLICT","assetConflict")
      // Reconcile a possibly committed mutation once; never replay it or remove its attachment blindly.
      Dict? proof
      try {proof=db.readById(changes.last.id,false)}
      catch (Err readErr) {commitUnknown=true; throw EnerCubixHttpErr(503,"UNKNOWN","assetCommitUnknown")}
      observed:=proof?.has("enerCubixCockpitAssetAudit") == true && proof?.get("enerCubixAssetProjectRef") == projectRef && proof?.get("enerCubixAssetOperation") == token
      if(!observed) throw e
    }
  }
  private Void cleanup(Dict r)
  {
    filename:=r["enerCubixAssetFile"] as Str
    if(filename == null || assets.any |a| {a["enerCubixAssetFile"] == filename}) return
    if(!Regex<|[0-9a-f]{32}\.(png|jpg)|>.matches(filename))return
    try {file:=ownedFile(filename); if(file.exists)file.delete}
    catch(Err e) {Log.get("enerCubix").warn("Owned asset metadata committed; private file cleanup deferred",e)}
  }
  private File ownedFile(Str filename)
  {
    if(!Regex<|[0-9a-f]{32}\.(png|jpg)|>.matches(filename)) throw ArgErr("assetUnavailable")
    file:=directory+filename.toUri
    base:=Interop.toJava(directory).getCanonicalPath+JavaFile.separator
    if(!base.startsWith(projectPath) || !Interop.toJava(file).getCanonicalPath.startsWith(base)) throw ArgErr("assetUnavailable")
    return file
  }
  private Str:Obj? dto(Dict r)
  {
    targets:=refs(r,"enerCubixHotspotRefs"); xs:=(List)r["enerCubixHotspotX"]; ys:=(List)r["enerCubixHotspotY"]
    return ["id":r.id.id,"mod":mod(r),"name":r.dis,"scopeId":((Ref)r["enerCubixAssetScopeRef"]).id,"hash":r["enerCubixAssetHash"],"mime":r["enerCubixAssetMime"],"width":((Number)r["enerCubixAssetWidth"]).toInt,"height":((Number)r["enerCubixAssetHeight"]).toInt,"size":((Number)r["enerCubixAssetSize"]).toInt,"updatedBy":r["enerCubixAssetUpdatedBy"],"updatedAt":((DateTime)r["enerCubixAssetUpdatedAt"]).toIso,"hotspots":targets.map |ref,i->Str:Obj?| { ["spaceId":ref.id,"x":((Number)xs[i]).toFloat,"y":((Number)ys[i]).toFloat] }]
  }
  private static Str? mod(Dict? r) {(r?.get("mod") as DateTime)?.toIso}
  private static Ref[] refs(Dict r,Str tag) {List values:=r[tag] as List ?: Obj?[,]; return values.map |v->Ref| {v as Ref ?: throw ArgErr("assetUnavailable")}}
  private static Str text(Map input,Str key) {v:=input[key] as Str; if(v == null || v.isEmpty)throw ArgErr("assetFields");return v}
  private static Str displayName(Str name) {if(name.trim.isEmpty || name.size > 120 || name.any |c| {c < 32}) throw ArgErr("assetFields");return name.trim}
  private static Number coordinate(Obj? value) {n:=value is Number ? ((Number)value).toFloat : EnerCubixMath.num(value);if(n == null || n.isNaN || n < 0f || n > 1f)throw ArgErr("assetHotspots");return Number(n)}
  private static Void fields(Map input,Str[] allowed) {if(input.keys.any |k| {!allowed.contains(k)})throw ArgErr("assetFields")}
}

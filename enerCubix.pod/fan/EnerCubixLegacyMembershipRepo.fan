using haystack
using folio
using skyarcd
using util

** An explicit, reversible import of narrowly bounded historical edge evidence.
** No native device tags, global timeline boundary or source history is edited.
class EnerCubixLegacyMembershipRepo
{
  EnerCubixRepo repo
  Context cx
  private Dict[] guards:=Dict[,]
  new make(EnerCubixRepo repo) {this.repo=repo;cx=repo.cx}

  Str:Obj? run(Str:Obj? input)
  {
    repo.mustWrite
    action:=input["action"] as Str ?: "preview"
    if (action == "rollback")
    {
      receipt:=cx.db.readById(Ref(input["id"].toStr))
      if (!receipt.has("enerCubixLegacyMembership")) throw ArgErr("legacyTopologyInvalidProof")
      EnerCubixRepo.checkMod(receipt,input["mod"])
      saved:=cx.db.commit(Diff(receipt,Etc.makeDict(["enerCubixLegacyEnabled":false,"enerCubixLegacyStatus":"rolledBack"]))).newRec
      return summary(saved)
    }
    if (!["preview","apply"].contains(action)) throw ArgErr("legacyTopologyInvalidProof")
    plan:=preview(input)
    id:=Ref(plan["id"].toStr);existing:=cx.db.readById(id,false)
    if (action == "preview") return plan
    if (existing?.get("enerCubixLegacyEnabled") == true) return summary(existing).set("alreadyApplied",true)
    if (input["revision"] != plan["revision"]) throw EnerCubixHttpErr(409,"CONFLICT","legacyTopologyStalePreview")
    data:=plan.dup;data.remove("revision");data.remove("existing")
    json:=JsonOutStream.writeJsonToStr(data)
    edges:=EnerCubixMath.maps(plan["edges"])
    tags:=Etc.makeDict(["enerCubixLegacyMembership":Marker.val,"enerCubixLegacyEnabled":false,"enerCubixLegacyStatus":"pending","enerCubixLegacyData":json,"enerCubixLegacyDigest":digest(data),"enerCubixLegacyChildRefs":edges.map |e->Ref| {Ref(e["childId"].toStr)},"enerCubixLegacyParentRefs":edges.map |e->Ref| {Ref(e["parentId"].toStr)}.unique,"enerCubixLegacyPointRefs":edges.map |e->Ref| {Ref(e["pointId"].toStr)}.unique,"dis":"Historical membership evidence "+id.id])
    checkGuards
    saved:=cx.db.commit(existing == null ? Diff.makeAdd(tags,id.toRel(cx.db.idPrefix)) : Diff(existing,tags)).newRec
    try
    {
      checkGuards
      saved=cx.db.commit(Diff(saved,Etc.makeDict(["enerCubixLegacyEnabled":true,"enerCubixLegacyStatus":"applied"]))).newRec
      // A concurrent importer may have activated a different receipt after
      // preview. Validate the current set before returning success.
      active(null)
      checkGuards
    }
    catch (Err e)
    {
      cx.db.commit(Diff(saved,Etc.makeDict(["enerCubixLegacyEnabled":false,"enerCubixLegacyStatus":"conflict"])))
      throw e
    }
    return summary(saved)
  }

  private Str:Obj? preview(Str:Obj? input)
  {
    guards=Dict[,]
    nativeRepo:=EnerCubixNativeEquipRepo(repo)
    aliases:=nativeRepo.mapping.dup
    model:=nativeRepo.model
    if (model != null) guards.add(model)
    ids:=EnerCubixMath.strings(input["legacyIds"])
    if (ids.isEmpty || ids.size > 100) throw ArgErr("legacyTopologyMissingMapping")
    ids.each |id| {checkProject(id)}
    sources:=EnerCubixMath.maps(input["sources"])
    if (sources.size < 2 || sources.size > 8) throw ArgErr("legacyTopologyInvalidProof")
    [Str:Obj?][] observed:=sources.map |s->[Str:Obj?]|
    {
      name:=s["file"] as Str ?: "";hash:=s["sha256"] as Str ?: ""
      if (!Regex<|[A-Za-z0-9_.-]+\.zip|>.matches(name) || !name.startsWith(cx.proj.name+"-") || !Regex<|[A-Fa-f0-9]{64}|>.matches(hash)) throw ArgErr("legacyTopologyInvalidBackup")
      return EnerCubixLegacyBackup.read(cx.proj.dir+`backup/${name}`,hash,cx.db.idPrefix ?: throw ArgErr("legacyTopologyWrongProject"),ids)
    }
    // A retained migration alias and a point's dated equipment owner are
    // independent identity evidence. Both must agree when both are available.
    first:=EnerCubixMath.maps(observed.first["records"])
    first.each |r|
    {
      point:=r["pointId"] as Str ?: throw ArgErr("legacyTopologyMissingSource")
      owner:=EnerCubixMath.maps(observed.first["pointOwners"]).find |o| {o["pointId"] == point}
      equip:=owner?.get("equipId") as Str ?: throw ArgErr("legacyTopologyMissingMapping")
      observed.each |s|
      {
        o:=EnerCubixMath.maps(s["pointOwners"]).find |e| {e["pointId"] == point}
        if (o == null || o["point"] != true || o["his"] != true || o["equipId"] != equip || o["unit"] != owner["unit"]) throw ArgErr("legacyTopologyPointMismatch")
      }
      key:=r["id"].toStr
      if (aliases.containsKey(key) && aliases[key] != equip) throw ArgErr("legacyTopologyMissingMapping")
      aliases[key]=equip
    }
    plan:=EnerCubixLegacyMembership.plan(input,observed,aliases)
    identity:=input.dup;["action","revision","id","mod"].each |k| {identity.remove(k)}
    id:=(cx.db.idPrefix ?: "")+"enerCubix-legacy-"+digest(identity)[0..<24]
    edges:=EnerCubixMath.maps(plan["edges"])
    targets:=[Str:Obj?][,]
    edges.each |edge|
    {
      edge["proofId"]=id
      child:=equipment(edge["childId"].toStr);parent:=equipment(edge["parentId"].toStr)
      checkPoint(edge["pointId"].toStr,child,edge["unit"].toStr)
      checkPoint(edge["parentPointId"].toStr,parent,edge["unit"].toStr)
      targets.add(["child":child.id.id,"childMod":EnerCubixRepo.iso(child["mod"]),"parent":parent.id.id,"parentMod":EnerCubixRepo.iso(parent["mod"])])
      edge["name"]=child.dis
    }
    others:=active(null).findAll |e| {e["proofId"] != id}
    EnerCubixLegacyMembership.validate(others.dup.addAll(edges))
    plan.setAll(["id":id,"project":cx.proj.name,"nativeTimelineStart":EnerCubixRepo.iso(cx.db.read(Filter.has("enerCubixMeterTimeline"),false)?.get("enerCubixTimelineStart")),"limitations":["snapshotRecoveryNotCompleteEventLog","outsideImportedRangeUnknown","strictBalanceUnchanged","energyOnly"]])
    existing:=cx.db.readById(Ref(id),false)
    plan["existing"]=existing == null ? null : summary(existing)
    plan["revision"]=digest(["plan":plan,"aliases":aliases,"targets":targets,"active":others])
    return plan
  }

  [Str:Obj?][] active([Str:Obj?]? request)
  {
    out:=[Str:Obj?][,]
    cx.db.readAllList(Filter.has("enerCubixLegacyMembership").and(Filter.eq("enerCubixLegacyEnabled",true))).each |receipt|
    {
      data:=(Str:Obj?)JsonInStream(receipt["enerCubixLegacyData"].toStr.in).readJson
      if (digest(data) != receipt["enerCubixLegacyDigest"]) throw ArgErr("legacyTopologyInvalidProof")
      EnerCubixMath.maps(data["edges"]).each |edge|
      {
        if (request != null && (DateTime.fromIso(edge["from"].toStr) >= DateTime.fromIso(request["to"].toStr) || DateTime.fromIso(edge["to"].toStr) <= DateTime.fromIso(request["from"].toStr))) return
        child:=cx.db.readById(Ref(edge["childId"].toStr),false);parent:=cx.db.readById(Ref(edge["parentId"].toStr),false)
        if (child != null && parent != null && cx.canRead(child) && cx.canRead(parent)) out.add(edge)
      }
      guards.add(receipt)
    }
    EnerCubixLegacyMembership.validate(out)
    return out
  }

  // Folio has no read-set-only persistent Diff. Never touch a source record
  // merely to validate its revision; an observed race disables the receipt.
  private Void checkGuards()
  {
    if (guards.any |r| {cx.db.readById(r.id,false)?.get("mod") != r["mod"]}) throw EnerCubixHttpErr(409,"CONFLICT","legacyTopologyStalePreview")
  }

  private Dict equipment(Str id)
  {
    checkProject(id)
    r:=cx.db.readById(Ref(id),false)
    if (r == null || !r.has("equip") || !cx.canRead(r)) throw ArgErr("legacyTopologyMissingMapping")
    guards.add(r)
    return r
  }
  private Void checkPoint(Str id, Dict equip, Str unit)
  {
    checkProject(id)
    p:=cx.db.readById(Ref(id),false)
    if (p == null || !p.has("point") || !p.has("his") || !cx.canRead(p) || (p["equipRef"] as Ref)?.id != equip.id.id || EnerCubixMath.unitFactor(p["unit"]?.toStr ?: "",unit) == null) throw ArgErr("legacyTopologyPointMismatch")
    guards.add(p)
  }
  private Void checkProject(Str id) {if (!(cx.db.idPrefix == null || id.startsWith(cx.db.idPrefix))) throw ArgErr("legacyTopologyWrongProject")}
  private static Str:Obj? summary(Dict r) { ["id":r.id.id,"mod":EnerCubixRepo.iso(r["mod"]),"status":r["enerCubixLegacyStatus"],"enabled":r["enerCubixLegacyEnabled"]] }
  private static Str digest(Obj? data) {JsonOutStream.writeJsonToStr(ordered(data)).toBuf.toDigest("SHA-256").toHex}
  private static Obj? ordered(Obj? value)
  {
    if (value is Map) {m:=Str:Obj?[:];m.ordered=true;((Map)value).keys.map |k->Str| {k.toStr}.sort.each |k| {m[k]=ordered(((Map)value)[k])};return m}
    if (value is List) return ((List)value).map |v->Obj?| {ordered(v)}
    return value
  }
}

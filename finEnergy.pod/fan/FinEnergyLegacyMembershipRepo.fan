using haystack
using folio
using skyarcd
using util

** An explicit, reversible import of narrowly bounded historical edge evidence.
** No native device tags, global timeline boundary or source history is edited.
class FinEnergyLegacyMembershipRepo
{
  FinEnergyRepo repo
  Context cx
  private Dict[] guards:=Dict[,]
  new make(FinEnergyRepo repo) {this.repo=repo;cx=repo.cx}

  Str:Obj? run(Str:Obj? input)
  {
    repo.mustWrite
    action:=input["action"] as Str ?: "preview"
    if (action == "rollback")
    {
      receipt:=cx.db.readById(Ref(input["id"].toStr))
      if (!receipt.has("finEnergyLegacyMembership")) throw ArgErr("legacyTopologyInvalidProof")
      FinEnergyRepo.checkMod(receipt,input["mod"])
      saved:=cx.db.commit(Diff(receipt,Etc.makeDict(["finEnergyLegacyEnabled":false,"finEnergyLegacyStatus":"rolledBack"]))).newRec
      return summary(saved)
    }
    if (!["preview","apply"].contains(action)) throw ArgErr("legacyTopologyInvalidProof")
    plan:=preview(input)
    id:=Ref(plan["id"].toStr);existing:=cx.db.readById(id,false)
    if (action == "preview") return plan
    if (existing?.get("finEnergyLegacyEnabled") == true) return summary(existing).set("alreadyApplied",true)
    if (input["revision"] != plan["revision"]) throw FinEnergyHttpErr(409,"CONFLICT","legacyTopologyStalePreview")
    data:=plan.dup;data.remove("revision");data.remove("existing")
    json:=JsonOutStream.writeJsonToStr(data)
    edges:=FinEnergyMath.maps(plan["edges"])
    tags:=Etc.makeDict(["finEnergyLegacyMembership":Marker.val,"finEnergyLegacyEnabled":false,"finEnergyLegacyStatus":"pending","finEnergyLegacyData":json,"finEnergyLegacyDigest":digest(data),"finEnergyLegacyChildRefs":edges.map |e->Ref| {Ref(e["childId"].toStr)},"finEnergyLegacyParentRefs":edges.map |e->Ref| {Ref(e["parentId"].toStr)}.unique,"finEnergyLegacyPointRefs":edges.map |e->Ref| {Ref(e["pointId"].toStr)}.unique,"dis":"Historical membership evidence "+id.id])
    checkGuards
    saved:=cx.db.commit(existing == null ? Diff.makeAdd(tags,id.toRel(cx.db.idPrefix)) : Diff(existing,tags)).newRec
    try
    {
      checkGuards
      saved=cx.db.commit(Diff(saved,Etc.makeDict(["finEnergyLegacyEnabled":true,"finEnergyLegacyStatus":"applied"]))).newRec
      // A concurrent importer may have activated a different receipt after
      // preview. Validate the current set before returning success.
      active(null)
      checkGuards
    }
    catch (Err e)
    {
      cx.db.commit(Diff(saved,Etc.makeDict(["finEnergyLegacyEnabled":false,"finEnergyLegacyStatus":"conflict"])))
      throw e
    }
    return summary(saved)
  }

  private Str:Obj? preview(Str:Obj? input)
  {
    guards=Dict[,]
    nativeRepo:=FinEnergyNativeEquipRepo(repo)
    aliases:=nativeRepo.mapping.dup
    model:=nativeRepo.model
    if (model != null) guards.add(model)
    ids:=FinEnergyMath.strings(input["legacyIds"])
    if (ids.isEmpty || ids.size > 100) throw ArgErr("legacyTopologyMissingMapping")
    ids.each |id| {checkProject(id)}
    sources:=FinEnergyMath.maps(input["sources"])
    if (sources.size < 2 || sources.size > 8) throw ArgErr("legacyTopologyInvalidProof")
    [Str:Obj?][] observed:=sources.map |s->[Str:Obj?]|
    {
      name:=s["file"] as Str ?: "";hash:=s["sha256"] as Str ?: ""
      if (!Regex<|[A-Za-z0-9_.-]+\.zip|>.matches(name) || !name.startsWith(cx.proj.name+"-") || !Regex<|[A-Fa-f0-9]{64}|>.matches(hash)) throw ArgErr("legacyTopologyInvalidBackup")
      return FinEnergyLegacyBackup.read(cx.proj.dir+`backup/${name}`,hash,cx.db.idPrefix ?: throw ArgErr("legacyTopologyWrongProject"),ids)
    }
    // A retained migration alias and a point's dated equipment owner are
    // independent identity evidence. Both must agree when both are available.
    first:=FinEnergyMath.maps(observed.first["records"])
    first.each |r|
    {
      point:=r["pointId"] as Str ?: throw ArgErr("legacyTopologyMissingSource")
      owner:=FinEnergyMath.maps(observed.first["pointOwners"]).find |o| {o["pointId"] == point}
      equip:=owner?.get("equipId") as Str ?: throw ArgErr("legacyTopologyMissingMapping")
      observed.each |s|
      {
        o:=FinEnergyMath.maps(s["pointOwners"]).find |e| {e["pointId"] == point}
        if (o == null || o["point"] != true || o["his"] != true || o["equipId"] != equip || o["unit"] != owner["unit"]) throw ArgErr("legacyTopologyPointMismatch")
      }
      key:=r["id"].toStr
      if (aliases.containsKey(key) && aliases[key] != equip) throw ArgErr("legacyTopologyMissingMapping")
      aliases[key]=equip
    }
    plan:=FinEnergyLegacyMembership.plan(input,observed,aliases)
    identity:=input.dup;["action","revision","id","mod"].each |k| {identity.remove(k)}
    id:=(cx.db.idPrefix ?: "")+"finEnergy-legacy-"+digest(identity)[0..<24]
    edges:=FinEnergyMath.maps(plan["edges"])
    targets:=[Str:Obj?][,]
    edges.each |edge|
    {
      edge["proofId"]=id
      child:=equipment(edge["childId"].toStr);parent:=equipment(edge["parentId"].toStr)
      checkPoint(edge["pointId"].toStr,child,edge["unit"].toStr)
      checkPoint(edge["parentPointId"].toStr,parent,edge["unit"].toStr)
      targets.add(["child":child.id.id,"childMod":FinEnergyRepo.iso(child["mod"]),"parent":parent.id.id,"parentMod":FinEnergyRepo.iso(parent["mod"])])
      edge["name"]=child.dis
    }
    others:=active(null).findAll |e| {e["proofId"] != id}
    FinEnergyLegacyMembership.validate(others.dup.addAll(edges))
    plan.setAll(["id":id,"project":cx.proj.name,"nativeTimelineStart":FinEnergyRepo.iso(cx.db.read(Filter.has("finEnergyMeterTimeline"),false)?.get("finEnergyTimelineStart")),"limitations":["snapshotRecoveryNotCompleteEventLog","outsideImportedRangeUnknown","strictBalanceUnchanged","energyOnly"]])
    existing:=cx.db.readById(Ref(id),false)
    plan["existing"]=existing == null ? null : summary(existing)
    plan["revision"]=digest(["plan":plan,"aliases":aliases,"targets":targets,"active":others])
    return plan
  }

  [Str:Obj?][] active([Str:Obj?]? request)
  {
    out:=[Str:Obj?][,]
    cx.db.readAllList(Filter.has("finEnergyLegacyMembership").and(Filter.eq("finEnergyLegacyEnabled",true))).each |receipt|
    {
      data:=(Str:Obj?)JsonInStream(receipt["finEnergyLegacyData"].toStr.in).readJson
      if (digest(data) != receipt["finEnergyLegacyDigest"]) throw ArgErr("legacyTopologyInvalidProof")
      FinEnergyMath.maps(data["edges"]).each |edge|
      {
        if (request != null && (DateTime.fromIso(edge["from"].toStr) >= DateTime.fromIso(request["to"].toStr) || DateTime.fromIso(edge["to"].toStr) <= DateTime.fromIso(request["from"].toStr))) return
        child:=cx.db.readById(Ref(edge["childId"].toStr),false);parent:=cx.db.readById(Ref(edge["parentId"].toStr),false)
        if (child != null && parent != null && cx.canRead(child) && cx.canRead(parent)) out.add(edge)
      }
      guards.add(receipt)
    }
    FinEnergyLegacyMembership.validate(out)
    return out
  }

  // Folio has no read-set-only persistent Diff. Never touch a source record
  // merely to validate its revision; an observed race disables the receipt.
  private Void checkGuards()
  {
    if (guards.any |r| {cx.db.readById(r.id,false)?.get("mod") != r["mod"]}) throw FinEnergyHttpErr(409,"CONFLICT","legacyTopologyStalePreview")
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
    if (p == null || !p.has("point") || !p.has("his") || !cx.canRead(p) || (p["equipRef"] as Ref)?.id != equip.id.id || FinEnergyMath.unitFactor(p["unit"]?.toStr ?: "",unit) == null) throw ArgErr("legacyTopologyPointMismatch")
    guards.add(p)
  }
  private Void checkProject(Str id) {if (!(cx.db.idPrefix == null || id.startsWith(cx.db.idPrefix))) throw ArgErr("legacyTopologyWrongProject")}
  private static Str:Obj? summary(Dict r) { ["id":r.id.id,"mod":FinEnergyRepo.iso(r["mod"]),"status":r["finEnergyLegacyStatus"],"enabled":r["finEnergyLegacyEnabled"]] }
  private static Str digest(Obj? data) {JsonOutStream.writeJsonToStr(ordered(data)).toBuf.toDigest("SHA-256").toHex}
  private static Obj? ordered(Obj? value)
  {
    if (value is Map) {m:=Str:Obj?[:];m.ordered=true;((Map)value).keys.map |k->Str| {k.toStr}.sort.each |k| {m[k]=ordered(((Map)value)[k])};return m}
    if (value is List) return ((List)value).map |v->Obj?| {ordered(v)}
    return value
  }
}

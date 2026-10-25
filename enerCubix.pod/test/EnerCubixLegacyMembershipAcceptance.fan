using haystack
using folio
using folio3
using concurrent
using skyarcd
using util

** Controlled backup evidence plus real native histories, isolated project only.
class EnerCubixLegacyMembershipAcceptance
{
  Context cx
  EnerCubixRepo repo
  Ref[] owned := [,]
  File[] archives := [,]
  Int checks := 0
  new make(Context cx) {this.cx=cx;repo=EnerCubixRepo(cx)}

  Str:Obj? run()
  {
    if (!["finseed_acceptance","enerCubix_acceptance"].contains(cx.proj.name)) throw ArgErr("Legacy membership acceptance requires the isolated project")
    repo.mustWrite
    timeline:=cx.db.read(Filter.has("enerCubixMeterTimeline"),false)
    start:=(timeline?.get("enerCubixTimelineStart") as DateTime) ?: DateTime.now
    from:=start.date.toDateTime(Time.defVal,start.tz)-2day;to:=from+1day
    name:="Legacy membership acceptance "+Uuid()
    try
    {
      category:=repo.save(["kind":"category","name":name,"unit":"kWh"]);owned.add(Ref(category["id"].toStr))
      master:=meter(name+" total",category["id"].toStr,null)
      a:=meter(name+" A",category["id"].toStr,master.id)
      b:=meter(name+" B",category["id"].toStr,master.id)
      c:=meter(name+" missing C",category["id"].toStr,master.id)
      [master,a,b].each |equip,i|
      {
        p:=cx.db.readById((Ref)equip["enerCubixPointRef"]);value:=[232908f,86071f,172082f][i]
        items:=HisItem[,];25.times |h| {items.add(HisItem(from+1hr*h,Number(value*h/24f,Unit("kWh"))))}
        cx.rt.his.write(p,items,null).get(1min)
      }
      req:=Str:Obj?["kind":"leak","dimension":"metering","categoryId":category["id"],"nodeIds":[master.id.id],"from":from.toIso,"to":to.toIso,"asOf":(to+1day).toIso,"period":"day","metric":"energy","perArea":false]
      check(total(repo.report(req))["knownSubmeter"] == null,"old topology is unknown before explicit import")
      oldMaster:=Ref(cx.db.idPrefix+"lp-m-"+Uuid().toStr[0..<16]);oldA:=Ref(cx.db.idPrefix+"lp-a-"+Uuid().toStr[0..<16]);oldB:=Ref(cx.db.idPrefix+"lp-b-"+Uuid().toStr[0..<16])
      legacy:=[ledger(oldMaster,master,null,category["id"].toStr,from-1hr),ledger(oldA,a,oldMaster,category["id"].toStr,from-1hr),ledger(oldB,b,oldMaster,category["id"].toStr,from-1hr)]
      sources:=[backup(legacy,[master,a,b],"first"),backup(legacy,[master,a,b],"last")]
      input:=Str:Obj?["action":"preview","from":from.toIso,"to":to.toIso,"legacyIds":[oldA.id,oldB.id],"sources":sources]
      service:=EnerCubixLegacyMembershipRepo(repo);preview:=service.run(input)
      check(EnerCubixMath.maps(preview["edges"]).size == 2 && cx.db.readById(Ref(preview["id"].toStr),false) == null,"preview is read only and derives exact point-owner identities")
      invalid:=input.dup;invalid["sources"]=[((Map)sources.first).dup.set("sha256","0"*64),sources.last];rejects |->| {service.run(invalid)}
      invalid=input.dup;invalid["sources"]=[((Map)sources.first).dup.set("file","../outside.zip"),sources.last];rejects |->| {service.run(invalid)}
      invalid=input.dup;invalid["legacyIds"]=["p:foreign:r:unrelated"];rejects |->| {service.run(invalid)}
      current:=cx.db.readById(a.id);cx.db.commit(Diff(current,Etc.makeDict(["dis":current.dis+" changed"])))
      apply:=input.dup.set("action","apply").set("revision",preview["revision"]);rejects |->| {service.run(apply)}
      current=cx.db.readById(a.id);cx.db.commit(Diff(current,Etc.makeDict(["dis":a.dis])))
      preview=service.run(input);apply["revision"]=preview["revision"]
      unchangedRecords:=owned.findAll |id| {cx.db.readById(id).has("equip") || cx.db.readById(id).has("point")}.map |id->Dict| {cx.db.readById(id)}
      rawBefore:=[master,a,b].map |e->Obj?| {raw(e,from,to)}
      owned.add(Ref(preview["id"].toStr));receipt:=service.run(apply)
      check(unchangedRecords.all |Dict r->Bool| {return Etc.dictToMap(r) == Etc.dictToMap(cx.db.readById(r.id))},"revision checks leave device and point tags and mods untouched")
      check(service.run(apply)["alreadyApplied"] == true,"apply is idempotent")
      after:=repo.report(req);sum:=total(after)
      check(near(sum["knownTotal"],232908f) && near(sum["knownSubmeter"],258153f),"native histories and imported edges restore available child sum")
      check(sum["membershipQuality"] == "snapshotRecovered" && sum["difference"] == null && sum["percentage"] == null,"recovered snapshots do not authorize strict leakage")
      check(after["from"] == req["from"] && after["to"] == req["to"] && after["asOf"] == req["asOf"],"query bounds and cutoff are unchanged")
      own:=EnerCubixMath.maps(((Map)after["extra"])["leakOwnUsage"])
      check(own.find |r| {r["nodeId"] == c.id.id}["value"] == null,"missing third meter stays null")
      rejects |->| {service.run(["action":"rollback","id":receipt["id"],"mod":from.toIso])}
      rolled:=service.run(["action":"rollback","id":receipt["id"],"mod":receipt["mod"]])
      check(rolled["enabled"] == false,"rollback disables only the proof receipt")
      forged:=req.dup.set("legacyMembership",preview["edges"])
      check(total(repo.report(forged))["knownSubmeter"] == null,"client proof cannot bypass stored receipts")
      check(near(total(repo.report(req))["knownTotal"],232908f),"rollback preserves own usage")
      check(rawBefore == [master,a,b].map |e->Obj?| {raw(e,from,to)},"apply and rollback preserve all original cumulative samples")
      check(unchangedRecords.all |Dict r->Bool| {return Etc.dictToMap(r) == Etc.dictToMap(cx.db.readById(r.id))},"rollback leaves all device and point tags and mods untouched")
      concurrentResult:=concurrentImports(input)
      check(unchangedRecords.all |Dict r->Bool| {return Etc.dictToMap(r) == Etc.dictToMap(cx.db.readById(r.id))},"concurrent imports leave device and point tags and mods untouched")
      check(rawBefore == [master,a,b].map |e->Obj?| {raw(e,from,to)},"concurrent imports preserve all original cumulative samples")
      return ["status":"passed","checks":checks,"project":cx.proj.name,"evidenceLevel":"controlledBackupsAndNativeHistories","request":req,"preview":preview,"receipt":receipt,"rollback":rolled,"concurrentImports":concurrentResult,"report":after]
    }
    finally
    {
      cx.db.readAllList(Filter.has("enerCubixMeterEpoch")).each |r| {if (owned.contains(r["enerCubixRecordRef"])) owned.add(r.id)}
      owned.dup.unique.reverse.each |id| {r:=cx.db.readById(id,false);if (r != null) cx.db.commit(Diff(r,null,Diff.remove))}
      archives.each |f| {if (f.exists && f.parent.normalize == (cx.proj.dir+`backup/`).normalize && f.name.startsWith(cx.proj.name+"-recovery-")) f.delete}
    }
  }

  private Dict meter(Str name,Str category,Ref? parent)
  {
    equip:=cx.db.commit(Diff.makeAdd(Etc.makeDict(["equip":Marker.val,"dis":name]))).newRec;owned.add(equip.id)
    point:=cx.db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"kind":"Number","unit":"kWh","tz":"Shanghai","equipRef":equip.id,"dis":name+" point"]))).newRec;owned.add(point.id)
    data:=Str:Obj?["id":equip.id.id,"mod":EnerCubixRepo.iso(equip["mod"]),"kind":parent == null ? "totalMeter" : "meter","name":name,"categoryId":category,"pointId":point.id.id,"includeInTotals":true,"autoSum":false]
    if (parent != null) data["meterParentId"]=parent.id
    repo.save(data);return cx.db.readById(equip.id)
  }
  private Dict ledger(Ref id,Dict equip,Ref? parent,Str category,DateTime since)
  {
    tags:=Str:Obj?["seed":Marker.val,"seedKind":parent == null ? "totalMeter" : "meter","dis":equip.dis,"seedPointRef":equip["enerCubixPointRef"],"seedCategoryRef":Ref(category),"seedConfig":JsonOutStream.writeJsonToStr(["unit":"kWh","includeInTotals":true]),"seedUpdatedAt":since]
    if (parent != null) tags["seedMeterParentRef"]=parent
    return Etc.makeDict(tags.set("id",id))
  }
  private Str:Obj? backup(Dict[] records,Dict[] equips,Str suffix)
  {
    temp:=(Env.cur.tempDir+`enerCubix-recovery-fixture-${Uuid()}/`).normalize;temp.create
    pool:=ActorPool();Folio? db:=null;file:=cx.proj.dir+`backup/${cx.proj.name}-recovery-${Uuid()}-${suffix}.zip`;archives.add(file)
    try
    {
      db=Folio3.open(FolioConfig {name="legacyFixture";dir=temp;idPrefix=cx.db.idPrefix;it.pool=pool;log=Log.get("legacyFixture")})
      records.each |r| {tags:=Etc.dictToMap(r);tags.remove("id");db.commit(Diff.makeAdd(Etc.makeDict(tags),r.id.toRel(cx.db.idPrefix)))}
      equips.each |e| {p:=cx.db.readById((Ref)e["enerCubixPointRef"]);db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"kind":"Number","unit":"kWh","equipRef":e.id]),p.id.toRel(cx.db.idPrefix)))}
      db.close;db=null;pool.stop.join
      file.parent.create;zip:=Zip.write(file.out)
      try
      {
        root:=file.basename+"/db/"
        meta:=zip.writeNext(Uri.fromStr(root+"backup-meta.props"));meta.writeProps(["ts":DateTime.now.toStr,"version":"3.1.5"]);meta.close
        temp.walk |f| {if (!f.isDir && (f.name == "folio.index" || f.parent.name == "data000")) {entry:=zip.writeNext(Uri.fromStr(root+f.uri.relTo(temp.uri).toStr));entry.writeBuf(f.readAllBuf);entry.close}}
      }
      finally {zip.close}
      return ["file":file.name,"sha256":file.readAllBuf.toDigest("SHA-256").toHex.upper]
    }
    finally {if (db != null) db.close;pool.stop.join;if (temp.osPath.startsWith(Env.cur.tempDir.normalize.osPath) && temp.name.startsWith("enerCubix-recovery-fixture-")) temp.delete}
  }
  private Str:Obj? total(Str:Obj? report) {EnerCubixMath.maps(((Map)report["extra"])["leakTotals"]).first}
  private Str:Obj? concurrentImports(Str:Obj? input)
  {
    second:=input.dup.set("legacyIds",EnerCubixMath.strings(input["legacyIds"]).dup.reverse)
    requests:=[input,second].map |r->[Str:Obj?]|
    {
      plan:=EnerCubixLegacyMembershipRepo(repo).run(r)
      owned.add(Ref(plan["id"].toStr))
      return r.dup.set("action","apply").set("revision",plan["revision"])
    }
    contextRef:=Unsafe(cx);gate:=AtomicInt();pool:=ActorPool()
    outcomes:=Obj?[,]
    try
    {
      futures:=requests.map |r->Future|
      {
        worker:=Actor(pool,|Obj? msg->Obj?|
        {
          gate.increment
          attempts:=0
          while (gate.val < 2 && attempts++ < 2000) Actor.sleep(1ms)
          if (gate.val < 2) throw Err("Concurrent acceptance worker did not start")
          try {return EnerCubixLegacyMembershipRepo(EnerCubixRepo((Context)contextRef.val)).run((Str:Obj?)msg).toImmutable}
          catch (Err e) {return Str:Obj?["error":e.msg].toImmutable}
        })
        return worker.send(r.toImmutable)
      }
      outcomes=futures.map |Future f->Obj?| {f.get(1min)}
    }
    finally {pool.stop.join}
    enabled:=owned.unique.findAll |id| {cx.db.readById(id,false)?.get("enerCubixLegacyEnabled") == true}.size
    check(enabled <= 1,"concurrent overlapping receipts cannot both remain enabled")
    check(outcomes.all |Map r->Bool| {return r["error"] == null || ["legacyTopologyOverlap","legacyTopologyCycle","legacyTopologyStalePreview"].contains(r["error"])},"concurrent failures are expected relationship or version conflicts")
    EnerCubixLegacyMembershipRepo(repo).active(null)
    return ["attempts":outcomes,"enabled":enabled]
  }
  private Obj?[] raw(Dict equip,DateTime from,DateTime to)
  {
    items:=Obj?[,]
    cx.rt.his.read(cx.db.readById((Ref)equip["enerCubixPointRef"]),Span.makeAbs(from,to+1sec),Etc.makeDict(["raw":Marker.val])) |item| {items.add([item.ts,item.val])}
    return items
  }
  private Bool near(Obj? value,Float expected) {value != null && (EnerCubixMath.num(value)-expected).abs < 0.0001f}
  private Void check(Bool condition,Str message) {if (!condition) throw Err(message);checks++}
  private Void rejects(|->| action)
  {
    caught:=false
    try {action()} catch (Err e) {caught=true}
    check(caught,"invalid import or stale revision must fail")
  }
}

using haystack
using folio
using skyarcd
using util

** Staged, owned native fixture: real housekeeping must publish the first valid
** minute from fresh version-one configuration. The receipt survives disconnects.
class EnerCubixEpochIdentityAcceptance
{
  Context cx
  EnerCubixRepo repo
  Dict? receipt
  Str:Obj? state:=[:]
  Ref[] owned:=[,]
  new make(Context cx) {this.cx=cx;repo=EnerCubixRepo(cx)}

  Str:Obj? run(Str action,Str runId)
  {
    if (!["finseed_acceptance","enerCubix_acceptance"].contains(cx.proj.name)) throw ArgErr("Epoch identity acceptance requires the isolated project")
    repo.mustWrite
    if (!Regex<|[A-Za-z0-9-]{1,80}|>.matches(runId)) throw ArgErr("Invalid acceptance run ID")
    id:=Ref("enerCubix-accept-epoch-"+runId.toBuf.toDigest("SHA-256").toHex[0..<24])
    receipt=cx.db.readById(id,false)
    if (receipt != null)
    {
      state=(Str:Obj?)JsonInStream(receipt["result"].toStr.in).readJson
      owned=EnerCubixMath.strings(state["owned"]).map |s->Ref| {Ref(s)}
    }
    if (action == "stage")
    {
      if (receipt != null) return state
      receipt=cx.db.commit(Diff.makeAdd(Etc.makeDict(["enerCubixAcceptanceReceipt":Marker.val,"enerCubixAcceptanceRunId":runId,"status":"staging","result":"{}","dis":"Epoch identity acceptance receipt"]),id)).newRec
      state=["runId":runId,"status":"staging","receiptId":id.id];persist
      try {stage;return state} catch(Err err) {cleanup;state["status"]="failed";state["error"]=err.toStr;persist;throw err}
    }
    if (receipt == null) throw ArgErr("Stage this run before checking it")
    if (action == "cleanup") {cleanup;state["status"]="cleaned";persist;return state}
    if (action != "verify") throw ArgErr("Unknown epoch acceptance action")
    if (state["status"] == "passed") return state
    if (DateTime.now < DateTime.fromIso(state["readyAt"].toStr)) return state.dup.set("pending",true)
    try {verify;cleanup;state["status"]="passed";persist;return state}
    catch(Err err) {cleanup;state["status"]="failed";state["error"]=err.toStr;persist;throw err}
  }

  private Void stage()
  {
    name:="Epoch identity "+state["runId"]
    category:=save(["kind":"category","name":name+" electricity","unit":"kWh"])
    profile:=save(["kind":"cleaningProfile","name":name+" cleaner","mode":"drop","parameters":["deltaMin":0,"deltaMax":1000,"timeMax":"1h","defNull":true]])
    site:=source(["site":Marker.val,"dis":name,"tz":"Shanghai"])
    floor:=source(["floor":Marker.val,"dis":name+" floor","siteRef":site.id])
    meter:=save(["kind":"meter","name":name+" meter","createNative":true,"siteId":site.id.id,"floorId":floor.id.id,"categoryId":category["id"],"cleaningEnabled":true,"cleaningProfileId":profile["id"],"autoSum":false])
    point:=cx.db.readById(Ref(meter["pointId"].toStr));track(point.id)
    expression:=save(["kind":"expression","name":name+" double","formula":"a * 2","variables":["a":meter["id"]]])
    virtualMeter:=save(["kind":"meter","name":name+" virtual","createVirtual":true,"siteId":site.id.id,"floorId":floor.id.id,"categoryId":category["id"],"expressionId":expression["id"],"autoSum":false])
    state.setAll(["siteId":site.id.id,"categoryId":category["id"],"profileId":profile["id"],"meterId":meter["id"],"pointId":point.id.id,"expressionId":expression["id"],"virtualId":virtualMeter["id"]]);persist
    epochs:=cx.db.readAllList(Filter.has("enerCubixMeterEpoch"))
    [category,profile,expression,meter,virtualMeter].each |record|
    {
      version:=epochs.find |r| {(r["enerCubixRecordRef"] as Ref)?.id == record["id"] && !r.has("enerCubixEpochRemoved")}
      if (version == null || ((Map)JsonInStream(version["enerCubixEpochConfig"].toStr.in).readJson)["id"] != record["id"]) throw Err("Initial epoch has a different identity")
    }
    start:=EnerCubixMeterHistory.floorMinute(DateTime.now)+1min
    samples:=[HisItem(start,Number(100,Unit("kWh"))),HisItem(start+30sec,Number(107,Unit("kWh"))),HisItem(start+1min,Number(110,Unit("kWh")))]
    cx.rt.his.write(point,samples,null).get(1min)
    state.setAll(["from":start.toIso,"to":(start+1min).toIso,"readyAt":(start+3min+10sec).toIso,"status":"staged","expected":10f,"expectedVirtual":20f,"raw":[100f,107f,110f],"initialEpochIdsMatch":true]);persist
  }

  private Void verify()
  {
    from:=DateTime.fromIso(state["from"].toStr);to:=DateTime.fromIso(state["to"].toStr)
    point:=cx.db.readById(Ref(state["pointId"].toStr))
    data:=EnerCubixMeterHistory.loadDb(cx.db,point,from,to)
    if (data == null) throw Err("Background generation has not published the owned meter")
    usage:=EnerCubixHistoryData(data).read(from,to)
    if (usage.value != 10f || usage.quality != "cleaned") throw Err("First owned minute: "+usage.value+" / "+usage.quality)
    formula:=cx.db.readById(EnerCubixMeterHistory.formulaId(Ref(state["virtualId"].toStr)),false)
    if (formula == null) throw Err("Background generation has not created the formula point")
    track(formula.id)
    formulaData:=EnerCubixMeterHistory.loadDb(cx.db,formula,from,to)
    if (formulaData == null) throw Err("Formula minute was not published")
    value:=EnerCubixHistoryData(formulaData).read(from,to)
    if (value.value != 20f) throw Err("Formula did not resolve the initial expression/category identities")
    virtualRecord:=EnerCubixMath.maps(repo.catalog["records"]).find |r| {r["id"] == state["virtualId"]}
    if (virtualRecord == null || virtualRecord["historyPointId"] != formula.id.id || virtualRecord["includeInTotals"] != false) throw Err("Native catalog must reference the committed archive without changing scope inclusion")
    reports:=[Str:Obj?][,]
    ["profile","ranking","proportion","comparison"].each |kind|
    {
      request:=["kind":kind,"dimension":"metering","nodeIds":[state["virtualId"]],"from":from.toIso,"to":to.toIso,"asOf":to.toIso,"period":"hour","metric":"energy","perArea":false]
      report:=repo.report(request)
      total:=EnerCubixMath.maps(((Map)report["summary"])["knownTotals"]).first
      sources:=EnerCubixMath.strings(total["sourceIds"])
      if (total["value"] != 20f || !sources.contains(formula.id.id) || sources.contains(formula.id.toProjRel.id)) throw Err("Ordinary "+kind+" did not read the qualified published formula history")
      if (kind == "proportion" && EnerCubixMath.maps(report["rows"]).first["knownPercentage"] != 100f) throw Err("Explicit virtual proportion must be fully represented")
      reports.add(["kind":kind,"value":total["value"],"sourceIds":sources])
    }
    scope:=repo.report(["kind":"dashboard","dimension":"space","spaceSource":"fin","nodeIds":[state["siteId"]],"from":from.toIso,"to":to.toIso,"asOf":to.toIso,"period":"hour","metric":"energy","perArea":false])
    scopeTotal:=EnerCubixMath.maps(((Map)scope["summary"])["selectionTotals"]).first
    if (scopeTotal["knownValue"] != 10f || EnerCubixMath.strings(scopeTotal["meterIds"]).contains(state["virtualId"])) throw Err("Excluded virtual meter changed ordinary space totals")
    raw:=HisItem[,];cx.rt.his.read(point,Span.makeAbs(from,to+1sec),Etc.makeDict(["raw":Marker.val])) |item| {raw.add(item)}
    if (raw.map |s->Float| {((Number)s.val).toFloat} != [100f,107f,110f]) throw Err("Owned raw readings changed")
    missing:=EnerCubixMeterHistory.loadDb(cx.db,point,to,to+1min)
    if (missing == null || EnerCubixHistoryData(missing).read(to,to+1min).quality != "missing") throw Err("No source data must mean missing rather than missingCleaningProfile")
    state.setAll(["value":usage.value,"quality":usage.quality,"formulaValue":value.value,"rawPreserved":true,"missingQuality":"missing","profileVersion":1,"historyPointId":virtualRecord["historyPointId"],"includeInTotals":false,"ordinaryReports":reports,"spaceTotal":scopeTotal["knownValue"]])
  }

  private Str:Obj? save(Str:Obj? record) {r:=repo.save(record);track(Ref(r["id"].toStr));return r}
  private Dict source(Str:Obj? tags) {r:=cx.db.commit(Diff.makeAdd(Etc.makeDict(tags))).newRec;track(r.id);return cx.db.readById(r.id)}
  private Void track(Ref id)
  {
    if (!owned.contains(id)) owned.add(id)
    state["owned"]=owned.map |r->Str| {r.id};persist
  }
  private Void persist()
  { receipt=cx.db.commit(Diff(cx.db.readById(receipt.id),Etc.makeDict(["status":state["status"],"result":JsonOutStream.writeJsonToStr(state)]))).newRec }
  private Void cleanup()
  {
    ownEquips:=owned.findAll |id| {cx.db.readById(id,false)?.has("equip") == true}
    ownEquips.each |id|
    {
      if (cx.db.readById(id).has("enerCubixVirtual"))
      {
        formula:=cx.db.readById(EnerCubixMeterHistory.formulaId(id),false)
        if (formula != null && formula.has("enerCubixFormulaResult") && !owned.contains(formula.id)) owned.add(formula.id)
      }
    }
    virtualIds:=ownEquips.findAll |id| {cx.db.readById(id).has("enerCubixVirtual")}
    expressionIds:=owned.findAll |id| {cx.db.readById(id,false)?.get("enerCubixKind") == "expression"}
    virtualIds.dup.addAll(expressionIds).addAll(ownEquips.findAll |id| {!virtualIds.contains(id)}).each |id|
    {
      r:=cx.db.readById(id,false)
      if (r?.has("enerCubix") == true) repo.remove(id.id,EnerCubixRepo.iso(r["mod"]))
    }
    pointIds:=owned.findAll |id| {cx.db.readById(id,false)?.has("point") == true}
    cx.db.readAllList(Filter.has("enerCubixComputed").or(Filter.has("enerCubixMeterGeneration")).or(Filter.has("enerCubixIntervalBatch")).or(Filter.has("enerCubixGenerationIssue"))).each |r|
    {
      main:=r["enerCubixMainRef"] as Ref;source:=r["enerCubixIntervalSourceRef"] as Ref;owner:=r["enerCubixOwnerRef"] as Ref
      if ((main != null && pointIds.contains(main)) || (source != null && pointIds.contains(source)) || (owner != null && owned.contains(owner))) cx.db.commit(Diff(r,null,Diff.remove))
    }
    owned.dup.reverse.each |id| {r:=cx.db.readById(id,false);if(r != null)cx.db.commit(Diff(r,null,Diff.remove))}
    state["owned"]=owned.map |r->Str| {r.id}
    state["ownedRemaining"]=owned.findAll |id| {cx.db.readById(id,false) != null}.size
  }
}

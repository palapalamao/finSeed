using axon
using haystack
using hisExt
using skyarcd
using util

const class FinEnergyLib
{
  @Axon
  static Str finEnergyAppUri() { "/api/"+Context.cur.proj.name+"/ext/finEnergy/" }

  @Axon
  static Dict finEnergyInfo() { Etc.makeDict(["pod":FinEnergyLib#.pod.name,"version":FinEnergyLib#.pod.version.toStr,"user":Context.cur.user.username]) }

  ** Computed history entry: raw reads bypass the function; normal reads emit
  ** cleaned, interval-start consumption through FIN's native yield callback.
  @Axon
  static Obj? finEnergyCleanHis(Dict rec, Obj? dates, Dict opts, Fn yield, Dict config := Etc.emptyDict)
  {
    cx:=Context.cur
    span:=HisLib.hisReadSpan(rec,dates)
    if (span == null) throw ArgErr("Cleaning requires a bounded history span")
    if (opts.has("raw"))
    {
      cx.rt.his.read(rec,span,opts) |HisItem item| { yield.call(cx,[item.ts,item.val]) }
      return null
    }
    result:=FinEnergyHistory.cleanRead(cx,rec,span,opts,config)
    FinEnergyHistory.nativeItems(result).each |item| { yield.call(cx,[item.ts,item.val]) }
    return null
  }

  @Axon { admin=true }
  static Dict finEnergyNativeSpaceAcceptance() { jsonResult(FinEnergyNativeSpaceAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyAreaAcceptance() { jsonResult(FinEnergyAreaAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyNativeAlarmAcceptance() { jsonResult(FinEnergyNativeAlarmAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyRenameNamespace(Str from, Str to, Bool apply := false, Str? revision := null)
  { FinEnergyNamespace.run(from,to,apply,revision) }

  ** Native Axon administration uses the same validation and permissions as the UI.
  @Axon
  static Dict finEnergyCatalog() { jsonResult(FinEnergyRepo(Context.cur).catalog) }

  ** Bounded read-only native navigation metadata for deployment verification.
  @Axon
  static Dict finEnergyNativeSpaceInfo() { jsonResult(FinEnergyRepo(Context.cur).nativeSpaceInfo) }

  @Axon { admin=true }
  static Dict finEnergyNativeEquipAcceptance() { jsonResult(FinEnergyNativeEquipAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyDirectEquipAcceptance() { jsonResult(FinEnergyDirectEquipAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyOwnedHistoryAcceptance() { jsonResult(FinEnergyOwnedHistoryAcceptance(Context.cur).run) }

  @Axon { admin = true }
  static Dict finEnergyLeakHistoryAcceptance() { jsonResult(FinEnergyOwnedHistoryAcceptance(Context.cur).run(true)) }

  @Axon { admin = true }
  static Dict finEnergyLegacyMembership(Str json)
  { jsonResult(FinEnergyLegacyMembershipRepo(FinEnergyRepo(Context.cur)).run((Str:Obj?)JsonInStream(json.in).readJson)) }

  @Axon { admin=true }
  static Dict finEnergyLegacyMembershipAcceptance() { jsonResult(FinEnergyLegacyMembershipAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyFlowHistoryAcceptance() { jsonResult(FinEnergyFlowHistoryAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyQueryReplayAcceptance(Str json) { jsonResult(FinEnergyQueryReplayAcceptance(Context.cur).run(json)) }

  @Axon { admin=true }
  static Dict finEnergyNativeMeterCreationAcceptance() { jsonResult(FinEnergyDirectEquipAcceptance(Context.cur).runCreation) }

  @Axon { admin=true }
  static Dict finEnergyNativeEquipStageAcceptance() { jsonResult(FinEnergyNativeEquipAcceptance(Context.cur).run(true)) }

  @Axon { admin=true }
  static Dict finEnergySaveConfig(Str json)
  {
    rec := (Str:Obj?)JsonInStream(json.in).readJson
    return jsonResult(FinEnergyRepo(Context.cur).save(rec))
  }

  @Axon
  static Dict finEnergyReport(Str json)
  {
    request := (Str:Obj?)JsonInStream(json.in).readJson
    return jsonResult(FinEnergyRepo(Context.cur).report(request))
  }

  @Axon
  static Dict finEnergyCleaningPreview(Str json)
  { jsonResult(FinEnergyCleaningRepo(FinEnergyRepo(Context.cur)).preview((Str:Obj?)JsonInStream(json.in).readJson)) }

  @Axon { admin=true }
  static Dict finEnergyCleaningAcceptance()
  { jsonResult(FinEnergyCleaningAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyCleaningVirtualAcceptance()
  { jsonResult(FinEnergyCleaningVirtualAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyCleaningBoundaryAcceptance()
  { jsonResult(FinEnergyCleaningBoundaryAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyCrossModuleAcceptance(Str? runId := null)
  { jsonResult(FinEnergyCrossModuleAcceptance(Context.cur).run(runId)) }

  @Axon { admin=true }
  static Dict finEnergyEpochIdentityAcceptance(Str action, Str runId)
  { jsonResult(FinEnergyEpochIdentityAcceptance(Context.cur).run(action,runId)) }

  private static Dict jsonResult(Obj data) { Etc.makeDict(["result":JsonOutStream.writeJsonToStr(data)]) }

  @Axon { admin=true }
  static Dict finEnergyManage(Str json) { jsonResult(FinEnergyRepo(Context.cur).manage((Str:Obj?)JsonInStream(json.in).readJson)) }

  @Axon { admin=true }
  static Dict finEnergyMigrate(Str json) { jsonResult(FinEnergyRepo(Context.cur).migration((Str:Obj?)JsonInStream(json.in).readJson)) }

  @Axon { admin=true }
  static Dict finEnergyEngineeringAcceptance() { jsonResult(FinEnergyEngineeringAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyThreeTreeAcceptance() { jsonResult(FinEnergyThreeTreeAcceptance(Context.cur).run) }

  ** Reproducible integration checks restricted to the independent acceptance project.
  @Axon { admin=true }
  static Dict finEnergyAcceptance()
  {
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(FinEnergyAcceptance(Context.cur).run)])
  }

  ** Exercise the real HTTP routes from the audited native FIN request context.
  @Axon { admin=true }
  static Dict finEnergyTransportAcceptance()
  {
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(FinEnergyHttpProbe().run)])
  }

  @Axon
  static Dict finEnergyPermissionAcceptance()
  {
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(FinEnergyHttpProbe().permissions)])
  }

  ** Test-only browser bridge; native FIN identity and route permissions still apply.
  @Axon
  static Dict finEnergyAcceptanceRequest(Str path, Str? payload := null)
  {
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(FinEnergyHttpProbe().proxy(path,payload))])
  }

  ** Native scheduled-job entry; configuration determines calculation/alarm enablement.
  @Axon { admin=true }
  static Dict finEnergyScheduled()
  {
    result := FinEnergyJobs(FinEnergyRepo(Context.cur)).scheduled
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(result)])
  }

  ** Bounded administration path shared with the scan button and scheduled job.
  @Axon { admin=true }
  static Dict finEnergyScanAlarms(Str from, Str to)
  { jsonResult(FinEnergyJobs(FinEnergyRepo(Context.cur)).run(["action":"scanAlarms","from":from,"to":to])) }
}

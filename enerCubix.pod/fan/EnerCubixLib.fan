using axon
using haystack
using hisExt
using skyarcd
using util

const class EnerCubixLib
{
  @Axon
  static Str enerCubixAppUri() { "/api/"+Context.cur.proj.name+"/ext/enerCubix/" }

  @Axon
  static Dict enerCubixInfo() { Etc.makeDict(["pod":EnerCubixLib#.pod.name,"version":EnerCubixLib#.pod.version.toStr,"user":Context.cur.user.username]) }

  ** Computed history entry: raw reads bypass the function; normal reads emit
  ** cleaned, interval-start consumption through FIN's native yield callback.
  @Axon
  static Obj? enerCubixCleanHis(Dict rec, Obj? dates, Dict opts, Fn yield, Dict config := Etc.emptyDict)
  {
    cx:=Context.cur
    span:=HisLib.hisReadSpan(rec,dates)
    if (span == null) throw ArgErr("Cleaning requires a bounded history span")
    if (opts.has("raw"))
    {
      cx.rt.his.read(rec,span,opts) |HisItem item| { yield.call(cx,[item.ts,item.val]) }
      return null
    }
    result:=EnerCubixHistory.cleanRead(cx,rec,span,opts,config)
    EnerCubixHistory.nativeItems(result).each |item| { yield.call(cx,[item.ts,item.val]) }
    return null
  }

  @Axon { admin=true }
  static Dict enerCubixNativeSpaceAcceptance() { jsonResult(EnerCubixNativeSpaceAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict enerCubixNativeAlarmAcceptance() { jsonResult(EnerCubixNativeAlarmAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict enerCubixRenameNamespace(Str from, Str to, Bool apply := false, Str? revision := null)
  { EnerCubixNamespace.run(from,to,apply,revision) }

  ** Native Axon administration uses the same validation and permissions as the UI.
  @Axon
  static Dict enerCubixCatalog() { jsonResult(EnerCubixRepo(Context.cur).catalog) }

  ** Bounded read-only native navigation metadata for deployment verification.
  @Axon
  static Dict enerCubixNativeSpaceInfo() { jsonResult(EnerCubixRepo(Context.cur).nativeSpaceInfo) }

  @Axon { admin=true }
  static Dict enerCubixNativeEquipAcceptance() { jsonResult(EnerCubixNativeEquipAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict enerCubixDirectEquipAcceptance() { jsonResult(EnerCubixDirectEquipAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict enerCubixOwnedHistoryAcceptance() { jsonResult(EnerCubixOwnedHistoryAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict enerCubixFlowHistoryAcceptance() { jsonResult(EnerCubixFlowHistoryAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict enerCubixQueryReplayAcceptance(Str json) { jsonResult(EnerCubixQueryReplayAcceptance(Context.cur).run(json)) }

  @Axon { admin=true }
  static Dict enerCubixNativeMeterCreationAcceptance() { jsonResult(EnerCubixDirectEquipAcceptance(Context.cur).runCreation) }

  @Axon { admin=true }
  static Dict enerCubixNativeEquipStageAcceptance() { jsonResult(EnerCubixNativeEquipAcceptance(Context.cur).run(true)) }

  @Axon { admin=true }
  static Dict enerCubixSaveConfig(Str json)
  {
    rec := (Str:Obj?)JsonInStream(json.in).readJson
    return jsonResult(EnerCubixRepo(Context.cur).save(rec))
  }

  @Axon
  static Dict enerCubixReport(Str json)
  {
    request := (Str:Obj?)JsonInStream(json.in).readJson
    return jsonResult(EnerCubixRepo(Context.cur).report(request))
  }

  @Axon
  static Dict enerCubixCleaningPreview(Str json)
  { jsonResult(EnerCubixCleaningRepo(EnerCubixRepo(Context.cur)).preview((Str:Obj?)JsonInStream(json.in).readJson)) }

  @Axon { admin=true }
  static Dict enerCubixCleaningAcceptance()
  { jsonResult(EnerCubixCleaningAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict enerCubixCleaningVirtualAcceptance()
  { jsonResult(EnerCubixCleaningVirtualAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict enerCubixCleaningBoundaryAcceptance()
  { jsonResult(EnerCubixCleaningBoundaryAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict enerCubixCrossModuleAcceptance(Str? runId := null)
  { jsonResult(EnerCubixCrossModuleAcceptance(Context.cur).run(runId)) }

  @Axon { admin=true }
  static Dict enerCubixEpochIdentityAcceptance(Str action, Str runId)
  { jsonResult(EnerCubixEpochIdentityAcceptance(Context.cur).run(action,runId)) }

  private static Dict jsonResult(Obj data) { Etc.makeDict(["result":JsonOutStream.writeJsonToStr(data)]) }

  @Axon { admin=true }
  static Dict enerCubixManage(Str json) { jsonResult(EnerCubixRepo(Context.cur).manage((Str:Obj?)JsonInStream(json.in).readJson)) }

  @Axon { admin=true }
  static Dict enerCubixMigrate(Str json) { jsonResult(EnerCubixRepo(Context.cur).migration((Str:Obj?)JsonInStream(json.in).readJson)) }

  @Axon { admin=true }
  static Dict enerCubixEngineeringAcceptance() { jsonResult(EnerCubixEngineeringAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict enerCubixThreeTreeAcceptance() { jsonResult(EnerCubixThreeTreeAcceptance(Context.cur).run) }

  ** Reproducible integration checks restricted to the independent acceptance project.
  @Axon { admin=true }
  static Dict enerCubixAcceptance()
  {
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(EnerCubixAcceptance(Context.cur).run)])
  }

  ** Exercise the real HTTP routes from the audited native FIN request context.
  @Axon { admin=true }
  static Dict enerCubixTransportAcceptance()
  {
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(EnerCubixHttpProbe().run)])
  }

  @Axon
  static Dict enerCubixPermissionAcceptance()
  {
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(EnerCubixHttpProbe().permissions)])
  }

  ** Test-only browser bridge; native FIN identity and route permissions still apply.
  @Axon
  static Dict enerCubixAcceptanceRequest(Str path, Str? payload := null)
  {
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(EnerCubixHttpProbe().proxy(path,payload))])
  }

  ** Native scheduled-job entry; configuration determines calculation/alarm enablement.
  @Axon { admin=true }
  static Dict enerCubixScheduled()
  {
    result := EnerCubixJobs(EnerCubixRepo(Context.cur)).scheduled
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(result)])
  }

  ** Bounded administration path shared with the scan button and scheduled job.
  @Axon { admin=true }
  static Dict enerCubixScanAlarms(Str from, Str to)
  { jsonResult(EnerCubixJobs(EnerCubixRepo(Context.cur)).run(["action":"scanAlarms","from":from,"to":to])) }
}

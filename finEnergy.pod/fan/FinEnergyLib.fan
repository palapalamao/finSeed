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
  static Dict finEnergyNativeSpaceAcceptance() { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyNativeSpaceAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyAreaAcceptance() { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyAreaAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyNativeAlarmAcceptance() { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyNativeAlarmAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyRenameNamespace(Str from, Str to, Bool apply := false, Str? revision := null)
  { FinEnergyNamespace.run(from,to,apply,revision) }

  @Axon { admin=true }
  static Dict finEnergyResumeNamespace(Str backup) { FinEnergyNamespace.resume(backup) }

  @Axon { admin=true }
  static Dict finEnergyRollbackNamespace(Str backup) { FinEnergyNamespace.rollback(backup) }

  ** Native Axon administration uses the same validation and permissions as the UI.
  @Axon
  static Dict finEnergyCatalog() { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyRepo(Context.cur).catalog) }

  ** Bounded read-only native navigation metadata for deployment verification.
  @Axon
  static Dict finEnergyNativeSpaceInfo() { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyRepo(Context.cur).nativeSpaceInfo) }

  @Axon { admin=true }
  static Dict finEnergyNativeEquipAcceptance() { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyNativeEquipAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyDirectEquipAcceptance() { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyDirectEquipAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyOwnedHistoryAcceptance() { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyOwnedHistoryAcceptance(Context.cur).run) }

  @Axon { admin = true }
  static Dict finEnergyLeakHistoryAcceptance() { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyOwnedHistoryAcceptance(Context.cur).run(true)) }

  @Axon { admin = true }
  static Dict finEnergyLegacyMembership(Str json)
  { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyLegacyMembershipRepo(FinEnergyRepo(Context.cur)).run((Str:Obj?)JsonInStream(json.in).readJson)) }

  @Axon { admin=true }
  static Dict finEnergyLegacyMembershipAcceptance() { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyLegacyMembershipAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyFlowHistoryAcceptance() { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyFlowHistoryAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyQueryReplayAcceptance(Str json) { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyQueryReplayAcceptance(Context.cur).run(json)) }

  @Axon { admin=true }
  static Dict finEnergyNativeMeterCreationAcceptance() { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyDirectEquipAcceptance(Context.cur).runCreation) }

  @Axon { admin=true }
  static Dict finEnergyNativeEquipStageAcceptance() { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyNativeEquipAcceptance(Context.cur).run(true)) }

  @Axon { admin=true }
  static Dict finEnergySaveConfig(Str json)
  { FinEnergyRepo(Context.cur).requireLicensedCalculation;
    rec := (Str:Obj?)JsonInStream(json.in).readJson
    return jsonResult(FinEnergyRepo(Context.cur).save(rec))
  }

  @Axon
  static Dict finEnergyReport(Str json)
  { FinEnergyRepo(Context.cur).requireLicensedCalculation;
    request := (Str:Obj?)JsonInStream(json.in).readJson
    return jsonResult(FinEnergyRepo(Context.cur).report(request))
  }

  @Axon
  static Dict finEnergyCleaningPreview(Str json)
  { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyCleaningRepo(FinEnergyRepo(Context.cur)).preview((Str:Obj?)JsonInStream(json.in).readJson)) }

  @Axon { admin=true }
  static Dict finEnergyCleaningAcceptance()
  { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyCleaningAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyCleaningVirtualAcceptance()
  { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyCleaningVirtualAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyCleaningBoundaryAcceptance()
  { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyCleaningBoundaryAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyCrossModuleAcceptance(Str? runId := null)
  { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyCrossModuleAcceptance(Context.cur).run(runId)) }

  @Axon { admin=true }
  static Dict finEnergyEpochIdentityAcceptance(Str action, Str runId)
  { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyEpochIdentityAcceptance(Context.cur).run(action,runId)) }

  private static Dict jsonResult(Obj data) { Etc.makeDict(["result":JsonOutStream.writeJsonToStr(data)]) }

  @Axon { admin=true }
  static Dict finEnergyManage(Str json) { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyRepo(Context.cur).manage((Str:Obj?)JsonInStream(json.in).readJson)) }

  @Axon { admin=true }
  static Dict finEnergyMigrate(Str json) { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyRepo(Context.cur).migration((Str:Obj?)JsonInStream(json.in).readJson)) }

  @Axon { admin=true }
  static Dict finEnergyEngineeringAcceptance() { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyEngineeringAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict finEnergyThreeTreeAcceptance() { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyThreeTreeAcceptance(Context.cur).run) }

  ** Reproducible integration checks restricted to the independent acceptance project.
  @Axon { admin=true }
  static Dict finEnergyAcceptance()
  { FinEnergyRepo(Context.cur).requireLicensedCalculation;
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(FinEnergyAcceptance(Context.cur).run)])
  }

  ** Exercise the real HTTP routes from the audited native FIN request context.
  @Axon { admin=true }
  static Dict finEnergyTransportAcceptance()
  { FinEnergyRepo(Context.cur).requireLicensedCalculation;
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(FinEnergyHttpProbe().run)])
  }

  @Axon
  static Dict finEnergyPermissionAcceptance()
  { FinEnergyRepo(Context.cur).requireLicensedCalculation;
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(FinEnergyHttpProbe().permissions)])
  }

  ** Test-only browser bridge; native FIN identity and route permissions still apply.
  @Axon
  static Dict finEnergyAcceptanceRequest(Str path, Str? payload := null)
  { FinEnergyRepo(Context.cur).requireLicensedCalculation;
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(FinEnergyHttpProbe().proxy(path,payload))])
  }

  ** Native scheduled-job entry; configuration determines calculation/alarm enablement.
  @Axon { admin=true }
  static Dict finEnergyScheduled()
  { FinEnergyRepo(Context.cur).requireLicensedCalculation;
    result := FinEnergyJobs(FinEnergyRepo(Context.cur)).scheduled
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(result)])
  }

  ** Bounded administration path shared with the scan button and scheduled job.
  @Axon { admin=true }
  static Dict finEnergyScanAlarms(Str from, Str to)
  { FinEnergyRepo(Context.cur).requireLicensedCalculation; return jsonResult(FinEnergyJobs(FinEnergyRepo(Context.cur)).run(["action":"scanAlarms","from":from,"to":to])) }
}

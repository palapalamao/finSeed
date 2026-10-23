using axon
using haystack
using skyarcd
using util

const class SeedLib
{
  @Axon
  static Str enerCubixAppUri() { "/api/"+Context.cur.proj.name+"/ext/enerCubix/" }

  ** Compatibility entry point for existing saved Axon expressions.
  @Axon
  static Str seedAppUri() { enerCubixAppUri() }

  @Axon
  static Dict enerCubixInfo() { Etc.makeDict(["pod":SeedLib#.pod.name,"version":SeedLib#.pod.version.toStr,"user":Context.cur.user.username]) }

  @Axon
  static Dict seedInfo() { enerCubixInfo() }

  @Axon { admin=true }
  static Dict seedNativeSpaceAcceptance() { jsonResult(SeedNativeSpaceAcceptance(Context.cur).run) }

  ** Native Axon administration uses the same validation and permissions as the UI.
  @Axon
  static Dict seedCatalog() { jsonResult(SeedRepo(Context.cur).catalog) }

  ** Bounded read-only native navigation metadata for deployment verification.
  @Axon
  static Dict seedNativeSpaceInfo() { jsonResult(SeedRepo(Context.cur).nativeSpaceInfo) }

  @Axon { admin=true }
  static Dict seedNativeEquipAcceptance() { jsonResult(SeedNativeEquipAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict seedNativeEquipStageAcceptance() { jsonResult(SeedNativeEquipAcceptance(Context.cur).run(true)) }

  @Axon { admin=true }
  static Dict seedSaveConfig(Str json)
  {
    rec := (Str:Obj?)JsonInStream(json.in).readJson
    return jsonResult(SeedRepo(Context.cur).save(rec))
  }

  @Axon
  static Dict seedReport(Str json)
  {
    request := (Str:Obj?)JsonInStream(json.in).readJson
    return jsonResult(SeedRepo(Context.cur).report(request))
  }

  private static Dict jsonResult(Obj data) { Etc.makeDict(["result":JsonOutStream.writeJsonToStr(data)]) }

  @Axon { admin=true }
  static Dict seedManage(Str json) { jsonResult(SeedRepo(Context.cur).manage((Str:Obj?)JsonInStream(json.in).readJson)) }

  @Axon { admin=true }
  static Dict seedMigrate(Str json) { jsonResult(SeedRepo(Context.cur).migration((Str:Obj?)JsonInStream(json.in).readJson)) }

  @Axon { admin=true }
  static Dict seedEngineeringAcceptance() { jsonResult(SeedEngineeringAcceptance(Context.cur).run) }

  @Axon { admin=true }
  static Dict seedThreeTreeAcceptance() { jsonResult(SeedThreeTreeAcceptance(Context.cur).run) }

  ** Reproducible integration checks restricted to the independent acceptance project.
  @Axon { admin=true }
  static Dict seedAcceptance()
  {
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(SeedAcceptance(Context.cur).run)])
  }

  ** Exercise the real HTTP routes from the audited native FIN request context.
  @Axon { admin=true }
  static Dict seedTransportAcceptance()
  {
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(SeedHttpProbe().run)])
  }

  @Axon
  static Dict seedPermissionAcceptance()
  {
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(SeedHttpProbe().permissions)])
  }

  ** Test-only browser bridge; native FIN identity and route permissions still apply.
  @Axon
  static Dict seedAcceptanceRequest(Str path, Str? payload := null)
  {
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(SeedHttpProbe().proxy(path,payload))])
  }

  ** Native scheduled-job entry; configuration determines calculation/alarm enablement.
  @Axon { admin=true }
  static Dict seedScheduled()
  {
    result := SeedJobs(SeedRepo(Context.cur)).scheduled
    return Etc.makeDict(["result":JsonOutStream.writeJsonToStr(result)])
  }
}

#! /usr/bin/env fan
using finBuild

class Args : BuildFinArgs
{
  new make() : super(Build#make) {}
}

class Build : BuildFinPod
{
  new make(Args args) : super(args)
  {
    edition := Env.cur.vars["FINENERGY_BUILD_EDITION"]
    if (edition != "china" && edition != "hq") throw ArgErr("Set an explicit FIN Energy build edition: china or hq")
    podName = "finEnergy"
    summary = "FIN Energy - Building Energy Analytics"
    version = Version("0.16.9")
    meta = ["proj.name":podName, "org.name":"FinEnergy", "license.name":"Commercial",
            "finEnergy.edition":edition, "finEnergy.licenseMode":edition == "china" ? "selfManaged" : "finNative"]
    commit := Env.cur.vars["FINENERGY_BUILD_COMMIT"]
    if (commit != null && !commit.isEmpty) meta["finEnergy.sourceCommit"] = commit
    depends = [
      "sys 1.0+", "concurrent 1.0+", "web 1.0+", "util 1.0+",
      "haystack 3.1.5.1+", "axon 3.1.5+", "folio 3.1.5+", "folio3 3.1.5+",
      "hx 3.1.5+", "skyarc 3.1.5+", "skyarcd 3.1.5+", "legacy 3.1.5+",
      "hisExt 3.1.5+", "finStackCoreExt 5.3.0.2761+", "fin 5.3.0.2761+", "alarmExt 5.3.0.2761+",
    ]
    // BuildFinPod has no testDirs. Source and resource directories are not recursive.
    srcDirs = [`fan/`, `fan/engine/`, `test/`]
    srcDirs.add("editions/${edition}/fan/".toUri).add("editions/${edition}/test/".toUri)
    resDirs = [`lib/`, `locale/`, `res/`, `res/web/`, `res/web/finEnergy/`,
               `res/web/finEnergy/modules/`]
    nodeDirs = Env.cur.vars["FINENERGY_UI_BUILT"] == "true" ? Uri[,] : [`ts/`]
    index = ["skyarc.ext":"finEnergy::FinEnergyExt", "skyarc.lib":"finEnergy::FinEnergyLib", "fin.lang":"finEnergy"]
  }
}

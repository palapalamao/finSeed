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
    podName = "enerCubix"
    summary = "EnergyCubix - Building Energy Analytics"
    version = Version("0.12.6")
    meta = ["proj.name":podName, "org.name":"EnerCubix", "license.name":"Commercial"]
    depends = [
      "sys 1.0+", "concurrent 1.0+", "web 1.0+", "util 1.0+",
      "haystack 3.1.5.1+", "axon 3.1.5+", "folio 3.1.5+", "folio3 3.1.5+",
      "hx 3.1.5+", "skyarc 3.1.5+", "skyarcd 3.1.5+", "legacy 3.1.5+",
      "hisExt 3.1.5+", "finStackCoreExt 5.3.0.2761+", "alarmExt 5.3.0.2761+",
    ]
    // BuildFinPod has no testDirs. Source and resource directories are not recursive.
    srcDirs = [`fan/`, `fan/engine/`, `test/`]
    resDirs = [`lib/`, `locale/`, `res/`, `res/web/`, `res/web/enerCubix/`,
               `res/web/enerCubix/modules/`]
    nodeDirs = Env.cur.vars["ENERCUBIX_UI_BUILT"] == "true" ? Uri[,] : [`ts/`]
    index = ["skyarc.ext":"enerCubix::EnerCubixExt", "skyarc.lib":"enerCubix::EnerCubixLib", "fin.lang":"enerCubix"]
  }
}

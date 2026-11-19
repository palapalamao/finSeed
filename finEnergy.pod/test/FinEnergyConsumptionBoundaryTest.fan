using haystack

class FinEnergyConsumptionBoundaryTest : Test
{
  Void testNativeAndReportShareStartStampedHour()
  {
    p:=point("finEnergyCleanHis"); raw:=HisItem[,]
    [100f,112f,107f,115f,120f].each |n,i| { raw.add(HisItem(at+15min*i,Number(n,Unit("kWh")))) }
    result:=FinEnergyCleaning.clean(p,raw,FinEnergyCleaning.config(["deltaMin":0,"defNull":true],"kWh"))
    nativeRows:=FinEnergyHistory.nativeItems(result)
    verifyEq(nativeRows.first.ts,at); verifyEq(nativeRows.last.ts,at+45min)
    verifyEq(nativeRows.map |i->Obj?| { i.val },Obj?[Number(12,Unit("kWh")),null,Number(8,Unit("kWh")),Number(5,Unit("kWh"))])
    total:=0f; nativeRows.findAll |i| { i.ts >= at && i.ts < at+1hr }.each |i| { if (i.val is Number) total+=((Number)i.val).toFloat }
    verifyEq(total,25f)
    report:=FinEnergyHistoryData(FinEnergyHistory.normalizeClean(p,result,at,at+1hr)).read(at,at+1hr)
    verifyEq(report.value,total); verifyEq(report.quality,"filtered")
    verifyEq(raw.last.ts,at+1hr); verifyEq(((Number)raw.last.val).toFloat,120f)
    trend:=FinEnergyMath.maps(FinEnergyHistory.normalizeClean(p,result,at,at+1hr,true)["samples"])
    verifyEq(trend.first["ts"],at.toIso); verifyEq(trend.last["ts"],(at+45min).toIso)
  }

  Void testManualFunctionConsumptionStartsAreNotShiftedAgain()
  {
    p:=point("hfTotalized")
    items:=[HisItem(at,Number(12,Unit("kWh"))),HisItem(at+15min,null),HisItem(at+30min,Number(8,Unit("kWh"))),HisItem(at+45min,Number(5,Unit("kWh"))),HisItem(at+1hr,Number(9,Unit("kWh")))]
    result:=FinEnergyHistory.externalResult(p,items)
    nativeRows:=FinEnergyHistory.nativeItems(result)
    verifyEq(nativeRows.map |i->DateTime| { i.ts },items.map |i->DateTime| { i.ts })
    value:=FinEnergyHistoryData(FinEnergyHistory.normalizeClean(p,result,at,at+1hr)).read(at,at+1hr)
    verifyEq(value.value,25f); verifyEq(value.quality,"filtered")
    verifyEq(items.first.ts,at); verifyEq(items.last.ts,at+1hr)
  }

  Void testExplicitConfigOverridesDefaultsWithoutMutatingThem()
  {
    defaults:=Etc.makeDict(["deltaMin":Number(0,Unit("kWh")),"defVal":NA.val,"timeMax":Number(1,Unit("hr"))])
    selected:=FinEnergyHistory.selectConfig(defaults,Etc.makeDict(["defVal":Number(0,Unit("kWh"))]))
    verifyEq(selected["defVal"],Number(0,Unit("kWh")))
    verifyEq(selected["timeMax"],Number(1,Unit("hr")))
    verifyEq(defaults["defVal"],NA.val)
    noTimeout:=FinEnergyHistory.selectConfig(defaults,Etc.makeDict(["timeMax":Remove.val]))
    verify(!noTimeout.has("timeMax")); verify(defaults.has("timeMax"))
    switched:=FinEnergyHistory.selectConfig(Etc.makeDict(["defNull":Marker.val,"deltaMin":Number(0)]),Etc.makeDict(["defVal":Number(0)]))
    verify(!switched.has("defNull")); verify(switched.has("defVal"))
  }

  private DateTime at() { DateTime.fromIso("2026-10-03T00:00:00Z") }
  private Dict point(Str function)
  { Etc.makeDict(["id":Ref("test"),"hisFunc":function,"hisMode":"consumption","hisTotalized":Marker.val,"hisCollectInterval":Number(15,Unit("min")),"hisFuncConfig":Etc.makeDict(["defNull":Marker.val]),"unit":"kWh"]) }
}

using haystack

class EnerCubixCleaningTest : Test
{
  Void testDefaultProfileDropsNegativeAndPreservesZero()
  {
    r:=run([10,10,5,8],generic)
    verifyEq(r.items.map |i->Obj?| { i.val },Obj?[Number(0f,Unit("kWh")),null,Number(3f,Unit("kWh"))])
    verifyEq(r.details[0]["reason"],"noPrevious")
    verifyEq(r.details[2]["reason"],"deltaMin")
    verifyEq(r.details[1]["valueType"],"number")
    verifyEq(r.summary["nullCount"],1)
    verifyEq(r.rawItems.size,4)
  }

  Void testBoundsAreIndividuallyEnabled()
  {
    r:=run([10,12,15,16],["deltaMax":2,"defNull":true])
    verifyEq(r.items[0].val,Number(2f,Unit("kWh")))
    verifyNull(r.items[1].val)
    verifyEq(r.items[2].val,Number(1f,Unit("kWh")))
    verifyErr(ArgErr#) { EnerCubixCleaning.config(["deltaMin":2,"deltaMax":1,"defNull":true],"kWh") }
  }

  Void testReplacementRequiresExplicitTypeAndPreservesNA()
  {
    r:=run([10,5,NA.val,8],["deltaMin":0,"defVal":["type":"na"]])
    verifyEq(r.items[0].val,NA.val)
    verifyEq(r.details[1]["substituted"],true)
    verifyEq(r.details[1]["valueType"],"na")
    verifyEq(r.items[1].val,NA.val)
    verifyEq(r.details[2]["substituted"],false)
    verifyErr(ArgErr#) { EnerCubixCleaning.config(["defVal":0],"kWh") }
    r=run([10,5],["deltaMin":0,"defVal":["type":"number","value":1000,"unit":"Wh"]])
    verifyEq(r.items[0].val,Number(1f,Unit("kWh")))
  }

  Void testRemoveNAOccursBeforeDifferencingOnly()
  {
    r:=run([10,NA.val,14],["removeNA":true,"defNull":true])
    verifyEq(r.items.size,1)
    verifyEq(r.items[0].val,Number(4f,Unit("kWh")))
    verifyEq(r.details[1]["reason"],"removedNA")
    verifyEq(r.details[2]["intervalSeconds"],7200f)
    r=run([10,NA.val,14],["defNull":true])
    verifyEq(r.items.map |i->Obj?| { i.val },Obj?[NA.val,NA.val])
    r=run([10,5],["removeNA":true,"deltaMin":0,"defVal":["type":"na"]])
    verifyEq(r.items[0].val,NA.val)
  }

  Void testNullAndNAAreDifferent()
  {
    r:=run([10,null,14,NA.val,18],["defNull":true])
    verifyNull(r.items[0].val); verifyNull(r.items[1].val)
    verifyEq(r.items[2].val,NA.val); verifyEq(r.items[3].val,NA.val)
    verifyEq(r.details[1]["valueType"],"null")
    verifyEq(r.details[3]["valueType"],"na")
  }

  Void testRolloverUsesPeriodAndBounds()
  {
    opts:=[Str:Obj?]["deltaMin":0,"deltaMax":100,"timeMax":"1h","hisTotalizedRollover":32768]
    r:=run([32760,12,600],opts)
    verifyEq(r.items[0].val,Number(20f,Unit("kWh")))
    verifyEq(r.details[1]["reason"],"rollover")
    verifyEq(r.summary["rolloverCount"],1)
    verifyNull(r.items[1].val)
    verifyEq(r.details[2]["reason"],"deltaMax")
    r=run([33000,12],opts); verifyNull(r.items[0].val)
    verifyEq(r.details[1]["reason"],"rolloverOutOfRange")
    opts["deltaMax"]=10; r=run([32760,12],opts); verifyNull(r.items[0].val)
    verifyEq(r.details[1]["reason"],"deltaMax")
  }

  Void testTimeoutNeverUsesRolloverOrInterpolates()
  {
    opts:=[Str:Obj?]["deltaMax":100,"timeMax":"30min","hisTotalizedRollover":32768]
    r:=run([32760,12],opts)
    verifyEq(r.items.size,1); verifyNull(r.items[0].val)
    verifyEq(r.details[1]["reason"],"timeMax")
    verifyEq(r.details[1]["intervalSeconds"],3600f)
  }

  Void testRateUsesActualElapsedTimeAndConvertsUnits()
  {
    opts:=[Str:Obj?]["derivMax":["type":"number","value":2000,"unit":"W"],"defNull":true]
    raw:=[HisItem(ts(0),Number(10f)),HisItem(ts(0)+30min,Number(11f)),HisItem(ts(1),Number(13f))]
    r:=EnerCubixCleaning.clean(point("kWh"),raw,EnerCubixCleaning.config(opts,"kWh"))
    verifyEq(r.items[0].val,Number(1f,Unit("kWh"))); verifyNull(r.items[1].val)
    verifyEq(r.details[2]["reason"],"derivMax")
    verifyErr(ArgErr#) { EnerCubixCleaning.config(["derivMax":["type":"number","value":1,"unit":"kWh"],"defNull":true],"kWh") }
    verifyErr(ArgErr#) { EnerCubixCleaning.config(["deltaMax":["type":"number","value":1,"unit":"kW"],"defNull":true],"kWh") }
  }

  Void testSupportedRates()
  {
    ["Wh":"W","kWh":"kW","MWh":"MW","BTU":"BTU/h","kBTU":"kBTU/h","gal":"gal/min","L":"L/min"].each |rate,unit|
    {
      cfg:=EnerCubixCleaning.config(["derivMax":["type":"number","value":60,"unit":rate],"defNull":true],unit)
      raw:=[HisItem(ts(0),Number(0f)),HisItem(ts(0)+1min,Number(1f))]
      r:=EnerCubixCleaning.clean(point(unit),raw,cfg)
      verify(r.items[0].val is Number,"$unit -> $rate: ${r.details}")
    }
  }

  Void testConfigurationRejectsFalseMixedModesAndInvalidNumbers()
  {
    verifyErr(ArgErr#) { EnerCubixCleaning.config(["defNull":false],"kWh") }
    verifyErr(ArgErr#) { EnerCubixCleaning.config(["removeNA":false,"defNull":true],"kWh") }
    verifyErr(ArgErr#) { EnerCubixCleaning.config(["defNull":true,"defVal":["type":"na"]],"kWh") }
    verifyErr(ArgErr#) { EnerCubixCleaning.config(["defNull":true,"hisTotalizedRollover":32768],"kWh") }
    verifyErr(ArgErr#) { EnerCubixCleaning.config(["hisTotalizedRollover":32768],"kWh") }
    verifyErr(ArgErr#) { EnerCubixCleaning.config(["deltaMax":10],"kWh") }
    verifyErr(ArgErr#) { EnerCubixCleaning.config(["hisTotalizedRollover":32768,"deltaMax":0],"kWh") }
    verifyErr(ArgErr#) { EnerCubixCleaning.config(["hisTotalizedRollover":32768,"derivMax":-1],"kWh") }
    verifyErr(ArgErr#) { EnerCubixCleaning.config(["defNull":true,"deltaMax":Float.nan],"kWh") }
    verifyErr(ArgErr#) { EnerCubixCleaning.config(["defNull":true,"timeMax":"0h"],"kWh") }
  }

  Void testNativeSnapshotRoundTrip()
  {
    cfg:=EnerCubixCleaning.config(["deltaMin":0,"deltaMax":["type":"number","value":2000,"unit":"Wh"],"timeMax":"1h","defNull":true,"removeNA":true],"kWh")
    verifyEq(cfg["deltaMax"],Number(2f,Unit("kWh")))
    verifyEq(cfg["defNull"],Marker.val)
    snap:=EnerCubixCleaning.jsonConfig(cfg)
    verifyEq(snap["defNull"],true)
    verifyEq(EnerCubixCleaning.jsonConfig(EnerCubixCleaning.config(snap,"kWh")),snap)
    withMeta:=Etc.dictSet(cfg,"enerCubixMode","drop")
    verifyEq(EnerCubixCleaning.jsonConfig(withMeta),snap)
  }

  private EnerCubixCleanResult run(Obj?[] values, Str:Obj? opts)
  {
    items:=HisItem[,]
    values.each |v,i| { items.add(HisItem(ts(i),v is Num ? Number.makeNum(v) : v)) }
    return EnerCubixCleaning.clean(point("kWh"),items,EnerCubixCleaning.config(opts,"kWh"))
  }
  private Dict point(Str unit) { Etc.makeDict(["unit":unit]) }
  private Str:Obj? generic() { ["deltaMin":0,"timeMax":"1h","defNull":true] }
  private DateTime ts(Int hour) { DateTime.fromIso("2026-01-01T00:00:00Z")+Duration(hour*1hr.ticks) }
}

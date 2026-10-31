class EnerCubixCockpitMetricErrorsTest : Test
{
  Void testCostInternalErrorKeepsEnergyTrendCarbonAndNoHalfReport()
  {
    ["cost","co2","auxiliaryEnergy","areaIntensity"].each |failed|
    {
      q:=request;if (failed == "auxiliaryEnergy") q["auxiliaryCategoryId"]="water"
      result:=run(q,failed,Err("internal sentinel"))
      values:=EnerCubixMath.maps(((Map)((Map)((Map)result["modules"])["kpis"])["data"])["values"])
      verifyEq(values.first["value"],10f)
      bad:=values.find |v| {v["id"] == failed}
      verifyNull(bad["value"]);verifyEq(bad["reasonCodes"],["COCKPIT_METRIC_ERROR"],failed)
      verifyEq(bad["status"],"error")
      verifyNotNull(((Map)result["modules"])["trend"])
      key:=failed == "auxiliaryEnergy" ? "auxiliary" : (failed == "areaIntensity" ? "area" : failed)
      verifyNull(((Map)result["reports"])["profile-"+key])
    }
  }
  Void testBudgetAuthInputCancelAndResourcesRemainGlobal()
  {
    Err[] failures:=[EnerCubixHttpErr(401,"SESSION","expired"),EnerCubixHttpErr(429,"COCKPIT_BUSY","busy"),EnerCubixHttpErr(403,"PERMISSION","denied"),EnerCubixHttpErr(504,"QUERY_TIMEOUT","budget"),ArgErr("input"),ParseErr("input"),CancelledErr("cancel"),InterruptedErr("cancel"),TimeoutErr("timeout"),IOErr("resource"),Err("wrapped resource",IOErr("resource"))]
    failures.each |e|
    {
      try {run(request,"cost",e);fail("Expected original global error")}
      catch (Err actual) {verifySame(actual,e)}
    }
  }
  Void testInvalidLocalProjectionAndReferenceFailureDoNotPublishHalfReports()
  {
    q:=request;q["comparison"]=["mode":"custom","from":(start-1day).toIso,"to":(end-1day).toIso]
    hs:=histories
    samples:=EnerCubixMath.maps(hs.first["samples"]).dup
    samples.addAll(samples.map |s->[Str:Obj?]| {["ts":(DateTime.fromIso(s["ts"].toStr)-1day).toIso,"value":4f]})
    hs.first["samples"]=samples
    reporter:=|Str:Obj? rq,[Str:Obj?][] rs,[Str:Obj?][] history->Str:Obj?|
    {
      result:=EnerCubixHistory.report(rq,rs,history)
      if (rq["metric"] == "cost" && DateTime.fromIso(rq["from"].toStr) < start) result["summary"]=null
      return result
    }
    result:=EnerCubixCockpit.execute(q,records,|rq,rs->[Str:Obj?][]| {hs},"test",TimeZone.utc,end,false,null,null,reporter)
    values:=EnerCubixMath.maps(((Map)((Map)((Map)result["modules"])["kpis"])["data"])["values"])
    cost:=values.find |v| {v["id"] == "cost"}
    verifyEq(cost["value"],20f);verifyNull(((Map)cost["comparison"])["changeRate"])
    verifyNotNull(((Map)result["reports"])["profile-cost"])
    verifyNull(((Map)result["reports"])["reference-profile-cost"])
    verifyEq(values.first["value"],10f)
  }
  private Str:Obj? run(Str:Obj? q,Str failed,Err error)
  {
    reporter:=|Str:Obj? rq,[Str:Obj?][] rs,[Str:Obj?][] hs->Str:Obj?|
    {
      id:=rq["perArea"] == true ? "areaIntensity" : (EnerCubixMath.strings(rq["categoryIds"]).contains("water") ? "auxiliaryEnergy" : rq["metric"])
      if (id == failed) throw error
      return EnerCubixHistory.report(rq,rs,hs)
    }
    return (Str:Obj?)EnerCubixCockpit#.method("execute").callList([q,records,|rq,rs->[Str:Obj?][]| {histories},"test",TimeZone.utc,end,false,null,null,reporter])
  }
  private DateTime start() {DateTime.fromIso("2026-10-01T00:00:00Z")}
  private DateTime end() {start+2hr}
  private Str:Obj? request() {["schemaVersion":1,"requestId":"errors-test","reportScope":["dimension":"metering","nodeIds":["a"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"hour","from":start.toIso,"to":end.toIso],"asOf":end.toIso,"comparison":["mode":"none"],"modules":["kpis","trend"]]}
  private [Str:Obj?][] records() {[["id":"c","kind":"category","unit":"kWh"],["id":"water","kind":"category","unit":"m³"],["id":"sub","kind":"subcategory","categoryId":"c","co2Factor":0.5f],["id":"a","kind":"meter","name":"A","categoryId":"c","pointId":"pa","subcategoryId":"sub","tariffId":"tariff","areaSource":"custom","area":100f],["id":"tariff","kind":"tariff","mode":"flat","rate":2f]]}
  private [Str:Obj?][] histories() {[["pointId":"pa","unit":"kWh","mode":"interval","samples":[["ts":start.toIso,"value":5f],["ts":(start+1hr).toIso,"value":5f]]]]}
}

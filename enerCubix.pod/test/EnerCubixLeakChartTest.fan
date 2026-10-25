class EnerCubixLeakChartTest : Test
{
  Void testHourlyBranchesAreDirectAndKeepTheirOwnValues()
  {
    rs:=records; rs.add(meter("grandchild","pg","a"))
    r:=EnerCubixEngine.report(request("hour"),rs,histories.add(history("pg",[10f,20f])))
    rows:=branches(r)
    verifyEq(rows.size,4)
    verifyEq(rows.map |row->Str| { row["branchId"].toStr }.unique.sort,["a","b"])
    near((Float?)rows.find |row| { row["branchId"] == "a" && row["ts"] == ts(0) }["value"],30f)
    near((Float?)rows.find |row| { row["branchId"] == "b" && row["ts"] == ts(1) }["value"],100f)
  }

  Void testDayAndAreaUseTheSameMasterDenominator()
  {
    rs:=records; rs.first["area"]=10f
    req:=request("day"); req["perArea"]=true
    r:=EnerCubixEngine.report(req,rs,histories)
    rows:=branches(r); verifyEq(rows.size,2)
    near((Float?)rows.find |row| { row["branchId"] == "a" }["value"],9f)
    near((Float?)rows.find |row| { row["branchId"] == "b" }["value"],15f)
    totals:=([Str:Obj?][])((Str:Obj?)r["extra"])["leakTotals"]
    near((Float?)totals.first["total"],24f); near((Float?)totals.first["submeter"],24f)
  }

  Void testMissingBranchKeepsKnownReadingsButNoCompleteStackTotal()
  {
    hs:=histories; samples:=([Str:Obj?][])hs.last["samples"]; samples[1]["value"]=null
    r:=EnerCubixEngine.report(request("day"),records,hs)
    rows:=branches(r)
    near((Float?)rows.find |row| { row["branchId"] == "a" }["value"],90f)
    verifyNull(rows.find |row| { row["branchId"] == "b" }["value"])
    verifyNull((([Str:Obj?][])r["rows"]).first["submeter"])
  }

  Void testNegativeGapIsPreservedAndExplained()
  {
    hs:=histories; hs[0]=history("pt",[20f,20f])
    r:=EnerCubixEngine.report(request("day"),records,hs)
    totals:=([Str:Obj?][])((Str:Obj?)r["extra"])["leakTotals"]
    near((Float?)totals.first["difference"],-200f)
    verify(((Str[])r["warnings"]).any |warning| { warning.contains("分表合计大于总表") })
  }

  Void testWeeksBeginOnMondayAndKeepPartialBuckets()
  {
    req:=request("week"); req["from"]=(DateTime.fromIso(ts(0))-1hr).toIso; req["to"]=(DateTime.fromIso(ts(2))-1hr).toIso
    hs:=histories; hs.each |h| { (([Str:Obj?][])h["samples"]).each |s| { s["ts"]=(DateTime.fromIso(s["ts"].toStr)-1hr).toIso } }
    r:=EnerCubixEngine.report(req,records,hs)
    rows:=([Str:Obj?][])r["rows"]
    verifyEq(rows.size,2)
    verifyEq(rows[0]["ts"],"2026-10-12T00:00:00Z")
    verifyEq(rows[1]["ts"],"2026-10-19T00:00:00Z")
    near((Float?)rows[0]["total"],100f); near((Float?)rows[1]["total"],140f)
    verifyEq(branches(r).size,4)
  }

  private [Str:Obj?][] records() { [meter("total","pt",null).set("kind","totalMeter"),meter("a","pa","total"),meter("b","pb","total")] }
  private Str:Obj? meter(Str id,Str point,Str? parent) { ["id":id,"kind":"meter","name":id,"pointId":point,"meterParentId":parent,"categoryId":"electric","unit":"kWh"] }
  private [Str:Obj?][] histories() { [history("pt",[100f,140f]),history("pa",[30f,60f]),history("pb",[50f,100f])] }
  private Str:Obj? history(Str id,Float?[] values) { ["pointId":id,"unit":"kWh","mode":"interval","samples":values.map |Float? v,Int i->[Str:Obj?]| { ["ts":ts(i),"value":v] }] }
  private Str:Obj? request(Str period) { ["kind":"leak","dimension":"metering","nodeIds":["total"],"from":ts(0),"to":ts(2),"period":period,"metric":"energy","perArea":false,"tz":"UTC"] }
  private Str ts(Int hour) { (DateTime.fromIso("2026-10-19T00:00:00Z")+Duration(hour*1hr.ticks)).toIso }
  private [Str:Obj?][] branches(Str:Obj? r) { ([Str:Obj?][])((Str:Obj?)r["extra"])["leakBranches"] }
  private Void near(Float? actual,Float expected) { verifyNotNull(actual); verify(((Float)actual-expected).abs < 0.000001f) }
}

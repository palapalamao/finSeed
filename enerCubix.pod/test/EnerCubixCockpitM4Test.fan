using util

class EnerCubixCockpitM4Test : Test
{
  Void testSnapshotUsesOneHistoryReadFreezesConfigsAndRanksRuleSeparately()
  {
    calls:=0;owned:=config
    result:=EnerCubixCockpit.execute(input,records,|q,rs->[Str:Obj?][]| {calls++;return history},"test",TimeZone.utc,end,true,|->DateTime| {end},|->[Str:Obj?][]| {[Str:Obj?][,]},null,EnerCubixCockpitDeadline(),owned)
    verifyEq(calls,1)
    budget:=(Map)((Map)((Map)((Map)result["modules"])["kpis"])["data"])["budget"]
    verifyEq(budget["status"],"ok");verifyEq(budget["periodActualCost"],10f)
    verify(((Float)budget["periodBudget"]-10000f/24f).abs < 0.000001f)
    issues:=(Map)((Map)((Map)result["modules"])["issues"])["data"]
    verifyEq(EnerCubixMath.maps(issues["ruleEvaluations"]).first["status"],"triggered")
    clue:=EnerCubixMath.maps(issues["items"]).find |r| {r["type"] == "ruleClue"}
    verify(clue != null);verifyNull(clue["nativeAlarmId"])
    verifyEq(((Map)clue["evidenceTarget"])["parentSnapshotId"],result["snapshotId"])
    refs:=EnerCubixMath.maps(((Map)result["provenance"])["configRefs"])
    verify(refs.any |r| {r["id"] == "budget" && r["mod"] == "b1"});verify(refs.any |r| {r["id"] == "rule" && r["mod"] == "r1"})
    ((Map)((List)owned["budgets"]).first)["amount"]=999f
    verifyEq(((Map)((List)budget["configuration"]).first)["amount"],310000f)
    verify(!JsonOutStream.writeJsonToStr(result).contains("_cockpitDeadline"))
    file:=Env.cur.vars["ENERCUBIX_M4_FIXTURE"]
    if(file != null) File.os(file).out.writeChars(JsonOutStream.writeJsonToStr(["snapshot":result,"catalog":["records":records,"cockpitConfigRefs":refs.findAll |r| {["budget","rule"].contains(r["id"])}],"budgets":["records":config["budgets"],"projectRef":"p:test","complete":true],"ruleProfiles":["records":config["rules"],"projectRef":"p:test","complete":true]])).close
  }
  Void testSameBoundaryBudgetAcrossThreeSelectionViews()
  {
    values:=[Str:Obj?][,]
    ["space","metering","organization"].each |d|
    {
      q:=input;q["reportScope"]=["dimension":d,"nodeIds":d == "space" ? ["s"] : (d == "organization" ? ["o"] : ["a"]),"selectionIntent":"range"]
      result:=EnerCubixCockpit.execute(q,records,|rq,rs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
      b:=(Map)((Map)((Map)((Map)result["modules"])["kpis"])["data"])["budget"]
      values.add(["status":b["status"],"periodBudget":b["periodBudget"],"periodActualCost":b["periodActualCost"],"variancePct":b["variancePct"],"configRefs":b["configRefs"]])
    }
    verifyEq(values[0],values[1]);verifyEq(values[1],values[2])
  }
  Void testSharedOrganizationWrapperCounterexample()
  {
    rs:=records;rs.find |r| {r["id"] == "a"}["kind"]="totalMeter"
    rs.add(["id":"other","kind":"organization"])
    rs.add(["id":"b","kind":"meter","nativeEquip":true,"categoryId":"c","pointId":"pb","spaceId":"s","meterParentId":"a","organizationId":"other"])
    samples:=[Str:Obj?][,]
    ["space","organization"].each |d|
    {
      q:=input;q["reportScope"]=["dimension":d,"nodeIds":d == "space" ? ["s"] : ["o"],"selectionIntent":"range"]
      result:=EnerCubixCockpit.execute(q,rs,|rq,recs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
      b:=(Map)((Map)((Map)((Map)result["modules"])["kpis"])["data"])["budget"]
      samples.add(["meterIds":((Map)result["boundary"])["meterIds"],"status":b["status"],"periodActualCost":b["periodActualCost"],"reasonCodes":b["reasonCodes"]])
    }
    verifyEq(samples[0],samples[1])
  }
  Void testExplicitPhysicalOverlapVirtualOwnAndUnassignedNeverBorrowCosts()
  {
    rs:=records;rs.find |r| {r["id"] == "a"}["kind"]="totalMeter"
    rs.add(["id":"b","kind":"meter","nativeEquip":true,"categoryId":"c","pointId":"pb","spaceId":"s","meterParentId":"a"])
    q:=input;q["reportScope"]=["dimension":"metering","nodeIds":["a","b"],"selectionIntent":"explicitObjects"]
    result:=EnerCubixCockpit.execute(q,rs,|rq,recs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
    budget:=(Map)((Map)((Map)((Map)result["modules"])["kpis"])["data"])["budget"]
    verifyEq(budget["status"],"unavailable");verifyEq(budget["reasonCodes"],["BUDGET_OVERLAP"])
    // The virtual meter has its own unobserved primary; physical source history
    // and its expression variables cannot make this budget actual complete.
    rs=records;rs.add(["id":"v","kind":"meter","nativeEquip":true,"categoryId":"c","pointId":"pv","spaceId":"s","expressionId":"formula","includeInTotals":true,"tariffId":"tariff"])
    q["reportScope"]=["dimension":"metering","nodeIds":["v"],"selectionIntent":"range"]
    result=EnerCubixCockpit.execute(q,rs,|rq,recs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
    budget=(Map)((Map)((Map)((Map)result["modules"])["kpis"])["data"])["budget"]
    verifyEq(budget["status"],"unavailable");verifyNull(budget["periodActualCost"])
    // An unassigned device still participates in an exact whole-project
    // physical set, independent of which view supplies those explicit IDs.
    rs=records;rs.find |r| {r["id"] == "a"}.remove("organizationId")
    ["space","metering","organization"].each |dimension|
    {
      q=input;q["reportScope"]=["dimension":dimension,"nodeIds":["a"],"selectionIntent":"explicitObjects"]
      result=EnerCubixCockpit.execute(q,rs,|rq,recs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
      budget=(Map)((Map)((Map)((Map)result["modules"])["kpis"])["data"])["budget"]
      verifyEq(budget["status"],"ok");verifyEq(budget["periodActualCost"],10f)
    }
  }
  Void testPartialAsOfBudgetUsesActualElapsedRangeAndOwnedConfigsDoNotChangeOldReports()
  {
    q:=input;((Map)q["time"])["to"]=(end+1hr).toIso
    result:=EnerCubixCockpit.execute(q,records,|rq,rs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
    budget:=(Map)((Map)((Map)((Map)result["modules"])["kpis"])["data"])["budget"]
    verifyEq(budget["status"],"ok");verifyEq(budget["effectiveTo"],end.toIso)
    before:=EnerCubixCockpit.execute(input,records,|rq,rs->[Str:Obj?][]| {history},"test",TimeZone.utc,end)
    after:=EnerCubixCockpit.execute(input,records,|rq,rs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
    ["profile-energy","profile-cost"].each |key| {verifyEq(((Map)before["reports"])[key],((Map)after["reports"])[key])}
  }
  Void testBudgetPressureUsesCapturedReportFormalPriorityAndSingleObservation()
  {
    owned:=config;((Map)((List)owned["budgets"]).first)["amount"]=31f
    pressure:=Str:Obj?["id":"pressure","mod":"r2","version":1,"name":"Explicit budget pressure","scopeKind":"project","scopeRef":"p:test","categoryRef":"c","ruleType":"budgetVariance","threshold":5f,"thresholdUnit":"%","currency":"CNY","enabled":true]
    ((List)owned["rules"]).add(pressure)
    event:=Str:Obj?["id":"alarm","episodeId":"alarm","nodeId":"a","categoryId":"c","ts":"2026-09-30T23:00:00Z","lastTs":"2026-10-01T00:00:00Z","nativeAlarmId":"alarm_offNormal","nativeActive":true,"state":"acknowledged","sourceIds":["p"]]
    reads:=0;eventReads:=0
    result:=EnerCubixCockpit.execute(input,records,|q,rs->[Str:Obj?][]| {reads++;return history},"test",TimeZone.utc,end,true,null,|->[Str:Obj?][]| {eventReads++;return [event]},null,null,owned)
    verifyEq(reads,1);verifyEq(eventReads,1)
    issues:=(Map)((Map)((Map)result["modules"])["issues"])["data"]
    verifyEq(issues["activeEventCount"],1f);verifyEq(((List)issues["topIds"]).first,"alarm");verifyEq(((List)issues["topIds"]).size,3)
    clue:=EnerCubixMath.maps(issues["items"]).find |i| {i["id"] == "rule:pressure"}
    verifyEq(clue["reportRef"],"budget-canonical-cost")
    verifyEq(((Map)clue["evidenceTarget"])["reportRef"],"budget-canonical-cost")
    file:=Env.cur.vars["ENERCUBIX_M4_PRESSURE_FIXTURE"]
    if(file != null) File.os(file).out.writeChars(JsonOutStream.writeJsonToStr(result)).close
  }
  private DateTime end() {DateTime.fromIso("2026-10-01T01:00:00Z")}
  private Str:Obj? input() {["schemaVersion":1,"requestId":"m4-controlled","reportScope":["dimension":"space","nodeIds":["s"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"hour","from":"2026-10-01T00:00:00Z","to":end.toIso],"asOf":end.toIso,"modules":["kpis","trend","issues"],"comparison":["mode":"none"]]}
  private Str:Obj? config() {["projectRef":"p:test","modelComplete":true,"budgetsComplete":true,"rulesComplete":true,"budgets":[["id":"budget","mod":"b1","version":1,"name":"Controlled monthly budget","scopeKind":"project","scopeRef":"p:test","categoryRef":"c","month":"2026-10","currency":"CNY","amount":310000f,"distribution":"uniform","enabled":true]],"rules":[["id":"rule","mod":"r1","version":1,"name":"Controlled non-working clue","scopeKind":"project","scopeRef":"p:test","categoryRef":"c","calendarRef":"cal","ruleType":"nonWorkingHighUsage","threshold":5f,"thresholdUnit":"kWh","enabled":true]]]}
  private [Str:Obj?][] records() {[["id":"c","mod":"c1","kind":"category","name":"Electricity","unit":"kWh"],["id":"s","mod":"s1","kind":"space","name":"Controlled site","nativeSourceId":"s","nativeSourceKind":"site"],["id":"o","mod":"o1","kind":"organization","name":"Controlled owner"],["id":"a","mod":"a1","kind":"meter","name":"Controlled own meter","nativeEquip":true,"spaceId":"s","categoryId":"c","pointId":"p","organizationId":"o","tariffId":"tariff"],["id":"tariff","mod":"t1","kind":"tariff","name":"Controlled legacy CNY tariff","categoryId":"c","mode":"flat","rate":1f],["id":"cal","mod":"cal1","kind":"calendar","name":"Explicit work calendar","workDays":[1,2,3,4,5],"workHours":[9,10,11,12,13,14,15,16,17],"exceptions":[Str:Obj?][,]]]}
  private [Str:Obj?][] history() {[["pointId":"p","mode":"interval","unit":"kWh","samples":[["ts":"2026-10-01T00:00:00Z","value":10f]]]]}
}

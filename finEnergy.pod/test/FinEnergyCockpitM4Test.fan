using util

class FinEnergyCockpitM4Test : Test
{
  Void testSnapshotUsesOneHistoryReadFreezesConfigsAndRanksRuleSeparately()
  {
    calls:=0;owned:=config
    result:=FinEnergyCockpit.execute(input,records,|q,rs->[Str:Obj?][]| {calls++;return history},"test",TimeZone.utc,end,true,|->DateTime| {end},|->[Str:Obj?][]| {[Str:Obj?][,]},null,FinEnergyCockpitDeadline(),owned)
    verifyEq(calls,1)
    budget:=(Map)((Map)((Map)((Map)result["modules"])["kpis"])["data"])["budget"]
    verifyEq(budget["status"],"ok");verifyEq(budget["periodActualCost"],10f)
    verify(((Float)budget["periodBudget"]-10000f/24f).abs < 0.000001f)
    issues:=(Map)((Map)((Map)result["modules"])["issues"])["data"]
    verifyEq(FinEnergyMath.maps(issues["ruleEvaluations"]).first["status"],"triggered")
    clue:=FinEnergyMath.maps(issues["items"]).find |r| {r["type"] == "ruleClue"}
    verify(clue != null);verifyNull(clue["nativeAlarmId"])
    verifyEq(((Map)clue["evidenceTarget"])["parentSnapshotId"],result["snapshotId"])
    refs:=FinEnergyMath.maps(((Map)result["provenance"])["configRefs"])
    verify(refs.any |r| {r["id"] == "budget" && r["mod"] == "b1"});verify(refs.any |r| {r["id"] == "rule" && r["mod"] == "r1"})
    ((Map)((List)owned["budgets"]).first)["amount"]=999f
    verifyEq(((Map)((List)budget["configuration"]).first)["amount"],310000f)
    verify(!JsonOutStream.writeJsonToStr(result).contains("_cockpitDeadline"))
    file:=Env.cur.vars["FINENERGY_M4_FIXTURE"]
    if(file != null) File.os(file).out.writeChars(JsonOutStream.writeJsonToStr(["snapshot":result,"catalog":["records":records,"cockpitConfigRefs":refs.findAll |r| {["budget","rule"].contains(r["id"])}],"budgets":["records":config["budgets"],"projectRef":"p:test","complete":true],"ruleProfiles":["records":config["rules"],"projectRef":"p:test","complete":true]])).close
  }
  Void testSameBoundaryBudgetAcrossThreeSelectionViews()
  {
    values:=[Str:Obj?][,]
    ["space","metering","organization"].each |d|
    {
      q:=input;q["reportScope"]=["dimension":d,"nodeIds":d == "space" ? ["s"] : (d == "organization" ? ["o"] : ["a"]),"selectionIntent":"range"]
      result:=FinEnergyCockpit.execute(q,records,|rq,rs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
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
      result:=FinEnergyCockpit.execute(q,rs,|rq,recs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
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
    result:=FinEnergyCockpit.execute(q,rs,|rq,recs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
    budget:=(Map)((Map)((Map)((Map)result["modules"])["kpis"])["data"])["budget"]
    verifyEq(budget["status"],"unavailable");verifyEq(budget["reasonCodes"],["BUDGET_OVERLAP"])
    // The virtual meter has its own unobserved primary; physical source history
    // and its expression variables cannot make this budget actual complete.
    rs=records;rs.add(["id":"v","kind":"meter","nativeEquip":true,"categoryId":"c","pointId":"pv","spaceId":"s","expressionId":"formula","includeInTotals":true,"tariffId":"tariff"])
    q["reportScope"]=["dimension":"metering","nodeIds":["v"],"selectionIntent":"range"]
    result=FinEnergyCockpit.execute(q,rs,|rq,recs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
    budget=(Map)((Map)((Map)((Map)result["modules"])["kpis"])["data"])["budget"]
    verifyEq(budget["status"],"unavailable");verifyNull(budget["periodActualCost"])
    // An unassigned device still participates in an exact whole-project
    // physical set, independent of which view supplies those explicit IDs.
    rs=records;rs.find |r| {r["id"] == "a"}.remove("organizationId")
    ["space","metering","organization"].each |dimension|
    {
      q=input;q["reportScope"]=["dimension":dimension,"nodeIds":["a"],"selectionIntent":"explicitObjects"]
      result=FinEnergyCockpit.execute(q,rs,|rq,recs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
      budget=(Map)((Map)((Map)((Map)result["modules"])["kpis"])["data"])["budget"]
      verifyEq(budget["status"],"ok");verifyEq(budget["periodActualCost"],10f)
    }
  }
  Void testPartialAsOfBudgetUsesActualElapsedRangeAndOwnedConfigsDoNotChangeOldReports()
  {
    q:=input;((Map)q["time"])["to"]=(end+1hr).toIso
    result:=FinEnergyCockpit.execute(q,records,|rq,rs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
    budget:=(Map)((Map)((Map)((Map)result["modules"])["kpis"])["data"])["budget"]
    verifyEq(budget["status"],"ok");verifyEq(budget["effectiveTo"],end.toIso)
    before:=FinEnergyCockpit.execute(input,records,|rq,rs->[Str:Obj?][]| {history},"test",TimeZone.utc,end)
    after:=FinEnergyCockpit.execute(input,records,|rq,rs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
    ["profile-energy","profile-cost"].each |key| {verifyEq(((Map)before["reports"])[key],((Map)after["reports"])[key])}
  }
  Void testBudgetPressureUsesCapturedReportFormalPriorityAndSingleObservation()
  {
    owned:=config;((Map)((List)owned["budgets"]).first)["amount"]=31f
    pressure:=Str:Obj?["id":"pressure","mod":"r2","version":1,"name":"Explicit budget pressure","scopeKind":"project","scopeRef":"p:test","categoryRef":"c","ruleType":"budgetVariance","threshold":5f,"thresholdUnit":"%","currency":"CNY","enabled":true]
    ((List)owned["rules"]).add(pressure)
    event:=Str:Obj?["id":"alarm","episodeId":"alarm","nodeId":"a","categoryId":"c","ts":"2026-09-30T23:00:00Z","lastTs":"2026-10-01T00:00:00Z","nativeAlarmId":"alarm_offNormal","nativeActive":true,"state":"acknowledged","sourceIds":["p"]]
    reads:=0;eventReads:=0
    result:=FinEnergyCockpit.execute(input,records,|q,rs->[Str:Obj?][]| {reads++;return history},"test",TimeZone.utc,end,true,null,|->[Str:Obj?][]| {eventReads++;return [event]},null,null,owned)
    verifyEq(reads,1);verifyEq(eventReads,1)
    issues:=(Map)((Map)((Map)result["modules"])["issues"])["data"]
    verifyEq(issues["activeEventCount"],1f);verifyEq(((List)issues["topIds"]).first,"alarm");verifyEq(((List)issues["topIds"]).size,3)
    clue:=FinEnergyMath.maps(issues["items"]).find |i| {i["id"] == "rule:pressure"}
    verifyEq(clue["reportRef"],"budget-canonical-cost")
    verifyEq(((Map)clue["evidenceTarget"])["reportRef"],"budget-canonical-cost")
    file:=Env.cur.vars["FINENERGY_M4_PRESSURE_FIXTURE"]
    if(file != null) File.os(file).out.writeChars(JsonOutStream.writeJsonToStr(result)).close
  }
  Void testUnrelatedConfigurationDoesNotChangeFingerprintOrExposePrivateAttribution()
  {
    base:=FinEnergyCockpit.execute(input,records,|q,rs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
    owned:=config
    ((List)owned["budgets"]).add(["id":"old-invalid-budget","mod":"old-v1","validation":"invalid"])
    ((List)owned["rules"]).add(["id":"old-invalid-rule","mod":"old-r1","validation":"invalid"])
    owned["budgetAttribution"]=["old-invalid-budget":["month":"2026-09","categoryRef":"c","scopeRef":"private-missing-scope"]]
    owned["ruleAttribution"]=["old-invalid-rule":["categoryRef":"other-category","scopeRef":"private-missing-scope"]]
    result:=FinEnergyCockpit.execute(input,records,|q,rs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,owned)
    verifyEq(((Map)result["provenance"])["configFingerprint"],((Map)base["provenance"])["configFingerprint"])
    serialized:=JsonOutStream.writeJsonToStr(result)
    ["old-invalid-budget","old-invalid-rule","private-missing-scope","Attribution"].each |secret| {verify(!serialized.contains(secret))}
  }
  Void testZeroTargetSnapshotRetainsCurveAndNeverTriggersBudgetPercentageRule()
  {
    owned:=config;b:=FinEnergyMath.maps(owned["budgets"]).first
    b["distribution"]="daily";b["dailyAmounts"]=(0..<31).map |i->Float| {i == 30 ? 310000f : 0f}
    ((List)owned["rules"]).add(["id":"pressure","version":1,"name":"Explicit pressure","scopeKind":"project","scopeRef":"p:test","categoryRef":"c","ruleType":"budgetVariance","threshold":0f,"thresholdUnit":"%","currency":"CNY","enabled":true])
    result:=FinEnergyCockpit.execute(input,records,|q,rs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,owned)
    budget:=(Map)((Map)((Map)((Map)result["modules"])["kpis"])["data"])["budget"]
    verifyEq(budget["status"],"ok");verifyEq(budget["periodBudget"],0f);verifyEq(budget["deviationAmount"],10f);verifyNull(budget["variancePct"])
    issues:=(Map)((Map)((Map)result["modules"])["issues"])["data"]
    verifyEq(FinEnergyMath.maps(issues["ruleEvaluations"]).find |r| {r["id"] == "pressure"}["status"],"unavailable")
    verify(!FinEnergyMath.maps(issues["items"]).any |i| {i["id"] == "rule:pressure"})
    file:=Env.cur.vars["FINENERGY_M4_ZERO_TARGET_FIXTURE"]
    if(file != null) File.os(file).out.writeChars(JsonOutStream.writeJsonToStr(result)).close
  }
  Void testP27AndP29UseComplete576HourOwnHistoryForHeadlineReportsAndBudget()
  {
    start:=DateTime.fromIso("2026-10-01T00:00:00Z");finish:=start+24day
    [224600f,260000f].each |total|
    {
      owned:=config
      ((List)owned["rules"]).add(["id":"pressure","mod":"pressure-v1","version":1,"name":"Explicit fixture budget pressure","scopeKind":"project","scopeRef":"p:test","categoryRef":"c","ruleType":"budgetVariance","threshold":5f,"thresholdUnit":"%","currency":"CNY","enabled":true])
      q:=input;q["time"]=["preset":"custom","period":"day","from":start.toIso,"to":finish.toIso];q["asOf"]=finish.toIso
      base:=total == 224600f ? 390f : 450f
      samples:=(0..<576).map |i->[Str:Obj?]| {["ts":(start+Duration(i*1hr.ticks)).toIso,"value":i == 575 ? total-base*575f : base]}
      hs:=[Str:Obj?][["pointId":"p","unit":"kWh","mode":"interval","samples":samples]]
      reads:=0
      result:=FinEnergyCockpit.execute(q,records,|rq,rs->[Str:Obj?][]| {reads++;return hs},"test",TimeZone.utc,finish,true,null,|->[Str:Obj?][]| {[Str:Obj?][,]},null,null,owned)
      verifyEq(reads,1)
      b:=(Map)((Map)((Map)((Map)result["modules"])["kpis"])["data"])["budget"]
      verifyEq(b["status"],"ok");verifyEq(b["monthBudget"],310000f);verifyEq(b["periodBudget"],240000f);verifyEq(b["periodActualCost"],total)
      verify(((Float)b["variancePct"]-(total-240000f)/240000f*100f).abs < 0.0000001f)
      report:=(Map)((Map)result["reports"])[b["costReportRef"]]
      selection:=FinEnergyMath.maps(((Map)report["summary"])["selectionTotals"]).first
      verifyEq(selection["value"],total)
      curve:=FinEnergyMath.maps(b["curve"]);verifyEq(curve.size,25);verifyEq(curve.last["cumulativeBudget"],240000f)
      issues:=(Map)((Map)((Map)result["modules"])["issues"])["data"]
      pressure:=FinEnergyMath.maps(issues["ruleEvaluations"]).find |r| {r["id"] == "pressure"}
      verifyEq(pressure["status"],total == 260000f ? "triggered" : "notTriggered")
      folder:=Env.cur.vars["FINENERGY_M4_24DAY_FIXTURE_DIR"]
      if(folder != null) File.os(folder+(total == 224600f ? "/p27-24day-224600.json" : "/p29-24day-260000.json")).out.writeChars(JsonOutStream.writeJsonToStr(result)).close
    }
  }
  Void testUsdLabelsAgreeAcrossCurrentReferenceCanonicalAndLegacyStaysUnchanged()
  {
    rs:=records;rs.find |r| {r["kind"] == "tariff"}["currency"]="USD"
    owned:=config;FinEnergyMath.maps(owned["budgets"]).first["currency"]="USD"
    q:=input;q["comparison"]=["mode":"custom","from":"2026-09-30T00:00:00Z","to":"2026-09-30T01:00:00Z"]
    hs:=history
    // The raw source list is supplied explicitly; no second native load.
    hs.first["samples"]=[["ts":"2026-09-30T00:00:00Z","value":5f],["ts":"2026-10-01T00:00:00Z","value":10f]]
    calls:=0
    result:=FinEnergyCockpit.execute(q,rs,|rq,recs->[Str:Obj?][]| {calls++;return hs},"test",TimeZone.utc,end,true,null,null,null,null,owned)
    verifyEq(calls,1)
    budget:=(Map)((Map)((Map)((Map)result["modules"])["kpis"])["data"])["budget"]
    verifyEq(budget["currency"],"USD");verifyEq(budget["periodActualCost"],10f)
    reports:=(Map)result["reports"]
    ["profile-cost","reference-profile-cost","budget-canonical-cost"].each |key|
    {
      report:=(Map)reports[key]
      verifyEq(((Map)report["extra"])["currencyStatus"],"ok");verifyEq(((Map)report["extra"])["currency"],"USD")
      expected:=key == "reference-profile-cost" ? 5f : 10f
      monetaryRows(report).each |row|
      {
        verifyEq(row["unit"],"USD")
        if(row.containsKey("value")) verifyEq(row["value"],expected)
        if(row.containsKey("knownValue")) verifyEq(row["knownValue"],expected)
        if(row.containsKey("quality")) verifyEq(row["quality"],"ok")
      }
      verifyEq(FinEnergyMath.maps(((Map)report["extra"])["usageCoverage"]).first["coveredSeconds"],3600f)
      verifyEq(FinEnergyMath.maps(((Map)((Map)report["extra"])["knownUsage"])["sourceUsage"]).first["unit"],"kWh")
    }
    rq:=FinEnergyCockpit.query(input,"test",TimeZone.utc,end).set("metric","cost")
    legacy:=FinEnergyHistory.report(rq,rs,history)
    monetaryRows(legacy).each |row| {verifyEq(row["unit"],"元")}
    verifyEq(FinEnergyMath.maps(((Map)legacy["summary"])["selectionTotals"]).first["value"],10f)
    output:=Env.cur.vars["FINENERGY_M4_USD_FIXTURE"]
    if(output != null) File.os(output).out.writeChars(JsonOutStream.writeJsonToStr(result)).close
  }
  Void testCockpitCurrencyRejectsInvalidAndMixedAndKeepsLegacyCny()
  {
    ["",4,"USD","CNY"].each |currency|
    {
      rs:=records;rs.find |r| {r["kind"] == "tariff"}["currency"]=currency
      owned:=config;FinEnergyMath.maps(owned["budgets"]).first["currency"]=currency == "USD" ? "USD" : "CNY"
      result:=FinEnergyCockpit.execute(input,rs,|rq,recs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,owned)
      kpis:=(Map)((Map)((Map)result["modules"])["kpis"])["data"]
      cost:=FinEnergyMath.maps(kpis["values"]).find |v| {v["id"] == "cost"}
      report:=(Map)((Map)result["reports"])["profile-cost"]
      if(currency == "USD" || currency == "CNY")
      {verifyEq(cost["unit"],currency);verifyEq(cost["value"],10f);verifyEq(((Map)report["extra"])["currencyStatus"],"ok")}
      else
      {verifyNull(cost["value"]);verifyEq(cost["unit"],"");verifyEq(((Map)report["extra"])["currencyStatus"],"unavailable");verifyEq(((Map)kpis["budget"])["status"],"unavailable")}
    }
    result:=FinEnergyCockpit.execute(input,records,|rq,recs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
    report:=(Map)((Map)result["reports"])["profile-cost"]
    verifyEq(((Map)report["extra"])["currency"],"CNY");verifyEq(((Map)report["extra"])["currencyBasis"],"legacyCnyConvention")
  }
  Void testMixedAndAbsentTariffNeverExportQualifiedMoneyAndKeepRawEnergy()
  {
    rs:=records;rs.find |r| {r["kind"] == "tariff"}["currency"]="USD"
    rs.addAll([["id":"cny","kind":"tariff","mode":"flat","rate":1f,"currency":"CNY"],["id":"b","kind":"meter","nativeEquip":true,"pointId":"pb","spaceId":"s","categoryId":"c","tariffId":"cny"]])
    hs:=history.dup.add(["pointId":"pb","mode":"interval","unit":"kWh","samples":[["ts":"2026-10-01T00:00:00Z","value":20f]]])
    owned:=config;FinEnergyMath.maps(owned["budgets"]).first["currency"]="USD"
    result:=FinEnergyCockpit.execute(input,rs,|rq,recs->[Str:Obj?][]| {hs},"test",TimeZone.utc,end,true,null,null,null,null,owned)
    kpis:=(Map)((Map)((Map)result["modules"])["kpis"])["data"]
    verifyEq(FinEnergyMath.maps(kpis["values"]).find |v| {v["id"] == "energy"}["value"],30f)
    verifyNull(FinEnergyMath.maps(kpis["values"]).find |v| {v["id"] == "cost"}["value"])
    ["profile-cost","budget-canonical-cost"].each |key|
    {
      report:=(Map)((Map)result["reports"])[key]
      verifyEq(((Map)report["extra"])["currencyStatus"],"unavailable")
      monetaryRows(report).each |r| {verifyEq(r["unit"],"");if(r.containsKey("value")) verifyNull(r["value"]);if(r.containsKey("knownValue")) verifyNull(r["knownValue"])}
      FinEnergyMath.maps(report["series"]).each |s| {FinEnergyMath.maps(s["points"]).each |p| {verifyNull(p["value"]);verifyEq(p["quality"],"currencyUnconfirmed")}}
      verify(FinEnergyMath.maps(((Map)((Map)report["extra"])["knownUsage"])["sourceUsage"]).all |r| {r["unit"] == "kWh"})
    }
    rs.find |r| {r["id"] == "tariff"}.remove("currency")
    FinEnergyMath.maps(owned["budgets"]).first["currency"]="CNY"
    result=FinEnergyCockpit.execute(input,rs,|rq,recs->[Str:Obj?][]| {hs},"test",TimeZone.utc,end,true,null,null,null,null,owned)
    report:=(Map)((Map)result["reports"])["profile-cost"]
    verifyEq(((Map)report["extra"])["currencyBasis"],"mixedExplicitAndLegacyCny")
    verifyEq(FinEnergyMath.maps(((Map)report["summary"])["selectionTotals"]).first["value"],30f)
    rs=records.exclude |r| {r["kind"] == "tariff"}
    result=FinEnergyCockpit.execute(input,rs,|rq,recs->[Str:Obj?][]| {history},"test",TimeZone.utc,end,true,null,null,null,null,config)
    report=(Map)((Map)result["reports"])["profile-cost"]
    verifyEq(((Map)report["extra"])["currencyReasonCodes"],["COST_TARIFF_MISSING"])
  }
  private [Str:Obj?][] monetaryRows(Map report)
  {
    rows:=FinEnergyMath.maps(report["series"]).dup.addAll(FinEnergyMath.maps(report["rows"]))
    summary:=(Map)report["summary"];extra:=(Map)report["extra"]
    ["totals","knownTotals","selectionTotals"].each |key| {rows.addAll(FinEnergyMath.maps(summary[key]))}
    ["selectionTotals","usageCoverage","details"].each |key| {rows.addAll(FinEnergyMath.maps(extra[key]))}
    return rows
  }
  private DateTime end() {DateTime.fromIso("2026-10-01T01:00:00Z")}
  private Str:Obj? input() {["schemaVersion":1,"requestId":"m4-controlled","reportScope":["dimension":"space","nodeIds":["s"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"hour","from":"2026-10-01T00:00:00Z","to":end.toIso],"asOf":end.toIso,"modules":["kpis","trend","issues"],"comparison":["mode":"none"]]}
  private Str:Obj? config() {["projectRef":"p:test","modelComplete":true,"budgetsComplete":true,"rulesComplete":true,"budgets":[["id":"budget","mod":"b1","version":1,"name":"Controlled monthly budget","scopeKind":"project","scopeRef":"p:test","categoryRef":"c","month":"2026-10","currency":"CNY","amount":310000f,"distribution":"uniform","enabled":true]],"rules":[["id":"rule","mod":"r1","version":1,"name":"Controlled non-working clue","scopeKind":"project","scopeRef":"p:test","categoryRef":"c","calendarRef":"cal","ruleType":"nonWorkingHighUsage","threshold":5f,"thresholdUnit":"kWh","enabled":true]]]}
  private [Str:Obj?][] records() {[["id":"c","mod":"c1","kind":"category","name":"Electricity","unit":"kWh"],["id":"s","mod":"s1","kind":"space","name":"Controlled site","nativeSourceId":"s","nativeSourceKind":"site"],["id":"o","mod":"o1","kind":"organization","name":"Controlled owner"],["id":"a","mod":"a1","kind":"meter","name":"Controlled own meter","nativeEquip":true,"spaceId":"s","categoryId":"c","pointId":"p","organizationId":"o","tariffId":"tariff"],["id":"tariff","mod":"t1","kind":"tariff","name":"Controlled legacy CNY tariff","categoryId":"c","mode":"flat","rate":1f],["id":"cal","mod":"cal1","kind":"calendar","name":"Explicit work calendar","workDays":[1,2,3,4,5],"workHours":[9,10,11,12,13,14,15,16,17],"exceptions":[Str:Obj?][,]]]}
  private [Str:Obj?][] history() {[["pointId":"p","mode":"interval","unit":"kWh","samples":[["ts":"2026-10-01T00:00:00Z","value":10f]]]]}
}

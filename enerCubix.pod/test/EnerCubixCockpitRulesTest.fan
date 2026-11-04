using haystack

class EnerCubixCockpitRulesTest : Test
{
  Void testExplicitRulesOnlyAndActualZeroNotMissing()
  {
    verify(EnerCubixMath.maps(run([Str:Obj?][,],history)["items"]).isEmpty)
    r:=run([profile],history);e:=EnerCubixMath.maps(r["evaluations"]).first
    verifyEq(e["status"],"triggered");verifyEq(EnerCubixMath.maps(r["items"]).first["type"],"ruleClue")
    h:=history;((Map)((List)h.first["samples"]).first)["value"]=0f
    verifyEq(EnerCubixMath.maps(run([profile],h)["evaluations"]).first["status"],"notTriggered")
    verifyEq(EnerCubixMath.maps(run([profile],[Str:Obj?][,])["evaluations"]).first["status"],"unavailable")
  }
  Void testSubstitutionAbsenceRequiresTheActualHourAndMissingIsUnknown()
  {
    a:=DateTime.fromIso("2026-10-01T00:00:00Z");b:=a+1hr
    shifted:=[Str:Obj?][["intervalStart":(a+30min).toIso,"intervalEnd":(b+30min).toIso,"quality":"ok"]]
    evidence:=Str:Obj?["coveredSeconds":3600f,"intervalCount":1,"detailsTruncated":false]
    verifyEq(EnerCubixCockpitRules.substitutionEvidence(evidence,shifted,a,b),2)
    shifted.first["intervalStart"]=a.toIso;shifted.first["intervalEnd"]=b.toIso
    verifyEq(EnerCubixCockpitRules.substitutionEvidence(evidence,shifted,a,b),0)
    evidence["detailsTruncated"]=true;verifyEq(EnerCubixCockpitRules.substitutionEvidence(evidence,[Str:Obj?][,],a,b),2)
    evidence["_containsSubstitutedIntervals"]=true;verifyEq(EnerCubixCockpitRules.substitutionEvidence(evidence,[Str:Obj?][,],a,b),1)
    verifyEq(EnerCubixCockpitRules.substitutionEvidence(Str:Obj?[:],[Str:Obj?][,],a,b),2)
  }
  Void testSubstitutionFactsRemainStableBeyondTheDiagnosticPrefixAndAtZeroQuota()
  {
    a:=DateTime.fromIso("2026-10-01T00:00:00Z");b:=a+1hr
    rows:=[Str:Obj?][["from":a.toIso,"to":b.toIso,"value":10f,"quality":"estimated","valueType":"number"]]
    h:=EnerCubixHistoryData(["pointId":"p","mode":"interval","unit":"kWh","intervals":rows])
    [0,1,1000].each |cap|
    {
      e:=h.captureKnownUsage(a,b,b,true,cap)
      verifyEq(e["_containsSubstitutedIntervals"],false)
      verifyEq(EnerCubixCockpitRules.substitutionEvidence(e,EnerCubixMath.maps(e["intervals"]),a,b),0)
    }
    rows.first["quality"]="substituted"
    h=EnerCubixHistoryData(["pointId":"p","mode":"interval","unit":"kWh","intervals":rows])
    [0,1,1000].each |cap| {e:=h.captureKnownUsage(a,b,b,true,cap);verifyEq(e["_containsSubstitutedIntervals"],true);verifyEq(EnerCubixCockpitRules.substitutionEvidence(e,EnerCubixMath.maps(e["intervals"]),a,b),1)}
    future:=h.captureKnownUsage(a,b,a+30min,true,0)
    verifyNull(future["_containsSubstitutedIntervals"]);verifyEq(EnerCubixCockpitRules.substitutionEvidence(future,[Str:Obj?][,],a,b),2)
    verify(!h.knownUsage(a,b,b).containsKey("_containsSubstitutedIntervals"))
  }
  Void testMultipleSourcesCountOneHourAndKeepUnverifiedSourcesSeparate()
  {
    rs:=records;rs.add(["id":"b","kind":"meter","nativeEquip":true,"spaceId":"s","categoryId":"c","pointId":"pb"])
    bound:=boundary.setAll(["meterIds":["a","b"],"sourcePointIds":["p","pb"]])
    a:=DateTime.fromIso(query["from"].toStr);b:=a+1hr
    substituted:=Str:Obj?["pointId":"p","mode":"interval","unit":"kWh","intervals":[["from":a.toIso,"to":b.toIso,"value":10f,"quality":"substituted","valueType":"number"]]]
    second:=substituted.dup.set("pointId","pb")
    [false,true].each |missing|
    {
      histories:=[substituted,missing ? Str:Obj?["pointId":"pb","mode":"interval","unit":"kWh","samples":[Str:Obj?][,]] : second]
      result:=EnerCubixCockpitRules.project(query,rs,histories,info([profile]),bound,EnerCubixBudgetMath.unavailable("BUDGET_NOT_CONFIGURED"),"snapshot")
      evaluation:=EnerCubixMath.maps(result["evaluations"]).first;inputs:=(Map)evaluation["inputs"]
      verifyEq(inputs["substitutedNonWorkingHours"],1)
      verifyEq(inputs["unknownSubstitutionNonWorkingHours"],missing ? 1 : 0)
      verifyEq(evaluation["status"],"unavailable");verify(EnerCubixMath.maps(result["items"]).isEmpty)
    }
  }
  Void testLongIntervalsSubstitutesPartialHoursAndInvalidCalendarNeverTrigger()
  {
    h:=history;h.first["mode"]="cumulative";h.first["samples"]=[["ts":"2026-10-01T00:00:00Z","value":0f],["ts":"2026-10-01T02:00:00Z","value":20f]]
    verifyEq(EnerCubixMath.maps(run([profile],h)["evaluations"]).first["status"],"unavailable")
    h=history;h.first["quality"]="substituted"
    verifyEq(EnerCubixMath.maps(run([profile],h)["evaluations"]).first["status"],"unavailable")
    q:=query;q["to"]="2026-10-01T00:30:00Z";q["asOf"]=q["to"]
    verifyEq(EnerCubixMath.maps(run([profile],history,q)["evaluations"]).first["status"],"unavailable")
    rs:=records;rs.last.remove("workHours")
    verifyEq(EnerCubixMath.maps(run([profile],history,null,rs)["evaluations"]).first["status"],"unavailable")
  }
  Void testBudgetClueRequiresSameReliableBudgetAndThreshold()
  {
    p:=profile;p["ruleType"]="budgetVariance";p["thresholdUnit"]="%";p["currency"]="CNY"
    budget:=Str:Obj?["status":"ok","scopeKind":"project","scopeRef":"p:test","categoryRef":"c","currency":"CNY","variancePct":12f,"periodBudget":100f,"periodActualCost":112f,"configRefs":[["id":"budget","version":1]]]
    r:=EnerCubixCockpitRules.project(query,records,history,info([p]),boundary,budget,"snapshot")
    verifyEq(EnerCubixMath.maps(r["evaluations"]).first["status"],"triggered")
    budget["status"]="unavailable"
    budget["referenceVariancePct"]=12f;budget["variancePct"]=null
    verifyEq(EnerCubixMath.maps(EnerCubixCockpitRules.project(query,records,history,info([p]),boundary,budget,"snapshot")["evaluations"]).first["status"],"unavailable")
    budget["status"]="ok"
    verifyEq(EnerCubixMath.maps(EnerCubixCockpitRules.project(query,records,history,info([p]),boundary,budget,"snapshot")["evaluations"]).first["status"],"unavailable")
  }
  Void testUnitsCalendarExceptionsAndDisabledProfilesAreExplicit()
  {
    p:=profile;p["thresholdUnit"]="MWh";p["threshold"]=0.005f
    r:=run([p],history);item:=EnerCubixMath.maps(r["items"]).first
    verifyEq(item["reference"],5f);verifyEq(item["unit"],"kWh")
    p["enabled"]=false
    verifyEq(EnerCubixMath.maps(run([p],history)["evaluations"]).first["status"],"disabled")
    rs:=records;rs.last["workHours"]=(0..<24).toList;rs.last["exceptions"]=[["date":"2026-10-01","working":true]]
    verifyEq(EnerCubixMath.maps(run([profile],history,null,rs)["evaluations"]).first["status"],"notTriggered")
    rs.last["exceptions"]=[["date":"2026-10-01","working":false]]
    verifyEq(EnerCubixMath.maps(run([profile],history,null,rs)["evaluations"]).first["status"],"triggered")
  }
  Void testDiagnosticQuotaDoesNotChangeCompleteNonWorkingRule()
  {
    start:=DateTime.fromIso(query["from"].toStr);finish:=start+2hr
    q:=query;q["to"]=finish.toIso;q["asOf"]=finish.toIso;q["_cockpitReadRanges"]=[["from":start.toIso,"to":finish.toIso]];q["_cockpitNeedsRuleFacts"]=true
    cfg:=Etc.makeDict(["defNull":Marker.val,"deltaMin":Number(0),"deltaMax":Number(10000)])
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":cfg])
    raw:=[HisItem(start,Number(0)),HisItem(start+1hr,Number(30)),HisItem(finish,Number(110))]
    p:=profile;p["threshold"]=50f
    Map? baseline
    [1000,1,0].each |quota|
    {
      budget:=EnerCubixStreamBudget();budget.detailCount=1000-quota
      hs:=EnerCubixCockpitStream.prepare(q,records,["p":point],["p":cfg],|Dict pt,Span span,|HisItem| sink| {raw.each |row| {if(row.ts>=span.start && row.ts<span.end) sink(row)}},budget)
      facts:=0
      substitutionFacts:=0
      ((Map)hs.first["_preparedReads"]).vals.each |pair| {((Map)((Map)pair)["known"]).vals.each |row| {if(((Map)row)["_closedOwnPrimaryHour"] == true) facts++;if(((Map)row).containsKey("_containsSubstitutedIntervals")) substitutionFacts++}}
      // Two original pairs cost12 entries; each retained private fact adds one.
      verifyEq(budget.cells,12+facts+substitutionFacts)
      if(quota == 0) verifyEq(facts,2)
      if(quota == 1000) verifyEq(facts,0)
      output:=run([p],hs,q);evaluation:=EnerCubixMath.maps(output["evaluations"]).first
      verifyEq(evaluation["status"],"triggered",quota.toStr)
      verifyEq(evaluation["actual"],80f);verifyEq(evaluation["triggerFrom"],(start+1hr).toIso)
      counts:=(Map)evaluation["inputs"]
      echo("RULE_DIAGNOSTIC quota="+quota+" status="+evaluation["status"]+" actual="+evaluation["actual"]+" valid="+counts["validNonWorkingHours"]+" privateFacts="+facts)
      verifyEq(counts["validNonWorkingHours"],2);verifyEq(counts["unavailableNonWorkingHours"],0);verifyEq(counts["triggerCount"],1)
      if(baseline == null) baseline=output
      else verifyEq(output,baseline)
      h:=EnerCubixHistoryData(hs.first);observed:=h.knownUsage(start+1hr,finish,finish)
      verifyEq(observed["detailsTruncated"],quota < 2)
      verify(EnerCubixMath.maps(observed["intervals"]).size <= quota)
      verify(!observed.containsKey("_closedOwnPrimaryHour"))
      verify(!observed.containsKey("_containsSubstitutedIntervals"))
      verify(!util::JsonOutStream.writeJsonToStr(output).contains("_closedOwnPrimaryHour"))
    }
  }

  Void testDenseRuleEligibilityUsesAllIntervalsBeforeLocalDiagnosticLimit()
  {
    start:=DateTime.fromIso(query["from"].toStr);finish:=start+1hr
    intervals:=(0..<1800).map |i->[Str:Obj?]| {["from":(start+Duration(i*2sec.ticks)).toIso,"to":(start+Duration((i+1)*2sec.ticks)).toIso,"value":1f,"quality":"cleaned","valueType":"number"]}
    h:=Str:Obj?["pointId":"p","mode":"interval","unit":"kWh","quality":"cleaned","intervals":intervals]
    result:=EnerCubixMath.maps(run([profile],[h])["evaluations"]).first
    verifyEq(result["status"],"triggered");verifyEq(result["actual"],1800f)
    data:=EnerCubixHistoryData(h).knownUsage(start,finish,finish,true)
    verifyEq(data["detailsTruncated"],true);verifyEq(data["intervalCount"],1800)
    verifyEq(EnerCubixMath.maps(data["intervals"]).size,1000);verifyEq(data["_closedOwnPrimaryHour"],true)
    // The invalid source fact is beyond the returned diagnostic prefix.
    ((Map)intervals[1750])["quality"]="substituted"
    data=EnerCubixHistoryData(h).knownUsage(start,finish,finish,true)
    verifyNull(data["_closedOwnPrimaryHour"])
    verifyEq(EnerCubixMath.maps(run([profile],[h])["evaluations"]).first["status"],"unavailable")
    verifyEq(data["_containsSubstitutedIntervals"],true,"the substitution beyond diagnostic row1000 must remain provable")
    evaluation:=EnerCubixMath.maps(run([profile],[h])["evaluations"]).first
    verifyEq(((Map)evaluation["inputs"])["substitutedNonWorkingHours"],1)
    verifyEq(((Map)evaluation["inputs"])["unknownSubstitutionNonWorkingHours"],0)
  }

  Void testNoDiagnosticRowsDoNotProveCrossHourSubstitutedOrNAData()
  {
    start:=DateTime.fromIso(query["from"].toStr);finish:=start+2hr
    q:=query;q["to"]=finish.toIso;q["asOf"]=finish.toIso;q["_cockpitReadRanges"]=[["from":start.toIso,"to":finish.toIso]];q["_cockpitNeedsRuleFacts"]=true
    cases:=[
      [HisItem(start,Number(0)),HisItem(finish,Number(20))],
      [HisItem(start,Number(0)),HisItem(start+1hr,Number(100)),HisItem(finish,Number(200))],
      [HisItem(start,Number(0)),HisItem(start+1hr,NA.val),HisItem(finish,Number(20))]]
    cases.each |raw,index|
    {
      params:=Str:Obj?["deltaMin":Number(0),"deltaMax":Number(50)]
      if(index == 1) params["defVal"]=Number(1)
      else params["defNull"]=Marker.val
      cfg:=Etc.makeDict(params)
      point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":cfg])
      budget:=EnerCubixStreamBudget();budget.detailCount=1000
      hs:=EnerCubixCockpitStream.prepare(q,records,["p":point],["p":cfg],|Dict pt,Span span,|HisItem| sink| {raw.each |row| {if(row.ts>=span.start && row.ts<span.end) sink(row)}},budget)
      verifyEq(EnerCubixMath.maps(run([profile],hs,q)["evaluations"]).first["status"],"unavailable")
      ((Map)hs.first["_preparedReads"]).vals.each |pair| {((Map)((Map)pair)["known"]).vals.each |row| {verifyNull(((Map)row)["_closedOwnPrimaryHour"])}}
    }
  }

  Void testPrivateFactsAreRequestedOnlyForEnabledNonWorkingConsumers()
  {
    cases:=[["rules":[Str:Obj?][,],"expected":false],["rules":[profile.dup.set("enabled",false)],"expected":false],["rules":[profile.dup.set("ruleType","budgetVariance")],"expected":false],["rules":[profile],"expected":true]]
    cases.each |row|
    {
      requested:=false;calls:=0
      input:=Str:Obj?["schemaVersion":1,"requestId":"private-facts-consumer","reportScope":["dimension":"space","nodeIds":["s"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"hour","from":query["from"],"to":query["to"]],"asOf":query["asOf"],"comparison":["mode":"none"],"modules":["issues"]]
      EnerCubixCockpit.execute(input,records,|Str:Obj? q,[Str:Obj?][] rs->[Str:Obj?][]| {calls++;requested=q["_cockpitNeedsRuleFacts"] == true;return history},"test",TimeZone.utc,DateTime.fromIso(query["to"].toStr),true,null,null,null,null,info(EnerCubixMath.maps(row["rules"])))
      verifyEq(calls,1);verifyEq(requested,row["expected"])
    }
  }

  private Str:Obj? run([Str:Obj?][] ps,[Str:Obj?][] hs,[Str:Obj?]? q:=null,[Str:Obj?][]? rs:=null)
  {EnerCubixCockpitRules.project(q ?: query,rs ?: records,hs,info(ps),boundary,EnerCubixBudgetMath.unavailable("BUDGET_NOT_CONFIGURED"),"snapshot")}
  private Str:Obj? info([Str:Obj?][] ps) {["rules":ps,"rulesComplete":true,"modelComplete":true,"projectRef":"p:test"]}
  private Str:Obj? profile() {["id":"rule","version":1,"name":"Explicit rule","scopeKind":"project","scopeRef":"p:test","categoryRef":"c","calendarRef":"cal","ruleType":"nonWorkingHighUsage","threshold":5f,"thresholdUnit":"kWh","enabled":true]}
  private Str:Obj? query() {["from":"2026-10-01T00:00:00Z","to":"2026-10-01T01:00:00Z","asOf":"2026-10-01T01:00:00Z","tz":"UTC","dimension":"space","spaceSource":"fin","nodeIds":["s"],"categoryIds":["c"]]}
  private Str:Obj? boundary() {["id":"boundary","meterIds":["a"],"sourcePointIds":["p"],"aggregateAllowed":true]}
  private [Str:Obj?][] history() {[["pointId":"p","mode":"interval","unit":"kWh","samples":[["ts":"2026-10-01T00:00:00Z","value":10f]]]]}
  private [Str:Obj?][] records() {[["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space","nativeSourceKind":"site"],["id":"a","kind":"meter","nativeEquip":true,"spaceId":"s","categoryId":"c","pointId":"p"],["id":"cal","kind":"calendar","workDays":[1,2,3,4,5],"workHours":[9,10,11,12,13,14,15,16,17],"exceptions":[Str:Obj?][,]]]}
}

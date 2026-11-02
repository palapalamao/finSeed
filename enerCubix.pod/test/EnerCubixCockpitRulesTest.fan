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
  private Str:Obj? run([Str:Obj?][] ps,[Str:Obj?][] hs,[Str:Obj?]? q:=null,[Str:Obj?][]? rs:=null)
  {EnerCubixCockpitRules.project(q ?: query,rs ?: records,hs,info(ps),boundary,EnerCubixBudgetMath.unavailable("BUDGET_NOT_CONFIGURED"),"snapshot")}
  private Str:Obj? info([Str:Obj?][] ps) {["rules":ps,"rulesComplete":true,"modelComplete":true,"projectRef":"p:test"]}
  private Str:Obj? profile() {["id":"rule","version":1,"name":"Explicit rule","scopeKind":"project","scopeRef":"p:test","categoryRef":"c","calendarRef":"cal","ruleType":"nonWorkingHighUsage","threshold":5f,"thresholdUnit":"kWh","enabled":true]}
  private Str:Obj? query() {["from":"2026-10-01T00:00:00Z","to":"2026-10-01T01:00:00Z","asOf":"2026-10-01T01:00:00Z","tz":"UTC","dimension":"space","spaceSource":"fin","nodeIds":["s"],"categoryIds":["c"]]}
  private Str:Obj? boundary() {["id":"boundary","meterIds":["a"],"sourcePointIds":["p"],"aggregateAllowed":true]}
  private [Str:Obj?][] history() {[["pointId":"p","mode":"interval","unit":"kWh","samples":[["ts":"2026-10-01T00:00:00Z","value":10f]]]]}
  private [Str:Obj?][] records() {[["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space","nativeSourceKind":"site"],["id":"a","kind":"meter","nativeEquip":true,"spaceId":"s","categoryId":"c","pointId":"p"],["id":"cal","kind":"calendar","workDays":[1,2,3,4,5],"workHours":[9,10,11,12,13,14,15,16,17],"exceptions":[Str:Obj?][,]]]}
}

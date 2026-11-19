class FinEnergyCockpitBudgetTest : Test
{
  Void testReferenceUsesIdenticalClosedCutoffWithoutExtrapolation()
  {
    owned:=info;b:=budget("project","p:test","2026-11");b["amount"]=11000000f;owned["budgets"]=[b]
    q:=query;q.setAll(["from":"2026-11-01T00:00:00+08:00","to":"2026-11-03T18:45:30+08:00","asOf":"2026-11-03T18:45:30.96964+08:00","tz":"Shanghai"])
    m:=metric;m.setAll(["value":1101690.70961312f,"completeValue":null,"valueBasis":"knownSubtotal","quality":"partial","reasonCodes":["estimated","filtered"],"coverage":[["complete":false]]])
    r:=FinEnergyCockpitBudget.project(q,records,owned,boundary,m)
    verify(((Float)r["periodBudget"]-1019918.9814814816f).abs<0.0000001f)
    verify(((Float)r["referenceVariancePct"]-8.017472918570551f).abs<0.0000001f)
    verify(((Float)r["referenceMonthUsagePct"]-10.015370087392f).abs<0.0000001f)
    verifyEq(((Map)r["referenceBasis"])["reasonCodes"],["estimated","filtered"])
    verifyNull(r["variancePct"]);verifyNull(r["monthUsagePct"])
    // Moving the observation later than a closed query cannot expand its budget.
    q["asOf"]="2026-11-04T00:00:00+08:00"
    later:=FinEnergyCockpitBudget.project(q,records,owned,boundary,m)
    verifyEq(later["periodBudget"],r["periodBudget"]);verifyEq(later["referenceVariancePct"],r["referenceVariancePct"])
  }
  Void testReferenceRatesRetainStrictEligibilityAndActualQuality()
  {
    owned:=info;owned["budgets"]=[budget("project","p:test","2026-10")]
    ["partial","estimated"].each |quality|
    {
      m:=metric;m.setAll(["valueBasis":"knownSubtotal","completeValue":null,"quality":quality,"reasonCodes":[quality],"coverage":[["complete":false]],"value":1101690.70961312f])
      b:=((List)owned["budgets"]).first as Map;b["amount"]=11000000f
      q:=query;q["asOf"]="2026-10-03T20:59:22.12Z"
      r:=FinEnergyCockpitBudget.project(q,records,owned,boundary,m)
      verifyEq(r["status"],"unavailable");verifyEq(r["comparisonStatus"],"unavailable")
      verifyNull(r["variancePct"]);verifyNull(r["monthUsagePct"])
      verify(r["referenceVariancePct"] is Float);verify(((Float)r["referenceMonthUsagePct"]-10.015370087392f).abs<0.0000001f)
      basis:=r["referenceBasis"] as Map
      verifyEq(basis["quality"],quality);verifyEq(basis["reasonCodes"],[quality]);verifyEq(basis["effectiveTo"],r["effectiveTo"])
      verify(((Float)r["referenceVariancePct"]-(1101690.70961312f-(Float)r["periodBudget"])/(Float)r["periodBudget"]*100f).abs<0.0000001f)
      m["value"]=0f;r=FinEnergyCockpitBudget.project(query,records,owned,boundary,m)
      verifyEq(r["referenceVariancePct"],-100f);verifyEq(r["referenceMonthUsagePct"],0f)
      m["value"]=null;r=FinEnergyCockpitBudget.project(query,records,owned,boundary,m)
      verifyNull(r["referenceVariancePct"]);verifyNull(r["referenceMonthUsagePct"])
    }
  }
  Void testReferenceRatesRespectScopeCurrencyMonthsAndZeroPeriod()
  {
    owned:=info;b:=budget("project","p:test","2026-10");owned["budgets"]=[b]
    m:=metric;m.setAll(["valueBasis":"knownSubtotal","completeValue":null,"quality":"partial","coverage":[["complete":false]]])
    b["distribution"]="daily";b["dailyAmounts"]=[0f].addAll((1..30).map |i->Float| {310000f/30f})
    q:=query;q["to"]="2026-10-02T00:00:00Z";q["asOf"]=q["to"]
    r:=FinEnergyCockpitBudget.project(q,records,owned,boundary,m)
    verifyNull(r["referenceVariancePct"]);verify(r["referenceMonthUsagePct"] is Float)
    b["currency"]="USD";r=FinEnergyCockpitBudget.project(q,records,owned,boundary,m)
    verifyNull(r["referenceVariancePct"]);verifyNull(r["referenceMonthUsagePct"])
    b["currency"]="CNY";owned["budgets"]=[b,b.dup]
    r=FinEnergyCockpitBudget.project(q,records,owned,boundary,m);verifyNull(r["referenceMonthUsagePct"])
    owned["budgets"]=[b];q["to"]="2026-12-01T00:00:00Z";q["asOf"]=q["to"]
    r=FinEnergyCockpitBudget.project(q,records,owned,boundary,m);verifyNull(r["referenceMonthUsagePct"])
    owned["budgets"]=[Str:Obj?][,];r=FinEnergyCockpitBudget.project(query,records,owned,boundary,m);verifyNull(r["referenceMonthUsagePct"])
    owned["budgets"]=[b];bad:=boundary;bad["aggregateAllowed"]=false
    r=FinEnergyCockpitBudget.project(query,records,owned,bad,m);verifyNull(r["referenceMonthUsagePct"])
  }
  Void testCanonicalCurrencyLegacyExplicitMixedAndInvalid()
  {
    cost:=metric
    verifyEq(FinEnergyCockpitBudget.currency(cost)["basis"],"legacyCnyConvention")
    ((Map)cost["details"])["tariffs"]=[["id":"t","currency":"CNY"],["id":"legacy"]]
    verifyEq(FinEnergyCockpitBudget.currency(cost)["basis"],"mixedExplicitAndLegacyCny")
    ((Map)cost["details"])["tariffs"]=[["currency":"USD"]];cost["unit"]="USD"
    verifyEq(FinEnergyCockpitBudget.currency(cost)["status"],"ok")
    ((Map)cost["details"])["tariffs"]=[["currency":"USD"],Str:Obj?[:]]
    verifyEq(FinEnergyCockpitBudget.currency(cost)["status"],"unavailable")
    ["",4].each |invalid| {((Map)cost["details"])["tariffs"]=[["currency":invalid]];cost["unit"]="CNY";verifyEq(FinEnergyCockpitBudget.currency(cost)["reason"],"BUDGET_CURRENCY_INVALID")}
  }
  Void testProjectAndSiteConflictIsIndependentOfViewAndCrossMonthCannotStitch()
  {
    ["space","metering","organization"].each |dimension|
    {
      q:=query;q["dimension"]=dimension
      owned:=info;owned["budgets"]=[budget("project","p:test","2026-10"),budget("space","s","2026-10")]
      r:=FinEnergyCockpitBudget.project(q,records,owned,boundary,metric)
      verifyEq(r["status"],"unavailable");verifyEq(r["reasonCodes"],["BUDGET_SCOPE_CONFLICT"])
    }
    owned:=info;owned["budgets"]=[budget("project","p:test","2026-10"),budget("space","s","2026-11")]
    q:=query;q["to"]="2026-12-01T00:00:00Z";q["asOf"]=q["to"]
    verifyEq(FinEnergyCockpitBudget.project(q,records,owned,boundary,metric)["reasonCodes"],["BUDGET_SCOPE_CONFLICT"])
  }
  Void testExactBudgetComputesAndPartialCostZeroAreNotConfused()
  {
    owned:=info;owned["budgets"]=[budget("project","p:test","2026-10")]
    r:=FinEnergyCockpitBudget.project(query,records,owned,boundary,metric)
    verifyEq(r["status"],"ok");verify(((Float)r["periodBudget"]-240000f).abs<0.000001f)
    verifyEq(r["referenceVariancePct"],r["variancePct"]);verifyEq(r["referenceMonthUsagePct"],r["monthUsagePct"])
    m:=metric;m["value"]=0f;m["completeValue"]=0f
    verifyEq(FinEnergyCockpitBudget.project(query,records,owned,boundary,m)["monthUsagePct"],0f)
    m["valueBasis"]="knownSubtotal";m["completeValue"]=null
    r=FinEnergyCockpitBudget.project(query,records,owned,boundary,m)
    verifyEq(r["status"],"unavailable");verifyNull(r["variancePct"])
  }
  Void testProvablyUnrelatedInvalidConfigurationsDoNotPoisonCurrentBudget()
  {
    owned:=info
    invalid:=Str:Obj?["id":"old-invalid","mod":"v1","validation":"invalid","reasonCodes":["OWNED_REFERENCE_INVALID"]]
    owned["budgets"]=[budget("project","p:test","2026-10"),invalid]
    owned["budgetAttribution"]=["old-invalid":["month":"2026-09","categoryRef":"c","scopeKind":"project","scopeRef":"p:test","scopeReadable":true]]
    r:=FinEnergyCockpitBudget.project(query,records,owned,boundary,metric)
    verifyEq(r["status"],"ok");verifyEq(FinEnergyMath.maps(r["configRefs"]).size,1)
    ((Map)owned["budgetAttribution"])["old-invalid"]=["month":"2026-10","categoryRef":"other"]
    verifyEq(FinEnergyCockpitBudget.project(query,records,owned,boundary,metric)["status"],"ok")
    owned["budgetAttribution"]=["old-invalid":["month":"2026-10","categoryRef":"c","scopeKind":"project","scopeRef":"p:test","scopeReadable":true]]
    verifyEq(FinEnergyCockpitBudget.project(query,records,owned,boundary,metric)["reasonCodes"],["BUDGET_CONFIG_INVALID"])
    owned.remove("budgetAttribution")
    verifyEq(FinEnergyCockpitBudget.project(query,records,owned,boundary,metric)["reasonCodes"],["BUDGET_CONFIG_INVALID"])
    rs:=records;rs.addAll([["id":"other-space","kind":"space","nativeSourceKind":"site"],["id":"other-meter","kind":"meter","nativeEquip":true,"pointId":"other-point","categoryId":"c","spaceId":"other-space"]])
    owned["budgets"]=[budget("space","s","2026-10"),invalid]
    owned["budgetAttribution"]=["old-invalid":["month":"2026-10","categoryRef":"c","scopeKind":"space","scopeRef":"other-space","scopeReadable":true]]
    verifyEq(FinEnergyCockpitBudget.project(query,rs,owned,boundary,metric)["status"],"ok")
    ((Map)((Map)owned["budgetAttribution"])["old-invalid"])["scopeReadable"]=false
    verifyEq(FinEnergyCockpitBudget.project(query,rs,owned,boundary,metric)["reasonCodes"],["BUDGET_CONFIG_INVALID"])
  }
  Void testOtherMonthAttributionUsesProjectCalendarAcrossDstOffsetChange()
  {
    q:=query;q.setAll(["from":"2026-11-01T00:00:00-04:00","to":"2026-12-01T00:00:00-05:00","asOf":"2026-12-01T00:00:00-05:00","tz":"New_York"])
    owned:=info;owned["budgets"]=[budget("project","p:test","2026-11"),["id":"december-invalid","validation":"invalid"]]
    owned["budgetAttribution"]=["december-invalid":["month":"2026-12","categoryRef":"c","scopeKind":"project","scopeRef":"p:test","scopeReadable":true]]
    verifyEq(FinEnergyCockpitBudget.project(q,records,owned,boundary,metric)["status"],"ok")
    q.setAll(["from":"2026-12-01T00:00:00-05:00","to":"2027-01-01T00:00:00-05:00","asOf":"2027-01-01T00:00:00-05:00"])
    owned["budgets"]=[budget("project","p:test","2026-12"),["id":"january-invalid","validation":"invalid"]]
    owned["budgetAttribution"]=["january-invalid":["month":"2027-01","categoryRef":"c","scopeKind":"project","scopeRef":"p:test","scopeReadable":true]]
    verifyEq(FinEnergyCockpitBudget.project(q,records,owned,boundary,metric)["status"],"ok")
  }
  private Str:Obj? budget(Str kind,Str scope,Str month) {["id":kind+month,"version":1,"scopeKind":kind,"scopeRef":scope,"categoryRef":"c","month":month,"currency":"CNY","amount":310000f,"distribution":"uniform","enabled":true]}
  private Str:Obj? info() {["projectRef":"p:test","modelComplete":true,"budgetsComplete":true]}
  private Str:Obj? query() {["dimension":"space","nodeIds":["s"],"categoryIds":["c"],"from":"2026-10-01T00:00:00Z","to":"2026-10-25T00:00:00Z","asOf":"2026-10-25T00:00:00Z","tz":"UTC"]}
  private Str:Obj? boundary() {["id":"boundary","meterIds":["a"],"aggregateAllowed":true]}
  private Str:Obj? metric() {["id":"cost","value":224600f,"completeValue":224600f,"valueBasis":"complete","unit":"CNY","quality":"ok","coverage":[["complete":true]],"details":["tariffs":[["id":"tariff"]]]]}
  private [Str:Obj?][] records() {[["id":"s","kind":"space","nativeSourceKind":"site","nativeSourceId":"s"],["id":"c","kind":"category","unit":"kWh"],["id":"a","kind":"meter","nativeEquip":true,"pointId":"p","spaceId":"s","categoryId":"c"]]}
}

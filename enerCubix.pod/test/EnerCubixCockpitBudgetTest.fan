class EnerCubixCockpitBudgetTest : Test
{
  Void testCanonicalCurrencyLegacyExplicitMixedAndInvalid()
  {
    cost:=metric
    verifyEq(EnerCubixCockpitBudget.currency(cost)["basis"],"legacyCnyConvention")
    ((Map)cost["details"])["tariffs"]=[["id":"t","currency":"CNY"],["id":"legacy"]]
    verifyEq(EnerCubixCockpitBudget.currency(cost)["basis"],"mixedExplicitAndLegacyCny")
    ((Map)cost["details"])["tariffs"]=[["currency":"USD"]];cost["unit"]="USD"
    verifyEq(EnerCubixCockpitBudget.currency(cost)["status"],"ok")
    ((Map)cost["details"])["tariffs"]=[["currency":"USD"],Str:Obj?[:]]
    verifyEq(EnerCubixCockpitBudget.currency(cost)["status"],"unavailable")
    ["",4].each |invalid| {((Map)cost["details"])["tariffs"]=[["currency":invalid]];cost["unit"]="CNY";verifyEq(EnerCubixCockpitBudget.currency(cost)["reason"],"BUDGET_CURRENCY_INVALID")}
  }
  Void testProjectAndSiteConflictIsIndependentOfViewAndCrossMonthCannotStitch()
  {
    ["space","metering","organization"].each |dimension|
    {
      q:=query;q["dimension"]=dimension
      owned:=info;owned["budgets"]=[budget("project","p:test","2026-10"),budget("space","s","2026-10")]
      r:=EnerCubixCockpitBudget.project(q,records,owned,boundary,metric)
      verifyEq(r["status"],"unavailable");verifyEq(r["reasonCodes"],["BUDGET_SCOPE_CONFLICT"])
    }
    owned:=info;owned["budgets"]=[budget("project","p:test","2026-10"),budget("space","s","2026-11")]
    q:=query;q["to"]="2026-12-01T00:00:00Z";q["asOf"]=q["to"]
    verifyEq(EnerCubixCockpitBudget.project(q,records,owned,boundary,metric)["reasonCodes"],["BUDGET_SCOPE_CONFLICT"])
  }
  Void testExactBudgetComputesAndPartialCostZeroAreNotConfused()
  {
    owned:=info;owned["budgets"]=[budget("project","p:test","2026-10")]
    r:=EnerCubixCockpitBudget.project(query,records,owned,boundary,metric)
    verifyEq(r["status"],"ok");verify(((Float)r["periodBudget"]-240000f).abs<0.000001f)
    m:=metric;m["value"]=0f;m["completeValue"]=0f
    verifyEq(EnerCubixCockpitBudget.project(query,records,owned,boundary,m)["monthUsagePct"],0f)
    m["valueBasis"]="knownSubtotal";m["completeValue"]=null
    r=EnerCubixCockpitBudget.project(query,records,owned,boundary,m)
    verifyEq(r["status"],"unavailable");verifyNull(r["variancePct"])
  }
  private Str:Obj? budget(Str kind,Str scope,Str month) {["id":kind+month,"version":1,"scopeKind":kind,"scopeRef":scope,"categoryRef":"c","month":month,"currency":"CNY","amount":310000f,"distribution":"uniform","enabled":true]}
  private Str:Obj? info() {["projectRef":"p:test","modelComplete":true,"budgetsComplete":true]}
  private Str:Obj? query() {["dimension":"space","nodeIds":["s"],"categoryIds":["c"],"from":"2026-10-01T00:00:00Z","to":"2026-10-25T00:00:00Z","asOf":"2026-10-25T00:00:00Z","tz":"UTC"]}
  private Str:Obj? boundary() {["id":"boundary","meterIds":["a"],"aggregateAllowed":true]}
  private Str:Obj? metric() {["id":"cost","value":224600f,"completeValue":224600f,"valueBasis":"complete","unit":"CNY","quality":"ok","coverage":[["complete":true]],"details":["tariffs":[["id":"tariff"]]]]}
  private [Str:Obj?][] records() {[["id":"s","kind":"space","nativeSourceKind":"site","nativeSourceId":"s"],["id":"c","kind":"category","unit":"kWh"],["id":"a","kind":"meter","nativeEquip":true,"pointId":"p","spaceId":"s","categoryId":"c"]]}
}

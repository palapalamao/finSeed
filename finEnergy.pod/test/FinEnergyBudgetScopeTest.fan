class FinEnergyBudgetScopeTest : Test
{
  Void testWholeProjectAndSpaceMatchAcrossViewsIncludingMissingMembers()
  {
    rs:=records
    ["space","metering","organization"].each |dimension|
    {
      q:=request(dimension);boundary:=Str:Obj?["meterIds":["a","b"],"aggregateAllowed":true]
      verify(FinEnergyBudgetScope.match("project","p:test","c",q,boundary,rs,"p:test")["eligible"] == true)
      verify(FinEnergyBudgetScope.match("space","s","c",q,boundary,rs,"p:test")["eligible"] == true)
    }
    rs.add(["id":"unplaced","kind":"meter","pointId":"pu","categoryId":"c"])
    verify(FinEnergyBudgetScope.match("project","p:test","c",request("space"),["meterIds":["a","b"],"aggregateAllowed":true],rs,"p:test")["eligible"] == false)
  }
  Void testHiddenAndVirtualOwnBoundariesNeverBecomeVisibleLeafEquivalence()
  {
    rs:=records;rs.last["_comparisonReadable"]=false
    verify(FinEnergyBudgetScope.match("project","p:test","c",request("metering"),["meterIds":["a"],"aggregateAllowed":true],rs,"p:test")["eligible"] == false)
    rs=records;rs.add(["id":"v","kind":"meter","pointId":"pv","categoryId":"c","expressionId":"formula","includeInTotals":true])
    verify(FinEnergyBudgetScope.match("space","s","c",request("metering"),["meterIds":["v"],"aggregateAllowed":true],rs,"p:test")["eligible"] == false)
    verify(FinEnergyBudgetScope.match("space","s","c",request("space"),["meterIds":["a","b"],"aggregateAllowed":false],records,"p:test")["eligible"] == false)
  }
  private Str:Obj? request(Str d) {["dimension":d,"nodeIds":d=="space" ? ["s"] : (d=="organization" ? ["org"] : ["a","b"]),"categoryIds":["c"],"spaceSource":"fin"]}
  private [Str:Obj?][] records() {[["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space","nativeSourceId":"s","nativeSourceKind":"site"],["id":"org","kind":"organization"],["id":"a","kind":"meter","nativeEquip":true,"pointId":"pa","categoryId":"c","spaceId":"s","organizationId":"org"],["id":"b","kind":"meter","nativeEquip":true,"pointId":"pb","categoryId":"c","spaceId":"s","organizationId":"org"]]}
}

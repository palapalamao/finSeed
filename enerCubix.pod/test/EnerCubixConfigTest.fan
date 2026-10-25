class EnerCubixConfigTest : Test
{
  Void testHistoryModeValidation()
  {
    records:=[map(["id":"g","kind":"group","name":"楼"]),map(["id":"c","kind":"category","name":"电"])]
    meter:=map(["id":"m","kind":"meter","name":"表","parentId":"g","categoryId":"c","pointId":"p","historyMode":"cumulative"])
    EnerCubixConfig.validate(meter,records)
    records.add(meter)
    other:=meter.dup; other["id"]="m2"; other["name"]="另一表"; other["historyMode"]="interval"
    verifyErr(ArgErr#) { EnerCubixConfig.validate(other,records) }
    other["historyMode"]="unknown"
    verifyErr(ArgErr#) { EnerCubixConfig.validate(other,records) }
    other["historyMode"]="auto"; EnerCubixConfig.validate(other,records)
  }
  Void testParentCycle()
  {
    records := [map(["id":"g1", "kind":"group", "name":"楼宇"]), map(["id":"g2", "kind":"group", "name":"楼层", "parentId":"g1"])]
    verifyErr(ArgErr#) { EnerCubixConfig.validate(map(["id":"g1", "kind":"group", "name":"楼宇", "parentId":"g2"]), records) }
  }
  Void testMasterUniqueness()
  {
    records := [map(["id":"g", "kind":"group", "name":"楼宇"]), map(["id":"c", "kind":"category", "name":"电", "unit":"kWh"]), map(["id":"m", "kind":"totalMeter", "name":"总电", "parentId":"g", "categoryId":"c"])]
    verifyErr(ArgErr#) { EnerCubixConfig.validate(map(["kind":"totalMeter", "name":"重复总电", "parentId":"g", "categoryId":"c"]), records) }
  }
  Void testReferencedDeletion()
  {
    records := [map(["id":"g", "kind":"group", "name":"楼宇"]), map(["id":"m", "kind":"meter", "name":"电表", "parentId":"g"])]
    verifyErr(ArgErr#) { EnerCubixConfig.canDelete("g", records) }
  }
  Void testHistoricalEventsDoNotPreventConfigurationCleanup()
  {
    records := [map(["id":"m","kind":"meter","name":"表"]),map(["id":"a","kind":"alarm","name":"历史报警","nodeId":"m"]) ]
    EnerCubixConfig.canDelete("m",records)
    verifyEq(records[1]["nodeId"],"m")
  }
  Void testFiveTariffs()
  {
    ["flat", "absolute", "weekly", "monthlyBlock", "yearlyBlock"].each |mode| { EnerCubixConfig.validate(map(["kind":"tariff", "name":mode, "mode":mode, "rate":1f, "blocks":[map(["limit":1000f,"rate":5f]), map(["limit":null,"rate":10f])]]), [,]) }
    verifyErr(ArgErr#) { EnerCubixConfig.validate(map(["kind":"tariff", "name":"错误费率", "mode":"other"]), [,]) }
  }
  Void testForeignSubcategory()
  {
    records := [map(["id":"g", "kind":"group", "name":"楼"]), map(["id":"c1", "kind":"category", "name":"电"]), map(["id":"c2", "kind":"category", "name":"水"]), map(["id":"s", "kind":"subcategory", "name":"水子类", "categoryId":"c2"])]
    verifyErr(ArgErr#) { EnerCubixConfig.validate(map(["kind":"meter", "name":"错配", "parentId":"g", "categoryId":"c1", "subcategoryId":"s"]), records) }
  }
  Void testFormulaInjection()
  {
    verifyErr(ArgErr#) { EnerCubixConfig.validate(map(["kind":"expression", "name":"非法", "formula":"readAll(point)", "variables":Str:Obj?[:]]), [,]) }
  }
  Void testDefaultUniqueness()
  {
    cat := map(["id":"c","kind":"category","name":"电"])
    rate := map(["id":"t","kind":"tariff","name":"默认","categoryId":"c","isDefault":true,"mode":"flat","rate":1f])
    verifyErr(ArgErr#) { EnerCubixConfig.validate(map(["kind":"tariff","name":"第二默认","categoryId":"c","isDefault":true]),[cat,rate]) }
    verifyErr(ArgErr#) { EnerCubixConfig.validate(map(["kind":"calendar","name":"第二默认","isDefault":true]),[map(["id":"cal","kind":"calendar","name":"默认","isDefault":true])]) }
  }
  Void testCalendarOverlapAndDate()
  {
    verifyErr(ArgErr#) { EnerCubixConfig.validate(map(["kind":"calendar","name":"重叠","peakHours":[8],"valleyHours":[8]]),[,]) }
    verifyErr(ArgErr#) { EnerCubixConfig.validate(map(["kind":"calendar","name":"错误日期","exceptions":[map(["date":"2026-02-30","working":true])]]),[,]) }
  }
  Void testFormulaSyntaxAndLateBindingCycle()
  {
    records := [map(["id":"g","kind":"group","name":"楼"]),map(["id":"c","kind":"category","name":"电"]),map(["id":"m","kind":"meter","name":"表","parentId":"g","categoryId":"c"])]
    verifyErr(ArgErr#) { EnerCubixConfig.validate(map(["kind":"expression","name":"错","formula":"a/*2","variables":["a":"m"]]),records) }
    expr := map(["id":"e","kind":"expression","name":"公式","formula":"a+1","variables":["a":"m"]])
    records.add(expr)
    verifyErr(ArgErr#) { EnerCubixConfig.validate(map(["id":"m","kind":"meter","name":"表","parentId":"g","categoryId":"c","expressionId":"e"]),records) }
  }
  private [Str:Obj?] map([Str:Obj?] m) { m }
}

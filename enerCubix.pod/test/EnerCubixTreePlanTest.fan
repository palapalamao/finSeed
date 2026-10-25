class EnerCubixTreePlanTest : Test
{
  Void testBranchSelectionAndExternalDependencies()
  {
    all:=records
    plan:=EnerCubixTreePlan.deletion(all,["g"])
    verifyEq(((List)plan["records"]).size,3)
    verifyEq(((List)plan["blockers"]).size,1)
    all.removeAt(4)
    verifyEq(((List)EnerCubixTreePlan.deletion(all,["g","child"])["records"]).size,3)
    verifyEq(((List)EnerCubixTreePlan.deletion(all,["g"])["blockers"]).size,0)
    verifyEq(EnerCubixTreePlan.roots(all,["g","m","child"]),["g"])
    verifyErr(ArgErr#) { EnerCubixTreePlan.deletion(all,["c"]) }
    verifyErr(ArgErr#) { EnerCubixTreePlan.deletion(all,["missing"]) }
  }

  Void testMoveKeepsSubtreeAndRejectsCycleOrDuplicateMasters()
  {
    all:=records
    verifyErr(ArgErr#) { EnerCubixTreePlan.move(all,["g"],"child") }
    changed:=EnerCubixTreePlan.move(all,["child","m"],"outside")
    verifyEq(changed.size,1)
    verifyEq(changed.first["id"],"child")
    verifyEq(changed.first["parentId"],"outside")
    verifyEq(all[2]["parentId"],"child")
    all.add(["id":"master1","kind":"totalMeter","name":"总表一","parentId":"child","categoryId":"c"])
    all.add(["id":"master2","kind":"totalMeter","name":"总表二","parentId":"outside","categoryId":"c"])
    verifyErr(ArgErr#) { EnerCubixTreePlan.move(all,["master1"],"outside") }
  }

  private [Str:Obj?][] records()
  {
    [
      [Str:Obj?]["id":"g","kind":"group","name":"主组"],
      [Str:Obj?]["id":"child","kind":"group","name":"子组","parentId":"g"],
      [Str:Obj?]["id":"m","kind":"meter","name":"分表","parentId":"child","categoryId":"c","pointId":"native-point"],
      [Str:Obj?]["id":"c","kind":"category","name":"电","unit":"kWh"],
      [Str:Obj?]["id":"t","kind":"template","name":"外部模板","request":["nodeIds":["m"]]],
      [Str:Obj?]["id":"outside","kind":"group","name":"其他组"],
      [Str:Obj?]["id":"a","kind":"alarm","name":"历史报警","nodeId":"m"],
    ]
  }
}

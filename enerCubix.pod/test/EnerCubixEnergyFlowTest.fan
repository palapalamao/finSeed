class EnerCubixEnergyFlowTest : Test
{
  Void testOverviewUsesOnlyIndependentMastersAndPreservesAllLevels()
  {
    r:=run; flow:=data(r); ns:=nodes(r)
    verifyEq(flow["rootIds"],["main","other"])
    near(node(r,"__energyFlow__:electric")["value"],150f)
    near(node(r,"main")["submeter"],90f)
    near(node(r,"main")["difference"],10f)
    near(node(r,"a")["difference"],10f)
    near(node(r,"__energyFlowDifference__:main")["value"],10f)
    verify(ns.any |n| { n["id"] == "grand" })
    verifyEq(((Str[])node(r,"grand")["sourceIds"]),["pg"])
    near(links(r).find |l| { l["target"] == "a" }["percentage"],60f)
  }

  Void testHistoryPlanIncludesEveryDescendantButNoOtherEnergy()
  {
    rs:=records; rs.add(meter("water","pw",null,1f).set("categoryId","water"))
    verifyEq(EnerCubixHistory.pointIds(request,rs),["pa","pb","pg","po","pq","pt"])
    req:=request; req["nodeIds"]=["a"]
    verifyEq(EnerCubixHistory.pointIds(req,rs),["pa","pg"])
  }

  Void testFocusedSubtreeAndAliasAreCanonical()
  {
    rs:=records; rs.add(meter("alias","pa","main",1f).set("canonicalId","a"))
    req:=request; req["nodeIds"]=["alias"]
    r:=EnerCubixEngine.report(req,rs,histories)
    verifyEq(data(r)["focusId"],"a"); verifyEq(data(r)["rootIds"],["a"])
    verifyEq(nodes(r).map |n->Str| { n["id"].toStr }.sort,["__energyFlowDifference__:a","a","grand"])
    verify(!nodes(r).any |n| { n["id"] == "alias" })
  }

  Void testMissingChildKeepsTheAvailableSiblingLink()
  {
    hs:=histories; hs.find |h| { h["pointId"] == "pb" }["samples"]=[["ts":ts(0),"value":null]]
    r:=EnerCubixEngine.report(request,records,hs)
    near(node(r,"main")["value"],100f); verifyNull(node(r,"main")["difference"])
    verifyNull(node(r,"b")["value"])
    verify(links(r).any |l| { l["source"] == "main" && l["target"] == "a" })
    verify(!links(r).any |l| { l["source"] == "main" && l["target"] == "b" })
    verify(links(r).any |l| { l["source"] == "other" })
    verify(!nodes(r).any |n| { n["id"] == "__energyFlowDifference__:main" })
  }

  Void testFilteredChildPreservesKnownAmountWithoutPublishingDifference()
  {
    hs:=histories; hs.find |h| {h["pointId"] == "pb"}["quality"]="filtered"
    r:=EnerCubixEngine.report(request,records,hs)
    near(node(r,"b")["knownValue"],30f)
    verifyNull(node(r,"main")["difference"])
    verify(links(r).any |l| {l["source"] == "main" && l["target"] == "b" && l["value"] == 30f})
  }

  Void testNegativeDifferenceIsNeverAnInventedFlow()
  {
    hs:=histories; hs[0]=history("pt",50f)
    r:=EnerCubixEngine.report(request,records,hs)
    near(node(r,"main")["difference"],-40f)
    verifyEq(node(r,"main")["balanceQuality"],"negativeBalance")
    verifyEq(node(r,"main")["lossEligible"],false)
    verify(links(r).any |l| { l["source"] == "main" && l["target"] == "a" })
    verify(!nodes(r).any |n| {n["nodeType"] == "difference" && n["parentId"] == "main"})
    near(node(r,"a")["value"],60f)
    verify(((Str[])r["warnings"]).any |w| { w.contains("分表合计大于总表") })
  }

  Void testUnlinkedMetersAreNotInventedInputsAndMakeOverlapExplicit()
  {
    rs:=records; rs.add(meter("orphan","pu",null,1f))
    r:=EnerCubixEngine.report(request,rs,histories.add(history("pu",25f)))
    verifyEq(data(r)["rootIds"],["main","other"])
    verifyEq(EnerCubixMath.maps(data(r)["unassigned"]).map |n->Str| { n["id"].toStr },["orphan"])
    verifyNull(node(r,"__energyFlow__:electric")["value"])
    verifyEq(node(r,"__energyFlow__:electric")["quality"],"topologyIncomplete")
  }

  Void testOverlappingMastersWithholdProjectTotal()
  {
    rs:=records; rs.find |n| { n["id"] == "other" }["spaceId"]="sa"
    r:=EnerCubixEngine.report(request,rs,histories)
    verifyNull(node(r,"__energyFlow__:electric")["value"])
    near(node(r,"main")["value"],100f); near(node(r,"other")["value"],50f)
    verify(!links(r).any |l| { l["source"] == "__energyFlow__:electric" })
  }

  Void testZeroNeverCreatesAPercentageOrSyntheticDifference()
  {
    hs:=histories.map |h->[Str:Obj?]| { history(h["pointId"].toStr,0f) }
    r:=EnerCubixEngine.report(request,records,hs)
    near(node(r,"main")["value"],0f); verifyNull(node(r,"a")["percentage"])
    verify(links(r).isEmpty)
    verify(!nodes(r).any |n| { n["nodeType"] == "difference" })
  }

  Void testExcludedMetersAreNotPromotedOrCounted()
  {
    rs:=records; rs.find |n| { n["id"] == "a" }["includeInTotals"]=false
    r:=EnerCubixEngine.report(request,rs,histories)
    verify(!nodes(r).any |n| { n["id"] == "a" || n["id"] == "grand" })
    near(node(r,"main")["difference"],70f)
  }

  Void testInvalidChainIsReportedWithoutRecursion()
  {
    rs:=records; rs.find |n| { n["id"] == "a" }["meterParentId"]="grand"
    r:=EnerCubixEngine.report(request,rs,histories)
    verify(EnerCubixMath.maps(data(r)["unassigned"]).any |n| { n["id"] == "a" })
    verifyNull(node(r,"__energyFlow__:electric")["value"])
  }

  Void testIncompatibleHistoryUnitsStayNull()
  {
    hs:=histories; hs[1]["unit"]="m³"
    r:=EnerCubixEngine.report(request,records,hs)
    verifyNull(node(r,"a")["value"]); verifyEq(node(r,"a")["quality"],"incompatibleUnit")
  }

  Void testRejectsUnsupportedScopeAndMetrics()
  {
    req:=request; req["metric"]="cost"; verifyErr(ArgErr#) { EnerCubixEngine.report(req,records,histories) }
    req=request; req["perArea"]=true; verifyErr(ArgErr#) { EnerCubixEngine.report(req,records,histories) }
    req=request; req["nodeIds"]=["main","other"]
    selected:=EnerCubixEngine.report(req,records,histories)
    verifyEq(EnerCubixMath.strings(data(selected)["rootIds"]).sort,["main","other"])
    req=request; req["nodeIds"]=["main","a"]
    selected=EnerCubixEngine.report(req,records,histories)
    verifyEq(EnerCubixMath.strings(data(selected)["rootIds"]),["a","main"])
    req=request; req["categoryId"]="unknown"; verifyErr(ArgErr#) { EnerCubixEngine.report(req,records,histories) }
  }

  private Str:Obj? run() { EnerCubixEngine.report(request,records,histories) }
  private Str:Obj? data(Str:Obj? r) { (Str:Obj?)((Str:Obj?)r["extra"])["energyFlow"] }
  private [Str:Obj?][] nodes(Str:Obj? r) { EnerCubixMath.maps(data(r)["nodes"]) }
  private [Str:Obj?][] links(Str:Obj? r) { EnerCubixMath.maps(data(r)["links"]) }
  private Str:Obj? node(Str:Obj? r,Str id) { nodes(r).find |n| { n["id"] == id } ?: throw Err("Missing flow node: $id") }
  private Str:Obj? request() { ["kind":"energyFlow","dimension":"metering","nodeIds":Str[,],"categoryId":"electric","from":ts(0),"to":ts(1),"period":"day","metric":"energy","perArea":false,"tz":"UTC"] }
  private [Str:Obj?][] records()
  {
    rs:=[meter("main","pt",null,100f).set("kind","totalMeter").set("spaceId","sa"),meter("a","pa","main",60f).set("spaceId","sa"),meter("b","pb","main",30f).set("spaceId","sa"),meter("grand","pg","a",50f).set("spaceId","sa"),meter("other","po",null,50f).set("kind","totalMeter").set("spaceId","sb"),meter("q","pq","other",40f).set("spaceId","sb")]
    rs.add(["id":"electric","kind":"category","name":"Electric","unit":"kWh"])
    rs.add(["id":"sa","kind":"space","name":"A"]); rs.add(["id":"sb","kind":"space","name":"B"])
    return rs
  }
  private Str:Obj? meter(Str id,Str point,Str? parent,Float unused) { ["id":id,"kind":"meter","name":id,"pointId":point,"meterParentId":parent,"categoryId":"electric","unit":"kWh"] }
  private [Str:Obj?][] histories() { [history("pt",100f),history("pa",60f),history("pb",30f),history("pg",50f),history("po",50f),history("pq",40f)] }
  private Str:Obj? history(Str id,Float? v) { ["pointId":id,"unit":"kWh","mode":"interval","samples":[["ts":ts(0),"value":v]]] }
  private Str ts(Int hour) { (DateTime.fromIso("2026-10-19T00:00:00Z")+Duration(hour*1hr.ticks)).toIso }
  private Void near(Obj? actual,Float expected) { verifyNotNull(actual); verify((((Float)actual)-expected).abs < 0.000001f) }
}

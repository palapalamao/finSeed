class EnerCubixFlowViewsTest : Test
{
  Void testPartialDataStillDrawsAvailableBranchesOverTheWholeQuery()
  {
    req:=request(["t"]); req["to"]=at(2); req["asOf"]=at(2)
    hs:=histories; hs.find |h| {h["pointId"] == "pb"}["intervals"]=[interval(0,null)]
    r:=EnerCubixEngine.report(req,records,hs); g:=graph(r,"t")
    verifyNull(node(g,"t")["value"]); near(node(g,"t")["knownValue"],110f)
    near(EnerCubixMath.maps(g["links"]).find |l| {l["target"] == "a"}["value"],40f)
    verifyNull(node(g,"t")["difference"])
    verifyNull(extra(r)["energyFlowSegments"])
    verifyEq(r["from"],at(0)); verifyEq(r["to"],at(2))
    verify(EnerCubixMath.maps(r["rows"]).all |row| {row["graphId"] != null})
    verify(EnerCubixMath.maps(r["series"]).all |row| {row["graphId"] != null})
  }

  Void testArchivedVirtualGroupsShareInputsWithoutChangingTheirOwnValues()
  {
    r:=EnerCubixEngine.report(request(["g1","g2"]),records,histories)
    g1:=graph(r,"g1"); g2:=graph(r,"g2")
    near(node(g1,"g1")["value"],45f); near(node(g2,"g2")["value"],105f)
    verifyEq(g1["basis"],"calculation"); verifyEq(g1["additive"],true)
    verifyEq(g1["contributionMemberIds"],["a"])
    verifyEq(g1["sharedMemberIds"],["a"])
    verifyEq(EnerCubixMath.maps(g2["links"]).size,2)
    account:=(Map)extra(r)["energyFlowAccounting"]
    verifyEq(account["canAdd"],false); near(account["unionValue"],100f)
    verifyEq(account["basis"],"classificationUnion")
    verifyEq(account["sharedMemberIds"],["a"])
    verifyEq(records.find |m| {m["id"] == "a"}["meterParentId"],"t")
    verifyEq(EnerCubixHistory.pointIds(request(["g1","g2"]),records),["pa","pb","pg1","pg2"])
  }

  Void testApprovedHundredFortyHundredExampleHasOnlyOneContributionUnion()
  {
    hs:=histories
    hs.find |h| {h["pointId"] == "pt"}["intervals"]=[interval(0,100f)]
    hs.find |h| {h["pointId"] == "pg1"}["intervals"]=[interval(0,40f)]
    hs.find |h| {h["pointId"] == "pg2"}["intervals"]=[interval(0,100f)]
    r:=EnerCubixEngine.report(request(["t","g1","g2"]),records,hs)
    near(node(graph(r,"t"),"t")["value"],100f)
    near(node(graph(r,"g1"),"g1")["value"],40f)
    near(node(graph(r,"g2"),"g2")["value"],100f)
    verifyNull(((Map)extra(r)["energyFlowAccounting"])["unionValue"])
    r=EnerCubixEngine.report(request(["g1","g2"]),records,hs)
    near(((Map)extra(r)["energyFlowAccounting"])["unionValue"],100f)
    overview:=(Map)extra(r)["energyFlowOverview"]
    near(EnerCubixMath.maps(overview["selectionTotals"]).first["knownValue"],100f)
  }

  Void testSubtractionAndNAKeepIndependentReadings()
  {
    rs:=records.add(virtualMeter("minus","subtract-expr","pm")).add(expression("subtract-expr","b-a",["a":"a","b":"b"]))
    r:=EnerCubixEngine.report(request(["minus"]),rs,histories.add(history("pm",20f)))
    near(node(graph(r,"minus"),"minus")["value"],20f)
    verifyEq(graph(r,"minus")["additive"],false)
    verifyNull(((Map)extra(r)["energyFlowAccounting"])["unionValue"])
    hs:=histories
    hs.find |h| {h["pointId"] == "pa"}["intervals"]=[interval(0,null).set("valueType","na").set("quality","na")]
    r=EnerCubixEngine.report(request(["t"]),records,hs);g:=graph(r,"t")
    verifyNull(node(g,"a")["knownValue"]);verifyEq(node(g,"a")["knownQuality"],"na")
    near(node(g,"b")["knownValue"],60f);near(node(g,"t")["knownSubmeter"],60f)
    verifyNull(node(g,"t")["difference"])
    verify(EnerCubixMath.maps(g["links"]).any |l| {l["target"] == "b" && l["value"] == 60f})
  }

  Void testMixedMeasuredAndVirtualObjectsDoNotCreateAFalseGrandTotal()
  {
    r:=EnerCubixEngine.report(request(["t","g1","g2"]),records,histories)
    verifyEq(graphs(r).size,3); near(node(graph(r,"t"),"t")["value"],110f)
    near(node(graph(r,"t"),"t")["difference"],10f)
    near(node(graph(r,"g2"),"g2")["value"],105f)
    account:=(Map)extra(r)["energyFlowAccounting"]
    verifyEq(account["canAdd"],false); verifyNull(account["unionValue"])
    verifyEq(account["basis"],"unavailable")
  }

  Void testNonAdditiveAndNestedRepeatedInputsKeepTheirArithmetic()
  {
    rs:=records
    rs.add(virtualMeter("weighted","weighted-expr","pw")); rs.add(expression("weighted-expr","2*a",["a":"a"]))
    rs.add(virtualMeter("nested","nested-expr","pn")); rs.add(expression("nested-expr","x+y",["x":"g1","y":"g2"]))
    hs:=histories.add(history("pw",80f)).add(history("pn",150f))
    ["weighted","nested"].each |id|
    {
      r:=EnerCubixEngine.report(request([id]),rs,hs); g:=graph(r,id)
      near(node(g,id)["value"],id == "weighted" ? 80f : 150f)
      verifyEq(g["additive"],false)
      verifyNull(((Map)extra(r)["energyFlowAccounting"])["unionValue"])
      verify(!EnerCubixMath.maps(g["links"]).isEmpty)
    }
  }

  Void testSpaceAndOrganizationNodesAreRealHierarchyAndRemainBounded()
  {
    ["space","organization"].each |dimension|
    {
      req:=request([dimension == "space" ? "site" : "org"]); req["dimension"]=dimension
      r:=EnerCubixEngine.report(req,records,histories); g:=graphs(r).first
      verifyEq(g["basis"],dimension)
      verify(EnerCubixMath.maps(g["nodes"]).any |n| {n["nodeType"] == dimension})
      verify(EnerCubixMath.maps(g["links"]).all |l| {l["relationKind"] == "grouping"})
      near(node(g,dimension == "space" ? "site" : "org")["knownValue"],110f)
      root:=node(g,dimension == "space" ? "site" : "org")
      near(root["knownSubmeter"],100f)
      near(node(g,"t")["knownValue"],110f)
      verifyEq(root["balanceQuality"],"overlappingScopes")
      verify(!EnerCubixMath.maps(g["links"]).any |l| {l["source"] == root["id"] && l["target"] == "t"})
      verify(!EnerCubixMath.maps(g["links"]).any |l| {l["target"] == "t"})
      near(node(g,dimension == "space" ? "site" : "org")["submeter"],100f)
      verifyEq(node(g,dimension == "space" ? "site" : "org")["balanceQuality"],"overlappingScopes")
    }
    req:=request(["f1"]); req["dimension"]="space"
    r:=EnerCubixEngine.report(req,records,histories); g:=graph(r,"f1")
    near(node(g,"f1")["knownValue"],40f)
    verify(!EnerCubixMath.maps(g["nodes"]).any |n| {n["nodeId"] == "b" || n["nodeId"] == "t"})
    verifyEq(EnerCubixHistory.pointIds(req,records),["pa"])
  }

  Void testOverlappingSpaceSelectionsUseOneGlobalPhysicalFrontier()
  {
    req:=request(["site","f1"]); req["dimension"]="space"
    r:=EnerCubixEngine.report(req,records,histories)
    verifyEq(graphs(r).size,2)
    a:=(Map)extra(r)["energyFlowAccounting"]
    verifyEq(a["canAdd"],false); near(a["unionValue"],110f)
    verifyEq(a["memberIds"],["t"])
    totals:=EnerCubixMath.maps(((Map)r["summary"])["selectionTotals"])
    near(totals.first["knownValue"],110f)
  }

  Void testLegacyScopeBridgePreservesSelectedObjectsAndTheirView()
  {
    req:=request(Str[,]); req["scopeDimension"]="space"; req["scopeNodeIds"]=["f1"]
    r:=EnerCubixEngine.report(req,records,histories)
    verifyEq(graphs(r).first["objectId"],"f1"); verifyEq(graphs(r).first["basis"],"space")
    verifyEq(EnerCubixHistory.pointIds(EnerCubixEngine.flowScope(req,records),records),["pa"])
  }

  Void testExplicitExcludedObjectsAreAllowedButAutomaticGroupsStillExcludeThem()
  {
    rs:=records; rs.find |m| {m["id"] == "a"}["includeInTotals"]=false
    r:=EnerCubixEngine.report(request(["a"]),rs,histories)
    near(node(graph(r,"a"),"a")["value"],40f)
    r=EnerCubixEngine.report(request(["g1"]),rs,histories)
    near(node(graph(r,"g1"),"a")["value"],40f)
    req:=request(["f1"]); req["dimension"]="space"
    r=EnerCubixEngine.report(req,rs,histories)
    verify(!EnerCubixMath.maps(graphs(r).first["nodes"]).any |n| {n["nodeId"] == "a"})
  }

  Void testMissingAndCyclicReferencesKeepOwnArchiveButNoUnsafeUnion()
  {
    ["absent","g1"].each |ref|
    {
      rs:=records; rs.find |m| {m["id"] == "e1"}["variables"]=["a":ref]
      r:=EnerCubixEngine.report(request(["g1"]),rs,histories)
      near(node(graph(r,"g1"),"g1")["value"],45f)
      verifyEq(graph(r,"g1")["additive"],false)
      verifyNull(((Map)extra(r)["energyFlowAccounting"])["unionValue"])
    }
  }

  Void testHiddenBranchesNeverBecomeAnInventedDifferenceOrDiscloseReferences()
  {
    rs:=records
    hidden:=meter("hidden-sentinel","secret-point","t","f1","o1").set("name","Private name sentinel").set("_comparisonReadable",false)
    rs=EnerCubixEnergyFlow.visible(rs,rs.dup.add(hidden))
    r:=EnerCubixEngine.report(request(["t"]),rs,histories)
    g:=graph(r,"t")
    near(node(g,"t")["value"],110f); verifyNull(node(g,"t")["difference"])
    verifyEq(node(g,"t")["lossEligible"],false)
    verifyNull(((Map)extra(r)["energyFlowAccounting"])["unionValue"])
    text:=r.toStr
    verify(!text.contains("hidden-sentinel") && !text.contains("Private name sentinel") && !text.contains("secret-point"))
    verify(EnerCubixMath.maps(g["links"]).any |l| {l["target"] == "a"})
  }

  Void testDifferentPhysicalIdsWithTheSameStoredPointShareOneContribution()
  {
    rs:=records;rs.add(meter("a-alias","pa","t","f1","o1"))
    rs.find |r| {r["id"] == "e2"}["formula"]="a"
    rs.find |r| {r["id"] == "e2"}["variables"]=["a":"a-alias"]
    r:=EnerCubixEngine.report(request(["g1","g2"]),rs,histories)
    account:=(Map)extra(r)["energyFlowAccounting"]
    near(account["unionValue"],40f);verifyEq(account["sharedMemberIds"],["a"])
    verifyEq(account["canAdd"],false)
    near(node(graph(r,"g1"),"g1")["value"],45f)
    near(node(graph(r,"g2"),"g2")["value"],105f)
  }

  Void testUnsafeCurrentTopologyWithholdsOnlyDifferenceAndLossEligibility()
  {
    [false,true].each |broken|
    {
      rs:=records
      if (broken) rs.find |m| {m["id"] == "t"}["meterParentId"]="missing-parent"
      else rs.add(meter("unlinked","pu",null,"site","org"))
      r:=EnerCubixEngine.report(request(["t"]),rs,histories)
      g:=graph(r,"t")
      near(node(g,"t")["value"],110f);verifyNull(node(g,"t")["difference"])
      verifyEq(node(g,"t")["lossEligible"],false)
      verify(EnerCubixMath.maps(g["links"]).any |l| {l["target"] == "a" && l["value"] == 40f})
      verify(!EnerCubixMath.maps(g["nodes"]).any |n| {n["nodeType"] == "difference"})
    }
  }

  private Map extra(Str:Obj? r) {(Map)r["extra"]}
  private [Str:Obj?][] graphs(Str:Obj? r) {EnerCubixMath.maps(extra(r)["energyFlowGraphs"])}
  private Str:Obj? graph(Str:Obj? r,Str id) {graphs(r).find |g| {g["objectId"] == id} ?: throw Err("Missing object graph: $id")}
  private Str:Obj? node(Str:Obj? g,Str id) {EnerCubixMath.maps(g["nodes"]).find |n| {n["nodeId"] == id} ?: throw Err("Missing node: $id")}
  private Str:Obj? request(Str[] ids) {["kind":"energyFlow","dimension":"metering","nodeIds":ids,"categoryId":"e","from":at(0),"to":at(1),"asOf":at(1),"period":"hour","metric":"energy","perArea":false,"tz":"UTC"]}
  private [Str:Obj?][] records()
  {
    return [["id":"e","kind":"category","name":"Electric","unit":"kWh"],
      ["id":"site","kind":"space","name":"Site"],["id":"f1","kind":"space","name":"Floor1","parentId":"site"],["id":"f2","kind":"space","name":"Floor2","parentId":"site"],
      ["id":"org","kind":"organization","name":"Organization"],["id":"o1","kind":"organization","name":"Department1","parentId":"org"],["id":"o2","kind":"organization","name":"Department2","parentId":"org"],
      meter("t","pt",null,"site","org").set("kind","totalMeter"),meter("a","pa","t","f1","o1"),meter("b","pb","t","f2","o2"),
      virtualMeter("g1","e1","pg1"),virtualMeter("g2","e2","pg2"),expression("e1","a",["a":"a"]),expression("e2","a+b",["a":"a","b":"b"])]
  }
  private Str:Obj? meter(Str id,Str point,Str? parent,Str space,Str org) {["id":id,"kind":"meter","name":id,"pointId":point,"meterParentId":parent,"spaceId":space,"organizationId":org,"categoryId":"e","unit":"kWh"]}
  private Str:Obj? virtualMeter(Str id,Str expr,Str point) {["id":id,"kind":"totalMeter","name":id,"expressionId":expr,"historyPointId":point,"categoryId":"e","unit":"kWh","includeInTotals":false]}
  private Str:Obj? expression(Str id,Str formula,Str:Str vars) {["id":id,"kind":"expression","formula":formula,"variables":vars]}
  private [Str:Obj?][] histories() {[history("pt",110f),history("pa",40f),history("pb",60f),history("pg1",45f),history("pg2",105f)]}
  private Str:Obj? history(Str id,Float value) {["pointId":id,"unit":"kWh","mode":"interval","intervals":[interval(0,value)]]}
  private Str:Obj? interval(Int hour,Float? value) {["from":at(hour),"to":at(hour+1),"value":value,"valueType":value == null ? "null" : "number","quality":value == null ? "missing" : "cleaned"]}
  private Str at(Int hour) {(DateTime.fromIso("2026-10-19T00:00:00Z")+Duration(hour*1hr.ticks)).toIso}
  private Void near(Obj? actual,Float expected) {verifyNotNull(actual); verify((((Float)actual)-expected).abs < 0.000001f)}
}

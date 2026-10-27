class EnerCubixEndUseTest : Test
{
  Void testUtilityCombinesOwnMetersByUtility()
  {
    r:=run("utility",["a","b","c"]); shares:=extra(r,"utilityShares")
    verifyEq(shares.size,2)
    lighting:=shares.find |s| {s["utilityId"] == "lighting"}
    verifyEq(lighting["name"],"Lighting"); verifyEq(lighting["value"],300f)
    verifyEq(lighting["meterIds"],["a","b"]); verifyEq(lighting["percentage"],50f)
    verifyEq(shares.find |s| {s["utilityId"] == "power"}["percentage"],50f)
    verifyEq(extra(r,"utilityMembers").size,3)
    verifyEq(EnerCubixMath.maps(((Map)r["summary"])["selectionTotals"]).first["value"],600f)
  }

  Void testMasterOwnPrimaryAndCanonicalDedup()
  {
    rs:=records; rs.add(meter("alias","pa","main","lighting").set("canonicalId","a"))
    r:=EnerCubixEngine.report(request("utility",["main","a","alias"]),rs,histories)
    verifyEq(extra(r,"utilityMembers").map |m->Str| {m["nodeId"].toStr}.sort,["a","main"])
    verifyEq(extra(r,"utilityShares").find |s| {s["utilityId"] == "lighting"}["percentageBasis"],"overlappingScopes")
    verifyNull(EnerCubixMath.maps(((Map)r["summary"])["selectionTotals"]).first["value"])
    only:=run("utility",["main"])
    verifyEq(extra(only,"utilityShares").size,1)
    verifyEq(extra(only,"utilityShares").first["value"],1000f)
    verifyEq(EnerCubixHistory.pointIds(request("utility",["main"]),records),["pm"])
  }

  Void testScopeUsesCommonMeterSetAtAnyDepthAndDirectEveryView()
  {
    ["space","organization"].each |dimension|
    {
      req:=request("utility",["deep"]); req["dimension"]=dimension
      rs:=records
      rs.add(["id":"root","kind":dimension,"name":"Root"])
      rs.add(["id":"middle","kind":dimension,"name":"Middle","parentId":"root"])
      rs.add(["id":"deep","kind":dimension,"name":"Deep","parentId":"middle"])
      rs.findAll |m| {["a","b","c"].contains(m["id"])}.each |m| {m[dimension == "space" ? "spaceId" : "organizationId"]="deep"}
      report:=EnerCubixEngine.report(req,rs,histories)
      verifyEq(extra(report,"utilityMembers").map |m->Str| {m["nodeId"].toStr}.sort,["a","b","c"])
      verifyEq(EnerCubixMath.maps(((Map)report["summary"])["selectionTotals"]).first["value"],600f)
      req["nodeIds"]=["a"]
      verifyEq(extra(EnerCubixEngine.report(req,rs,histories),"utilityShares").first["value"],100f)
    }
  }

  Void testUtilityMissingZeroNegativeAndPerArea()
  {
    hs:=histories.findAll |h| {h["pointId"] != "pb"}
    r:=EnerCubixEngine.report(request("utility",["a","b","c"]),records,hs)
    light:=extra(r,"utilityShares").find |s| {s["utilityId"] == "lighting"}
    verifyNull(light["value"]); verifyEq(light["knownValue"],100f); verifyEq(light["knownPercentage"],25f)
    verifyEq(extra(r,"utilityMembers").find |m| {m["nodeId"] == "b"}["coverage"],0f)
    hs=histories.map |h->[Str:Obj?]| {history(h["pointId"].toStr,0f)}
    r=EnerCubixEngine.report(request("utility",["a","b"]),records,hs)
    verifyEq(extra(r,"utilityShares").first["percentageBasis"],"zeroKnownTotal"); verifyNull(extra(r,"utilityShares").first["percentage"])
    hs=histories; hs[1]=history("pa",-10f)
    r=EnerCubixEngine.report(request("utility",["a","c"]),records,hs)
    verify(extra(r,"utilityShares").all |s| {s["percentage"] == null && s["percentageBasis"] == "negativeConsumption"})
    req:=request("utility",["a","c"]); req["perArea"]=true
    r=EnerCubixEngine.report(req,records,histories)
    verify(extra(r,"utilityShares").all |s| {s["percentage"] == null && s["percentageBasis"] == "areaNormalized"})
  }

  Void testEndUseFlowRootUtilityMembersAndResidual()
  {
    r:=run("energyFlow",["main"]); graph:=extra(r,"energyFlowGraphs").first
    verifyEq(graph["basis"],"endUse")
    verifyEq(graph["contributionMemberIds"],["a","b","c"])
    ns:=EnerCubixMath.maps(graph["nodes"])
    verifyEq(ns.find |n| {n["nodeId"] == "main"}["value"],1000f)
    verifyEq(ns.find |n| {n["nodeId"] == "main"}["difference"],400f)
    verifyEq(ns.find |n| {n["nodeType"] == "utility" && n["utilityId"] == "lighting"}["value"],300f)
    verifyEq(ns.find |n| {n["nodeType"] == "difference"}["value"],400f)
    verifyEq(ns.findAll |n| {n["nodeType"] == "meter"}.size,4)
    verify(EnerCubixMath.maps(graph["links"]).all |l| {l["relationKind"] == "classification"})
    verifyEq(EnerCubixHistory.pointIds(request("energyFlow",["main"]),records),["pa","pb","pc","pm"])
    verifyEq(((Map)((Map)r["extra"])["energyFlowAccounting"])["unionValue"],600f)
  }

  Void testEndUseMissingNoResidualNegativeNoNegativeFlow()
  {
    hs:=histories.findAll |h| {h["pointId"] != "pb"}
    graph:=extra(EnerCubixEngine.report(request("energyFlow",["main"]),records,hs),"energyFlowGraphs").first
    ns:=EnerCubixMath.maps(graph["nodes"])
    verifyNull(ns.first["difference"]); verify(!ns.any |n| {n["nodeType"] == "difference"})
    verifyEq(ns.find |n| {n["nodeType"] == "utility" && n["utilityId"] == "lighting"}["knownValue"],100f)
    hs=histories; hs[0]=history("pm",50f)
    graph=extra(EnerCubixEngine.report(request("energyFlow",["main"]),records,hs),"energyFlowGraphs").first
    verifyEq(EnerCubixMath.maps(graph["nodes"]).first["difference"],-550f)
    verify(EnerCubixMath.maps(graph["links"]).all |l| {(Float)l["value"] > 0f})
    verify(!EnerCubixMath.maps(graph["nodes"]).any |n| {n["nodeType"] == "difference"})
  }

  Void testEndUseNoMembersSharedRootsAndFormulaSafety()
  {
    graph:=extra(run("energyFlow",["a"]),"energyFlowGraphs").first
    verifyEq(EnerCubixMath.maps(graph["nodes"]).size,1); verifyEq(graph["boundaryQuality"],"comparisonEmpty")
    rs:=records; rs.add(meter("virtual","pv",null,null,"totalMeter").set("expressionId","expr"))
    rs.add(["id":"expr","kind":"expression","name":"Formula","formula":"A+B+C","variables":["A":"a","B":"b","C":"c"]])
    req:=request("energyFlow",["virtual"])
    graph=extra(EnerCubixEngine.report(req,rs,histories.add(history("pv",700f))),"energyFlowGraphs").first
    verifyEq(EnerCubixMath.maps(graph["nodes"]).first["value"],700f)
    verifyEq(EnerCubixMath.maps(graph["nodes"]).first["balanceMode"],"consistency")
    verify(!EnerCubixMath.maps(graph["nodes"]).any |n| {n["nodeType"] == "difference"})
    req["nodeIds"]=["main","virtual"]
    r:=EnerCubixEngine.report(req,rs,histories)
    verifyEq(((Map)((Map)r["extra"])["energyFlowAccounting"])["basis"],"unavailable")
    req=request("energyFlow",["main"]); req["flowMode"]="bad"
    verifyErr(ArgErr#) {EnerCubixEngine.report(req,records,histories)}
    req=request("energyFlow",["scope"]); req["dimension"]="space"; rs=records;rs.add(["id":"scope","kind":"space","name":"Scope"])
    verifyErr(ArgErr#) {EnerCubixEngine.report(req,rs,histories)}
  }

  Void testCrossReportScopeSetAndMixedEnergyUnits()
  {
    rs:=records; rs.add(["id":"scope","kind":"space","name":"Scope"])
    rs.findAll |r| {["a","b","c"].contains(r["id"])}.each |r| {r["spaceId"]="scope"}
    ["utility","profile","ranking","proportion"].each |kind|
    {
      req:=request(kind,["scope"]);req["dimension"]="space"
      total:=EnerCubixMath.maps(((Map)EnerCubixEngine.report(req,rs,histories)["summary"])["selectionTotals"]).first
      verifyEq(total["value"],600f);verifyEq(total["meterIds"],["a","b","c"])
    }
    rs.add(["id":"water","kind":"category","name":"Water","unit":"m³"])
    rs.add(meter("waterMeter","pw",null,null).set("categoryId","water").set("unit","m³"))
    hs:=histories.add(history("pw",8f).set("unit","m³"))
    r:=EnerCubixEngine.report(request("utility",["a","waterMeter"]),rs,hs)
    totals:=EnerCubixMath.maps(((Map)r["summary"])["selectionTotals"])
    verifyEq(totals.size,2);verifyEq(totals.find |t| {t["categoryId"] == "water"}["value"],8f)
    verifyEq(extra(r,"utilityShares").find |t| {t["categoryId"] == "water"}["utilityId"],"")
  }

  Void testEndUseBoundaryStopsAtPhysicalMeterAndExactResidual()
  {
    rs:=records;rs.add(meter("grandchild","pg","a","power"))
    hs:=histories;hs[2]=history("pb",300f);hs[3]=history("pc",500f);hs.add(history("pg",90f))
    graph:=extra(EnerCubixEngine.report(request("energyFlow",["main"]),rs,hs),"energyFlowGraphs").first
    ns:=EnerCubixMath.maps(graph["nodes"])
    verifyEq(ns.first["difference"],100f)
    verifyEq(ns.find |n| {n["nodeType"] == "utility" && n["utilityId"] == "lighting"}["value"],400f)
    verifyEq(ns.find |n| {n["nodeType"] == "utility" && n["utilityId"] == "power"}["value"],500f)
    verify(!ns.any |n| {n["nodeId"] == "grandchild"})
    rootLinks:=EnerCubixMath.maps(graph["links"]).findAll |l| {l["source"] == "main"}
    verifyEq(rootLinks.size,3)
    verifyEq(rootLinks.reduce(0f) |Float sum,Str:Obj? link->Float| {sum+(Float)link["value"]},1000f)
    verifyEq(EnerCubixHistory.pointIds(request("energyFlow",["main"]),rs),["pa","pb","pc","pm"])
    req:=request("energyFlow",["main"]);req.remove("flowMode")
    old:=EnerCubixEngine.report(req,rs,hs);req["flowMode"]="relations"
    verifyEq(EnerCubixEngine.report(req,rs,hs),old)
  }

  Void testEndUseSourceOverlapAndHiddenPrimaryAreUnavailable()
  {
    rs:=records
    rs.add(meter("other","po",null,null,"totalMeter")).add(meter("shared","pa","other","power"))
    hs:=histories.add(history("po",500f))
    r:=EnerCubixEngine.report(request("energyFlow",["main","other"]),rs,hs)
    verifyEq(((Map)((Map)r["extra"])["energyFlowAccounting"])["basis"],"unavailable")
    rs=records;rs.find |m| {m["id"] == "main"}["_comparisonPointReadable"]=false
    r=EnerCubixEngine.report(request("energyFlow",["main"]),rs,histories)
    root:=EnerCubixMath.maps(extra(r,"energyFlowGraphs").first["nodes"]).first
    verifyNull(root["value"]);verifyEq(root["quality"],"forbidden");verifyNull(root["difference"])
    overview:=(Map)((Map)r["extra"])["energyFlowOverview"]
    own:=EnerCubixMath.maps(overview["rows"]).find |m| {m["nodeId"] == "main"}
    verifyNull(own["value"]);verifyEq(own["quality"],"forbidden")
  }

  Void testUtilityPerAreaPreservesOwnValuesWithoutAddingIntensities()
  {
    req:=request("utility",["a","b"]);req["perArea"]=true
    r:=EnerCubixEngine.report(req,records,histories)
    verifyNull(extra(r,"utilityShares").first["value"])
    verifyEq(extra(r,"utilityShares").first["percentageBasis"],"areaNormalized")
    verifyNull(EnerCubixMath.maps(((Map)r["summary"])["selectionTotals"]).first["value"])
    verifyEq(extra(r,"utilityMembers").find |m| {m["nodeId"] == "a"}["value"],10f)
    verifyEq(extra(r,"utilityMembers").find |m| {m["nodeId"] == "b"}["value"],20f)
  }

  Void testTemplateFlowModeEnum()
  {
    template:=Str:Obj?["id":"template","kind":"template","name":"Flow","request":request("energyFlow",["main"])]
    EnerCubixConfig.validate(template,records)
    ((Map)template["request"])["flowMode"]="invalid"
    verifyErr(ArgErr#) {EnerCubixConfig.validate(template,records)}
    ((Map)template["request"]).remove("flowMode")
    EnerCubixConfig.validate(template,records)
  }

  Void testUtilityCostUsesCompleteAmountsAndHistoryPlanUsesSameOwnSet()
  {
    rs:=records
    rs.add(["id":"tariff","kind":"tariff","name":"Tariff","categoryId":"electric","isDefault":true,"mode":"flat","rate":2f])
    req:=request("utility",["a","c"]);req["metric"]="cost"
    shares:=extra(EnerCubixEngine.report(req,rs,histories),"utilityShares")
    verifyEq(shares.find |s| {s["utilityId"] == "lighting"}["percentage"],25f)
    verify(shares.all |s| {!s.containsKey("knownPercentage")})
    group:=Str:Obj?["id":"g","kind":"group","name":"Group"]
    rs=records.add(group);rs.findAll |m| {["main","a","b","c"].contains(m["id"])}.each |m| {m["parentId"]="g"}
    req=request("utility",["g"]);req.remove("dimension")
    verifyEq(EnerCubixHistory.pointIds(req,rs),["pm"])
  }

  Void testEndUseExplicitBoundaryIgnoresAutomaticTotalExclusions()
  {
    rs:=records
    rs.findAll |r| {["meter","totalMeter"].contains(r["kind"])}.each |r| {r["includeInTotals"]=false}
    graph:=extra(EnerCubixEngine.report(request("energyFlow",["main"]),rs,histories),"energyFlowGraphs").first
    verifyEq(graph["contributionMemberIds"],["a","b","c"])
    root:=EnerCubixMath.maps(graph["nodes"]).first
    verifyEq(root["balanceMode"],"independent")
    verifyEq(root["lossEligible"],true)
    verifyEq(EnerCubixMath.maps(graph["nodes"]).find |n| {n["nodeType"] == "difference"}["value"],400f)
  }

  Void testUtilityPrimaryProvenanceOverlapAndNaStayExplicit()
  {
    hs:=histories
    hs.find |h| {h["pointId"] == "pa"}["sourceIds"]=["sharedSource"]
    hs.find |h| {h["pointId"] == "pb"}["sourceIds"]=["sharedSource"]
    r:=EnerCubixEngine.report(request("utility",["a","b"]),records,hs)
    share:=extra(r,"utilityShares").first
    verifyNull(share["value"]);verifyNull(share["knownValue"]);verifyEq(share["percentageBasis"],"overlappingScopes")
    verifyEq(extra(r,"utilityMembers").map |m->Float| {(Float)m["value"]},[100f,200f])
    hs=histories
    hs.find |h| {h["pointId"] == "pa"}["samples"]=[["ts":"2026-01-01T00:00:00Z","value":null,"quality":"na","valueType":"na"]]
    r=EnerCubixEngine.report(request("utility",["a"]),records,hs)
    verifyEq(extra(r,"utilityMembers").first["valueType"],"na");verifyEq(extra(r,"utilityShares").first["knownQuality"],"na")
    verify(((Str[])run("energyFlow",["a"])["warnings"]).contains("endUseBoundaryEmpty"))
  }

  Void testEndUseOverdrawnBranchesHaveNoWeightedRibbons()
  {
    hs:=[history("pm",500f),history("pa",400f),history("pb",200f),history("pc",0f)]
    graph:=extra(EnerCubixEngine.report(request("energyFlow",["main"]),records,hs),"energyFlowGraphs").first
    verify(EnerCubixMath.maps(graph["links"]).isEmpty)
    ns:=EnerCubixMath.maps(graph["nodes"])
    verifyEq(ns.first["value"],500f);verifyEq(ns.first["difference"],-100f);verifyEq(ns.first["balanceQuality"],"negativeBalance")
    verifyEq(ns.find |n| {n["nodeId"] == "a"}["value"],400f)
    verify(!ns.any |n| {n["nodeType"] == "difference"})
  }

  Void testEndUseMissingRootHasNoWeightedRibbons()
  {
    hs:=histories.findAll |h| {h["pointId"] != "pm"}
    graph:=extra(EnerCubixEngine.report(request("energyFlow",["main"]),records,hs),"energyFlowGraphs").first
    verify(EnerCubixMath.maps(graph["links"]).isEmpty)
    ns:=EnerCubixMath.maps(graph["nodes"])
    verifyNull(ns.first["value"]);verifyEq(ns.find |n| {n["nodeId"] == "a"}["knownValue"],100f)
    verify(!ns.any |n| {n["nodeType"] == "difference"})
  }

  Void testEndUseOverlappingOrNonadditiveBoundaryHasNoWeightedRibbons()
  {
    rs:=records;rs.find |r| {r["id"] == "b"}["utilityId"]="power"
    hs:=histories;hs[1]["sourceIds"]=["shared"];hs[2]["sourceIds"]=["shared"]
    graph:=extra(EnerCubixEngine.report(request("energyFlow",["main"]),rs,hs),"energyFlowGraphs").first
    verify(EnerCubixMath.maps(graph["links"]).isEmpty);verifyEq(graph["boundaryQuality"],"overlappingScopes")
    verifyEq(EnerCubixMath.maps(graph["nodes"]).find |n| {n["nodeId"] == "a"}["value"],100f)
    rs=records;rs.find |r| {r["id"] == "a"}["expressionId"]="expr"
    rs.add(["id":"expr","kind":"expression","name":"Nonadditive","formula":"X*2","variables":["X":"b"]])
    graph=extra(EnerCubixEngine.report(request("energyFlow",["main"]),rs,histories),"energyFlowGraphs").first
    verify(EnerCubixMath.maps(graph["links"]).isEmpty);verify(graph["boundaryQuality"] != "ok")
    verifyEq(EnerCubixMath.maps(graph["nodes"]).find |n| {n["nodeId"] == "a"}["value"],100f)
  }

  Void testEndUseNegativeMemberKeepsSignedReadingWithoutWeightedRibbons()
  {
    hs:=histories
    hs[2]["intervals"]=[["from":"2026-01-01T00:00:00Z","to":"2026-01-01T01:00:00Z","value":-20f,"quality":"ok"]]
    graph:=extra(EnerCubixEngine.report(request("energyFlow",["main"]),records,hs),"energyFlowGraphs").first
    verify(EnerCubixMath.maps(graph["links"]).isEmpty)
    ns:=EnerCubixMath.maps(graph["nodes"])
    verifyEq(ns.find |n| {n["nodeId"] == "b"}["value"],-20f)
    verifyEq(ns.find |n| {n["nodeId"] == "b"}["knownValue"],-20f)
    verifyEq(ns.find |n| {n["nodeId"] == "a"}["value"],100f)
    verify(!ns.any |n| {n["nodeType"] == "difference"})
    verifyEq(ns.first["lossEligible"],false)
  }

  Void testEndUsePartialKnownReadingsNeverCreateResidual()
  {
    req:=request("energyFlow",["main"]);req["to"]="2026-01-01T02:00:00Z"
    graph:=extra(EnerCubixEngine.report(req,records,histories),"energyFlowGraphs").first
    ns:=EnerCubixMath.maps(graph["nodes"])
    verifyNull(ns.first["value"]);verifyEq(ns.first["knownValue"],1000f)
    verifyEq(ns.find |n| {n["nodeId"] == "a"}["knownValue"],100f)
    verifyEq(ns.first["lossEligible"],false)
    verify(!ns.any |n| {n["nodeType"] == "difference"})
  }

  private Str:Obj? run(Str kind,Str[] ids) {EnerCubixEngine.report(request(kind,ids),records,histories)}
  private [Str:Obj?][] extra(Str:Obj? r,Str key) {EnerCubixMath.maps(((Map)r["extra"])[key])}
  private Str:Obj? request(Str kind,Str[] ids)
  { ["kind":kind,"dimension":"metering","flowMode":"endUse","nodeIds":ids,"categoryId":"electric","from":"2026-01-01T00:00:00Z","to":"2026-01-01T01:00:00Z","asOf":"2026-01-02T00:00:00Z","period":"hour","metric":"energy","tz":"UTC"] }
  private [Str:Obj?][] records()
  { [[Str:Obj?]["id":"electric","kind":"category","name":"Electric","unit":"kWh"],[Str:Obj?]["id":"lighting","kind":"utility","name":"Lighting"],[Str:Obj?]["id":"power","kind":"utility","name":"Power"],meter("main","pm",null,null,"totalMeter"),meter("a","pa","main","lighting"),meter("b","pb","main","lighting"),meter("c","pc","main","power")] }
  private Str:Obj? meter(Str id,Str point,Str? parent,Str? utility,Str kind:="meter")
  { ["id":id,"kind":kind,"name":id,"pointId":point,"meterParentId":parent,"utilityId":utility,"categoryId":"electric","unit":"kWh","area":10f] }
  private [Str:Obj?][] histories() {[history("pm",1000f),history("pa",100f),history("pb",200f),history("pc",300f)]}
  private Str:Obj? history(Str point,Float val)
  { ["pointId":point,"unit":"kWh","mode":"interval","samples":[[Str:Obj?]["ts":"2026-01-01T00:00:00Z","value":val]]] }
}

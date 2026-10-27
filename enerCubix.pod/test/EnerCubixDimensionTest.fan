class EnerCubixDimensionTest : Test
{
  Void testFloorScopeUsesOnlyCoveredMeters()
  {
    rs:=base
    hs:=histories
    r:=run(rs,hs,"space",["floor"])
    near(value(r),30f)
    verifyEq(points(r).first["sourceIds"],["pf"])
    r=run(rs,hs,"space",["building"])
    near(value(r),100f)
    verifyEq(points(r).first["sourceIds"],["pm"])
  }

  Void testUnconfirmedOverlapKeepsDetailsAndNullTotal()
  {
    rs:=base
    rs.find |r| { r["id"] == "floorMeter" }.remove("meterParentId")
    r:=run(rs,histories,"space",["building"])
    verifyNull(value(r)); verifyEq(points(r).first["quality"],"topologyIncomplete")
    extra:=(Str:Obj?)r["extra"]
    details:=([Str:Obj?][])extra["details"]
    verifyEq(details.size,2)
    near((Float?)details.find |d| { d["nodeId"] == "master" }["value"],100f)
    near((Float?)details.find |d| { d["nodeId"] == "floorMeter" }["value"],30f)
    verify(!((Str[])r["warnings"]).isEmpty)
  }

  Void testOrganizationAttributionAndSharedMaster()
  {
    rs:=base
    r:=run(rs,histories,"organization",["tenant"])
    near(value(r),30f)
    // A whole-building reading owned by A also covers a confirmed B branch.
    rs.find |m| { m["id"] == "master" }["organizationId"]="tenant"
    rs.find |m| { m["id"] == "floorMeter" }["organizationId"]="other"
    r=run(rs,histories,"organization",["tenant"])
    verifyNull(value(r)); verifyEq(points(r).first["quality"],"accountingIncomplete")
    r=run(rs,histories,"organization",["master"])
    verifyNull(value(r)); verifyEq(points(r).first["quality"],"accountingIncomplete")
    details:=([Str:Obj?][])((Str:Obj?)r["extra"])["details"]
    near((Float?)details.first["value"],100f)
    r=run(rs,histories,"organization",["company"])
    near(value(r),100f)
  }

  Void testCanonicalAliasesOnlyCollapseInNewViews()
  {
    rs:=base
    alias:=rs.find |m| { m["id"] == "floorMeter" }.dup
    alias["id"]="alias"; alias["canonicalId"]="floorMeter"; alias["parentId"]="legacy"
    rs.add(alias)
    near(value(run(rs,histories,"space",["floor"])),30f)
    near(value(run(rs,histories,"metering",["alias"])),30f)
    req:=request("space",["floorMeter","alias"])
    r:=EnerCubixEngine.report(req,rs,histories)
    verifyEq(((List)r["series"]).size,1)
    req=request("legacy",["legacy"])
    r=EnerCubixEngine.report(req,rs,histories)
    near(value(r),60f)
    req.remove("dimension")
    verifyEq(EnerCubixEngine.report(req,rs,histories),r)
  }

  Void testLeakUsesExplicitDirectMeterChildren()
  {
    rs:=base
    leaf:=meter("leaf","pl","floor","floorMeter","tenant")
    rs.add(leaf)
    hs:=histories.add(history("pl",10f))
    req:=request("metering",["master"]); req["kind"]="leak"
    r:=EnerCubixEngine.report(req,rs,hs)
    near(value(r),70f)
    rows:=([Str:Obj?][])r["rows"]
    near((Float?)rows.first["total"],100f)
    near((Float?)rows.first["submeter"],30f)
    req["nodeIds"]=["floorMeter"]
    near(value(EnerCubixEngine.report(req,rs,hs)),20f)
  }

  Void testUtilityScopeAndUnknownUsage()
  {
    rs:=base
    req:=request("space",["floor"]); req["kind"]="utility"
    r:=EnerCubixEngine.report(req,rs,histories)
    near(value(r),30f)
    verify(((Str)(([Str:Obj?][])r["series"]).first["name"]).contains("未指定分项"))
    room:=[Str:Obj?]["id":"room","kind":"space","name":"room","parentId":"floor"]
    rs.add(room); req["nodeIds"]=["room"]
    verifyErr(ArgErr#) { EnerCubixEngine.report(req,rs,histories) }
    req=request("organization",["tenant"]); req["kind"]="utility"
    near(value(EnerCubixEngine.report(req,rs,histories)),30f)
  }

  Void testSensorsAndVirtualExclusionsRemain()
  {
    rs:=base
    sensor:=meter("sensor","ps","floor",null,"tenant"); sensor["kind"]="sensor"
    computed:=meter("virtual","pv","floor",null,"tenant"); computed["expressionId"]="expr"
    rs.add(sensor).add(computed).add(["id":"expr","kind":"expression","formula":"a * 2","variables":["a":"floorMeter"]])
    near(value(run(rs,histories,"space",["floor"])),30f)
    computed["includeInTotals"]=true
    near(value(run(rs,histories.dup.add(["pointId":"pv","unit":"kWh","mode":"interval","samples":[[Str:Obj?]["ts":"2026-01-01T00:00:00Z","value":60f]]]),"space",["floor"])),90f)
  }

  Void testUtilityUsesMeasuredBranchesAndWarnsAboutCoverage()
  {
    rs:=base
    rs.find |m| { m["id"] == "floorMeter" }["utilityId"]="lighting"
    rs.add(["id":"lighting","kind":"utility","name":"照明"])
    req:=request("space",["building"]); req["kind"]="utility"
    r:=EnerCubixEngine.report(req,rs,histories)
    ss:=([Str:Obj?][])r["series"]
    verifyEq(ss.size,1); verify(ss.first["name"].toStr.contains("照明")); near(value(r),30f)
    verify(((Str[])r["warnings"]).any |w| { w.contains("分项覆盖不完整") })
    totals:=([Str:Obj?][])((Str:Obj?)r["extra"])["scopeTotals"]
    near((Float?)totals.first["value"],100f)
  }

  Void testDashboardUnionAndHistoryDependencies()
  {
    req:=request("space",["building","floor"]); req["kind"]="dashboard"
    r:=EnerCubixEngine.report(req,base,histories)
    totals:=([Str:Obj?][])((Str:Obj?)r["extra"])["grandTotals"]
    near((Float?)totals.first["value"],100f)
    req["nodeIds"]=["floor"]
    plan:=EnerCubixDimension.dependencies(req,base)
    verifyEq(plan["points"],["pf"])
    verify(((Str[])plan["nodes"]).contains("floorMeter"))
    req=request("metering",["master"]); req["kind"]="leak"
    verifyEq(EnerCubixDimension.dependencies(req,base)["points"],["pf","pm"])
  }

  Void testSiblingBranchesAndUnlinkedLeak()
  {
    rs:=base
    rs.add(meter("sibling","pb","floor","master","tenant"))
    hs:=histories.add(history("pb",5f))
    near(value(run(rs,hs,"space",["floor"])),35f)
    req:=request("metering",["master"]); req["kind"]="leak"
    near(value(EnerCubixEngine.report(req,rs,hs)),65f)
    rs.find |m| { m["id"] == "sibling" }.remove("meterParentId")
    r:=EnerCubixEngine.report(req,rs,hs)
    verifyNull(value(r)); verifyEq(points(r).first["quality"],"topologyIncomplete")
  }

  Void testDimensionalMetricAndScopeValidation()
  {
    rs:=base
    rs.add(["id":"price","kind":"tariff","categoryId":"electric","mode":"flat","rate":2f,"isDefault":true])
    req:=request("space",["building"]); req["metric"]="cost"
    near(value(EnerCubixEngine.report(req,rs,histories)),200f)
    req["dimension"]="unknown"
    verifyErr(ArgErr#) { EnerCubixEngine.report(req,rs,histories) }
    req["dimension"]="space"; req["nodeIds"]=["company"]
    verifyErr(ArgErr#) { EnerCubixEngine.report(req,rs,histories) }
  }

  Void testEmptyDimensionHasNoLegacyDashboardFallback()
  {
    rs:=[meter("unassigned","pf","unknown",null,null)]
    req:=request("space",Str[,]); req["kind"]="dashboard"
    r:=EnerCubixEngine.report(req,rs,histories)
    verify(((List)r["series"]).isEmpty)
    verifyEq(EnerCubixDimension.dependencies(req,rs)["points"],Str[,])
  }

  Void testPerAreaDashboardUsesMaximalScopeArea()
  {
    rs:=base
    rs.find |r| { r["id"] == "building" }["area"]=1000f
    rs.find |r| { r["id"] == "floor" }["area"]=300f
    req:=request("space",["building","floor"]); req["kind"]="dashboard"; req["perArea"]=true
    r:=EnerCubixEngine.report(req,rs,histories)
    total:=grandTotal(r)
    near((Float?)total["value"],0.1f)
    verifyEq(total["unit"],"kWh/m²")
    verifyEq(total["sourceIds"],["pm"])
  }

  Void testPerAreaDashboardUsesDisjointScopeAreas()
  {
    rs:=base
    rs.find |r| { r["id"] == "floor" }["area"]=300f
    rs.add(["id":"annex","kind":"space","name":"annex","area":200f])
    rs.add(meter("annexMeter","pa","annex",null,"other"))
    hs:=histories.add(history("pa",20f))
    req:=request("space",["floor","annex"]); req["kind"]="dashboard"; req["perArea"]=true
    total:=grandTotal(EnerCubixEngine.report(req,rs,hs))
    near((Float?)total["value"],0.1f)
    verifyEq(total["quality"],"ok")
  }

  Void testPerAreaDashboardMissingAndAmbiguousAreas()
  {
    rs:=base
    rs.find |r| { r["id"] == "building" }["area"]=1000f
    req:=request("space",["floor"]); req["kind"]="dashboard"; req["perArea"]=true
    r:=EnerCubixEngine.report(req,rs,histories)
    total:=grandTotal(r)
    verifyNull(total["value"]); verifyEq(total["quality"],"missingArea")
    verify(!((Str[])r["warnings"]).isEmpty)
    rs.find |m| { m["id"] == "floor" }["area"]=300f
    req["nodeIds"]=["floor","master"]
    r=EnerCubixEngine.report(req,rs,histories); total=grandTotal(r)
    verifyNull(total["value"]); verifyEq(total["quality"],"ambiguousArea")
    verify(((Str[])r["warnings"]).any |w| { w.contains("ambiguousArea") })
    req["nodeIds"]=["floor","floorMeter"]
    near((Float?)grandTotal(EnerCubixEngine.report(req,rs,histories))["value"],0.1f)
  }

  Void testPerAreaDashboardMeterFrontierAndLegacy()
  {
    rs:=base
    rs.find |r| { r["id"] == "master" }["area"]=1000f
    rs.find |r| { r["id"] == "floorMeter" }["area"]=300f
    req:=request("metering",["master","floorMeter"]); req["kind"]="dashboard"; req["perArea"]=true
    near((Float?)grandTotal(EnerCubixEngine.report(req,rs,histories))["value"],0.1f)
    req["dimension"]="legacy"
    near((Float?)grandTotal(EnerCubixEngine.report(req,rs,histories))["value"],0.1f)
    rs.find |m| { m["id"] == "master" }["area"]=0f
    req["dimension"]="metering"
    total:=grandTotal(EnerCubixEngine.report(req,rs,histories))
    verifyNull(total["value"]); verifyEq(total["quality"],"missingArea")
  }

  private [Str:Obj?][] base()
  {
    master:=meter("master","pm","building",null,null); master["kind"]="totalMeter"
    floor:=meter("floorMeter","pf","floor","master","tenant"); floor["parentId"]="legacy"
    return [
      [Str:Obj?]["id":"building","kind":"space","name":"building"],
      [Str:Obj?]["id":"floor","kind":"space","name":"floor","parentId":"building"],
      [Str:Obj?]["id":"company","kind":"organization","name":"company"],
      [Str:Obj?]["id":"tenant","kind":"organization","name":"tenant","parentId":"company"],
      [Str:Obj?]["id":"other","kind":"organization","name":"other","parentId":"company"],
      [Str:Obj?]["id":"legacy","kind":"group","name":"legacy"],
      master,floor,
    ]
  }
  private Str:Obj? meter(Str id, Str point, Str space, Str? upstream, Str? org)
  { ["id":id,"kind":"meter","name":id,"pointId":point,"spaceId":space,"meterParentId":upstream,"organizationId":org,"categoryId":"electric","unit":"kWh"] }
  private Str:Obj? request(Str dimension, Str[] selected)
  { ["kind":"profile","dimension":dimension,"nodeIds":selected,"from":"2026-01-01T00:00:00Z","to":"2026-01-01T01:00:00Z","period":"hour","metric":"energy","tz":"UTC"] }
  private Str:Obj? run([Str:Obj?][] rs, [Str:Obj?][] hs, Str dimension, Str[] selected)
  { EnerCubixEngine.report(request(dimension,selected),rs,hs) }
  private [Str:Obj?][] histories() { [history("pm",100f),history("pf",30f)] }
  private Str:Obj? history(Str id, Float v)
  { ["pointId":id,"unit":"kWh","mode":"interval","samples":[[Str:Obj?]["ts":"2026-01-01T00:00:00Z","value":v]]] }
  private [Str:Obj?][] points(Str:Obj? result) { ([Str:Obj?][])(([Str:Obj?][])result["series"]).first["points"] }
  private Float? value(Str:Obj? result) { (Float?)points(result).first["value"] }
  private Str:Obj? grandTotal(Str:Obj? result) { (([Str:Obj?][])((Str:Obj?)result["extra"])["grandTotals"]).first }
  private Void near(Float? actual, Float expected) { verifyNotNull(actual); verify(((Float)actual-expected).abs < 0.000001f,"$actual != $expected") }
}

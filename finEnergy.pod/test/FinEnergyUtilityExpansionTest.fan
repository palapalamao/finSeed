class FinEnergyUtilityExpansionTest : Test
{
  Void testUnassignedMasterExpandsToOwnLeafEndUses()
  {
    req:=request("metering",["main"])
    result:=FinEnergyEngine.report(req,records,histories)
    verifyEq(memberIds(result),["a","b","c"])
    shares:=rows(result,"utilityShares")
    verifyEq(shares.size,3)
    verifyEq(shares.find |r| {r["utilityId"]=="lighting"}["value"],20f)
    verifyEq(shares.find |r| {r["utilityId"]=="cooling"}["value"],10f)
    verifyEq(shares.find |r| {r["utilityId"]==""}["value"],5f)
    verifyEq(totals(result).first["value"],35f)
    verifyEq(FinEnergyDimension.dependencies(req,records)["points"],["pa","pb","pc"])
    verifyEq(FinEnergyHistory.pointIds(req,records).sort,["pa","pb","pc"])
    req["kind"]="profile"
    own:=FinEnergyEngine.report(req,records,histories)
    verifyEq(FinEnergyMath.maps(FinEnergyMath.maps(own["series"]).first["points"]).first["value"],100f)
  }

  Void testWholeSiteAndOrganizationUseTheSameScopedLeafSet()
  {
    ["space","organization"].each |dimension|
    {
      req:=request(dimension,[dimension=="space" ? "site" : "org"])
      result:=FinEnergyEngine.report(req,records,histories)
      verifyEq(memberIds(result),["a","b","c"],dimension)
      verifyEq(totals(result).first["value"],35f,dimension)
      verifyEq(FinEnergyDimension.dependencies(req,records)["points"],["pa","pb","pc"],dimension)
    }
  }

  Void testOverlappingScopeEntrancesAndAliasesDeduplicateLeaves()
  {
    rs:=records
    rs.add(meter("alias","pa","middle","lighting").set("canonicalId","a"))
    req:=request("metering",["main","middle","a","alias"])
    result:=FinEnergyEngine.report(req,rs,histories)
    verifyEq(memberIds(result),["a","b","c"])
    verifyEq(totals(result).first["value"],35f)
    verify(rows(result,"utilityShares").all |r| {r["percentageBasis"]=="knownUsage"})
    req=request("space",["site","floor","main","middle","alias"])
    result=FinEnergyEngine.report(req,rs,histories)
    verifyEq(memberIds(result),["a","b","c"])
    verifyEq(totals(result).first["value"],35f)
  }

  Void testAutomaticScopeNeverExpandsAcrossItsMembership()
  {
    rs:=records
    rs.add(["id":"otherSite","kind":"space","name":"Other site"])
    rs.add(["id":"otherOrg","kind":"organization","name":"Other organization"])
    rs.add(meter("outside","po","main","lighting").setAll(["spaceId":"otherSite","organizationId":"otherOrg"]))
    hs:=histories.add(history("po",50f))
    ["space","organization"].each |dimension|
    {
      req:=request(dimension,[dimension=="space" ? "site" : "org"])
      verifyEq(memberIds(FinEnergyEngine.report(req,rs,hs)),["a","b","c"])
      req["nodeIds"]=["main"]
      verifyEq(memberIds(FinEnergyEngine.report(req,rs,hs)),["a","b","c","outside"])
    }
  }

  Void testMissingLeafPrimaryAndHistoryNeverFallBackToAncestors()
  {
    req:=request("metering",["main"])
    hs:=histories.findAll |h| {h["pointId"]!="pa"}
    result:=FinEnergyEngine.report(req,records,hs)
    verifyEq(memberIds(result),["a","b","c"])
    member:=rows(result,"utilityMembers").find |r| {r["nodeId"]=="a"}
    verifyNull(member["value"]);verifyEq(member["quality"],"missing")
    verifyEq(totals(result).first["knownValue"],15f)
    rs:=records;rs.find |r| {r["id"]=="a"}.remove("pointId")
    result=FinEnergyEngine.report(req,rs,histories)
    verifyEq(memberIds(result),["a","b","c"])
    verifyNull(rows(result,"utilityMembers").find |r| {r["nodeId"]=="a"}["value"])
    verifyEq(FinEnergyDimension.dependencies(req,rs)["points"],["pb","pc"])
  }

  Void testNaAndSharedPrimaryRemainExplicitAfterExpansion()
  {
    req:=request("metering",["main"])
    hs:=histories
    hs.find |h| {h["pointId"]=="pa"}["samples"]=[["ts":"2026-01-01T00:00:00Z","value":null,"quality":"na","valueType":"na"]]
    result:=FinEnergyEngine.report(req,records,hs)
    verifyEq(memberIds(result),["a","b","c"])
    verifyEq(rows(result,"utilityMembers").find |r| {r["nodeId"]=="a"}["valueType"],"na")
    rs:=records;rs.find |r| {r["id"]=="b"}["pointId"]="pa"
    result=FinEnergyEngine.report(req,rs,histories)
    verifyEq(memberIds(result),["a","b","c"])
    verifyNull(totals(result).first["value"])
    verify(rows(result,"utilityShares").all |r| {r["percentageBasis"]=="overlappingScopes" && r["percentage"]==null})
  }

  Void testAutomaticParticipationAndExplicitLeafSelectionStaySeparate()
  {
    rs:=records;rs.find |r| {r["id"]=="b"}["includeInTotals"]=false
    rs.add(meter("formula","pv","main","lighting").set("expressionId","expr"))
    rs.add(["id":"expr","kind":"expression","name":"Unused formula","formula":"a","variables":["a":"a"]])
    req:=request("metering",["main"])
    verifyEq(memberIds(FinEnergyEngine.report(req,rs,histories)),["a","c"])
    req["nodeIds"]=["b"]
    verifyEq(memberIds(FinEnergyEngine.report(req,rs,histories)),["b"])
    rs.findAll |r| {["meter","totalMeter"].contains(r["kind"])}.each |r| {r["includeInTotals"]=false}
    req["nodeIds"]=["main"]
    result:=FinEnergyEngine.report(req,rs,histories)
    verifyEq(memberIds(result),["main"])
    verifyEq(rows(result,"utilityShares").first["utilityId"],"")
    verifyEq(rows(result,"utilityShares").first["value"],100f)
  }

  Void testMixedEnergyAndMissingIntermediateDoNotCreateFalseContainment()
  {
    rs:=records
    rs.add(["id":"water","kind":"category","name":"Water","unit":"m³"])
    rs.add(meter("waterMain","pwm",null,null,"totalMeter").set("categoryId","water"))
    rs.add(meter("waterLeaf","pwl","waterMain",null).set("categoryId","water"))
    hs:=histories.add(history("pwm",200f).set("unit","m³")).add(history("pwl",8f).set("unit","m³"))
    result:=FinEnergyEngine.report(request("space",["site"]),rs,hs)
    verifyEq(memberIds(result),["a","b","c","waterLeaf"])
    verifyEq(totals(result).size,2)
    verifyEq(totals(result).find |r| {r["categoryId"]=="water"}["value"],8f)
    rs=records.findAll |r| {r["id"]!="middle"}
    result=FinEnergyEngine.report(request("metering",["main"]),rs,histories)
    verifyEq(memberIds(result),["c"])
  }

  Void testSummaryFloorDoesNotHideOtherFloorsAndScopeUnionDropsIt()
  {
    rs:=records
    rs.add(["id":"summaryFloor","kind":"space","name":"Summary floor","parentId":"site"])
    rs.add(["id":"nativeEquip","kind":"meter","name":"Native equipment","nativeEquip":true,"nativeTreeParentId":"floor","spaceId":"floor","includeInTotals":false])
    rs.findAll |r| {r["pointId"]!=null}.each |r| {r["spaceId"]="unrelatedManualSpace";r["nativeSpaceId"]="nativeEquip"}
    rs.find |r| {r["id"]=="main"}["nativeSpaceId"]="summaryFloor"
    req:=request("space",["site"]).set("spaceSource","fin")
    verifyEq(memberIds(FinEnergyEngine.report(req,rs,histories)),["a","b","c"])
    req["nodeIds"]=["summaryFloor"]
    verifyEq(memberIds(FinEnergyEngine.report(req,rs,histories)),["main"])
    req["nodeIds"]=["summaryFloor","floor"]
    verifyEq(memberIds(FinEnergyEngine.report(req,rs,histories)),["a","b","c"])
    verifyEq(FinEnergyDimension.dependencies(req,rs)["points"],["pa","pb","pc"])
  }

  Void testSameFinalLeafSetKeepsCrossReportBaseUsage()
  {
    ["utility","profile","ranking","proportion"].each |kind|
    {
      req:=request("metering",["a","b","c"]).set("kind",kind)
      verifyEq(totals(FinEnergyEngine.report(req,records,histories)).first["value"],35f,kind)
    }
  }

  Void testDifferentEnergyIntermediateNeverHidesAnUpstreamOwnReading()
  {
    rs:=records.findAll |r| {!["b","c"].contains(r["id"])}
    rs.add(["id":"water","kind":"category","name":"Water","unit":"m³"])
    rs.find |r| {r["id"]=="middle"}["categoryId"]="water"
    hs:=histories;hs.find |h| {h["pointId"]=="pmed"}["unit"]="m³"
    result:=FinEnergyEngine.report(request("space",["site"]),rs,hs)
    verifyEq(memberIds(result),["a","main","middle"])
    verifyNull(totals(result).find |r| {r["categoryId"]=="electric"}["value"])
    verifyEq(memberIds(FinEnergyEngine.report(request("metering",["main"]),rs,hs)),["main"])
  }

  Void testUnreadableNodesAndPrimaryPointsDoNotExposeDescendants()
  {
    ["_comparisonReadable","_comparisonPointReadable"].each |flag|
    {
      rs:=records;rs.find |r| {r["id"]=="middle"}[flag]=false
      req:=request("metering",["main"])
      verifyEq(memberIds(FinEnergyEngine.report(req,rs,histories)),["c"],flag)
      verifyEq(FinEnergyDimension.dependencies(req,rs)["points"],["pc"],flag)
      rs=records;rs.find |r| {r["id"]=="a"}[flag]=false
      verifyEq(memberIds(FinEnergyEngine.report(req,rs,histories)),["b","c"],flag)
    }
  }

  Void testCyclicRelationshipsKeepDetailsButCannotProduceACombinedTotal()
  {
    rs:=records;rs.find |r| {r["id"]=="middle"}["meterParentId"]="a"
    result:=FinEnergyEngine.report(request("space",["site"]),rs,histories)
    verify(memberIds(result).contains("a"));verify(memberIds(result).contains("middle"))
    verifyNull(totals(result).first["value"])
    verify(rows(result,"utilityShares").all |r| {r["percentageBasis"]=="overlappingScopes"})
  }

  private Str[] memberIds(Str:Obj? result) {rows(result,"utilityMembers").map |r->Str| {r["nodeId"].toStr}.sort}
  private [Str:Obj?][] rows(Str:Obj? result,Str key) {FinEnergyMath.maps(((Map)result["extra"])[key])}
  private [Str:Obj?][] totals(Str:Obj? result) {FinEnergyMath.maps(((Map)result["summary"])["selectionTotals"])}
  private Str:Obj? request(Str dimension,Str[] ids)
  { ["kind":"utility","dimension":dimension,"nodeIds":ids,"from":"2026-01-01T00:00:00Z","to":"2026-01-01T01:00:00Z","asOf":"2026-01-02T00:00:00Z","period":"hour","metric":"energy","tz":"UTC"] }
  private [Str:Obj?][] records()
  {
    return [[Str:Obj?]["id":"electric","kind":"category","name":"Electricity","unit":"kWh"],
      ["id":"lighting","kind":"utility","name":"Lighting"],["id":"cooling","kind":"utility","name":"Cooling"],
      ["id":"site","kind":"space","name":"Site"],["id":"floor","kind":"space","name":"Floor","parentId":"site"],
      ["id":"org","kind":"organization","name":"Organization"],
      meter("main","pm",null,null,"totalMeter"),meter("middle","pmed","main",null,"totalMeter"),
      meter("a","pa","middle","lighting"),meter("b","pb","middle","cooling"),meter("c","pc","main",null)]
  }
  private Str:Obj? meter(Str id,Str point,Str? parent,Str? utility,Str kind:="meter")
  { ["id":id,"kind":kind,"name":id,"pointId":point,"meterParentId":parent,"utilityId":utility,"categoryId":"electric","spaceId":"floor","organizationId":"org"] }
  private [Str:Obj?][] histories() {[history("pm",100f),history("pmed",40f),history("pa",20f),history("pb",10f),history("pc",5f)]}
  private Str:Obj? history(Str point,Float value)
  { ["pointId":point,"unit":"kWh","mode":"interval","samples":[[Str:Obj?]["ts":"2026-01-01T00:00:00Z","value":value]]] }
}

class EnerCubixCrossModuleUsageTest : Test
{
  Void testEveryApplicableReportSharesTheClosedSourceSubtotal()
  {
    ["profile","ranking","proportion","utility","comparison","daily","workingHours","workingDays","dashboard"].each |kind|
    {
      r:=run(kind)
      verifyEq(known(r),30f,kind)
      verifyEq(r["from"],at(0)); verifyEq(r["to"],at(150))
      verifyEq(((Map)r["summary"])["totals"]->first->get("value"),null)
    }
    verifyEq(known(run("primary","coal")),3f)
    verifyEq(known(run("primary","co2")),15f)
  }

  Void testRankingDoesNotCropTheRequestedRangeAndMissingObjectsHaveNoRank()
  {
    req:=request("ranking"); req["nodeIds"]=["m","missing"]
    rs:=records.dup.add(["id":"missing","kind":"meter","name":"Missing","categoryId":"e","pointId":"absent"])
    r:=EnerCubixHistory.report(req,rs,histories)
    verifyEq(r["from"],at(0)); verifyEq(r["to"],at(150)); verifyNull(r["rangeAdjustment"])
    rows:=EnerCubixMath.maps(r["rows"])
    verifyEq(rows.first["nodeId"],"m"); verifyEq(rows.first["knownValue"],30f)
    verifyEq(rows.first["rank"],1); verifyNull(rows.last["rank"])
  }

  Void testKnownSharesAreExplicitAndSinglePositiveObjectIsOneHundredPercent()
  {
    r:=run("proportion")
    row:=EnerCubixMath.maps(r["rows"]).first
    verifyEq(row["knownPercentage"],100f); verifyEq(row["percentageBasis"],"knownUsage")
    rs:=records.dup.add(["id":"b","kind":"meter","name":"B","categoryId":"e","pointId":"pb"])
    hs:=histories.dup.add(history("pb",[["from":at(0),"to":at(60),"value":10f,"quality":"cleaned"]]))
    req:=request("proportion"); req["nodeIds"]=["m","b"]
    rows:=EnerCubixMath.maps(EnerCubixEngine.report(req,rs,hs)["rows"])
    verifyEq(rows[0]["knownPercentage"],75f); verifyEq(rows[1]["knownPercentage"],25f)
  }

  Void testPartialComparisonPreservesBothQuantitiesButNotDifferenceOrRate()
  {
    hs:=histories.dup
    source:=history("p",EnerCubixMath.maps(hs.first["intervals"]).dup.addAll([
      ["from":at(-180),"to":at(-120),"value":5f,"quality":"cleaned"],
      ["from":at(-120),"to":at(-60),"value":10f,"quality":"filtered"]]))
    req:=request("comparison"); req["otherFrom"]=at(-180); req["otherTo"]=at(-30)
    r:=EnerCubixEngine.report(req,records,[source])
    row:=EnerCubixMath.maps(((Map)r["extra"])["comparisons"]).first
    verifyEq(row["knownCurrent"],30f); verifyEq(row["knownReference"],15f)
    verifyNull(row["difference"]); verifyNull(row["percentage"])
    verifyEq(row["comparability"],"incompleteCoverage")
    reference:=EnerCubixMath.maps(r["series"]).last
    verifyEq(EnerCubixMath.maps(reference["points"])[0]["knownValue"],5f)
  }

  Void testObservedDailyAverageAndWorkSplitsDoNotEraseFilteredNumbers()
  {
    req:=request("daily"); req["to"]=at(3*1440); req["asOf"]=at(3*1440)
    hs:=[history("p",[["from":at(0),"to":at(60),"value":10f,"quality":"cleaned"],["from":at(1440),"to":at(1500),"value":20f,"quality":"filtered"]])]
    r:=EnerCubixEngine.report(req,records,hs)
    row:=EnerCubixMath.maps(r["rows"]).first
    verifyEq(row["knownValue"],15f); verifyEq(row["knownSamples"],2)
    work:=EnerCubixMath.maps(run("workingHours")["rows"]).first
    verifyEq(work["knownWorking"],20f); verifyEq(work["knownNonworking"],10f)
    verifyNull(work["workingPercentage"])
  }

  Void testAsOfAndClippedQueriesNeverBorrowOrProrateAnInterval()
  {
    req:=request("ranking"); req["asOf"]=at(90)
    r:=EnerCubixEngine.report(req,records,histories)
    verifyEq(known(r),10f); verifyEq(r["to"],at(150)); verifyEq(r["asOf"],at(90))
    hs:=[history("p",[["from":at(0),"to":at(15),"value":10f,"quality":"cleaned"],["from":at(15),"to":at(30),"value":20f,"quality":"cleaned"],["from":at(30),"to":at(45),"value":30f,"quality":"cleaned"],["from":at(45),"to":at(60),"value":40f,"quality":"cleaned"]])]
    ["profile","ranking","proportion","comparison","dashboard"].each |kind|
    {
      q:=request(kind); q["from"]=at(10); q["to"]=at(50)
      verifyEq(known(EnerCubixEngine.report(q,records,hs)),50f,kind)
    }
  }

  Void testSameEffectiveMeterSetAcrossDimensionsAndOverlappingScopesIsDeduplicated()
  {
    rs:=records.dup
    rs=rs.map |r->[Str:Obj?]| {r["id"]=="m" ? r.dup.set("spaceId","s").set("organizationId","o") : r}
    rs.add(["id":"s","kind":"space","name":"Space"])
    rs.add(["id":"o","kind":"organization","name":"Organization"])
    rs.add(["id":"b","kind":"meter","name":"B","spaceId":"s","organizationId":"o","categoryId":"e","pointId":"pb"])
    hs:=histories.dup.add(history("pb",[["from":at(0),"to":at(60),"value":10f,"quality":"cleaned"]]))
    ["space","metering","organization"].each |dimension|
    {
      req:=request("dashboard"); req["dimension"]=dimension
      req["nodeIds"]=dimension=="space" ? ["s","m"] : (dimension=="organization" ? ["o","m"] : ["m","b"])
      r:=EnerCubixEngine.report(req,rs,hs)
      total:=EnerCubixMath.maps(((Map)r["summary"])["selectionTotals"]).first
      verifyEq(total["knownValue"],40f,dimension)
      verifyEq(EnerCubixMath.strings(total["meterIds"]).sort,["b","m"])
    }
    rs=rs.map |r->[Str:Obj?]| {r["id"]=="b" ? r.dup.set("meterParentId","m") : r}
    q:=request("proportion"); q["dimension"]="metering"; q["nodeIds"]=["m","b"]
    r:=EnerCubixEngine.report(q,rs,hs)
    total:=EnerCubixMath.maps(((Map)r["summary"])["selectionTotals"]).first
    verifyEq(total["knownValue"],30f); verifyEq(total["meterIds"],["m"])
    verify(EnerCubixMath.maps(r["rows"]).all |row| {row["knownPercentage"]==null && row["percentageBasis"]=="overlappingScopes"})
  }

  Void testTopologySectionsDoNotChangeAnObjectsOwnQuantity()
  {
    rs:=records.dup; rs=rs.map |r->[Str:Obj?]| {r["id"]=="m" ? r.dup.set("kind","totalMeter") : r}
    req:=request("energyFlow"); req["dimension"]="metering"; req["categoryId"]="e"
    req["meterHistorySegments"]=[["from":at(0),"to":at(45),"known":false],["from":at(45),"to":at(100),"known":true,"records":rs],["from":at(100),"to":at(150),"known":true,"records":rs]]
    r:=EnerCubixEngine.report(req,rs,histories)
    overview:=(Map)((Map)r["extra"])["energyFlowOverview"]
    row:=EnerCubixMath.maps(overview["rows"]).find |entry| {entry["id"]=="m"}
    verifyEq(row["value"],30f); verifyEq(row["complete"],false)
    verifyEq(r["from"],at(0)); verifyEq(r["to"],at(150))
  }

  Void testFlowScopeResolvesThroughTheSameEffectiveMeterSet()
  {
    rs:=records.dup.map |r->[Str:Obj?]| {r["id"]=="m" ? r.dup.set("spaceId","s") : r}
    rs.add(["id":"s","kind":"space","name":"Space"])
    rs.add(["id":"b","kind":"meter","name":"B","spaceId":"s","categoryId":"e","pointId":"pb"])
    req:=request("energyFlow"); req["dimension"]="metering"; req["categoryId"]="e"; req["nodeIds"]=Str[,]
    req["scopeDimension"]="space"; req["scopeNodeIds"]=["s"]
    hs:=histories.dup.add(history("pb",[["from":at(0),"to":at(60),"value":10f,"quality":"cleaned"]]))
    r:=EnerCubixEngine.report(req,rs,hs)
    total:=EnerCubixMath.maps(((Map)r["summary"])["selectionTotals"]).first
    verifyEq(total["knownValue"],40f); verifyEq(EnerCubixMath.strings(total["meterIds"]).sort,["b","m"])
  }

  private Str:Obj? run(Str kind, Str metric:="energy") {EnerCubixEngine.report(request(kind,metric),records,histories)}
  private Float? known(Str:Obj? r) {EnerCubixMath.num(EnerCubixMath.maps(((Map)r["summary"])["knownTotals"]).first?.get("value"))}
  private Str:Obj? request(Str kind, Str metric:="energy") { ["kind":kind,"nodeIds":kind=="utility" ? ["g"] : ["m"],"from":at(0),"to":at(150),"asOf":at(150),"period":"hour","metric":metric,"perArea":false,"workHours":[1]] }
  private [Str:Obj?][] records() { [["id":"g","kind":"group","name":"Building"],["id":"m","kind":"meter","name":"Meter","parentId":"g","categoryId":"e","subcategoryId":"sub","utilityId":"u","pointId":"p","area":100f],["id":"e","kind":"category","name":"Electricity","unit":"kWh"],["id":"sub","kind":"subcategory","name":"Factors","categoryId":"e","coalFactor":0.1f,"co2Factor":0.5f],["id":"u","kind":"utility","name":"Lighting","categoryId":"e"],["id":"cal","kind":"calendar","name":"Calendar","isDefault":true,"workDays":[2],"workHours":[1]]] }
  private [Str:Obj?][] histories() { [history("p",[["from":at(0),"to":at(60),"value":10f,"quality":"cleaned"],["from":at(60),"to":at(120),"value":20f,"quality":"filtered"]])] }
  private Str:Obj? history(Str id, [Str:Obj?][] intervals) { ["pointId":id,"mode":"interval","quality":"cleaned","unit":"kWh","samples":Obj?[,],"intervals":intervals] }
  private Str at(Int minute) {(DateTime.fromIso("2026-10-20T00:00:00+08:00")+Duration(minute*1min.ticks)).toIso}
}

class EnerCubixReferenceCurvesTest : Test
{
  Void testBoundNativeReferenceIsIndependentOfDimensionAndReport()
  {
    ["profile","daily","utility","primary","leak","comparison"].each |kind|
    {
      ["space","metering","organization"].each |dimension|
      {
        q:=request(kind).set("dimension",dimension)
        rs:=records
        if (dimension == "space")
        {
          q["spaceSource"]="fin"
          rs.add(["id":"temp","kind":"nativePoint","name":"Outside temperature","parentId":"s","unit":"°C"])
        }
        verify(EnerCubixHistory.pointIds(q,rs).contains("temp"),"$kind $dimension must load the bound reference")
      }
    }
    // Browsing an unbound native point still does not authorize a history read.
    rs:=records.dup.add(["id":"unbound","kind":"nativePoint","name":"Unbound"])
    q:=request("profile").set("nodeIds",["unbound"]).set("referenceIds",Str[,])
    verify(!EnerCubixHistory.pointIds(q,rs).contains("unbound"))
  }

  Void testReferenceCurvesNeverAlterBusinessStatistics()
  {
    ["profile","daily","utility","primary","leak","comparison"].each |kind|
    {
      q:=request(kind)
      without:=q.dup;without.remove("referenceIds")
      base:=EnerCubixEngine.report(without,records,histories)
      result:=EnerCubixEngine.report(q,records,histories)
      refs:=EnerCubixMath.maps(result["series"]).findAll |line| {line["role"] == "reference"}
      verify(!refs.isEmpty,kind)
      verifyEq(result["summary"],base["summary"],kind)
      verifyEq(((Map)result["extra"])["utilityShares"],((Map)base["extra"])["utilityShares"],kind)
      verifyEq(((Map)result["extra"])["leakTotals"],((Map)base["extra"])["leakTotals"],kind)
      refs.each |line| {verifyEq(line["unit"],"°C")}
    }
  }

  Void testDailyReferenceUsesAvailableHourlyMeansAndPreservesZeroAndNa()
  {
    hs:=histories
    hs.last["samples"]=[["ts":at(0),"value":0f],["ts":at(24),"value":20f],["ts":at(1),"value":null,"valueType":"na"],["ts":at(25),"value":30f]]
    result:=EnerCubixEngine.report(request("daily"),records,hs)
    ref:=EnerCubixMath.maps(result["series"]).find |line| {line["role"] == "reference"}
    verifyNotNull(ref)
    points:=EnerCubixMath.maps(ref["points"])
    verifyEq(points.size,24)
    verifyEq(points[0]["value"],10f)
    verifyEq(points[0]["validSamples"],2)
    verifyEq(points[1]["value"],30f)
    verifyEq(points[1]["validSamples"],1)
    verifyEq(points[1]["naSamples"],1)
    verifyNull(points[2]["value"])
    verifyEq(points[2]["missingSamples"],2)
    verifyEq(points[0]["expectedSamples"],2)
  }

  Void testPeriodComparisonHasTwoRealReferenceRanges()
  {
    q:=request("comparison")
    q["from"]=at(24);q["to"]=at(48);q["otherFrom"]=at(0);q["otherTo"]=at(24)
    result:=EnerCubixEngine.report(q,records,histories)
    refs:=EnerCubixMath.maps(result["series"]).findAll |line| {line["role"] == "reference"}
    verifyEq(refs.size,2)
    current:=refs.find |line| {line["referencePeriod"] == "current"}
    previous:=refs.find |line| {line["referencePeriod"] == "comparison"}
    verifyNotNull(current);verifyNotNull(previous)
    verifyEq(EnerCubixMath.maps(current["points"]).first["ts"],at(24))
    verifyEq(EnerCubixMath.maps(previous["points"]).first["ts"],at(0))
    verifyEq(EnerCubixMath.maps(current["points"]).first["value"],20f)
    verifyEq(EnerCubixMath.maps(previous["points"]).first["value"],10f)
    verify(EnerCubixMath.maps(result["series"]).any |line| {line["id"].toStr.endsWith("|reference") && line["role"] != "reference"})
  }

  Void testReferenceIgnoresMetricAndKeepsRawHistory()
  {
    hs:=histories
    hs.last["samples"]=[["ts":at(0),"value":999f]]
    hs.last["rawSamples"]=[["ts":at(0),"value":18f]]
    ["energy","cost","coal"].each |metric|
    {
      result:=EnerCubixEngine.report(request("profile").set("metric",metric),records,hs)
      ref:=EnerCubixMath.maps(result["series"]).find |line| {line["role"] == "reference"}
      verifyNotNull(ref);verifyEq(ref["unit"],"°C")
      verifyEq(EnerCubixMath.maps(ref["points"]).first["value"],18f)
    }
  }

  Void testObjectAxesDoNotAcquireReferenceCurves()
  {
    ["ranking","proportion","workingHours","workingDays"].each |kind|
    {
      result:=EnerCubixEngine.report(request(kind),records,histories)
      verify(!EnerCubixMath.maps(result["series"]).any |line| {line["role"] == "reference"})
    }
  }

  Void testCovReferencePreservesNaAndNeverExtendsPastCutoff()
  {
    hs:=histories
    hs.last["mode"]="cov"
    hs.last["samples"]=[["ts":at(0),"value":null,"valueType":"na"],["ts":at(1),"value":20f]]
    q:=request("profile").set("period","hour").set("to",at(3)).set("asOf",at(2))
    result:=EnerCubixEngine.report(q,records,hs)
    ref:=EnerCubixMath.maps(result["series"]).find |line| {line["role"] == "reference"}
    points:=EnerCubixMath.maps(ref["points"])
    verifyEq(points[0]["valueType"],"na")
    verifyEq(points[1]["value"],20f)
    verifyNull(points[2]["value"])
    verifyEq(points[2]["missingSamples"],1)
  }

  private Str:Obj? request(Str kind)
  {
    q:=Str:Obj?["kind":kind,"dimension":"metering","nodeIds":["m"],"referenceIds":["temp"],"from":at(0),"to":at(48),"asOf":at(72),"period":"day","metric":"energy","perArea":false]
    if (kind == "comparison") {q["otherFrom"]=at(0);q["otherTo"]=at(48);q["comparisonAlignment"]="duration"}
    return q
  }
  private [Str:Obj?][] records()
  {
    [["id":"s","kind":"space","name":"Site"],["id":"m","kind":"totalMeter","name":"Main","spaceId":"s","categoryId":"e","utilityId":"u","pointId":"mp"],
     ["id":"c","kind":"meter","name":"Child","spaceId":"s","categoryId":"e","utilityId":"u","pointId":"cp","meterParentId":"m"],
     ["id":"e","kind":"category","name":"Electricity","unit":"kWh"],["id":"u","kind":"utility","name":"Lighting","categoryId":"e"],
     ["id":"t","kind":"tariff","name":"Tariff","categoryId":"e","isDefault":true,"mode":"flat","rate":2f],
     ["id":"weather","kind":"binding","name":"Outside temperature","pointId":"temp","role":"reference"]]
  }
  private [Str:Obj?][] histories()
  {
    meter:=[Str:Obj?][,];child:=[Str:Obj?][,];temperature:=[Str:Obj?][,]
    (0..<48).each |hour| {meter.add(["ts":at(hour),"value":10f]);child.add(["ts":at(hour),"value":5f]);temperature.add(["ts":at(hour),"value":hour < 24 ? 10f : 20f])}
    return [["pointId":"mp","unit":"kWh","mode":"interval","samples":meter],["pointId":"cp","unit":"kWh","mode":"interval","samples":child],["pointId":"temp","unit":"°C","mode":"sampled","samples":temperature]]
  }
  private Str at(Int hours) {(DateTime.fromIso("2026-10-01T00:00:00+08:00")+Duration(hours*1hr.ticks)).toIso}
}

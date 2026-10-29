class EnerCubixCostConsistencyTest : Test
{
  Void testAvailableCostAcrossReportsAndViews()
  {
    ["profile","ranking","proportion","utility","comparison","daily","workingHours","workingDays","dashboard"].each |kind|
    {
      ["space","metering","organization"].each |dimension|
      {
        req:=request(kind).set("dimension",dimension).set("nodeIds",dimension == "space" ? ["s","m"] : (dimension == "organization" ? ["o","m"] : ["m"]))
        result:=EnerCubixEngine.report(req,records,histories)
        known:=EnerCubixMath.maps(((Map)result["summary"])["selectionTotals"]).first
        verifyEq(known["knownValue"],50f,"$kind $dimension")
        verifyEq(known["unit"],"元")
        verifyNull(EnerCubixMath.maps(((Map)result["summary"])["totals"]).first["value"])
      }
    }
  }

  Void testCostFlowSharesTheSamePrimaryHistorySubtotal()
  {
    req:=request("energyFlow").set("dimension","metering").set("categoryId","e")
    result:=EnerCubixEngine.report(req,records,histories)
    total:=EnerCubixMath.maps(((Map)result["summary"])["selectionTotals"]).first
    verifyEq(total["knownValue"],50f); verifyEq(total["unit"],"元")
  }

  Void testFourBandsUseTariffRatherThanAnUnrelatedCalendar()
  {
    req:=request("daily")
    result:=EnerCubixEngine.report(req,records,histories)
    rows:=EnerCubixMath.maps(result["rows"])
    verifyEq(rows.find |r| {r["hour"] == 0}["band"],"sharp")
    verifyEq(rows.find |r| {r["hour"] == 1}["band"],"valley")
    bands:=EnerCubixMath.maps(((Map)result["extra"])["loadBands"])
    verifyEq(bands.find |r| {r["band"] == "sharp"}["knownValue"],30f)
    verifyEq(bands.find |r| {r["band"] == "valley"}["knownValue"],20f)
  }

  Void testVirtualCostFlowUsesTheSamePrimaryMeterSelection()
  {
    rs:=records.addAll([["id":"b","kind":"totalMeter","name":"B","spaceId":"s","organizationId":"o","categoryId":"e","pointId":"pb","autoSum":true,"meterOrigin":["type":"virtual","reason":"submeterSum"]],["id":"child","kind":"meter","name":"Child","spaceId":"s","organizationId":"o","categoryId":"e","pointId":"pc","meterParentId":"m","utilityId":"u"]])
    rs.find |r| {r["id"] == "m"}.setAll(["kind":"totalMeter","autoSum":true,"meterOrigin":["type":"virtual","reason":"submeterSum"]])
    rs.addAll([["id":"sa","kind":"space","name":"Floor A","parentId":"s"],["id":"sb","kind":"space","name":"Floor B","parentId":"s"]])
    rs.findAll |r| {["m","child"].contains(r["id"])}.each |r| {r["spaceId"]="sa"}
    rs.find |r| {r["id"] == "b"}["spaceId"]="sb"
    hs:=histories.addAll([["pointId":"pb","mode":"interval","unit":"kWh","samples":[["ts":at(0),"value":2f]]],["pointId":"pc","mode":"interval","unit":"kWh","samples":[["ts":at(0),"value":1000f]]]])
    ["metering","space","organization"].each |dimension|
    {
      ["relations","endUse"].each |mode|
      {
        ids:=mode == "endUse" || dimension == "metering" ? ["m","b","child","m"] : (dimension == "space" ? ["s","m"] : ["o","m"])
        profile:=EnerCubixEngine.report(request("profile").set("dimension",dimension).set("nodeIds",ids),rs,hs)
        verifyEq(EnerCubixMath.maps(((Map)profile["summary"])["selectionTotals"]).first["knownValue"],56f)
        result:=EnerCubixEngine.report(request("energyFlow").set("dimension",dimension).set("flowMode",mode).set("nodeIds",ids).set("categoryId","e"),rs,hs)
        total:=EnerCubixMath.maps(((Map)result["summary"])["selectionTotals"]).first
        verifyEq(total["knownValue"],56f,"$mode $dimension total=$total")
        verifyNull(total["value"])
        verifyEq(total["meterIds"],["b","m"])
        verifyEq(EnerCubixMath.strings(total["sourceIds"]).sort,["p","pb"])
        accounting:=(Map)((Map)result["extra"])["energyFlowAccounting"]
        verifyEq(accounting["unionValue"],56f)
        verifyEq(accounting["basis"],"meterCostScope")
      }
    }
    rs.addAll([["id":"sc","kind":"space","name":"Other floor"],["id":"standalone","kind":"meter","name":"Standalone","spaceId":"sc","categoryId":"e","pointId":"ps"]])
    hs.add(["pointId":"ps","mode":"interval","unit":"kWh","samples":[["ts":at(0),"value":1f]]])
    automatic:=EnerCubixEngine.report(request("energyFlow").set("dimension","metering").set("nodeIds",Str[,]).set("categoryId","e"),rs,hs)
    automaticTotal:=EnerCubixMath.maps(((Map)automatic["summary"])["selectionTotals"]).first
    verifyEq(automaticTotal["knownValue"],59f)
    verifyEq(automaticTotal["meterIds"],["b","m","standalone"])
    rs.find |r| {r["id"] == "m"}["pointId"]="missing-primary"
    result:=EnerCubixEngine.report(request("energyFlow").set("dimension","metering").set("categoryId","e"),rs,hs)
    total:=EnerCubixMath.maps(((Map)result["summary"])["selectionTotals"]).first
    verifyNull(total["knownValue"])
    verifyEq(total["sourceIds"],["missing-primary"])
  }

  Void testCostForecastIsTheSumOfCanonicalMeterModels()
  {
    rs:=records.dup.add(["id":"b","kind":"meter","name":"B","spaceId":"s","organizationId":"o","categoryId":"e","pointId":"pb"])
    hs:=[Str:Obj?][,]
    ["p","pb"].each |point|
    {
      samples:=[Str:Obj?][,]
      (0..<56*24).each |hour| {samples.add(["ts":at(hour*60),"value":point == "p" ? (hour/24%7+1).toFloat : (8-hour/24%7).toFloat])}
      hs.add(["pointId":point,"mode":"interval","quality":"ok","unit":"kWh","samples":samples])
    }
    Float? expected:=null
    ["metering","space","organization"].each |dimension|
    {
      req:=request("forecast").set("dimension",dimension).set("period","day").set("forecastDays",7).set("to",at(56*1440)).set("asOf",at(56*1440))
      // Fixed past training dates: forecasts may not consume future samples.
      offset:=-100*1440
      req["from"]=at(offset); req["to"]=at(offset+56*1440); req["asOf"]=req["to"]
      data:=hs.map |h->[Str:Obj?]| {h.dup.set("samples",EnerCubixMath.maps(h["samples"]).map |s->[Str:Obj?]| {s.dup.set("ts",(DateTime.fromIso(s["ts"].toStr)+Duration(offset*1min.ticks)).toIso)})}
      req["nodeIds"]=dimension == "space" ? ["s"] : (dimension == "organization" ? ["o"] : ["m","b"])
      result:=EnerCubixEngine.report(req,rs,data)
      fits:=EnerCubixMath.maps(((Map)result["extra"])["forecasts"])
      verify(fits.all |f| {f["status"] == "ok" && f["model"] == "meterSum"})
      total:=fits.reduce(0f) |Float sum,fit->Float| {sum+(Float)fit["predictedTotal"]}
      if (expected == null) expected=total
      verifyEq(total,expected,dimension)
    }
  }

  Void testAsOfAndZeroRemainTruthfulForCost()
  {
    req:=request("ranking").set("asOf",at(90))
    r:=EnerCubixEngine.report(req,records,histories)
    verifyEq(EnerCubixMath.maps(((Map)r["summary"])["knownTotals"]).first["value"],30f)
    hs:=histories;EnerCubixMath.maps(hs.first["intervals"]).each |row| {row["value"]=0f}
    r=EnerCubixEngine.report(request("ranking"),records,hs)
    verifyEq(EnerCubixMath.maps(((Map)r["summary"])["knownTotals"]).first["value"],0f)
  }

  Void testDateExceptionChangesBothThePriceAndTimeBand()
  {
    rs:=records
    rs.find |r| {r["id"] == "t"}["exceptions"]=[["from":"2026-10-20","to":"2026-10-21","startHour":1,"endHour":2,"rate":4f,"band":"peak"]]
    result:=EnerCubixEngine.report(request("daily"),rs,histories)
    row:=EnerCubixMath.maps(result["rows"]).find |r| {r["hour"] == 1}
    verifyEq(row["band"],"peak");verifyEq(row["knownValue"],80f)
    ctx:=EnerCubixContext(rs,histories,DateTime.fromIso(at(0)).tz)
    verifyEq(ctx.timeBand("m","e",DateTime.fromIso(at(1440+60)),DateTime.fromIso(at(1440+120))),"valley")
  }

  Void testFractionalRulesPriceClosedIntervalsOnceWithoutProration()
  {
    rs:=records
    rs.find |r| {r["id"] == "t"}["rules"]=[["startHour":0,"endHour":0.5f,"rate":1f,"band":"valley"],["startHour":0.5f,"endHour":1,"rate":3f,"band":"sharp"]]
    hs:=histories
    hs.first["intervals"]=[["from":at(0),"to":at(20),"value":10f,"quality":"cleaned"],["from":at(20),"to":at(40),"value":20f,"quality":"cleaned"],["from":at(40),"to":at(60),"value":5f,"quality":"cleaned"]]
    req:=request("profile").set("to",at(60))
    result:=EnerCubixEngine.report(req,rs,hs)
    verifyEq(EnerCubixMath.maps(((Map)result["summary"])["knownTotals"]).first["value"],45f)
    // The interval beginning 00:20 belongs to that tariff, even across 00:30.
    usage:=(Map)((Map)result["extra"])["knownUsage"]
    reads:=EnerCubixMath.maps(usage["sourceUsage"])
    verifyEq(reads.reduce(0f) |Float sum,row->Float| {sum+(Float)row["coveredSeconds"]},3600f)
  }

  Void testAbsentPrimaryHistoryNeverFallsBackToAChildForCost()
  {
    rs:=records.dup.add(["id":"child","kind":"meter","name":"Child","categoryId":"e","pointId":"p","meterParentId":"m"])
    rs.find |r| {r["id"] == "m"}["pointId"]="missing-primary"
    result:=EnerCubixEngine.report(request("profile").set("dimension","metering"),rs,histories)
    row:=EnerCubixMath.maps(((Map)result["summary"])["knownTotals"]).first
    verifyNull(row["value"]);verifyEq(row["sourceIds"],["missing-primary"])
  }

  Void testDifferentMeterTariffsShareOneDeduplicatedCostAcrossViews()
  {
    rs:=records.dup.addAll([["id":"b","kind":"meter","name":"B","spaceId":"s","organizationId":"o","categoryId":"e","pointId":"pb","tariffId":"tb","utilityId":"u"],["id":"tb","kind":"tariff","name":"B tariff","mode":"flat","rate":5f,"band":"flat"]])
    hs:=histories.dup.add(["pointId":"pb","mode":"interval","quality":"ok","unit":"kWh","samples":[["ts":at(0),"value":2f]]])
    ["space","metering","organization"].each |dimension|
    {
      ["profile","ranking","proportion","utility","daily","workingHours","workingDays","dashboard"].each |kind|
      {
        req:=request(kind).set("dimension",dimension).set("nodeIds",dimension == "space" ? ["s","m"] : (dimension == "organization" ? ["o","m"] : ["m","b"]))
        result:=EnerCubixEngine.report(req,rs,hs)
        total:=EnerCubixMath.maps(((Map)result["summary"])["selectionTotals"]).first
        verifyEq(total["knownValue"],60f,"$kind $dimension")
        verifyEq(EnerCubixMath.strings(total["meterIds"]).sort,["b","m"])
        verifyEq(EnerCubixMath.strings(total["sourceIds"]).sort,["p","pb"])
      }
    }
  }

  private Str:Obj? request(Str kind) { ["kind":kind,"nodeIds":["m"],"from":at(0),"to":at(150),"asOf":at(150),"period":"hour","metric":"cost","perArea":false,"workHours":[1]] }
  private [Str:Obj?][] records() { [["id":"s","kind":"space","name":"Space"],["id":"o","kind":"organization","name":"Organization"],["id":"m","kind":"meter","name":"Meter","spaceId":"s","organizationId":"o","categoryId":"e","pointId":"p","utilityId":"u"],["id":"e","kind":"category","name":"Electricity","unit":"kWh"],["id":"u","kind":"utility","name":"Lighting","categoryId":"e"],["id":"t","kind":"tariff","name":"Four bands","categoryId":"e","isDefault":true,"mode":"weekly","rate":2f,"band":"flat","rules":[["startHour":0,"endHour":1,"rate":3f,"band":"sharp"],["startHour":1,"endHour":2,"rate":1f,"band":"valley"]]],["id":"cal","kind":"calendar","name":"Unrelated calendar","workDays":[2],"workHours":[1],"peakHours":[0]]] }
  private [Str:Obj?][] histories() { [["pointId":"p","mode":"interval","quality":"cleaned","unit":"kWh","samples":Obj?[,],"intervals":[["from":at(0),"to":at(60),"value":10f,"quality":"cleaned"],["from":at(60),"to":at(120),"value":20f,"quality":"filtered"]]]] }
  private Str at(Int minute) {(DateTime.fromIso("2026-10-20T00:00:00+08:00")+Duration(minute*1min.ticks)).toIso}
}

class EnerCubixEngineTest : Test
{
  Void testCumulativeAndInterval()
  {
    // Authoritative two cumulative boundaries 1000 -> 1120 mean 120, never 1120.
    r := run([meter("m", "p")], [history("p", "cumulative", [1000f, 1120f])])
    near(value(r), 120f)
    r = run([meter("m", "p")], [history("p", "interval", [12f, 30f])])
    near(value(r), 12f)
    req := request(); req["to"] = ts(2)
    r = run([meter("m", "p")], [history("p", "interval", [12f, 30f])], req)
    near(value(r, 1), 30f)
  }

  Void testMissingResetMaximum()
  {
    r := run([meter("m", "p")], [history("p", "cumulative", [100f])])
    verifyNull(value(r)); verifyEq(quality(r), "missing")
    r = run([meter("m", "p")], [history("p", "cumulative", [100f, 2f])])
    verifyNull(value(r)); verifyEq(quality(r), "reset")
    m := meter("m", "p"); m["maximum"] = 5f
    r = run([m], [history("p", "interval", [8f])])
    verifyNull(value(r)); verifyEq(quality(r), "maximum")
  }

  Void testInterpolationAndSourceImmutability()
  {
    h := history("p", "cumulative", [10f, 30f]); samples := ([Str:Obj?][])h["samples"]
    samples[1]["ts"] = ts(2)
    req := request(); req["from"] = "2026-01-01T00:30:00Z"; req["to"] = "2026-01-01T01:30:00Z"
    r := run([meter("m", "p")], [h], req)
    pts := points(r)
    near((Float?)pts[0]["value"], 5f); near((Float?)pts[1]["value"], 5f)
    verifyEq(pts[0]["quality"], "estimated")
    verifyEq(samples[0]["value"], 10f); verifyEq(samples[1]["ts"], ts(2))
  }

  Void testGroupMasterAndIndependentSelections()
  {
    g := rec("g", "group"); sub := rec("sub", "group"); sub["parentId"] = "g"
    a := meter("a", "pa", "g"); b := meter("b", "pb", "sub")
    master := meter("t", "pt", "g"); master["kind"] = "totalMeter"
    other := meter("w", "pw", "sub"); other["categoryId"] = "water"
    req := request(); req["nodeIds"] = ["g", "sub"]
    r := run([g,sub,a,b,master,other], [history("pa","interval",[10f]),history("pb","interval",[20f]),history("pt","interval",[50f]),history("pw","interval",[7f])], req)
    ss := ([Str:Obj?][])r["series"]
    verifyEq(ss.size, 4)
    near((Float?)points(r,0)[0]["value"], 50f)
    near((Float?)points(r,1)[0]["value"], 7f)
    near((Float?)points(r,2)[0]["value"], 20f)
  }

  Void testVirtualDefaultAndExplicitTotals()
  {
    g := rec("g", "group"); a := meter("a", "pa", "g"); b := meter("b", "pb", "g")
    e := rec("e", "expression"); e["formula"] = "(a + b) * 2 - a / 2"; e["variables"] = ["a":"a", "b":"b"]
    v := meter("v", "pv", "g"); v["expressionId"] = "e"
    sensor := rec("s", "sensor"); sensor["parentId"] = "g"; sensor["pointId"] = "ps"; sensor["categoryId"] = "electric"
    req := request(); req["nodeIds"] = ["g", "v"]
    hs := [history("pa","interval",[10f]),history("pb","interval",[20f]),history("ps","sampled",[99f]),history("pv","interval",[55f])]
    r := run([g,a,b,e,v,sensor], hs, req)
    near(value(r), 30f); near((Float?)points(r,1)[0]["value"], 55f)
    v["includeInTotals"] = true
    r = run([g,a,b,e,v,sensor], hs, req); near(value(r), 85f)
  }

  Void testVirtualCycleAndDivisionByZero()
  {
    a := meter("m", ""); a["expressionId"] = "e"
    e := rec("e", "expression"); e["formula"] = "a + 1"; e["variables"] = ["a":"m"]
    r := run([a,e], [Str:Obj?][,]); verifyNull(value(r)); verifyEq(quality(r), "missing")
    e["formula"] = "1 / 0"; e["variables"] = Str:Str[:]
    r = run([a,e], [Str:Obj?][,]); verifyNull(value(r)); verifyEq(quality(r), "missing")
    e["formula"] = "sys::Env.cur"; r = run([a,e], [Str:Obj?][,]); verifyNull(value(r)); verifyEq(quality(r), "missing")
  }

  Void testCoefficientsAndArea()
  {
    m := meter("m", "p"); m["subcategoryId"] = "sc"; m["area"] = 20f
    sc := rec("sc", "subcategory"); sc["coalFactor"] = 0.12f; sc["co2Factor"] = 0.7f
    req := request(); req["metric"] = "coal"; req["perArea"] = true
    r := run([m,sc], [history("p","interval",[100f])], req); near(value(r), 0.6f)
    req["metric"] = "co2"; req["perArea"] = false
    r = run([m,sc], [history("p","interval",[100f])], req); near(value(r), 70f)
    m.remove("area"); req["perArea"] = true
    r = run([m,sc], [history("p","interval",[100f])], req); verifyNull(value(r)); verifyEq(quality(r), "missingArea")
  }

  Void testTariffFlatWeeklyExceptionAndAbsolute()
  {
    m := meter("m", "p"); m["tariffId"] = "t"
    t := rec("t", "tariff"); t["mode"] = "flat"; t["rate"] = 0.5f
    req := request(); req["metric"] = "cost"
    hs := [history("p","interval",[10f])]
    near(value(run([m,t],hs,req)),5f)
    t["mode"] = "weekly"; t["rules"] = [[Str:Obj?]["weekday":4,"startHour":0,"endHour":1,"rate":2f]]
    near(value(run([m,t],hs,req)),20f)
    t["exceptions"] = [[Str:Obj?]["from":"2026-01-01","to":"2026-01-02","rate":3f]]
    near(value(run([m,t],hs,req)),30f)
    t["mode"] = "absolute"; t.remove("exceptions")
    t["rules"] = [[Str:Obj?]["from":ts(0),"to":ts(1),"rate":4f]]
    near(value(run([m,t],hs,req)),40f)
  }

  Void testMarginalMonthlyAndAnnualBlocks()
  {
    // 60 units in first hour cost 60; next 60 crosses 100 at 1 then 20 at 2 => 80.
    m := meter("m", "p"); m["tariffId"] = "t"
    t := rec("t", "tariff"); t["mode"] = "monthlyBlock"
    t["blocks"] = [[Str:Obj?]["limit":100f,"rate":1f],[Str:Obj?]["limit":null,"rate":2f]]
    req := request(); req["metric"] = "cost"; req["from"] = ts(1); req["to"] = ts(2)
    hs := [history("p","interval",[60f,60f])]
    near(value(run([m,t],hs,req)),80f)
    t["mode"] = "yearlyBlock"; near(value(run([m,t],hs,req)),80f)
    hs = [history("p","interval",[60f])]; (([Str:Obj?][])hs[0]["samples"])[0]["ts"] = ts(1)
    r := run([m,t],hs,req); verifyNull(value(r)); verifyEq(quality(r),"missingTariffBaseline")
  }

  Void testCalendarWorkingAndNonworking()
  {
    c := rec("c", "calendar"); c["workHours"] = [1]; c["workDays"] = [4]
    m := meter("m","p"); req := request(); req["kind"] = "workingHours"; req["to"] = ts(2)
    r := run([m,c],[history("p","interval",[10f,30f])],req)
    rows := ([Str:Obj?][])r["rows"]
    near((Float?)rows[0]["working"],30f); near((Float?)rows[0]["nonworking"],10f)
    req["kind"] = "workingDays"; c["exceptions"] = [[Str:Obj?]["date":"2026-01-01","working":false]]
    r = run([m,c],[history("p","interval",[10f,30f])],req); rows = ([Str:Obj?][])r["rows"]
    near((Float?)rows[0]["nonworking"],40f)
  }

  Void testCopAndRegression()
  {
    a := meter("a","pa"); b := meter("b","pb")
    c := rec("c","cop"); c["numeratorId"] = "b"; c["denominatorId"] = "a"
    req := request(); req["nodeIds"] = ["c"]; req["kind"] = "cop"; req["to"] = ts(3)
    hs := [history("pa","interval",[1f,2f,3f]),history("pb","interval",[3f,5f,7f])]
    r := run([a,b,c],hs,req); near(value(r),3f)
    req["kind"] = "regression"; req["xId"] = "a"; req["yId"] = "b"; req["nodeIds"] = ["a","b"]
    r = run([a,b,c],hs,req); extra := (Str:Obj?)r["extra"]
    near((Float?)extra["slope"],2f); near((Float?)extra["intercept"],1f); near((Float?)extra["r2"],1f)
  }

  Void testEmptySelectionAndTableAgreement()
  {
    req := request(); req["nodeIds"] = Str[,]
    r := run([meter("m","p")],[history("p","interval",[5f])],req)
    verify(((Obj[])r["series"]).isEmpty)
    req["nodeIds"] = ["m"]; r = run([meter("m","p")],[history("p","interval",[5f])],req)
    rows := ([Str:Obj?][])r["rows"]; verifyEq(rows[0]["value"],value(r))
    verifyEq(rows[0]["quality"],quality(r))
  }

  Void testCopAggregatesBeforeDividing()
  {
    a:=meter("a","pa"); b:=meter("b","pb")
    c:=rec("c","cop"); c["numeratorId"]="b"; c["denominatorId"]="a"
    req:=request(); req["kind"]="cop"; req["nodeIds"]=["c"]; req["period"]="day"; req["to"]=ts(3)
    r:=run([a,b,c],[history("pa","interval",[1f,2f,3f]),history("pb","interval",[3f,5f,7f])],req)
    near(value(r),2.5f)
    totals:=([Str:Obj?][])((Str:Obj?)r["summary"])["totals"]
    near((Float?)totals[0]["value"],2.5f)
  }

  Void testLeakSignedAndSubgroupMaster()
  {
    g:=rec("g","group"); sub:=rec("sub","group"); sub["parentId"]="g"
    master:=meter("t","pt","g"); master["kind"]="totalMeter"
    submaster:=meter("st","pst","sub"); submaster["kind"]="totalMeter"
    member:=meter("a","pa","sub")
    req:=request(); req["kind"]="leak"; req["nodeIds"]=["g"]
    r:=run([g,sub,master,submaster,member],[history("pt","interval",[100f]),history("pst","interval",[120f]),history("pa","interval",[10f])],req)
    near(value(r),-20f)
    row:=(([Str:Obj?][])r["rows"])[0]
    near((Float?)row["percentage"],-20f); near((Float?)row["submeter"],120f)
  }

  Void testTrendKeepsRawCountersAndRegressionReference()
  {
    m:=meter("m","p"); req:=request(); req["kind"]="trend"; req["to"]=ts(2)
    r:=run([m],[history("p","cumulative",[100f,140f,180f])],req)
    near(value(r),100f); near(value(r,1),140f)
    req["kind"]="regression"; req["xId"]="outside"; req["yId"]="m"; req["to"]=ts(3)
    r=run([m],[history("p","interval",[3f,5f,7f]),history("outside","sampled",[1f,2f,3f])],req)
    fit:=(Str:Obj?)r["extra"]; near((Float?)fit["slope"],2f)
  }

  Void testRankingProportionAndUtilityMissing()
  {
    g:=rec("g","group"); a:=meter("a","pa","g"); b:=meter("b","pb","g")
    a["utilityId"]="u"; b["utilityId"]="v"
    u:=rec("u","utility"); u["categoryId"]="electric"; v:=rec("v","utility"); v["categoryId"]="electric"
    req:=request(); req["kind"]="ranking"; req["nodeIds"]=["a","b"]
    r:=run([g,a,b,u,v],[history("pa","interval",[10f]),history("pb","interval",[30f])],req)
    rows:=([Str:Obj?][])r["rows"]; verifyEq(rows[0]["nodeId"],"b"); near((Float?)rows[0]["percentage"],75f)
    req["kind"]="utility"; req["nodeIds"]=["g"]
    r=run([g,a,b,u,v],[history("pa","interval",[10f])],req)
    verifyEq((([Str:Obj?][])r["series"]).size,2)
    verifyNull((Float?)points(r,1)[0]["value"])
  }

  Void testAbsoluteTariffSplitWithinHour()
  {
    m:=meter("m","p"); m["tariffId"]="t"
    t:=rec("t","tariff"); t["mode"]="absolute"; t["rate"]=1f
    t["rules"]=[[Str:Obj?]["from":"2026-01-01T00:30:00Z","to":ts(1),"rate":3f]]
    req:=request(); req["metric"]="cost"
    r:=run([m,t],[history("p","interval",[10f])],req); near(value(r),20f)
  }

  Void testProjectTimezoneBucketsAndMonthlyReset()
  {
    req:=request(); req["period"]="day"; req["tz"]="Shanghai"; req["from"]="2025-12-31T16:00:00Z"; req["to"]="2025-12-31T17:00:00Z"
    h:=history("p","interval",[10f]); (([Str:Obj?][])h["samples"])[0]["ts"]="2025-12-31T16:00:00Z"
    r:=run([meter("m","p")],[h],req)
    verifyEq(points(r)[0]["ts"],"2026-01-01T00:00:00+08:00")
    m:=meter("m","p"); m["tariffId"]="t"; t:=rec("t","tariff"); t["mode"]="monthlyBlock"
    t["blocks"]=[[Str:Obj?]["limit":5f,"rate":1f],[Str:Obj?]["limit":null,"rate":2f]]
    req["metric"]="cost"; req["from"]="2026-02-01T00:00:00+08:00"; req["to"]="2026-02-01T01:00:00+08:00"
    (([Str:Obj?][])h["samples"])[0]["ts"]="2026-02-01T00:00:00+08:00"
    r=run([m,t],[h],req); near(value(r),15f)
  }

  Void testExplicitComparisonAndZeroReference()
  {
    req:=request(); req["kind"]="comparison"; req["from"]=ts(1); req["to"]=ts(2); req["otherFrom"]=ts(0); req["otherTo"]=ts(1)
    r:=run([meter("m","p")],[history("p","interval",[0f,15f])],req)
    extra:=(Str:Obj?)r["extra"]; c:=(([Str:Obj?][])extra["comparisons"])[0]
    near((Float?)c["difference"],15f); verifyNull(c["percentage"])
  }

  Void testAnnualTariffAndDashboard()
  {
    start:=DateTime.fromIso(ts(0)); samples:=[Str:Obj?][,]
    (0..<8760).each |i| { samples.add(["ts":(start+Duration(i*1hr.ticks)).toIso,"value":1f]) }
    m:=meter("m","p"); m["tariffId"]="t"; t:=rec("t","tariff"); t["mode"]="yearlyBlock"
    t["blocks"]=[[Str:Obj?]["limit":100f,"rate":1f],[Str:Obj?]["limit":null,"rate":2f]]
    h:=[Str:Obj?]["pointId":"p","unit":"kWh","mode":"interval","samples":samples]
    req:=request(); req["metric"]="cost"; req["period"]="year"; req["to"]="2027-01-01T00:00:00Z"; req["asOf"]=req["to"]
    r:=run([m,t],[h],req); near(value(r),17420f)
    req["kind"]="dashboard"; req["metric"]="energy"; req["to"]=ts(1); req["nodeIds"]=Str[,]
    r=run([m,t],[h],req); near(value(r),1f)
  }

  Void testRegressionUsesRequestedPeriod()
  {
    start:=DateTime.fromIso(ts(0)); energy:=[Str:Obj?][,]; reference:=[Str:Obj?][,]
    (0..<48).each |i|
    {
      at:=(start+Duration(i*1hr.ticks)).toIso
      energy.add(["ts":at,"value":i < 24 ? 3f : 5f]); reference.add(["ts":at,"value":i < 24 ? 10f : 20f])
    }
    req:=request(); req["kind"]="regression"; req["period"]="day"; req["to"]="2026-01-03T00:00:00Z"; req["xId"]="outside"; req["yId"]="m"
    r:=run([meter("m","p")],[[Str:Obj?]["pointId":"p","mode":"interval","samples":energy],[Str:Obj?]["pointId":"outside","mode":"sampled","samples":reference]],req)
    fit:=(Str:Obj?)r["extra"]; verifyEq(fit["count"],2); near((Float?)fit["slope"],4.8f); near((Float?)fit["intercept"],24f)
  }

  Void testKnownUnitConversionAndUnsupportedEnergyHistory()
  {
    g:=rec("g","group"); cat:=rec("electric","category"); cat["unit"]="kWh"
    a:=meter("a","pa","g"); b:=meter("b","pb","g"); b["unit"]="MWh"
    req:=request(); req["nodeIds"]=["g"]
    hb:=history("pb","interval",[0.02f]); hb["unit"]="MWh"
    r:=run([g,cat,a,b],[history("pa","interval",[10f]),hb],req); near(value(r),30f)
    req["nodeIds"]=["a"]
    r=run([a],[history("pa","sampled",[400f])],req); verifyNull(value(r)); verifyEq(quality(r),"notEnergyHistory")
  }

  Void testWorkingHoursIsIndependentOfWorkDays()
  {
    c:=rec("c","calendar"); c["workHours"]=[0]; c["workDays"]=[1,2,3,4,5]
    c["exceptions"]=[[Str:Obj?]["date":"2026-01-03","working":false]]
    req:=request(); req["kind"]="workingHours"; req["from"]="2026-01-03T00:00:00Z"; req["to"]="2026-01-03T01:00:00Z"
    h:=history("p","interval",[10f]); (([Str:Obj?][])h["samples"])[0]["ts"]=req["from"]
    r:=run([meter("m","p"),c],[h],req); row:=(([Str:Obj?][])r["rows"])[0]
    near((Float?)row["working"],10f); near((Float?)row["nonworking"],0f)
  }

  Void testCovAndPartialGaugeAverage()
  {
    sensor:=rec("s","sensor"); sensor["pointId"]="p"
    h:=history("p","cov",[0f,100f,100f]); samples:=([Str:Obj?][])h["samples"]; samples[1]["ts"]="2026-01-01T00:45:00Z"; samples[2]["ts"]=ts(1)
    req:=request(); req["nodeIds"]=["s"]
    r:=run([sensor],[h],req); near(value(r),25f)
    h=history("p","sampled",[10f,20f]); samples=([Str:Obj?][])h["samples"]; samples[0]["ts"]="2026-01-01T00:30:00Z"
    req["from"]="2026-01-01T00:30:00Z"; req["to"]=ts(2); req["period"]="day"
    r=run([sensor],[h],req); near(value(r),50f/3f)
  }

  Void testDefaultTariffCalendarAndMissingCoefficient()
  {
    m:=meter("m","p"); t:=rec("t","tariff"); t["mode"]="flat"; t["rate"]=2f; t["categoryId"]="electric"; t["isDefault"]=true
    req:=request(); req["metric"]="cost"
    r:=run([m,t],[history("p","interval",[10f])],req); near(value(r),20f)
    t["isDefault"]=false; r=run([m,t],[history("p","interval",[10f])],req); verifyNull(value(r)); verifyEq(quality(r),"missingTariff")
    req["metric"]="oil"; req["kind"]="primary"; r=run([m],[history("p","interval",[10f])],req); verifyNull(value(r)); verifyEq(quality(r),"missingCoefficient")
    c1:=rec("c1","calendar"); c1["workHours"]=[1]
    c2:=rec("c2","calendar"); c2["workHours"]=[0]; c2["isDefault"]=true
    req["metric"]="energy"; req["kind"]="workingHours"
    r=run([m,c1,c2],[history("p","interval",[10f])],req); row:=(([Str:Obj?][])r["rows"])[0]; near((Float?)row["working"],10f)
  }

  Void testSameRangeComparisonReferenceIds()
  {
    req:=request(); req["kind"]="comparison"; req["referenceIds"]=["b","outside"]
    r:=run([meter("m","p"),meter("b","pb")],[history("p","interval",[10f]),history("pb","interval",[20f]),history("outside","sampled",[7f])],req)
    verifyEq((([Str:Obj?][])r["series"]).size,3)
    near((Float?)points(r,1)[0]["value"],20f); near((Float?)points(r,2)[0]["value"],7f)
  }

  Void testConfigurationExpressionSyntax()
  {
    verify(EnerCubixExpression.validate("a / (b-b)",["a","b"]))
    verify(!EnerCubixExpression.validate("a++",["a"]))
    verify(!EnerCubixExpression.validate("a/*b",["a","b"]))
    verify(!EnerCubixExpression.validate("(a+b",["a","b"]))
    verify(!EnerCubixExpression.validate("1/0+unknown",["a"]))
    verify(EnerCubixExpression.validate("-a + 1e3 * (b / 2)",["a","b"]))
  }

  Void testProfileReferenceCurveDoesNotEnterEnergyTotals()
  {
    req:=request(); req["referenceIds"]=["outside"]
    r:=run([meter("m","p")],[history("p","interval",[10f]),history("outside","sampled",[23f])],req)
    verifyEq((([Str:Obj?][])r["series"]).size,2); near((Float?)points(r,1)[0]["value"],23f)
    totals:=([Str:Obj?][])((Str:Obj?)r["summary"])["totals"]; verifyEq(totals.size,1); near((Float?)totals[0]["value"],10f)
  }

  Void testDashboardGrandTotalsAcrossCategories()
  {
    g:=rec("g","group"); sub:=rec("sub","group"); sub["parentId"]="g"
    a:=meter("a","pa","g"); a["tariffId"]="te"; a["subcategoryId"]="sca"
    b:=meter("b","pb","sub"); b["categoryId"]="water"; b["unit"]="m³"; b["tariffId"]="tw"; b["subcategoryId"]="scb"
    te:=rec("te","tariff"); te["mode"]="flat"; te["rate"]=2f
    tw:=rec("tw","tariff"); tw["mode"]="flat"; tw["rate"]=3f
    sca:=rec("sca","subcategory"); sca["co2Factor"]=0.5f
    scb:=rec("scb","subcategory"); scb["co2Factor"]=2f
    records:=[g,sub,a,b,te,tw,sca,scb]
    ha:=history("pa","interval",[10f]); hb:=history("pb","interval",[4f]); hb["unit"]="m³"
    req:=request(); req["kind"]="dashboard"; req["metric"]="cost"; req["nodeIds"]=Str[,]
    r:=run(records,[ha,hb],req); extra:=(Str:Obj?)r["extra"]
    verifyEq((([Str:Obj?][])extra["overview"]).size,2)
    totals:=([Str:Obj?][])extra["grandTotals"]; verifyEq(totals.size,1)
    near((Float?)totals[0]["value"],32f); verifyEq(totals[0]["name"],"总费用"); verifyEq(totals[0]["unit"],"元")
    verifyEq(((Str[])totals[0]["sourceIds"]).sort,["pa","pb"])
    req["metric"]="energy"; r=run(records,[ha,hb],req); extra=(Str:Obj?)r["extra"]
    totals=([Str:Obj?][])extra["grandTotals"]; verifyEq(totals.size,2)
    near((Float?)totals.find |t| { t["unit"] == "kWh" }["value"],10f)
    near((Float?)totals.find |t| { t["unit"] == "m³" }["value"],4f)
    verifyEq(totals[0]["name"],"所选对象合计")
    req["metric"]="co2"; r=run(records,[ha,hb],req); extra=(Str:Obj?)r["extra"]
    totals=([Str:Obj?][])extra["grandTotals"]; near((Float?)totals[0]["value"],13f); verifyEq(totals[0]["name"],"总CO₂")
    req["metric"]="cost"; r=run(records,[ha],req); extra=(Str:Obj?)r["extra"]
    totals=([Str:Obj?][])extra["grandTotals"]; verifyNull(totals[0]["value"]); verifyEq(totals[0]["quality"],"missing")
    // Independent series stay visible; the selection union counts each meter once.
    req["nodeIds"]=["g","a"]; r=run(records,[ha,hb],req); extra=(Str:Obj?)r["extra"]
    totals=([Str:Obj?][])extra["grandTotals"]; near((Float?)totals[0]["value"],32f)
  }

  Void testRegressionFitLineEndpointsAndUndefinedFit()
  {
    a:=meter("a","pa"); b:=meter("b","pb")
    req:=request(); req["kind"]="regression"; req["nodeIds"]=["a","b"]; req["xId"]="a"; req["yId"]="b"; req["to"]=ts(3)
    r:=run([a,b],[history("pa","interval",[1f,2f,3f]),history("pb","interval",[3f,5f,7f])],req)
    extra:=(Str:Obj?)r["extra"]; fit:=([Str:Obj?][])extra["fitLine"]
    verifyEq(fit.size,2); near((Float?)fit[0]["x"],1f); near((Float?)fit[0]["y"],3f); near((Float?)fit[1]["x"],3f); near((Float?)fit[1]["y"],7f)
    r=run([a,b],[history("pa","interval",[1f,1f,1f]),history("pb","interval",[3f,5f,7f])],req)
    extra=(Str:Obj?)r["extra"]; verify((([Str:Obj?][])extra["fitLine"]).isEmpty); verifyNull(extra["slope"])
    r=run([a,b],[history("pa","interval",[1f,null,null]),history("pb","interval",[3f,5f,7f])],req)
    extra=(Str:Obj?)r["extra"]; verify((([Str:Obj?][])extra["fitLine"]).isEmpty); verifyEq(extra["count"],1)
  }

  Void testUtilitySharesCombineTheDeduplicatedSelection()
  {
    g:=rec("g","group"); sub:=rec("sub","group"); sub["parentId"]="g"
    a:=meter("a","pa","sub"); a["utilityId"]="u"
    b:=meter("b","pb","sub"); b["utilityId"]="v"
    u:=rec("u","utility"); u["categoryId"]="electric"; v:=rec("v","utility"); v["categoryId"]="electric"
    records:=[g,sub,a,b,u,v]
    req:=request(); req["kind"]="utility"; req["nodeIds"]=["g","sub"]
    r:=run(records,[history("pa","interval",[10f]),history("pb","interval",[30f])],req)
    extra:=(Str:Obj?)r["extra"]; shares:=([Str:Obj?][])extra["utilityShares"]; verifyEq(shares.size,2)
    first:=shares.find |s| {s["utilityId"] == "u"};second:=shares.find |s| {s["utilityId"] == "v"}
    near((Float?)first["percentage"],25f);near((Float?)second["percentage"],75f)
    verifyEq(first["unit"],"kWh");verifyEq(first["categoryId"],"electric");verifyEq(first["quality"],"ok")
    verifyEq(first["meterIds"],["a"])
    r=run(records,[history("pa","interval",[10f])],req);extra=(Str:Obj?)r["extra"];shares=([Str:Obj?][])extra["utilityShares"]
    shares.each |row| {verifyNull(row["percentage"]);verifyEq(row["percentageQuality"],"missing")}
    verifyEq(shares.findAll |row| {row["value"] == 10f}.size,1)
    r=run(records,[history("pa","interval",[0f]),history("pb","interval",[0f])],req);extra=(Str:Obj?)r["extra"];shares=([Str:Obj?][])extra["utilityShares"]
    shares.each |row| {verifyEq(row["value"],0f);verifyNull(row["percentage"]);verifyEq(row["percentageBasis"],"zeroKnownTotal")}
  }

  Void testUtilityMastersAndUnrelatedSubgroups()
  {
    g:=rec("g","group"); child:=rec("child","group"); child["parentId"]="g"
    branch:=meter("branch","pb","g"); branch["utilityId"]="lighting"
    master:=meter("master","pm","g"); master["kind"]="totalMeter"
    childMaster:=meter("childMaster","pc","child"); childMaster["kind"]="totalMeter"
    utility:=rec("lighting","utility"); utility["categoryId"]="electric"
    records:=[g,child,branch,master,childMaster,utility]
    hs:=[history("pb","interval",[144f]),history("pm","interval",[240f]),history("pc","interval",[72f])]
    req:=request(); req["kind"]="utility"; req["nodeIds"]=["g"]
    // Scope membership is identical to ordinary profile selection: its own
    // authoritative master is never replaced by utility-tagged child histories.
    r:=run(records,hs,req);near(value(r),240f);verifyEq(points(r)[0]["sourceIds"],["pm"])
    childMaster["utilityId"]="lighting"
    r=run(records,hs[0..<2],req);near(value(r),240f)
    master["utilityId"]="lighting"
    r=run(records,hs,req);near(value(r),240f);verifyEq(points(r)[0]["sourceIds"],["pm"])
    r=run(records,[hs[0],hs[2]],req);verifyNull(value(r));verifyEq(quality(r),"missing")
    verifyEq(points(r)[0]["sourceIds"],["pm"])
    r=run([g,master,utility],[hs[1]],req);near(value(r),240f)
    req["kind"]="profile"; r=run(records,hs,req); near(value(r),240f)
    req["kind"]="leak"; r=run(records,hs,req); near(value(r),24f)
  }

  Void testBindingAliasesInReferenceTrendAndRegression()
  {
    m:=meter("m","energy")
    runtime:=rec("runtime","binding"); runtime["pointId"]="p"; runtime["role"]="runtime"; runtime["alias"]="其他用途别名"
    binding:=rec("binding","binding"); binding["name"]="温度参考点"; binding["pointId"]="p"; binding["role"]="reference"; binding["alias"]="室外温度"
    req:=request(); req["referenceIds"]=["p"]
    hs:=[history("energy","interval",[3f,5f,7f]),history("p","sampled",[1f,2f,3f])]
    records:=[m,runtime,binding]
    r:=run(records,hs,req); ss:=([Str:Obj?][])r["series"]
    verifyEq(ss[1]["name"],"室外温度"); verifyEq(ss[1]["id"],"p|reference")
    req["kind"]="trend"; req["nodeIds"]=["p"]; req.remove("referenceIds")
    r=run(records,hs,req); ss=([Str:Obj?][])r["series"]
    verifyEq(ss[0]["name"],"室外温度"); verifyEq(ss[0]["id"],"p")
    req["kind"]="regression"; req["xId"]="p"; req["yId"]="m"; req["to"]=ts(3)
    r=run(records,hs,req); extra:=(Str:Obj?)r["extra"]
    verifyEq(extra["xName"],"室外温度"); verifyEq(extra["yName"],"m")
    binding["alias"]=""
    req["kind"]="trend"; r=run(records,hs,req); ss=([Str:Obj?][])r["series"]
    verifyEq(ss[0]["name"],"温度参考点")
    m["alias"]="主表别名"; req["nodeIds"]=["m"]
    r=run(records,hs,req); ss=([Str:Obj?][])r["series"]; verifyEq(ss[0]["name"],"主表别名")
  }

  Void testDailyLoadBandsAreIntervalTotals()
  {
    calendar:=rec("cal","calendar"); calendar["peakHours"]=[0]; calendar["valleyHours"]=[1]
    start:=DateTime.fromIso(ts(0)); samples:=[Str:Obj?][,]
    (0..<48).each |i|
    {
      value:=1f
      if (i == 0) value=10f
      if (i == 1) value=6f
      if (i == 24) value=30f
      if (i == 25) value=14f
      samples.add(["ts":(start+Duration(i*1hr.ticks)).toIso,"value":value])
    }
    h:=[Str:Obj?]["pointId":"p","unit":"kWh","mode":"interval","samples":samples]
    req:=request(); req["kind"]="daily"; req["to"]="2026-01-03T00:00:00Z"
    r:=run([meter("m","p"),calendar],[h],req)
    near(value(r),20f); near(value(r,1),10f)
    verifyEq(points(r)[0]["band"],"peak"); verifyEq(points(r)[1]["band"],"valley"); verifyEq(points(r)[2]["band"],"flat")
    rows:=([Str:Obj?][])r["rows"]; verifyEq(rows[0]["band"],"peak")
    extra:=(Str:Obj?)r["extra"]; bands:=([Str:Obj?][])extra["loadBands"]
    verifyEq(extra["loadBandsAggregation"],"intervalTotal")
    near((Float?)bands.find |b| { b["band"] == "peak" }["value"],40f)
    near((Float?)bands.find |b| { b["band"] == "valley" }["value"],20f)
    near((Float?)bands.find |b| { b["band"] == "flat" }["value"],44f)
    samples[24]["value"]=null
    r=run([meter("m","p"),calendar],[h],req); extra=(Str:Obj?)r["extra"]; bands=([Str:Obj?][])extra["loadBands"]
    peak:=bands.find |b| { b["band"] == "peak" }; verifyNull(peak["value"]); verifyEq(peak["quality"],"missing")
    near((Float?)bands.find |b| { b["band"] == "valley" }["value"],20f)
    req["to"]=ts(1)
    r=run([meter("m","p"),calendar],[h],req); extra=(Str:Obj?)r["extra"]; bands=([Str:Obj?][])extra["loadBands"]
    near((Float?)bands.find |b| { b["band"] == "valley" }["value"],0f)
    near((Float?)bands.find |b| { b["band"] == "flat" }["value"],0f)
  }

  Void testDailyWithoutCalendarUsesUnknownBand()
  {
    req:=request(); req["kind"]="daily"
    r:=run([meter("m","p")],[history("p","interval",[10f])],req)
    verifyEq(points(r)[0]["band"],"unknown")
    verify(!((Str[])r["warnings"]).isEmpty)
    extra:=(Str:Obj?)r["extra"]; bands:=([Str:Obj?][])extra["loadBands"]
    verifyEq(bands.size,1); verifyEq(bands[0]["band"],"unknown"); near((Float?)bands[0]["value"],10f)
    r=run([meter("m","p")],[history("p","interval",[null])],req)
    extra=(Str:Obj?)r["extra"]; bands=([Str:Obj?][])extra["loadBands"]; verifyNull(bands[0]["value"]); verifyEq(bands[0]["quality"],"missing")
  }

  private Str:Obj? run([Str:Obj?][] rs, [Str:Obj?][] hs, [Str:Obj?]? req := null) { EnerCubixEngine.report(req ?: request(),rs,hs) }
  private Str:Obj? request() { ["kind":"profile","nodeIds":["m"],"from":ts(0),"to":ts(1),"period":"hour","metric":"energy","perArea":false,"tz":"UTC"] }
  private Str:Obj? rec(Str id, Str kind) { ["id":id,"kind":kind,"name":id] }
  private Str:Obj? meter(Str id, Str point, Str? parent := null) { ["id":id,"kind":"meter","name":id,"pointId":point,"parentId":parent,"categoryId":"electric","unit":"kWh"] }
  private Str:Obj? history(Str id, Str mode, Float?[] values)
  {
    samples := [Str:Obj?][,]; values.each |Float? v, Int i| { samples.add(["ts":ts(i),"value":v]) }
    return ["pointId":id,"unit":"kWh","mode":mode,"samples":samples]
  }
  private Str ts(Int hour) { "2026-01-01T${hour.toStr.padl(2,'0')}:00:00Z" }
  private [Str:Obj?][] points(Str:Obj? r, Int i := 0) { ([Str:Obj?][])(([Str:Obj?][])r["series"])[i]["points"] }
  private Float? value(Str:Obj? r, Int i := 0) { (Float?)points(r)[i]["value"] }
  private Str quality(Str:Obj? r) { points(r)[0]["quality"].toStr }
  private Void near(Float? actual, Float expected) { verifyNotNull(actual); verify(((Float)actual-expected).abs < 0.000001f,"$actual != $expected") }
}



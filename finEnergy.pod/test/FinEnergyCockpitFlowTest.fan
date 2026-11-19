using util
using haystack

class FinEnergyCockpitFlowTest : Test
{
  Void testOnePreparedUnionKeepsOwnReadingsAndIndependentGraphs()
  {
    calls:=0
    result:=FinEnergyCockpit.execute(request(["t","g1","g2"]),records,|Str:Obj? q,[Str:Obj?][] rs->[Str:Obj?][]|
    {
      calls++; verify(q.isImmutable);verify(rs.isImmutable)
      verifyEq(FinEnergyMath.strings(q["_cockpitPointIds"]),["pa","pb","pg1","pg2","pt"])
      verifyEq(FinEnergyHistory.pointIds(q,rs),["pg1","pg2","pt"])
      verifyEq(FinEnergyMath.maps(q["_cockpitRanges"]).size,1)
      return histories
    },"test",TimeZone.utc,end)
    verifyEq(calls,1)
    verifyEq(((Map)result["boundary"])["sourcePointIds"],["pg1","pg2","pt"])
    verifyEq(((Map)result["capabilities"])["availableFaces"],["space","balance"])
    verifyEq(graphs(result).size,3)
    verifyEq(node(graph(result,"t"),"t")["value"],100f)
    verifyEq(node(graph(result,"g1"),"g1")["value"],40f)
    verifyEq(node(graph(result,"g2"),"g2")["value"],100f)
    verifyEq(node(graph(result,"t"),"t")["knownSubmeter"],100f)
    verifyEq(accounting(result)["canAdd"],false)
    verifyNull(accounting(result)["unionValue"])
    verifyEq(module(result)["status"],"partial")
    verifyNull(energy(result)["value"])
    fixture:=Env.cur.vars["FINENERGY_COCKPIT_FLOW_FIXTURE"]
    if (fixture != null) File.os(fixture).out.writeChars(JsonOutStream.writeJsonToStr(result)).close
  }

  Void testSharedContributionUnionDoesNotAddVirtualOwnValues()
  {
    result:=run(request(["g1","g2"]),records,histories)
    verifyEq(accounting(result)["unionValue"],100f)
    verifyEq(accounting(result)["canAdd"],false)
    verifyEq(accounting(result)["sharedMemberIds"],["a"])
    verifyEq(graph(result,"g1")["sharedMemberIds"],["a"])
    verifyEq(graph(result,"g2")["sharedMemberIds"],["a"])
    verifyEq(graph(result,"g2")["basis"],"calculation")
    verifyEq(((Map)module(result)["data"])["graphIds"],graphs(result).map |g->Str| {g["graphId"].toStr})
  }

  Void testBalanceEvidenceDoesNotExpandKpiBoundary()
  {
    hs:=histories;hs.find |h| {h["pointId"] == "pt"}["intervals"]=[interval(110f)]
    plain:=request(["t"]);plain["modules"]=["kpis","trend"]
    baseline:=run(plain,records,hs)
    result:=run(request(["t"]),records,hs)
    verifyEq(energy(result)["value"],110f)
    verifyEq(energy(result)["value"],energy(baseline)["value"])
    verifyEq(((Map)result["boundary"])["meterIds"],["t"])
    verifyEq(((Map)result["boundary"])["sourcePointIds"],["pt"])
    verifyEq(node(graph(result,"t"),"t")["difference"],10f)
    verifyEq(node(graph(result,"t"),"t")["submeter"],100f)
  }

  Void testMissingVirtualOwnHistoryStaysMissingWithVisibleContribution()
  {
    hs:=histories.findAll |h| {h["pointId"] != "pg1"}
    result:=run(request(["g1"]),records,hs)
    verifyNull(node(graph(result,"g1"),"g1")["value"])
    verifyNull(node(graph(result,"g1"),"g1")["knownValue"])
    verifyEq(node(graph(result,"g1"),"a")["value"],40f)
    verifyEq(accounting(result)["unionValue"],40f)
    verifyNull(energy(result)["value"])
    verifyEq(module(result)["status"],"partial")
  }

  Void testSignedNegativeDifferenceNeverCreatesNegativeFlowWidths()
  {
    hs:=histories;hs.find |h| {h["pointId"] == "pt"}["intervals"]=[interval(90f)]
    result:=run(request(["t"]),records,hs)
    g:=graph(result,"t")
    verifyEq(node(g,"t")["difference"],-10f)
    verifyEq(node(g,"t")["lossEligible"],false)
    verify(FinEnergyMath.maps(g["links"]).all |l| {(Float)l["value"] >= 0f})
    verify(!FinEnergyMath.maps(g["nodes"]).any |n| {n["nodeType"] == "difference"})
  }

  Void testStatisticalViewsNeverBorrowOtherFloorContributions()
  {
    ["space","organization"].each |dim|
    {
      q:=request([dim == "space" ? "f1" : "o1"],dim)
      calls:=0
      result:=FinEnergyCockpit.execute(q,records,|Str:Obj? rq,[Str:Obj?][] rs->[Str:Obj?][]|
      {calls++;verifyEq(rq["_cockpitPointIds"],["pa"]);return histories},"test",TimeZone.utc,end)
      verifyEq(calls,1);verifyEq(graphs(result).size,1)
      g:=graphs(result).first
      verifyEq(g["basis"],dim)
      verifyEq(node(g,dim == "space" ? "f1" : "o1")["value"],40f)
      verify(FinEnergyMath.maps(g["nodes"]).all |n| {n["difference"] == null && n["lossEligible"] != true})
      verify(!FinEnergyMath.maps(g["nodes"]).any |n| {["b","t"].contains(n["nodeId"])})
    }
  }

  Void testHiddenBranchRemainsOpaqueAndCannotInventACompleteGraph()
  {
    rs:=records
    hidden:=meter("hidden-sentinel","secret-point","t","f1","o1").set("name","Private name sentinel").set("_comparisonReadable",false)
    rs=FinEnergyEnergyFlow.visible(rs,rs.dup.add(hidden))
    result:=run(request(["t"]),rs,histories)
    g:=graph(result,"t")
    verifyNull(node(g,"t")["difference"]);verifyEq(node(g,"t")["lossEligible"],false)
    verifyEq(module(result)["status"],"partial")
    text:=JsonOutStream.writeJsonToStr(result)
    verify(!text.contains("hidden-sentinel") && !text.contains("Private name sentinel") && !text.contains("secret-point"))
  }

  Void testContributionBudgetCountsEveryPreparedDeviceBeforeLoad()
  {
    rs:=records.findAll |r| {!["g1","g2","e1","e2","a","b"].contains(r["id"])}
    for (i:=0;i<200;i++) rs.add(meter("m"+i,"p"+i,"t","f1","o1"))
    calls:=0
    try
    {
      FinEnergyCockpit.execute(request(["t"]),rs,|q,saved->[Str:Obj?][]| {calls++;return histories},"test",TimeZone.utc,end)
      fail("Expected contribution meter budget")
    }
    catch (ArgErr e) {verifyEq(e.msg,"cockpitMeterLimit")}
    verifyEq(calls,0)
  }

  Void testFullBranchesAndExactTwoHundredDeviceBudgetArePreserved()
  {
    rs:=records.findAll |r| {!["g1","g2","e1","e2","a","b"].contains(r["id"])}
    hs:=[history("pt",199f)]
    for (i:=0;i<199;i++) {rs.add(meter("m"+i,"p"+i,"t","f1","o1"));hs.add(history("p"+i,1f))}
    result:=run(request(["t"]),rs,hs)
    verifyEq(FinEnergyMath.maps(graph(result,"t")["nodes"]).findAll |n| {n["nodeType"] == "meter"}.size,200)
    verifyEq(node(graph(result,"t"),"t")["submeter"],199f)
  }

  Void testNestedAliasWeightedAndSubtractiveFormulaSemanticsAreReused()
  {
    rs:=records;hs:=histories
    rs.add(meter("a-alias","pa","t","f1","o1"))
    rs.find |r| {r["id"] == "e1"}["variables"]=["a":"a-alias"]
    rs.add(virtualMeter("nested","en","pn")).add(expression("en","x+y",["x":"g1","y":"b"]))
    rs.add(virtualMeter("weighted","ew","pw")).add(expression("ew","2*a",["a":"a"]))
    rs.add(virtualMeter("minus","em","pm")).add(expression("em","a-b",["a":"a","b":"b"]))
    hs.add(history("pn",100f)).add(history("pw",80f)).add(history("pm",-20f))
    result:=run(request(["nested"]),rs,hs)
    verifyEq(graph(result,"nested")["additive"],true)
    verifyEq(accounting(result)["unionValue"],100f)
    verifyEq(graph(result,"nested")["contributionMemberIds"],["a","b"])
    result=run(request(["weighted","minus"]),rs,hs)
    verify(graphs(result).all |g| {g["additive"] == false && g["basis"] == "calculation"})
    verifyEq(node(graph(result,"weighted"),"weighted")["value"],80f)
    verifyEq(node(graph(result,"minus"),"minus")["value"],-20f)
    verifyNull(accounting(result)["unionValue"])
    verify(graphs(result).all |g| {FinEnergyMath.maps(g["links"]).all |l| {(Float)l["value"] >= 0f}})
  }

  Void testMissingOwnPointBindingDoesNotBorrowFormulaPoint()
  {
    rs:=records;rs.find |r| {r["id"] == "g1"}.remove("pointId")
    result:=FinEnergyCockpit.execute(request(["g1"]),rs,|Str:Obj? q,[Str:Obj?][] saved->[Str:Obj?][]|
    {verifyEq(FinEnergyMath.strings(q["_cockpitPointIds"]),["pa"]);return histories},"test",TimeZone.utc,end)
    verifyNull(node(graph(result,"g1"),"g1")["value"])
    verifyEq(node(graph(result,"g1"),"a")["value"],40f)
    verifyEq(((Map)result["boundary"])["sourcePointIds"],Str[,])
  }

  Void testCurrentOnlyFlowSourcesShareComparisonAndTariffUnion()
  {
    rs:=records;rs.find |r| {r["id"] == "t"}["tariffId"]="tariff"
    rs.add(["id":"tariff","kind":"tariff","mode":"monthlyBlock","blocks":[["rate":1f]]])
    q:=request(["t"]);refStart:=start-10day
    q["comparison"]=["mode":"custom","from":refStart.toIso,"to":(refStart+1hr).toIso]
    FinEnergyCockpit.execute(q,rs,|Str:Obj? rq,[Str:Obj?][] saved->[Str:Obj?][]|
    {
      verifyEq(FinEnergyMath.strings(rq["_cockpitPointIds"]),["pa","pb","pt"])
      ranges:=FinEnergyMath.maps(rq["_cockpitRanges"])
      sourceRanges:=ranges.findAll |r| {FinEnergyMath.strings(r["pointIds"]).contains("pa")}
      verifyEq(sourceRanges.size,1);verifyEq(sourceRanges.first["from"],start.toIso);verifyEq(sourceRanges.first["to"],end.toIso)
      verifyEq(ranges.find |r| {FinEnergyMath.strings(r["pointIds"]).contains("pt")}["from"],FinEnergyMath.bucket(start,"month").toIso)
      verifyEq(FinEnergyMath.maps(rq["_cockpitReadRanges"]).size,2)
      return histories
    },"test",TimeZone.utc,end)
  }

  Void testPreparedStreamingHourlyAndGlobalPartialBoundsMatchOriginalHistory()
  {
    q:=request(["t"]);q["time"]=["preset":"custom","period":"day","from":(start+13sec).toIso,"to":(start+2hr+37sec).toIso];q["asOf"]=(start+3hr).toIso
    raw:=HisItem[,]
    for (i:=0;i<1800;i++) raw.add(HisItem(start-1hr+7sec+Duration(i*10sec.ticks),Number(i.toFloat)))
    points:=Str:Dict[:]
    ["pt","pa","pb"].each |id| {points[id]=Etc.makeDict(["id":Ref(id),"point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","kind":"Number"])}
    oracle:=points.keys.map |id->[Str:Obj?]| {FinEnergyHistory.normalize(points[id],raw,start-1hr,start+4hr)}
    expected:=FinEnergyCockpit.execute(q,records,|rq,saved->[Str:Obj?][]| {oracle},"test",TimeZone.utc,start+3hr)
    calls:=0
    actual:=FinEnergyCockpit.execute(q,records,|Str:Obj? rq,[Str:Obj?][] saved->[Str:Obj?][]|
    {
      calls++
      return FinEnergyCockpitStream.prepare(rq,saved,points,Str:Dict[:],|Dict p,Span span,|HisItem| sink|
      {raw.each |item| {if (item.ts >= span.start && item.ts < span.end) sink(item)}},FinEnergyStreamBudget())
    },"test",TimeZone.utc,start+3hr)
    verifyEq(calls,1);verifyEq(energy(actual)["value"],energy(expected)["value"])
    ["t","a","b"].each |id|
    {
      a:=node(graph(actual,"t"),id);e:=node(graph(expected,"t"),id)
      ["value","knownValue","difference","submeter","coveredSeconds","complete"].each |field| {verifyEq(a[field],e[field],field)}
    }
  }

  Void testFlowConfigurationsFreezeBeforeHistoryAndRemainPermissionChecked()
  {
    rs:=records;rs.each |r| {r["mod"]=start.toIso}
    db:=Str:Dict[:];rs.each |r| {db[r["id"].toStr]=Etc.makeDict(["id":Ref(r["id"].toStr),"mod":start])}
    histories.each |h| {db[h["pointId"].toStr]=Etc.makeDict(["id":Ref(h["pointId"].toStr),"mod":start,"point":Marker.val,"his":Marker.val])}
    db["e1"]=Etc.makeDict(["id":Ref("e1"),"mod":start+1sec])
    reads:=0
    try
    {
      FinEnergyCockpit.execute(request(["g1"]),rs,|Str:Obj? q,[Str:Obj?][] saved->[Str:Obj?][]|
      {
        verify(FinEnergyMath.strings(q["_cockpitConfigIds"]).contains("e1"))
        FinEnergyHistory.prepareConfiguration(q,saved,|Str id->Dict?| {db[id]},|Dict p->Bool| {true},|Dict p->Dict| {Etc.emptyDict})
        reads++;return histories
      },"test",TimeZone.utc,end)
      fail("Expected frozen expression conflict")
    }
    catch (FinEnergyHttpErr e) {verifyEq(e.status,409);verifyEq(e.code,"CONFIGURATION_CHANGED")}
    verifyEq(reads,0)
    db["e1"]=Etc.makeDict(["id":Ref("e1"),"mod":start])
    try
    {
      FinEnergyCockpit.execute(request(["g1"]),rs,|Str:Obj? q,[Str:Obj?][] saved->[Str:Obj?][]|
      {
        FinEnergyHistory.prepareConfiguration(q,saved,|Str id->Dict?| {db[id]},|Dict p->Bool| {p.id.id != "e1"},|Dict p->Dict| {Etc.emptyDict})
        reads++;return histories
      },"test",TimeZone.utc,end)
      fail("Expected opaque configuration permission failure")
    }
    catch (FinEnergyHttpErr e) {verifyEq(e.status,403);verifyEq(e.code,"PERMISSION");verify(!e.msg.contains("e1"))}
    verifyEq(reads,0)
  }

  Void testCrossProjectPrimaryRefIsRejectedBeforeAnyLoad()
  {
    rs:=records;rs.find |r| {r["id"] == "t"}["pointId"]="p:other:r:secret"
    calls:=0
    try
    {
      FinEnergyCockpit.execute(request(["t"]),rs,|q,saved->[Str:Obj?][]| {calls++;return histories},"test",TimeZone.utc,end)
      fail("Expected project ref guard")
    }
    catch (ArgErr e) {verifyEq(e.msg,"cockpitRef")}
    verifyEq(calls,0)
  }

  Void testExplicitNestedScopesRetainIndependentGraphsAndFreezeTheirHierarchy()
  {
    q:=request(["site","f1"],"space")
    result:=FinEnergyCockpit.execute(q,records,|Str:Obj? rq,[Str:Obj?][] saved->[Str:Obj?][]|
    {
      refs:=FinEnergyMath.strings(rq["_cockpitConfigIds"])
      verify(refs.contains("site") && refs.contains("f1") && refs.contains("f2"))
      return histories
    },"test",TimeZone.utc,end)
    verifyEq(graphs(result).map |g->Str| {g["objectId"].toStr}.sort,["f1","site"])
    verifyEq(graph(result,"f1")["basis"],"space")
    verifyEq(node(graph(result,"f1"),"f1")["value"],40f)
    q["reportScope"]=["dimension":"space","nodeIds":["site","f1"],"selectionIntent":"range"]
    result=run(q,records,histories)
    verifyEq(graphs(result).map |g->Str| {g["objectId"].toStr},["site"])
  }

  Void testOptionalModuleFailureDoesNotRemoveKpisOrSwallowBudgetErrors()
  {
    rs:=records;rs.find |r| {r["id"] == "c"}["unit"]=""
    result:=run(request(["t"]),rs,histories)
    verifyEq(module(result)["status"],"error")
    verifyEq(((Map)module(result)["error"])["code"],"COCKPIT_MODULE_ERROR")
    verifyNotNull(((Map)result["modules"])["kpis"])
    verify(!((Map)result["reports"]).containsKey("energy-flow"))
    verifyErr(FinEnergyHttpErr#) |->Void|
    {
      FinEnergyCockpit.execute(request(["t"]),records,|q,saved->[Str:Obj?][]| {throw FinEnergyHttpErr(422,"HISTORY_SCAN_LIMIT","cockpitHistoryScanLimit")},"test",TimeZone.utc,end)
    }
  }

  Void testParticipatingUtilityAndExpressionDefinitionsChangeTheFingerprint()
  {
    rs:=records
    rs.find |r| {r["id"] == "a"}["utilityId"]="lighting"
    rs.add(["id":"lighting","kind":"utility","name":"Lighting","categoryId":"c","mod":start.toIso])
    rs.add(["id":"unused-utility","kind":"utility","name":"Unused","categoryId":"c","mod":start.toIso])
    q:=request(["a"]);q["modules"]=["kpis","endUse"]
    first:=run(q,rs,histories)
    refs:=FinEnergyMath.maps(((Map)first["provenance"])["configRefs"])
    verify(refs.any |r| {r["id"] == "lighting"});verify(!refs.any |r| {r["id"] == "unused-utility"})
    rs.find |r| {r["id"] == "lighting"}["name"]="Lights"
    second:=run(q,rs,histories)
    verify(((Map)first["provenance"])["configFingerprint"] != ((Map)second["provenance"])["configFingerprint"])
    verifyEq(energy(first)["value"],energy(second)["value"])
    q=request(["g1"]);q["modules"]=["kpis"]
    first=run(q,rs,histories)
    verify(FinEnergyMath.maps(((Map)first["provenance"])["configRefs"]).any |r| {r["id"] == "e1"})
    rs.find |r| {r["id"] == "e1"}["formula"]="2*a"
    second=run(q,rs,histories)
    verify(((Map)first["provenance"])["configFingerprint"] != ((Map)second["provenance"])["configFingerprint"])
    verifyEq(energy(first)["value"],energy(second)["value"])
  }

  private Str:Obj? run(Str:Obj? q,[Str:Obj?][] rs,[Str:Obj?][] hs)
  {FinEnergyCockpit.execute(q,rs,|rq,saved->[Str:Obj?][]| {hs},"test",TimeZone.utc,end)}
  private Map module(Str:Obj? r) {(Map)((Map)r["modules"])["balance"]}
  private Map report(Str:Obj? r) {(Map)((Map)r["reports"])[((Map)module(r)["data"])["reportRef"]]}
  private Map extra(Str:Obj? r) {(Map)report(r)["extra"]}
  private Map accounting(Str:Obj? r) {(Map)extra(r)["energyFlowAccounting"]}
  private [Str:Obj?][] graphs(Str:Obj? r) {FinEnergyMath.maps(extra(r)["energyFlowGraphs"])}
  private Str:Obj? graph(Str:Obj? r,Str id) {graphs(r).find |g| {g["objectId"] == id} ?: throw Err("Missing graph: $id")}
  private Str:Obj? node(Str:Obj? g,Str id) {FinEnergyMath.maps(g["nodes"]).find |n| {n["nodeId"] == id} ?: throw Err("Missing node: $id")}
  private Map energy(Str:Obj? r) {(Map)((List)((Map)((Map)((Map)r["modules"])["kpis"])["data"])["values"]).first}
  private DateTime start() {DateTime.fromIso("2026-10-19T00:00:00Z")}
  private DateTime end() {start+1hr}
  private Str:Obj? request(Str[] ids,Str dim := "metering")
  {["schemaVersion":1,"requestId":"balance-test","reportScope":["dimension":dim,"nodeIds":ids,"selectionIntent":"explicitObjects"],"focusCategoryId":"c","time":["preset":"custom","period":"hour","from":start.toIso,"to":end.toIso],"asOf":end.toIso,"comparison":["mode":"none"],"modules":["kpis","trend","balance"]]}
  private [Str:Obj?][] records()
  {[["id":"c","kind":"category","name":"Electricity","unit":"kWh"],["id":"site","kind":"space","name":"Site"],["id":"f1","kind":"space","name":"Floor1","parentId":"site"],["id":"f2","kind":"space","name":"Floor2","parentId":"site"],["id":"org","kind":"organization","name":"Organization"],["id":"o1","kind":"organization","name":"Department1","parentId":"org"],["id":"o2","kind":"organization","name":"Department2","parentId":"org"],meter("t","pt",null,"site","org").set("kind","totalMeter"),meter("a","pa","t","f1","o1"),meter("b","pb","t","f2","o2"),virtualMeter("g1","e1","pg1"),virtualMeter("g2","e2","pg2"),expression("e1","a",["a":"a"]),expression("e2","a+b",["a":"a","b":"b"]) ]}
  private Str:Obj? meter(Str id,Str point,Str? parent,Str space,Str org) {["id":id,"kind":"meter","name":id,"pointId":point,"meterParentId":parent,"spaceId":space,"nativeSpaceId":space,"organizationId":org,"categoryId":"c","unit":"kWh"]}
  private Str:Obj? virtualMeter(Str id,Str expr,Str point) {["id":id,"kind":"totalMeter","name":id,"pointId":point,"expressionId":expr,"categoryId":"c","unit":"kWh","includeInTotals":false]}
  private Str:Obj? expression(Str id,Str formula,Str:Str vars) {["id":id,"kind":"expression","formula":formula,"variables":vars]}
  private [Str:Obj?][] histories() {[history("pt",100f),history("pa",40f),history("pb",60f),history("pg1",40f),history("pg2",100f)]}
  private Str:Obj? history(Str point,Float value) {["pointId":point,"unit":"kWh","mode":"interval","intervals":[interval(value)]]}
  private Str:Obj? interval(Float? value) {["from":start.toIso,"to":end.toIso,"value":value,"valueType":value == null ? "null" : "number","quality":value == null ? "missing" : "cleaned"]}
}

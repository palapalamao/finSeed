using util
using haystack

class FinEnergyCockpitEfficiencyTest : Test
{
  Void testTotalRatioPreparedUnionAndUndilutedKpis()
  {
    calls:=0
    result:=FinEnergyCockpit.execute(request,records,|Str:Obj? q,[Str:Obj?][] rs->[Str:Obj?][]|
    {
      calls++;verify(q.isImmutable);verify(rs.isImmutable)
      verifyEq(q["_cockpitPointIds"],["pi","po"])
      verifyEq(FinEnergyMath.maps(q["_cockpitRanges"]).size,1)
      verify(FinEnergyMath.strings(q["_cockpitConfigIds"]).contains("cop"))
      return histories
    },"test",TimeZone.utc,end)
    verifyEq(calls,1);verifyEq(module(result)["status"],"ok")
    item:=items(result).first
    verifyEq(((Map)item["numerator"])["value"],96000f)
    verifyEq(((Map)item["denominator"])["value"],24000f)
    verifyEq(((Map)item["ratio"])["value"],4f) // mean of hourly COPs is 5, not 4
    verifyEq(((Map)item["numerator"])["unit"],"kWh")
    verifyEq(((Map)item["ratio"])["sourceIds"],["po","pi"])
    verifyEq(item["from"],start.toIso);verifyEq(item["to"],end.toIso)
    verifyEq(((Map)item["configRef"])["mod"],start.toIso)
    verifyEq(item["baselineEfficiency"],3.5f)
    verifyEq(energy(result)["value"],24000f)
    verifyEq(((Map)result["boundary"])["sourcePointIds"],["pi"])
    verifyEq(((Map)result["capabilities"])["availableFaces"],["space","efficiency"])
    verifyNotNull(((Map)result["reports"])[item["reportRef"]])
    fixture:=Env.cur.vars["FINENERGY_COCKPIT_EFFICIENCY_FIXTURE"]
    if (fixture != null) File.os(fixture).out.writeChars(JsonOutStream.writeJsonToStr(result)).close
  }

  Void testMissingZeroUnitsBoundariesAndCoverageNeverBecomeRatios()
  {
    hs:=histories.findAll |h| {h["pointId"] != "po"}
    verifyUnavailable(run(records,hs),"missing")
    hs=histories;hs.find |h| {h["pointId"] == "pi"}["samples"]=[sample(start,0f),sample(start+1hr,0f)]
    verifyUnavailable(run(records,hs),"divisionByZero")
    rs:=records;rs.find |r| {r["id"] == "heat"}["unit"]="m³"
    verifyUnavailable(run(rs,histories),"COP_INCOMPATIBLE_UNITS")
    rs=records;rs.find |r| {r["id"] == "out"}["areaSpaceId"]="elsewhere"
    verifyUnavailable(run(rs,histories),"COP_BOUNDARY_MISMATCH")
    hs=histories;hs.find |h| {h["pointId"] == "po"}["samples"]=[sample(start,48000f)]
    verifyUnavailable(run(records,hs),"missing")
    hs=histories;hs.find |h| {h["pointId"] == "po"}["quality"]="streamingUnsupportedConfiguration"
    verifyUnavailable(run(records,hs),"streamingUnsupportedConfiguration")
  }

  Void testUnitConversionAndNoConfiguration()
  {
    rs:=records;rs.find |r| {r["id"] == "heat"}["unit"]="MWh"
    result:=run(rs,histories)
    verifyEq(((Map)items(result).first["numerator"])["value"],96f)
    verifyEq(((Map)items(result).first["ratio"])["value"],4f)
    result=run(records.findAll |r| {r["kind"] != "cop"},histories)
    verifyEq(module(result)["status"],"unavailable")
    verifyEq(module(result)["reasonCodes"],["COP_NOT_CONFIGURED"])
    verifyEq(items(result).size,0);verifyEq(energy(result)["value"],24000f)
  }

  Void testCategoriesAndConfigurationBudgetBeforeLoad()
  {
    rs:=records;rs.add(["id":"water","kind":"category","unit":"m³"])
    q:=request;q["auxiliaryCategoryId"]="water"
    result:=FinEnergyCockpit.execute(q,rs,|Str:Obj? rq,[Str:Obj?][] saved->[Str:Obj?][]|
    {verifyEq(rq["_cockpitPointIds"],["pi"]);return histories},"test",TimeZone.utc,end)
    verifyUnavailable(result,"COP_CATEGORY_LIMIT")
    rs=records
    for (i:=1;i<20;i++) rs.add(cop("cop"+i))
    verifyEq(items(run(rs,histories)).size,20)
    rs.add(cop("cop20"));calls:=0
    try
    {
      FinEnergyCockpit.execute(request,rs,|rq,saved->[Str:Obj?][]| {calls++;return histories},"test",TimeZone.utc,end)
      fail("Expected configuration limit")
    }
    catch (FinEnergyHttpErr e) {verifyEq(e.code,"COP_CONFIGURATION_LIMIT")}
    verifyEq(calls,0)
  }

  Void testOpaqueHiddenAndUnrelatedConfigsAndOwnPrimaryOnly()
  {
    rs:=records;rs.add(cop("hidden-sentinel").set("name","Private sentinel").set("_comparisonReadable",false))
    rs.add(meter("unrelated","pu","elec","other-site"));rs.add(cop("unrelated-cop").set("denominatorId","unrelated").set("numeratorId","unrelated"))
    result:=run(rs,histories)
    verifyEq(items(result).size,1)
    text:=JsonOutStream.writeJsonToStr(result)
    verify(!text.contains("hidden-sentinel") && !text.contains("Private sentinel") && !text.contains("unrelated-cop"))
    rs=records;rs.find |r| {r["id"] == "out"}["_comparisonReadable"]=false
    result=run(rs,histories)
    verifyEq(items(result).size,0)
    verify(!JsonOutStream.writeJsonToStr(result).contains("\"po\""))
    rs=records;rs.find |r| {r["id"] == "out"}.remove("pointId")
    rs.find |r| {r["id"] == "out"}.setAll(["expressionId":"expr","autoSum":true])
    rs.add(["id":"expr","kind":"expression","formula":"a","variables":["a":"in"]])
    result=FinEnergyCockpit.execute(request,rs,|Str:Obj? rq,[Str:Obj?][] saved->[Str:Obj?][]|
    {verifyEq(rq["_cockpitPointIds"],["pi"]);return histories},"test",TimeZone.utc,end)
    verifyUnavailable(result,"COP_PRIMARY_REQUIRED")
  }

  Void testInstallationOnlyCannotProveServiceCoverage()
  {
    rs:=records
    ["in","out"].each |id| {r:=rs.find |r| {r["id"] == id};r.remove("areaSource");r.remove("areaSpaceId");r.remove("spaceId")}
    verifyUnavailable(run(rs,histories),"COP_BOUNDARY_MISMATCH")
  }

  Void testStreamingAndRawUseExactlyTheSameRatioAndQuantities()
  {
    q:=request;q["time"]=["preset":"custom","period":"day","from":(start+13sec).toIso,"to":(start+2hr+37sec).toIso];q["asOf"]=(start+3hr).toIso
    raw:=HisItem[,]
    for (i:=0;i<1800;i++) raw.add(HisItem(start-1hr+7sec+Duration(i*10sec.ticks),Number(i.toFloat)))
    points:=Str:Dict[:]
    ["pi","po"].each |id| {points[id]=Etc.makeDict(["id":Ref(id),"point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"])}
    whole:=points.vals.map |p->[Str:Obj?]| {FinEnergyHistory.normalize(p,raw,start,start+4hr)}
    expected:=FinEnergyCockpit.execute(q,records,|rq,saved->[Str:Obj?][]| {whole},"test",TimeZone.utc,start+4hr)
    streamed:=FinEnergyCockpit.execute(q,records,|Str:Obj? rq,[Str:Obj?][] saved->[Str:Obj?][]|
    {FinEnergyCockpitStream.prepare(rq,saved,points,Str:Dict[:],|Dict p,Span span,|HisItem| sink| {raw.each |item| {if (item.ts >= span.start && item.ts < span.end) sink(item)}},FinEnergyStreamBudget(137,200000,20000000,30min))},"test",TimeZone.utc,start+4hr)
    ["numerator","denominator","ratio"].each |key|
    {actual:=((Map)items(streamed).first[key]).dup;oracle:=((Map)items(expected).first[key]).dup;actual.remove("boundaryId");oracle.remove("boundaryId");verifyEq(actual,oracle)}
    verifyEq(((Map)items(streamed).first["ratio"])["value"],1f)
  }

  Void testCopAndServiceRevisionsFreezeBeforeHistoryAndStayAuthoritative()
  {
    db:=Str:Dict[:]
    records.each |r| {fields:=Str:Obj?["id":Ref(r["id"].toStr)];if (r["mod"] != null) fields["mod"]=DateTime.fromIso(r["mod"].toStr);db[r["id"].toStr]=Etc.makeDict(fields)}
    ["pi","po"].each |id| {db[id]=Etc.makeDict(["id":Ref(id),"mod":start,"point":Marker.val,"his":Marker.val])}
    reads:=0
    try
    {
      FinEnergyCockpit.execute(request,records,|Str:Obj? q,[Str:Obj?][] rs->[Str:Obj?][]|
      {
        db["cop"]=Etc.makeDict(["id":Ref("cop"),"mod":start+1sec])
        FinEnergyHistory.prepareConfiguration(q,rs,|Str id->Dict?| {db[id]},|Dict r->Bool| {true},|Dict r->Dict| {Etc.emptyDict})
        reads++;return histories
      },"test",TimeZone.utc,end)
      fail("Expected frozen COP conflict")
    }
    catch (FinEnergyHttpErr e) {verifyEq(e.code,"CONFIGURATION_CHANGED")}
    verifyEq(reads,0)
    db["cop"]=Etc.makeDict(["id":Ref("cop"),"mod":start])
    result:=FinEnergyCockpit.execute(request,records,|Str:Obj? q,[Str:Obj?][] rs->[Str:Obj?][]|
    {
      FinEnergyHistory.prepareConfiguration(q,rs,|Str id->Dict?| {db[id]},|Dict r->Bool| {true},|Dict r->Dict| {Etc.emptyDict})
      db["cop"]=Etc.makeDict(["id":Ref("cop"),"mod":start+1sec])
      return histories
    },"test",TimeZone.utc,end)
    verifyEq(((Map)items(result).first["ratio"])["value"],4f)
    verifyEq(((Map)items(result).first["configRef"])["mod"],start.toIso)
    verifyErr(FinEnergyHttpErr#) |->Void|
    {
      FinEnergyCockpit.execute(request,records,|rq,rs->[Str:Obj?][]| {throw FinEnergyHttpErr(422,"HISTORY_SCAN_LIMIT","cockpitHistoryScanLimit")},"test",TimeZone.utc,end)
    }
  }

  Void testMissingCategoryAndFilteredCoverageFailClosed()
  {
    result:=run(records.findAll |r| {r["id"] != "heat"},histories)
    verifyUnavailable(result,"COP_INVALID_CONFIGURATION")
    hs:=histories;hs.find |h| {h["pointId"] == "po"}["intervals"]=[["from":start.toIso,"to":(start+1hr).toIso,"value":null,"quality":"filtered"],["from":(start+1hr).toIso,"to":end.toIso,"value":48000f,"quality":"ok"]]
    result=run(records,hs)
    verifyNull(((Map)items(result).first["ratio"])["value"])
    verifyEq(((Map)items(result).first["numerator"])["valueBasis"],"unavailable")
  }

  Void testGroupCopUsesExistingFrontierAndCountsOriginalDevices()
  {
    rs:=records;rs.find |r| {r["id"] == "cop"}["numeratorId"]="group"
    rs.add(["id":"group","kind":"group","name":"Output group"])
    rs.find |r| {r["id"] == "out"}["parentId"]="group"
    verifyEq(((Map)items(run(rs,histories)).first["ratio"])["value"],4f)
    // A configured master still uses only its own primary; its children must
    // count toward the request's original-device admission budget.
    rs.find |r| {r["id"] == "out"}["kind"]="totalMeter"
    for (i:=0;i<199;i++) rs.add(meter("child"+i,"pc"+i,"heat").set("parentId","group"))
    calls:=0
    try
    {
      FinEnergyCockpit.execute(request,rs,|rq,saved->[Str:Obj?][]| {calls++;return histories},"test",TimeZone.utc,end)
      fail("Expected original-device budget")
    }
    catch (ArgErr e) {verifyEq(e.msg,"cockpitMeterLimit")}
    verifyEq(calls,0)
  }

  Void testHiddenGroupMemberCannotProduceACompleteCopOrLeakIdentity()
  {
    rs:=records;rs.find |r| {r["id"] == "cop"}["numeratorId"]="group"
    rs.add(["id":"group","kind":"group","name":"Output group"])
    rs.find |r| {r["id"] == "out"}["parentId"]="group"
    hidden:=meter("hidden-sentinel","hidden-point","heat").set("parentId","group").set("_comparisonReadable",false)
    projected:=FinEnergyCockpitEfficiency.visible(rs,rs.dup.add(hidden))
    result:=run(projected,histories)
    verifyUnavailable(result,"COP_BOUNDARY_UNAVAILABLE")
    text:=JsonOutStream.writeJsonToStr(result)
    verify(!text.contains("hidden-sentinel") && !text.contains("hidden-point"))
  }

  Void testMalformedOptionalConfigurationDoesNotEraseEnergy()
  {
    rs:=records;rs.find |r| {r["id"] == "cop"}["id"]="p:other:r:cop"
    result:=run(rs,histories)
    verifyEq(module(result)["status"],"error")
    verifyEq(((Map)module(result)["error"])["code"],"COCKPIT_MODULE_ERROR")
    verifyEq(energy(result)["value"],24000f)
    verify(!JsonOutStream.writeJsonToStr(result).contains("p:other:r:cop"))
  }

  Void testCopSourcesOnlyUseCurrentRangeWhenEnergyHasAComparison()
  {
    q:=request;q["comparison"]=["mode":"custom","from":(start-10day).toIso,"to":(end-10day).toIso]
    FinEnergyCockpit.execute(q,records,|Str:Obj? rq,[Str:Obj?][] saved->[Str:Obj?][]|
    {
      outputRanges:=FinEnergyMath.maps(rq["_cockpitRanges"]).findAll |r| {FinEnergyMath.strings(r["pointIds"]).contains("po")}
      verifyEq(outputRanges.size,1);verifyEq(outputRanges.first["from"],start.toIso);verifyEq(outputRanges.first["to"],end.toIso)
      verifyEq(FinEnergyMath.maps(rq["_cockpitReadRanges"]).size,2)
      return histories
    },"test",TimeZone.utc,end)
  }

  private Void verifyUnavailable(Str:Obj? r,Str reason)
  {item:=items(r).first;verifyNull(((Map)item["ratio"])["value"]);verify(((List)((Map)item["ratio"])["reasonCodes"]).contains(reason));verifyEq(energy(r)["value"],reason == "divisionByZero" ? 0f : 24000f)}
  private Str:Obj? run([Str:Obj?][] rs,[Str:Obj?][] hs) {FinEnergyCockpit.execute(request,rs,|q,saved->[Str:Obj?][]| {hs},"test",TimeZone.utc,end)}
  private Map module(Str:Obj? r) {(Map)((Map)r["modules"])["efficiency"]}
  private [Str:Obj?][] items(Str:Obj? r) {FinEnergyMath.maps(((Map)module(r)["data"])["items"])}
  private Map energy(Str:Obj? r) {(Map)((List)((Map)((Map)((Map)r["modules"])["kpis"])["data"])["values"]).first}
  private DateTime start() {DateTime.fromIso("2026-10-01T00:00:00Z")}
  private DateTime end() {start+2hr}
  private Str:Obj? request() {["schemaVersion":1,"requestId":"efficiency-test","reportScope":["dimension":"metering","nodeIds":["in"],"selectionIntent":"range"],"focusCategoryId":"elec","time":["preset":"custom","period":"hour","from":start.toIso,"to":end.toIso],"asOf":end.toIso,"comparison":["mode":"none"],"modules":["kpis","efficiency"]]}
  private Str:Obj? meter(Str id,Str point,Str cat,Str space := "plant") {["id":id,"name":id,"kind":"meter","categoryId":cat,"pointId":point,"nativeSpaceId":space,"spaceId":space,"areaSource":"space","areaSpaceId":space,"unit":"kWh","mod":start.toIso]}
  private Str:Obj? cop(Str id := "cop") {["id":id,"name":"Plant COP","kind":"cop","numeratorId":"out","denominatorId":"in","mod":start.toIso,"baselineEfficiency":3.5f]}
  private [Str:Obj?][] records() {[ ["id":"elec","kind":"category","unit":"kWh"],["id":"heat","kind":"category","unit":"kWh"],["id":"plant","kind":"space","name":"Plant","nativeSourceId":"plant","nativeSourceKind":"floor"],meter("in","pi","elec"),meter("out","po","heat"),cop ]}
  private [Str:Obj?][] histories() {[ ["pointId":"pi","unit":"kWh","mode":"interval","samples":[sample(start,6000f),sample(start+1hr,18000f)]],["pointId":"po","unit":"kWh","mode":"interval","samples":[sample(start,48000f),sample(start+1hr,48000f)]] ]}
  private Str:Obj? sample(DateTime t,Float value) {["ts":t.toIso,"value":value]}
}

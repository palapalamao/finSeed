using util

class FinEnergyCockpitIssuesTest : Test
{
  Void testOneObservationPreservesEpisodeAckAndIndependentHourlyEvidence()
  {
    count:=0;loads:=0;rs:=records
    rs.find |r| {r["id"] == "sub"}.remove("co2Factor")
    es:=[event("event",-6).set("state","acknowledged").set("ackAt",(start-4hr).toIso).set("ackBy","operator")]
    es.first["hours"]=(0..<5).map |i->[Str:Obj?]| {["ts":(start-6hr+1hr*i).toIso,"value":12f,"unit":"kWh","limit":10f,"quality":"ok"]}
    es.first["lastTs"]=(start-2hr).toIso
    result:=FinEnergyCockpit.execute(request,rs,|q,saved->[Str:Obj?][]| {loads++;return histories},"test",TimeZone.utc,end,false,|->DateTime| {observed},|->[Str:Obj?][]| {count++;return es})
    verifyEq(count,1);verifyEq(loads,1)
    data:=data(result);items:=FinEnergyMath.maps(data["items"])
    verifyEq(items.size,1);verifyEq(data["activeEventCount"],1f)
    verifyEq(data["stateObservedAt"],observed.toIso)
    item:=items.first;verifyEq(item["id"],"event");verifyEq(item["episodeId"],"event")
    verifyEq(item["type"],"energyAlarm");verifyEq(item["nativeAlarmId"],"event_offNormal")
    verifyEq(item["active"],true);verifyEq(item["acknowledged"],true)
    verifyEq(item["hourCount"],5);verifyEq(((List)item["hours"]).size,5)
    verifyEq(item["evidenceFrom"],(start-6hr).toIso);verifyEq(item["evidenceTo"],(start-1hr).toIso)
    evidence:=(Map)((Map)item["evidenceTarget"])["request"]
    verifyEq(evidence["period"],"hour");verifyEq(evidence["nodeIds"],["a"])
    verifyEq(evidence["asOf"],observed.toIso)
    verifyEq(((Map)((Map)result["context"])["time"])["from"],start.toIso)
    values:=FinEnergyMath.maps(((Map)((Map)((Map)result["modules"])["kpis"])["data"])["values"])
    verifyEq(values.find |v| {v["id"] == "activeAlarms"}["value"],data["activeEventCount"])
    verifyEq(data["topIds"],["event"])
    fixture:=Env.cur.vars["FINENERGY_COCKPIT_ISSUES_FIXTURE"]
    if (fixture != null) File.os(fixture).out.writeChars(JsonOutStream.writeJsonToStr(result)).close
  }

  Void testDedupStableOrderCurrentStatusAndRuleClueDistinction()
  {
    a:=event("older",-8);a["severity"]=2
    b:=event("severe",-3);b["severity"]=9
    child:=event("child",-2).set("episodeId","older")
    clue:=event("legacy",-10);clue.remove("nativeAlarmId")
    closed:=event("closed",-9).set("nativeActive",false).set("recoveredAt",(start-8hr).toIso)
    result:=run(records,histories,[clue,child,closed,b,a])
    items:=FinEnergyMath.maps(data(result)["items"])
    verifyEq(items.map |i->Str| {i["id"].toStr},["severe","older","legacy"])
    verifyEq(items.last["type"],"ruleClue");verifyEq(data(result)["activeEventCount"],3f)
    verifyEq(data(run(records,histories,[a,b,clue,closed,child]))["topIds"],data(result)["topIds"])
    verifyEq(((Map)items.first["nativeDetail"])["reasonCode"],"NATIVE_ALARM_DEEP_LINK_UNAVAILABLE")
  }

  Void testSourcesObjectCategoryAndProjectAreValidatedWithoutLeakingMetadata()
  {
    rs:=records
    rs.add(["id":"hidden","kind":"meter","pointId":"hidden-point","categoryId":"c","spaceId":"s","_comparisonReadable":false])
    hidden:=event("hidden-event",-1).set("sourceIds",["p","hidden-point"]).set("name","Secret sentinel")
    badNode:=event("bad-node",-1).set("nodeId","hidden")
    foreign:=event("p:other:r:event",-1)
    foreignAlarm:=event("foreign-alarm",-1).set("nativeAlarmId","p:other:r:native")
    foreignCategory:=event("foreign-category",-1).set("categoryId","other")
    safe:=event("safe",-1)
    r:=run(rs,histories,[hidden,badNode,foreign,foreignAlarm,foreignCategory,safe])
    text:=JsonOutStream.writeJsonToStr(data(r))
    verifyEq(FinEnergyMath.maps(data(r)["items"]).map |i->Str| {i["id"].toStr},["safe"])
    ["Secret sentinel","hidden-point","p:other","bad-node","foreign-category"].each |s| {verify(!text.contains(s))}
    verifyEq(data(r)["activeEventCount"],1f)
  }

  Void testQualityKeepsZeroNaAndMissingSeparateWithNoInventedAlarm()
  {
    hs:=histories;hs.first["samples"]=[["ts":start.toIso,"value":0f]]
    result:=run(records,hs,[Str:Obj?][,]);items:=FinEnergyMath.maps(data(result)["items"])
    verify(items.size > 0);verify(items.all |i| {i["type"] == "dataQuality"})
    verify(items.all |i| {i["active"] == null && i["acknowledged"] == null && i["nativeAlarmId"] == null})
    issue:=items.find |i| {i["metricId"] == "energy"}
    verifyEq(issue["actual"],0f);verifyEq(issue["valueType"],"number")
    verifyEq(((Map)issue["evidenceTarget"])["kind"],"profile")
    hs.first["samples"]=[["ts":start.toIso,"value":null,"valueType":"na","quality":"na"],["ts":(start+1hr).toIso,"value":null,"valueType":"na","quality":"na"]]
    result=run(records,hs,[Str:Obj?][,]);issue=FinEnergyMath.maps(data(result)["items"]).find |i| {i["metricId"] == "energy"}
    verifyNull(issue["actual"]);verifyEq(issue["valueType"],"na")
    verifyEq(data(result)["activeEventCount"],0f)
  }

  Void testUnavailableEventReadDoesNotImplyZeroAndBudgetErrorsPropagate()
  {
    result:=FinEnergyCockpit.execute(request,records,|q,rs->[Str:Obj?][]| {histories},"test",TimeZone.utc,end,false,|->DateTime| {observed},|->[Str:Obj?][]| {throw IOErr("secret internal error")})
    verifyEq(module(result)["status"],"partial");verifyNull(data(result)["activeEventCount"])
    verify(((List)module(result)["reasonCodes"]).contains("ACTIVE_EVENTS_READ_ERROR"))
    verify(!JsonOutStream.writeJsonToStr(result).contains("secret internal error"))
    try
    {
      FinEnergyCockpit.execute(request,records,|q,rs->[Str:Obj?][]| {histories},"test",TimeZone.utc,end,false,null,|->[Str:Obj?][]| {throw FinEnergyHttpErr(403,"PERMISSION","denied")})
      fail("Expected permission error")
    }
    catch (FinEnergyHttpErr e) {verifyEq(e.status,403)}
  }

  Void testIssuesOnlyReadsOnceWithoutKpiAndMissingNativeStatusIsOpaque()
  {
    q:=request;q["modules"]=["issues"];count:=0
    result:=FinEnergyCockpit.execute(q,records,|rq,rs->[Str:Obj?][]| {histories},"test",TimeZone.utc,end,false,|->DateTime| {observed},|->[Str:Obj?][]| {count++;return [event("removed",-2).set("nativeAlarmMissing",true)]})
    verifyEq(count,1);verifyNull(data(result)["activeEventCount"])
    verifyEq(module(result)["status"],"partial")
    verify(FinEnergyMath.maps(data(result)["items"]).all |i| {i["type"] != "energyAlarm"})
    verifyNull(((Map)result["modules"])["kpis"])
  }

  Void testGroupEventRequiresWholeReadableBoundaryAndDoesNotMutateInput()
  {
    rs:=records;rs.add(["id":"g","kind":"group","name":"Group"])
    rs.find |r| {r["id"] == "a"}["parentId"]="g"
    es:=[event("group-event",-2).set("nodeId","g")]
    before:=JsonOutStream.writeJsonToStr(es)
    result:=run(rs,histories,es)
    verifyEq(FinEnergyMath.maps(data(result)["items"]).first["id"],"group-event")
    verifyEq(JsonOutStream.writeJsonToStr(es),before)
    rs.add(["id":"outside","kind":"meter","pointId":"outside-p","categoryId":"c","parentId":"g"])
    result=run(rs,histories,es)
    verify(FinEnergyMath.maps(data(result)["items"]).all |i| {i["id"] != "group-event"})
    verifyEq(data(result)["activeEventCount"],0f)
  }

  Void testDisabledEventsStayUnreadAndBadEvidenceIsUnavailable()
  {
    q:=request;q["modules"]=["trend"];count:=0
    FinEnergyCockpit.execute(q,records,|rq,rs->[Str:Obj?][]| {histories},"test",TimeZone.utc,end,false,null,|->[Str:Obj?][]| {count++;return [event("e",-2)]})
    verifyEq(count,0)
    bad:=event("e",-2).set("episodeStartTs","not-an-instant")
    result:=run(records,histories,[bad])
    item:=FinEnergyMath.maps(data(result)["items"]).first
    verifyNull(item["evidenceTarget"]);verifyEq(item["reasonCodes"],["EVENT_EVIDENCE_UNAVAILABLE"])
    result=FinEnergyCockpit.execute(request,records,|rq,rs->[Str:Obj?][]| {histories},"test",TimeZone.utc,end,false,null,|->[Str:Obj?][]| {throw Err("internal provider failure")})
    verifyNull(data(result)["activeEventCount"])
    verifyEq(module(result)["reasonCodes"],["ACTIVE_EVENTS_READ_ERROR"])
  }

  Void testSelectingOwnTotalDoesNotWidenEventOrEnergyBoundaryToDescendants()
  {
    rs:=records;rs.find |r| {r["id"] == "a"}["kind"]="totalMeter"
    rs.add(["id":"child","kind":"meter","pointId":"pc","categoryId":"c","meterParentId":"a"])
    child:=event("child-event",-2).set("nodeId","child").set("sourceIds",["pc"])
    result:=run(rs,histories,[event("total-event",-2),child])
    verifyEq(FinEnergyMath.maps(data(result)["items"]).findAll |i| {i["type"] != "dataQuality"}.map |i->Str| {i["id"].toStr},["total-event"])
    verifyEq(data(result)["activeEventCount"],1f)
    scope:=(Map)data(result)["eventScope"]
    verifyEq(scope["basis"],"selectedObjectsAndEffectiveMeters")
    verifyEq(scope["objectIds"],["a"]);verifyEq(scope["meterIds"],["a"])
    verifyEq(((Map)result["boundary"])["sourcePointIds"],["p"])
  }

  Void testRuntimeEventSourcePermissionsAreCheckedOnceWithoutReadingAlarmIdAsFolio()
  {
    seen:=Str:Int[:]
    safe:=event("safe",-2);denied:=event("denied",-1).set("sourceIds",["hidden-source"])
    foreign:=event("foreign",-1).set("sourceIds",["p:other:r:source"])
    events:=FinEnergyCockpitIssues.readableEvents([safe,denied,foreign],"test") |id->Bool|
    {seen[id]=(seen[id] ?: 0)+1;return id != "hidden-source"}
    verifyEq(events,[safe]);verifyEq(seen["a"],1);verifyEq(seen["c"],1)
    verifyEq(seen["hidden-source"],1);verify(!seen.containsKey("p:other:r:source"))
    verify(!seen.containsKey("safe_offNormal"))
  }

  private Str:Obj? run([Str:Obj?][] rs,[Str:Obj?][] hs,[Str:Obj?][] events)
  {FinEnergyCockpit.execute(request,rs,|q,saved->[Str:Obj?][]| {hs},"test",TimeZone.utc,end,false,|->DateTime| {observed},|->[Str:Obj?][]| {events})}
  private Map module(Str:Obj? r) {(Map)((Map)r["modules"])["issues"]}
  private Map data(Str:Obj? r) {(Map)module(r)["data"]}
  private DateTime start() {DateTime.fromIso("2026-10-01T00:00:00Z")}
  private DateTime end() {start+2hr}
  private DateTime observed() {end+30day}
  private Str:Obj? request() {["schemaVersion":1,"requestId":"issues-test","reportScope":["dimension":"metering","nodeIds":["a"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"hour","from":start.toIso,"to":end.toIso],"asOf":end.toIso,"comparison":["mode":"none"],"modules":["kpis","issues"]]}
  private [Str:Obj?][] records() {[["id":"c","kind":"category","unit":"kWh"],["id":"tariff","kind":"tariff","mode":"flat","rate":1f,"currency":"CNY"],["id":"sub","kind":"subcategory","categoryId":"c","co2Factor":0.5f],["id":"s","kind":"space","name":"Building"],["id":"a","kind":"meter","name":"Meter A","pointId":"p","categoryId":"c","subcategoryId":"sub","spaceId":"s","tariffId":"tariff","areaSource":"custom","area":1000f]]}
  private [Str:Obj?][] histories() {[["pointId":"p","unit":"kWh","mode":"interval","samples":[["ts":start.toIso,"value":5f],["ts":(start+1hr).toIso,"value":5f]]]]}
  private Str:Obj? event(Str id,Int hour) {["id":id,"episodeId":id,"nodeId":"a","categoryId":"c","ts":(start+1hr*hour).toIso,"lastTs":(start+1hr*hour).toIso,"value":12f,"limit":10f,"unit":"kWh","quality":"ok","nativeAlarmId":id+"_offNormal","nativeActive":true,"state":"open","sourceIds":["p"]]}
}

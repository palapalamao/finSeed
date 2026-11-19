using util

class FinEnergyCockpitFacesTest : Test
{
  Void testEndUseRetainsTheCanonicalMasterOwnReadingRatherThanExpandingLeaves()
  {
    rs:=records;rs.findAll |r| {["a","b"].contains(r["id"])}.each |r| {r["meterParentId"]="t"}
    rs.add(["id":"t","kind":"totalMeter","name":"Master","pointId":"pt","categoryId":"c","utilityId":"masterUse"])
    rs.add(["id":"masterUse","kind":"utility","name":"Master use","categoryId":"c"])
    hs:=["pt","pa","pb"].map |id,Int i->[Str:Obj?]| {return ["pointId":id,"mode":"cumulative","unit":"kWh","intervalSeconds":3600f,"samples":[["ts":start.toIso,"value":0f],["ts":(start+1hr).toIso,"value":[100f,40f,50f][i]]]]}
    q:=request;q["reportScope"]=["dimension":"metering","nodeIds":["t"],"selectionIntent":"range"];q["time"]=["preset":"custom","period":"hour","from":start.toIso,"to":(start+1hr).toIso];q["asOf"]=(start+1hr).toIso
    result:=FinEnergyCockpit.execute(q,rs,|Str:Obj? x,[Str:Obj?][] saved->[Str:Obj?][]| {hs},"test",TimeZone.utc,start+1hr)
    boundary:=(Map)result["boundary"];verifyEq(boundary["meterIds"],["t"])
    kpis:=FinEnergyMath.maps(((Map)((Map)((Map)result["modules"])["kpis"])["data"])["values"])
    verifyEq(kpis.find |m| {m["id"]=="energy"}["value"],100f)
    uses:=(Map)((Map)((Map)result["modules"])["endUse"])["data"]
    verifyEq(uses["meterIds"],["t"])
    report:=(Map)((Map)result["reports"])[uses["reportRef"]];extra:=(Map)report["extra"]
    verifyEq(FinEnergyMath.maps(extra["utilityMembers"]).map |m->Str| {m["nodeId"].toStr},["t"])
    shares:=FinEnergyMath.maps(extra["utilityShares"]);verifyEq(shares.size,1);verifyEq(shares.first["utilityId"],"masterUse");verifyEq(shares.first["knownValue"],100f)
    ordinary:=FinEnergyHistory.report(["kind":"utility","dimension":"metering","nodeIds":["t"],"from":start.toIso,"to":(start+1hr).toIso,"asOf":(start+1hr).toIso,"period":"hour","metric":"energy"],rs,hs)
    verifyEq(FinEnergyMath.maps(((Map)ordinary["extra"])["utilityMembers"]).map |m->Str| {m["nodeId"].toStr},["a","b"])
    verifyEq(FinEnergyMath.maps(((Map)ordinary["extra"])["utilityShares"]).reduce(0f) |Float total,m->Float| {total+(Float)m["knownValue"]},90f)
  }

  Void testExactEndUsePlannerAndConsumerHaveTheSameCanonicalOwnPointSet()
  {
    rs:=records;rs.add(["id":"t","kind":"totalMeter","name":"Master","pointId":"pt","categoryId":"c","includeInTotals":false])
    rs.add(["id":"alias","kind":"meter","name":"Alias","pointId":"pt","categoryId":"c","canonicalId":"t"])
    rs.find |r| {r["id"]=="a"}["meterParentId"]="t"
    dim:=FinEnergyDimension("metering",rs);ctx:=FinEnergyContext(dim.records,[Str:Obj?][,],TimeZone.utc,dim)
    q:=FinEnergyCockpitReports.faceQuery(["_cockpitCategoryId":"c","categoryIds":["c"]],["meterIds":["alias","t","a"]],"face-endUse")
    picked:=FinEnergyEndUse.resolveReport(ctx,q)
    verifyEq(picked.map |m->Str| {m["id"].toStr},["a","t"])
    deps:=FinEnergyDimension.dependencies(q,rs)
    verifyEq(deps["nodes"],["a","t"]);verifyEq(deps["points"],["pa","pt"])
    // Excluded explicit meters remain analyzable; parents are not pruned when
    // the boundary includes both objects. Existing overlap logic limits sums.
    verifyEq(FinEnergyEndUse.overlap(ctx,picked),true)
    bad:=q.dup.set("nodeIds",["outside-unreadable"])
    verifyErr(ArgErr#) {FinEnergyEndUse.resolveReport(ctx,bad)}
    ["kind","dimension","metric","categoryIds","_cockpitExactMeterSet"].each |key|
    {
      invalid:=q.dup;invalid[key]=key=="categoryIds" ? ["other"] : "invalid"
      verifyErr(ArgErr#) {FinEnergyEndUse.resolveReport(ctx,invalid)}
    }
    hidden:=rs.find |r| {r["id"]=="b"};hidden["nativeHidden"]=true
    blocked:=FinEnergyContext(rs,[Str:Obj?][,],TimeZone.utc)
    verifyErr(ArgErr#) {FinEnergyEndUse.resolveReport(blocked,q.dup.set("nodeIds",["b"]))}
    // A readable source in another energy category must never enter the set.
    verifyErr(ArgErr#) {FinEnergyEndUse.resolveReport(ctx,q.dup.setAll(["categoryIds":["water"],"_cockpitCategoryId":"water"]))}
  }

  Void testThreeFacesShareOnePreparedLoadAndExactMeterBoundary()
  {
    calls:=0
    result:=FinEnergyCockpit.execute(request,records,|Str:Obj? q,[Str:Obj?][] rs->[Str:Obj?][]| {calls++;return histories},"test",TimeZone.utc,end)
    verifyEq(calls,1)
    modules:=(Map)result["modules"]
    ["time","endUse","organization"].each |id| {verify(modules.containsKey(id),id)}
    verifyEq(((Map)result["capabilities"])["availableFaces"],["space","time","endUse","organization"])
    org:=(Map)((Map)modules["organization"])["data"]
    verifyEq(org["meterIds"],["a","b"])
    nodes:=FinEnergyMath.maps(org["nodes"])
    verifyEq(nodes.find |n| {n["id"] == "company"}["value"],120f)
    verifyEq(nodes.find |n| {n["id"] == "department"}["value"],120f)
    verifyEq(nodes.find |n| {n["nodeKind"] == "unassigned"}["value"],180f)
    roots:=FinEnergyMath.strings(org["rootIds"])
    verifyEq(nodes.findAll |n| {roots.contains(n["id"])}.reduce(0f) |Float v,n->Float| {v+(Float)n["value"]},300f)
    time:=(Map)((Map)modules["time"])["data"]
    verifyEq(((List)time["heatmap"]).size,48)
    daily:=(Map)((Map)result["reports"])[time["dailyReportRef"]]
    verify(FinEnergyMath.maps(daily["series"]).all |s| {s["unit"] == "kWh"})
    verifyEq(FinEnergyMath.maps(FinEnergyMath.maps(daily["series"]).first["points"]).first["value"],5f)
    verify(FinEnergyMath.strings(((Map)modules["time"])["reasonCodes"]).contains("MISSING_CALENDAR"))
    uses:=(Map)((Map)modules["endUse"])["data"]
    verifyEq(uses["additive"],true)
    utility:=(Map)((Map)result["reports"])[uses["reportRef"]]
    shares:=FinEnergyMath.maps(((Map)utility["extra"])["utilityShares"])
    verifyEq(shares.find |s| {s["utilityId"] == "lighting"}["knownPercentage"],40f)
    verifyEq(shares.find |s| {s["utilityId"] == "motive"}["knownPercentage"],60f)
    fixture:=Env.cur.vars["FINENERGY_COCKPIT_FACES_FIXTURE"]
    if (fixture != null) File.os(fixture).out.writeChars(JsonOutStream.writeJsonToStr(result)).close
  }

  Void testIncompleteDaysAndFutureHoursNeverBecomeZeroHeatmapCells()
  {
    q:=request;q["time"]=["preset":"custom","period":"day","from":start.toIso,"to":(end-1hr).toIso]
    result:=FinEnergyCockpit.execute(q,records,|Str:Obj? x,[Str:Obj?][] rs->[Str:Obj?][]| {histories},"test",TimeZone.utc,end)
    time:=(Map)((Map)((Map)result["modules"])["time"])["data"]
    verifyEq(((List)time["heatmap"]).size,0)
    verifyEq(((List)time["excludedDays"]).size,2)
  }

  Void testOverlappingScopeKeepsOtherModulesSafeAndEndUseBoundaryIndependent()
  {
    rs:=records
    rs.findAll |r| {["a","b"].contains(r["id"])}.each |r| {r["meterParentId"]="t"}
    rs.add(["id":"t","kind":"totalMeter","name":"Master","pointId":"pt","categoryId":"c","organizationId":"company"])
    hs:=histories;rows:=[Str:Obj?][,]
    (0..24).each |hour| {rows.add(["ts":(start+1hr*hour).toIso,"value":hour*12.5f])}
    hs.add(["pointId":"pt","mode":"cumulative","unit":"kWh","intervalSeconds":3600f,"samples":rows])
    q:=request;q["reportScope"]=["dimension":"metering","nodeIds":["t","a","b"],"selectionIntent":"explicitObjects"]
    r:=FinEnergyCockpit.execute(q,rs,|Str:Obj? x,[Str:Obj?][] saved->[Str:Obj?][]| {hs},"test",TimeZone.utc,end)
    modules:=(Map)r["modules"];uses:=(Map)((Map)modules["endUse"])["data"]
    verifyEq(uses["additive"],false)
    report:=(Map)((Map)r["reports"])[uses["reportRef"]]
    verifyEq(((List)((Map)report["extra"])["utilityMembers"]).size,3)
    verifyEq(FinEnergyMath.maps(((Map)report["extra"])["utilityMembers"]).map |m->Str| {m["nodeId"].toStr},["a","b","t"])
    verify(FinEnergyMath.maps(((Map)report["extra"])["utilityShares"]).all |s| {s["knownPercentage"]==null})
    verify(FinEnergyMath.maps(((Map)((Map)modules["organization"])["data"])["nodes"]).all |n| {n["value"] == null})
  }

  Void testRealZeroAndNaRemainDistinctInHeatmapAndOrganization()
  {
    hs:=histories
    FinEnergyMath.maps(hs.first["samples"]).each |p| {p["value"]=0f}
    FinEnergyMath.maps(hs.last["samples"]).each |p| {p["value"]=null;p["valueType"]="na";p["quality"]="na"}
    r:=FinEnergyCockpit.execute(request,records,|Str:Obj? x,[Str:Obj?][] rs->[Str:Obj?][]| {hs},"test",TimeZone.utc,end)
    modules:=(Map)r["modules"]
    time:=(Map)((Map)modules["time"])["data"]
    verifyEq(((List)time["heatmap"]).size,24)
    verify(FinEnergyMath.maps(time["heatmap"]).all |cell| {cell["value"] == 0f})
    nodes:=FinEnergyMath.maps(((Map)((Map)modules["organization"])["data"])["nodes"])
    verifyEq(nodes.find |n| {n["id"] == "company"}["value"],0f)
    verifyEq(nodes.find |n| {n["nodeKind"] == "unassigned"}["valueType"],"na")
  }

  Void testCurrentOrganizationHierarchyOnlyGroupsTheEffectiveSet()
  {
    rs:=records
    rs.add(["id":"outside","kind":"meter","name":"Outside","pointId":"outside-point","categoryId":"c","organizationId":"company"])
    rs.find |r| {r["id"] == "b"}["organizationId"]="hidden-organization-ref"
    r:=FinEnergyCockpit.execute(request,rs,|Str:Obj? x,[Str:Obj?][] saved->[Str:Obj?][]| {histories},"test",TimeZone.utc,end)
    org:=(Map)((Map)((Map)r["modules"])["organization"])["data"]
    verifyEq(org["meterIds"],["a","b"])
    verifyEq(FinEnergyMath.maps(org["nodes"]).find |n| {n["id"] == "company"}["value"],120f)
    verify(!JsonOutStream.writeJsonToStr(org).contains("hidden-organization-ref"))
    verify(!JsonOutStream.writeJsonToStr(org).contains("outside-point"))
  }

  Void testDstCompleteDaysUseTheirActualHourCounts()
  {
    tz:=TimeZone("New_York")
    [Date(2026,Month.mar,8),Date(2026,Month.nov,1)].each |date|
    {
      from:=date.toDateTime(Time.defVal,tz);to:=(date+1day).toDateTime(Time.defVal,tz)
      hours:=((to-from).ticks/1hr.ticks).toInt
      hs:=["pa","pb"].map |id,Int meter->[Str:Obj?]|
      {
        rows:=[Str:Obj?][,]
        (0..hours).each |hour| {rows.add(["ts":(from+1hr*hour).toIso,"value":hour*(meter == 0 ? 5f : 7.5f)])}
        return ["pointId":id,"mode":"cumulative","unit":"kWh","intervalSeconds":3600f,"samples":rows]
      }
      q:=request;q["time"]=["preset":"custom","period":"day","from":from.toIso,"to":to.toIso];q["asOf"]=to.toIso
      r:=FinEnergyCockpit.execute(q,records,|Str:Obj? x,[Str:Obj?][] rs->[Str:Obj?][]| {hs},"test",tz,to)
      time:=(Map)((Map)((Map)r["modules"])["time"])["data"]
      verifyEq(((List)time["heatmap"]).size,hours*2)
      verifyEq(((List)time["excludedDays"]).size,0)
    }
  }

  Void testConfiguredCalendarIsReusedWithoutASeparateHistoryLoad()
  {
    rs:=records;rs.add(["id":"calendar","kind":"calendar","name":"Work","isDefault":true,"workHours":(8..17).toList,"workDays":[1,2,3,4,5]])
    calls:=0
    r:=FinEnergyCockpit.execute(request,rs,|Str:Obj? x,[Str:Obj?][] saved->[Str:Obj?][]| {calls++;return histories},"test",TimeZone.utc,end)
    verifyEq(calls,1)
    time:=(Map)((Map)((Map)r["modules"])["time"])["data"]
    verifyNotNull(time["workingReportRef"]);verifyNotNull(time["workingDaysReportRef"])
    work:=(Map)((Map)r["reports"])[time["workingReportRef"]]
    rows:=FinEnergyMath.maps(work["rows"])
    verifyEq(rows.find |row| {row["nodeId"] == "a"}["working"],50f)
    verifyEq(rows.find |row| {row["nodeId"] == "b"}["working"],75f)
  }

  Void testAssignedIncompleteSourcesDoNotAdvertiseCompleteDistributionModules()
  {
    rs:=records;rs.find |r| {r["id"] == "b"}["organizationId"]="department"
    hs:=histories
    FinEnergyMath.maps(hs.first["samples"]).each |p| {p["value"]=0f}
    FinEnergyMath.maps(hs.last["samples"]).each |p| {p["value"]=null;p["valueType"]="na";p["quality"]="na"}
    r:=FinEnergyCockpit.execute(request,rs,|Str:Obj? x,[Str:Obj?][] saved->[Str:Obj?][]| {hs},"test",TimeZone.utc,end)
    modules:=(Map)r["modules"]
    verifyEq(((Map)modules["endUse"])["status"],"partial")
    verifyEq(((Map)modules["organization"])["status"],"partial")
    company:=FinEnergyMath.maps(((Map)((Map)modules["organization"])["data"])["nodes"]).find |n| {n["id"] == "company"}
    verifyEq(company["value"],0f);verifyNull(company["completeValue"])
  }

  private DateTime start() {DateTime.fromIso("2026-10-01T00:00:00Z")}
  private DateTime end() {start+24hr}
  private Str:Obj? request()
  { ["schemaVersion":1,"requestId":"faces-test","reportScope":["dimension":"metering","nodeIds":["a","b"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"day","from":start.toIso,"to":end.toIso],"asOf":end.toIso,"comparison":["mode":"none"],"modules":["kpis","trend","time","endUse","organization"]] }
  private [Str:Obj?][] records()
  { [["id":"c","kind":"category","name":"Electricity","unit":"kWh"],["id":"a","kind":"meter","name":"A","pointId":"pa","categoryId":"c","utilityId":"lighting","organizationId":"department"],["id":"b","kind":"meter","name":"B","pointId":"pb","categoryId":"c","utilityId":"motive"],["id":"lighting","kind":"utility","name":"Lighting","categoryId":"c"],["id":"motive","kind":"utility","name":"Motive","categoryId":"c"],["id":"company","kind":"organization","name":"Company"],["id":"department","kind":"organization","name":"Department","parentId":"company"]] }
  private [Str:Obj?][] histories()
  {
    return ["pa","pb"].map |id,Int meter->[Str:Obj?]|
    {
      rows:=[Str:Obj?][,]
      (0..24).each |hour| {rows.add(["ts":(start+1hr*hour).toIso,"value":hour*(meter == 0 ? 5f : 7.5f)])}
      return ["pointId":id,"mode":"cumulative","unit":"kWh","intervalSeconds":3600f,"samples":rows]
    }
  }
}

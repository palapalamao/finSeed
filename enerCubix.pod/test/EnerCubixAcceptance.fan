using haystack
using folio
using skyarcd

** Runtime integration fixture. Never permitted in a user's business project.
class EnerCubixAcceptance
{
  Context cx
  EnerCubixRepo repo
  Str:Obj?[] checks := [:]
  Str[] reportKinds := [,]
  new make(Context cx) { this.cx=cx; this.repo=EnerCubixRepo(cx) }

  Str:Obj? run()
  {
    if (cx.proj.name != "enerCubix_acceptance") throw ArgErr("Acceptance fixture requires enerCubix_acceptance project")
    from:=DateTime.fromIso("2026-10-19T00:00:00+08:00").toTimeZone(TimeZone.fromStr("Shanghai"))
    to:=from+24hr
    cat:=save(["kind":"category","name":"验收电力","unit":"kWh"])
    sub:=save(["kind":"subcategory","name":"验收电力系数","categoryId":cat["id"],"coalFactor":0.1229f,"co2Factor":0.57f])
    utility:=save(["kind":"utility","name":"验收照明用途","categoryId":cat["id"]])
    tariff:=save(["kind":"tariff","name":"验收普通费率","mode":"flat","rate":1.2f,"categoryId":cat["id"],"isDefault":true])
    cal:=save(["kind":"calendar","name":"验收工作日历","isDefault":true,"peakHours":[8,9],"valleyHours":[0,1],"workHours":[8,9,10,11,12,13,14,15,16,17],"workDays":[1,2,3,4,5],"exceptions":Obj?[,]])
    root:=save(["kind":"group","name":"验收楼宇","area":1000f,"alarmLimits":[["categoryId":cat["id"],"limit":9f,"enabled":true]]])
    child:=save(["kind":"group","name":"验收楼层","parentId":root["id"],"area":300f])
    masterPoint:=point("enerCubix-test-master",true,from,10f)
    branchPoint:=point("enerCubix-test-branch",false,from,6f)
    childPoint:=point("enerCubix-test-child",true,from,3f)
    master:=save(["kind":"totalMeter","name":"验收总表","parentId":root["id"],"pointId":masterPoint.id.id,"categoryId":cat["id"],"subcategoryId":sub["id"],"includeInTotals":true,"alarmEnabled":true,"alarmLimit":8f])
    branch:=save(["kind":"meter","name":"验收分表","parentId":root["id"],"pointId":branchPoint.id.id,"categoryId":cat["id"],"subcategoryId":sub["id"],"utilityId":utility["id"],"includeInTotals":true])
    childMaster:=save(["kind":"totalMeter","name":"验收楼层总表","parentId":child["id"],"pointId":childPoint.id.id,"categoryId":cat["id"],"subcategoryId":sub["id"],"includeInTotals":true])
    expr:=save(["kind":"expression","name":"验收虚表表达式","formula":"a+b","variables":["a":branch["id"],"b":childMaster["id"]]])
    vMeter:=save(["kind":"meter","name":"验收虚表","parentId":root["id"],"categoryId":cat["id"],"expressionId":expr["id"],"includeInTotals":false])
    cop:=save(["kind":"cop","name":"验收COP","numeratorId":child["id"],"denominatorId":branch["id"]])
    q:=Str:Obj?["kind":"profile","nodeIds":[root["id"]],"from":from.toIso,"to":to.toIso,"period":"day","metric":"energy","perArea":false]
    profile:=report(q)
    value("native total overrides branches",firstPoint(profile),240f,[masterPoint.id.id])
    rootSeries:=EnerCubixMath.maps(profile["series"]).first
    q["metric"]="cost"; value("native default flat tariff",firstPoint(report(q)),288f,[masterPoint.id.id])
    q["metric"]="co2"; value("CO2 conversion",firstPoint(report(q)),136.8f,[masterPoint.id.id])
    q["metric"]="energy"; q["perArea"]=true; value("area normalization",firstPoint(report(q)),0.24f,[masterPoint.id.id])
    q["perArea"]=false; q["kind"]="leak"
    leak:=report(q)
    value("master less branches including child master",firstPoint(leak),24f,[masterPoint.id.id,branchPoint.id.id,childPoint.id.id])
    leakRow:=EnerCubixMath.maps(leak["rows"]).first
    check("leak master total",leakRow["total"],240f)
    check("leak branch sum",leakRow["submeter"],216f)
    check("leak percentage",leakRow["percentage"],10f)
    q["kind"]="cop"; q["nodeIds"]=[cop["id"]]
    value("COP ratio of sums",firstPoint(report(q)),0.5f,[childPoint.id.id,branchPoint.id.id])
    q["kind"]="profile"; q["nodeIds"]=[vMeter["id"]]
    value("expression and interval-end conversion",firstPoint(report(q)),216f,[branchPoint.id.id,childPoint.id.id],"derived")
    q["nodeIds"]=[branch["id"],child["id"]]
    ["ranking","proportion"].each |kind|
    {
      q["kind"]=kind; result:=report(q); rr:=EnerCubixMath.maps(result["rows"])
      if (rr.size != 2 || rr[0]["nodeId"] != branch["id"] || rr[1]["nodeId"] != child["id"]) throw Err("$kind selected-object order failed")
      value("$kind branch",rr[0],144f,[branchPoint.id.id])
      value("$kind child",rr[1],72f,[childPoint.id.id])
      check("$kind branch percentage",rr[0]["percentage"],200f/3f)
      check("$kind child percentage",rr[1]["percentage"],100f/3f)
    }
    q["nodeIds"]=[root["id"]]; q["kind"]="utility"
    utilityReport:=report(q)
    value("native utility excludes unrelated master-only child",firstPoint(utilityReport),144f,[branchPoint.id.id])
    shares:=EnerCubixMath.maps(((Map)utilityReport["extra"])["utilityShares"])
    if (shares.size != 1 || shares.first["nodeId"] != root["id"]) throw Err("Utility grouping failed")
    value("native utility share amount",shares.first,144f,[branchPoint.id.id])
    check("native utility share percentage",shares.first["percentage"],100f)
    q["nodeIds"]=[root["id"]]; q["kind"]="daily"
    daily:=report(q); dailyPoints:=EnerCubixMath.maps(EnerCubixMath.maps(daily["series"]).first["points"])
    if (dailyPoints.size != 24) throw Err("Daily expected 24 hours")
    dailyPoints.each |p,i|
    {
      value("daily hour $i",p,10f,[masterPoint.id.id])
      band:=i == 8 || i == 9 ? "peak" : (i == 0 || i == 1 ? "valley" : "flat")
      if (p["band"] != band) throw Err("Daily band mismatch at $i")
    }
    bands:=EnerCubixMath.maps(((Map)daily["extra"])["loadBands"])
    value("daily peak interval total",bands.find |r| { r["band"] == "peak" },20f,[masterPoint.id.id])
    value("daily valley interval total",bands.find |r| { r["band"] == "valley" },20f,[masterPoint.id.id])
    value("daily flat interval total",bands.find |r| { r["band"] == "flat" },200f,[masterPoint.id.id])
    if (((Map)daily["extra"])["loadBandsAggregation"] != "intervalTotal") throw Err("Daily band aggregation metadata failed")
    q["kind"]="workingHours"; working:=report(q); workRow:=EnerCubixMath.maps(working["rows"]).first
    value("working-hours whole interval",workRow,240f,[masterPoint.id.id])
    check("working hours",workRow["working"],100f); check("nonworking hours",workRow["nonworking"],140f)
    check("working hour percentage",workRow["workingPercentage"],125f/3f)
    q["kind"]="workingDays"; workRow=EnerCubixMath.maps(report(q)["rows"]).first
    value("working-day whole interval",workRow,240f,[masterPoint.id.id])
    check("Monday working day",workRow["working"],240f); check("Monday nonworking day",workRow["nonworking"],0f)
    q["kind"]="comparison"; q["otherFrom"]=from.toIso; q["otherTo"]=to.toIso
    aligned:=q.dup
    aligned["from"]=(from+8hr).toIso; aligned["to"]=(from+14hr).toIso
    aligned["otherFrom"]=(from+14hr).toIso; aligned["otherTo"]=(from+20hr).toIso
    aligned["period"]="week"; aligned["comparisonAlignment"]="duration"
    paired:=EnerCubixMath.maps(report(aligned)["series"])
    if (paired.size != 2) throw Err("Aligned comparison expected two series")
    paired.each |line,i|
    {
      pp:=EnerCubixMath.maps(line["points"])
      if (pp.size != 1 || pp.first["ts"] != (i == 0 ? aligned["from"] : aligned["otherFrom"])) throw Err("Comparison bucket origin mismatch")
      value("native aligned comparison period $i",pp.first,60f,[masterPoint.id.id])
    }
    objectQuery:=q.dup; objectQuery.remove("otherFrom"); objectQuery.remove("otherTo")
    objectQuery["nodeIds"]=[branch["id"],childMaster["id"]]; objectQuery["baselineId"]=childMaster["id"]
    objectRows:=EnerCubixMath.maps(((Map)report(objectQuery)["extra"])["comparisons"])
    check("explicit second-object baseline difference",objectRows.first["difference"],72f)
    check("explicit second-object baseline percentage",objectRows.first["percentage"],100f)
    templateSaved:=save(["kind":"template","name":"验收指定基准模板","request":objectQuery])
    templateStored:=repo.records.find |r| { r["id"] == templateSaved["id"] }
    if (((Map)templateStored["request"])["baselineId"] != childMaster["id"]) throw Err("Baseline template persistence failed")
    nativeTemplate:=cx.db.readById(Ref(templateSaved["id"].toStr))
    if (!((List)nativeTemplate["enerCubixDependencyRefs"]).contains(Ref(childMaster["id"].toStr))) throw Err("Missing Folio baseline dependency Ref")
    checks["explicit baseline Folio template roundtrip"]=[true]
    comparison:=report(q); same:=EnerCubixMath.maps(((Map)comparison["extra"])["comparisons"]).first
    check("same-range comparison current",same["current"],240f); check("same-range comparison reference",same["reference"],240f)
    check("same-range difference",same["difference"],0f); check("same-range percentage",same["percentage"],0f)
    if (same["quality"] != "ok") throw Err("Same-range comparison quality failed")
    EnerCubixMath.maps(comparison["series"]).each |s| { value("comparison series "+s["id"],EnerCubixMath.maps(s["points"]).first,240f,[masterPoint.id.id]) }
    q.remove("otherFrom"); q.remove("otherTo")
    q["kind"]="primary"; q["metric"]="coal"
    primary:=report(q)
    value("primary coal conversion kgce",firstPoint(primary),29.496f,[masterPoint.id.id])
    if (EnerCubixMath.maps(primary["series"]).first["unit"] != "kgce") throw Err("Primary coal unit failed")
    q["metric"]="energy"; q["kind"]="dashboard"
    dashboard:=report(q)
    value("dashboard category overview",EnerCubixMath.maps(((Map)dashboard["extra"])["overview"]).first,240f,[masterPoint.id.id])
    value("dashboard selected grand total",EnerCubixMath.maps(((Map)dashboard["extra"])["grandTotals"]).first,240f,[masterPoint.id.id])
    q["metric"]="cost"; dashboard=report(q)
    value("dashboard cost grand total",EnerCubixMath.maps(((Map)dashboard["extra"])["grandTotals"]).first,288f,[masterPoint.id.id])
    q["metric"]="co2"; dashboard=report(q)
    value("dashboard CO2 grand total",EnerCubixMath.maps(((Map)dashboard["extra"])["grandTotals"]).first,136.8f,[masterPoint.id.id])
    q["metric"]="energy"
    q["kind"]="trend"; q["nodeIds"]=[master["id"]]
    trend:=report(q); ps:=EnerCubixMath.maps(EnerCubixMath.maps(trend["series"]).first["points"])
    if (ps.size != 96) throw Err("Raw trend expected 96 in-range quarter-hour samples, got ${ps.size}")
    value("raw cumulative trend retained",ps.first,1000f,[masterPoint.id.id])
    value("raw cumulative trend last in-range sample",ps.last,1237.5f,[masterPoint.id.id])
    q["kind"]="regression"; q["period"]="hour"; q["xId"]=masterPoint.id.id; q["yId"]=branch["id"]
    regression:=report(q); fit:=(Map)regression["extra"]
    check("regression valid hourly pairs",fit["count"],24f)
    check("regression slope",fit["slope"],0f); check("regression intercept",fit["intercept"],6f)
    if (fit["r2"] != null) throw Err("Constant Y must not invent r2")
    endpoints:=EnerCubixMath.maps(fit["fitLine"])
    if (endpoints.size != 2) throw Err("Regression fitted endpoints missing")
    check("regression first x",endpoints.first["x"],1003.75f); check("regression last x",endpoints.last["x"],1233.75f)
    endpoints.each |p| { check("regression fitted y "+p["x"],p["y"],6f) }
    EnerCubixMath.maps(regression["rows"]).each |r,i|
    {
      value("regression hourly y $i",r,6f,[masterPoint.id.id,branchPoint.id.id])
      check("regression hourly reference x $i",r["x"],1003.75f+10f*i.toFloat)
    }
    nativeTariffs(cat,from)
    missingQuery:=q.dup; missingQuery["kind"]="profile"; missingQuery["nodeIds"]=[branch["id"]]
    missingQuery["period"]="day"; missingQuery["from"]=(from-24hr).toIso; missingQuery["to"]=from.toIso
    absent:=firstPoint(report(missingQuery))
    if (absent["value"] != null || absent["quality"] != "missing" || EnerCubixMath.strings(absent["sourceIds"]) != [branchPoint.id.id]) throw Err("Absent native source interval must stay null with evidence")
    checks["native missing interval remains null"]=[absent["value"],absent["quality"],absent["sourceIds"]]
    copied:=repo.tree("copy",root["id"].toStr,null,root["mod"])
    count:=((List)copied["records"]).size
    if (count != 6) throw Err("Tree copy expected 6 nodes, got $count")
    checks["tree copy preserves six-node hierarchy"]=[true]
    if (EnerCubixMath.maps(copied["records"]).any |r| { EnerCubixRelations.meterKinds.contains(r["kind"]) && (r["pointId"] != null || r["expressionId"] != null || r["includeInTotals"] != false) }) throw Err("Copied meters must remain unbound")
    checks["tree copy clears source bindings and total flags"]=[true]
    ((List)copied["records"]).dup.reverse.each |v|
    {
      copy:=(Map)v
      repo.remove(copy["id"].toStr,copy["mod"])
    }
    checks["owned copied fixture hierarchy removed after check"]=[true]
    empty:=save(["kind":"group","name":"验收删除空组"])
    repo.remove(empty["id"].toStr,empty["mod"])
    checks["empty group deletion"]=[true]
    Bool refused:=false
    try { repo.remove(root["id"].toStr,root["mod"]) } catch (ArgErr e) { refused=true }
    if (!refused) throw Err("Occupied group deletion was accepted")
    checks["occupied group deletion rejected"]=[true]
    job:=EnerCubixJobs(repo).run(["action":"recalculate","from":from.toIso,"to":to.toIso])
    if (job["status"] != "completed") throw Err("Recalculation failed")
    checks["native derived history recompute"]=[job["processed"]]
    before:=derivedHistory(rootSeries,from,to)
    again:=EnerCubixJobs(repo).run(["action":"recalculate","from":from.toIso,"to":to.toIso])
    if (again["status"] != "completed") throw Err("Second recalculation failed")
    after:=derivedHistory(rootSeries,from,to)
    if (before != after) throw Err("Same-range recalculation changed timestamps, values or count")
    checks["native derived history same-range idempotency"]=[before.size,after.size]
    original:=rawHistory(masterPoint,from,to).find |item| { item.ts == from }
    if (original == null) throw Err("Source counter boundary disappeared")
    check("source cumulative history remains unchanged",((Number)original.val).toFloat,1000f)
    EnerCubixJobs(repo).run(["action":"scanAlarms","from":from.toIso,"to":to.toIso])
    alarms:=repo.records.findAll |r| { r["kind"] == "alarm" && r["nodeId"] == master["id"] }
    if (alarms.size != 24) throw Err("Expected 24 hourly threshold events, got ${alarms.size}")
    groupAlarms:=repo.records.findAll |r| { r["kind"] == "alarm" && r["nodeId"] == root["id"] && r["categoryId"] == cat["id"] }
    if (groupAlarms.size != 24) throw Err("Expected 24 group category threshold events, got ${groupAlarms.size}")
    checks["native group category hourly thresholds"]=[groupAlarms.size]
    ack:=repo.acknowledge(alarms.first["id"].toStr,alarms.first["mod"],"验收确认")
    if (ack["ackBy"] != cx.user.username || ack["state"] != "acknowledged") throw Err("Native alarm acknowledgement identity failed")
    checks["alarm threshold and acknowledgement"]=[true]
    expectedKinds:=["profile","ranking","proportion","utility","daily","comparison","primary","cop","leak","workingHours","workingDays","regression","trend","dashboard"].sort
    if (reportKinds.dup.sort != expectedKinds) throw Err("Report-kind acceptance coverage incomplete: $reportKinds")
    return ["project":cx.proj.name,"actor":cx.user.username,"checks":checks,"reportKinds":reportKinds,"status":"passed"]
  }

  ** Independent owned source starts at both month/year boundaries. No zero
  ** baseline is assumed for the original October sources.
  private Void nativeTariffs(Str:Obj? category, DateTime from)
  {
    group:=save(["kind":"group","name":"验收独立用途费用组"])
    year:=DateTime.fromIso("2026-01-01T00:00:00+08:00").toTimeZone(from.tz)
    tierPoint:=point("enerCubix-test-tariff-source",false,year,6f)
    meter:=save(["kind":"meter","name":"验收独立用途费用表","parentId":group["id"],"pointId":tierPoint.id.id,"categoryId":category["id"],"includeInTotals":true])
    try
    {
      q:=Str:Obj?["kind":"profile","nodeIds":[meter["id"]],"from":year.toIso,"to":(year+24hr).toIso,"period":"day","metric":"cost","perArea":false]
      definitions:=[
        [Str:Obj?]["mode":"flat","rate":2f],
        [Str:Obj?]["mode":"absolute","rate":1f,"rules":[["from":year.toIso,"to":(year+12hr).toIso,"rate":2f]]],
        [Str:Obj?]["mode":"weekly","rate":1f,"rules":[["weekday":4,"startHour":8,"endHour":18,"rate":3f]]],
        [Str:Obj?]["mode":"monthlyBlock","rate":0f,"blocks":[["limit":100f,"rate":1f],["limit":null,"rate":2f]]],
        [Str:Obj?]["mode":"yearlyBlock","rate":0f,"blocks":[["limit":100f,"rate":1f],["limit":null,"rate":2f]]]]
      expected:=[288f,216f,264f,188f,188f]
      definitions.each |definition,i|
      {
        definition["kind"]="tariff"; definition["name"]="验收独立费率 "+definition["mode"]; definition["categoryId"]=category["id"]; definition["isDefault"]=false
        tariff:=save(definition)
        meter["tariffId"]=tariff["id"]; meter=repo.save(meter)
        value("native tariff "+definition["mode"],firstPoint(report(q)),expected[i],[tierPoint.id.id])
      }
    }
    finally
    {
      // Remove only this isolated configuration; original branch bindings stay intact.
      latest:=repo.records.find |r| { r["id"] == meter["id"] }
      if (latest != null) repo.remove(latest["id"].toStr,latest["mod"])
      latest=repo.records.find |r| { r["id"] == group["id"] }
      if (latest != null) repo.remove(latest["id"].toStr,latest["mod"])
    }
  }

  private [Str:Obj?][] derivedHistory(Str:Obj? series, DateTime from, DateTime to)
  {
    point:=cx.db.readById(Ref(EnerCubixJobs.derivedId(series)))
    EnerCubixJobs.checkOwned(point,series)
    if (point["unit"] != "kWh") throw Err("Derived point unit expected kWh")
    // Dedicated computed consumption uses interval END timestamps.
    items:=rawHistory(point,from,to+1sec).findAll |item| { item.ts > from && item.ts <= to }
    if (items.size != 24) throw Err("Derived native history expected 24 items, got ${items.size}")
    result:=[Str:Obj?][,]
    items.each |item,i|
    {
      if (item.ts != from+1hr*(i+1)) throw Err("Derived native history timestamp mismatch at $i")
      number:=item.val as Number ?: throw Err("Derived native history has nonnumeric item")
      if (number.unit != Unit.fromStr("kWh")) throw Err("Derived native history item unit failed")
      check("derived native hourly energy $i",number.toFloat,10f)
      result.add(["ts":item.ts.toIso,"value":number.toFloat,"unit":number.unit.toStr])
    }
    checks["native derived history readback"]=[point.id.id,items.size,"kWh"]
    return result
  }

  private HisItem[] rawHistory(Dict point, DateTime from, DateTime to)
  {
    items:=HisItem[,]
    cx.rt.his.read(point,Span.makeAbs(from,to),Etc.makeDict(["raw":Marker.val])) |HisItem item| { items.add(item) }
    return items.sort |a,b| { a.ts <=> b.ts }
  }

  private Str:Obj? report(Str:Obj? request)
  {
    kind:=request["kind"].toStr
    if (!reportKinds.contains(kind)) reportKinds.add(kind)
    return repo.report(request)
  }

  private Void value(Str label, [Str:Obj?]? point, Float expected, Str[] sources, Str quality:="ok")
  {
    if (point == null) throw Err("$label has no result")
    check(label,point["value"],expected)
    if (point["quality"] != quality) throw Err("$label quality expected $quality got "+point["quality"])
    if (EnerCubixMath.strings(point["sourceIds"]).sort != sources.dup.sort) throw Err("$label source evidence mismatch: "+point["sourceIds"])
    checks[label+" quality and sources"]=[quality,sources]
  }

  private Str:Obj? save(Str:Obj? r)
  {
    existing:=repo.records.find |x| { x["kind"] == r["kind"] && x["name"] == r["name"] }
    if (existing != null) { r["id"]=existing["id"]; r["mod"]=existing["mod"] }
    return repo.save(r)
  }

  private Dict point(Str id, Bool cumulative, DateTime from, Float hourly)
  {
    key:=Ref(id)
    rec:=cx.db.readById(key,false)
    if (rec == null)
    {
      tags:=Str:Obj?["point":Marker.val,"his":Marker.val,"kind":"Number","unit":"kWh","tz":"Shanghai","hisMode":"consumption","dis":id,"enerCubixAcceptanceSource":Marker.val,"hisCollectInterval":Number(15,Unit.fromStr("min"))]
      if (cumulative) tags["hisTotalized"]=Marker.val
      rec=cx.db.commit(Diff.makeAdd(Etc.makeDict(tags),key)).newRec
    }
    if (!rec.has("enerCubixAcceptanceSource")) throw Err("Fixture point ownership mismatch")
    items:=HisItem[,]
    for (i:=0;i<=96;i++)
    {
      if (!cumulative && i==0) continue
      value:=cumulative ? 1000f+hourly*i.toFloat/4f : hourly/4f
      items.add(HisItem(from+15min*i,Number(value,Unit.fromStr("kWh"))))
    }
    cx.rt.his.write(rec,items,null).get(1min)
    return rec
  }

  private Str:Obj? firstPoint(Str:Obj? report)
  {
    series:=EnerCubixMath.maps(report["series"])
    if (series.isEmpty) throw Err("No report series: $report")
    points:=EnerCubixMath.maps(series.first["points"])
    if (points.isEmpty) throw Err("No report points: $report")
    return points.first
  }

  private Void check(Str label, Obj? actual, Float expected)
  {
    if (actual == null || (EnerCubixConfig.number(actual)-expected).abs > 0.000001f) throw Err("$label expected $expected got $actual")
    checks[label]=[actual,expected]
  }
}

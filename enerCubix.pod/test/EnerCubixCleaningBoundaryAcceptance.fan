using haystack
using folio
using skyarcd
using util

** Exercises native hisRollup, rather than approximating it with report arithmetic.
class EnerCubixCleaningBoundaryAcceptance
{
  Context cx
  EnerCubixRepo repo
  Ref[] owned := [,]
  Int checks := 0
  new make(Context cx) { this.cx=cx; repo=EnerCubixRepo(cx) }

  Str:Obj? run()
  {
    if (!["finseed_acceptance","enerCubix_acceptance"].contains(cx.proj.name)) throw ArgErr("Boundary acceptance requires the isolated project")
    repo.mustWrite
    prefix:="Boundary acceptance "+DateTime.nowTicks
    try
    {
      category:=save(["kind":"category","name":prefix+" energy","unit":"kWh"])
      site:=source(["site":Marker.val,"dis":prefix,"tz":"Shanghai"])
      equip:=source(["equip":Marker.val,"dis":prefix+" meter","siteRef":site.id])
      point:=source(["point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"hisMode":"consumption","hisCollectInterval":Number(15,Unit("min")),"kind":"Number","unit":"kWh","tz":"Shanghai","dis":prefix+" reading","equipRef":equip.id,"siteRef":site.id])
      profile:=save(["kind":"cleaningProfile","name":prefix+" profile","mode":"drop","parameters":["deltaMin":0,"timeMax":"1h","defNull":true]])
      repo.save(["id":equip.id.id,"mod":EnerCubixRepo.iso(equip["mod"]),"kind":"meter","name":equip.dis,"pointId":point.id.id,"categoryId":category["id"],"cleaningEnabled":true,"cleaningProfileId":profile["id"],"historyMode":"cumulative"])
      from:=DateTime.fromIso("2026-10-03T00:00:00+08:00").toTimeZone(TimeZone.fromStr("Shanghai"))
      raw:=HisItem[,]
      [100f,112f,107f,115f,120f,130f].each |v,i| { raw.add(HisItem(from+15min*i,Number(v,Unit("kWh")))) }
      // Separate windows also put one interval across midnight and one at the
      // end-exclusive boundary of the next day's query.
      midnight:=from+2day
      [190f,200f,212f,207f,215f,220f,230f].each |v,i| { raw.add(HisItem(midnight-15min+15min*i,Number(v,Unit("kWh")))) }
      (7..98).each |i| { raw.add(HisItem(midnight-15min+15min*i,Number(230+i-6,Unit("kWh")))) }
      cx.rt.his.write(cx.db.readById(point.id),raw,null).get(1min)

      check(value(nativeRollup(point.id,from,from+1hr,"1hr")) == Number(25,Unit("kWh")),"native hour is 25 rather than 20")
      check(report(equip.id,from,from+1hr)["value"] == 25f,"report matches native hour")
      check(value(nativeRollup(point.id,midnight,midnight+1hr,"1hr")) == Number(25,Unit("kWh")),"midnight excludes previous-day interval and next-hour interval")
      check(value(nativeRollup(point.id,midnight,midnight+1day,"1day")) == Number(126,Unit("kWh")),"native day groups intervals by their start")
      check(report(equip.id,midnight,midnight+1day)["value"] == 126f,"full-day report matches native day without borrowing adjacent intervals")
      check(report(equip.id,midnight,midnight+1hr)["value"] == 25f,"midnight report matches native hour")
      archive(equip,point)

      profile["mode"]="replace"; profile["parameters"]=["deltaMin":0,"timeMax":"1h","defVal":["type":"na"]]
      profile=repo.save(profile)
      check(value(nativeRollup(point.id,from,from+1hr,"1hr")) === NA.val,"new native query uses the current NA replacement profile")
      check(report(equip.id,from,from+1hr)["valueType"] == "na","new report uses the current NA replacement profile")
      check(value(nativeRollup(point.id,from,from+1hr,"1hr",true)) === NA.val,"explicit native preview propagates candidate true NA")
      overrideConfig:=EnerCubixHistory.selectConfig((Dict)cx.db.readById(point.id)["hisFuncConfig"],Etc.makeDict(["defVal":Number(0,Unit("kWh"))]))
      explicit:=EnerCubixHistory.cleanRead(cx,cx.db.readById(point.id),Span.makeAbs(from,from+1hr),Etc.makeDict(["enerCubixCleaningPreview":Marker.val]),overrideConfig)
      invalid:=EnerCubixHistory.nativeItems(explicit).find |item| { item.ts == from+15min }
      check(invalid?.val == Number(0,Unit("kWh")),"explicit numeric zero overrides stored NA configuration")
      check(((Dict)cx.db.readById(point.id)["hisFuncConfig"])["defVal"] === NA.val,"explicit override never changes stored point config")

      profile["parameters"]=["deltaMin":0,"timeMax":"1h","defVal":["type":"number","value":0,"unit":"kWh"]]
      profile=repo.save(profile)
      check(value(nativeRollup(point.id,from,from+1hr,"1hr",true)) == Number(25,Unit("kWh")),"explicit native preview keeps zero replacement numeric")
      check(report(equip.id,from,from+1hr)["quality"] == "substituted","new report uses the current numeric replacement profile")
      preview:=EnerCubixCleaningRepo(repo).preview(["nodeId":equip.id.id,"from":from.toIso,"to":(from+1hr).toIso])
      check(EnerCubixMath.num(((Map)preview["summary"])["substitutedCount"]) == 1f,"explicit preview reports candidate replacement quality")
      after:=HisItem[,]; cx.rt.his.read(cx.db.readById(point.id),null,Etc.makeDict(["raw":Marker.val])) |i| { after.add(i) }
      check(after.map |i->Obj?| { i.val } == raw.map |i->Obj?| { i.val },"all raw counter values remain unchanged")
      ruleUpdates(category,site,from)
      return ["status":"passed","checks":checks,"project":cx.proj.name]
    }
    finally
    {
      owned.dup.reverse.each |id|
      {
        rec:=cx.db.readById(id,false)
        if (rec?.has("enerCubixBoundaryAcceptance") == true) cx.db.commit(Diff(rec,null,Diff.remove))
      }
    }
  }

  private Str:Obj? report(Ref id, DateTime from, DateTime to)
  {
    result:=repo.report(["kind":"profile","dimension":"metering","nodeIds":[id.id],"from":from.toIso,"to":to.toIso,"period":"hour","metric":"energy"])
    return EnerCubixMath.maps(((Map)result["summary"])["totals"]).first ?: throw Err("Missing report total")
  }
  private Void ruleUpdates(Str:Obj? category, Dict site, DateTime from)
  {
    equip:=source(["equip":Marker.val,"dis":site.dis+" rule update","siteRef":site.id])
    point:=source(["point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"hisMode":"consumption","kind":"Number","unit":"kWh","tz":"Shanghai","dis":equip.dis+" reading","equipRef":equip.id,"siteRef":site.id])
    profile:=save(["kind":"cleaningProfile","name":equip.dis+" profile","mode":"drop","parameters":["deltaMin":0,"timeMax":"1h","defNull":true]])
    repo.save(["id":equip.id.id,"mod":EnerCubixRepo.iso(equip["mod"]),"kind":"meter","name":equip.dis,"pointId":point.id.id,"categoryId":category["id"],"cleaningEnabled":true,"cleaningProfileId":profile["id"],"historyMode":"cumulative"])
    raw:=[HisItem(from,Number(100,Unit("kWh"))),HisItem(from+1hr,Number(110,Unit("kWh"))),HisItem(from+90min,Number(105,Unit("kWh"))),HisItem(from+2hr,Number(125,Unit("kWh")))]
    cx.rt.his.write(cx.db.readById(point.id),raw,null).get(1min)
    archive(equip,point)
    query:=Str:Obj?["kind":"profile","dimension":"metering","nodeIds":[equip.id.id],"from":from.toIso,"to":(from+130min).toIso,"period":"hour","metric":"energy"]
    old:=repo.report(query); frozen:=JsonOutStream.writeJsonToStr(old)
    check(known(old)==30f,"initial query has known subtotal 30")
    profile["parameters"]=["deltaMin":0,"deltaMax":15,"timeMax":"1h","defNull":true]; profile=repo.save(profile)
    fresh:=repo.report(query)
    check(known(fresh)==10f,"new query uses deltaMax 15 and has known subtotal 10")
    cleaning:=EnerCubixMath.maps(((Map)fresh["extra"])["cleaning"]).first
    check(cleaning["profileVersion"] == profile["version"],"new report records the current profile version")
    nativeRows:=HisItem[,]; cx.rt.his.read(cx.db.readById(point.id),Span.makeAbs(from,from+130min),Etc.emptyDict) |item| {nativeRows.add(item)}
    check(!nativeRows.any |item| {item.val==Number(20,Unit("kWh"))},"new native read filters the old 20 interval")
    check(JsonOutStream.writeJsonToStr(old)==frozen,"old report result remains frozen at subtotal 30")

    // A saved post-cutover fact remains authoritative across later rule changes.
    cutover:=from+2hr; state:=cx.db.readById(EnerCubixMeterHistory.stateId(point.id))
    cx.db.commit(Diff(state,Etc.makeDict(["enerCubixGenerationStart":cutover])))
    interval:=Str:Obj?["from":cutover.toIso,"to":(cutover+1min).toIso,"value":77f,"valueType":"number","quality":"derived","sourceIds":[point.id.id],"configVersion":1]
    batch:=source(["enerCubixIntervalBatch":Marker.val,"enerCubixMainRef":point.id,"enerCubixBatchHour":EnerCubixMath.floorHour(cutover.toTimeZone(TimeZone.utc)),"enerCubixIntervals":JsonOutStream.writeJsonToStr([interval])])
    before:=cx.db.readById(batch.id)["enerCubixIntervals"]
    crossing:=EnerCubixHistory.load(cx,["kind":"profile","dimension":"metering","nodeIds":[equip.id.id],"from":from.toIso,"to":(cutover+1min).toIso,"period":"hour","metric":"energy"],repo.records).first
    h:=EnerCubixHistoryData(crossing)
    check(h.read(from,cutover).value==10f,"cross-cutover query cleans only the raw prefix with the current rule")
    check(h.read(cutover,cutover+1min).value==77f,"cross-cutover query reads the published suffix without recleaning")
    check(value(nativeRollup(point.id,cutover,cutover+1min,"1min"))==Number(77,Unit("kWh")),"native query also retains the published suffix despite deltaMax 15")
    check(cx.db.readById(batch.id)["enerCubixIntervals"]==before,"normal queries never change published payload or its config version")

    record:=EnerCubixRepo.decode(cx.db.readById(equip.id)); record["cleaningEnabled"]=false; repo.save(record)
    disabled:=EnerCubixHistory.load(cx,["kind":"profile","dimension":"metering","nodeIds":[equip.id.id],"from":from.toIso,"to":cutover.toIso,"period":"hour","metric":"energy"],repo.records).first
    check(disabled["cleaning"]==null && !cx.db.readById(point.id).has("hisFunc"),"disabling cleaning stops applying the old profile to raw history")
    cx.db.commit(Diff(cx.db.readById(point.id),Etc.makeDict(["hisFunc":"hfTotalized","hisFuncWritable":Marker.val,"hisFuncConfig":Etc.makeDict(["deltaMin":Number(0),"defNull":Marker.val])])))
    external:=EnerCubixHistory.load(cx,["kind":"profile","dimension":"metering","nodeIds":[equip.id.id],"from":from.toIso,"to":cutover.toIso,"period":"hour","metric":"energy"],repo.records).first
    check(((Map)external["cleaning"])["externalFunctionManaged"]==true && ((Map)external["cleaning"])["function"]=="hfTotalized","report keeps the external function's output contract")
    externalRows:=HisItem[,]; cx.rt.his.read(cx.db.readById(point.id),Span.makeAbs(from,cutover),Etc.emptyDict) |item| {externalRows.add(item)}
    check(EnerCubixMath.maps(external["rawSamples"]).size==externalRows.size,"report preserves the external native output count, including empty output")
    check(((Map)((Map)external["cleaning"])["parameters"])["deltaMax"]==null,"external function parameters do not inherit the previous owned threshold")
    check(cx.db.readById(point.id)["hisFunc"]=="hfTotalized","report leaves the external history function intact")
    cx.db.commit(Diff(cx.db.readById(point.id),Etc.makeDict(["hisFunc":Remove.val,"hisFuncWritable":Remove.val,"hisFuncConfig":Remove.val])))
    record=EnerCubixRepo.decode(cx.db.readById(equip.id)); record["cleaningEnabled"]=true; repo.save(record)
    enabled:=EnerCubixHistory.load(cx,["kind":"profile","dimension":"metering","nodeIds":[equip.id.id],"from":from.toIso,"to":cutover.toIso,"period":"hour","metric":"energy"],repo.records).first
    check(EnerCubixHistoryData(enabled).read(from,cutover).value==10f,"reenabling cleaning uses the current profile")
    after:=HisItem[,]; cx.rt.his.read(cx.db.readById(point.id),null,Etc.makeDict(["raw":Marker.val])) |item| {after.add(item)}
    check(after.map |item->Obj?| {item.val}==raw.map |item->Obj?| {item.val},"rule changes and toggles preserve raw readings")
  }
  private Float? known(Str:Obj? result) { EnerCubixMath.num(EnerCubixMath.maps(((Map)result["summary"])["knownTotals"]).first?.get("value")) }
  private Grid nativeRollup(Ref id, DateTime from, DateTime to, Str interval, Bool preview := false)
  { (Grid)cx.evalOrReadAll("readById(@"+id.id+").hisRead("+dates(from,to)+(preview ? ",{enerCubixCleaningPreview}" : "")+").hisRollup(sum,"+interval+").hisClip") }
  private Str dates(DateTime from, DateTime to) { at(from)+".."+at(to) }
  private Str at(DateTime ts) { "dateTime("+ts.date+",time("+ts.hour+","+ts.min+","+ts.sec+"))" }
  private Obj? value(Grid grid) { grid.toRows.first?.get("v0") }
  private Void check(Bool ok, Str message) { if (!ok) throw Err(message); checks++ }
  private Void archive(Dict equip, Dict point)
  {
    EnerCubixMeterGeneration.ensure(cx.db,EnerCubixRepo.decode(cx.db.readById(equip.id)),repo.records,DateTime.now)
    [EnerCubixMeterHistory.stateId(point.id),EnerCubixMeterHistory.usageId(point.id)].each |id|
    {
      record:=cx.db.readById(id,false)
      if (record != null) { owned.add(id); cx.db.commit(Diff(record,Etc.makeDict(["enerCubixBoundaryAcceptance":Marker.val]))) }
    }
  }
  private Dict source(Str:Obj? tags)
  {
    tags=tags.dup; tags["enerCubixBoundaryAcceptance"]=Marker.val
    rec:=cx.db.commit(Diff.makeAdd(Etc.makeDict(tags))).newRec; owned.add(rec.id)
    return cx.db.readById(rec.id)
  }
  private Str:Obj? save(Str:Obj? data)
  {
    record:=repo.save(data); id:=Ref(record["id"].toStr); owned.add(id)
    cx.db.commit(Diff(cx.db.readById(id),Etc.makeDict(["enerCubixBoundaryAcceptance":Marker.val])))
    return EnerCubixRepo.decode(cx.db.readById(id))
  }
}

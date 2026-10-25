using haystack
using folio
using skyarcd

** Native tests own every fixture. Production projects are rejected before writes.
class EnerCubixCrossModuleAcceptance
{
  Context cx
  EnerCubixRepo repo
  Ref[] owned := [,]
  Ref[] points := [,]
  Ref[] equips := [,]
  Int checks := 0
  new make(Context cx) {this.cx=cx; repo=EnerCubixRepo(cx)}

  ** An isolated-only receipt makes a lost HTTP response reconcilable by read.
  Str:Obj? run(Str? runId := null)
  {
    if (!["finseed_acceptance","enerCubix_acceptance"].contains(cx.proj.name)) throw ArgErr("Cross-module acceptance requires the isolated project")
    repo.mustWrite
    if (runId == null) return runOwned
    if (!Regex<|[A-Za-z0-9-]{1,80}|>.matches(runId)) throw ArgErr("Invalid acceptance run ID")
    id:=Ref("enerCubix-accept-cross-"+runId.toBuf.toDigest("SHA-256").toHex[0..<24])
    prior:=cx.db.readById(id,false)
    if (prior != null)
    {
      if (prior["result"] is Str) return (Str:Obj?)util::JsonInStream(prior["result"].toStr.in).readJson
      return ["status":prior["status"],"runId":runId,"receiptId":id.id]
    }
    receipt:=cx.db.commit(Diff.makeAdd(Etc.makeDict(["enerCubixAcceptanceReceipt":Marker.val,"enerCubixAcceptanceRunId":runId,"status":"running","dis":"Cross-module acceptance receipt"]),id)).newRec
    try
    {
      result:=runOwned; result["runId"]=runId;result["receiptId"]=id.id
      cx.db.commit(Diff(cx.db.readById(receipt.id),Etc.makeDict(["status":"passed","result":util::JsonOutStream.writeJsonToStr(result)])))
      return result
    }
    catch (Err err)
    {
      cx.db.commit(Diff(cx.db.readById(receipt.id),Etc.makeDict(["status":"failed","error":err.toStr])))
      throw err
    }
  }

  private Str:Obj? runOwned()
  {
    if (!["finseed_acceptance","enerCubix_acceptance"].contains(cx.proj.name)) throw ArgErr("Cross-module acceptance requires the isolated project")
    repo.mustWrite
    prefix:="Cross module acceptance "+DateTime.nowTicks
    before:=Str:HisItem[][:]
    cases:=[Str:Obj?][,]
    try
    {
      category:=save(["kind":"category","name":prefix+" electricity","unit":"kWh"])
      sub:=save(["kind":"subcategory","name":prefix+" factors","categoryId":category["id"],"coalFactor":0.1f,"co2Factor":0.5f])
      utility:=save(["kind":"utility","name":prefix+" lighting","categoryId":category["id"]])
      organization:=save(["kind":"organization","name":prefix+" owner"])
      calendar:=save(["kind":"calendar","name":prefix+" calendar","workDays":[2],"workHours":[1],"peakHours":[1],"valleyHours":[0]])
      profile:=save(["kind":"cleaningProfile","name":prefix+" cleaner","mode":"drop","parameters":["deltaMin":0,"timeMax":"1h","defNull":true]])
      site:=source(["site":Marker.val,"dis":prefix,"tz":"Shanghai"])
      floor:=source(["floor":Marker.val,"dis":prefix+" floor","siteRef":site.id])
      from:=DateTime.fromIso("2026-10-20T00:00:00+08:00").toTimeZone(TimeZone.fromStr("Shanghai"))
      ["a","b"].each |name|
      {
        equip:=source(["equip":Marker.val,"dis":prefix+" "+name,"siteRef":site.id,"floorRef":floor.id]); equips.add(equip.id)
        point:=source(["point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"hisMode":"consumption","hisCollectInterval":Number(15,Unit("min")),"kind":"Number","unit":"kWh","tz":"Shanghai","dis":equip.dis+" reading","siteRef":site.id,"equipRef":equip.id]); points.add(point.id)
        repo.save(["id":equip.id.id,"mod":EnerCubixRepo.iso(equip["mod"]),"kind":"meter","name":equip.dis,"pointId":point.id.id,"categoryId":category["id"],"subcategoryId":sub["id"],"utilityId":utility["id"],"organizationId":organization["id"],"cleaningEnabled":true,"cleaningProfileId":profile["id"],"historyMode":"cumulative","autoSum":false,"area":100f])
        values:=name == "a" ? [100f,110f,105f,125f] : [50f,55f,55f,60f]
        rows:=HisItem[,]
        [0,60,90,120].each |minute,i| {rows.add(HisItem(from+Duration(minute*1min.ticks),Number(values[i],Unit("kWh"))))}
        [0,60,120].each |minute,i| {rows.add(HisItem(from-1day+Duration(minute*1min.ticks),Number([100f,105f,115f][i],Unit("kWh"))))}
        rows=rows.sort |a,b| {a.ts <=> b.ts}
        cx.rt.his.write(cx.db.readById(point.id),rows,null).get(1min)
        before[point.id.id]=rows
      }
      ["profile","ranking","proportion","utility","daily","comparison","dashboard","workingHours"].each |kind|
      {
        req:=request(kind,[equips[0].id],from)
        r:=repo.report(req)
        check(known(r)==30f,kind+" has the same known30")
        check(r["from"]==from.toIso && r["to"]==(from+150min).toIso,kind+" keeps the query bounds")
        cases.add(["kind":kind,"known":known(r),"asOf":r["asOf"]])
      }
      ["space","metering","organization"].each |dimension|
      {
        req:=request("ranking",equips.map |id->Str| {id.id},from); req["dimension"]=dimension
        total:=selection(repo.report(req))
        check(EnerCubixMath.num(total["knownValue"])==40f,dimension+" selection union is40")
        check(EnerCubixMath.strings(total["meterIds"]).sort==equips.map |id->Str| {id.id}.sort,dimension+" exposes the same effective IDs")
      }
      req:=request("dashboard",[organization["id"].toStr,equips[0].id],from); req["dimension"]="organization"
      check(EnerCubixMath.num(selection(repo.report(req))["knownValue"])==40f,"organization plus member does not double count")
      req=request("primary",[equips[0].id],from); req["metric"]="coal"
      check(known(repo.report(req))==3f,"coal derives from known30")
      req["metric"]="co2"; check(known(repo.report(req))==15f,"carbon derives from known30")
      req=request("proportion",[equips[0].id],from)
      row:=EnerCubixMath.maps(repo.report(req)["rows"]).first
      check(EnerCubixMath.num(row["knownPercentage"])==100f,"one positive known meter has100 percent of known use")
      req=request("comparison",[equips[0].id],from); req["otherFrom"]=(from-1day).toIso; req["otherTo"]=(from-1day+150min).toIso
      comparison:=EnerCubixMath.maps(((Map)repo.report(req)["extra"])["comparisons"]).first
      check(EnerCubixMath.num(comparison["knownCurrent"])==30f && EnerCubixMath.num(comparison["knownReference"])==15f,"comparison retains both observed quantities")
      check(comparison["percentage"]==null && comparison["difference"]==null,"incomplete comparison has no invented rate or difference")
      req=request("energyFlow",[equips[0].id],from); req["categoryId"]=category["id"]
      flow:=repo.report(req)
      node:=EnerCubixMath.maps(((Map)((Map)flow["extra"])["energyFlowOverview"])["rows"]).find |r| {r["id"]==equips[0].id}
      check(EnerCubixMath.num(node["value"])==30f,"flow own quantity equals profile despite historical topology sections")
      // Confirmed current hierarchy changes selection deduplication, not raw readings.
      parent:=EnerCubixRepo.decode(cx.db.readById(equips[0])); parent["kind"]="totalMeter"; parent["autoSum"]=false; repo.save(parent)
      child:=EnerCubixRepo.decode(cx.db.readById(equips[1])); child["meterParentId"]=equips[0].id; repo.save(child)
      req=request("ranking",equips.map |id->Str| {id.id},from)
      total:=selection(repo.report(req))
      check(EnerCubixMath.num(total["knownValue"])==30f && EnerCubixMath.strings(total["meterIds"])==[equips[0].id],"parent and child selection union counts the parent once")
      points.each |point|
      {
        after:=HisItem[,]; cx.rt.his.read(cx.db.readById(point),null,Etc.makeDict(["raw":Marker.val])) |item| {after.add(item)}
        check(after.map |item->Obj?| {item.val}==before[point.id].map |item->Obj?| {item.val},"raw readings are unchanged")
      }
    }
    finally {cleanup}
    remaining:=owned.findAll |id| {cx.db.readById(id,false)!=null}
    check(remaining.isEmpty,"all owned entities/configuration were removed")
    return ["status":"passed","checks":checks,"cases":cases,"ownedRemaining":remaining.size,"project":cx.proj.name,"auditHistoryRetained":true]
  }

  private Str:Obj? request(Str kind, Str[] ids, DateTime from)
  { ["kind":kind,"dimension":"metering","nodeIds":ids,"from":from.toIso,"to":(from+150min).toIso,"asOf":(from+130min).toIso,"period":"hour","metric":"energy","perArea":false,"workHours":[1]] }
  private Float? known(Str:Obj? r) {EnerCubixMath.num(EnerCubixMath.maps(((Map)r["summary"])["knownTotals"]).first?.get("value"))}
  private Str:Obj? selection(Str:Obj? r) {EnerCubixMath.maps(((Map)r["summary"])["selectionTotals"]).first ?: throw Err("Missing selection union")}
  private Void check(Bool ok, Str message) {if (!ok) throw Err(message); checks++}
  private Dict source(Str:Obj? tags)
  {tags=tags.dup.set("enerCubixCrossModuleAcceptance",Marker.val); rec:=cx.db.commit(Diff.makeAdd(Etc.makeDict(tags))).newRec; owned.add(rec.id); return cx.db.readById(rec.id)}
  private Str:Obj? save(Str:Obj? data)
  {r:=repo.save(data); id:=Ref(r["id"].toStr); owned.add(id); cx.db.commit(Diff(cx.db.readById(id),Etc.makeDict(["enerCubixCrossModuleAcceptance":Marker.val]))); return EnerCubixRepo.decode(cx.db.readById(id))}
  private Void cleanup()
  {
    owned.dup.reverse.each |id|
    {
      r:=cx.db.readById(id,false)
      if (r?.has("enerCubixCrossModuleAcceptance")==true) cx.db.commit(Diff(r,null,Diff.remove))
    }
    cx.db.readAllList(Filter.has("enerCubixComputed").or(Filter.has("enerCubixMeterGeneration")).or(Filter.has("enerCubixIntervalBatch")).or(Filter.has("enerCubixGenerationIssue"))).each |r|
    {
      main:=r["enerCubixMainRef"] as Ref; usage:=r["enerCubixIntervalSourceRef"] as Ref; owner:=r["enerCubixOwnerRef"] as Ref
      ownMain:=main != null && points.contains(main)
      ownUsage:=usage != null && points.contains(usage)
      ownIssue:=owner != null && equips.contains(owner)
      if ((ownMain && (r.has("enerCubixMeterGeneration") || r.has("enerCubixIntervalBatch"))) || (ownUsage && r.has("enerCubixComputed")) || (ownIssue && r.has("enerCubixGenerationIssue"))) cx.db.commit(Diff(r,null,Diff.remove))
    }
  }
}

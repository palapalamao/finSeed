using haystack
using folio
using skyarcd

** A virtual meter cleans its own stored readings independently of current children.
class EnerCubixCleaningVirtualAcceptance
{
  Context cx
  EnerCubixRepo repo
  Ref[] owned := [,]
  Int checks := 0
  new make(Context cx) { this.cx=cx; repo=EnerCubixRepo(cx) }

  Str:Obj? run()
  {
    if (!["finseed_acceptance","enerCubix_acceptance"].contains(cx.proj.name)) throw ArgErr("Virtual cleaning acceptance requires the isolated project")
    repo.mustWrite
    prefix:="Virtual own cleaning "+DateTime.nowTicks
    try
    {
      category:=save(["kind":"category","name":prefix+" energy","unit":"kWh"])
      site:=source(["site":Marker.val,"dis":prefix,"tz":"Shanghai"])
      main:=source(["equip":Marker.val,"dis":prefix+" main","siteRef":site.id])
      a:=source(["equip":Marker.val,"dis":prefix+" A","siteRef":site.id])
      b:=source(["equip":Marker.val,"dis":prefix+" B","siteRef":site.id])
      pMain:=point(main,site,"own total"); pA:=point(a,site,"counter A"); pB:=point(b,site,"counter B")
      mainProfile:=save(["kind":"cleaningProfile","name":prefix+" main profile","mode":"drop","parameters":["deltaMin":0,"timeMax":"1h","defNull":true]])
      profileA:=save(["kind":"cleaningProfile","name":prefix+" rollover A","mode":"rollover","parameters":["hisTotalizedRollover":32768,"deltaMax":100,"timeMax":"1h"]])
      profileB:=save(["kind":"cleaningProfile","name":prefix+" rollover B","mode":"rollover","parameters":["hisTotalizedRollover":100,"deltaMax":20,"timeMax":"1h"]])
      attach(main,pMain,category,mainProfile,null,true)
      check(cx.db.readById(pMain.id).has("enerCubixCleaningOwned"),"own cleaning can be enabled with no current children")
      attach(a,pA,category,profileA,main.id.id)
      attach(b,pB,category,profileB,main.id.id)
      from:=DateTime.fromIso("2026-10-02T00:00:00+08:00").toTimeZone(TimeZone.fromStr("Shanghai"))
      write(pA.id,from,[32760f,12f,22f]); write(pB.id,from,[99f,4f,7f]); write(pMain.id,from,[1000f,1010f,1025f])
      span:=Span.makeAbs(from,from+2hr)
      normal:=read(pMain.id,span,Etc.emptyDict)
      check(valueAt(normal,from) == Number(10,Unit("kWh")) && valueAt(normal,from+1hr) == Number(15,Unit("kWh")),"native virtual history cleans its own saved readings")
      request:=Str:Obj?["kind":"profile","dimension":"metering","nodeIds":[main.id.id],"from":from.toIso,"to":(from+2hr).toIso,"period":"hour","metric":"energy","perArea":false]
      total:=reportTotal(request)
      check(total["value"] == 25f,"virtual report matches its own native stored consumption")
      check(EnerCubixMath.strings(total["sourceIds"]) == [pMain.id.id],"virtual report identifies its own stored point")
      archive(main,pMain)
      profileA["mode"]="replace"; profileA["parameters"]=["deltaMin":0,"deltaMax":5,"defVal":["type":"na"],"timeMax":"1h"]
      profileA=repo.save(profileA)
      check(reportTotal(request)["value"] == 25f,"editing a child profile does not retroactively change parent history")
      disable:=EnerCubixRepo.decode(cx.db.readById(b.id)); disable["cleaningEnabled"]=false
      repo.save(disable)
      check(!cx.db.readById(pB.id).has("enerCubixCleaningOwned") && cx.db.readById(pMain.id).has("enerCubixCleaningOwned"),"child cleaning can be disabled without invalidating parent's own history")
      check(reportTotal(request)["value"] == 25f,"unconfigured current child does not remove parent historical values")
      mainProfile["mode"]="replace"; mainProfile["parameters"]=["deltaMin":0,"deltaMax":5,"timeMax":"1h","defVal":["type":"na"]]
      mainProfile=repo.save(mainProfile)
      normal=read(pMain.id,span,Etc.emptyDict)
      check(valueAt(normal,from) == Number(10,Unit("kWh")) && valueAt(normal,from+1hr) == Number(15,Unit("kWh")),"normal native history retains the frozen profile after an NA rule change")
      total=reportTotal(request)
      check(total["value"] == 25f,"normal report retains frozen own history after an NA rule change")
      naPreview:=EnerCubixCleaningRepo(repo).preview(["nodeId":main.id.id,"from":from.toIso,"to":(from+2hr).toIso])
      naRows:=EnerCubixMath.maps(naPreview["cleaned"])
      check(naRows.size == 2 && naRows.all |row| { row["value"] == null && row["valueType"] == "na" },"explicit preview keeps candidate NA distinct from zero")
      mainProfile["parameters"]=["deltaMin":0,"deltaMax":5,"timeMax":"1h","defVal":["type":"number","value":0,"unit":"kWh"]]
      mainProfile=repo.save(mainProfile)
      normal=read(pMain.id,span,Etc.emptyDict)
      check(valueAt(normal,from) == Number(10,Unit("kWh")) && valueAt(normal,from+1hr) == Number(15,Unit("kWh")),"normal native history is unchanged by a later zero replacement")
      total=reportTotal(request)
      check(total["value"] == 25f,"normal report retains its original own usage version")
      preview:=EnerCubixCleaningRepo(repo).preview(["nodeId":main.id.id,"from":from.toIso,"to":(from+2hr).toIso])
      previewRows:=EnerCubixMath.maps(preview["cleaned"])
      check(previewRows.size == 2 && previewRows.first["value"] == 0f && previewRows.last["value"] == 0f && previewRows.first["ts"] == from.toIso,"preview applies the total's own profile at native interval starts")
      check(EnerCubixMath.num(((Map)preview["summary"])["substitutedCount"]) == 2f,"preview identifies numeric substitutions under the candidate profile")
      after:=read(pMain.id,Span.makeAbs(from,from+3hr),Etc.makeDict(["raw":Marker.val])).findAll |item| { item.ts >= from && item.ts <= from+2hr }
      check(after.map |item->Obj?| { item.val } == Obj?[Number(1000,Unit("kWh")),Number(1010,Unit("kWh")),Number(1025,Unit("kWh"))],"own cleaning never rewrites raw total history")
      return ["status":"passed","project":cx.proj.name,"checks":checks]
    }
    finally
    {
      owned.dup.reverse.each |id| { record:=cx.db.readById(id,false); if (record != null && record.has("enerCubixCleaningVirtualAcceptance")) cx.db.commit(Diff(record,null,Diff.remove)) }
    }
  }

  private Void archive(Dict equip, Dict point)
  {
    EnerCubixMeterGeneration.ensure(cx.db,EnerCubixRepo.decode(cx.db.readById(equip.id)),repo.records,DateTime.now)
    [EnerCubixMeterHistory.stateId(point.id),EnerCubixMeterHistory.usageId(point.id)].each |id|
    {
      record:=cx.db.readById(id,false)
      if (record != null) { owned.add(id); cx.db.commit(Diff(record,Etc.makeDict(["enerCubixCleaningVirtualAcceptance":Marker.val]))) }
    }
  }

  private Void attach(Dict equip, Dict point, Str:Obj? category, Str:Obj? profile, Str? parent := null, Bool virtualTotal := false, Bool cleaning := true)
  {
    data:=Str:Obj?["id":equip.id.id,"mod":EnerCubixRepo.iso(equip["mod"]),"kind":virtualTotal ? "totalMeter" : "meter","name":equip.dis,"pointId":point.id.id,"categoryId":category["id"],"cleaningEnabled":cleaning,"cleaningProfileId":profile["id"],"historyMode":"cumulative","autoSum":virtualTotal,"includeInTotals":true]
    if (parent != null) data["meterParentId"]=parent
    repo.save(data)
  }
  private Dict source(Str:Obj? tags)
  {
    tags=tags.dup; tags["enerCubixCleaningVirtualAcceptance"]=Marker.val
    record:=cx.db.commit(Diff.makeAdd(Etc.makeDict(tags))).newRec
    owned.add(record.id); return cx.db.readById(record.id)
  }
  private Dict point(Dict equip, Dict site, Str name)
  { source(["point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"hisMode":"consumption","hisCollectInterval":Number(1,Unit("hr")),"kind":"Number","unit":"kWh","tz":"Shanghai","dis":name,"equipRef":equip.id,"siteRef":site.id]) }
  private Str:Obj? save(Str:Obj? data)
  {
    record:=repo.save(data); id:=Ref(record["id"].toStr); owned.add(id)
    cx.db.commit(Diff(cx.db.readById(id),Etc.makeDict(["enerCubixCleaningVirtualAcceptance":Marker.val])))
    return EnerCubixRepo.decode(cx.db.readById(id))
  }
  private Void write(Ref id, DateTime from, Float[] values)
  { rows:=HisItem[,]; values.each |v,i| { rows.add(HisItem(from+1hr*i,Number(v,Unit("kWh")))) }; cx.rt.his.write(cx.db.readById(id),rows,null).get(1min) }
  private HisItem[] read(Ref id, Span span, Dict opts)
  { rows:=HisItem[,]; cx.rt.his.read(cx.db.readById(id),span,opts) |HisItem item| { rows.add(item) }; return rows }
  private Obj? valueAt(HisItem[] values, DateTime at) { values.find |item| { item.ts == at }?.val }
  private Str:Obj? reportTotal(Str:Obj? request)
  { result:=repo.report(request); summary:=(Map)result["summary"]; return EnerCubixMath.maps(summary["totals"]).first ?: throw Err("Virtual report has no total") }
  private Void check(Bool value, Str message) { if (!value) throw Err(message); checks++ }
}

using haystack
using folio
using skyarcd

** Own stored history remains readable when current physical/virtual children change.
class EnerCubixOwnedHistoryAcceptance
{
  Context cx
  EnerCubixRepo repo
  Ref[] owned := [,]
  Int checks := 0
  new make(Context cx) { this.cx=cx; repo=EnerCubixRepo(cx) }

  Str:Obj? run(Bool leakOnly := false)
  {
    if (!["finseed_acceptance","enerCubix_acceptance"].contains(cx.proj.name)) throw ArgErr("Owned-history acceptance requires the isolated project")
    repo.mustWrite
    prefix:="Owned history "+DateTime.nowTicks
    from:=DateTime.fromIso("2026-10-10T00:00:00+08:00").toTimeZone(TimeZone.fromStr("Shanghai"))
    try
    {
      category:=save(["kind":"category","name":prefix+" energy","unit":"kWh"])
      profile:=save(["kind":"cleaningProfile","name":prefix+" clean","mode":"drop","parameters":["deltaMin":0,"deltaMax":1000,"timeMax":"1h","defNull":true]])
      site:=source(["site":Marker.val,"dis":prefix,"tz":"Shanghai"])
      equip:=source(["equip":Marker.val,"dis":prefix+" total","siteRef":site.id])
      point:=source(["point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"hisMode":"consumption","hisCollectInterval":Number(15,Unit("min")),"kind":"Number","unit":"kWh","tz":"Shanghai","dis":prefix+" raw","equipRef":equip.id,"siteRef":site.id])
      repo.save(["id":equip.id.id,"mod":EnerCubixRepo.iso(equip["mod"]),"kind":"totalMeter","name":equip.dis,"pointId":point.id.id,"categoryId":category["id"],"autoSum":true,"cleaningEnabled":true,"cleaningProfileId":profile["id"],"includeInTotals":true])
      check(cx.db.readById(point.id).has("enerCubixCleaningOwned"),"a total's own historical cleaning can be configured before children are ready")
      raw:=[HisItem(from,Number(1000,Unit("kWh"))),HisItem(from+15min,Number(1010,Unit("kWh"))),HisItem(from+30min,Number(1025,Unit("kWh"))),HisItem(from+45min,Number(1040,Unit("kWh"))),HisItem(from+1hr,Number(1060,Unit("kWh")))]
      cx.rt.his.write(cx.db.readById(point.id),raw,null).get(1min)
      req:=Str:Obj?["kind":"trend","dimension":"metering","nodeIds":[equip.id.id],"from":from.toIso,"to":(from+1hr).toIso,"period":"hour","metric":"energy","perArea":false]
      expected:=raw.findAll |i| { i.ts < from+1hr }.map |i->Float?| { ((Number)i.val).toFloat }
      baseline:=repo.report(req)
      check(values(baseline) == expected,"trend shows own stored cumulative readings; expected="+expected+", actual="+values(baseline))
      check(EnerCubixMath.maps(((Map)baseline["extra"])["cleaning"]).isEmpty,"raw trend bypasses consumption cleaning metadata")
      child:=source(["equip":Marker.val,"dis":prefix+" late physical child","siteRef":site.id,"enerCubix":Marker.val,"enerCubixKind":"meter","enerCubixMeterParentRef":equip.id,"enerCubixCategoryRef":Ref(category["id"].toStr),"enerCubixPointRef":Ref.gen])
      check(values(repo.report(req)) == expected,"an unavailable newly added physical child does not change old total raw history")
      virtualChild:=source(["equip":Marker.val,"dis":prefix+" late virtual child","siteRef":site.id,"enerCubix":Marker.val,"enerCubixKind":"totalMeter","enerCubixAutoSum":true,"enerCubixMeterParentRef":equip.id,"enerCubixCategoryRef":Ref(category["id"].toStr),"enerCubixPointRef":Ref.gen])
      check(values(repo.report(req)) == expected,"a newly added nested virtual child does not change old total raw history")
      balanceReq:=req.dup;balanceReq["kind"]="leak";balanceReq["asOf"]=DateTime.now.toIso
      balance:=repo.report(balanceReq)
      ownUsage:=EnerCubixMath.maps(((Map)balance["extra"])["leakOwnUsage"])
      ownTotal:=ownUsage.find |r| {r["nodeId"] == equip.id.id}
      check(ownTotal != null && ownTotal["value"] == 60f,"leak report reads the selected total's own stored history even before historical membership is confirmed")
      balanceTotal:=EnerCubixMath.maps(((Map)balance["extra"])["leakTotals"]).first
      check(balanceTotal["knownTotal"] == 60f && balanceTotal["difference"] == null && balanceTotal["percentage"] == null,"unavailable child data cannot hide own usage or create a leakage claim")
      check(balance["from"] == balanceReq["from"] && balance["to"] == balanceReq["to"] && balance["asOf"] == balanceReq["asOf"],"leak report keeps the exact requested range and fixed cutoff")
      if (leakOnly) return ["status":"passed","checks":checks,"project":cx.proj.name,"request":balanceReq,"report":balance]
      req["kind"]="profile"
      report:=repo.report(req)
      total:=EnerCubixMath.maps(((Map)report["summary"])["totals"]).first
      check(total != null && total["value"] == 60f,"normal energy query cleans the selected total's own stored readings")
      own:=EnerCubixHistory.cleanRead(cx,cx.db.readById(point.id),Span.makeAbs(from,from+1hr),Etc.emptyDict,Etc.emptyDict)
      check(EnerCubixMath.strings(own.summary["sourceIds"]) == [point.id.id],"normal cleaning provenance identifies the selected stored point")
      [child,virtualChild].each |member|
      {
        current:=cx.db.readById(member.id)
        repo.remove(member.id.id,EnerCubixRepo.iso(current["mod"]))
        preservedMember:=cx.db.readById(member.id,false)
        check(preservedMember != null && preservedMember.has("equip") && !preservedMember.has("enerCubixKind"),"removing a physical or virtual child clears configuration and preserves native equipment")
      }
      req["kind"]="trend"
      check(values(repo.report(req)) == expected,"removing children leaves selected total raw history unchanged")
      EnerCubixMeterGeneration.ensure(cx.db,EnerCubixRepo.decode(cx.db.readById(equip.id)),repo.records,DateTime.now)
      stateId:=EnerCubixMeterHistory.stateId(point.id)
      state:=cx.db.readById(stateId)
      check(((Dict)state["enerCubixGenerationLegacyConfig"])["deltaMax"] == Number(1000,Unit("kWh")),"archive activation freezes the original own cleaning threshold")
      [stateId,EnerCubixMeterHistory.usageId(point.id)].each |id|
      {
        record:=cx.db.readById(id,false)
        if (record != null) { owned.add(id); cx.db.commit(Diff(record,Etc.makeDict(["enerCubixOwnedHistoryAcceptance":Marker.val]))) }
      }
      profile["parameters"]=["deltaMin":0,"deltaMax":1,"timeMax":"1h","defNull":true]
      profile=repo.save(profile)
      req["kind"]="profile"
      frozenReport:=repo.report(req)
      frozenTotal:=EnerCubixMath.maps(((Map)frozenReport["summary"])["totals"]).first
      check(frozenTotal != null && frozenTotal["value"] == 60f,"a later tiny threshold does not silently re-clean pre-cutover report history")
      nativeRows:=HisItem[,]; cx.rt.his.read(cx.db.readById(point.id),Span.makeAbs(from,from+1hr),Etc.emptyDict) |item| { nativeRows.add(item) }
      nativeTotal:=0f; nativeRows.each |item| { if (item.ts >= from && item.ts < from+1hr && item.val is Number) nativeTotal+=((Number)item.val).toFloat }
      check(nativeTotal == 60f,"native consumption history uses the same frozen legacy profile")
      preview:=EnerCubixCleaningRepo(repo).preview(["nodeId":equip.id.id,"from":from.toIso,"to":(from+1hr).toIso])
      previewRows:=EnerCubixMath.maps(preview["cleaned"])
      check(previewRows.size == 4 && previewRows.all |row| { row["value"] == null },"explicit preview may apply the newest threshold without rewriting legacy history")
      preserved:=HisItem[,]; cx.rt.his.read(cx.db.readById(point.id),Span.makeAbs(from,from+1hr+1min),Etc.makeDict(["raw":Marker.val])) |i| { if (i.ts >= from && i.ts <= from+1hr) preserved.add(i) }
      check(preserved.map |i->Obj?| { i.val } == raw.map |i->Obj?| { i.val },"queries never rewrite selected point raw history")
      req["kind"]="energyFlow"; req["categoryId"]=category["id"]; req["nodeIds"]=Str[,]; req["from"]=(from-1hr).toIso
      flow:=repo.report(req)
      overview:=((Map)flow["extra"])["energyFlowOverview"] as Map
      check(overview != null && EnerCubixMath.maps(flow["rows"]).size == 1,"unknown historic project topology still returns the meter's own history")
      row:=EnerCubixMath.maps(flow["rows"]).first
      check(row["value"] == 60f && row["coverage"] == 0.5f && row["complete"] == false,"whole-range own subtotal and duration coverage preserve a real leading gap")
      parts:=EnerCubixMath.maps(((Map)flow["extra"])["energyFlowSegments"])
      check(parts.size == 1 && EnerCubixMath.maps(((Map)parts.first["energyFlow"])["links"]).isEmpty,"unknown topology does not fabricate links")
      check(flow["from"] == req["from"] && flow["to"] == req["to"],"flow overview preserves the full requested period")
      return ["status":"passed","checks":checks,"project":cx.proj.name]
    }
    finally
    {
      owned.dup.reverse.each |id| { r:=cx.db.readById(id,false); if (r != null && r.has("enerCubixOwnedHistoryAcceptance")) cx.db.commit(Diff(r,null,Diff.remove)) }
    }
  }

  private Float?[] values(Str:Obj? report)
  { EnerCubixMath.maps(EnerCubixMath.maps(report["series"]).first?.get("points")).map |p->Float?| { EnerCubixMath.num(p["value"]) } }
  private Dict source(Str:Obj? tags)
  { tags=tags.dup; tags["enerCubixOwnedHistoryAcceptance"]=Marker.val; r:=cx.db.commit(Diff.makeAdd(Etc.makeDict(tags))).newRec; owned.add(r.id); return cx.db.readById(r.id) }
  private Str:Obj? save(Str:Obj? data)
  { r:=repo.save(data); id:=Ref(r["id"].toStr); owned.add(id); cx.db.commit(Diff(cx.db.readById(id),Etc.makeDict(["enerCubixOwnedHistoryAcceptance":Marker.val]))); return EnerCubixRepo.decode(cx.db.readById(id)) }
  private Void check(Bool pass, Str message) { if (!pass) throw Err(message); checks++ }
}

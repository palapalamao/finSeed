using haystack
using folio
using skyarcd

** Covers the actual Repo -> native history -> temporal flow integration.
class EnerCubixFlowHistoryAcceptance
{
  Context cx
  EnerCubixRepo repo
  Ref[] owned := [,]
  Ref[] mainPoints := [,]
  new make(Context cx) { this.cx=cx; repo=EnerCubixRepo(cx) }

  Str:Obj? run()
  {
    if (!["finseed_acceptance","enerCubix_acceptance"].contains(cx.proj.name)) throw ArgErr("Flow acceptance requires the isolated project")
    repo.mustWrite
    prefix:="Flow history "+DateTime.nowTicks
    try
    {
      cat:=repo.save(["kind":"category","name":prefix,"unit":"kWh"]); owned.add(Ref(cat["id"].toStr))
      total:=meter(prefix+" total",cat["id"].toStr,null)
      child:=meter(prefix+" child",cat["id"].toStr,total.id)
      at:=EnerCubixMeterHistory.floorMinute(DateTime.now)+1min
      [total,child].each |equip|
      {
        record:=EnerCubixRepo.decode(cx.db.readById(equip.id))
        EnerCubixMeterGeneration.ensure(cx.db,record,repo.records,at)
        point:=cx.db.readById((Ref)cx.db.readById(equip.id)["enerCubixPointRef"])
        mainPoints.add(point.id)
        [EnerCubixMeterHistory.stateId(point.id),EnerCubixMeterHistory.usageId(point.id)].each |id| { if (!owned.contains(id)) owned.add(id) }
        [EnerCubixValue(10f,"cleaned"),EnerCubixValue(null,"filtered"),EnerCubixValue(20f,"cleaned")].each |value,i|
        {
          state:=cx.db.readById(EnerCubixMeterHistory.stateId(point.id))
          EnerCubixMeterGeneration.publish(cx.db,point,state,at+1min*i,at+1min*(i+1),value,DateTime.now,false)
        }
      }
      req:=Str:Obj?["kind":"energyFlow","dimension":"metering","categoryId":cat["id"],"nodeIds":[total.id.id],"from":at.toIso,"to":(at+3min+50sec).toIso,"period":"hour","metric":"energy","perArea":false]
      result:=repo.report(req)
      parts:=EnerCubixMath.maps(((Map)result["extra"])["energyFlowSegments"])
      if (parts.size != 4) throw Err("Native report did not split valid, filtered and unpublished intervals; segments="+parts.size)
      first:=(Map)parts[0]["energyFlow"]; last:=(Map)parts[2]["energyFlow"]
      if (EnerCubixMath.maps(first["links"]).size != 1 || EnerCubixMath.maps(last["links"]).size != 1) throw Err("Native report lost complete stored flow intervals")
      if (EnerCubixMath.num(EnerCubixMath.maps(last["nodes"]).find |n| { n["id"] == total.id.id }["value"]) != 20f) throw Err("Native flow changed stored usage")
      return ["status":"passed","checks":4,"segments":parts.size,"from":result["from"],"to":result["to"]]
    }
    finally
    {
      mainPoints.each |point|
      {
        cx.db.readAllList(Filter.has("enerCubixIntervalBatch").and(Filter.eq("enerCubixMainRef",point))).each |batch| { owned.add(batch.id) }
      }
      owned.dup.unique.reverse.each |id| { r:=cx.db.readById(id,false); if (r != null) cx.db.commit(Diff(r,null,Diff.remove)) }
    }
  }

  private Dict meter(Str name, Str category, Ref? parent)
  {
    equip:=cx.db.commit(Diff.makeAdd(Etc.makeDict(["equip":Marker.val,"dis":name]))).newRec; owned.add(equip.id)
    point:=cx.db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"kind":"Number","unit":"kWh","tz":"Shanghai","equipRef":equip.id,"dis":name+" source"]))).newRec; owned.add(point.id)
    data:=Str:Obj?["id":equip.id.id,"mod":EnerCubixRepo.iso(equip["mod"]),"kind":parent == null ? "totalMeter" : "meter","name":name,"categoryId":category,"pointId":point.id.id,"includeInTotals":true]
    if (parent != null) data["meterParentId"]=parent.id
    else data["autoSum"]=true
    repo.save(data)
    return cx.db.readById(equip.id)
  }
}

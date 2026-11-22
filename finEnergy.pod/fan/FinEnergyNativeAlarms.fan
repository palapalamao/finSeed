using haystack
using folio
using hx
using alarmExt

** Hourly evidence shares one native source for each continuous exceedance.
** Physical point and connector alarms keep their independent lifecycle.
class FinEnergyNativeAlarms
{
  FinEnergyRepo repo
  new make(FinEnergyRepo repo) { this.repo=repo }

  static Ref nativeId(Str eventId) { Ref(AlarmFuncs.toKey(Ref(eventId),"offNormal")) }

  internal [Str:Obj?] rootOf([Str:Obj?] event)
  {
    if (event["episodeId"] == null || event["episodeId"] == event["id"]) return event
    root:=FinEnergyRepo.decode(repo.stored(event["episodeId"].toStr))
    if (root["kind"] != "alarm" || root["nodeId"] != event["nodeId"] || root["categoryId"] != event["categoryId"] || root["unit"] != event["unit"]) throw ArgErr("原生报警关联不匹配")
    return root
  }

  internal Void applyEpisode([Str:Obj?] episode, Str? evaluated)
  {
    repo.mustWrite
    root:=FinEnergyRepo.decode(repo.stored(episode["rootId"].toStr))
    if (root["nativeAlarmId"] != null && Ref(root["nativeAlarmId"].toStr).toProjRel != nativeId(root["id"].toStr))
    {
      rootOf(root) // validate an earlier grouping before detaching a split episode
      root.remove("nativeAlarmId")
    }
    root["episodeId"]=root["id"]; root["episodeStartTs"]=episode["startTs"]
    root["lastTs"]=episode["lastTs"]; root["recoveredAt"]=episode["recoveredAt"]
    if (episode["recoveryValue"] != null) root["recoveryValue"]=episode["recoveryValue"]
    if (evaluated != null && (root["lastEvaluatedTs"] == null || DateTime.fromIso(evaluated) > DateTime.fromIso(root["lastEvaluatedTs"].toStr))) root["lastEvaluatedTs"]=evaluated
    root=ensure(repo.save(root,true))
    ((List)episode["memberIds"]).each |member|
    {
      if (member == root["id"]) return
      child:=FinEnergyRepo.decode(repo.stored(member.toStr))
      prior:=AlarmFuncs.alarmsGetById(nativeId(member.toStr))
      if (prior != null)
      {
        legacy:=child.dup; legacy.remove("episodeId")
        checkOwned(legacy,prior)
        // Archive before retiring only this owned duplicate from the current
        // native database. Native alarm history is never cleared.
        child["nativeAlarmArchive"]=ZincWriter.gridToStr(Etc.makeDictsGrid(null,[prior]))
        child["priorAckBy"]=prior.ackedBy; child["priorAckAt"]=FinEnergyRepo.iso(prior.acked)
        child["priorAckNote"]=prior.ackMessage
      }
      child["episodeId"]=root["id"]; child["nativeAlarmId"]=root["nativeAlarmId"]
      child.remove("recoveredAt")
      repo.save(child,true)
      if (prior != null) AlarmFuncs.alarmsRemove([prior.id])
      source:=repo.stored(member.toStr)
      if (source.has("inAlarm")) AlarmFuncs.toNormalNew([source.id],"FIN Energy | merged",null,Etc.makeDict(["ackRequired":false]))
    }
    if (root["recoveredAt"] != null && root["nativeAlarmId"] != null)
    {
      alarm:=AlarmFuncs.alarmsGetById(nativeId(root["id"].toStr))
      if (alarm != null)
      {
        checkOwned(root,alarm)
        root=project(FinEnergyRepo.decode(repo.stored(root["id"].toStr)),alarm)
        repo.save(root,true) // retain native confirmation even if recovery archives it
        if (alarm.active)
        {
          AlarmLib lib:=HxContext.curHx.rt.lib("alarm")
          tracker:=AlarmTracker([Ref(root["id"].toStr)],lib,AlarmDispatcher.INTERNAL)
          // Restore the native tracker's cache from its persisted active state.
          // A fresh tracker otherwise ignores a request to disable a state.
          tracker.enabledStates["offNormal"]=true
          meta:=metadata(root)
          if (root["recoveryValue"] != null) meta=Etc.dictSet(meta,"sourceValue",Number(FinEnergyConfig.number(root["recoveryValue"]),Unit.fromStr(root["unit"].toStr,false)))
          tracker.transition("offNormal",false,DateTime.fromIso(root["recoveredAt"].toStr),"FIN Energy | normal",null,null,meta).get(30sec)
        }
      }
      root=FinEnergyRepo.decode(repo.stored(root["id"].toStr))
      root["nativeRecoveredAt"]=root["recoveredAt"]
      repo.save(root,true)
    }
  }

  [Str:Obj?] ensure([Str:Obj?] event)
  {
    repo.mustWrite
    event=rootOf(event)
    source:=repo.stored(event["id"].toStr)
    if (source["finEnergyKind"] != "alarm") throw ArgErr("记录不是报警")
    event=FinEnergyRepo.decode(source)
    // Preserve closed legacy events; importing them must not reopen old alarms.
    if (event["nativeAlarmId"] == null && event["state"] == "acknowledged") return event
    id:=nativeId(event["id"].toStr)
    if (event["nativeAlarmId"] != null && Ref(event["nativeAlarmId"].toStr).toProjRel != id) throw ArgErr("原生报警关联不匹配")
    alarm:=AlarmFuncs.alarmsGetById(id)
    if (alarm == null)
    {
      // Native operator removal is authoritative. Do not resurrect linked alarms.
      if (event["nativeAlarmId"] != null) return event
      tags:=Str:Obj?["finEnergyEnergyAlarmSource":Marker.val,"navName":event["name"]]
      node:=repo.cx.db.readById(Ref(event["nodeId"].toStr),false)
      if (node != null)
      {
        ["siteRef","floorRef"].each |key| { if (node[key] is Ref) tags[key]=node[key] }
        if (node.has("equip")) tags["equipRef"]=node.id
        else if (node["equipRef"] is Ref) tags["equipRef"]=node["equipRef"]
      }
      repo.cx.db.commit(Diff(source,Etc.makeDict(tags)))
      value:=event["value"].toStr
      limit:=event["limit"].toStr
      name:=event["name"].toStr
      symbol:=event["unit"]?.toStr ?: ""
      // Symbols, original object names and units keep persisted event text neutral.
      message:="FIN Energy | $name | $value > $limit $symbol"
      alarm=AlarmFuncs.toAlarmNew([source.id],"offNormal",message,DateTime.fromIso(event["ts"].toStr),null,metadata(event)).first
      if (alarm == null) throw Err("FIN 原生报警创建失败")
    }
    checkOwned(event,alarm)
    if (event["nativeAlarmId"] == null)
    {
      // The native engine may have updated source.inAlarm/mod. Link against the
      // fresh source; a failed link can be reconciled by its stable native ID.
      source=repo.stored(event["id"].toStr)
      repo.cx.db.commit(Diff(source,Etc.makeDict(["finEnergyNativeAlarmRef":alarm.id])))
      event=FinEnergyRepo.decode(repo.stored(event["id"].toStr))
    }
    return project(event,alarm)
  }

  [Str:Obj?][] list()
  {
    return nativeEvents(FinEnergyAlarmGroups(source(true)).events)
  }

  Str:Obj? page(Int offset,Int limit,Str state,Str? target)
  {FinEnergyAlarmGroups.page(nativeEvents(FinEnergyAlarmGroups(source(false)).events(false)),offset,limit,state,target)}

  Str:Obj? detail(Str id)
  {
    selected:=source(false).findAll |r| {r["id"]==id || r["episodeId"]==id}
    full:=selected.map |r->Str:Obj?| {FinEnergyRepo.decode(repo.stored(r["id"].toStr))}
    event:=FinEnergyAlarmGroups(full).event(id,true)
    if(event==null) throw FinEnergyHttpErr(404,"NOT_FOUND","记录不存在")
    return nativeEvents([event]).first
  }

  private [Str:Obj?][] source(Bool full)
  {
    repo.mustRead;repo.requireConfigurationAccess
    rows:=repo.cx.db.readAllList(Filter.has("finEnergyKind").and(Filter.eq("finEnergyKind","alarm")).and(Filter.has("finEnergy").or(Filter.has("equip"))))
    return rows.findAll |r| {repo.cx.canRead(r)}.map |r->Str:Obj?| {full ? FinEnergyRepo.decode(r) : FinEnergyCockpitInput.decode(r,null)}
  }

  private [Str:Obj?][] nativeEvents([Str:Obj?][] events)
  {
    ids:=events.findAll |r| { r["nativeAlarmId"] != null }.map |r->Ref| { Ref(r["nativeAlarmId"].toStr).toProjRel }
    if (ids.isEmpty) return events
    AlarmLib lib:=HxContext.curHx.rt.lib("alarm")
    Alarm[] alarms:=lib.db.get(HxContext.curHx,ids).get(30sec)
    index:=Str:Alarm[:];alarms.each |alarm| {index[alarm.id.toProjRel.id]=alarm}
    return events.map |event->[Str:Obj?]|
    {
      if (event["nativeAlarmId"] == null) return event
      alarm:=index[Ref(event["nativeAlarmId"].toStr).toProjRel.id]
      if (alarm == null)
      {
        result:=event.dup
        if (event["nativeRecoveredAt"] != null) { result["nativeActive"]=false; result["nativeState"]="normal" }
        else result["nativeAlarmMissing"]=true
        return result
      }
      checkOwned(event,alarm)
      return project(event,alarm)
    }
  }

  [Str:Obj?] acknowledge([Str:Obj?] event, Str note)
  {
    event=ensure(event)
    if (event["nativeAlarmId"] == null) return event
    alarm:=AlarmFuncs.alarmsGetById(Ref(event["nativeAlarmId"].toStr).toProjRel)
    if (alarm == null)
    {
      if (event["nativeRecoveredAt"] != null && event["state"] == "acknowledged") return event
      throw ArgErr("原生报警已移除，请刷新原生报警列表")
    }
    checkOwned(event,alarm)
    if (!alarm.isAcked)
    {
      alarm=AlarmFuncs.alarmAck(alarm.id,note).first
      if (alarm == null || !alarm.isAcked) throw Err("FIN 原生报警确认失败")
    }
    return project(FinEnergyRepo.decode(repo.stored(event["id"].toStr)),alarm)
  }

  internal static Dict metadata([Str:Obj?] event)
  {
    unit:=Unit.fromStr(event["unit"]?.toStr ?: "",false)
    return Etc.makeDict(["finEnergyEnergyAlarm":Marker.val,"finEnergyEventRef":Ref(event["id"].toStr),
      "finEnergyNodeRef":Ref(event["nodeId"].toStr),"finEnergyCategoryRef":Ref(event["categoryId"].toStr),
      "finEnergySourceRefs":((List)(event["sourceIds"] ?: Str[,])).map |v->Ref| { Ref(v.toStr) },
      "finEnergyLimit":Number(FinEnergyConfig.number(event["limit"]),unit),
      "sourceValue":Number(FinEnergyConfig.number(event["value"]),unit),"sourceStatus":event["quality"] ?: "ok","ackRequired":Marker.val])
  }

  internal static Void checkOwned([Str:Obj?] event, Dict alarm)
  {
    meta:=alarm["metadata"] as Dict
    source:=alarm["sourceRef"] as Ref
    eventRef:=meta?.get("finEnergyEventRef") as Ref
    if (alarm.id.toProjRel != nativeId(event["id"].toStr) || source?.toProjRel != Ref(event["id"].toStr).toProjRel ||
        alarm["state"] != "offNormal" || meta?.has("finEnergyEnergyAlarm") != true || eventRef?.toProjRel != source?.toProjRel)
      throw ArgErr("原生报警关联不匹配")
  }

  internal static [Str:Obj?] project([Str:Obj?] event, Dict alarm)
  {
    result:=event.dup
    result["nativeAlarmId"]=alarm.id.id
    result["nativeState"]=alarm["state"]
    result["nativeActive"]=alarm.has("active")
    result["state"]=alarm["acked"] == null ? "open" : "acknowledged"
    result["ackBy"]=alarm["ackedBy"]
    result["ackAt"]=FinEnergyRepo.iso(alarm["acked"])
    result["ackNote"]=alarm["ackMessage"]
    return result
  }
}

using haystack
using folio
using skyarcd
using alarmExt

** Native lifecycle checks run only in the isolated project with owned fixtures.
class EnerCubixNativeAlarmAcceptance
{
  Context cx
  EnerCubixRepo repo
  Ref[] owned := [,]
  Ref[] nativeIds := [,]
  new make(Context cx) { this.cx=cx; repo=EnerCubixRepo(cx) }

  Str:Obj? run()
  {
    if (cx.proj.name != "enerCubix_acceptance") throw ArgErr("Native alarm acceptance requires isolated project")
    repo.mustWrite
    prefix:="native-alarm-acceptance-"+DateTime.nowTicks
    bridge:=EnerCubixNativeAlarms(repo)
    checks:=Str[,]
    try
    {
      site:=source(["site":Marker.val,"dis":prefix+" site","tz":"Shanghai"])
      meter:=source(["equip":Marker.val,"dis":prefix+" meter","siteRef":site.id])
      category:=repo.save(["kind":"category","name":prefix+" electricity","unit":"kWh"])
      owned.add(Ref(category["id"].toStr))
      first:=event(prefix+" A",meter.id,category["id"].toStr)
      linked:=bridge.ensure(first)
      id:=Ref(linked["nativeAlarmId"].toStr); nativeIds.add(id)
      alarm:=AlarmFuncs.alarmsGetById(id)
      require(alarm != null && alarm.has("alarm") && alarm.ackRequired,"native create")
      require(alarm.sourceRef.toProjRel == Ref(first["id"].toStr).toProjRel,"hourly event source")
      require(((Number)alarm.curVal).unit == Unit("kWh"),"native value unit")
      require(repo.stored(first["id"].toStr)["siteRef"] == site.id,"navigation scope")
      require(bridge.ensure(first)["nativeAlarmId"] == id.id,"duplicate ensure")
      require(AlarmFuncs.alarms(Ref(first["id"].toStr)).size == 1,"one native alarm")
      checks.add("native creation, units, location and idempotence")

      current:=repo.stored(first["id"].toStr)
      cx.db.commit(Diff(current,Etc.makeDict(["enerCubixNativeAlarmRef":Remove.val])))
      require(bridge.ensure(EnerCubixRepo.decode(repo.stored(first["id"].toStr)))["nativeAlarmId"] == id.id,"link recovery")
      require(AlarmFuncs.alarms(Ref(first["id"].toStr)).size == 1,"no duplicate after recovery")
      checks.add("interrupted linking reconciles native alarm")

      AlarmFuncs.alarmAck(id,"confirmed from native Alarm")
      projected:=bridge.list.find |r| { r["id"] == first["id"] }
      require(projected["state"] == "acknowledged" && projected["ackNote"] == "confirmed from native Alarm","native confirmation projection")
      require(projected["ackBy"] == AlarmFuncs.alarmsGetById(id).ackedBy,"native actor")
      require(bridge.ensure(first)["state"] == "acknowledged","rescan preserves acknowledgement")
      checks.add("native confirmation reflected in energy list")

      second:=bridge.ensure(event(prefix+" B",meter.id,category["id"].toStr))
      secondId:=Ref(second["nativeAlarmId"].toStr); nativeIds.add(secondId)
      confirmed:=repo.acknowledge(second["id"].toStr,second["mod"],"confirmed from energy list")
      nativeAck:=AlarmFuncs.alarmsGetById(secondId)
      require(nativeAck.isAcked && nativeAck.ackMessage == "confirmed from energy list","energy confirmation reaches native")
      require(confirmed["ackAt"] == nativeAck.acked.toIso && confirmed["ackBy"] == nativeAck.ackedBy,"same native identity and time")
      checks.add("energy confirmation uses native actor, time and note")

      legacy:=event(prefix+" legacy",meter.id,category["id"].toStr,"acknowledged")
      require(bridge.ensure(legacy)["nativeAlarmId"] == null,"closed legacy must not reopen")
      require(AlarmFuncs.alarmsGetById(EnerCubixNativeAlarms.nativeId(legacy["id"].toStr)) == null,"no closed legacy native alarm")
      AlarmFuncs.alarmsRemove([secondId])
      bridge.ensure(second)
      require(AlarmFuncs.alarmsGetById(secondId) == null,"native removal stays removed")
      checks.add("closed legacy and native removal remain authoritative")
      continuation:=bridge.ensure(event(prefix+" continuation",meter.id,category["id"].toStr,"open",14))
      continuationId:=Ref(continuation["nativeAlarmId"].toStr); nativeIds.add(continuationId)
      AlarmFuncs.alarmAck(continuationId,"original child confirmation")
      evidence:=[EnerCubixRepo.decode(repo.stored(first["id"].toStr)),continuation]
      observations:=[observation(13,19.390625f),observation(14,15f)]
      apply(bridge,evidence,observations)
      require(AlarmFuncs.alarmsGetById(continuationId) == null,"superseded native current record retired")
      require(repo.stored(continuation["id"].toStr)["enerCubixAlarmEpisodeRef"] == Ref(first["id"].toStr),"hourly evidence shares episode")
      require(!repo.stored(continuation["id"].toStr).has("inAlarm"),"merged child source is normal")
      archived:=EnerCubixRepo.decode(repo.stored(continuation["id"].toStr))
      require(archived["nativeAlarmArchive"] != null,"original native record archived")
      require(archived["priorAckNote"] == "original child confirmation","merged child acknowledgement preserved")
      grouped:=bridge.list.find |r| { r["id"] == first["id"] }
      require(grouped["hourCount"] == 2 && grouped["state"] == "acknowledged","continued exceedance preserves native acknowledgement")
      checks.add("continuous exceedance merges native alarms and retains hourly evidence")

      observations.add(observation(15,7f))
      evidence=evidence.map |e->[Str:Obj?]| { EnerCubixRepo.decode(repo.stored(e["id"].toStr)) }
      apply(bridge,evidence,observations)
      require(AlarmFuncs.alarmsGetById(id) == null,"confirmed recovered native alarm archived")
      require(!repo.stored(first["id"].toStr).has("inAlarm"),"native source recovers")
      closed:=bridge.list.find |r| { r["id"] == first["id"] }
      require(closed["nativeActive"] == false && closed["state"] == "acknowledged","confirmed recovered state retained")
      require(closed["ackNote"] == "confirmed from native Alarm","original confirmation retained after recovery")
      reentry:=event(prefix+" reentry",meter.id,category["id"].toStr,"open",16)
      evidence.add(reentry); observations.add(observation(16,12f))
      apply(bridge,evidence,observations)
      reentryId:=EnerCubixNativeAlarms.nativeId(reentry["id"].toStr); nativeIds.add(reentryId)
      require(AlarmFuncs.alarmsGetById(reentryId).active,"new native event after recovery")
      require(EnerCubixRepo.decode(repo.stored(reentry["id"].toStr))["episodeId"] == reentry["id"],"reentry owns another episode")
      checks.add("valid normal hour closes episode and later exceedance creates a new alarm")

      unacked:=event(prefix+" recover unacknowledged",meter.id,category["id"].toStr,"open",18)
      unackedId:=EnerCubixNativeAlarms.nativeId(unacked["id"].toStr); nativeIds.add(unackedId)
      apply(bridge,[unacked],[observation(18,12f),observation(19,1f)])
      require(!AlarmFuncs.alarmsGetById(unackedId).active,"unacknowledged recovery does not acknowledge")
      require(!repo.stored(unacked["id"].toStr).has("inAlarm"),"unacknowledged source normal")
      row:=bridge.list.find |r| { r["id"] == unacked["id"] }
      require(row["state"] == "open" && row["nativeActive"] == false,"confirmation and recovery independent")
      acked:=repo.acknowledge(row["id"].toStr,row["mod"],"confirm after recovery")
      require(acked["state"] == "acknowledged" && AlarmFuncs.alarmsGetById(unackedId) == null,"confirmation after recovery archives native record")
      checks.add("unacknowledged recovery and later native confirmation")
      return ["status":"passed","version":EnerCubixRepo#.pod.version.toStr,"checks":checks]
    }
    finally
    {
      // A failed transition may have created a native record before returning.
      // Reconcile only alarms belonging to this run's owned source records.
      owned.each |id|
      {
        rec:=cx.db.readById(id,false)
        if (rec == null || rec["enerCubixKind"] != "alarm") return
        alarm:=AlarmFuncs.alarmsGetById(EnerCubixNativeAlarms.nativeId(id.id))
        if (alarm == null) return
        EnerCubixNativeAlarms.checkOwned(EnerCubixRepo.decode(rec),alarm)
        if (!nativeIds.contains(alarm.id)) nativeIds.add(alarm.id)
      }
      nativeIds.each |id| { if (AlarmFuncs.alarmsGetById(id) != null) AlarmFuncs.alarmsRemove([id]) }
      owned.reverse.each |id| { rec:=cx.db.readById(id,false); if (rec != null) cx.db.commit(Diff(rec,null,Diff.remove)) }
    }
  }

  private [Str:Obj?] event(Str name, Ref meter, Str category, Str state := "open", Int hour := 13)
  {
    rec:=repo.save(["kind":"alarm","name":name,"nodeId":meter.id,"categoryId":category,"ts":"2026-10-23T${hour}:00:00+08:00","value":19.390625f,"limit":7f,"unit":"kWh","state":state,"quality":"ok","sourceIds":Str[,]],true)
    owned.add(Ref(rec["id"].toStr)); return rec
  }

  private [Str:Obj?] observation(Int hour, Float? value)
  { ["ts":"2026-10-23T${hour}:00:00+08:00","value":value,"limit":7f,"quality":value == null ? "missing" : "ok"] }

  private Void apply(EnerCubixNativeAlarms bridge, [Str:Obj?][] events, [Str:Obj?][] observations)
  {
    EnerCubixAlarmEpisodes.plan(events,observations).each |g| { bridge.applyEpisode(g,observations.last["ts"].toStr) }
  }

  private Dict source(Str:Obj? tags)
  {
    tags["enerCubixNativeAlarmAcceptance"]=Marker.val
    rec:=cx.db.commit(Diff.makeAdd(Etc.makeDict(tags))).newRec
    owned.add(rec.id); return rec
  }

  private Void require(Bool pass, Str message) { if (!pass) throw Err("Native alarm acceptance: "+message) }
}

** Read-only projection of existing event identity and this snapshot's quality.
** No scanning, event grouping heuristic, acknowledgement or persistent messages.
internal class FinEnergyCockpitIssues
{
  ** Native event records can be readable while a referenced source is not.
  ** Check actual Folio permissions, without treating Alarm DB IDs as Folio IDs.
  static [Str:Obj?][] readableEvents([Str:Obj?][] events, Str project, |Str->Bool| read)
  {
    checked:=Str:Bool[:]
    return events.findAll |e|
    {
      ids:=FinEnergyMath.strings(e["sourceIds"]).dup
      ["id","nodeId","categoryId"].each |key| {if (e[key] is Str) ids.add(e[key])}
      if (ids.any |id| {!validRef(id,project)}) return false
      return ids.unique.all |id|
      {
        if (!checked.containsKey(id)) checked[id]=read(id)
        return checked[id]
      }
    }
  }

  static Str:Obj? observe(|->[Str:Obj?][]|? provider, FinEnergyContext ctx, Str[] ids, Str category, Str:Obj? boundary, |->DateTime| clock, Str project)
  {
    result:=Str:Obj?["episodes":[Str:Obj?][,],"stateObservedAt":null,"reasonCodes":["ACTIVE_EVENTS_UNAVAILABLE"]]
    if (provider == null) return result
    rows:=[Str:Obj?][,]
    try {rows=([Str:Obj?][])provider().toImmutable}
    catch (FinEnergyHttpErr e) {throw e}
    catch (IOErr e) {result["reasonCodes"]=["ACTIVE_EVENTS_READ_ERROR"];return result}
    catch (TimeoutErr e) {result["reasonCodes"]=["ACTIVE_EVENTS_READ_ERROR"];return result}
    catch (ArgErr e) {result["reasonCodes"]=["ACTIVE_EVENTS_READ_ERROR"];return result}
    catch (Err e) {result["reasonCodes"]=["ACTIVE_EVENTS_READ_ERROR"];return result}
    result["stateObservedAt"]=clock().toIso
    visiblePoints:=ctx.byId.vals.findAll |r| {readable(r)}.map |r->Str| {r["pointId"] as Str ?: ""}.findAll |Str p->Bool| {!p.isEmpty}.unique
    rows=rows.findAll |e|
    {
      if (e["id"] isnot Str || e["nodeId"] isnot Str || e["categoryId"] != category || !readable(e)) return false
      if (["id","nodeId","categoryId","episodeId","nativeAlarmId"].any |key| {!validRef(e[key] as Str,project)}) return false
      if (FinEnergyMath.strings(e["sourceIds"]).any |id| {!validRef(id,project) || !visiblePoints.contains(id)}) return false
      node:=e["nodeId"] as Str ?: "";record:=ctx.byId[node]
      if (record == null || !readable(record)) return false
      if (ids.contains(node) || FinEnergyMath.strings(boundary["meterIds"]).contains(node)) return true
      members:=ctx.scopeMeters(node,category)
      return !members.isEmpty && members.all |m| {readable(m) && FinEnergyMath.strings(boundary["meterIds"]).contains(m["id"])}
    }
    // NativeAlarms.list already returns roots. Fixtures/legacy providers may also
    // include members carrying an existing episodeId; never create a new episode.
    roots:=[Str:Obj?][,]
    rows.map |e->Str| {e["episodeId"] as Str ?: e["id"].toStr}.unique.sort.each |id|
    {
      members:=rows.findAll |e| {(e["episodeId"] as Str ?: e["id"].toStr) == id}
      root:=members.find |e| {e["id"] == id}
      if (root != null) roots.add(root)
    }
    result["episodes"]=roots
    result["reasonCodes"]=roots.any |e| {e["nativeAlarmMissing"] == true} ? ["ACTIVE_EVENTS_UNAVAILABLE"] : Str[,]
    return (Str:Obj?)result.toImmutable
  }

  static Bool active(Str:Obj? event)
  {event["nativeActive"] == true || (event["nativeActive"] == null && event["recoveredAt"] == null && event["nativeRecoveredAt"] == null)}

  static Str:Obj? project(Str:Obj? observation, Str:Obj? eventMetric, [Str:Obj?][] values, Str:Obj? request, Str:Obj? boundary, FinEnergyContext ctx, Str:Obj? clues := [:])
  {
    items:=[Str:Obj?][,];observed:=observation["stateObservedAt"] as Str
    FinEnergyMath.maps(observation["episodes"]).findAll |e| {active(e) && e["nativeAlarmMissing"] != true}.each |e|
    {
      root:=e["episodeId"] as Str ?: e["id"].toStr
      begin:=date(e["episodeStartTs"] ?: e["ts"]);last:=date(e["lastTs"] ?: e["ts"])
      end:=last == null ? null : last+1hr
      hours:=FinEnergyMath.maps(e["hours"]).findAll |h| {date(h["ts"]) != null}.map |h->[Str:Obj?]|
      {["ts":h["ts"],"value":FinEnergyMath.num(h["value"]),"unit":h["unit"],"limit":FinEnergyMath.num(h["limit"]),"quality":h["quality"]]}
      item:=Str:Obj?["id":root,"episodeId":root,"type":e["nativeAlarmId"] == null ? "ruleClue" : "energyAlarm","objectId":e["nodeId"],"name":ctx.displayName(e["nodeId"].toStr),"categoryId":e["categoryId"],"unit":e["unit"] ?: "","evidenceFrom":begin?.toIso,"evidenceTo":end?.toIso,"active":true,"acknowledged":e["state"] == "acknowledged","recoveredAt":e["nativeRecoveredAt"] ?: e["recoveredAt"],"stateObservedAt":observed,"sourceIds":e["sourceIds"] ?: Str[,],"detailTarget":["kind":"messages","eventId":root],"nativeDetail":["available":false,"reasonCode":"NATIVE_ALARM_DEEP_LINK_UNAVAILABLE"],"actual":FinEnergyMath.num(e["latestValue"] ?: e["value"]),"reference":FinEnergyMath.num(e["limit"]),"hours":hours,"hourCount":e["hourCount"] ?: (hours.isEmpty ? 1 : hours.size)]
      ["nativeAlarmId","ackAt","ackBy","ackNote"].each |key| {if (e[key] is Str) item[key]=e[key]}
      if (FinEnergyMath.num(e["severity"]) != null) item["severity"]=FinEnergyMath.num(e["severity"])
      if (begin != null && end != null && end > begin && observed != null && end <= date(observed))
        item["evidenceTarget"]=evidence([e["nodeId"].toStr],e["categoryId"].toStr,begin.toIso,end.toIso,observed,"metering")
      else item["reasonCodes"]=["EVENT_EVIDENCE_UNAVAILABLE"]
      items.add(item)
    }
    values.findAll |v| {v["id"] != "activeAlarms"}.each |value|
    {
      comparison:=value["comparison"] as Map
      reasons:=FinEnergyMath.strings(value["reasonCodes"]).dup
      if (value["completeValue"] == null && reasons.isEmpty) reasons.add("DATA_INCOMPLETE")
      if (comparison != null && comparison["changeRate"] == null) reasons.addAll(FinEnergyMath.strings(comparison["reasonCodes"]))
      if (reasons.isEmpty) return
      key:=boundary["id"].toStr+"|"+value["id"].toStr+"|"+reasons.unique.sort.join("|")
      item:=Str:Obj?["id":"quality:"+key.toBuf.toDigest("SHA-256").toHex,"type":"dataQuality","objectId":FinEnergyMath.strings(request["nodeIds"]).first,"categoryId":value["categoryId"] ?: ((List)request["categoryIds"]).first,"unit":value["unit"],"evidenceFrom":request["from"],"evidenceTo":request["to"],"active":null,"acknowledged":null,"stateObservedAt":observed,"metricId":value["id"],"actual":value["value"],"valueType":value["valueType"],"valueBasis":value["valueBasis"],"sourceIds":value["sourceIds"],"reasonCodes":reasons.unique.sort,"detailTarget":["kind":"profile","metricId":value["id"]]]
      if (value["id"] == "energy") item["evidenceTarget"]=evidence(FinEnergyMath.strings(request["nodeIds"]),item["categoryId"].toStr,request["from"].toStr,request["to"].toStr,request["asOf"].toStr,request["dimension"].toStr)
      items.add(item)
    }
    items.addAll(FinEnergyMath.maps(clues["items"]))
    items.sort |a,b->Int|
    {
      kinds:=["energyAlarm","ruleClue","dataQuality"]
      c:=kinds.index(a["type"]) <=> kinds.index(b["type"]);if (c != 0) return c
      // Missing severity has no fabricated display value. Known severity wins;
      // remaining ties use real episode duration/start, then stable identity.
      aSeverity:=FinEnergyMath.num(a["severity"]);bSeverity:=FinEnergyMath.num(b["severity"])
      if (aSeverity == null && bSeverity != null) return 1
      if (aSeverity != null && bSeverity == null) return -1
      if (aSeverity != null && bSeverity != null) {c=bSeverity <=> aSeverity;if (c != 0) return c}
      aa:=date(a["evidenceFrom"]);bb:=date(b["evidenceFrom"])
      if (aa != null && bb != null && aa != bb) return aa <=> bb
      return a["id"].toStr <=> b["id"].toStr
    }
    reasons:=FinEnergyMath.strings(observation["reasonCodes"])
    eventScope:=Str:Obj?["basis":"selectedObjectsAndEffectiveMeters","objectIds":request["nodeIds"],"meterIds":boundary["meterIds"],"categoryId":((List)request["categoryIds"]).first]
    return ["status":!reasons.isEmpty ? "partial" : (items.isEmpty ? "empty" : "ok"),"boundaryId":boundary["id"],"reasonCodes":reasons,"data":["stateObservedAt":observed,"items":items,"total":items.size,"topIds":items.map |i->Str| {i["id"].toStr}[0..<items.size.min(3)],"activeEventCount":eventMetric["value"],"eventScope":eventScope,"messageCenterTarget":["kind":"messages"],"ruleEvaluations":clues["evaluations"] ?: [Str:Obj?][,]]]
  }

  private static Str:Obj? evidence(Str[] ids, Str category, Str from, Str to, Str asOf, Str dimension)
  {["kind":"profile","request":["kind":"profile","dimension":dimension,"spaceSource":"fin","nodeIds":ids,"categoryIds":[category],"from":from,"to":to,"asOf":asOf,"period":"hour","metric":"energy"]]}
  private static DateTime? date(Obj? v) {DateTime.fromIso(v as Str ?: "",false)}
  private static Bool readable(Str:Obj? r) {r["_comparisonReadable"] != false && r["_comparisonPointReadable"] != false && r["nativeHidden"] != true}
  private static Bool validRef(Str? id,Str project)
  {id == null || (!id.isEmpty && id.trim == id && !id.any |c| {c.isSpace || c < 32} && (!id.startsWith("p:") || id.startsWith("p:"+project+":r:")))}
}

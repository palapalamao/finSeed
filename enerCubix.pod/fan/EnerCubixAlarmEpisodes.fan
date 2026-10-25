** Deterministic grouping of hourly evidence. Only a valid low observation closes
** an episode; time gaps and missing data cannot prove recovery.
internal class EnerCubixAlarmEpisodes
{
  static [Str:Obj?][] plan([Str:Obj?][] events, [Str:Obj?][] samples)
  {
    timeline:=Int:Bool[:]
    byHour:=Int:[Str:Obj?][][:]
    zone:=TimeZone.utc
    events.each |e|
    {
      at:=DateTime.fromIso(e["ts"].toStr); zone=at.tz
      timeline[at.ticks]=true
      if (!byHour.containsKey(at.ticks)) byHour[at.ticks]=[Str:Obj?][,]
      byHour[at.ticks].add(e)
    }
    events.each |e|
    {
      if (e["recoveredAt"] == null) return
      tick:=(DateTime.fromIso(e["recoveredAt"].toStr)-1hr).ticks
      if (!byHour.containsKey(tick)) timeline[tick]=false
    }
    samples.each |p|
    {
      at:=DateTime.fromIso(p["ts"].toStr); zone=at.tz
      if (byHour.containsKey(at.ticks) || p["value"] == null || !["ok","derived","cleaned","corrected"].contains(p["quality"])) return
      if (EnerCubixConfig.number(p["value"]) <= EnerCubixConfig.number(p["limit"])) timeline[at.ticks]=false
    }
    result:=[Str:Obj?][,]
    members:=[Str:Obj?][,]
    timeline.keys.sort.each |tick|
    {
      if (timeline[tick]) { members.addAll(byHour[tick]); return }
      if (members.isEmpty) return
      result.add(group(members,DateTime.makeTicks(tick,zone)+1hr)); members=[Str:Obj?][,]
    }
    if (!members.isEmpty) result.add(group(members,null))
    result.each |g|
    {
      if (g["recoveredAt"] == null) return
      hour:=DateTime.fromIso(g["recoveredAt"].toStr)-1hr
      sample:=samples.find |p| { DateTime.fromIso(p["ts"].toStr) == hour }
      old:=events.find |e| { e["id"] == g["rootId"] }
      value:=sample?.get("value") ?: old?.get("recoveryValue")
      if (value != null) g["recoveryValue"]=value
    }
    return result
  }

  private static [Str:Obj?] group([Str:Obj?][] members, DateTime? recovered)
  {
    root:=members.find |e| { e["episodeId"] == e["id"] }
    if (root == null) root=members.find |e| { e["nativeAlarmId"] != null && haystack::Ref(e["nativeAlarmId"].toStr).toProjRel == EnerCubixNativeAlarms.nativeId(e["id"].toStr) }
    if (root == null) root=members.find |e| { e["state"] != "acknowledged" } ?: members.first
    return ["rootId":root["id"],"startTs":members.first["ts"],"lastTs":members.last["ts"],
      "memberIds":members.map |e->Str| { e["id"].toStr },"recoveredAt":recovered?.toIso]
  }
}

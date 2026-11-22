** Request-local grouping. Hour rows are indexed once rather than re-scanned for
** every episode; summaries do not retain hourly evidence or recovery archives.
internal class FinEnergyAlarmGroups
{
  new make([Str:Obj?][] rows)
  {
    rows.each |r|
    {
      id:=r["id"].toStr;parent:=r["episodeId"] as Str
      if(parent==null || parent==id) roots.add(r)
      key:=parent ?: id
      if(!members.containsKey(key)) members[key]=[Str:Obj?][,]
      members[key].add(r);times[id]=DateTime.fromIso(r["ts"].toStr)
    }
    members.each |hours| {hours.sort |a,b| {times[a["id"].toStr] <=> times[b["id"].toStr]}}
  }
  private [Str:Obj?][] roots:=[,]
  private Str:[Str:Obj?][] members:=[:]
  private Str:DateTime times:=[:]
  [Str:Obj?][] events(Bool detail:=true) {roots.map |r->Str:Obj?| {build(r,detail)}}
  [Str:Obj?]? event(Str id,Bool detail)
  {r:=roots.find |r| {r["id"]==id};return r==null ? null : build(r,detail)}
  private Str:Obj? build(Str:Obj? root,Bool detail)
  {
    hours:=members[root["id"].toStr] ?: throw ArgErr("Alarm episode has no root")
    result:=root.dup;result.remove("nativeAlarmArchive");result.remove("hours")
    result["hourCount"]=hours.size;result["latestValue"]=hours.last["value"]
    result["peakValue"]=hours.reduce(0f) |Float peak,e->Float| {peak.max(FinEnergyConfig.number(e["value"]))}
    if(detail) result["hours"]=hours.map |e->Str:Obj?| {["ts":e["ts"],"value":e["value"],"unit":e["unit"],"limit":e["limit"],"quality":e["quality"],"priorAckBy":e["priorAckBy"],"priorAckAt":e["priorAckAt"],"priorAckNote":e["priorAckNote"]]}
    return result
  }
  static Str:Obj? page([Str:Obj?][] events,Int offset,Int limit,Str state:="all",Str? target:=null)
  {
    if(offset<0 || limit<1 || limit>200 || !["all","open","acknowledged"].contains(state)) throw ArgErr("分页范围无效")
    selected:=events.findAll |r| {target!=null ? (r["id"]==target || r["episodeId"]==target) : (state=="all" || r["state"]==state)}
    start:=offset.min(selected.size);end:=(start+limit).min(selected.size)
    return ["items":selected[start..<end],"total":selected.size,"offset":offset,"limit":limit]
  }
}

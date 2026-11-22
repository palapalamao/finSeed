class FinEnergyAlarmGroupsTest : Test
{
  Void testSinglePassGroupingKeepsAllHoursAndOriginalEventOrder()
  {
    rows:=[row("a",null,0,10),row("b",null,1,8),row("a2","a",2,30),row("a1","a",1,20)]
    groups:=FinEnergyAlarmGroups(rows)
    summary:=groups.events(false)
    verifyEq(summary.map |r->Str| {r["id"].toStr},["a","b"])
    a:=summary.first;verifyEq(a["hourCount"],3);verifyEq(a["latestValue"],30);verifyEq(a["peakValue"],30f)
    verifyFalse(a.containsKey("hours"));verifyFalse(a.containsKey("nativeAlarmArchive"))
    detail:=groups.event("a",true)
    hours:=FinEnergyMath.maps(detail["hours"])
    verifyEq(hours.map |r->Int| {r["value"]},[10,20,30]);verifyEq(hours[1]["priorAckBy"],"Previous operator")
    verifyEq(FinEnergyMath.maps(groups.event("b",true)["hours"]).size,1)
    verifyNull(groups.event("missing",true));verify(rows.first.containsKey("nativeAlarmArchive"))
  }
  Void testPageFiltersWholeEventSummariesWithoutChangingTotalsOrEvidence()
  {
    all:=[row("a",null,0,10).set("state","open"),row("b",null,1,20).set("state","acknowledged"),row("c",null,2,30).set("state","open")]
    result:=FinEnergyAlarmGroups.page(all,1,1,"open")
    verifyEq(result["total"],2);verifyEq(FinEnergyMath.maps(result["items"]).first["id"],"c")
    verifyEq(FinEnergyAlarmGroups.page(all,0,30,"all","b")["total"],1)
    verifyEq(FinEnergyAlarmGroups.page(all,9,30,"all")["total"],3)
    verifyErr(ArgErr#) {FinEnergyAlarmGroups.page(all,-1,30,"all")}
    verifyErr(ArgErr#) {FinEnergyAlarmGroups.page(all,0,201,"all")}
  }
  private Str:Obj? row(Str id,Str? parent,Int hour,Int value)
  { ["id":id,"episodeId":parent,"kind":"alarm","name":id,"ts":"2026-11-01T${hour.toStr.padl(2,'0')}:00:00Z","value":value,"unit":"kWh","limit":9,"quality":"ok","priorAckBy":"Previous operator","nativeAlarmArchive":["keep":"original"]] }
}

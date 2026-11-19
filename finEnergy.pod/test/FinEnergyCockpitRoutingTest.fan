** The prepared route has a separate report boundary. The existing KPI fault
** callback remains restricted to the KPI projections it originally controlled.
class FinEnergyCockpitRoutingTest : Test
{
  Void testPreparedReportRouteUsesStableKeysAndExactQueries()
  {
    a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+24hr
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space","area":100f],["id":"m","kind":"meter","pointId":"p","categoryId":"c","spaceId":"s","nativeSpaceId":"s","nativeTreeParentId":"s","nativeEquip":true],["id":"cal","kind":"calendar","workHours":[1,2],"workDays":[1,2,3,4,5]]]
    rows:=[Str:Obj?][,];(0..<24).each |i| {rows.add(["ts":(a+1hr*i).toIso,"value":1f])}
    hs:=[Str:Obj?][["pointId":"p","unit":"kWh","mode":"interval","samples":rows]]
    input:=Str:Obj?["schemaVersion":1,"requestId":"routing","reportScope":["dimension":"space","nodeIds":["s"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"day","from":a.toIso,"to":b.toIso],"asOf":b.toIso,"modules":["kpis","trend","space","time","endUse","organization"],"comparison":["mode":"none"]]
    load:=|Str:Obj? q,[Str:Obj?][] saved->[Str:Obj?][]| {hs}
    before:=FinEnergyCockpit.execute(input,rs,load,"test",TimeZone.utc,b)
    seen:=Str:Str:Obj?[:]
    route:=|Str key,Str:Obj? q->Str:Obj?|
    {
      verify(!seen.containsKey(key));seen[key]=q.dup
      return FinEnergyHistory.report(q,rs,hs)
    }
    after:=FinEnergyCockpit.execute(input,rs,load,"test",TimeZone.utc,b,false,null,null,null,null,[:],route)
    verifyEq(seen.keys.sort,["face-daily","face-endUse","face-heatmap","face-meter-profile","face-workingDays","face-workingHours","profile-area","profile-co2","profile-cost","profile-energy","space-summary"].sort)
    verifyEq(((Map)before["reports"]),((Map)after["reports"]))
    verifyEq(seen["face-daily"]["period"],"hour")
    verifyEq(seen["face-meter-profile"]["nodeIds"],["m"])
    verifyEq(seen["space-summary"]["dimension"],"space")
    verifyEq(seen["face-heatmap"]["nodeIds"],["s"])
    verifyEq(seen["profile-area"]["perArea"],true)
  }

  Void testKpiFaultCallbackCannotInterceptEnergyOrFaces()
  {
    a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+1hr
    input:=Str:Obj?["schemaVersion":1,"requestId":"routing","reportScope":["dimension":"metering","nodeIds":["m"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"hour","from":a.toIso,"to":b.toIso],"asOf":b.toIso,"modules":["kpis","organization"],"comparison":["mode":"none"]]
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c"]]
    hs:=[Str:Obj?][["pointId":"p","unit":"kWh","mode":"interval","samples":[["ts":a.toIso,"value":1f]]]]
    calls:=0
    result:=FinEnergyCockpit.execute(input,rs,|q,saved->[Str:Obj?][]| {hs},"test",TimeZone.utc,b,false,null,null,|q,saved,history->Str:Obj?| {calls++;throw Err("kpi fault")})
    verifyEq(calls,3)
    verifyEq(FinEnergyMath.maps(((Map)((Map)result["reports"])["profile-energy"])["series"]).size,1)
    verifyEq(((Map)((Map)result["modules"])["organization"])["status"],"partial")
  }
}


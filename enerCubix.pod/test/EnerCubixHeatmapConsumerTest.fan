class EnerCubixHeatmapConsumerTest : Test
{
  Void testCompleteDstDaysAndPartialBoundsMatchOriginalFace()
  {
    tz:=TimeZone("New_York")
    [Date(2026,Month.mar,8),Date(2026,Month.nov,1)].each |date|
    {
      a:=date.toDateTime(Time.defVal,tz);b:=(date+1day).toDateTime(Time.defVal,tz)
      exercise(a,b,b);exercise(a+20min,b,b);exercise(a,b-20min,b);exercise(a,b,b-20min)
    }
  }
  Void testZerosNaCleaningAndMissingDaysKeepOriginalEligibility()
  {
    at:=DateTime.fromIso("2026-01-01T00:00:00Z")
    ["ok","na","filtered","substituted","incompleteInterval","missing","cleaned"].each |quality|
    {exercise(at,at+49hr,at+49hr,quality)}
  }
  Void testIncompleteYearKeepsOnlyCurrentDayWorkspace()
  {at:=DateTime.fromIso("2026-01-01T00:00:00Z");exercise(at,at+1000hr,at+1000hr,"na")}

  Void testRejectedFinalDayCannotPublishOrReleasePeerAllocation()
  {
    at:=DateTime.fromIso("2026-01-01T00:00:00Z");line:=EnerCubixLine("a|c","a","A","c","kWh")
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    consumer:=EnerCubixHeatmapConsumer(line,at,at+48hr,at+48hr,state,output)
    verifyErr(ArgErr#) {consumer.finish}
    (0..<48).each |i| {consumer.add(EnerCubixTick(at+1hr*i,at+1hr*(i+1),EnerCubixValue(0f,"ok",["p"])))}
    peer:=EnerCubixPreparedOwner(budget);peer.hold(budget.remaining);held:=peer.entries
    verifyErr(EnerCubixHttpErr#) {consumer.finish};verifyErr(EnerCubixHttpErr#) {consumer.finish}
    state.close;output.close;verifyEq(budget.temporary.val,held);peer.close;verifyEq(budget.temporary.val,0)
  }

  Void testInputCannotRetainAnExistingTickHistory()
  {
    at:=DateTime.fromIso("2026-01-01T00:00:00Z");line:=EnerCubixLine("a|c","a","A","c","kWh")
    line.ticks.add(EnerCubixTick(at,at+1hr,EnerCubixValue(1f,"ok")))
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    verifyErr(ArgErr#) {rejected:=EnerCubixHeatmapConsumer(line,at,at+1hr,at+1hr,state,output)}
    state.close;output.close;verifyEq(budget.temporary.val,0)
  }

  private Void exercise(DateTime from,DateTime to,DateTime cutoff,Str quality := "ok")
  {
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"a","kind":"meter","name":"A","pointId":"pa","categoryId":"c"]]
    q:=Str:Obj?["kind":"profile","nodeIds":["a"],"dimension":"metering","from":from.toIso,"to":to.toIso,"asOf":cutoff.toIso,"tz":from.tz.name,"period":"hour","metric":"energy","perArea":false]
    samples:=[Str:Obj?][,];at:=EnerCubixMath.floorHour(from)
    while(at<to)
    {samples.add(["ts":at.toIso,"value":quality=="na" || quality=="missing" ? null : 0f,"quality":quality,"valueType":quality=="na" ? "na" : (quality=="missing" ? "null" : "number")]);at+=1hr}
    hs:=[Str:Obj?][["pointId":"pa","mode":"interval","unit":"kWh","samples":samples]]
    dim:=EnerCubixDimension("metering",rs);ctx:=EnerCubixContext(dim.records,EnerCubixKnownUsage.clip(hs,cutoff),from.tz,dim)
    expected:=(Map)EnerCubixCockpitFaces#.method("time").callList([q,q,rs,hs,Str:Obj?[:],ctx])
    line:=EnerCubixReport(ctx,q,from,to,"profile","hour","energy").line("a","c")
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    definition:=EnerCubixLine(line.id,line.nodeId,line.name,line.category,line.unit)
    consumer:=EnerCubixHeatmapConsumer(definition,from,to,cutoff,state,output)
    line.ticks.each |tick| {consumer.add(tick)}
    actual:=consumer.finish;data:=(Map)expected["data"]
    verifyEq(actual["heatmap"],data["heatmap"]);verifyEq(actual["excludedDays"],data["excludedDays"])
    retained:=5+((List)actual["excludedDays"]).size*5
    ((List)actual["heatmap"]).each |Map row| {retained+=12+((List)row["sourceIds"]).size}
    verify(output.entries>=retained,"admit the actual retained cell/source graph")
    verify(budget.peak.val<200000)
    if(quality=="na" && (to-from)>=1000hr) verify(budget.peak.val<2000,"incomplete hours must not accumulate in the output")
    cells:=(List)actual["heatmap"];excluded:=(List)actual["excludedDays"]
    state.close;verifyEq(actual["heatmap"],data["heatmap"])
    output.close;verify(actual.isEmpty);verify(cells.isEmpty);verify(excluded.isEmpty);verifyEq(budget.temporary.val,0)
    verifyErr(ArgErr#) {consumer.finish}
  }
}

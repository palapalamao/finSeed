using [java] java.util::IdentityHashMap

class EnerCubixHeatmapConsumerTest : Test
{
  Void testCompleteDaySharesOnlyEqualOrderedSourceVectorsWithinItsOutputOwner()
  {
    at:=DateTime.fromIso("2026-01-01T00:00:00Z");line:=EnerCubixLine("a|c","a","A","c","kWh")
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    consumer:=EnerCubixHeatmapConsumer(line,at,at+48hr,at+48hr,state,output)
    ids:=(0..<21).map |i->Str| {"p$i"}
    (0..<48).each |i| {consumer.add(EnerCubixTick(at+1hr*i,at+1hr*(i+1),EnerCubixValue(i.toFloat,"ok",ids.dup)))}
    data:=consumer.finish;cells:=EnerCubixMath.maps(data["heatmap"])
    try
    {
      verifyEq(cells.size,48);verify(cells[0]["sourceIds"]===cells[23]["sourceIds"])
      verify(cells[24]["sourceIds"]===cells[47]["sourceIds"]);verify(cells[0]["sourceIds"]!==cells[24]["sourceIds"],"days have independent owner transfers")
      cells.each |row,i| {verifyEq(row["value"],i.toFloat);verifyEq(row["sourceIds"],ids);verifyEq(row["hour"],i%24)}
      verifyEq(output.entries,5+graphEntries(data,IdentityHashMap()),"charge every actual map/list entry exactly once")
      state.close;verifyEq(cells[23]["sourceIds"],ids)
    }
    finally {state.close;output.close}
    verifyEq(budget.temporary.val,0)
  }

  private Int graphEntries(Obj? value,IdentityHashMap seen)
  {
    if(value==null || (value isnot Map && value isnot List) || seen.containsKey(value)) return 0
    seen.put(value,true);n:=1+(value is Map ? ((Map)value).size : ((List)value).size)
    if(value is Map) ((Map)value).each |v| {n+=graphEntries(v,seen)}
    else ((List)value).each |v| {n+=graphEntries(v,seen)}
    return n
  }

  Void testOrderedAndEmptySourceVectorsKeepAllHourlyCells()
  {
    at:=DateTime.fromIso("2026-01-01T00:00:00Z");line:=EnerCubixLine("a|c","a","A","c","kWh")
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    consumer:=EnerCubixHeatmapConsumer(line,at,at+24hr,at+24hr,state,output)
    (0..<24).each |i|
    {ids:=i==5 || i==7 ? Str[,] : (i%2==0 ? ["p","q"] : ["q","p"]);consumer.add(EnerCubixTick(at+1hr*i,at+1hr*(i+1),EnerCubixValue(0f,"ok",ids)))}
    data:=consumer.finish;cells:=EnerCubixMath.maps(data["heatmap"])
    try
    {
      verifyEq(cells.size,24);verify(cells[0]["sourceIds"]!==cells[1]["sourceIds"])
      verify(cells[0]["sourceIds"]===cells[2]["sourceIds"]);verify(cells[5]["sourceIds"]===cells[7]["sourceIds"])
      verifyEq(cells[0]["sourceIds"],["p","q"]);verifyEq(cells[1]["sourceIds"],["q","p"]);verifyEq(cells[5]["sourceIds"],Str[,])
      verifyEq(output.entries,5+graphEntries(data,IdentityHashMap()))
      state.close;verifyEq(cells[0]["sourceIds"],["p","q"])
    }
    finally {state.close;output.close}
    verifyEq(budget.temporary.val,0)
  }

  Void testDenseAnnualHeatmapKeeps8760IndividualHoursInsideTheExistingLimit()
  {
    at:=DateTime.fromIso("2026-01-01T00:00:00Z");line:=EnerCubixLine("a|c","a","A","c","kWh")
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    consumer:=EnerCubixHeatmapConsumer(line,at,at+8760hr,at+8760hr,state,output);ids:=(0..<21).map |i->Str| {"p$i"}
    try
    {
      (0..<8760).each |i| {consumer.add(EnerCubixTick(at+1hr*i,at+1hr*(i+1),EnerCubixValue(i.toFloat,"ok",ids.dup)))}
      data:=consumer.finish;cells:=EnerCubixMath.maps(data["heatmap"])
      verifyEq(cells.size,8760);verifyEq(EnerCubixMath.maps(data["excludedDays"]).size,0)
      cells.each |row,i| {verifyEq(row["value"],i.toFloat);verifyEq(row["sourceIds"],ids)}
      verifyEq(output.entries,5+graphEntries(data,IdentityHashMap()));verify(budget.peak.val<110000)
    }
    finally {state.close;output.close}
    verifyEq(budget.temporary.val,0)
  }

  Void testSharedSourcesSurviveDestructiveFreezeAndProducerCleanup()
  {
    at:=DateTime.fromIso("2026-01-01T00:00:00Z");line:=EnerCubixLine("a|c","a","A","c","kWh")
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget);target:=EnerCubixPreparedOwner(budget)
    consumer:=EnerCubixHeatmapConsumer(line,at,at+24hr,at+24hr,state,output)
    (0..<24).each |i| {consumer.add(EnerCubixTick(at+1hr*i,at+1hr*(i+1),EnerCubixValue(i.toFloat,"ok",["p","q"])))}
    data:=consumer.finish
    try
    {
      frozen:=(Map)EnerCubixCockpitFreeze.value(data,target,null,|Obj value|
      {
        count:=1+(value is Map ? ((Map)value).size : ((List)value).size)
        if(value is Map) ((Map)value).clear;else ((List)value).clear
        output.release(count)
      })
      verifyEq(output.entries,5);state.close;output.close
      cells:=(List)frozen["heatmap"];verifyEq(cells.size,24)
      cells.each |Map cell,i| {verifyEq(cell["value"],i.toFloat);verifyEq(cell["sourceIds"],["p","q"])}
      verify(((Map)cells.first)["sourceIds"]===((Map)cells.last)["sourceIds"])
    }
    finally {state.close;output.close;target.close}
    verifyEq(budget.temporary.val,0)
  }

  Void testCompletedHeatmapRetiresOnlyDuplicatePrivateLinks()
  {
    at:=DateTime.fromIso("2026-01-01T00:00:00Z");line:=EnerCubixLine("a|c","a","A","c","kWh")
    budget:=EnerCubixStreamBudget().state;state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget);peer:=EnerCubixPreparedOwner(budget);peer.hold(31);held:=peer.entries
    consumer:=EnerCubixHeatmapConsumer(line,at,at+49hr,at+49hr,state,output)
    49.times |i| {consumer.add(EnerCubixTick(at+1hr*i,at+1hr*(i+1),EnerCubixValue(0f,"ok",["p"])))}
    data:=consumer.finish;cells:=((List)data["heatmap"]).dup;excluded:=((List)data["excludedDays"]).dup;n:=cells.size+excluded.size+data.size
    output.hold(2+cells.size+excluded.size)
    output.watch |->Void| {cells.each |Map row| {((List)row["sourceIds"]).clear;row.clear};excluded.each |Map row| {row.clear};cells.clear;excluded.clear}
    try
    {
      verifyErr(ArgErr#) {consumer.retirePrivateLinks}
      state.close;before:=output.entries;consumer.retirePrivateLinks
      verifyEq(output.entries,before-n);verify(data.isEmpty);verifyEq(cells.size,48);verifyEq(excluded.size,1)
      verifyEq(((Map)cells.first)["value"],0f);verifyEq(((Map)cells.first)["sourceIds"],["p"])
      verifyEq(peer.entries,held);output.close;verifyEq(budget.temporary.val,held)
    }
    finally {state.close;output.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }

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
    verifyEq(output.entries,5+graphEntries(actual,IdentityHashMap()),"admit every actual retained container entry, counting shared arrays once")
    verify(budget.peak.val<200000)
    if(quality=="na" && (to-from)>=1000hr) verify(budget.peak.val<2000,"incomplete hours must not accumulate in the output")
    cells:=(List)actual["heatmap"];excluded:=(List)actual["excludedDays"]
    state.close;verifyEq(actual["heatmap"],data["heatmap"])
    output.close;verify(actual.isEmpty);verify(cells.isEmpty);verify(excluded.isEmpty);verifyEq(budget.temporary.val,0)
    verifyErr(ArgErr#) {consumer.finish}
  }
}

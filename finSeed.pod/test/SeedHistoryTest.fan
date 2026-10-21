using haystack

class SeedHistoryTest : Test
{
  Void testExplicitLegacyCounterAndNativeTotalized()
  {
    point:=Etc.makeDict(["id":Ref("legacy"),"his":Marker.val,"unit":"kWh"])
    items:=[HisItem(ts(0),Number(207401.15625f)),HisItem(ts(24),Number(207920.953125f))]
    automatic:=SeedHistory.normalize(point,items,ts(0),ts(24))
    verifyEq(automatic["mode"],"sampled")
    configured:=SeedHistory.normalize(point,items,ts(0),ts(24),false,"cumulative")
    parsed:=SeedHistoryData(configured)
    verifyEq(parsed.read(ts(0),ts(24)).value,519.796875f)
    verify(!point.has("hisMode")); verify(!point.has("hisTotalized"))
    totalized:=Etc.makeDict(["id":Ref("native"),"his":Marker.val,"hisTotalized":Marker.val])
    verifyEq(SeedHistory.normalize(totalized,items,ts(0),ts(24))["mode"],"cumulative")
    verifyEq(SeedHistory.normalize(totalized,items,ts(0),ts(24),true,"cumulative")["rawSamples"],configured["rawSamples"])
  }
  Void testDependencySelectionIsBounded()
  {
    records:=[
      [Str:Obj?]["id":"g","kind":"group"],
      [Str:Obj?]["id":"a","kind":"meter","parentId":"g","pointId":"pa"],
      [Str:Obj?]["id":"s","kind":"sensor","parentId":"g","pointId":"ps"],
      [Str:Obj?]["id":"v","kind":"meter","parentId":"g","expressionId":"e"],
      [Str:Obj?]["id":"e","kind":"expression","formula":"a","variables":["a":"a"]],
      [Str:Obj?]["id":"unrelated","kind":"meter","pointId":"unrelatedPoint"],
      [Str:Obj?]["id":"c","kind":"cop","numeratorId":"a","denominatorId":"v"],
    ]
    req:=request(); req["nodeIds"]=["g","c"]; req["referenceIds"]=["outside"]
    verifyEq(SeedHistory.pointIds(req,records).sort,["outside","pa"])
    req["kind"]="trend"; req["nodeIds"]=["s"]; req.remove("referenceIds")
    verifyEq(SeedHistory.pointIds(req,records),["ps"])
    req["nodeIds"]=Str[,]; verify(SeedHistory.pointIds(req,records).isEmpty)
  }

  Void testBillingReadStartsAtCycleBoundary()
  {
    req:=request(); req["metric"]="cost"; req["from"]="2026-09-15T00:00:00+08:00"; req["to"]="2026-09-16T00:00:00+08:00"; req["tz"]="Shanghai"
    records:=[[Str:Obj?]["id":"m","kind":"meter","pointId":"p","tariffId":"t"],[Str:Obj?]["id":"t","kind":"tariff","mode":"monthlyBlock"]]
    plan:=SeedHistory.range(req,records); verifyEq(((DateTime)plan["from"]).toIso,"2026-09-01T00:00:00+08:00")
    records[1]["mode"]="yearlyBlock"; plan=SeedHistory.range(req,records)
    verifyEq(((DateTime)plan["from"]).toIso,"2026-01-01T00:00:00+08:00")
    req["otherFrom"]="2025-09-15T00:00:00+08:00"; req["otherTo"]="2025-09-16T00:00:00+08:00"
    plan=SeedHistory.range(req,records); verifyEq(((DateTime)plan["from"]).toIso,"2025-01-01T00:00:00+08:00")
  }

  Void testRawCounterBoundariesArePreserved()
  {
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisMode":"consumption","hisTotalized":Marker.val,"unit":"kWh"])
    items:=[HisItem(ts(-1),Number(100f)),HisItem(ts(0),Number(110f)),HisItem(ts(1),Number(125f)),HisItem(ts(2),Number(140f))]
    h:=SeedHistory.normalize(point,items,ts(0),ts(1))
    verifyEq(h["mode"],"cumulative"); samples:=([Str:Obj?][])h["samples"]
    verifyEq(samples.size,4); verifyEq(samples[0]["value"],100f); verifyEq(samples[3]["value"],140f)
    verifyEq(samples[0]["ts"],ts(-1).toIso)
  }

  Void testEndStampedQuarterHoursBecomeCompleteStartHour()
  {
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number(15f,Unit("min")),"unit":"kWh"])
    items:=HisItem[,]
    (1..4).each |i| { items.add(HisItem(ts(0)+Duration(i*15min.ticks),Number(i.toFloat))) }
    h:=SeedHistory.normalize(point,items,ts(0),ts(1)); samples:=([Str:Obj?][])h["samples"]
    verifyEq(h["mode"],"interval"); verifyEq(samples.size,1); verifyEq(samples[0]["ts"],ts(0).toIso); verifyEq(samples[0]["value"],10f)
    items.removeAt(1); h=SeedHistory.normalize(point,items,ts(0),ts(1)); samples=([Str:Obj?][])h["samples"]
    verifyNull(samples[0]["value"])
  }

  Void testTrendNeverShiftsConsumptionTimestamps()
  {
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number(1f,Unit("hr"))])
    h:=SeedHistory.normalize(point,[HisItem(ts(1),Number(10f))],ts(0),ts(2),true)
    samples:=([Str:Obj?][])h["samples"]; verifyEq(samples[0]["ts"],ts(1).toIso); verifyEq(samples[0]["value"],10f)
  }

  Void testComputedHistoryKeepsHisFunc()
  {
    stored:=Etc.makeDict(["his":Marker.val,"hisMode":"consumption","hisTotalized":Marker.val])
    verify(SeedHistory.readOptions(stored).has("raw"))
    computed:=Etc.makeDict(["his":Marker.val,"hisMode":"consumption","hisTotalized":Marker.val,"hisFunc":"myCounter"])
    opts:=SeedHistory.readOptions(computed); verify(!opts.has("raw")); verifyEq(opts["hisTotalized"],Remove.val)
  }

  Void testUnknownIntervalNeverAssumesOneHour()
  {
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisMode":"consumption"])
    h:=SeedHistory.normalize(point,[HisItem(ts(1),Number(10f))],ts(0),ts(1))
    verifyEq(h["quality"],"missingInterval")
    items:=[HisItem(ts(1),Number(10f)),HisItem(ts(2),Number(20f)),HisItem(ts(3),Number(30f))]
    h=SeedHistory.normalize(point,items,ts(0),ts(3))
    verifyEq(h["quality"],"estimated"); samples:=([Str:Obj?][])h["samples"]; verifyEq(samples[0]["value"],10f)
  }

  Void testReferenceUsesOriginalIntervalSamples()
  {
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number(15f,Unit("min")),"unit":"kWh"])
    items:=HisItem[,]; (1..4).each |i| { items.add(HisItem(ts(0)+Duration(i*15min.ticks),Number(i.toFloat))) }
    h:=SeedHistory.normalize(point,items,ts(0),ts(1))
    parsed:=SeedHistoryData(h)
    verifyEq(parsed.read(ts(0),ts(1)).value,10f)
    verifyEq(parsed.read(ts(0),ts(1),true).value,2f)
  }

  private Str:Obj? request() { ["kind":"profile","nodeIds":["m"],"from":ts(0).toIso,"to":ts(1).toIso,"metric":"energy","tz":"UTC"] }
  private DateTime ts(Int hour) { DateTime.fromIso("2026-01-01T00:00:00Z")+Duration(hour*1hr.ticks) }
}

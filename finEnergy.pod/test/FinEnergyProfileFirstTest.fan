using haystack

** Chart-first is a contribution-scoped result, never partial diagnostic evidence.
class FinEnergyProfileFirstTest : Test
{
  Void testChartKeepsArithmeticAndCoverageButDefersMemberEvidence()
  {
    q:=request;rs:=records;hs:=histories
    full:=FinEnergyHistory.report(q,rs,hs)
    chart:=FinEnergyHistory.report(q.dup.set("_profileFirst",true),rs,hs.findAll |h| {h["pointId"]=="pt"})
    verifyEq(chart["series"],full["series"])
    verifyEq(chart["rows"],full["rows"])
    verifyEq(chart["summary"],full["summary"])
    extra:=(Map)chart["extra"]
    verifyEq(extra["usageCoverage"],((Map)full["extra"])["usageCoverage"])
    verify(!extra.containsKey("details"))
    verify(!extra.containsKey("knownUsage"))
    verify(!extra.containsKey("cleaning"))
    verifyEq(chart["warnings"],full["warnings"])
  }

  Void testFirstStageReadsOnlyContributingOwnPoints()
  {
    q:=request.set("_profileFirst",true)
    verifyEq(FinEnergyHistory.pointIds(q,records),["pt"])
    // Explicitly selecting a meter still reads its own point.
    q["nodeIds"]=["s","a"]
    verifyEq(FinEnergyHistory.pointIds(q,records),["pa","pt"])
  }

  Void testPublicOptInIsNarrowAndCannotForcePrivateMode()
  {
    q:=request;rs:=records
    verify(FinEnergyProfileFirst.activate(q.dup.set("responseMode","chart"),rs)["_profileFirst"]==true)
    verify(FinEnergyProfileFirst.activate(q,rs)["_profileFirst"]!=true)
    verify(FinEnergyProfileFirst.activate(q.dup.set("_profileFirst",true),rs)["_profileFirst"]!=true)
    changes:=Str:Obj?["kind":"daily","metric":"cost","period":"hour","dimension":"organization","perArea":true,"referenceIds":["weather"],"otherFrom":q["from"],"raw":true,"nodeIds":["unknown"]]
    changes.each |value,key|
    {verify(FinEnergyProfileFirst.activate(q.dup.set("responseMode","chart").set(key,value),rs)["_profileFirst"]!=true,key)}
    verify(!q.containsKey("_profileFirst"))
  }

  Void testAliasesOtherCategoriesAndExplicitChildKeepTheirOwnPoints()
  {
    rs:=records
    alias:=rs.last.dup.setAll(["id":"alias","canonicalId":"a"]);rs.add(alias)
    rs.add(["id":"water","kind":"category","unit":"m³"])
    rs.add(["id":"w","kind":"meter","name":"Water","pointId":"pw","categoryId":"water","nativeSpaceId":"s"])
    q:=request.set("_profileFirst",true).set("nodeIds",["s","alias"])
    verifyEq(FinEnergyHistory.pointIds(q,rs),["pa","pt","pw"])
    hs:=histories.add(["pointId":"pw","mode":"interval","unit":"m³","samples":[["ts":q["from"],"value":0f]]])
    sameChart(q,rs,hs)
  }

  Void testMissingShadowedChildDoesNotCreateFalseChartWarnings()
  {
    q:=request.set("_profileFirst",true);rs:=records;hs:=histories
    chart:=FinEnergyHistory.report(q,rs,hs.findAll |h| {h["pointId"]=="pt"})
    full:=FinEnergyHistory.report(q.dup.set("_profileFirst",false),rs,hs.findAll |h| {h["pointId"]=="pt"})
    verifyEq(chart["series"],full["series"]);verifyEq(chart["summary"],full["summary"])
    verifyEq(chart["warnings"],Str[,])
    verify(!FinEnergyMath.strings(full["warnings"]).isEmpty)
    // Keep topology config: an unlinked overlapping meter is still a quality issue.
    rs.last.remove("meterParentId")
    sameChart(q,rs,hs)
    verifyEq(FinEnergyMath.maps(FinEnergyMath.maps(FinEnergyHistory.report(q,rs,hs)["series"]).first["points"]).first["quality"],"topologyIncomplete")
  }

  Void testCleanedProjectionKeepsNAReplacementsRolloverAndCutoff()
  {
    at:=DateTime.fromIso(request["from"].toStr)
    point:=Etc.makeDict(["id":Ref("pt"),"unit":"kWh"])
    samples:=HisItem[,]
    [Number(100),Number(110),NA.val,Number(125),Number(4),Number(8)].each |v,i| {samples.add(HisItem(at+1hr*i,v))}
    [Str:Obj?["deltaMin":0,"defNull":true],Str:Obj?["deltaMin":0,"defVal":["type":"number","value":0]],Str:Obj?["deltaMin":0,"deltaMax":100,"hisTotalizedRollover":128]].each |config|
    {
      cleaned:=FinEnergyCleaning.clean(point,samples,Etc.makeDict(config))
      full:=FinEnergyHistory.normalizeClean(point,cleaned,at,at+6hr)
      chart:=FinEnergyHistory.normalizeChartClean(point,cleaned,at,at+6hr)
      verifyEq(chart["intervals"],full["intervals"])
      verify(!chart.containsKey("rawSamples"));verify(!chart.containsKey("cleaning"))
      q:=request.set("to",(at+5hr+30min).toIso).set("asOf",(at+4hr+30min).toIso)
      fullResult:=FinEnergyHistory.report(q,records,[full])
      chartResult:=FinEnergyHistory.report(q.dup.set("_profileFirst",true),records,[chart])
      verifyEq(chartResult["series"],fullResult["series"]);verifyEq(chartResult["summary"],fullResult["summary"])
      verifyEq(((Map)chartResult["extra"])["usageCoverage"],((Map)fullResult["extra"])["usageCoverage"])
    }
  }

  private Void sameChart(Str:Obj? q,[Str:Obj?][] rs,[Str:Obj?][] hs)
  {
    full:=FinEnergyHistory.report(q.dup.set("_profileFirst",false),rs,hs)
    points:=FinEnergyHistory.pointIds(q,rs)
    chart:=FinEnergyHistory.report(q,rs,hs.findAll |h| {points.contains(h["pointId"])})
    ["series","rows","summary"].each |key| {verifyEq(chart[key],full[key],key)}
    verifyEq(((Map)chart["extra"])["usageCoverage"],((Map)full["extra"])["usageCoverage"])
  }

  private Str:Obj? request()
  {Str:Obj?["kind":"profile","dimension":"space","spaceSource":"fin","nodeIds":["s"],"metric":"energy","period":"day","perArea":false,"from":"2026-09-01T00:00:00Z","to":"2026-09-03T00:00:00Z","asOf":"2026-09-03T00:00:00Z","tz":"UTC"]}
  private [Str:Obj?][] records()
  {
    [Str:Obj?][["id":"c","kind":"category","unit":"kWh","name":"Electricity"],
      ["id":"s","kind":"space","name":"Building","nativeSourceKind":"site"],
      ["id":"t","kind":"totalMeter","name":"Main","pointId":"pt","categoryId":"c","nativeSpaceId":"s"],
      ["id":"a","kind":"meter","name":"Branch","pointId":"pa","categoryId":"c","nativeSpaceId":"s","meterParentId":"t"]]
  }
  private [Str:Obj?][] histories()
  {
    ["pt","pa"].map |id,index->[Str:Obj?]|
    {samples:=[Str:Obj?][,];at:=DateTime.fromIso("2026-09-01T00:00:00Z");(0..<49).each |i| {samples.add(["ts":(at+1hr*i).toIso,"value":i.toFloat*(index==0 ? 10f : 2f)])};return ["pointId":id,"unit":"kWh","mode":"cumulative","samples":samples]}
  }
}

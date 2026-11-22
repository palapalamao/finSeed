using haystack

** Full-report oracle: internal projections may shrink, public evidence may not.
class FinEnergyFullCleaningProjectionTest : Test
{
  Void testFullProjectionRetainsAuthoritativeIntervalsAndEveryEvidenceField()
  {
    result:=clean("p",[10,10,5,NA.val,null,20,24],["deltaMin":0,"defNull":true])
    old:=FinEnergyHistory.normalizeClean(point("p"),result,at,at+6hr)
    fast:=FinEnergyHistory.normalizeFullClean(point("p"),result,at,at+6hr)
    verifyEq(fast["intervals"],old["intervals"])
    verifyEq(fast["cleaning"],old["cleaning"])
    verify(FinEnergyMath.maps(fast["samples"]).isEmpty,"full interval readers do not need a second dense hourly projection")
    verify(!fast.containsKey("rawSamples"),"no raw consumer requested")
  }

  Void testCleanModesAndIrregularCoverageMatchOriginalMetadata()
  {
    cases:=Obj?[][
      [[10,10,5,NA.val,null,20,24],["deltaMin":0,"defNull":true]],
      [[10,5,8,2,20,22,21],["deltaMin":0,"defVal":["type":"number","value":2]]],
      [[10,5,8,2,20,22,21],["deltaMin":0,"defVal":["type":"na"]]],
      [[32760,12,15,10,20,50,55],["deltaMax":100,"hisTotalizedRollover":32768]],
      [[10,NA.val,14,16,NA.val,20,24],["removeNA":true,"defNull":true]]]
    cases.each |c|
    {
      result:=clean("p",(Obj?[])c[0],(Str:Obj?)c[1])
      [at,at+15min].each |from|
      {
        old:=FinEnergyHistory.normalizeClean(point("p"),result,from,at+5hr+30min)
        fast:=FinEnergyHistory.normalizeFullClean(point("p"),result,from,at+5hr+30min,true)
        verifyEq(fast["cleaning"],old["cleaning"])
        verifyEq(fast["intervals"],old["intervals"])
        verifyEq(fast["rawSamples"],old["rawSamples"])
      }
    }
    result:=FinEnergyCleanResult()
    result.summary=["sourceIds":["p"]]
    // Crossing/overlapping segments and positive numeric values with explicit
    // missing quality retain the historical summary coverage arithmetic.
    [[at+15min,900f,1f,"cleaned",false],[at+90min,4500f,2f,"cleaned",false],
     [at+2hr,1800f,3f,"missing",false],[at+2hr,1800f,4f,"filtered",false],
     [at+3hr,3600f,5f,"substituted",true]].each |c|
    {
      result.details.add(["ts":((DateTime)c[0]).toIso,"intervalSeconds":c[1],"value":c[2],"valueType":"number","quality":c[3],"substituted":c[4],"reason":"ok","emitted":true])
    }
    old:=FinEnergyHistory.normalizeClean(point("p"),result,at,at+3hr)
    fast:=FinEnergyHistory.normalizeFullClean(point("p"),result,at,at+3hr)
    verifyEq(fast["cleaning"],old["cleaning"])
    verifyEq(fast["intervals"],old["intervals"])
  }

  Void testAllOrdinaryReportKindsKeepCompleteResultAndReferenceReadings()
  {
    [false,true].each |withRef|
    {
      ["profile","ranking","proportion","utility","daily","comparison","primary","cop","leak","workingHours","workingDays","regression","dashboard","energyFlow"].each |kind|
      {
        ["energy","cost","coal","co2","rawcoal","oil"].each |metric|
        {
          q:=request(kind).set("metric",metric)
          if(kind=="cop") {q["nodeIds"]=["cop"];q.remove("dimension")}
          if(kind=="regression") {q["xId"]="p";q["yId"]="m"}
          if(kind=="comparison") {q["otherFrom"]=(at+3hr).toIso;q["otherTo"]=(at+6hr).toIso}
          if(kind=="energyFlow") {q["categoryId"]="e";if(!["energy","cost"].contains(metric)) return}
          if(withRef) q["referenceIds"]=["p"]
          hs:=histories(false);fast:=histories(true,withRef || kind=="regression")
          verifyEq(FinEnergyHistory.report(q,records,fast),FinEnergyHistory.report(q,records,hs),"$kind $metric reference=$withRef")
        }
      }
    }
  }

  Void testForecastAndAreaKeepFullCleaningEvidence()
  {
    start:=at-56day; end:=at
    rows:=HisItem[,];value:=0f
    (0..56*24).each |i| {rows.add(HisItem(start+1hr*i,Number(value)));value+=(i/24%7+1).toFloat}
    result:=FinEnergyCleaning.clean(point("p"),rows,FinEnergyCleaning.config(["defNull":true],"kWh"))
    original:=FinEnergyHistory.normalizeClean(point("p"),result,start,end)
    fast:=FinEnergyHistory.normalizeFullClean(point("p"),result,start,end)
    ["forecast","profile"].each |kind|
    {
      q:=request(kind).set("from",start.toIso).set("to",end.toIso).set("asOf",end.toIso).set("period","day").set("forecastDays",7).set("nodeIds",["s"]).set("dimension","space").set("perArea",true)
      // The unchanged evidence quota generates fresh UUIDs independently.
      // Retain every key/list/count and normalize only those identifier values.
      verifyEq(stableCaptureIds(FinEnergyHistory.report(q,records,[fast])),stableCaptureIds(FinEnergyHistory.report(q,records,[original])),kind)
    }
  }

  Void testDaylightSavingSummaryRetainsOriginalCoverage()
  {
    tz:=TimeZone.fromStr("New_York");half:=TimeZone.fromStr("Lord_Howe")
    [DateTime(2026,Month.mar,8,0,0,0,0,tz),DateTime(2026,Month.nov,1,0,0,0,0,tz),
     DateTime(2026,Month.apr,5,0,0,0,0,half),DateTime(2026,Month.oct,4,0,0,0,0,half)].each |start|
    {
      rows:=HisItem[,];(0..6*4).each |i| {rows.add(HisItem(start+15min*i,Number(i.toFloat)))}
      result:=FinEnergyCleaning.clean(point("p"),rows,FinEnergyCleaning.config(["defNull":true],"kWh"))
      original:=FinEnergyHistory.normalizeClean(point("p"),result,start,start+6hr)
      fast:=FinEnergyHistory.normalizeFullClean(point("p"),result,start,start+6hr)
      verifyEq(fast["cleaning"],original["cleaning"])
      verifyEq(fast["intervals"],original["intervals"])
    }
  }

  private Obj? stableCaptureIds(Obj? input)
  {
    if(input is Map)
    {
      out:=Str:Obj?[:]
      ((Map)input).each |v,k| {out[k.toStr]=k.toStr.lower.endsWith("captureid") && v is Str ? "independent-capture" : stableCaptureIds(v)}
      return out
    }
    if(input is List) return ((List)input).map |v->Obj?| {stableCaptureIds(v)}
    return input
  }

  private [Str:Obj?][] histories(Bool fast,Bool rawView:=false)
  {
    out:=[Str:Obj?][,]
    ["p","cp"].each |id|
    {
      result:=clean(id,id=="p" ? Obj?[10,12,10,13,16,20,25] : Obj?[0,1,2,NA.val,5,6,8],["deltaMin":0,"defVal":["type":"number","value":2]])
      out.add(fast ? FinEnergyHistory.normalizeFullClean(point(id),result,at,at+6hr,rawView) : FinEnergyHistory.normalizeClean(point(id),result,at,at+6hr))
    }
    return out
  }
  private Str:Obj? request(Str kind)
  {["kind":kind,"dimension":"metering","nodeIds":["m"],"from":at.toIso,"to":(at+3hr).toIso,"asOf":(at+6hr).toIso,"period":"hour","metric":"energy","perArea":false,"tz":"UTC"]}
  private [Str:Obj?][] records()
  {[["id":"s","kind":"space","name":"Site","area":100f],
    ["id":"m","kind":"totalMeter","name":"Main","pointId":"p","categoryId":"e","spaceId":"s","utilityId":"u","unit":"kWh"],
    ["id":"c","kind":"meter","name":"Child","pointId":"cp","categoryId":"e","spaceId":"s","utilityId":"u","unit":"kWh","meterParentId":"m"],
    ["id":"e","kind":"category","unit":"kWh","name":"Electricity","coal":0.1f,"co2":0.5f,"rawcoal":0.2f,"oil":0.3f],
    ["id":"u","kind":"utility","categoryId":"e","name":"Lighting"],
    ["id":"t","kind":"tariff","categoryId":"e","isDefault":true,"mode":"weekly","rate":2f,"rules":[["from":"01:00","to":"02:00","rate":3f]]],
    ["id":"cal","kind":"calendar","isDefault":true,"workHours":[1],"workDays":[1,2,3,4,5]],
    ["id":"cop","kind":"cop","numeratorId":"m","denominatorId":"c"],
    ["id":"binding","kind":"binding","pointId":"p","role":"reference","name":"Raw counter"]]}
  private FinEnergyCleanResult clean(Str id,Obj?[] values,Str:Obj? options)
  {
    rows:=HisItem[,];values.each |v,i| {rows.add(HisItem(at+1hr*i,v is Num ? Number.makeNum(v) : v))}
    result:=FinEnergyCleaning.clean(point(id),rows,FinEnergyCleaning.config(options,"kWh"))
    result.summary["sourceIds"]=[id]
    return result
  }
  private Dict point(Str id) {Etc.makeDict(["id":Ref(id),"unit":"kWh","hisFunc":"finEnergyCleanHis"])}
  private DateTime at() {DateTime.fromIso("2026-11-01T00:00:00Z")}
}

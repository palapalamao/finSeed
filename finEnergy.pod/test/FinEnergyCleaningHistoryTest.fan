using haystack

class FinEnergyCleaningHistoryTest : Test
{
  Void testOwnedIntervalsSupportExactPartialHoursWithoutScaling()
  {
    h:=FinEnergyHistoryData(["pointId":"own","mode":"interval","quality":"derived","samples":Obj?[,],"intervals":[
      ["from":ts(0).toIso,"to":(ts(0)+15min).toIso,"value":10f,"quality":"cleaned"],
      ["from":(ts(0)+15min).toIso,"to":(ts(0)+45min).toIso,"value":20f,"quality":"cleaned"],
      ["from":(ts(0)+45min).toIso,"to":ts(1).toIso,"value":30f,"quality":"cleaned"],
    ]])
    verifyEq(h.read(ts(0),ts(0)+45min).value,30f)
    verifyEq(h.read(ts(0)+15min,ts(1)).value,50f)
    verifyNull(h.read(ts(0),ts(0)+10min).value)
    verifyEq(h.read(ts(0),ts(0)+10min).quality,"incompleteInterval")
    verifyEq(h.read(ts(0),ts(1)).sources,["own"])
  }

  Void testOwnedIntervalsKeepZeroNAFilteredAndRealGapsDistinct()
  {
    records:=[Str:Obj?][
      "pointId":"own","mode":"interval","quality":"derived","samples":Obj?[,],"intervals":[
        ["from":ts(0).toIso,"to":(ts(0)+30min).toIso,"value":0f,"quality":"cleaned"],
        ["from":(ts(0)+30min).toIso,"to":ts(1).toIso,"value":null,"valueType":"na","quality":"na"],
      ]]
    h:=FinEnergyHistoryData(records)
    verifyEq(h.read(ts(0),ts(0)+30min).value,0f)
    verifyEq(h.read(ts(0),ts(1)).quality,"na")
    intervals:=([Str:Obj?][])records["intervals"]
    intervals.last["valueType"]="null"; intervals.last["quality"]="filtered"
    h=FinEnergyHistoryData(records)
    verifyEq(h.read(ts(0),ts(1)).value,0f)
    verifyEq(h.read(ts(0),ts(1)).quality,"filtered")
    intervals.last["from"]=(ts(0)+45min).toIso
    h=FinEnergyHistoryData(records)
    verifyNull(h.read(ts(0),ts(1)).value)
    verifyEq(h.read(ts(0),ts(1)).quality,"missing")
  }

  Void testCutoverUsesLegacyOnlyBeforeAndPublishedOnlyAfter()
  {
    cutover:=ts(0)+30min
    legacy:=Str:Obj?["pointId":"own","mode":"interval","intervals":[
      ["from":ts(0).toIso,"to":cutover.toIso,"value":10f,"quality":"cleaned"],
      ["from":cutover.toIso,"to":ts(1).toIso,"value":9000f,"quality":"cleaned"],
    ]]
    published:=Str:Obj?["pointId":"own","mode":"interval","quality":"derived","intervals":[
      ["from":cutover.toIso,"to":ts(1).toIso,"value":3f,"quality":"derived"],
    ]]
    merged:=FinEnergyHistory.mergePublished(legacy,published,cutover)
    verifyEq(FinEnergyHistoryData(merged).read(ts(0),ts(1)).value,13f)
    verifyEq((([Str:Obj?][])legacy["intervals"]).last["value"],9000f)
    (([Str:Obj?][])published["intervals"]).first["value"]=null
    (([Str:Obj?][])published["intervals"]).first["quality"]="missing"
    merged=FinEnergyHistory.mergePublished(legacy,published,cutover)
    verifyNull(FinEnergyHistoryData(merged).read(ts(0),ts(1)).value)
  }

  Void testNativePublishedIntervalsAreNotDifferencedAndKeepQuality()
  {
    cutover:=ts(0)
    published:=Str:Obj?["cutover":cutover.toIso,"intervals":[
      ["from":ts(0).toIso,"to":(ts(0)+15min).toIso,"value":7f,"quality":"corrected"],
      ["from":(ts(0)+15min).toIso,"to":(ts(0)+30min).toIso,"value":0f,"quality":"substituted"],
      ["from":(ts(0)+30min).toIso,"to":(ts(0)+45min).toIso,"value":null,"valueType":"na","quality":"na"],
      ["from":(ts(0)+45min).toIso,"to":ts(1).toIso,"value":null,"quality":"missing"],
    ]]
    result:=FinEnergyHistory.publishedResult(point("own"),published)
    nativeRows:=FinEnergyHistory.nativeItems(result)
    verifyEq(nativeRows.map |item->Obj?| { item.val },Obj?[Number(7,Unit("kWh")),Number(0,Unit("kWh")),NA.val,null])
    verifyEq(nativeRows.first.ts,ts(0)); verifyEq(nativeRows.last.ts,ts(0)+45min)
    verifyEq(result.details.first["quality"],"corrected")
    verifyEq(result.details[1]["quality"],"substituted")
    verifyEq(result.summary["sourceIds"],["own"])
  }

  Void testExplicitCleaningConfigsDoNotMutatePreviouslyComputedResults()
  {
    frozen:=FinEnergyCleaning.config(["deltaMin":0,"deltaMax":1000,"defNull":true],"kWh")
    latest:=FinEnergyCleaning.config(["deltaMin":0,"deltaMax":1,"defNull":true],"kWh")
    p:=Etc.makeDict(Etc.dictToMap(point("own")).set("hisFuncConfig",latest))
    raw:=[HisItem(ts(0),Number(1000)),HisItem(ts(0)+30min,Number(1010)),HisItem(ts(1),Number(1025))]
    original:=FinEnergyCleaning.clean(p,raw,frozen)
    oldValue:=FinEnergyHistoryData(FinEnergyHistory.normalizeClean(p,original,ts(0),ts(1))).read(ts(0),ts(1))
    verifyEq(oldValue.value,25f)
    current:=FinEnergyCleaning.clean(p,raw,latest)
    verifyNull(FinEnergyHistoryData(FinEnergyHistory.normalizeClean(p,current,ts(0),ts(1))).read(ts(0),ts(1)).value)
    verifyEq(FinEnergyHistoryData(FinEnergyHistory.normalizeClean(p,original,ts(0),ts(1))).read(ts(0),ts(1)).value,25f)
    verifyEq(((Dict)p["hisFuncConfig"])["deltaMax"],Number(1,Unit("kWh")))
  }

  Void testFilteredSubtotalAndNAHaveDifferentSemantics()
  {
    drop:=normalized(null)
    h:=FinEnergyHistoryData(drop)
    value:=h.read(ts(0),ts(1))
    verifyEq(value.value,60f); verifyEq(value.quality,"filtered")
    verifyNull(FinEnergyValue.divide(value,FinEnergyValue(100f,"ok")).value)
    verifyEq(((Map)((Map)drop["cleaning"])["summary"])["coverage"],0.75f)
    na:=FinEnergyHistoryData(normalized(NA.val)).read(ts(0),ts(1))
    verifyNull(na.value); verifyEq(na.quality,"na"); verifyEq(na.valueType,"na")
    verifyEq(FinEnergyValue.sum([value,na]).quality,"na")
  }

  Void testReplacementZeroAndDerivedWriteRemainExplicit()
  {
    h:=FinEnergyHistoryData(normalized(Number(0f,Unit("kWh"))))
    value:=h.read(ts(0),ts(1))
    verifyEq(value.value,60f); verifyEq(value.quality,"substituted")
    verifyNull(FinEnergyValue.divide(value,FinEnergyValue(100f,"ok")).value)
    verifyEq(FinEnergyValue(0f,"cleaned").valueType,"number")
  }

  Void testVirtualTotalCleansIndependentCounterPeriods()
  {
    a:=FinEnergyCleaning.clean(point("a"),[HisItem(ts(0),Number(32760f)),HisItem(ts(1),Number(12f))],FinEnergyCleaning.config(["hisTotalizedRollover":32768,"deltaMax":100],"kWh"))
    b:=FinEnergyCleaning.clean(point("b"),[HisItem(ts(0),Number(99f)),HisItem(ts(1),Number(4f))],FinEnergyCleaning.config(["hisTotalizedRollover":100,"deltaMax":100],"kWh"))
    a.summary["sourceIds"]=["a"]; b.summary["sourceIds"]=["b"]
    total:=FinEnergyHistory.sumClean(point("total"),[a,b],["kWh","kWh"])
    verifyEq(((Number)total.items.first.val).toFloat,25f)
    normalized:=FinEnergyHistory.normalizeClean(point("total"),total,ts(0),ts(1))
    value:=FinEnergyHistoryData(normalized).read(ts(0),ts(1))
    verifyEq(value.value,25f); verifyEq(value.sources.sort,["a","b"])
    // The explicit raw read still has the original absolute counter values.
    verifyEq(((Number)a.rawItems.first.val).toFloat,32760f)
    verifyEq(((Number)a.rawItems.last.val).toFloat,12f)
  }

  Void testGapsAndMisalignedSourcesCannotBecomeMeasuredTotals()
  {
    partial:=normalized(null)
    intervals:=([Str:Obj?][])partial["intervals"]
    intervals.first["quality"]="missing"; intervals.first["value"]=null
    verifyNull(FinEnergyHistoryData(partial).read(ts(0),ts(1)).value)
    a:=FinEnergyCleanResult([HisItem(ts(1),Number(20f))],[["ts":ts(1).toIso,"value":20f,"valueType":"number","reason":"ok","intervalSeconds":3600,"emitted":true]])
    b:=FinEnergyCleanResult([HisItem(ts(2),Number(30f))],[["ts":ts(2).toIso,"value":30f,"valueType":"number","reason":"ok","intervalSeconds":3600,"emitted":true]])
    sum:=FinEnergyHistory.sumClean(point("total"),[a,b],["kWh","kWh"])
    verify(sum.items.all |i| { i.val == null })
    verify(sum.details.all |d| { d["reason"] == "unalignedSources" })
  }

  Void testSourceRolloversSurviveNormalizationAndNestedTotals()
  {
    a:=source("a",[32760f,12f,22f],["hisTotalizedRollover":32768,"deltaMax":100])
    b:=source("b",[98f,3f,7f],["hisTotalizedRollover":100,"deltaMax":100])
    total:=FinEnergyHistory.sumClean(point("total"),[a,b],["kWh","kWh"])
    result:=FinEnergyHistory.normalizeClean(point("total"),total,ts(0),ts(2))
    h:=FinEnergyHistoryData(result)
    verifyEq(h.read(ts(0),ts(1)).value,25f); verifyEq(h.read(ts(1),ts(2)).value,14f)
    meta:=(Str:Obj?)result["cleaning"]
    verifyEq(meta["rolloverCount"],2)
    events:=([Str:Obj?][])meta["details"]
    verifyEq(events.map |e->Str| { e["pointId"].toStr }.sort,["a","b"])
    events.each |e|
    {
      verifyEq(e["intervalStart"],ts(0).toIso); verifyEq(e["intervalEnd"],ts(1).toIso)
      verifyEq(e["rule"],"hisTotalizedRollover"); verifyEq(e["profileVersion"],1)
      verifyEq(e["unit"],"kWh")
    }
    c:=source("c",[98f,3f,7f],["hisTotalizedRollover":100,"deltaMax":100])
    root:=FinEnergyHistory.sumClean(point("root"),[total,c],["kWh","kWh"])
    nested:=(Str:Obj?)FinEnergyHistory.normalizeClean(point("root"),root,ts(0),ts(2))["cleaning"]
    verifyEq(nested["rolloverCount"],3)
    verifyEq((([Str:Obj?][])nested["details"]).map |e->Str| { e["pointId"].toStr }.sort,["a","b","c"])
    late:=(Str:Obj?)FinEnergyHistory.normalizeClean(point("root"),root,ts(1),ts(2))["cleaning"]
    verifyEq(late["rolloverCount"],0); verifyEq((([Str:Obj?][])late["details"]).size,0)
    lateSources:=([Str:Obj?][])late["sources"]
    verifyEq(lateSources.first["rolloverCount"],0)
    verifyEq((([Str:Obj?][])lateSources.first["sources"]).first["rolloverCount"],0)
  }

  Void testSimultaneousSourceFailuresKeepRulesAndIndividualCounts()
  {
    a:=source("a",[100f,90f,95f],["deltaMin":0,"defVal":Number(0f,Unit("kWh"))])
    b:=source("b",[50f,40f,43f],["deltaMin":0,"defNull":true])
    total:=FinEnergyHistory.sumClean(point("total"),[a,b],["kWh","kWh"])
    meta:=(Str:Obj?)FinEnergyHistory.normalizeClean(point("total"),total,ts(0),ts(2))["cleaning"]
    verifyEq(meta["rejectedCount"],2); verifyEq(meta["substitutedCount"],1)
    events:=([Str:Obj?][])meta["details"]
    verifyEq(events.size,2); verify(events.all |e| { e["rule"] == "deltaMin" })
    verifyEq(events.find |e| { e["pointId"] == "a" }["substituted"],true)
    verifyEq(((Map)events.first["parameters"])["deltaMin"],0)
    later:=(Str:Obj?)FinEnergyHistory.normalizeClean(point("total"),total,ts(1),ts(2))["cleaning"]
    verifyEq(later["rejectedCount"],0); verifyEq(later["substitutedCount"],0)
  }

  Void testEvidenceLimitDoesNotTruncateSourceCounts()
  {
    part:=FinEnergyCleanResult(); part.summary["sourceIds"]=["a"]
    1002.times |i|
    {
      at:=ts(0)+Duration((i+1)*1sec.ticks)
      part.items.add(HisItem(at,Number(1f)))
      part.details.add(["ts":at.toIso,"value":1f,"valueType":"number","reason":"rollover","intervalSeconds":1,"emitted":true])
    }
    total:=FinEnergyHistory.sumClean(point("total"),[part],["kWh"])
    meta:=(Str:Obj?)FinEnergyHistory.normalizeClean(point("total"),total,ts(0),ts(1))["cleaning"]
    verifyEq(meta["rolloverCount"],1002); verifyEq(meta["detailsTruncated"],true)
    verifyEq((([Str:Obj?][])meta["details"]).size,1000)
  }

  private FinEnergyCleanResult source(Str id, Float[] readings, Str:Obj? parameters)
  {
    cfg:=FinEnergyCleaning.config(parameters,"kWh")
    result:=FinEnergyCleaning.clean(point(id),readings.map |n,i->HisItem| { HisItem(ts(i),Number(n)) },cfg)
    result.summary.setAll(["pointId":id,"sourceIds":[id],"profileId":"${id}-profile","profileVersion":1,"parameters":parameters])
    return result
  }

  Void testRemovedNAAndSourceEventsRespectQueryBoundaries()
  {
    cfg:=FinEnergyCleaning.config(["hisTotalizedRollover":32768,"deltaMax":100,"removeNA":true],"kWh")
    part:=FinEnergyCleaning.clean(point("a"),[HisItem(ts(0),Number(32760f)),HisItem(ts(0)+15min,NA.val),HisItem(ts(1),Number(12f)),HisItem(ts(2),Number(22f))],cfg)
    part.summary["sourceIds"]=["a"]
    total:=FinEnergyHistory.sumClean(point("total"),[part],["kWh"])
    first:=FinEnergyHistory.cleaningEvidence(point("total"),total,ts(0),ts(1))
    verifyEq(first["removedNACount"],1); verifyEq(first["rolloverCount"],1); verifyEq(first["rejectedCount"],0)
    verifyEq((([Str:Obj?][])first["details"]).size,2)
    later:=FinEnergyHistory.cleaningEvidence(point("total"),total,ts(1),ts(2))
    verifyEq(later["removedNACount"],0); verifyEq(later["rolloverCount"],0)
    verifyEq((([Str:Obj?][])later["details"]).size,0)
  }

  private Str:Obj? normalized(Obj? special)
  {
    items:=HisItem[,]; details:=[Str:Obj?][,]
    [10f,0f,20f,30f].each |n,i|
    {
      at:=ts(0)+Duration((i+1)*15min.ticks)
      val:=i == 1 ? special : Number(n,Unit("kWh"))
      items.add(HisItem(at,val))
      details.add(["ts":at.toIso,"value":val is Number ? ((Number)val).toFloat : null,"valueType":val === NA.val ? "na" : (val == null ? "null" : "number"),"reason":i == 1 ? "deltaMax" : "ok","substituted":i == 1 && val != null,"intervalSeconds":900,"emitted":true])
    }
    result:=FinEnergyCleanResult(items,details,["profileId":"profile","profileVersion":1,"parameters":["deltaMin":0]])
    return FinEnergyHistory.normalizeClean(point("meter"),result,ts(0),ts(1))
  }

  private Dict point(Str id) { Etc.makeDict(["id":Ref(id),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh"]) }
  private DateTime ts(Int h) { DateTime.fromIso("2026-01-01T00:00:00Z")+Duration(h*1hr.ticks) }
}

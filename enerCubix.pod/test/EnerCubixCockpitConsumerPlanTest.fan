using util

** Metadata handoff only. Reports here use the existing tiny fixture engine;
** no native source factory, streaming admission or live FIN proof is claimed.
class EnerCubixCockpitConsumerPlanTest : Test
{
  Void testRequestMetadataIsSeparatedBeforeHistoryParsingEvenWithoutPoints()
  {
    rs:=records;rs.find |r| {r["id"]=="d"}.remove("pointId")
    rq:=input;rq["modules"]=["trend"]
    budget:=EnerCubixStreamBudget()
    diagnostics:=Str:Obj?["schemaVersion":1,"rowBudget":1000,"returnedCount":0,"returnedByKind":[:],"truncated":false,"entries":Obj?[,]].toImmutable
    meta:=Str:Obj?["_cockpitRequestMeta":["schemaVersion":1,"diagnostics":diagnostics,"preparedBudget":budget.state,"streaming":budget.evidence]]
    actual:=EnerCubixCockpit.execute(rq,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {[meta]},"test",TimeZone.utc,end,true,null,null,null,null,[:],|Str key,Str:Obj? q->Str:Obj?| {EnerCubixHistory.report(q,rs,[Str:Obj?][,])})
    verifyEq(actual["diagnostics"],diagnostics)
    proof:=(Map)actual["provenance"];verifyEq(proof["preparedRuntime"],budget.state.evidence)
    verifyEq(((Map)((List)proof["streaming"]).first)["nativeReadCount"],0)
    verifyNull(proof["sourceLastObservedAt"]);verify(EnerCubixMath.maps(proof["historyPlan"]).isEmpty)
    json:=JsonOutStream.writeJsonToStr(actual)
    ["_cockpitRequestMeta","preparedBudget","EnerCubixPreparedBudget"].each |privateName| {verify(!json.contains(privateName))}
    projected:=0
    verifyErr(ArgErr#) {EnerCubixCockpit.execute(rq,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {[meta,meta]},"test",TimeZone.utc,end,true,null,null,null,null,[:],|Str key,Str:Obj? q->Str:Obj?| {projected++;return EnerCubixHistory.report(q,rs,[Str:Obj?][,])})}
    verifyEq(projected,0)
    verifyErr(ArgErr#) {EnerCubixCockpit.execute(input,records,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {[meta]},"test",TimeZone.utc,end)}
  }
  Void testMalformedRequestMetadataRejectsBeforeReportProjection()
  {
    budget:=EnerCubixStreamBudget()
    diagnostics:=Str:Obj?["schemaVersion":1,"rowBudget":1000,"returnedCount":0,"returnedByKind":[:],"truncated":false,"entries":Obj?[,]]
    base:=Str:Obj?["schemaVersion":1,"diagnostics":diagnostics,"preparedBudget":budget.state]
    [base.dup.set("diagnostics",[:]),base.dup.set("diagnostics",diagnostics.dup.set("returnedCount",1001)),base.dup.set("preparedBudget",null),base.dup.set("streaming","invalid"),base.dup.set("historyConfigObservedFrom","invalid"),base.dup.set("publishDiagnostics","invalid")].each |candidate|
    {
      projected:=0
      verifyErr(ArgErr#) {EnerCubixCockpit.execute(input,records,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {[Str:Obj?][["_cockpitRequestMeta":candidate]]},"test",TimeZone.utc,end,true,null,null,null,null,[:],|Str key,Str:Obj? q->Str:Obj?| {projected++;return EnerCubixHistory.report(q,records,histories)})}
      verifyEq(projected,0)
    }
  }
  Void testFrozenPrivatePlanIsReadyBeforeLoadAndAbsentFromSnapshot()
  {
    rs:=records;hs:=histories;rq:=input
    old:=EnerCubixCockpit.execute(rq,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {return hs},"test",TimeZone.utc,end,true,|->DateTime| {end})
    calls:=0;Str? handedBoundary
    actual:=EnerCubixCockpit.execute(rq,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]|
    {
      calls++;verify(q.isImmutable);verify(frozen.isImmutable)
      plan:=q["_cockpitConsumers"] as Map;verifyNotNull(plan);verify(plan.isImmutable)
      report:=(Map)plan["request"];verify(!report.containsKey("_cockpitConsumers"));verifyEq(report["to"],"2026-10-01T02:00:00Z")
      verifyEq(plan["enabled"],rq["modules"]);verifyEq(((Map)plan["comparison"])["mode"],"none")
      verifyEq(((Map)plan["boundary"])["meterIds"],["d"])
      handedBoundary=((Map)plan["boundary"])["id"] as Str
      verify(((Map)plan["flow"])["canonicalRecords"] is List);verifyEq(((List)((Map)plan["efficiency"])["items"]).size,1)
      verifyEq(q["_cockpitPointIds"],["pd","pn"])
      return hs
    },"test",TimeZone.utc,end,true,|->DateTime| {end},null,null,null,[:],|Str key,Str:Obj? q->Str:Obj?| {EnerCubixHistory.report(q,rs,hs)})
    verifyEq(calls,1)
    ["context","limitations"].each |field| {verifyEq(actual[field],old[field])}
    verifyEq(((Map)actual["boundary"])["id"],handedBoundary)
    verifyEq(((Map)actual["boundary"]).findAll |v,k| {k!="id"},((Map)old["boundary"]).findAll |v,k| {k!="id"}) // A fresh boundary ID belongs to each snapshot.
    ["configFingerprint","configRefs","appliedCleaning","sourceLastObservedAt","historyLimitations","historyConfigObservedFrom","historyConfigObservedTo","historyPlan"].each |field| {verifyEq(((Map)actual["provenance"])[field],((Map)old["provenance"])[field])}
    verify(!JsonOutStream.writeJsonToStr(actual).contains("_cockpitConsumers"))
  }
  Void testEmptyPlanStillCallsOnlyTheExplicitMetadataLoader()
  {
    rs:=records;rs.find |r| {r["id"]=="d"}.remove("pointId")
    rq:=input;rq["modules"]=["trend"]
    calls:=0
    actual:=EnerCubixCockpit.execute(rq,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]|
    {calls++;verify(((List)q["_cockpitRanges"]).isEmpty);verify(EnerCubixMath.strings(q["_cockpitPointIds"]).isEmpty);verify(q["_cockpitConsumers"] is Map);return [Str:Obj?][,]},"test",TimeZone.utc,end,true,null,null,null,null,[:],|Str key,Str:Obj? q->Str:Obj?| {EnerCubixHistory.report(q,rs,[Str:Obj?][,])})
    verifyEq(calls,1);verify(EnerCubixMath.maps(((Map)actual["provenance"])["historyPlan"]).isEmpty)
    verifyNull(((Map)actual["provenance"])["sourceLastObservedAt"])
    verifyEq(((Map)actual["provenance"])["streaming"],Obj?[,])
    legacyCalls:=0
    EnerCubixCockpit.execute(rq,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {legacyCalls++;return [Str:Obj?][,]},"test",TimeZone.utc,end)
    verifyEq(legacyCalls,0)
  }
  Void testExternalInputCannotInjectConsumerMetadata()
  {
    q:=input;q["_cockpitConsumers"]=["request":[:]]
    verifyErr(ArgErr#) {EnerCubixCockpit.query(q,"test",TimeZone.utc,end)}
  }
  private DateTime end() {DateTime.fromIso("2026-10-01T02:00:00Z")}
  private Str:Obj? input() {["schemaVersion":1,"requestId":"consumer-plan","reportScope":["dimension":"space","spaceSource":"fin","nodeIds":["s"],"selectionIntent":"range"],"focusCategoryId":"cd","time":["preset":"custom","period":"hour","from":"2026-10-01T00:00:00Z","to":end.toIso],"asOf":end.toIso,"comparison":["mode":"none"],"modules":["kpis","trend","space","time","endUse","organization","balance","efficiency","issues"]]}
  private [Str:Obj?][] records() {[["id":"cn","kind":"category","unit":"MWh"],["id":"cd","kind":"category","unit":"kWh"],["id":"s","kind":"space","nativeSourceKind":"site","area":1000f],["id":"n","kind":"meter","nativeEquip":true,"nativeTreeParentId":"s","nativeSpaceId":"s","spaceId":"s","categoryId":"cn","pointId":"pn"],["id":"d","kind":"meter","nativeEquip":true,"nativeTreeParentId":"s","nativeSpaceId":"s","spaceId":"s","categoryId":"cd","pointId":"pd"],["id":"cop","kind":"cop","numeratorId":"n","denominatorId":"d"],["id":"tariff","kind":"tariff","categoryId":"cd","mode":"flat","isDefault":true,"rate":1f]]}
  private [Str:Obj?][] histories() {[["pointId":"pn","mode":"interval","unit":"MWh","samples":[["ts":"2026-10-01T00:00:00Z","value":0.1f],["ts":"2026-10-01T01:00:00Z","value":0.2f]]],["pointId":"pd","mode":"interval","unit":"kWh","samples":[["ts":"2026-10-01T00:00:00Z","value":10f],["ts":"2026-10-01T01:00:00Z","value":40f]]]]}
}

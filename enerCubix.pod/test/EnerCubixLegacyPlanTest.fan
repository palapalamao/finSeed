using haystack

class EnerCubixLegacyPlanTest : Test
{
  Void testRejectsCycleAcrossStaggeredWindows()
  {
    rows:=[timedEdge("b","d",0,1),timedEdge("c","e",1,2),timedEdge("a","f",10,12),timedEdge("a","b",0,10),timedEdge("b","c",1,11),timedEdge("c","a",2,12)]
    verifyErr(ArgErr#) {EnerCubixLegacyMembership.validate(rows)}
    verifyErr(ArgErr#) {EnerCubixLegacyMembership.validate(rows.dup.reverse)}
  }

  Void testCycleLookingEdgesThatNeverCoexistAreAccepted()
  {
    rows:=[timedEdge("b","d",0,1),timedEdge("c","e",1,2),timedEdge("a","f",10,12),timedEdge("a","b",0,10),timedEdge("b","c",1,11),timedEdge("c","a",10,12)]
    EnerCubixLegacyMembership.validate(rows)
    EnerCubixLegacyMembership.validate([timedEdge("a","b",0,1),timedEdge("b","a",1,2)])
    verify(true)
  }

  private Str:Obj? timedEdge(Str child,Str parent,Int start,Int end)
  {
    from:=DateTime.fromIso("2026-10-24T00:00:00+08:00")
    return ["childId":child,"parentId":parent,"pointId":"p"+child,"categoryId":"e","proofId":child+start.toStr,"from":(from+1hr*start).toIso,"to":(from+1hr*end).toIso]
  }

  Void testBackupEntryLimitRejectsBeforeReadingAnUnboundedEntry()
  {
    verifyEq(EnerCubixLegacyBackup.readLimited("small".toBuf.in,5).readAllStr,"small")
    verifyErr(ArgErr#) {EnerCubixLegacyBackup.readLimited("larger".toBuf.in,5)}
  }
  Void testLegacyBusinessTimeSurvivesNamespaceOnlyModification()
  {
    business:=DateTime.fromIso("2026-10-23T23:22:00+08:00")
    raw:=Etc.makeDict(["id":Ref("old"),"mod":DateTime.fromIso("2026-10-24T03:33:00+08:00"),"dis":"Legacy","seedKind":"meter","seedUpdatedAt":business,"seedConfig":"{}"])
    decoded:=EnerCubixLegacyBackup.decode(raw)
    verifyEq(decoded["updatedAt"],business.toIso);verifyEq(decoded["kind"],"meter")
  }
  Void testStablePointRefsAndBusinessRevisionMapWithoutNameMatching()
  {
    result:=EnerCubixLegacyMembership.plan(input,sources,["oldA":"a","oldM":"m"])
    e:=EnerCubixMath.maps(result["edges"]).first
    verifyEq(e["childId"],"a");verifyEq(e["parentId"],"m");verifyEq(e["pointId"],"pa")
    verifyEq(e["from"],input["from"]);verifyEq(e["to"],input["to"]);verifyEq(e["basis"],"snapshotRecovered")
  }

  Void testChangedParentsOrBindingsNeedSeparateEvidenceRanges()
  {
    ss:=sources
    (([Str:Obj?][])ss[1]["records"])[0]["meterParentId"]="other"
    verifyErr(ArgErr#) {EnerCubixLegacyMembership.plan(input,ss,["oldA":"a","oldM":"m"])}
    ss=sources;(([Str:Obj?][])ss[1]["records"])[0]["pointId"]="newPoint"
    verifyErr(ArgErr#) {EnerCubixLegacyMembership.plan(input,ss,["oldA":"a","oldM":"m"])}
  }

  Void testRejectsMissingMappingFutureBusinessRevisionAndUnobservedEnd()
  {
    verifyErr(ArgErr#) {EnerCubixLegacyMembership.plan(input,sources,Str:Str[:])}
    q:=input;q["from"]="2026-10-23T00:00:00+08:00"
    verifyErr(ArgErr#) {EnerCubixLegacyMembership.plan(q,sources,["oldA":"a","oldM":"m"])}
    q=input;q["to"]="2026-10-26T00:00:00+08:00"
    verifyErr(ArgErr#) {EnerCubixLegacyMembership.plan(q,sources,["oldA":"a","oldM":"m"])}
  }

  Void testRejectsOverlappingEdgesCyclesAndCrossEnergyParents()
  {
    base:=Str:Obj?["childId":"a","parentId":"m","pointId":"pa","categoryId":"e","proofId":"p","from":input["from"],"to":input["to"]]
    verifyErr(ArgErr#) {EnerCubixLegacyMembership.validate([base,base.dup.set("parentId","other")])}
    verifyErr(ArgErr#) {EnerCubixLegacyMembership.validate([base,base.dup.set("childId","m").set("parentId","a").set("pointId","pm")])}
    ss:=sources;(([Str:Obj?][])ss[0]["records"])[1]["categoryId"]="water"
    verifyErr(ArgErr#) {EnerCubixLegacyMembership.plan(input,ss,["oldA":"a","oldM":"m"])}
  }

  private Str:Obj? input() { ["from":"2026-10-24T00:00:00+08:00","to":"2026-10-25T00:00:00+08:00","legacyIds":["oldA"]] }
  private [Str:Obj?][] sources()
  {
    [Str:Obj?][] rs:=[["id":"oldA","kind":"meter","name":"Unrelated display A","pointId":"pa","meterParentId":"oldM","categoryId":"e","unit":"kWh","includeInTotals":true,"updatedAt":"2026-10-23T23:22:00+08:00"],["id":"oldM","kind":"meter","name":"Different display B","pointId":"pm","categoryId":"e","unit":"kWh","updatedAt":"2026-10-24T00:05:00+08:00"]]
    return [["file":"first.zip","sha256":"a","capturedAt":"2026-10-24T00:12:00+08:00","records":rs],["file":"last.zip","sha256":"b","capturedAt":"2026-10-25T00:11:00+08:00","records":rs.map |r->[Str:Obj?]| {r.dup}]]
  }
}

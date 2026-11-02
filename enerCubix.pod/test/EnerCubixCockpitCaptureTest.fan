** Diagnostic samples only; this pool is never a numeric report data source.
class EnerCubixCockpitCaptureTest : Test
{
  Void testLateDiagnosticGroupsReceiveFairSamplesWithinWholePacketLimit()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
    pool:=EnerCubixCockpitCapture(plan,owner)
    (0..<1800).each |i| {pool.put("clean",row(i));verify(pool.retainedRows<=1000)}
    (0..<1500).each |i|
    {
      r:=row(i).set("intervals",[row(i)]).set("intervalCount",1)
      pool.put("reads",r);verify(pool.retainedRows<=1000)
    }
    (0..<1200).each |i| {pool.put("flow",row(i));verify(pool.retainedRows<=1000)}
    verifyErr(ArgErr#) {pool.freeze}
    ["clean","reads","flow"].each |key| {pool.seal(key)}
    result:=pool.freeze;verifyEq(result["rowBudget"],1000);verify((Int)result["returnedCount"]<=1000)
    weights:=[pool.rows("clean").size,pool.rows("reads").size*2,pool.rows("flow").size]
    verify((Int)weights.max-(Int)weights.min<=2,"late groups must not be starved by an earlier full pool")
    entries:=EnerCubixMath.maps(result["entries"])
    ["cleaningEvents":1800,"sourceUsage":1500,"sourceIntervals":1500,"coveragePeriods":1200].each |n,kind|
    {verifyEq(entries.find |e| {e["kind"]==kind}["totalCount"],n)}
    verifyEq(((Map)result["returnedByKind"])["sourceIntervals"],pool.rows("reads").size)
    escaped:=pool.rows("clean");sample:=escaped.first
    owner.close;verify(escaped.isEmpty);verify(sample.isEmpty);verify(result.isEmpty);verifyEq(budget.temporary.val,0)
    verifyErr(ArgErr#) {pool.freeze}
  }

  Void testNestedIntervalsAreRowsAndInputContainersRemainUntouched()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
    pool:=EnerCubixCockpitCapture(plan,owner)
    raw:=row(1).set("intervals",(0..<2000).map |i->Obj?| {row(i)}).set("intervalCount",2000)
    before:=raw.toStr;pool.put("reads",raw)
    saved:=pool.rows("reads").first
    verify(saved!==raw);verify(((List)saved["intervals"]).size<2000);verifyEq(saved["detailsTruncated"],true)
    verifyEq(pool.retainedRows,1+((List)saved["intervals"]).size)
    ["clean","reads","flow"].each |key| {pool.seal(key)}
    result:=pool.freeze;verifyEq(EnerCubixMath.maps(result["entries"]).find |r| {r["kind"]=="sourceIntervals"}["totalCount"],2000)
    owner.close;verifyEq(raw.toStr,before);verify(saved.isEmpty);verifyEq(budget.temporary.val,0)
  }

  Void testOwnerGuardAndRejectedCopyPreserveOtherOwners()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
    pool:=EnerCubixCockpitCapture(plan,owner);output:=EnerCubixPreparedOwner(budget);pool.bind(output)
    verifyErr(ArgErr#) {owner.close}
    peer:=EnerCubixPreparedOwner(budget);peer.hold(budget.remaining);held:=peer.entries
    verifyErr(EnerCubixHttpErr#) {pool.put("clean",row(1))};verifyErr(EnerCubixHttpErr#) {pool.freeze}
    output.close;owner.close;verifyEq(budget.temporary.val,held);peer.close;verifyEq(budget.temporary.val,0)
  }
  Void testTruncatedParentSlicesUseDistinctIdentitiesAndTruthfulReasons()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
    pool:=EnerCubixCockpitCapture(plan,owner)
    raw:=row(1).set("intervals",(0..<1000).map |i->Obj?| {row(i)}).set("intervalCount",2000).set("detailsTruncated",true).set("intervalsCaptureId","upstream-capture")
    pool.put("reads",raw);pool.put("reads",raw)
    saved:=pool.rows("reads")
    verify(saved[0]["intervalsCaptureId"]!=saved[1]["intervalsCaptureId"])
    verify(saved[0]["intervalsCaptureId"]!="upstream-capture")
    ["clean","reads","flow"].each |key| {pool.seal(key)}
    result:=pool.freeze;entries:=EnerCubixMath.maps(result["entries"])
    verifyEq(entries.find |e| {e["kind"]=="sourceUsage"}["reason"],"complete")
    child:=entries.find |e| {e["kind"]=="sourceIntervals"}
    verifyEq(child["reason"],"upstreamAndSnapshotLimit");verify(child["returnedRange"] is Map)
    // Account every actual retained map/list once, including cloned descriptors
    // and metadata heads. Class metadata is reserved separately by the pool.
    roots:=Obj?[result,pool.protectedRoots]
    ["groups","heads","metadataEntries","byKind","bindings"].each |name| {roots.add(EnerCubixCockpitCapture#.field(name).get(pool))}
    ((Map)EnerCubixCockpitCapture#.field("groups").get(pool)).each |EnerCubixCockpitCaptureGroup g|
    {roots.add(g.spec);roots.add(g.rows);roots.add(g.cells);g.cells.each |c| {roots.add(c.row)}}
    seen:=Obj[,];Int graph:=roots.reduce(0) |Int n,v->Int| {n+count(v,seen)}
    rowCharges:=0
    ((Map)EnerCubixCockpitCapture#.field("groups").get(pool)).each |EnerCubixCockpitCaptureGroup g| {g.cells.each |c| {rowCharges+=c.owner.entries}}
    verify(owner.entries+rowCharges>=graph,"admit retained diagnostic, descriptor and metadata graphs")
    echo("DIAGNOSTIC_GRAPH retained="+graph+" admitted="+(owner.entries+rowCharges)+" rows="+pool.retainedRows+" peak="+budget.peak.val)
    metadataList:=(List)result["entries"];owner.close;verify(metadataList.isEmpty);verifyEq(budget.temporary.val,0)
  }
  Void testUnknownCountsAndCyclesCannotBecomeSuccessfulEmptyEvidence()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
    pool:=EnerCubixCockpitCapture(plan,owner)
    pool.seal("clean",true);pool.seal("reads");pool.seal("flow")
    result:=pool.freeze;entry:=EnerCubixMath.maps(result["entries"]).find |e| {e["kind"]=="cleaningEvents"}
    verifyEq(entry["totalCount"],null);verifyEq(entry["truncated"],true);verifyEq(entry["reason"],"upstreamDiagnosticLimit")
    verifyErr(ArgErr#) {pool.put("clean",row(1))};verify(pool.freeze===result);owner.close
    owner=EnerCubixPreparedOwner(budget);pool=EnerCubixCockpitCapture(plan,owner)
    cycle:=Str:Obj?[:];cycle["self"]=cycle
    verifyErr(ArgErr#) {pool.put("clean",cycle)};verifyErr(ArgErr#) {pool.freeze}
    owner.close;verify(cycle["self"]===cycle);verifyEq(budget.temporary.val,0)
  }
  Void testWideParentTailCannotEvictAnEntireExistingDiagnosticGroup()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
    pool:=EnerCubixCockpitCapture(plan,owner)
    (0..<1800).each |i| {pool.put("clean",row(i))}
    raw:=row(1).set("intervals",(0..<2000).map |i->Obj?| {row(i)}).set("intervalCount",2000)
    (0..<10).each |i| {pool.put("reads",raw)}
    (0..<1500).each |i| {pool.put("flow",row(i))}
    verify(!pool.rows("clean").isEmpty);verify(!pool.rows("reads").isEmpty);verify(!pool.rows("flow").isEmpty)
    verify(pool.retainedRows<=1000)
    ["clean","reads","flow"].each |key| {pool.seal(key)}
    result:=pool.freeze;verifyEq(result["returnedCount"],pool.retainedRows)
    owner.close;verifyEq(budget.temporary.val,0)
  }
  Void testEarlyFinishedReportTruncationUsesFinalGlobalSample()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
    pool:=EnerCubixCockpitCapture(plan,owner);output:=EnerCubixPreparedOwner(budget);output.hold(12)
    known:=Str:Obj?["basis":"closedSourceIntervals","sourceUsage":pool.rows("reads"),"detailsTruncated":false]
    output.watch |->Void| {known.clear};pool.bind(output)
    (0..<800).each |i| {pool.put("reads",row(i))}
    pool.knownEnvelope("reads",known,output,800)
    pool.seal("reads")
    (0..<1800).each |i| {pool.put("clean",row(i))}
    (0..<1200).each |i| {pool.put("flow",row(i))}
    pool.seal("clean");pool.seal("flow");pool.freeze
    verify(pool.rows("reads").size<800)
    verifyEq(known["sourceUsageTruncated"],true,"later groups must update an earlier report's final evidence status")
    verifyEq(known["sourceUsageRowCount"],800);verifyEq(known["detailsTruncated"],true)
    output.close;owner.close;verifyEq(budget.temporary.val,0)
  }
  private Int count(Obj? value,Obj[] seen)
  {
    if(value isnot Map && value isnot List) return 0
    if(seen.any |v| {v===value}) return 0
    seen.add(value)
    if(value is Map) return ((Map)value).vals.reduce(1+((Map)value).size) |Int n,v->Int| {n+count(v,seen)}
    return ((List)value).reduce(1+((List)value).size) |Int n,v->Int| {n+count(v,seen)}
  }
  private Str:[Str:Obj?] plan()
  {
    (Str:[Str:Obj?])Str:[Str:Obj?][
      "clean":["kind":"cleaningEvents","grain":"cleaningEvent","reportRefs":["profile-energy"]],
      "reads":["kind":"sourceUsage","grain":"sourceRead","reportRefs":["profile-energy"]],
      "flow":["kind":"coveragePeriods","grain":"hour","reportRefs":["energy-flow"]]].toImmutable
  }
  private Str:Obj? row(Int i)
  { ["pointId":"p","sourceIds":["p"],"from":(at+1min*i).toIso,"to":(at+1min*(i+1)).toIso,"value":i.toFloat] }
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

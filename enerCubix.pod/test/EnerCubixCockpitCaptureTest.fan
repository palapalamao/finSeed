** Diagnostic samples only; this pool is never a numeric report data source.
class EnerCubixCockpitCaptureTest : Test
{
  Void testFinalizedEnvelopeTargetsRetireBeforeCompletedReportFactsAreConsumed()
  {
    scope:=EnerCubixCockpitRequestScope("retired-envelope-targets","a");budget:=scope.stream.state
    owner:=EnerCubixPreparedOwner(budget);pool:=EnerCubixCockpitCapture(plan,owner)
    first:=EnerCubixPreparedOwner(budget);second:=EnerCubixPreparedOwner(budget)
    a:=Str:Obj?[:];ar:=Str:Obj?[:];b:=Str:Obj?[:];br:=Str:Obj?[:]
    sourceA:=Str:Obj?["known":a,"row":ar];sourceB:=Str:Obj?["known":b,"row":br]
    first.hold(96);second.hold(96)
    first.watch |->Void| {EnerCubixReportConsumer.clearPublic(sourceA,Obj[,],pool.protectedRoots)}
    second.watch |->Void| {EnerCubixReportConsumer.clearPublic(sourceB,Obj[,],pool.protectedRoots)}
    try
    {
      pool.put("reads",row(1));pool.put("flow",row(1))
      pool.knownEnvelope("reads",a,first,1);pool.periodEnvelope("flow",ar,first,1)
      pool.knownEnvelope("reads",b,second,1);pool.periodEnvelope("flow",br,second,1)
      ["clean","reads","flow"].each |key| {pool.seal(key)};pool.freeze
      // These envelopes must no longer retain aliases to report-owned heads.
      verify(((List)pool->envelopes).isEmpty);verify(((List)pool->periodEnvelopes).isEmpty)
      verify(a["sourceUsage"]===pool.rows("reads"));verify(br["periods"]===pool.rows("flow"))
      expected:=sourceB.toImmutable;scope.prepareReportBorrows(Obj[,],pool.protectedRoots)
      one:=scope.freezeOwnedReport("first",sourceA,first);scope.prepareReportFacts(sourceB,second)
      verify(b.isEmpty);verify(br.isEmpty)
      two:=scope.freezeOwnedReport("second",sourceB,second);verifyEq(two,expected)
      verify(((Map)one["known"])["sourceUsage"]===((Map)two["known"])["sourceUsage"])
      verifyEq(pool.rows("reads").first["value"],1f);verifyEq(pool.rows("flow").first["value"],1f)
      first.close;second.close;scope.releaseReportBorrows;owner.close;verifyEq(two,expected)
    }
    finally {first.close;second.close;scope.close;owner.close}
    verifyEq(budget.temporary.val,0)
  }

  Void testBusinessOwnerAdmitsItsHeaderAndForkBeforeReclaimingOnlyMutableSamples()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget);pool:=EnerCubixCockpitCapture(plan,owner)
    (0..<30).each |i| {pool.put("clean",row(i))}
    peer:=EnerCubixPreparedOwner(budget);peer.hold(budget.remaining-3);held:=peer.entries
    business:=EnerCubixPreparedOwner(budget,pool);verifyEq(business.entries,5);verifyEq(peer.entries,held);verifyEq(pool.retainedRows,0)
    child:=business.fork;verifyEq(child.entries,5);child.hold(12)
    verifyErr(ArgErr#) {child.hold(-1)};verifyEq(peer.entries,held);verify(budget.peak.val<=200000)
    child.close;business.close;peer.close;["clean","reads","flow"].each |key| {pool.seal(key)};pool.freeze;owner.close;verifyEq(budget.temporary.val,0)
  }
  Void testBusinessAdmissionCannotEvictFrozenSamplesOrBorrowAnotherBudget()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget);pool:=EnerCubixCockpitCapture(plan,owner)
    pool.put("clean",row(1));["clean","reads","flow"].each |key| {pool.seal(key)};pool.freeze
    sample:=pool.rows("clean").first;before:=sample.toStr
    foreign:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());verifyErr(ArgErr#) {bad:=EnerCubixPreparedOwner(foreign,pool)};verifyEq(foreign.temporary.val,0)
    peer:=EnerCubixPreparedOwner(budget);peer.hold(budget.remaining);held:=peer.entries
    verifyErr(EnerCubixHttpErr#) {blocked:=EnerCubixPreparedOwner(budget,pool)}
    verifyEq(pool.retainedRows,1);verifyEq(sample.toStr,before);verifyEq(peer.entries,held)
    peer.close;owner.close;verifyEq(budget.temporary.val,0)
  }

  Void testOptionalSamplesYieldWithoutFailingAnOtherwiseAdmittedQuery()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
    pool:=EnerCubixCockpitCapture(plan,owner)
    (0..<12).each |i| {pool.put("reads",row(i).set("intervals",[row(i)]).set("intervalCount",1))}
    peer:=EnerCubixPreparedOwner(budget);peer.hold(budget.remaining-80);held:=peer.entries
    verifyEq(pool.put("clean",row(1)),false)
    verifyEq(pool.retainedRows,0);verifyEq(peer.entries,held)
    // Once pressure has reclaimed optional samples, later hours keep exact
    // logical counters without growing this pool again.
    (0..<5).each |i| {verifyEq(pool.put("flow",row(i)),false)}
    peer.close
    ["clean","reads","flow"].each |key| {pool.seal(key)}
    result:=pool.freeze;verifyEq(result["returnedCount"],0);verifyEq(result["preparedEntryLimited"],true)
    entries:=EnerCubixMath.maps(result["entries"])
    ["cleaningEvents":1,"sourceUsage":12,"sourceIntervals":12,"coveragePeriods":5].each |n,kind|
    {entry:=entries.find |e| {e["kind"]==kind};verifyEq(entry["totalCount"],n);verifyEq(entry["returnedCount"],0);verifyEq(entry["reason"],"snapshotDiagnosticBudget")}
    verify(budget.peak.val<=200000);owner.close;verifyEq(budget.temporary.val,0)
  }

  Void testPublishedMetadataDropsAbsentReportsWithoutResamplingOrMutatingFrozenEvidence()
  {
    (0..<3).each |variant|
    {
      budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
      spec:=plan.dup;spec["clean"]=spec["clean"].dup.set("reportRefs",["profile-energy","profile-cost"])
      pool:=EnerCubixCockpitCapture(spec,owner)
      pool.put("clean",row(1));pool.put("reads",row(1).set("intervals",[row(1)]).set("intervalCount",1));pool.put("flow",row(1))
      ["clean","reads","flow"].each |key| {pool.seal(key)}
      frozen:=pool.freeze;before:=frozen.toStr;sample:=pool.rows("reads").first
      reports:=variant==0 ? Str:Obj?["profile-energy":[:],"profile-cost":[:],"energy-flow":[:]] : (variant==1 ? Str:Obj?["profile-energy":[:]] : Str:Obj?[:])
      published:=pool.publish(reports);rows:=EnerCubixMath.maps(published["entries"])
      verifyEq(published["returnedCount"],variant==0 ? 4 : (variant==1 ? 3 : 0))
      verifyEq(published["returnedCount"],rows.reduce(0) |Int n,Map r->Int| {n+(Int)r["returnedCount"]})
      verify(rows.all |r| {EnerCubixMath.strings(r["reportRefs"]).all |ref| {reports.containsKey(ref)}})
      verifyEq(frozen.toStr,before);verify(pool.rows("reads").first===sample);verifyErr(ArgErr#) {pool.publish(reports)}
      peer:=EnerCubixPreparedOwner(budget);peer.hold(budget.remaining);held:=peer.entries
      owner.close;verify(published.isEmpty);verify(sample.isEmpty);verifyEq(budget.temporary.val,held)
      peer.close;verifyEq(budget.temporary.val,0)
    }
  }
  Void testRejectedPublicationPreservesTheOtherOwnersAllocation()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
    pool:=EnerCubixCockpitCapture(plan,owner);["clean","reads","flow"].each |key| {pool.seal(key)};pool.freeze
    peer:=EnerCubixPreparedOwner(budget);peer.hold(budget.remaining);held:=peer.entries
    verifyErr(EnerCubixHttpErr#) {pool.publish(["profile-energy":[:]])}
    verifyEq(peer.entries,held);owner.close;verifyEq(budget.temporary.val,held);peer.close;verifyEq(budget.temporary.val,0)
  }
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
    verifyEq(pool.put("clean",row(1)),false);["clean","reads","flow"].each |key| {pool.seal(key)};verifyErr(EnerCubixHttpErr#) {pool.freeze}
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

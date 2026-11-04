using util

** Controlled request/gate/wire lifetime, not native HTTP authentication proof.
class EnerCubixCockpitRequestScopeTest : Test
{
  Void testCleaningFactChargesImmutableDescendantsThroughFinalScopeLifetime()
  {
    [false,true].each |immutableRoot|
    {
      scope:=EnerCubixCockpitRequestScope("cleaning-fact-ownership","a");budget:=scope.stream.state
      source:=Str:Obj?["nested":Str:Obj?["values":[1,2,3]].toImmutable]
      if(immutableRoot) source=(Str:Obj?)source.toImmutable
      try
      {
        owner:=scope.historyOutput;before:=owner.entries
        result:=(Map)scope->freezeCleaningFact(source)
        verify(result.isImmutable);verifyEq(result,source);verify(result["nested"]===source["nested"])
        // Outer map2 + nested map2 + vector4, plus one retained root holder.
        verify(owner.entries-before>=8+3,"already immutable source containers need their own surviving ownership")
        frozen:=scope.freezeSnapshot(["fact":result]);verify(frozen["fact"]===result)
      }
      finally {scope.close}
      verifyEq(budget.temporary.val,0)
    }
  }

  Void testCleaningFactRejectsCyclesAndQuotaWithoutMutatingItsSource()
  {
    scope:=EnerCubixCockpitRequestScope("cleaning-fact-failure","a");budget:=scope.stream.state
    source:=Str:Obj?[:];source["self"]=source;peer:=EnerCubixPreparedOwner(budget)
    try
    {
      before:=scope.entries;verifyErr(NotImmutableErr#) {scope->freezeCleaningFact(source)}
      verifyEq(scope.entries,before);verify(source["self"]===source)
      bad:=Obj:Obj?[:];bad[Str:Obj?["key":1].toImmutable]=0
      verifyErr(NotImmutableErr#) {scope->freezeCleaningFact(bad)};verifyEq(scope.entries,before)
      source.clear;source["value"]=0
      peer.hold(budget.remaining-1);held:=peer.entries
      verifyErr(EnerCubixHttpErr#) {scope->freezeCleaningFact(source)}
      verifyEq(peer.entries,held);verifyEq(scope.entries,before);verifyEq(source["value"],0)
      peer.close;result:=(Map)scope->freezeCleaningFact(source);verifyEq(result["value"],0)
    }
    finally {peer.close;scope.close}
    verifyEq(budget.temporary.val,0)
  }

  Void testConservativePublicGraphCompactionFitsSmallTraversalWorkspace()
  {
    scope:=EnerCubixCockpitRequestScope("public-graph-compaction","a");budget:=scope.stream.state
    producer:=EnerCubixPreparedOwner(budget);peer:=EnerCubixPreparedOwner(budget)
    rows:=[Str:Obj?][,];400.times |i| {rows.add(["value":i])};source:=Str:Obj?["rows":rows]
    producer.hold(2000);scope.prepareReportBorrows(Obj[,],Obj[,]);peer.hold(budget.remaining-96);held:=peer.entries
    try
    {
      verifyEq(scope.publicReportEntries(["value":0],12),12)
      compact:=scope.publicReportEntries(source,producer.entries)
      verifyEq(compact,2+401+400*2+32)
      verifyEq(peer.entries,held);verifyEq(rows.size,400);verifyEq(rows.last["value"],399)
      verifyEq(budget.temporary.val,scope.entries+producer.entries+peer.entries)
    }
    finally {producer.close;scope.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }

  Void testPrivateSourceHeadersTransferBeforeReportsWithoutAnExtraDeepCopy()
  {
    scope:=EnerCubixCockpitRequestScope("owned-source-headers","a");budget:=scope.stream.state
    producer:=EnerCubixPreparedOwner(budget);peer:=EnerCubixPreparedOwner(budget);rows:=[Str:Obj?][,];stats:=Str:Obj?["nativeReadCount":17]
    100.times |i|
    {
      row:=Str:Obj?["pointId":"p$i","unit":"kWh","sourceIds":["p$i"],"configRefs":[["id":"cfg$i","mod":"version"]],"streaming":stats]
      20.times |j| {row["metadata$j"]=j};rows.add(row)
    }
    expected:=rows.toImmutable;producer.hold(8000);producer.watch |->Void| {rows.clear}
    peer.hold(budget.remaining-2200);held:=peer.entries
    try
    {
      result:=scope.freezeSourceHeaders(rows,producer)
      verify(result.isImmutable);verifyEq(result,expected);verify(rows.isEmpty);verify(stats.isEmpty)
      verify(result.first["streaming"]===result.last["streaming"]);verifyEq(((Map)result.first["streaming"])["nativeReadCount"],17)
      verify(scope.freezeHistoryHeaders(result.dup)===result)
      verifyErr(ArgErr#) {scope.freezeHistoryHeaders([result.first.dup])}
      producer.close;verifyEq(peer.entries,held);scope.close;verifyEq(budget.temporary.val,held)
    }
    finally {producer.close;scope.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }

  Void testImmutablePayloadBorrowingRequiresThisScopesLiveSnapshotAndOutput()
  {
    scope:=EnerCubixCockpitRequestScope("payload-source","a");foreign:=EnerCubixCockpitRequestScope("payload-source","b")
    other:=EnerCubixPreparedOwner(scope.stream.state)
    try
    {
      source:=scope.freezeSnapshot(["rows":[["value":0f]],"diagnostics":["rowBudget":1000]])
      output:=scope.payloadOutput;verify(scope.canBorrowPayload(source,output))
      equal:=source.dup.toImmutable;verifyEq(equal,source);verify(!scope.canBorrowPayload(equal,output))
      verify(!scope.canBorrowPayload(source,other));verify(!foreign.canBorrowPayload(source,output))
      // A diagnostic projection may construct a new immutable graph. It has
      // equal business values, but does not carry this scope's admission proof.
      projected:=(Str:Obj?)source.dup.set("diagnostics",["changed":true]).toImmutable
      verify(!scope.canBorrowPayload(projected,output))
      output.close;verify(!scope.canBorrowPayload(source,output))
    }
    finally {other.close;scope.close;foreign.close}
    verifyEq(scope.stream.state.temporary.val,0);verifyEq(foreign.stream.state.temporary.val,0)
  }

  Void testOwnedReportTransferPreservesAliasesAndEveryBorrowedDescendant()
  {
    scope:=EnerCubixCockpitRequestScope("transfer-aliases","a");budget:=scope.stream.state
    producer:=EnerCubixPreparedOwner(budget);other:=EnerCubixPreparedOwner(budget)
    child:=Str:Obj?["values":[7f,null,0f]];sample:=Str:Obj?["quality":"partial","detail":[child]]
    catalog:=Str:Obj?["nested":[child]];beforeCatalog:=catalog.toImmutable;beforeSample:=sample.toImmutable
    shared:=Str:Obj?["name":"中文 😀","values":[12.5f,null,0f]];equal:=shared.dup
    source:=Str:Obj?[:];source.ordered=true
    source["same"]=[shared,shared];source["equal"]=equal;source["directBorrow"]=child
    source["sampleBorrow"]=sample["detail"];source["distinctEqualBorrow"]=child.dup
    expected:=source.toImmutable;producer.hold(512);producer.watch |->Void| {source.clear}
    second:=Str:Obj?["directBorrow":child,"sampleBorrow":sample]
    secondExpected:=second.toImmutable;other.hold(128);other.watch |->Void| {second.clear}
    try
    {
      scope.prepareReportBorrows([catalog],[sample])
      result:=scope.freezeOwnedReport("first",source,producer)
      verify(result.isImmutable);verify(result.ordered);verifyEq(result,expected)
      same:=(List)result["same"];verify(same.first===same.last);verify(same.first!==result["equal"])
      verify(((Map)same.first)["values"]===((Map)result["equal"])["values"])
      verify(result["directBorrow"]!==result["distinctEqualBorrow"])
      verify(source.isEmpty);verify(shared.isEmpty);verify(equal.isEmpty)
      verifyEq(catalog,beforeCatalog);verifyEq(sample,beforeSample);verifyEq(child["values"],[7f,null,0f])
      verify(scope.frozenReport("first")===result);producer.close
      next:=scope.freezeOwnedReport("second",second,other);verifyEq(next,secondExpected)
      verifyEq(catalog,beforeCatalog);verifyEq(sample,beforeSample);other.close
      verifyEq(result,expected);verifyEq(next,secondExpected)
    }
    finally {producer.close;other.close;scope.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testOwnedWideReportTransfersParentLinksBeforeCopyingItsChildren()
  {
    scope:=EnerCubixCockpitRequestScope("wide-report-transfer","a");budget:=scope.stream.state
    producer:=EnerCubixPreparedOwner(budget);peer:=EnerCubixPreparedOwner(budget)
    rows:=(0..<2000).map |i->Str:Obj?| {["index":i,"value":i.toFloat]}
    source:=Str:Obj?["rows":rows];expected:=source.toImmutable
    // Root, row vector, 2000 distinct three-entry maps and cleanup/control.
    producer.hold(32+2+2001+6000);producer.watch |->Void| {EnerCubixReportConsumer.clearPublic(source,Obj[,],Obj[,])}
    try
    {
      scope.prepareReportBorrows(Obj[,],Obj[,]);peer.hold(budget.remaining-11000);held:=peer.entries
      frozen:=scope.freezeOwnedReport("daily",source,producer)
      verify(frozen.isImmutable);verifyEq(frozen,expected);verifyEq(((List)frozen["rows"]).size,2000)
      verify(source.isEmpty);verify(rows.isEmpty);verifyEq(peer.entries,held)
      verify(budget.peak.val<=200000);echo("OWNED_WIDE rows=2000 peak="+budget.peak.val+" producerRemaining="+producer.entries);producer.close
      snapshot:=scope.freezeSnapshot(["report":frozen]);verifyEq(snapshot["report"],expected)
      scope.close;verifyEq(budget.temporary.val,held)
    }
    finally {producer.close;scope.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testOwnedReportTransferFailurePublishesNothingAndPreservesPeerAndBorrowedInputs()
  {
    scope:=EnerCubixCockpitRequestScope("transfer-failure","a");budget:=scope.stream.state
    producer:=EnerCubixPreparedOwner(budget);peer:=EnerCubixPreparedOwner(budget);peer.hold(31);held:=peer.entries
    borrowed:=Str:Obj?["rows":[["value":0f]]];expected:=borrowed.toImmutable
    source:=Str:Obj?[:];source.ordered=true;first:=Str:Obj?["data":[1,2,3]]
    source["first"]=first;source["borrowed"]=borrowed;source["invalid"]=StrBuf().add("opaque")
    producer.hold(128);producer.watch |->Void| {source.clear}
    try
    {
      scope.prepareReportBorrows([borrowed],Obj[,])
      verifyErr(NotImmutableErr#) {scope.freezeOwnedReport("failed",source,producer)}
      verify(first.isEmpty,"The fixture fails after consuming one owned child")
      verifyNull(scope.frozenReport("failed"));verify(!scope.responseStarted);verifyEq(borrowed,expected)
      verifyEq(peer.entries,held);producer.close;scope.close;verifyEq(budget.temporary.val,held)
    }
    finally {producer.close;scope.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testOwnedEarlyCycleRejectsAfterRetiringParentsWithoutReleasingPeer()
  {
    scope:=EnerCubixCockpitRequestScope("early-cycle","a");budget:=scope.stream.state
    producer:=EnerCubixPreparedOwner(budget);peer:=EnerCubixPreparedOwner(budget);peer.hold(31);held:=peer.entries
    cycle:=Str:Obj?[:];cycle["self"]=cycle;source:=Str:Obj?["cycle":cycle]
    producer.hold(64);producer.watch |->Void| {source.clear;cycle.clear}
    try
    {
      scope.prepareReportBorrows(Obj[,],Obj[,])
      verifyErr(NotImmutableErr#) {scope.freezeOwnedReport("cyclic",source,producer)}
      verify(source.isEmpty);verify(cycle.isEmpty);verifyNull(scope.frozenReport("cyclic"))
      verifyEq(peer.entries,held);verify(!scope.responseStarted)
      producer.close;scope.close;verifyEq(budget.temporary.val,held)
    }
    finally {producer.close;scope.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }

  Void testOwnedEarlyTransferKeepsReadOnlyBorrowedViewsAndTheirDescendants()
  {
    scope:=EnerCubixCockpitRequestScope("early-readonly","a");producer:=EnerCubixPreparedOwner(scope.stream.state)
    child:=Str:Obj?["values":[0f,null,3f]];catalog:=Str:Obj?["nested":[child]].ro
    expectedCatalog:=catalog.toImmutable;source:=Str:Obj?[:];source.ordered=true
    ids:=[1,2,3];equal:=child.dup
    source["catalog"]=catalog;source["direct"]=child;source["alias"]=child
    source["collisions"]=Str:Obj?["Aa":child,"BB":equal,"AaAa":ids,"BBBB":ids]
    expected:=source.toImmutable
    producer.hold(128);producer.watch |->Void| {source.clear}
    try
    {
      scope.prepareReportBorrows([catalog],Obj[,]);frozen:=scope.freezeOwnedReport("readonly",source,producer)
      verify(frozen.ordered);verifyEq(frozen,expected);verify(frozen["direct"]===frozen["alias"])
      verify(((List)((Map)frozen["catalog"])["nested"]).first===frozen["direct"])
      verifyEq(catalog,expectedCatalog);verifyEq(child["values"],[0f,null,3f])
      collision:=(Map)frozen["collisions"]
      verify(collision["Aa"]!==collision["BB"]);verify(collision["AaAa"]===collision["BBBB"])
      verifyEq(collision["AaAa"].typeof,ids.typeof);verifyEq(collision["AaAa"],[1,2,3])
      verifyEq(JsonOutStream.writeJsonToStr(frozen),JsonOutStream.writeJsonToStr(expected))
      producer.close;scope.releaseReportBorrows;verifyEq(frozen,expected);scope.close
    }
    finally {producer.close;scope.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testOwnedReportTransferRejectsUnpreparedCrossRequestAndClosedProducers()
  {
    scope:=EnerCubixCockpitRequestScope("transfer-context","a");budget:=scope.stream.state
    producer:=EnerCubixPreparedOwner(budget);foreign:=EnerCubixPreparedOwner(EnerCubixStreamBudget().state)
    source:=Str:Obj?["value":1];producer.hold(16)
    try
    {
      verifyErr(ArgErr#) {scope.freezeOwnedReport("not-ready",source,producer)}
      scope.prepareReportBorrows(Obj[,],Obj[,]);verifyErr(ArgErr#) {scope.prepareReportBorrows(Obj[,],Obj[,])}
      verifyErr(ArgErr#) {scope.freezeOwnedReport("foreign",source,foreign)}
      producer.close;verifyErr(ArgErr#) {scope.freezeOwnedReport("closed",source,producer)}
      verifyEq(source,Str:Obj?["value":1]);verifyNull(scope.frozenReport("foreign"));verifyNull(scope.frozenReport("closed"))
    }
    finally {producer.close;foreign.close;scope.close}
    verifyEq(budget.temporary.val,0);verifyEq(foreign.budget.temporary.val,0)
  }

  Void testExactInputModelFactsShareOneFrozenCopyWithinTheOriginalBudget()
  {
    rs:=[Str:Obj?][,];500.times |i| {r:=Str:Obj?["id":"r$i","kind":"meter"];18.times |j| {r["field$j"]="value$j"};rs.add(r)}
    model:=rs.map |r->Str:Obj?| {r.dup};scope:=EnerCubixCockpitRequestScope("input-facts","a");peer:=EnerCubixPreparedOwner(scope.stream.state);peer.hold(177000)
    try
    {
      frozen:=scope.freezeInputs([:],["modelRecords":model],rs);rows:=(List)frozen["records"];models:=(List)((Map)frozen["owned"])["modelRecords"]
      verifyEq(rows.typeof,rs.typeof);verifyEq(models.typeof,model.typeof);verify(rows!==models)
      500.times |i| {verify(rows[i]===models[i])}
      verifyEq(rs.size,500);verifyEq(model.size,500);verifyEq(budgetValue(scope),scope.entries+peer.entries)
      scope.close;verifyEq(budgetValue(scope),peer.entries)
    }
    finally {scope.close;peer.close}
  }
  private Int budgetValue(EnerCubixCockpitRequestScope scope) {scope.stream.state.temporary.val}
  Void testInputFactsWithDifferentFieldsOrContainerOrderingStaySeparate()
  {
    record:=Str:Obj?["id":"m","kind":"meter","name":"original"]
    changed:=record.dup.set("name","changed");ordered:=Str:Obj?[:];ordered.ordered=true;ordered.setAll(record)
    scope:=EnerCubixCockpitRequestScope("different-input-facts","a")
    try
    {
      frozen:=scope.freezeInputs([:],["modelRecords":[changed,ordered]],[record]);row:=((List)frozen["records"]).first;models:=(List)((Map)frozen["owned"])["modelRecords"]
      verify(row!==models.first);verify(row!==models.last);verifyEq(((Map)models.first)["name"],"changed");verify(((Map)models.last).ordered)
    }
    finally {scope.close}
  }
  Void testPreparationLivesUntilTheCompositeInputIsFrozen()
  {
    scope:=EnerCubixCockpitRequestScope("preparation","a");peer:=EnerCubixPreparedOwner(scope.stream.state);peer.hold(31)
    work:=scope.preparationWorkspace;rows:=[Str:Obj?][["id":"m","name":"原表名"]]
    work.hold(5);work.watch |->Void| {rows.clear}
    try
    {
      frozen:=scope.freezeInputs(["key":"value"],["modelRecords":rows],rows)
      verify(rows.isEmpty);verifyEq(work.entries,0)
      verifyEq(((Map)((List)frozen["records"]).first)["name"],"原表名")
      verify(((Map)frozen["owned"])["modelRecords"]===frozen["records"])
      verifyEq(scope.stream.state.temporary.val,scope.entries+peer.entries)
      scope.close;verifyEq(scope.stream.state.temporary.val,peer.entries)
    }
    finally {scope.close;peer.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testPreparationFailureDoesNotDropAnotherOwnersCharge()
  {
    scope:=EnerCubixCockpitRequestScope("preparation-limit","a");work:=scope.preparationWorkspace;peer:=EnerCubixPreparedOwner(scope.stream.state)
    peer.hold(scope.stream.state.remaining-3);held:=peer.entries
    try {verifyErr(EnerCubixHttpErr#) {work.hold(4)};scope.close;verifyEq(scope.stream.state.temporary.val,held)}
    finally {scope.close;peer.close}
  }
  Void testSourcePlanReusesOnlyExactFrozenInputFacts()
  {
    scope:=EnerCubixCockpitRequestScope("source-plan-facts","a");baseline:=EnerCubixPreparedOwner(scope.stream.state)
    record:=Str:Obj?["id":"meter","kind":"meter","name":"原始表名","pointId":"point"]
    plainA:=Str:Obj?["value":1];plainB:=Str:Obj?["value":1]
    source:=Str:Obj?["same":[record.dup,record.dup],"changed":record.dup.set("name","modified"),"plain":[plainA,plainB]]
    before:=JsonOutStream.writeJsonToStr(source)
    try
    {
      expected:=EnerCubixCockpitFreeze.value(source,baseline)
      bundle:=scope.freezeInputs(["schemaVersion":1],[:],[record]);fact:=((List)bundle["records"]).first
      frozen:=scope.freezeSourcePlan(source)
      verify(((List)frozen["same"]).all |row| {row===fact})
      verify(frozen["changed"]!==fact);verifyEq(((Map)frozen["changed"])["name"],"modified")
      verify(((List)frozen["plain"]).first!==((List)frozen["plain"]).last)
      // Unordered Map copies may use a different bucket iteration order. The
      // existing freeze, rather than the mutable input's JSON, is the baseline.
      verifyEq(JsonOutStream.writeJsonToStr(frozen),JsonOutStream.writeJsonToStr(expected))
      verifyEq(JsonOutStream.writeJsonToStr(source),before);baseline.close
      record["name"]="later edit";plainA["value"]=99
      verifyEq(((Map)((List)frozen["same"]).first)["name"],"原始表名")
      verifyEq(((Map)((List)frozen["plain"]).first)["value"],1)
      verifyErr(ArgErr#) {scope.freezeSourcePlan(source)}
      verifyEq(scope.stream.state.temporary.val,scope.entries)
    }
    finally {scope.close;baseline.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testHistoryProofSurvivesMetadataWorkspaceAndRawHeaderCleanup()
  {
    scope:=EnerCubixCockpitRequestScope("history-proof","a");peer:=EnerCubixPreparedOwner(scope.stream.state);peer.hold(31)
    stats:=Str:Obj?["nativeReadCount":2]
    raw:=Str:Obj?["pointId":"p","configRefs":[["id":"profile","mod":"2026-10-01T00:00:00Z"]],"cleaning":["profileId":"profile","profileVersion":1,"parameters":["deltaMin":0f]],"streaming":stats,"sourceLastObservedAt":"2026-10-01T01:00:00Z"]
    try
    {
      headers:=scope.freezeHistoryHeaders([raw,["pointId":"other","streaming":stats]])
      verify(headers.first["streaming"]===headers.last["streaming"])
      work:=scope.metadataWorkspace(1)
      meta:=EnerCubixCockpitHistoryMeta(["p"],DateTime.fromIso("2026-10-01T02:00:00Z"),work,scope.historyOutput)
      headers.each |header| {meta.observe(header)}
      proof:=meta.snapshot;scope.finishMetadata
      verifyEq(work.entries,0);verifyErr(ArgErr#) {meta.observe(headers.first)}
      ((Map)((Map)raw["cleaning"])["parameters"])["deltaMin"]=99f;stats["nativeReadCount"]=999;raw.clear
      verifyEq(((Map)((List)proof["streaming"]).first)["nativeReadCount"],2)
      verifyEq(((Map)((Map)((List)proof["appliedCleaning"]).first)["parameters"])["deltaMin"],0f)
      verifyEq(((Map)((List)proof["configRefs"]).first)["id"],"profile")
      verifyEq(proof["sourceLastObservedAt"],"2026-10-01T01:00:00Z")
      verifyEq(scope.stream.state.temporary.val,scope.entries+peer.entries)
      scope.deliver(proof,|Buf bytes| {verify(bytes.size>0)})
      scope.close;verifyEq(scope.stream.state.temporary.val,peer.entries)
    }
    finally {scope.close;peer.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testThinHeaderCopyCannotBePublishedBeforeItsAdmission()
  {
    scope:=EnerCubixCockpitRequestScope("history-header-limit","a");peer:=EnerCubixPreparedOwner(scope.stream.state)
    peer.hold(scope.stream.state.remaining-24);held:=peer.entries
    headers:=[Str:Obj?][["pointId":"p","configRefs":[["id":"profile","mod":"version"]]]]
    try
    {
      verifyErr(EnerCubixHttpErr#) {scope.freezeHistoryHeaders(headers)}
      verifyEq(headers.first["pointId"],"p");verify(!scope.responseStarted)
      scope.close;verifyEq(scope.stream.state.temporary.val,held)
    }
    finally {scope.close;peer.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testPlanningCatalogCanReleaseItsOwnersWithoutClearingInputRecords()
  {
    scope:=EnerCubixCockpitRequestScope("planning-scope","a");peer:=EnerCubixPreparedOwner(scope.stream.state);peer.hold(31)
    records:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space"],["id":"m","kind":"meter","pointId":"p","categoryId":"c","spaceId":"s"]].toImmutable
    try
    {
      context:=scope.planningContext(records,TimeZone.utc,"space",false)
      verifyErr(ArgErr#) {scope.sourceCatalog(records.dup.toImmutable,TimeZone.utc,[:])}
      catalog:=scope.sourceCatalog(records,TimeZone.utc,["p":"kWh"])
      verifyEq(catalog.primaryUnit("p"),"kWh")
      verifyErr(ArgErr#) {scope.sourceCatalog(records,TimeZone.utc,["p":"Wh"])}
      verifyEq(context.scopeMeters("s","c").first["id"],"m")
      verifyEq(scope.stream.state.temporary.val,scope.entries+peer.entries)
      scope.finishPlanning;scope.finishPlanning
      verifyEq(((Map)records.last)["pointId"],"p");verifyEq(scope.stream.state.temporary.val,scope.entries+peer.entries)
      verifyErr(ArgErr#) {scope.planningContext(records,TimeZone.utc,"space",false)}
      scope.close;verifyEq(scope.stream.state.temporary.val,peer.entries)
    }
    finally {scope.close;peer.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testPlanningCatalogAdmissionFailureDoesNotReleasePeerOrTheGate()
  {
    scope:=EnerCubixCockpitRequestScope("planning-limit","a");peer:=EnerCubixPreparedOwner(scope.stream.state)
    records:=[Str:Obj?][,];(0..<300).each |i| {records.add(["id":"m$i","kind":"meter"])};records=records.toImmutable
    peer.hold(scope.stream.state.remaining-100);held:=peer.entries
    try
    {
      verifyErr(EnerCubixHttpErr#) {scope.planningContext(records,TimeZone.utc,"metering",false)}
      verifyEq(peer.entries,held);verifyEq(scope.stream.nativeReads,0)
      verifyErr(EnerCubixHttpErr#) {EnerCubixCockpitGate.enter("planning-limit","a")}
      scope.close;verifyEq(scope.stream.state.temporary.val,held)
    }
    finally {scope.close;peer.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testFinalSnapshotBorrowsFrozenInputsAndKeepsItsCopyOwnedThroughTheSender()
  {
    scope:=EnerCubixCockpitRequestScope("request-snapshot","a");Map? frozen
    try
    {
      inputs:=scope.freezeInputs(["schemaVersion":1],[:],[["id":"m","kind":"meter"]])
      inputRecord:=(Map)((List)inputs["records"]).first;shared:=Str:Obj?["value":12.5f,"source":inputRecord]
      frozen=scope.freezeSnapshot(["schemaVersion":1,"left":shared,"right":shared])
      verify(frozen.isImmutable);verify(frozen["left"]===frozen["right"]);verify(((Map)frozen["left"])["source"]===inputRecord)
      shared["value"]=999f;verifyEq(((Map)frozen["left"])["value"],12.5f)
      scope.deliver((Str:Obj?)frozen,|Buf bytes| {verify(scope.stream.state.temporary.val>scope.entries)})
      verifyEq(scope.stream.state.temporary.val,scope.entries)
    }
    finally {frozen=null;scope.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testInputBundleSharesFrozenModelRecordsAndKeepsTheirOwnerThroughSending()
  {
    record:=Str:Obj?["id":"m","name":"Original 中文","kind":"meter"]
    records:=[record];owned:=Str:Obj?["modelRecords":records,"modelComplete":true]
    scope:=EnerCubixCockpitRequestScope("request-inputs","a");Map? inputs
    try
    {
      inputs=scope.freezeInputs(["schemaVersion":1],owned,records)
      verify(inputs.isImmutable);model:=(List)((Map)inputs["owned"])["modelRecords"]
      verify(model===inputs["records"]);verify(model.first===((List)inputs["records"]).first)
      record["name"]="later edit";verifyEq(((Map)model.first)["name"],"Original 中文")
      scope.deliver(["schemaVersion":1],|Buf bytes| {verify(scope.stream.state.temporary.val>scope.entries);verify(inputs.isImmutable)})
      verifyEq(scope.stream.state.temporary.val,scope.entries)
    }
    finally {inputs=null;scope.close}
    verifyEq(scope.stream.state.temporary.val,0);verify(!records.isImmutable)
  }
  Void testGateRemainsHeldThroughWireSendingAndAnOldCloseCannotReleaseANewRequest()
  {
    project:="request-scope-success";user:="a";scope:=EnerCubixCockpitRequestScope(project,user);calls:=0
    try
    {
      scope.deliver(["schemaVersion":1,"name":"中文 EN 😀"],|Buf bytes|
      {
        calls++;verify(scope.responseStarted);verify(!scope.canSendError)
        verifyErr(ArgErr#) {scope.close}
        verifyErr(EnerCubixHttpErr#) {unexpected:=EnerCubixCockpitRequestScope(project,user);unexpected.close}
        verifyErr(EnerCubixHttpErr#) {EnerCubixCockpitGate.enter(project,user)}
        parsed:=(Map)JsonInStream(bytes.in).readJson
        verifyEq(parsed["ok"],true);verifyEq(((Map)parsed["data"])["name"],"中文 EN 😀")
      })
      verifyEq(calls,1);verifyEq(scope.stream.state.temporary.val,scope.entries)
    }
    finally {scope.close}
    verifyEq(scope.stream.state.temporary.val,0)
    next:=EnerCubixCockpitRequestScope(project,user)
    try {scope.close;verifyErr(EnerCubixHttpErr#) {EnerCubixCockpitGate.enter(project,user)}}
    finally {next.close}
    EnerCubixCockpitGate.enter(project,user);EnerCubixCockpitGate.leave(project,user)
  }
  Void testSerializationFailureAllowsAnErrorButSendingFailureNeverAllowsASecondResponse()
  {
    project:="request-scope-failure";scope:=EnerCubixCockpitRequestScope(project,"a");calls:=0
    try
    {
      payloadBytes:=8388608
      try {scope.deliver(["text":"x".padl(payloadBytes,'x')],|Buf bytes| {calls++});fail("Expected complete-envelope limit")}
      catch(EnerCubixHttpErr e) {verifyEq(e.status,413)}
      verify(!scope.responseStarted);verify(scope.canSendError);verifyEq(calls,0)
      verifyErr(EnerCubixHttpErr#) {EnerCubixCockpitGate.enter(project,"a")}
    }
    finally {scope.close}
    scope=EnerCubixCockpitRequestScope(project,"a");original:=IOErr("controlled socket write failure");Err? observed
    try
    {
      try {scope.deliver(["value":12.5f],|Buf bytes| {calls++;throw original})}
      catch(Err e) {observed=e}
      verify(observed===original);verifyEq(calls,1);verify(scope.responseStarted);verify(!scope.canSendError)
      verifyErr(ArgErr#) {scope.deliver(["value":99f],|Buf bytes| {calls++})}
      verifyEq(calls,1)
    }
    finally {scope.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testRejectedScopeDoesNotReleaseAnotherRequestOrItsBudget()
  {
    project:="request-scope-admission";scope:=EnerCubixCockpitRequestScope(project,"a")
    stream:=EnerCubixStreamBudget();peer:=EnerCubixPreparedOwner(stream.state);peer.hold(stream.state.remaining);held:=peer.entries
    try
    {
      verifyErr(EnerCubixHttpErr#) {unexpected:=EnerCubixCockpitRequestScope(project,"a",stream);unexpected.close}
      verifyErr(EnerCubixHttpErr#) {EnerCubixCockpitGate.enter(project,"a")}
      verifyErr(EnerCubixHttpErr#) {unexpected:=EnerCubixCockpitRequestScope(project,"b",stream);unexpected.close}
      verifyEq(peer.entries,held);verifyEq(stream.state.temporary.val,held)
      // Failed b construction entered and then rolled back only b's gate slot.
      EnerCubixCockpitGate.enter(project,"b");EnerCubixCockpitGate.leave(project,"b")
    }
    finally {peer.close;scope.close}
    verifyEq(stream.state.temporary.val,0)
  }
}

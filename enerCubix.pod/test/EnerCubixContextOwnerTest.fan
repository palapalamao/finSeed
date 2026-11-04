using haystack

** Actual private producer frames; no FIN data or project mutation.
class EnerCubixContextOwnerTest : Test
{
  Void testFrameAdmissionIncludesCopiedKnownHeaderFields()
  {
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"]];ids:=Str[,]
    for(i:=0;i<18;i++) {ids.add("m$i");rs.add(["id":"m$i","kind":"meter","pointId":"p$i","categoryId":"c"])}
    q:=Str:Obj?["kind":"profile","nodeIds":ids,"from":at.toIso,"to":(at+1hr).toIso,"asOf":(at+1hr).toIso,"tz":"UTC","period":"hour","metric":"energy"]
    budget:=EnerCubixStreamBudget();state:=EnerCubixPreparedOwner(budget.state)
    ctx:=EnerCubixContext(rs,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(state);known:=EnerCubixContext.known(ctx,at+1hr)
    streams:=EnerCubixCockpitStream[,]
    read:=|Dict p,Span span,|HisItem| sink| {(0..1).each |i| {ts:=at+Duration(i*1hr.ticks);if(ts>=span.start && ts<span.end) sink(HisItem(ts,Number(1)))}}
    for(i:=0;i<18;i++)
    {
      p:=Etc.makeDict(["id":Ref("p$i"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])
      stream:=EnerCubixCockpitStream.openCursor(p,null,at,at+1hr,q,rs,budget,read,ctx);stream.advance(at+1hr);streams.add(stream)
    }
    try
    {
      EnerCubixCockpitStream.withFrames(streams,budget.state) |histories,frame|
      {
        ctx.beginFrame(frame,histories);known.beginFrame(frame,histories)
        ids.each |id| {known.node(id,"c",at,at+1hr)}
        verifyEq(known.knownReads.size,18)
        verifyErr(ArgErr#) {known.knownEvidence}
        headers:=known.knownReads.vals.reduce(1+known.knownReads.size) |Int n,row->Int| {n+1+row.size}
        verify(frame.entries>=headers,"copied header map fields must be admitted")
        first:=frame.entries
        // Replacing equal-sized headers uses one reusable scratch allocation,
        // not an ever-growing charge for every duplicate source visit.
        ids.each |id| {known.node(id,"c",at,at+1hr)}
        verifyEq(frame.entries,first)
      }
    }
    finally {streams.each |stream| {stream.close};state.close}
    verifyEq(budget.state.temporary.val,0)
  }

  Void testKnownAndStrictRootsClearBeforeTheirOwnerReleases()
  {
    budget:=EnerCubixStreamBudget();peer:=EnerCubixPreparedOwner(budget.state);peer.hold(13)
    persistent:=EnerCubixPreparedOwner(budget.state);ctx:=EnerCubixContext(records,[Str:Obj?][,],TimeZone.utc)
    ctx.useOwner(persistent);known:=EnerCubixContext.known(ctx,at+4hr)
    cursor:=source(budget,[HisItem(at,Number(0)),HisItem(at+1hr,Number(10)),HisItem(at+2hr,Number(20))])
    cursor.advance(at+1hr)
    cursor.withFrame |h|
    {
      before:=budget.state.temporary.val;frame:=EnerCubixPreparedOwner(budget.state)
      verifyErr(ArgErr#) {ctx.beginFrame(frame,["wrong":h])}
      ctx.beginFrame(frame,["p":h]);known.beginFrame(frame,["p":h])
      strictValue:=ctx.node("m","c",at,at+1hr);knownValue:=known.node("m","c",at,at+1hr)
      verifyEq(strictValue.value,10f);verifyEq(knownValue.value,10f);verify(!known.knownReads.isEmpty)
      verify(ctx.node("m","c",at,at+1hr)===strictValue)
      verify(known.node("m","c",at,at+1hr)===knownValue)
      // Recursive scope visits reuse this device's own result in this frame.
      verify(ctx.node("m","c",at,at+1hr,"energy",["group"])===strictValue)
      bound:=EnerCubixContext.bound(ctx,"m",ctx.byId["m"].dup.set("maximum",5f))
      verifyEq(bound.node("m","c",at,at+1hr).quality,"maximum")
      observedBound:=EnerCubixContext.known(bound,at+4hr)
      verifyEq(observedBound.node("m","c",at,at+1hr).quality,"maximum")
      verifyErr(ArgErr#) {persistent.close}
      frame.close
      verify(ctx.byPoint.isEmpty);verify(known.byPoint.isEmpty);verify(known.knownReads.isEmpty)
      verifyEq(budget.state.temporary.val,before)
      verifyErr(ArgErr#) {ctx.node("m","c",at,at+1hr)}
      verifyErr(ArgErr#) {known.knownEvidence}
      verifyErr(ArgErr#) {bound.node("m","c",at,at+1hr)}
      verifyErr(ArgErr#) {observedBound.node("m","c",at,at+1hr)}
      verifyEq(ctx.unit("m","c","energy"),"kWh")
    }
    cursor.close;persistent.close;verifyEq(budget.state.temporary.val,peer.entries)
    peer.close;verifyEq(budget.state.temporary.val,0)
  }

  Void testSourceDomainCacheDoesNotSurviveFrameBoundary()
  {
    budget:=EnerCubixStreamBudget();persistent:=EnerCubixPreparedOwner(budget.state)
    ctx:=EnerCubixContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(persistent)
    cursor:=source(budget,[HisItem(at+1hr,Number(0)),HisItem(at+3hr,Number(10))])
    qualities:=Str[,]
    for(i:=1;i<=3;i++)
    {
      end:=at+Duration(i*1hr.ticks);cursor.advance(end)
      cursor.withFrame |h|
      {
        frame:=EnerCubixPreparedOwner(budget.state);ctx.beginFrame(frame,["p":h])
        qualities.add(ctx.node("m","c",end-1hr,end).quality)
        frame.close
      }
    }
    verifyEq(qualities,["missing","incompleteInterval","incompleteInterval"])
    cursor.close;persistent.close;verifyEq(budget.state.temporary.val,0)
  }

  Void testForeignOwnerAndUnleasedHistoryCannotEnterFrame()
  {
    budget:=EnerCubixStreamBudget();persistent:=EnerCubixPreparedOwner(budget.state)
    ctx:=EnerCubixContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(persistent)
    verifyErr(ArgErr#) {ctx.beginFrame(persistent,Str:EnerCubixHistoryData[:])}
    foreign:=EnerCubixPreparedOwner(EnerCubixPreparedBudget(EnerCubixCockpitDeadline()))
    verifyErr(ArgErr#) {ctx.beginFrame(foreign,Str:EnerCubixHistoryData[:])}
    foreign.close
    frame:=EnerCubixPreparedOwner(budget.state)
    raw:=EnerCubixHistoryData(["pointId":"p","mode":"interval","unit":"kWh","samples":[["ts":at.toIso,"value":10f]]])
    verifyErr(ArgErr#) {ctx.beginFrame(frame,["p":raw])}
    frame.close;persistent.close;verifyEq(budget.state.temporary.val,0)
  }

  Void testFailedMetadataAdmissionStillDropsRegisteredRoots()
  {
    budget:=EnerCubixStreamBudget();budget.state.hold(199993)
    persistent:=EnerCubixPreparedOwner(budget.state)
    ctx:=EnerCubixContext(records,[Str:Obj?][,],TimeZone.utc)
    verifyErr(EnerCubixHttpErr#) {ctx.useOwner(persistent)}
    persistent.close
    verify(ctx.byId.isEmpty);verify(ctx.children.isEmpty)
    verifyEq(budget.state.temporary.val,199993)
    budget.state.releaseTemporary(199993)
  }

  Void testWarningsFollowOriginalLineAndPhaseOrderAcrossInterleavedHours()
  {
    budget:=EnerCubixStreamBudget();owner:=EnerCubixPreparedOwner(budget.state)
    ctx:=EnerCubixContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    ctx.warn("preamble");ctx.orderWarnings
    ctx.warningScope(0,1,at.ticks);ctx.warn("second line")
    ctx.warningScope(3,0,at.ticks);ctx.warn("details")
    ctx.warningScope(0,0,(at+12hr).ticks);ctx.warn("first line later")
    ctx.warningScope(0,0,at.ticks);ctx.warn("first line earlier");ctx.warn("same hour next")
    ctx.warningScope(1,0,at.ticks);ctx.warn("selection")
    verifyEq(ctx.orderedWarnings,["preamble","first line earlier","same hour next","first line later","second line","selection","details"])
    retained:=owner.entries
    // Repeated later visits cannot replace the first logical occurrence.
    ctx.warningScope(4,0,at.ticks);ctx.warn("first line earlier")
    verifyEq(owner.entries,retained)
    // An earlier logical visit to the same message updates its rank in place.
    ctx.warningScope(0,0,at.ticks-1);ctx.warn("first line later")
    verifyEq(owner.entries,retained)
    verifyEq(ctx.orderedWarnings,["preamble","first line later","first line earlier","same hour next","second line","selection","details"])
    owner.close;verify(ctx.warnings.isEmpty);verifyEq(budget.state.temporary.val,0)
    verifyErr(ArgErr#) {ctx.warningScope(0,0,at.ticks)}
  }

  Void testOwnedWarningMembershipIsAdmittedBeforePublishing()
  {
    budget:=EnerCubixStreamBudget();owner:=EnerCubixPreparedOwner(budget.state)
    ctx:=EnerCubixContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    known:=EnerCubixContext.known(ctx,at+1hr)
    peer:=EnerCubixPreparedOwner(budget.state);peer.hold(budget.state.remaining-1)
    verifyErr(EnerCubixHttpErr#) {known.warn("主表 : missing")}
    verify(known.warnings.isEmpty,"failed admission must not publish a partial warning")
    owner.close;verify(known.warnings.isEmpty)
    verifyEq(budget.state.temporary.val,peer.entries)
    peer.close;verifyEq(budget.state.temporary.val,0)
  }

  Void testOwnedKnownWarningsKeepFirstOccurrenceAndRetireWithOwner()
  {
    budget:=EnerCubixStreamBudget();owner:=EnerCubixPreparedOwner(budget.state)
    ctx:=EnerCubixContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    known:=EnerCubixContext.known(ctx,at+1hr)
    expected:=Str[,]
    for(i:=0;i<256;i++) {message:="Meter $i : missing";expected.add(message);known.warn(message)}
    retained:=owner.entries
    for(hour:=0;hour<24;hour++) for(i:=255;i>=0;i--) known.warn(expected[i])
    verifyEq(known.warnings,expected);verifyEq(owner.entries,retained)
    owner.close;verify(known.warnings.isEmpty);verifyEq(budget.state.temporary.val,0)
  }

  Void testOwnFrameMemoReusesSlotsAcrossHourAndMetricChanges()
  {
    rs:=records;rs[1]["subcategoryId"]="s";rs.add(["id":"s","kind":"subcategory","coalFactor":2f])
    budget:=EnerCubixStreamBudget();owner:=EnerCubixPreparedOwner(budget.state)
    ctx:=EnerCubixContext(rs,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    q:=Str:Obj?["from":at.toIso,"to":(at+24hr).toIso,"asOf":(at+24hr).toIso,"tz":"UTC"]
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])
    stream:=EnerCubixCockpitStream.openCursor(point,null,at,at+24hr,q,rs,budget,|Dict p,Span span,|HisItem| sink|
    // Native consumption readings are end stamped; include the left context.
    // 01:00 carries hour 00's 1, while the 00:00 row belongs before the range.
    {(0..24).each |i| {ts:=at+Duration(i*1hr.ticks);if(ts>=span.start && ts<span.end) sink(HisItem(ts,Number(i)))}})
    try
    {
      stream.advance(at+24hr)
      EnerCubixCockpitStream.withFrames([stream],budget.state) |histories,frame|
      {
        ctx.beginFrame(frame,histories)
        firstEntries:=0
        for(i:=0;i<24;i++)
        {
          start:=at+Duration(i*1hr.ticks);end:=start+1hr
          value:=ctx.node("m","c",start,end);verifyEq(value.value,(i+1).toFloat)
          verify(ctx.node("m","c",start,end,"energy",["scope"])===value)
          verifyEq(ctx.node("m","c",start,end,"coal").value,2f*(i+1).toFloat)
          if(i==0) firstEntries=frame.entries
          else verifyEq(frame.entries,firstEntries,"completed hour/metric results must not accumulate in the frame memo")
        }
      }
    }
    finally {stream.close;owner.close}
    verifyEq(budget.state.temporary.val,0)
  }

  Void testBorrowedEmptyKnownViewIsReadOnlyInContextAndLeaseBound()
  {
    budget:=EnerCubixStreamBudget();owner:=EnerCubixPreparedOwner(budget.state)
    ctx:=EnerCubixContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    known:=EnerCubixContext.known(ctx,at+4hr);cursor:=source(budget,HisItem[,])
    EnerCubixHistoryData? expired
    try
    {
      cursor.advance(at+4hr)
      EnerCubixCockpitStream.withFrames([cursor],budget.state) |histories,frame|
      {
        h:=histories["p"];expired=h;ctx.beginFrame(frame,histories);known.beginFrame(frame,histories)
        borrowed:=(Str:Obj?)h->borrowedKnownUsage(at,at+1hr,at+4hr)
        verify(h->borrowedKnownUsage(at,at+1hr,at+4hr)===borrowed)
        ordinary:=h.knownUsage(at,at+1hr,at+4hr)
        verify(ordinary!==borrowed);ordinary["knownQuality"]="caller edit"
        verifyEq(borrowed["knownQuality"],"missing");verifyEq(borrowed["coveredSeconds"],0f)
        verifyEq(borrowed["intervalCount"],0);verifyEq(((EnerCubixValue)borrowed["value"]).value,null)
        before:=borrowed.dup
        verifyEq(known.node("m","c",at,at+1hr).quality,"missing")
        verify(known.knownReads.isEmpty);verify(known.emptyEvidenceOmitted)
        verifyEq(borrowed,before,"context must not mutate the borrowed source view")
      }
      verifyErr(ArgErr#) {expired->borrowedKnownUsage(at,at+1hr,at+4hr)}
    }
    finally {cursor.close;owner.close}
    verifyEq(budget.state.temporary.val,0)
  }

  Void testCanonicalStrictNumbersSurviveConsumerCloseWithoutSkippingKnownEvidence()
  {
    rs:=records;rs[1]["subcategoryId"]="sub";rs[1]["tariffId"]="t";rs.add(["id":"sub","kind":"subcategory","co2Factor":0.5f]);rs.add(["id":"t","kind":"tariff","mode":"flat","rate":2f,"currency":"CNY"])
    budget:=EnerCubixStreamBudget();model:=EnerCubixPreparedOwner(budget.state);catalog:=EnerCubixCockpitCatalog(rs.toImmutable,TimeZone.utc,model)
    first:=EnerCubixPreparedOwner(budget.state);second:=EnerCubixPreparedOwner(budget.state)
    a:=EnerCubixContext.shared(catalog,"space",false,first);b:=EnerCubixContext.shared(catalog,"metering",false,second)
    cursor:=source(budget,[HisItem(at,Number(0)),HisItem(at+1hr,Number(10)),HisItem(at+2hr,Number(30))]);EnerCubixValue? original;EnerCubixHistoryData? expired
    try
    {
      cursor.advance(at+1hr)
      EnerCubixCockpitStream.withFrames([cursor],budget.state) |histories,sourceOwner|
      {
        expired=histories["p"];fa:=EnerCubixPreparedOwner(budget.state);fb:=EnerCubixPreparedOwner(budget.state)
        try
        {
          a.beginFrame(fa,histories);original=a.node("m","c",at,at+1hr);carbon:=a.node("m","c",at,at+1hr,"co2")
          verifyEq(original.value,10f);verifyEq(carbon.value,5f)
          verifyEq(a.node("m","c",at,at+1hr,"cost").value,20f);verify(a.usedTariffs.containsKey("m"))
          fa.close;first.close
          b.beginFrame(fb,histories);before:=budget.state.lookups.val
          shared:=b.node("m","c",at,at+1hr);verify(shared===original,"canonical views borrow the same admitted strict result after its first consumer closes")
          verifyEq(budget.state.lookups.val,before,"the same physical strict result is not fetched again")
          verify(b.node("m","c",at,at+1hr,"co2")===carbon)
          bound:=EnerCubixContext.bound(b,"m",b.byId["m"].dup.set("maximum",5f));verifyEq(bound.node("m","c",at,at+1hr).quality,"maximum")
          verifyEq(b.node("m","c",at,at+1hr).value,10f)
          known:=EnerCubixContext.known(b,at+4hr);verifyEq(known.node("m","c",at,at+1hr).value,10f)
          verifyEq(known.knownReads.size,1);verify(!known.emptyEvidenceOmitted);verify(!known.unpreparedEvidenceOmitted)
          verifyEq(b.node("m","c",at,at+1hr,"cost").value,20f);verify(b.usedTariffs.containsKey("m"))
        }
        finally {fa.close;fb.close}
      }
      verifyErr(ArgErr#) {expired.ownStrict(catalog.byId["m"],"c",at,at+1hr,"energy")}
      cursor.close
      next:=source(budget,[HisItem(at,Number(0)),HisItem(at+1hr,Number(99))])
      try
      {
        next.advance(at+1hr)
        EnerCubixCockpitStream.withFrames([next],budget.state) |histories,sourceOwner|
        {
          local:=EnerCubixPreparedOwner(budget.state)
          try {b.beginFrame(local,histories);value:=b.node("m","c",at,at+1hr);verifyEq(value.value,99f);verify(value!==original)}
          finally {local.close}
        }
      }
      finally {next.close}
    }
    finally {cursor.close;first.close;second.close;model.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }

  Void testStrictSourceReuseKeepsZeroAndExactKeysAndRejectsBeforeAllocation()
  {
    budget:=EnerCubixStreamBudget();cursor:=source(budget,[HisItem(at,Number(7)),HisItem(at+1hr,Number(7))]);peer:=EnerCubixPreparedOwner(budget.state)
    record:=records[1]
    try
    {
      cursor.advance(at+1hr)
      EnerCubixCockpitStream.withFrames([cursor],budget.state) |histories,owner|
      {
        h:=histories["p"];zero:=h.read(at,at+1hr);verifyEq(zero.value,0f)
        h.rememberOwnStrict(record,"c",at,at+1hr,"energy",zero)
        verify(h.ownStrict(record,"c",at,at+1hr,"energy").value===zero)
        verifyEq(h.ownStrict(record.dup,"c",at,at+1hr,"energy"),null)
        verifyEq(h.ownStrict(record,"other",at,at+1hr,"energy"),null)
        verifyEq(h.ownStrict(record,"c",at+1min,at+1hr,"energy"),null)
        verifyEq(h.ownStrict(record,"c",at,at+1hr,"co2"),null)
        h.rememberOwnStrict(record,"c",at,at+1hr,"cost",zero)
        verifyEq(h.ownStrict(record,"c",at,at+1hr,"cost"),null)
        peer.hold(budget.state.remaining-13);held:=owner.entries;peerHeld:=peer.entries;total:=budget.state.temporary.val
        verifyErr(EnerCubixHttpErr#) {h.rememberOwnStrict(record,"c",at,at+1hr,"co2",zero)}
        verifyEq(owner.entries,held);verifyEq(peer.entries,peerHeld);verifyEq(budget.state.temporary.val,total)
        verifyEq(h.ownStrict(record,"c",at,at+1hr,"co2"),null)
        verifyEq(zero.value,0f);verifyEq(zero.sources,["p"])
      }
      verifyEq(budget.state.temporary.val-peer.entries>0,true)
    }
    finally {cursor.close;peer.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }

  Void testCanonicalContextsShareOnlyProvenEmptyOwnResultsWithinSourceFrame()
  {
    rs:=records;rs[1]["subcategoryId"]="s";rs.add(["id":"s","kind":"subcategory"])
    budget:=EnerCubixStreamBudget();model:=EnerCubixPreparedOwner(budget.state)
    catalog:=EnerCubixCockpitCatalog(rs.toImmutable,TimeZone.utc,model)
    first:=EnerCubixPreparedOwner(budget.state);second:=EnerCubixPreparedOwner(budget.state)
    a:=EnerCubixContext.shared(catalog,"space",false,first);a.orderWarnings
    b:=EnerCubixContext.shared(catalog,"metering",false,second);b.orderWarnings
    bound:=EnerCubixContext.bound(a,"s",["id":"s","kind":"subcategory","coalFactor":2f]);bound.orderWarnings
    cursor:=source(budget,HisItem[,])
    try
    {
      cursor.advance(at+1hr)
      EnerCubixCockpitStream.withFrames([cursor],budget.state) |histories,frame|
      {
        a.beginFrame(frame,histories);b.beginFrame(frame,histories);bound.beginFrame(frame,histories)
        a.warningScope(3,0,at.ticks);av:=a.node("m","c",at,at+1hr,"coal")
        a.warningScope(0,0,at.ticks);a.warn("first logical phase");a.node("m","c",at,at+1hr,"coal")
        b.warningScope(0,0,at.ticks);bv:=b.node("m","c",at,at+1hr,"coal")
        verifyEq(av.value,null);verifyEq(av.quality,"missingCoefficient");verifyEq(av.sources,["p"])
        verify(av===bv,"canonical views should reuse the admitted empty result")
        verifyEq(a.orderedWarnings,["first logical phase","m : missingCoefficient"])
        verifyEq(b.orderedWarnings,["m : missingCoefficient"])
        bound.warningScope(0,0,at.ticks)
        verifyEq(bound.node("m","c",at,at+1hr,"coal").quality,"missing","bound coefficient must not borrow the canonical result")
      }
    }
    finally {cursor.close;second.close;first.close;model.close}
    verifyEq(budget.state.temporary.val,0)
  }

  Void testSharedEmptySubpairsKeepConsumerDomainWarningPrecedence()
  {
    budget:=EnerCubixStreamBudget();model:=EnerCubixPreparedOwner(budget.state)
    catalog:=EnerCubixCockpitCatalog(records.toImmutable,TimeZone.utc,model)
    first:=EnerCubixPreparedOwner(budget.state);second:=EnerCubixPreparedOwner(budget.state)
    a:=EnerCubixContext.shared(catalog,"space",false,first);a.orderWarnings
    b:=EnerCubixContext.shared(catalog,"space",false,second);b.orderWarnings
    mid:=at+30min
    q:=Str:Obj?["from":at.toIso,"to":(at+1hr).toIso,"asOf":(at+1hr).toIso,"tz":"UTC",
      "_cockpitReadRanges":[["from":at.toIso,"to":mid.toIso],["from":mid.toIso,"to":(at+1hr).toIso]]]
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"])
    cursor:=EnerCubixCockpitStream.openCursor(point,null,at,at+1hr,q,records,budget,|Dict p,Span s,|HisItem| sink| {})
    try
    {
      cursor.advance(at+1hr)
      EnerCubixCockpitStream.withFrames([cursor],budget.state) |histories,frame|
      {
        a.beginFrame(frame,histories);b.beginFrame(frame,histories)
        b.warningScope(0,0,at.ticks);b.node("m","c",at,mid);b.node("m","c",mid,at+1hr)
        a.warningScope(3,0,at.ticks);a.node("m","c",at,mid)
        a.warningScope(1,0,at.ticks);a.warn("middle phase")
        a.warningScope(0,0,at.ticks);a.node("m","c",mid,at+1hr)
        verifyEq(a.orderedWarnings,["middle phase","m : missing"])
      }
    }
    finally {cursor.close;second.close;first.close;model.close}
    verifyEq(budget.state.temporary.val,0)
  }

  Void testWarningTextReusesExactMessagesAndFallsBackWithoutTakingPeerBudget()
  {
    budget:=EnerCubixStreamBudget();owner:=EnerCubixPreparedOwner(budget.state)
    catalog:=EnerCubixCockpitCatalog(records.toImmutable,TimeZone.utc,owner)
    message:=(Str)catalog->warningText("主表 A","missing",false)
    verifyEq(message,"主表 A : missing")
    retained:=owner.entries
    verify(catalog->warningText("主表 A","missing",false)===message)
    verifyEq(owner.entries,retained)
    verifyEq(catalog->warningText("主表 A","missing",true),"主表 A: missing")
    verifyEq(catalog->warningText("主表 A","na",false),"主表 A : na")
    retained=owner.entries
    peer:=EnerCubixPreparedOwner(budget.state);peer.hold(budget.state.remaining-1)
    verifyEq(catalog->warningText("uncached label","missing",false),"uncached label : missing")
    verifyEq(owner.entries,retained,"optional text reuse must not reclaim peer or diagnostic capacity")
    owner.close;verifyEq(budget.state.temporary.val,peer.entries);peer.close
    verifyEq(budget.state.temporary.val,0)
    verifyErr(ArgErr#) {catalog->warningText("closed","missing",false)}
  }

  Void testOptionalWarningTextLeavesCurrentWarningAdmissionAvailable()
  {
    budget:=EnerCubixStreamBudget();model:=EnerCubixPreparedOwner(budget.state)
    catalog:=EnerCubixCockpitCatalog(records.toImmutable,TimeZone.utc,model)
    state:=EnerCubixPreparedOwner(budget.state);ctx:=EnerCubixContext.shared(catalog,"space",false,state);ctx.orderWarnings
    peer:=EnerCubixPreparedOwner(budget.state);peer.hold(budget.state.remaining-8)
    retained:=model.entries
    try
    {
      ctx.warnLine("主表边界","missing")
      verifyEq(ctx.orderedWarnings,["主表边界: missing"])
      verifyEq(model.entries,retained,"optional text caching must leave the current mandatory warning available")
    }
    finally {state.close;model.close;peer.close}
    verifyEq(budget.state.temporary.val,0)
  }

  private EnerCubixCockpitStream source(EnerCubixStreamBudget budget,HisItem[] raw)
  {
    cfg:=Etc.makeDict(["defNull":Marker.val]);p:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":cfg])
    q:=Str:Obj?["from":at.toIso,"to":(at+4hr).toIso,"asOf":(at+4hr).toIso,"tz":"UTC"]
    return EnerCubixCockpitStream.openCursor(p,cfg,at,at+4hr,q,records,budget,|Dict point,Span span,|HisItem| sink| {raw.each |row| {if(row.ts>=span.start && row.ts<span.end) sink(row)}})
  }
  private [Str:Obj?][] records() {[["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c"]]}
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

using haystack
using [java] java.lang::Class as JavaClass

** Actual private producer frames; no FIN data or project mutation.
class FinEnergyContextOwnerTest : Test
{
  Void testValidatedMemoProofTracksRecordIdentityAndIsClearedOnReplacement()
  {
    budget:=FinEnergyStreamBudget();model:=FinEnergyPreparedOwner(budget.state);state:=FinEnergyPreparedOwner(budget.state)
    catalog:=FinEnergyCockpitCatalog(records.toImmutable,TimeZone.utc,model,[:],false,false,true)
    ctx:=FinEnergyContext.shared(catalog,"metering",false,state)
    cursor:=source(budget,[HisItem(at,Number(0)),HisItem(at+1hr,Number(10))])
    try
    {
      cursor.advance(at+1hr)
      FinEnergyCockpitStream.withFrames([cursor],budget.state) |histories,outer|
      {
        frame:=FinEnergyPreparedOwner(budget.state);record:=catalog.byId["m"]
        try
        {
          ctx.beginFrame(frame,histories);value:=ctx.node("m","c",at,at+1hr)
          verifyEq(value.value,10f);verify(ctx.node("m","c",at,at+1hr)===value)
          slots:=(Map)FinEnergyContext#.field("ownFrameValues").get(ctx);slot:=slots["m"]
          verify(slot->record===record,"only the validated immutable canonical record proves this hit")
          catalog.byId["m"]=record.dup.set("name","meter").set("configurationError","changed configuration").toImmutable
          verifyEq(ctx.node("m","c",at,at+1hr).quality,"invalidConfiguration")
          catalog.byId["m"]=record
          verifyEq(ctx.node("m","c",at,at+1hr,"energy",["m"]).quality,"cycle")
          verify(ctx.node("m","c",at,at+1hr)===value)
          FinEnergyContext#.method("saveOwnFrameValue").callOn(ctx,Obj?["m","c",at,at+1hr,"energy",FinEnergyValue(99f,"ok",["p"]),true,record.dup])
          verifyEq(slot->record,null,"updating a slot must also revoke its obsolete record proof")
        }
        finally {catalog.byId["m"]=record;frame.close}
        verifyErr(ArgErr#) {ctx.node("m","c",at,at+1hr)}
      }
    }
    finally {cursor.close;state.close;model.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }

  Void testIntervalOnlyWindowPreservesClosedValuesQualityAndRuleFacts()
  {
    point:=Etc.makeDict(["id":Ref("p"),"unit":"kWh","tz":"UTC"])
    raw:=HisItem[,];for(i:=0;i<720;i++) raw.add(HisItem(at+Duration(i*10sec.ticks),Number(i)))
    closed:=FinEnergyInterval[
      FinEnergyInterval(at-10min,at+10min,2f,"cleaned","number"),
      FinEnergyInterval(at+10min,at+20min,3f,"cleaned","number"),
      FinEnergyInterval(at+20min,at+30min,null,"na","na"),
      FinEnergyInterval(at+30min,at+50min,8f,"substituted","number"),
      FinEnergyInterval(at+50min,at+80min,9f,"cleaned","number"),
      FinEnergyInterval(at+80min,at+2hr,null,"filtered","null")]
    factory:=FinEnergyHistoryData#.method("closedWindow")
    [at+90min,at+2hr].each |cutoff|
    {
      old:=FinEnergyHistoryData.window(point,"interval",raw,closed,cutoff)
      fast:=(FinEnergyHistoryData)factory.call(point,closed,cutoff)
      verify(fast.samples.isEmpty && fast.rawSamples.isEmpty)
      [DateTime[at,at+1hr],DateTime[at+5min,at+40min],DateTime[at+1hr,at+2hr]].each |range|
      {
        a:=old.read(range[0],range[1]);b:=fast.read(range[0],range[1])
        verifyEq([b.value,b.quality,b.sources],[a.value,a.quality,a.sources])
        [false,true].each |rules| {[0,1000].each |limit|
        {
          before:=old.captureKnownUsage(range[0],range[1],cutoff,rules,limit)
          after:=fast.captureKnownUsage(range[0],range[1],cutoff,rules,limit)
          av:=(FinEnergyValue)before.remove("value");bv:=(FinEnergyValue)after.remove("value")
          verifyEq([bv.value,bv.quality,bv.sources],[av.value,av.quality,av.sources]);verifyEq(after,before)
        }}
      }
    }
    simple:=(FinEnergyHistoryData)factory.call(point,[FinEnergyInterval(at,at+1hr,12f,"cleaned","number")],at+1hr)
    verifyEq(simple.read(at,at+1hr).value,12f);verifyEq(simple.knownUsage(at,at+1hr,at+1hr)["knownValue"],12f)
    cumulative:=FinEnergyHistoryData.window(point,"cumulative",[HisItem(at,Number(10)),HisItem(at+1hr,Number(50))],null,at+1hr)
    verifyEq(cumulative.samples.size,2);verifyEq(cumulative.read(at,at+1hr).value,40f)
  }

  Void testKnownHeaderAdmitsNewSlotAndFieldsAtomically()
  {
    budget:=FinEnergyStreamBudget();persistent:=FinEnergyPreparedOwner(budget.state);frame:=FinEnergyPreparedOwner(budget.state);peer:=FinEnergyPreparedOwner(budget.state)
    ctx:=FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(persistent);ctx.beginFrame(frame,Str:FinEnergyHistoryData[:])
    method:=FinEnergyContext#.method("knownHeader");charges:=(Str:Int)FinEnergyContext#.field("knownCharges").get(ctx);before:=frame.entries
    try
    {
      peer.hold(budget.state.remaining-2);held:=peer.entries
      verifyErr(FinEnergyHttpErr#) {method.call(ctx,"exact-pair",2)}
      verify(charges.isEmpty,"rejected field admission must not publish an intermediate empty slot")
      verifyEq(frame.entries,before);verifyEq(peer.entries,held)
      peer.close;method.call(ctx,"exact-pair",2);verifyEq(charges["exact-pair"],2);verifyEq(frame.entries,before+3)
      method.call(ctx,"exact-pair",1);verifyEq(frame.entries,before+3)
      upgrade:=FinEnergyPreparedOwner(budget.state)
      try
      {
        upgrade.hold(budget.state.remaining-2);upgradeHeld:=upgrade.entries
        verifyErr(FinEnergyHttpErr#) {method.call(ctx,"exact-pair",5)}
        verifyEq(charges["exact-pair"],2);verifyEq(frame.entries,before+3);verifyEq(upgrade.entries,upgradeHeld)
        upgrade.close;method.call(ctx,"exact-pair",5);verifyEq(charges["exact-pair"],5);verifyEq(frame.entries,before+6)
      }
      finally {upgrade.close}
    }
    finally {frame.close;persistent.close;peer.close}
    verifyEq(budget.state.temporary.val,0)
  }

  Void testProducerCleanupDoesNotClonePublishedReadonlyIndexAtFullBudget()
  {[false,true].each |reject| {checkPublishedIndex(reject)}}

  private Void checkPublishedIndex(Bool reject)
  {
    budget:=FinEnergyStreamBudget();cursor:=source(budget,[HisItem(at,Number(0)),HisItem(at+1hr,Number(10))]);cursor.advance(at+1hr)
    // The exact FIN runtime Map.ro implementation clones storage on mutation
    // of its mutable alias. Observe real storage identity, not budget counters.
    storage:=JavaClass.forName("fan.sys.Map").getDeclaredField("map");storage.setAccessible(true)
    Map? published;Obj? before;FinEnergyPreparedOwner? peer;held:=0
    try
    {
      run:=|->Void|
      {
        FinEnergyCockpitStream.withFrames([cursor],budget.state) |histories,owner|
        {
          published=histories;verify(histories.isRO);before=storage.get(histories)
          peer=FinEnergyPreparedOwner(budget.state);peer.hold(budget.state.remaining);held=peer.entries
          if(reject) throw IOErr("controlledConsumerRejection")
        }
      }
      if(reject) verifyErr(IOErr#) {run()};else run()
      verify(storage.get(published)===before,"cleanup must drop roots without triggering Map.ro copy-on-write")
      verifyErr(ArgErr#) {((FinEnergyHistoryData)published["p"]).read(at,at+1hr)}
      cursor.close;verifyEq(budget.state.temporary.val,held)
    }
    finally {published=null;before=null;cursor.close;peer?.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }

  Void testCompleteKnownHeadersShareOnlyInsideOwnedCanonicalSourceHour()
  {
    budget:=FinEnergyStreamBudget();model:=FinEnergyPreparedOwner(budget.state);catalog:=FinEnergyCockpitCatalog(records.toImmutable,TimeZone.utc,model,[:],false,false,true)
    aOwner:=FinEnergyPreparedOwner(budget.state);bOwner:=FinEnergyPreparedOwner(budget.state)
    a:=FinEnergyContext.shared(catalog,"space",false,aOwner);b:=FinEnergyContext.shared(catalog,"metering",false,bOwner)
    ka:=FinEnergyContext.known(a,at+4hr);kb:=FinEnergyContext.known(b,at+4hr)
    cfg:=Etc.makeDict(["defNull":Marker.val]);p:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"finEnergyCleanHis","hisFuncConfig":cfg])
    q:=Str:Obj?["from":at.toIso,"to":(at+4hr).toIso,"asOf":(at+4hr).toIso,"tz":"UTC","_cockpitReadRanges":[["from":at.toIso,"to":(at+4hr).toIso],["from":at.toIso,"to":(at+2hr).toIso]]]
    cursor:=FinEnergyCockpitStream.openCursor(p,cfg,at,at+4hr,q,records,budget,|Dict point,Span span,|HisItem| sink| {[HisItem(at,Number(0)),HisItem(at+1hr,Number(10)),HisItem(at+2hr,Number(30))].each |row| {if(row.ts>=span.start && row.ts<span.end) sink(row)}})
    try
    {
      cursor.advance(at+1hr)
      FinEnergyCockpitStream.withFrames([cursor],budget.state) |histories,sourceOwner|
      {
        fa:=FinEnergyPreparedOwner(budget.state);fb:=FinEnergyPreparedOwner(budget.state)
        try
        {
          a.beginFrame(fa,histories);ka.beginFrame(fa,histories);verifyEq(ka.node("m","c",at,at+1hr).value,10f)
          verify(histories.isRO,"producer source maps are read-only for every consumer")
          verifyErr(ReadonlyErr#) {histories.remove("p")}
          verify(a.byPoint===histories,"owned contexts borrow the already-owned source index instead of copying its entries")
          first:=ka.knownReads.vals.first;firstKey:=ka.knownReads.keys.first;before:=first.dup;verifyEq(FinEnergyMath.maps(first["intervals"]).size,1)
          copy:=first.dup;copy.clear;fa.close;aOwner.close
          b.beginFrame(fb,histories);kb.beginFrame(fb,histories);lookups:=budget.state.lookups.val
          verifyEq(kb.node("m","c",at,at+1hr).value,10f)
          verifyEq(budget.state.lookups.val,lookups+1,"the shared header path keeps the original prepared lookup/deadline cadence")
          verifyEq(FinEnergyContext#.field("knownScratch").get(kb),6,"an already owned complete header needs only two scalar value workspaces, not another copied map or detail vectors")
          verify(kb.knownReads.vals.first===first,"consumer evidence links borrow the same admitted complete header")
          verify(kb.knownReads.keys.first===firstKey,"an exact shared source header retains its immutable key text after the first consumer expires")
          verify(!kb.emptyEvidenceOmitted);verifyEq(kb.knownReads.size,1)
          sharedCharges:=(Str:Int)FinEnergyContext#.field("knownCharges").get(kb)
          verifyEq(sharedCharges.vals.first,2,"the source owns the complete shared header; this consumer retains only its slot/key links")
          verify(sourceOwner.entries>=8+first.size)
          verify(histories["p"].knownEvidence(b.byId["m"],at,at+1hr,at+4hr)===first)
          fresh:=kb.ownRaw(b.byId["m"],at,at+1hr,Str[,]);fresh.value=-999f
          verifyEq(kb.ownRaw(b.byId["m"],at,at+1hr,Str[,]).value,10f,"only the header is shared; raw numeric values stay independent")
          FinEnergyContext#.field("knownDetailCount").set(kb,1000)
          verifyEq(kb.ownRaw(b.byId["m"],at,at+1hr,Str[,]).value,10f)
          replaced:=kb.knownReads.vals.first
          verify(replaced!==first);verifyEq(FinEnergyMath.maps(replaced["intervals"]).size,0)
          verify(sharedCharges.vals.first>2,"a later trimmed replacement must upgrade the same slot before allocating its independent map")
          verifyEq(first,before)
          otherEnd:=FinEnergyContext.known(b,at+2hr);verifyEq(otherEnd.node("m","c",at,at+1hr).value,10f)
          verify(otherEnd.knownReads.vals.first!==first,"second prepared queryEnd is an independent key")
          bound:=FinEnergyContext.bound(b,"m",b.byId["m"].dup.set("maximum",5f));limited:=FinEnergyContext.known(bound,at+4hr)
          verifyEq(limited.node("m","c",at,at+1hr).quality,"maximum");verify(limited.knownReads.vals.first!==first)
          trimmed:=FinEnergyContext.known(b,at+4hr);FinEnergyContext#.field("knownDetailCount").set(trimmed,1000)
          verifyEq(trimmed.node("m","c",at,at+1hr).value,10f);row:=trimmed.knownReads.vals.first
          verify(row!==first);verifyEq(FinEnergyMath.maps(row["intervals"]).size,0);verifyEq(row["detailsTruncated"],true);verify(row["intervalsCaptureId"] is Str)
          verifyEq(first,before);verifyEq(FinEnergyMath.maps(first["intervals"]).size,1)
          peer:=FinEnergyPreparedOwner(budget.state)
          try
          {
            peer.hold(budget.state.remaining-1);held:=sourceOwner.entries;peerHeld:=peer.entries;total:=budget.state.temporary.val;otherRecord:=b.byId["m"].dup.toImmutable
            verifyErr(FinEnergyHttpErr#) {histories["p"].rememberKnownEvidence(otherRecord,at,at+1hr,at+4hr,first)}
            verifyEq(sourceOwner.entries,held);verifyEq(peer.entries,peerHeld);verifyEq(budget.state.temporary.val,total)
            verifyEq(histories["p"].knownEvidence(otherRecord,at,at+1hr,at+4hr),null)
          }
          finally {peer.close}
        }
        finally {fa.close;fb.close}
      }
    }
    finally {cursor.close;aOwner.close;bOwner.close;model.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }

  Void testSinglePassPhysicalContextsKeepNumbersAndEvidenceWithoutUnusedMemo()
  {
    budget:=FinEnergyStreamBudget();model:=FinEnergyPreparedOwner(budget.state);catalog:=FinEnergyCockpitCatalog(records.toImmutable,TimeZone.utc,model)
    normalOwner:=FinEnergyPreparedOwner(budget.state);fastOwner:=FinEnergyPreparedOwner(budget.state)
    normal:=FinEnergyContext.shared(catalog,"metering",false,normalOwner);fast:=FinEnergyContext.shared(catalog,"metering",false,fastOwner)
    nk:=FinEnergyContext.known(normal,at+4hr);fk:=FinEnergyContext.known(fast,at+4hr)
    cursor:=source(budget,[HisItem(at,Number(0)),HisItem(at+1hr,Number(10)),HisItem(at+2hr,Number(30))])
    try
    {
      for(i:=0;i<2;i++)
      {
        from:=at+1hr*i;to:=from+1hr;cursor.advance(to)
        FinEnergyCockpitStream.withFrames([cursor],budget.state) |histories,sourceOwner|
        {
          a:=FinEnergyPreparedOwner(budget.state);b:=FinEnergyPreparedOwner(budget.state)
          try
          {
            normal.beginFrame(a,histories);nk.beginFrame(a,histories);fast.beginFrame(b,histories,false,true);fk.beginFrame(b,histories,false,true)
            nv:=normal.node("m","c",from,to);kv:=nk.node("m","c",from,to);fv:=fast.node("m","c",from,to);fkv:=fk.node("m","c",from,to)
            verifyEq(fv.value,10f*(i+1).toFloat);verifyEq(fv.value,nv.value);verifyEq(fv.quality,nv.quality);verifyEq(fv.sources,nv.sources)
            verifyEq(fkv.value,kv.value);verifyEq(fkv.quality,kv.quality);verifyEq(fkv.sources,kv.sources)
            verifyEq(fk.knownReads,nk.knownReads);verifyEq(fk.knownReads.size,1)
            verify(a.entries-b.entries>=20,"a single visit must not retain the unused strict/known memo maps and wrappers")
          }
          finally {a.close;b.close}
        }
      }
    }
    finally {cursor.close;normalOwner.close;fastOwner.close;model.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }

  Void testFrameAdmissionIncludesCopiedKnownHeaderFields()
  {
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"]];ids:=Str[,]
    for(i:=0;i<18;i++) {ids.add("m$i");rs.add(["id":"m$i","kind":"meter","pointId":"p$i","categoryId":"c"])}
    q:=Str:Obj?["kind":"profile","nodeIds":ids,"from":at.toIso,"to":(at+1hr).toIso,"asOf":(at+1hr).toIso,"tz":"UTC","period":"hour","metric":"energy"]
    budget:=FinEnergyStreamBudget();state:=FinEnergyPreparedOwner(budget.state)
    ctx:=FinEnergyContext(rs,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(state);known:=FinEnergyContext.known(ctx,at+1hr)
    streams:=FinEnergyCockpitStream[,]
    read:=|Dict p,Span span,|HisItem| sink| {(0..1).each |i| {ts:=at+Duration(i*1hr.ticks);if(ts>=span.start && ts<span.end) sink(HisItem(ts,Number(1)))}}
    for(i:=0;i<18;i++)
    {
      p:=Etc.makeDict(["id":Ref("p$i"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])
      stream:=FinEnergyCockpitStream.openCursor(p,null,at,at+1hr,q,rs,budget,read,ctx);stream.advance(at+1hr);streams.add(stream)
    }
    try
    {
      FinEnergyCockpitStream.withFrames(streams,budget.state) |histories,frame|
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
    budget:=FinEnergyStreamBudget();peer:=FinEnergyPreparedOwner(budget.state);peer.hold(13)
    persistent:=FinEnergyPreparedOwner(budget.state);ctx:=FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc)
    ctx.useOwner(persistent);known:=FinEnergyContext.known(ctx,at+4hr)
    cursor:=source(budget,[HisItem(at,Number(0)),HisItem(at+1hr,Number(10)),HisItem(at+2hr,Number(20))])
    cursor.advance(at+1hr)
    cursor.withFrame |h|
    {
      before:=budget.state.temporary.val;frame:=FinEnergyPreparedOwner(budget.state)
      verifyErr(ArgErr#) {ctx.beginFrame(frame,["wrong":h])}
      ctx.beginFrame(frame,["p":h]);known.beginFrame(frame,["p":h])
      strictValue:=ctx.node("m","c",at,at+1hr);knownValue:=known.node("m","c",at,at+1hr)
      verifyEq(strictValue.value,10f);verifyEq(knownValue.value,10f);verify(!known.knownReads.isEmpty)
      verify(ctx.node("m","c",at,at+1hr)===strictValue)
      verify(known.node("m","c",at,at+1hr)===knownValue)
      // Recursive scope visits reuse this device's own result in this frame.
      verify(ctx.node("m","c",at,at+1hr,"energy",["group"])===strictValue)
      bound:=FinEnergyContext.bound(ctx,"m",ctx.byId["m"].dup.set("maximum",5f))
      verifyEq(bound.node("m","c",at,at+1hr).quality,"maximum")
      observedBound:=FinEnergyContext.known(bound,at+4hr)
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
    budget:=FinEnergyStreamBudget();persistent:=FinEnergyPreparedOwner(budget.state)
    ctx:=FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(persistent)
    cursor:=source(budget,[HisItem(at+1hr,Number(0)),HisItem(at+3hr,Number(10))])
    qualities:=Str[,]
    for(i:=1;i<=3;i++)
    {
      end:=at+Duration(i*1hr.ticks);cursor.advance(end)
      cursor.withFrame |h|
      {
        frame:=FinEnergyPreparedOwner(budget.state);ctx.beginFrame(frame,["p":h])
        qualities.add(ctx.node("m","c",end-1hr,end).quality)
        frame.close
      }
    }
    verifyEq(qualities,["missing","incompleteInterval","incompleteInterval"])
    cursor.close;persistent.close;verifyEq(budget.state.temporary.val,0)
  }

  Void testForeignOwnerAndUnleasedHistoryCannotEnterFrame()
  {
    budget:=FinEnergyStreamBudget();persistent:=FinEnergyPreparedOwner(budget.state)
    ctx:=FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(persistent)
    verifyErr(ArgErr#) {ctx.beginFrame(persistent,Str:FinEnergyHistoryData[:])}
    foreign:=FinEnergyPreparedOwner(FinEnergyPreparedBudget(FinEnergyCockpitDeadline()))
    verifyErr(ArgErr#) {ctx.beginFrame(foreign,Str:FinEnergyHistoryData[:])}
    foreign.close
    frame:=FinEnergyPreparedOwner(budget.state)
    raw:=FinEnergyHistoryData(["pointId":"p","mode":"interval","unit":"kWh","samples":[["ts":at.toIso,"value":10f]]])
    verifyErr(ArgErr#) {ctx.beginFrame(frame,["p":raw])}
    frame.close;persistent.close;verifyEq(budget.state.temporary.val,0)
  }

  Void testReadonlyCallerIndexWithoutProducerAdmissionStillNeedsOwnedCopy()
  {
    budget:=FinEnergyStreamBudget();persistent:=FinEnergyPreparedOwner(budget.state)
    ctx:=FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(persistent)
    cursor:=source(budget,[HisItem(at,Number(0)),HisItem(at+1hr,Number(10))]);cursor.advance(at+1hr)
    try
    {
      cursor.withFrame |h|
      {
        frame:=FinEnergyPreparedOwner(budget.state);index:=Str:FinEnergyHistoryData["p":h].ro
        try
        {
          ctx.beginFrame(frame,index)
          verify(ctx.byPoint!==index,"read-only alone is not proof that another owner admitted the source index")
          verifyEq(ctx.node("m","c",at,at+1hr).value,10f)
        }
        finally {frame.close}
      }
    }
    finally {cursor.close;persistent.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }

  Void testFailedMetadataAdmissionStillDropsRegisteredRoots()
  {
    budget:=FinEnergyStreamBudget();budget.state.hold(199993)
    persistent:=FinEnergyPreparedOwner(budget.state)
    ctx:=FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc)
    verifyErr(FinEnergyHttpErr#) {ctx.useOwner(persistent)}
    persistent.close
    verify(ctx.byId.isEmpty);verify(ctx.children.isEmpty)
    verifyEq(budget.state.temporary.val,199993)
    budget.state.releaseTemporary(199993)
  }

  Void testWarningsFollowOriginalLineAndPhaseOrderAcrossInterleavedHours()
  {
    budget:=FinEnergyStreamBudget();owner:=FinEnergyPreparedOwner(budget.state)
    ctx:=FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
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
    budget:=FinEnergyStreamBudget();owner:=FinEnergyPreparedOwner(budget.state)
    ctx:=FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    known:=FinEnergyContext.known(ctx,at+1hr)
    peer:=FinEnergyPreparedOwner(budget.state);peer.hold(budget.state.remaining-1)
    verifyErr(FinEnergyHttpErr#) {known.warn("主表 : missing")}
    verify(known.warnings.isEmpty,"failed admission must not publish a partial warning")
    owner.close;verify(known.warnings.isEmpty)
    verifyEq(budget.state.temporary.val,peer.entries)
    peer.close;verifyEq(budget.state.temporary.val,0)
  }

  Void testOwnedKnownWarningsKeepFirstOccurrenceAndRetireWithOwner()
  {
    budget:=FinEnergyStreamBudget();owner:=FinEnergyPreparedOwner(budget.state)
    ctx:=FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    known:=FinEnergyContext.known(ctx,at+1hr)
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
    budget:=FinEnergyStreamBudget();owner:=FinEnergyPreparedOwner(budget.state)
    ctx:=FinEnergyContext(rs,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    q:=Str:Obj?["from":at.toIso,"to":(at+24hr).toIso,"asOf":(at+24hr).toIso,"tz":"UTC"]
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])
    stream:=FinEnergyCockpitStream.openCursor(point,null,at,at+24hr,q,rs,budget,|Dict p,Span span,|HisItem| sink|
    // Native consumption readings are end stamped; include the left context.
    // 01:00 carries hour 00's 1, while the 00:00 row belongs before the range.
    {(0..24).each |i| {ts:=at+Duration(i*1hr.ticks);if(ts>=span.start && ts<span.end) sink(HisItem(ts,Number(i)))}})
    try
    {
      stream.advance(at+24hr)
      FinEnergyCockpitStream.withFrames([stream],budget.state) |histories,frame|
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
    budget:=FinEnergyStreamBudget();owner:=FinEnergyPreparedOwner(budget.state)
    ctx:=FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(owner)
    known:=FinEnergyContext.known(ctx,at+4hr);cursor:=source(budget,HisItem[,])
    FinEnergyHistoryData? expired
    try
    {
      cursor.advance(at+4hr)
      FinEnergyCockpitStream.withFrames([cursor],budget.state) |histories,frame|
      {
        h:=histories["p"];expired=h;ctx.beginFrame(frame,histories);known.beginFrame(frame,histories)
        borrowed:=(Str:Obj?)h->borrowedKnownUsage(at,at+1hr,at+4hr)
        verify(h->borrowedKnownUsage(at,at+1hr,at+4hr)===borrowed)
        ordinary:=h.knownUsage(at,at+1hr,at+4hr)
        verify(ordinary!==borrowed);ordinary["knownQuality"]="caller edit"
        verifyEq(borrowed["knownQuality"],"missing");verifyEq(borrowed["coveredSeconds"],0f)
        verifyEq(borrowed["intervalCount"],0);verifyEq(((FinEnergyValue)borrowed["value"]).value,null)
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
    budget:=FinEnergyStreamBudget();model:=FinEnergyPreparedOwner(budget.state);catalog:=FinEnergyCockpitCatalog(rs.toImmutable,TimeZone.utc,model)
    first:=FinEnergyPreparedOwner(budget.state);second:=FinEnergyPreparedOwner(budget.state)
    a:=FinEnergyContext.shared(catalog,"space",false,first);b:=FinEnergyContext.shared(catalog,"metering",false,second)
    cursor:=source(budget,[HisItem(at,Number(0)),HisItem(at+1hr,Number(10)),HisItem(at+2hr,Number(30))]);FinEnergyValue? original;FinEnergyHistoryData? expired
    try
    {
      cursor.advance(at+1hr)
      FinEnergyCockpitStream.withFrames([cursor],budget.state) |histories,sourceOwner|
      {
        expired=histories["p"];fa:=FinEnergyPreparedOwner(budget.state);fb:=FinEnergyPreparedOwner(budget.state)
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
          bound:=FinEnergyContext.bound(b,"m",b.byId["m"].dup.set("maximum",5f));verifyEq(bound.node("m","c",at,at+1hr).quality,"maximum")
          verifyEq(b.node("m","c",at,at+1hr).value,10f)
          known:=FinEnergyContext.known(b,at+4hr);verifyEq(known.node("m","c",at,at+1hr).value,10f)
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
        FinEnergyCockpitStream.withFrames([next],budget.state) |histories,sourceOwner|
        {
          local:=FinEnergyPreparedOwner(budget.state)
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
    budget:=FinEnergyStreamBudget();cursor:=source(budget,[HisItem(at,Number(7)),HisItem(at+1hr,Number(7))]);peer:=FinEnergyPreparedOwner(budget.state)
    record:=records[1]
    try
    {
      cursor.advance(at+1hr)
      FinEnergyCockpitStream.withFrames([cursor],budget.state) |histories,owner|
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
        verifyErr(FinEnergyHttpErr#) {h.rememberOwnStrict(record,"c",at,at+1hr,"co2",zero)}
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
    budget:=FinEnergyStreamBudget();model:=FinEnergyPreparedOwner(budget.state)
    catalog:=FinEnergyCockpitCatalog(rs.toImmutable,TimeZone.utc,model,[:],false,false,true)
    first:=FinEnergyPreparedOwner(budget.state);second:=FinEnergyPreparedOwner(budget.state)
    a:=FinEnergyContext.shared(catalog,"space",false,first);a.orderWarnings
    b:=FinEnergyContext.shared(catalog,"metering",false,second);b.orderWarnings
    bound:=FinEnergyContext.bound(a,"s",["id":"s","kind":"subcategory","coalFactor":2f]);bound.orderWarnings
    cursor:=source(budget,HisItem[,])
    try
    {
      cursor.advance(at+1hr)
      FinEnergyCockpitStream.withFrames([cursor],budget.state) |histories,frame|
      {
        a.beginFrame(frame,histories);b.beginFrame(frame,histories);bound.beginFrame(frame,histories)
        a.warningScope(3,0,at.ticks);av:=a.node("m","c",at,at+1hr,"coal")
        a.warningScope(0,0,at.ticks);a.warn("first logical phase");a.node("m","c",at,at+1hr,"coal")
        b.warningScope(0,0,at.ticks);bv:=b.node("m","c",at,at+1hr,"coal")
        aKey:=((Map)FinEnergyContext#.field("cache").get(a)).keys.first
        bKey:=((Map)FinEnergyContext#.field("cache").get(b)).keys.first
        verify(aKey===bKey,"same source pair reuses its original admitted empty-domain key")
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
    budget:=FinEnergyStreamBudget();model:=FinEnergyPreparedOwner(budget.state)
    catalog:=FinEnergyCockpitCatalog(records.toImmutable,TimeZone.utc,model)
    first:=FinEnergyPreparedOwner(budget.state);second:=FinEnergyPreparedOwner(budget.state)
    a:=FinEnergyContext.shared(catalog,"space",false,first);a.orderWarnings
    b:=FinEnergyContext.shared(catalog,"space",false,second);b.orderWarnings
    mid:=at+30min
    q:=Str:Obj?["from":at.toIso,"to":(at+1hr).toIso,"asOf":(at+1hr).toIso,"tz":"UTC",
      "_cockpitReadRanges":[["from":at.toIso,"to":mid.toIso],["from":mid.toIso,"to":(at+1hr).toIso]]]
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"])
    cursor:=FinEnergyCockpitStream.openCursor(point,null,at,at+1hr,q,records,budget,|Dict p,Span s,|HisItem| sink| {})
    try
    {
      cursor.advance(at+1hr)
      FinEnergyCockpitStream.withFrames([cursor],budget.state) |histories,frame|
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
    budget:=FinEnergyStreamBudget();owner:=FinEnergyPreparedOwner(budget.state)
    catalog:=FinEnergyCockpitCatalog(records.toImmutable,TimeZone.utc,owner)
    message:=(Str)catalog->warningText("主表 A","missing",false)
    verifyEq(message,"主表 A : missing")
    retained:=owner.entries
    verify(catalog->warningText("主表 A","missing",false)===message)
    verifyEq(owner.entries,retained)
    verifyEq(catalog->warningText("主表 A","missing",true),"主表 A: missing")
    verifyEq(catalog->warningText("主表 A","na",false),"主表 A : na")
    retained=owner.entries
    peer:=FinEnergyPreparedOwner(budget.state);peer.hold(budget.state.remaining-1)
    verifyEq(catalog->warningText("uncached label","missing",false),"uncached label : missing")
    verifyEq(owner.entries,retained,"optional text reuse must not reclaim peer or diagnostic capacity")
    owner.close;verifyEq(budget.state.temporary.val,peer.entries);peer.close
    verifyEq(budget.state.temporary.val,0)
    verifyErr(ArgErr#) {catalog->warningText("closed","missing",false)}
  }

  Void testOptionalWarningTextLeavesCurrentWarningAdmissionAvailable()
  {
    budget:=FinEnergyStreamBudget();model:=FinEnergyPreparedOwner(budget.state)
    catalog:=FinEnergyCockpitCatalog(records.toImmutable,TimeZone.utc,model)
    state:=FinEnergyPreparedOwner(budget.state);ctx:=FinEnergyContext.shared(catalog,"space",false,state);ctx.orderWarnings
    peer:=FinEnergyPreparedOwner(budget.state);peer.hold(budget.state.remaining-8)
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

  private FinEnergyCockpitStream source(FinEnergyStreamBudget budget,HisItem[] raw)
  {
    cfg:=Etc.makeDict(["defNull":Marker.val]);p:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"finEnergyCleanHis","hisFuncConfig":cfg])
    q:=Str:Obj?["from":at.toIso,"to":(at+4hr).toIso,"asOf":(at+4hr).toIso,"tz":"UTC"]
    return FinEnergyCockpitStream.openCursor(p,cfg,at,at+4hr,q,records,budget,|Dict point,Span span,|HisItem| sink| {raw.each |row| {if(row.ts>=span.start && row.ts<span.end) sink(row)}})
  }
  private [Str:Obj?][] records() {[["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c"]]}
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

using haystack

** Full report DTOs from original leaf math; controlled sources, not FIN acceptance.
class EnerCubixReportConsumerTest : Test
{
  Void testConstructorFailureBetweenReducerForkAndCleanupRegistrationReleasesChild()
  {
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","categoryId":"c","pointId":"p"]].toImmutable
    start:=DateTime.fromIso("2026-01-01T00:00:00Z");end:=start+1hr
    budget:=EnerCubixStreamBudget().state;state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget);peer:=EnerCubixPreparedOwner(budget)
    dim:=EnerCubixDimension("metering",rs);ctx:=EnerCubixContext(dim.records,[Str:Obj?][,],TimeZone.utc,dim);ctx.useOwner(state)
    q:=Str:Obj?["from":start.toIso,"to":end.toIso,"asOf":end.toIso,"metric":"energy"]
    report:=EnerCubixReport(ctx,q,start,end,"daily","day","energy",state);cursors:=[report.openLine("m","c")]
    try
    {
      // Parent hook(1), consumer/closed-handle fields(27+5 per line), child owner(4):
      // the next parent hook must reject without stranding the child owner.
      peer.hold(budget.remaining-(1+27+5*cursors.size+4));held:=peer.entries
      verifyErr(EnerCubixHttpErr#) {unexpected:=EnerCubixReportConsumer(ctx,report,cursors,start,end,"day",state,output)}
      verifyEq(budget.temporary.val,state.entries+output.entries+peer.entries)
      state.close;output.close;verifyEq(budget.temporary.val,held)
    }
    finally {state.close;output.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }

  Void testOwnedReportsBuildAreaMetadataOnlyForNormalization()
  {
    source:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","categoryId":"c","pointId":"p","area":120f]].toImmutable
    start:=DateTime.fromIso("2026-01-01T00:00:00Z");end:=start+1hr;budget:=EnerCubixStreamBudget().state;state:=EnerCubixPreparedOwner(budget)
    dim:=EnerCubixDimension("metering",source);ctx:=EnerCubixContext(dim.records,[Str:Obj?][,],TimeZone.utc,dim);ctx.useOwner(state)
    q:=Str:Obj?["from":start.toIso,"to":end.toIso,"asOf":end.toIso,"perArea":false,"metric":"energy"]
    try
    {
      plain:=EnerCubixReport(ctx,q,start,end,"profile","hour","energy",state).openLine("m","c").line
      verify(plain.normalizationArea.isEmpty)
      normalized:=EnerCubixReport(ctx,q.dup.set("perArea",true),start,end,"profile","hour","energy",state).openLine("m","c").line
      verifyEq(normalized.normalizationArea["value"],120f);verifyEq(normalized.unit,"kWh/m²");verifyEq(source.last["area"],120f)
    }
    finally {state.close}
    verifyEq(budget.temporary.val,0)
  }

  Void testProfileMixedSelectionAndDetailsMatchOriginalReport()
  {
    [false,true].each |area|
    {
      q:=query.set("perArea",area);rs:=records
      exercise(q,rs)
    }
  }

  Void testRankingAndProportionPreserveOverlapAndKnownCoverage()
  {
    ["ranking","proportion","primary","dashboard"].each |kind| {exercise(query.set("kind",kind),records)}
  }

  Void testDetailOnlyAliasDoesNotChangeEarlierCoverageOrEvidence()
  {rs:=records;rs.last["pointId"]="pa";exercise(query,rs)}

  Void testCoefficientsAndTimedTariffKeepSameOwnMeterCalculation()
  {
    ["coal","co2","cost"].each |metric|
    {
      rs:=records
      rs.add(["id":"sub","kind":"subcategory","categoryId":"c","coalFactor":0.1229f,"co2Factor":0.5257f])
      rs.add(["id":"tariff","kind":"tariff","categoryId":"c","isDefault":true,"mode":"weekly","rate":0.735f,"currency":"CNY","rules":[["startHour":0,"endHour":0.5f,"rate":1f,"band":"valley"],["startHour":0.5f,"endHour":1,"rate":3f,"band":"sharp"]]])
      rs.findAll |r| {["meter","totalMeter"].contains(r["kind"])}.each |r| {r["subcategoryId"]="sub"}
      exercise(query.set("metric",metric),rs)
    }
  }

  Void testIncompleteOutputCannotPublishAndCleanupPreservesPeerOwner()
  {exercise(query,records,true)}

  Void testEmptySourceKeepsMissingCoverageAndEvidenceOmission()
  {exercise(query,records,false,true)}

  Void testMultipleCategoriesKeepAreaAndWarningOrder()
  {
    rs:=records;rs.each |r| {r.remove("area")}
    rs.add(["id":"water","kind":"category","unit":"m³"])
    rs.add(["id":"w","name":"Water","kind":"meter","pointId":"pb","categoryId":"water","spaceId":"s","nativeSpaceId":"s"])
    exercise(query.set("perArea",true),rs)
  }

  Void testCompatibleSourceUnitConversionMatchesOriginalLeafOrder()
  {exercise(query,records,false,false,"Wh")}

  Void testBorrowedNativeAreaMetadataSurvivesOutputExpiry()
  {rs:=records;rs.find |r| {r["id"]=="a"}["nativeArea"]=["value":10f,"unit":"m²"];exercise(query,rs)}

  Void testDailyHourAndTimeBandRowsMatchOriginalReport()
  {
    exercise(query.set("kind","daily"),records)
    rs:=records
    rs.add(["id":"cal","kind":"calendar","workHours":[0,1],"peakHours":[0],"valleyHours":[1]])
    exercise(query.set("kind","daily").set("perArea",true),rs)
  }

  Void testExactPartialFinalHourStillUsesOriginalPreparedSubrange()
  {
    q:=query.set("to",(at+200min).toIso).set("asOf",(at+200min).toIso)
    exercise(q,records);exercise(q.set("kind","daily"),records)
  }

  Void testUtilityKeepsConfiguredEndUseAndExplicitMeterFrontier()
  {
    rs:=records
    rs.add(["id":"u","kind":"utility","name":"Lighting","categoryId":"c"])
    rs.add(["id":"ac","kind":"utility","name":"AC","categoryId":"c"])
    rs.find |r| {r["id"]=="t"}["utilityId"]="u"
    rs.find |r| {r["id"]=="a"}["utilityId"]="u"
    rs.find |r| {r["id"]=="b"}["utilityId"]="ac"
    exercise(query.set("kind","utility"),rs)
    exercise(query.set("kind","utility").set("perArea",true),rs)
  }

  Void testWorkingBucketsKeepCalendarExceptionsOverridesAndMissingState()
  {
    ["workingHours","workingDays"].each |kind|
    {
      exercise(query.set("kind",kind),records)
      rs:=records
      rs.add(["id":"cal","kind":"calendar","workDays":[6],"workHours":[23,1],"exceptions":[["date":"2026-02-01","working":true]]])
      exercise(query.set("kind",kind).set("perArea",true),rs)
      exercise(query.set("kind",kind).set("workHours",Int[,]),rs)
    }
  }

  Void testOwnDailyObjectsDoNotCopyUnrelatedCatalogIntoEachOutput()
  {exerciseOutputGraph("own")}
  Void testFinishedReportsRetireReducersBeforeBuildingPublicDtos()
  {exerciseOutputGraph("retired")}
  Void testEveryOverlappingScopeDetailPairRemainsAdmitted()
  {exerciseOutputGraph("space")}
  Void testOrganizationAreasRetainAndExpireGeneratedOverlapGraphs()
  {exerciseOutputGraph("organization")}
  Void testUtilitySharedSourcesAndCompatibilityAliasesRemainOwned()
  {exerciseOutputGraph("utility");exerciseOutputGraph("alias")}
  Void testDiagnosticLimitAndNearFullFailureDoNotLoseOwnership()
  {exerciseOutputGraph("own",100);exerciseOutputGraph("organization",24,true)}
  Void testWorkingOutputOwnsTwoBinsWithoutUnusedPeriodSeries()
  {exerciseOutputGraph("working")}
  Void testSpaceFocusSummaryDoesNotMaterializeUnusedHourlyReport()
  {exerciseOutputGraph("summary")}
  Void testFocusSummaryKeepsOriginalOwnTotalsAndCoverage()
  {
    exercise(query,records,false,false,"kWh",true)
    exercise(query,records,false,true,"kWh",true)
    rs:=records;rs.last["pointId"]="pa";exercise(query,rs,false,false,"Wh",true)
  }
  Void testSharedModelReportsKeepMetadataAliveUntilOutputExpiry()
  {
    exercise(query,records,false,false,"kWh",false,true)
    exercise(query,records,false,false,"kWh",true,true)
    rs:=records
    rs.add(["id":"tariff","kind":"tariff","categoryId":"c","isDefault":true,"mode":"flat","rate":0.735f,"rules":[["startHour":0,"endHour":1,"rate":1f]]])
    exercise(query.set("metric","cost"),rs,false,false,"kWh",false,true)
    exercise(query,records,true,false,"kWh",false,true)
  }
  Void test81FocusSummariesIncludeOwnedCanonicalCatalogInJointPeak()
  {exerciseOutputGraph("summaryShared")}
  Void testPooledScopeRetainsOnlyItsFinalDataAndClassAllowance()
  {exerciseOutputGraph("pooledScope")}

  Void testPooledScopeCountsRepeatedOutputReferencesOnlyOnce()
  {exerciseOutputGraph("pooledIdentity")}

  private Void exerciseOutputGraph(Str mode,Int hours := 24,Bool failFinish := false)
  {
    start:=DateTime.fromIso("2026-01-01T00:00:00Z");end:=start+Duration(hours*1hr.ticks)
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"]];ids:=Str[,]
    for(i:=0;i<18;i++) {ids.add("m$i");rs.add(["id":"m$i","kind":"meter","categoryId":"c","pointId":"p$i"])}
    dimension:="metering";kind:="daily";area:=false
    if(mode=="working") {kind="workingDays";rs.add(["id":"cal","kind":"calendar","workDays":[1,2,3,4,5]])}
    summaryOnly:=mode.startsWith("summary")
    if(mode.startsWith("pooled"))
    {dimension="space";kind="profile";ids=["scope"];rs.add(["id":"scope","kind":"space"]);rs.findAll |r| {r["kind"]=="meter"}.each |r| {r["spaceId"]="scope"}}
    if(mode=="space" || summaryOnly)
    {
      dimension="space";ids.clear
      spaces:=summaryOnly ? 81 : 10
      for(i:=0;i<spaces;i++) {ids.add("s$i");rs.add(["id":"s$i","kind":"space","parentId":i==0 ? null : "s"+(i-1),"area":100f])}
      rs.findAll |r| {r["kind"]=="meter"}.each |r| {r["spaceId"]="s"+(spaces-1)}
      if(summaryOnly) kind="profile"
    }
    if(mode=="organization")
    {
      dimension="organization";ids=["o","child"];area=true
      rs.add(["id":"o","kind":"organization"]);rs.add(["id":"child","kind":"organization","parentId":"o"])
      rs.add(["id":"building","kind":"space","area":100f,"nativeArea":["value":100f,"unit":"m²"]]);rs.add(["id":"floor","kind":"space","parentId":"building","area":40f])
      rs.findAll |r| {r["kind"]=="meter"}.each |r,i|
      {r["organizationId"]="child";r["areaSource"]="space";r["areaSpaceId"]=i%2==0 ? "building" : "floor";r["nativeArea"]=["value":10f,"unit":"m²"]}
    }
    if(mode=="utility" || mode=="alias")
    {
      kind="utility"
      rs.add(["id":"u","kind":"utility","categoryId":"c"]);rs.add(["id":"v","kind":"utility","categoryId":"c"])
      rs.findAll |r| {r["kind"]=="meter"}.each |r,i| {r["utilityId"]=i%2==0 ? "u" : "v"}
      rs.find |r| {r["id"]=="m1"}["pointId"]="p0"
      if(mode=="alias") rs.find |r| {r["id"]=="m1"}["canonicalId"]="m0"
    }
    for(i:=0;i<1000;i++) rs.add(["id":"unused$i","kind":"nativePoint","name":"Unselected point $i","nativeSourceId":"point$i","nativeSourceKind":"point","nativeTreeParentId":"folder","nativeHis":true,"unit":"kWh","siteRef":"site","equipRef":"unselected","nativeMod":"frozen","nativeDis":"Original point $i","writable":false,"nativePoint":true])
    gran:=mode.startsWith("pooled") ? "month" : "hour"
    q:=Str:Obj?["kind":kind,"nodeIds":ids,"dimension":dimension,"from":start.toIso,"to":end.toIso,"asOf":end.toIso,"tz":"UTC","period":gran,"metric":"energy","perArea":area]
    original:=rs.toStr
    streamBudget:=EnerCubixStreamBudget();budget:=streamBudget.state;state:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    sources:=EnerCubixCockpitStream[,]
    model:=mode=="summaryShared" ? EnerCubixPreparedOwner(budget) : null
    captureOwner:=mode.startsWith("pooled") ? EnerCubixPreparedOwner(budget) : null
    try
    {
      catalog:=model==null ? null : EnerCubixCockpitCatalog(rs.toImmutable,TimeZone.utc,model)
      dim:=catalog==null ? EnerCubixDimension(dimension,rs) : null
      ctx:=catalog==null ? EnerCubixContext(dim.records,[Str:Obj?][,],TimeZone.utc,dim) : EnerCubixContext.shared(catalog,dimension,false,state)
      if(catalog==null) ctx.useOwner(state)
      ctx.orderWarnings
      report:=EnerCubixReport(ctx,q,start,end,kind,gran,"energy",state,summaryOnly)
      EnerCubixLineCursor[] cursors:=kind=="utility" ? EnerCubixEndUse.resolve(ctx,ids).map |r->EnerCubixLineCursor| {report.openLine(r["id"].toStr,"c")} : ids.map |id->EnerCubixLineCursor| {report.openLine(id,"c")}
      capture:=captureOwner==null ? null : EnerCubixCockpitCapture(Str:[Str:Obj?]["scope":["kind":"sourceUsage","grain":"sourceRead","objectIds":ids,"sourceIds":rs.findAll |r| {r["kind"]=="meter"}.map |r->Str| {r["pointId"].toStr},"sourceIdsComplete":true,"requestRange":["from":start.toIso,"to":end.toIso,"asOf":end.toIso]]],captureOwner)
      consumer:=EnerCubixReportConsumer(ctx,report,cursors,start,end,gran,state,output,capture,capture==null ? null : "scope")
      if(mode=="pooledIdentity")
      {
        scratch:=EnerCubixPreparedOwner(budget);scratch.hold(64);seen:=Int:Obj[][:]
        counter:=EnerCubixReportConsumer#.method("retainedEntries")
        measure:=|Obj graph->Int| {args:=counter.params.size==2 ? Obj?[graph,100] : Obj?[graph,100,seen,scratch];return (Int)counter.callOn(consumer,args)}
        shared:=Str["a","b"];graph:=Str:Obj?["left":shared,"right":shared]
        verifyEq(measure(graph),6,"one map and one shared list, not two equal-looking copies")
        seen.each |bucket| {bucket.clear};seen.clear
        verifyEq(measure(Str:Obj?["left":Str["a","b"],"right":Str["a","b"]]),9,"distinct equal containers each occupy storage")
        seen.each |bucket| {bucket.clear};seen.clear
        unrelated:=Str:Obj?["other":1];scratch.hold(3);seen[Env.cur.idHash(graph)]=Obj[unrelated]
        verifyEq(measure(graph),6,"a colliding identity bucket must not merge a distinct object")
        seen.each |bucket| {bucket.clear};seen.clear
        cycle:=Str:Obj?[:];cycle["self"]=cycle
        verifyEq(measure(cycle),2,"one cyclic container still has one physical allocation");cycle.clear
        seen.each |bucket| {bucket.clear};seen.clear
        peer:=EnerCubixPreparedOwner(budget);peer.hold(budget.remaining);held:=peer.entries
        verifyEq(measure(graph),100,"no memo room retains the original envelope cap without allocation failure")
        verifyEq(peer.entries,held);peer.close;scratch.close
      }
      verify(budget.peak.val<=200000)
      verify(cursors.all |cursor| {cursor.watermark==start})
      verifyEq(budget.unprepared.val,0)
      read:=|Dict point,Span span,|HisItem| sink|
      {(0..hours).each |i| {ts:=start+Duration(i*1hr.ticks);if(ts>=span.start && ts<span.end) sink(HisItem(ts,Number(1)))}}
      rs.findAll |r| {r["kind"]=="meter"}.map |r->Str| {r["pointId"].toStr}.unique.each |Str pointId|
      {
        point:=Etc.makeDict(["id":Ref(pointId),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])
        sources.add(EnerCubixCockpitStream.openCursor(point,null,start,end,q,rs,streamBudget,read,ctx))
      }
      for(i:=0;i<hours;i++)
      {
        next:=start+Duration((i+1)*1hr.ticks);sources.each |source| {source.advance(next)}
        EnerCubixCockpitStream.withFrames(sources,budget) |hs,frame| {consumer.addFrame(hs,frame)}
      }
      if(failFinish)
      {
        peer:=EnerCubixPreparedOwner(budget);peer.hold(budget.remaining);held:=peer.entries
        verifyErr(EnerCubixHttpErr#) {consumer.finish};verifyErr(EnerCubixHttpErr#) {consumer.finish}
        sources.each |source| {source.close};state.close;output.close;model?.close;verifyEq(budget.temporary.val,held)
        peer.close;verifyEq(budget.temporary.val,0);verifyEq(rs.toStr,original);return
      }
      actual:=consumer.finish
      if(mode=="retired")
      {
        ["firstMeters","lastMeters","meters","covers","daily","working"].each |field|
        {value:=EnerCubixReportConsumer#.field(field).get(consumer);verify(value is Map ? ((Map)value).isEmpty : ((List)value).isEmpty,"finished reduction roots must be severed: $field")}
        verifyEq(consumer.childStateEntries,0,"retired child owners must leave the work census")
      }
      if(capture!=null) capture.freeze
      if(summaryOnly)
      {
        verify(report.frameLedger(cursors.map |c->EnerCubixLine| {c.line}).isEmpty)
        verify(!actual.containsKey("series"));verify(!actual.containsKey("rows"))
        ["totals","knownTotals"].each |field|
        {xs:=EnerCubixMath.maps(((Map)actual["summary"])[field]);verifyEq(xs.size,81);verify(xs.all |x| {x["value"]==432f && ((List)x["sourceIds"]).size==18})}
        verify(((EnerCubixPeriodConsumer[])EnerCubixReportConsumer#.field("periods").get(consumer)).all |p| {p.periods.isEmpty})
        verify(((Map)EnerCubixReportConsumer#.field("evidence").get(consumer)).isEmpty)
      }
      if(hours==100) {known:=(Map)((Map)actual["extra"])["knownUsage"];verifyEq(((List)known["sourceUsage"]).size,1000);verifyEq(known["sourceUsageRowCount"],1800)}
      if(mode=="space") verifyEq(EnerCubixMath.maps(((Map)actual["extra"])["details"]).size,180)
      if(mode=="organization")
      {verify(!((List)cursors.first.line.normalizationArea["excludedOverlaps"]).isEmpty);verifyEq(cursors.first.line.normalizationArea["value"],100f)}
      // Count retained data containers once by identity, excluding only input
      // catalog graphs. Include capture and frozen rows, not just the JSON root.
      seen:=Obj[,];borrowed:=(Obj[])EnerCubixReportConsumer#.field("borrowed").get(consumer)
      excluded:=capture==null ? borrowed : borrowed.dup.addAll(capture.protectedRoots)
      roots:=Obj?[actual,borrowed]
      ["consumedPeriods","consumedMeters","consumedCoverage","consumedEvidence","consumedDaily","consumedWorking"].each |field| {roots.add(EnerCubixReport#.field(field).get(report))}
      ["evidence","frozenMeters"].each |field| {roots.add(EnerCubixReportConsumer#.field(field).get(consumer))}
      cursors.each |cursor| {roots.add(cursor.line.consumedTotals);roots.add(cursor.line.normalizationArea)}
      ((EnerCubixPeriodConsumer[])EnerCubixReportConsumer#.field("periods").get(consumer)).each |period| {roots.add(EnerCubixPeriodConsumer#.field("totals").get(period))}
      sources.each |source| {source.close};state.close
      owned:=roots.reduce(0) |Int n,root->Int| {n+outputEntries(root,excluded,seen)}
      verify(output.entries>=owned,"output admission must cover every retained data entry")
      captured:=captureOwner?.entries ?: 0
      if(capture!=null) ((Str:EnerCubixCockpitCaptureGroup)EnerCubixCockpitCapture#.field("groups").get(capture)).each |group| {group.cells.each |cell| {captured+=cell.owner.entries}}
      verify(budget.peak.val<=200000);verifyEq(budget.temporary.val,output.entries+(model?.entries ?: 0)+captured)
      echo("DAILY_OUTPUT_GRAPH mode="+mode+" hours="+hours+" retained="+owned+" admitted="+output.entries+" model="+(model?.entries ?: 0)+" peak="+budget.peak.val)
      if(capture!=null)
      {
        peer:=EnerCubixPreparedOwner(budget)
        try
        {
          // Leave 6500 entries for this detached report while admitting the
          // next consumer. Existing pooled evidence keeps its separate owners.
          peer.hold(budget.remaining+output.entries-6500)
          verifyEq(EnerCubixMath.maps(((Map)actual["summary"])["totals"]).first["value"],432f)
          verify(output.entries>=owned);verifyEq(rs.toStr,original)
        }
        finally {peer.close}
      }
    }
    finally {sources.each |source| {source.close};state.close;output.close;captureOwner?.close;model?.close}
    verifyEq(budget.temporary.val,0)
    verifyEq(rs.toStr,original)
  }

  private Int outputEntries(Obj? value,Obj[] borrowed,Obj[] seen)
  {
    if(value isnot Map && value isnot List && value isnot EnerCubixValue) return 0
    if(borrowed.any |v| {v === value}) return 0
    if(seen.any |v| {v === value}) return 0
    seen.add(value)
    if(value is EnerCubixValue) return 3+outputEntries(((EnerCubixValue)value).sources,borrowed,seen)
    if(value is Map) return ((Map)value).vals.reduce(1+((Map)value).size) |Int n,v->Int| {n+outputEntries(v,borrowed,seen)}
    return ((List)value).reduce(1+((List)value).size) |Int n,v->Int| {n+outputEntries(v,borrowed,seen)}
  }

  Void test82SourcesRetainFullMonthlyReportAndBoundedEvidence()
  {
    start:=DateTime.fromIso("2026-01-01T00:00:00Z");end:=start+1000hr
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"g","kind":"group"]]
    samples:=[Str:Obj?][,]
    for(i:=0;i<1000;i++) samples.add(["ts":(start+Duration(i*1hr.ticks)).toIso,"value":1f])
    whole:=[Str:Obj?][,]
    for(i:=0;i<82;i++)
    {
      rs.add(["id":"m$i","kind":"meter","pointId":"p$i","parentId":"g","categoryId":"c"])
      whole.add(["pointId":"p$i","mode":"interval","unit":"kWh","samples":samples])
    }
    q:=Str:Obj?["kind":"profile","nodeIds":["g"],"from":start.toIso,"to":end.toIso,"asOf":end.toIso,"tz":"UTC","period":"month","metric":"energy"]
    expected:=EnerCubixEngine.report(q,rs,whole)
    budget:=EnerCubixStreamBudget();state:=EnerCubixPreparedOwner(budget.state);output:=EnerCubixPreparedOwner(budget.state)
    ctx:=EnerCubixContext(rs,[Str:Obj?][,],TimeZone.utc);ctx.useOwner(state);ctx.orderWarnings
    report:=EnerCubixReport(ctx,q,start,end,"profile","month","energy",state)
    consumer:=EnerCubixReportConsumer(ctx,report,[report.openLine("g","c")],start,end,"month",state,output)
    read:=|Dict p,Span span,|HisItem| sink|
    {
      n:=((span.start-start).ticks/1hr.ticks).max(0);ts:=start+Duration(n*1hr.ticks)
      while(ts<span.end && ts<=end) {if(ts>=span.start) sink(HisItem(ts,Number(1)));ts+=1hr}
    }
    sources:=EnerCubixCockpitStream[,]
    for(i:=0;i<82;i++)
    {
      point:=Etc.makeDict(["id":Ref("p$i"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])
      sources.add(EnerCubixCockpitStream.openCursor(point,null,start,end,q,rs,budget,read,ctx))
    }
    retained:=0
    for(i:=0;i<1000;i++)
    {
      finish:=start+Duration((i+1)*1hr.ticks);sources.each |source| {source.advance(finish)}
      EnerCubixCockpitStream.withFrames(sources,budget.state) |histories,frame| {consumer.addFrame(histories,frame)}
      if(i==0) retained=state.entries
      else verifyEq(state.entries,retained)
    }
    actual:=consumer.finish
    ["summary","series","rows","warnings"].each |key| {verifyEq(actual[key],expected[key],key)}
    a:=(Map)actual["extra"];e:=(Map)expected["extra"]
    verifyEq(a["usageCoverage"],e["usageCoverage"])
    known:=(Map)a["knownUsage"];verifyEq(((List)known["sourceUsage"]).size,1000)
    verifyEq(known["sourceUsageRowCount"],82000);verifyEq(known["sourceUsageTruncated"],true)
    verifyEq(budget.state.unprepared.val,0);verify(budget.state.peak.val<200000)
    echo("FULL_REPORT_82 "+budget.evidence.toStr+" state="+budget.state.evidence.toStr)
    sources.each |source| {source.close};state.close
    verifyEq(actual["summary"],expected["summary"]);verifyEq(budget.state.temporary.val,output.entries)
    output.close;verify(actual.isEmpty);verifyEq(budget.state.temporary.val,0)
  }

  private Void exercise(Str:Obj? q,[Str:Obj?][] rs,Bool failFinish := false,Bool empty := false,Str sourceUnit := "kWh",Bool summaryOnly := false,Bool sharedCatalog := false)
  {
    inputBefore:=rs.toStr
    points:=Str:Dict[:]
    ["pt","pa","pb"].each |id| {points[id]=Etc.makeDict(["id":Ref(id),"his":Marker.val,"hisTotalized":Marker.val,"unit":sourceUnit,"tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":Etc.makeDict(["defNull":Marker.val])])}
    cfg:=Etc.makeDict(["defNull":Marker.val]);configs:=Str:Dict[:];points.each |p,id| {configs[id]=cfg}
    read:=|Dict p,Span span,|HisItem| sink|
    {
      if(empty) return
      values:=p.id.id == "pt" ? Obj?[0,10000000000000000f,10000000000000000f,10000000000000002f,10000000000000004f] :
        (p.id.id == "pa" ? Obj?[0,10,NA.val,30,40] : Obj?[0,20,40,60,80])
      values.each |value,i| {ts:=at+Duration(i*1hr.ticks);if(ts>=span.start && ts<span.end) sink(HisItem(ts,value is Int ? Number((Int)value) : (value is Float ? Number((Float)value) : value)))}
    }
    whole:=EnerCubixCockpitStream.prepare(q,rs,points,configs,read,EnerCubixStreamBudget())
    expected:=EnerCubixEngine.report(q,rs,whole)
    budget:=EnerCubixStreamBudget();state:=EnerCubixPreparedOwner(budget.state);output:=EnerCubixPreparedOwner(budget.state)
    model:=sharedCatalog ? EnerCubixPreparedOwner(budget.state) : null
    catalog:=model==null ? null : EnerCubixCockpitCatalog(rs.toImmutable,TimeZone.utc,model)
    dimension:=catalog==null ? EnerCubixDimension("space",rs,true) : null
    ctx:=catalog==null ? EnerCubixContext(dimension.records,[Str:Obj?][,],TimeZone.utc,dimension) : EnerCubixContext.shared(catalog,"space",true,state)
    if(catalog==null) ctx.useOwner(state)
    ctx.orderWarnings
    queryEnd:=DateTime.fromIso(q["to"].toStr)
    report:=EnerCubixReport(ctx,q,at,queryEnd,q["kind"].toStr,"month",q["metric"].toStr,state,summaryOnly)
    cursors:=EnerCubixLineCursor[,]
    if(q["kind"]=="utility") EnerCubixEndUse.resolve(ctx,EnerCubixMath.strings(q["nodeIds"])).each |meter| {cursors.add(report.openLine(meter["id"].toStr,meter["categoryId"] as Str ?: ""))}
    else EnerCubixMath.strings(q["nodeIds"]).each |id| {ctx.categories(id).each |category| {cursors.add(report.openLine(id,category))}}
    consumer:=EnerCubixReportConsumer(ctx,report,cursors,at,queryEnd,"month",state,output)
    if(catalog!=null) verify(EnerCubixReportConsumer#.field("borrowed").get(consumer)===catalog.protectedRoots)
    sources:=EnerCubixCockpitStream[,]
    points.keys.sort.each |id| {sources.add(EnerCubixCockpitStream.openCursor(points[id],configs[id],at,queryEnd,q,rs,budget,read,ctx))}
    for(i:=0;i<4;i++)
    {
      end:=at+Duration((i+1)*1hr.ticks);sources.each |source| {source.advance(end)}
      EnerCubixCockpitStream.withFrames(sources,budget.state) |histories,frame| {consumer.addFrame(histories,frame)}
      verify(ctx.byPoint.isEmpty)
    }
    if(failFinish)
    {
      peer:=EnerCubixPreparedOwner(budget.state);peer.hold(budget.state.remaining);held:=peer.entries
      verifyErr(EnerCubixHttpErr#) {consumer.finish}
      verifyErr(EnerCubixHttpErr#) {consumer.finish}
      sources.each |source| {source.close};state.close;output.close;model?.close
      verifyEq(budget.state.temporary.val,held);peer.close;verifyEq(budget.state.temporary.val,0)
      verifyEq(rs.toStr,inputBefore);return
    }
    actual:=consumer.finish
    label:=q["kind"].toStr
    if(summaryOnly)
    { ["totals","knownTotals"].each |key| {verifyEq(((Map)actual["summary"])[key],((Map)expected["summary"])[key],key)} }
    else ["summary","series","rows","warnings"].each |key| {verifyEq(actual[key],expected[key],"$label : $key")}
    a:=(Map)actual["extra"];e:=(Map)expected["extra"]
    if(summaryOnly) {verifyEq(a["usageCoverage"],e["usageCoverage"]);verifyEq(a.keys.sort,["relationBasis","usageCoverage"])}
    else
    {
      e.keys.findAll |key| {key != "knownUsage"}.each |key| {verifyEq(a[key],e[key],"$label : extra/$key")}
      actualKnown:=((Map)a["knownUsage"]).dup;expectedKnown:=((Map)e["knownUsage"]).dup
      if(expectedKnown.containsKey("sourceUsageCaptureId"))
      {verify(actualKnown["sourceUsageCaptureId"] is Str);actualKnown.remove("sourceUsageCaptureId");expectedKnown.remove("sourceUsageCaptureId")}
      verifyEq(actualKnown,expectedKnown)
    }
    verifyEq(budget.state.unprepared.val,0)
    cursors.each |cursor| {verify(cursor.line.ticks.isEmpty)}
    escapedRows:=(List)(summaryOnly ? ((Map)actual["summary"])["totals"] : actual["rows"]);escapedRow:=(Map)escapedRows.first;escapedArea:=cursors.first.line.normalizationArea
    sources.each |source| {source.close};state.close
    if(summaryOnly) verifyEq(((Map)actual["summary"])["totals"],((Map)expected["summary"])["totals"])
    else verifyEq(actual["summary"],expected["summary"])
    verifyEq(budget.state.temporary.val,output.entries+(model?.entries ?: 0))
    if(model!=null) verifyErr(ArgErr#) {model.close}
    output.close;verify(actual.isEmpty);verify(escapedRows.isEmpty);verify(escapedRow.isEmpty)
    verify(escapedArea.isEmpty)
    model?.close
    verifyEq(rs.toStr,inputBefore);verifyEq(budget.state.temporary.val,0)
    verifyErr(ArgErr#) {consumer.finish}
  }

  private [Str:Obj?][] records()
  {
    [["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space","nativeSourceKind":"site","area":100f],
     ["id":"t","kind":"totalMeter","pointId":"pt","categoryId":"c","spaceId":"s","nativeSpaceId":"s","area":100f],
     ["id":"a","kind":"meter","pointId":"pa","categoryId":"c","spaceId":"s","nativeSpaceId":"s","meterParentId":"t","area":10f],
     ["id":"b","kind":"meter","pointId":"pb","categoryId":"c","spaceId":"s","nativeSpaceId":"s","meterParentId":"t","area":20f]]
  }
  private Str:Obj? query() {["kind":"profile","nodeIds":["s","a"],"from":at.toIso,"to":(at+4hr).toIso,"asOf":(at+4hr).toIso,"tz":"UTC","period":"month","metric":"energy","dimension":"space","spaceSource":"fin"]}
  private DateTime at() {DateTime.fromIso("2026-01-31T23:00:00Z")}
}

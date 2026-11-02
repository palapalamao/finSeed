using haystack
using util

class EnerCubixRegistryCopTest : Test
{
  Void testEightModulesAndTwentyCopConfigurationsReleaseEachDerivedFrame()
  {
    a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+2hr
    rs:=[Str:Obj?][["id":"cn","kind":"category","unit":"MWh"],["id":"cd","kind":"category","unit":"kWh","co2Factor":0.5f],["id":"s","kind":"space","nativeSourceKind":"site","area":1000f],["id":"ng","kind":"space","nativeSourceKind":"floor","parentId":"s"],["id":"dg","kind":"space","nativeSourceKind":"floor","parentId":"s"],["id":"cal","kind":"calendar","isDefault":true,"workDays":[1,2,3,4,5],"workHours":[8,9,10,11,12,13,14,15,16]],["id":"tariff","kind":"tariff","categoryId":"cd","isDefault":true,"mode":"flat","rate":1f]]
    points:=Str:Dict[:];units:=Str:Str[:]
    ["n","d"].each |side|
    {
      (0..<10).each |i|
      {
        id:=side+i;point:="p"+id;unit:=side=="n" ? "MWh" : "kWh"
        rs.add(["id":id,"kind":"meter","categoryId":side=="n" ? "cn" : "cd","pointId":point,"nativeEquip":true,"nativeTreeParentId":side+"g","nativeSpaceId":side+"g","spaceId":side+"g","areaSource":"space","areaSpaceId":"s"])
        units[point]=unit;points[point]=Etc.makeDict(["id":Ref(point),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":unit,"tz":"UTC"])
      }
    }
    (0..<20).each |i| {rs.add(["id":"cop"+i,"kind":"cop","numeratorId":"ng","denominatorId":"dg"])}
    q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"space","spaceSource":"fin","nodeIds":["s"],"categoryIds":["cd"],"_cockpitCategoryId":"cd","period":"day","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC"]
    read:=|Dict point,Span span,|HisItem| sink| {(0..2).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(point.id.id.startsWith("pn") ? 0.1f : 10f)))}}
    cop:=EnerCubixCockpitEfficiency.prepare(q,rs,"cubeTest",["cd","cn"])
    flow:=EnerCubixCockpitFlow.prepare(q,rs,"cubeTest",true)
    boundary:=Str:Obj?["id":"boundary","meterIds":(0..<10).map |i->Str| {"d"+i},"sourcePointIds":(0..<10).map |i->Str| {"pd"+i}]
    expectedReports:=Str:Obj?[:];expectedModules:=Str:Obj?[:]
    EnerCubixCockpitEfficiency.attach(cop,EnerCubixCockpitStream.prepare(q,rs,points,[:],read,EnerCubixStreamBudget()),boundary,expectedReports,expectedModules)
    budget:=EnerCubixStreamBudget()
    registry:=EnerCubixCockpitRegistry(q.toImmutable,rs.toImmutable,boundary.toImmutable,["kpis","trend","space","time","endUse","organization","balance","efficiency"],["mode":"none"],null,[:],budget,units,points.keys,[:],flow.toImmutable,cop.toImmutable)
    sources:=EnerCubixCockpitStream[,]
    try
    {
      verifyEq(budget.nativeReads,0)
      points.keys.sort.each |id| {sources.add(EnerCubixCockpitStream.openCursor(points[id],null,a,b,q,rs,budget,read,registry.planning))}
      (0..<2).each |i|
      {
        start:=a+1hr*i;end:=start+1hr;sources.each |source| {source.advance(end)}
        EnerCubixCockpitStream.withFrames(sources,budget.state) |h,frame|
        {
          registry.addFrame(start,end,h,frame)
          verify(!registry.planning.byPoint.isEmpty,"The original source frame is still active")
          ((Map)EnerCubixCockpitRegistry#.field("works").get(registry)).each |work|
          {
            report:=work.typeof.field("report").get(work)
            context:=(EnerCubixContext)EnerCubixReport#.field("ctx").get(report)
            verify(context.byPoint.isEmpty,"Consumed report caches expire before the producer frame")
          }
          ((Map)EnerCubixCockpitRegistry#.field("copWorks").get(registry)).each |work|
          {
            consumer:=work.typeof.field("consumer").get(work)
            context:=(EnerCubixContext)EnerCubixCopConsumer#.field("ctx").get(consumer)
            verify(context.byPoint.isEmpty,"Consumed COP caches expire before the next configuration")
          }
        }
      }
      sources.each |source| {source.close};registry.finish
      actualReports:=Str:Obj?[:];actualModules:=Str:Obj?[:]
      EnerCubixCockpitEfficiency.attach(cop,[Str:Obj?][,],boundary,actualReports,actualModules,|Str id->Str:Obj?| {registry.copData(id)})
      verifyEq(json(actualReports),json(expectedReports));verifyEq(json(actualModules),json(expectedModules))
      verifyEq(actualReports.size,20);verifyEq(budget.nativeReads,20);verifyEq(budget.state.unprepared.val,0)
      verifyEq(registry.read("energy-flow",(Str:Obj?)flow["request"])["kind"],"energyFlow")
      verify((Int)registry.diagnostics["returnedCount"]<=1000)
      echo("COP_EIGHT_MODULES "+budget.state.evidence)
    }
    finally {sources.each |source| {source.close};registry.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
  Void testPreparedCopRoutesKeepOriginalQuantitiesReportsAndAliasContext()
  {
    [0,1,2].each |variant|
    {
      a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+2hr
      rs:=[Str:Obj?][["id":"cn","kind":"category","unit":"MWh"],["id":"cd","kind":"category","unit":"kWh"],["id":"s","kind":"space","nativeSourceKind":"site"],["id":"n","kind":"meter","name":"Cooling","categoryId":"cn","pointId":"pn","spaceId":"s"],["id":"d","kind":"meter","name":"Electricity","categoryId":"cd","pointId":"pd","spaceId":"s"],["id":"cop","kind":"cop","name":"System COP","numeratorId":variant==0 ? "n" : "alias","denominatorId":"d"]]
      if(variant>0) {alias:=Str:Obj?["id":"alias","kind":"meter","name":"Legacy cooling","canonicalId":"n","categoryId":"cn","pointId":"pn","spaceId":"s"];if(variant==2) alias["configurationError"]="invalidPrimaryPoint";rs.add(alias)}
      q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"space","nodeIds":["s"],"categoryIds":["cd"],"_cockpitCategoryId":"cd","period":"hour","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC"]
      prepared:=EnerCubixCockpitEfficiency.prepare(q,rs,"cubeTest",["cd","cn"])
      points:=Str:Dict[:]
      ["pn","pd"].each |id| {points[id]=Etc.makeDict(["id":Ref(id),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":id=="pn" ? "MWh" : "kWh","tz":"UTC"])}
      read:=|Dict point,Span span,|HisItem| sink| {(0..2).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(point.id.id=="pn" ? 0.1f*i : 10f*i*i)))}}
      histories:=EnerCubixCockpitStream.prepare(q,rs,points,[:],read,EnerCubixStreamBudget())
      boundary:=Str:Obj?["id":"boundary","meterIds":["d"],"sourcePointIds":["pd"]]
      expectedReports:=Str:Obj?[:];expectedModules:=Str:Obj?[:];EnerCubixCockpitEfficiency.attach(prepared,histories,boundary,expectedReports,expectedModules)
      budget:=EnerCubixStreamBudget()
      registry:=EnerCubixCockpitRegistry(q.toImmutable,rs.toImmutable,boundary.toImmutable,["trend","efficiency"],["mode":"none"],null,[:],budget,["pn":"MWh","pd":"kWh"],points.keys,[:],[:],prepared.toImmutable)
      sources:=EnerCubixCockpitStream[,]
      try
      {
        verifyEq(budget.nativeReads,0);verify(registry.keys.contains("cop:cop"))
        verifyErr(ArgErr#) {registry.copData("cop")}
        points.keys.sort.each |id| {sources.add(EnerCubixCockpitStream.openCursor(points[id],null,a,b,q,rs,budget,read,registry.planning))}
        (0..<2).each |i| {start:=a+1hr*i;end:=start+1hr;sources.each |source| {source.advance(end)};EnerCubixCockpitStream.withFrames(sources,budget.state) |h,frame| {registry.addFrame(start,end,h,frame)}}
        sources.each |source| {source.close};registry.finish
        actualReports:=Str:Obj?[:];actualModules:=Str:Obj?[:]
        // No history is supplied to this projection. A fallback would change
        // the available values and fail the complete original result comparison.
        EnerCubixCockpitEfficiency.attach(prepared,[Str:Obj?][,],boundary,actualReports,actualModules,|Str id->Str:Obj?| {registry.copData(id)})
        verifyEq(json(actualReports),json(expectedReports));verifyEq(json(actualModules),json(expectedModules))
        report:=registry.read("cop:cop",EnerCubixCockpitReports.copQuery(q,"cop"));verify(report===actualReports["cop:cop"])
        verifyErr(ArgErr#) {registry.read("cop:cop",EnerCubixCockpitReports.copQuery(q,"different"))}
        verifyErr(ArgErr#) {registry.copData("different")}
        verifyEq(budget.nativeReads,2);verifyEq(budget.state.unprepared.val,0)
        entries:=EnerCubixMath.maps(registry.diagnostics["entries"])
        verify(!entries.any |entry| {EnerCubixMath.strings(entry["reportRefs"]).contains("cop:cop")},"COP does not fabricate known-usage diagnostics")
        profile:=registry.read("profile-energy",q)
        known:=(Map)((Map)profile["extra"])["knownUsage"]
        diagnostic:=entries.find |entry| {entry["id"]==known["sourceUsageDiagnosticRef"]}
        verifyEq(diagnostic["sourceIdsComplete"],true)
        EnerCubixMath.maps(known["sourceUsage"]).each |row|
        {verify(EnerCubixMath.strings(diagnostic["sourceIds"]).contains(row["pointId"]),"Every retained own-primary detail must be declared in the diagnostic source set")}
        registry.close;verify(report.isEmpty)
      }
      finally {sources.each |source| {source.close};registry.close}
      verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
    }
  }
  Void testUnconfiguredAndFailedOptionalPlansDeclareNoCopReport()
  {
    a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+1hr
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c"]]
    q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"metering","nodeIds":["m"],"categoryIds":["c"],"_cockpitCategoryId":"c","period":"hour","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC"]
    prepared:=EnerCubixCockpitEfficiency.prepare(q,rs,"cubeTest",["c"])
    [prepared,Str:Obj?["error":true]].each |plan|
    {
      budget:=EnerCubixStreamBudget();registry:=EnerCubixCockpitRegistry(q.toImmutable,rs.toImmutable,Str:Obj?["id":"boundary","meterIds":["m"],"sourcePointIds":["p"]].toImmutable,["trend","efficiency"],["mode":"none"],null,[:],budget,[:],["p"],[:],[:],plan.toImmutable)
      try {verifyEq(registry.keys,["profile-energy"]);verifyEq(budget.nativeReads,0);verifyErr(ArgErr#) {registry.copData("anything")}}
      finally {registry.close}
      verifyEq(budget.state.temporary.val,0)
    }
  }
  private Obj? json(Obj? value) {JsonInStream(JsonOutStream.writeJsonToStr(value).in).readJson}
}

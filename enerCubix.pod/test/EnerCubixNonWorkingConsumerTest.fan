using haystack

class EnerCubixNonWorkingConsumerTest : Test
{
  Void testZeroPartialLongFilteredSubstitutedNaAndCalendarConditionsMatchOriginal()
  {
    (0..<10).each |variant|
    {
      a:=DateTime.fromIso("2026-10-01T00:00:00Z");b:=a+2hr
      calendar:=Str:Obj?["id":"cal","kind":"calendar","workDays":[1,2,3,4,5],"workHours":[9,10,11,12,13,14,15,16,17],"exceptions":[Str:Obj?][,]]
      if(variant==6) calendar["workHours"]=["invalid"]
      if(variant==8 || variant==9) calendar["workHours"]=(0..<24).toList
      if(variant==9) calendar["exceptions"]=[["date":"2026-10-01","working":false]]
      rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space","nativeSourceKind":"site"],["id":"m","kind":"meter","categoryId":"c","pointId":"p","spaceId":"s"],calendar]
      from:=variant==5 ? a+30min : a;to:=variant==5 ? b-30min : b
      q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"space","nodeIds":["s"],"categoryIds":["c"],"_cockpitCategoryId":"c","period":"day","from":from.toIso,"to":to.toIso,"asOf":to.toIso,"tz":"UTC","_cockpitNeedsRuleFacts":true]
      profile:=Str:Obj?["id":"rule","version":1,"name":"Night usage","scopeKind":"project","scopeRef":"p:test","categoryRef":"c","calendarRef":"cal","ruleType":"nonWorkingHighUsage","threshold":50f,"thresholdUnit":variant==7 ? "degC" : "kWh","enabled":true]
      boundary:=Str:Obj?["id":"boundary","meterIds":["m"],"sourcePointIds":["p"],"aggregateAllowed":true]
      owned:=Str:Obj?["rules":[profile],"rulesComplete":true,"modelComplete":true,"projectRef":"p:test"]
      raw:=[HisItem(a,Number(0)),HisItem(a+1hr,Number(variant==0 ? 0 : 30)),HisItem(b,Number(variant==0 ? 0 : 110))]
      if(variant==1) raw.removeAt(1)
      cfg:=Etc.makeDict(variant==3 || variant==4 ? ["defVal":variant==3 ? Number(20) : NA.val,"deltaMax":Number(50)] : ["defNull":Marker.val,"deltaMax":Number(variant==2 ? 50 : 10000)])
      point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":cfg])
      read:=|Dict p,Span span,|HisItem| sink| {raw.each |row| {if(row.ts>=span.start && row.ts<span.end) sink(row)}}
      hs:=EnerCubixCockpitStream.prepare(q,rs,["p":point],["p":cfg],read,EnerCubixStreamBudget())
      budgetResult:=EnerCubixBudgetMath.unavailable("BUDGET_NOT_CONFIGURED")
      expected:=EnerCubixCockpitRules.project(q,rs,hs,owned,boundary,budgetResult,"snapshot")
      budget:=EnerCubixStreamBudget();model:=EnerCubixPreparedOwner(budget.state);state:=EnerCubixPreparedOwner(budget.state);output:=EnerCubixPreparedOwner(budget.state);planning:=EnerCubixPreparedOwner(budget.state);peer:=EnerCubixPreparedOwner(budget.state)
      catalog:=EnerCubixCockpitCatalog(rs.toImmutable,TimeZone.utc,model,["p":"kWh"])
      consumer:=EnerCubixNonWorkingConsumer(q.toImmutable,profile.toImmutable,rs.toImmutable,boundary.toImmutable,catalog,state,output)
      source:=EnerCubixCockpitStream.openCursor(point,cfg,a,b,q,rs,budget,read,EnerCubixContext.shared(catalog,"space",false,planning))
      try
      {
        (0..<2).each |i| {start:=a+1hr*i;end:=start+1hr;source.advance(end);EnerCubixCockpitStream.withFrames([source],budget.state) |h,frame| {consumer.addFrame(start,end,h,frame)}}
        source.close;facts:=consumer.finish;state.close;planning.close
        actual:=EnerCubixCockpitRules.project(q,rs,[Str:Obj?][,],owned,boundary,budgetResult,"snapshot",|Str id->Str:Obj?| {return facts})
        verifyEq(actual,expected,variant.toStr);verifyEq(budget.state.unprepared.val,0)
        peer.hold(budget.state.remaining);held:=peer.entries;output.close;verifyEq(peer.entries,held);verify(facts.isEmpty)
      }
      finally {source.close;state.close;output.close;planning.close;model.close;peer.close}
      verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
    }
  }
  Void testActualHourlyFactsMatchOriginalRulesBeforeDiagnosticSampling()
  {
    // Different quotas retain different diagnostics, never different rule facts.
    [1000,1,0].each |quota|
    {
      a:=DateTime.fromIso("2026-10-01T00:00:00Z");b:=a+2hr
      rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space","nativeSourceKind":"site"],["id":"m","kind":"meter","categoryId":"c","pointId":"p","spaceId":"s"],["id":"cal","kind":"calendar","workDays":[1,2,3,4,5],"workHours":[9,10,11,12,13,14,15,16,17],"exceptions":[Str:Obj?][,]]]
      q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"space","nodeIds":["s"],"categoryIds":["c"],"_cockpitCategoryId":"c","period":"day","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC","_cockpitNeedsRuleFacts":true]
      profile:=Str:Obj?["id":"rule","version":1,"name":"Night usage","scopeKind":"project","scopeRef":"p:test","categoryRef":"c","calendarRef":"cal","ruleType":"nonWorkingHighUsage","threshold":0.05f,"thresholdUnit":"MWh","enabled":true]
      boundary:=Str:Obj?["id":"boundary","meterIds":["m"],"sourcePointIds":["p"],"aggregateAllowed":true]
      owned:=Str:Obj?["rules":[profile],"rulesComplete":true,"modelComplete":true,"projectRef":"p:test"]
      cfg:=Etc.makeDict(["defNull":Marker.val,"deltaMin":Number(0),"deltaMax":Number(10000)])
      point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":cfg])
      read:=|Dict p,Span span,|HisItem| sink| {[HisItem(a,Number(0)),HisItem(a+1hr,Number(30)),HisItem(b,Number(110))].each |row| {if(row.ts>=span.start && row.ts<span.end) sink(row)}}
      oldBudget:=EnerCubixStreamBudget();oldBudget.detailCount=1000-quota
      histories:=EnerCubixCockpitStream.prepare(q,rs,["p":point],["p":cfg],read,oldBudget)
      budgetResult:=EnerCubixBudgetMath.unavailable("BUDGET_NOT_CONFIGURED")
      expected:=EnerCubixCockpitRules.project(q,rs,histories,owned,boundary,budgetResult,"snapshot")
      budget:=EnerCubixStreamBudget();budget.detailCount=1000-quota
      model:=EnerCubixPreparedOwner(budget.state);state:=EnerCubixPreparedOwner(budget.state);output:=EnerCubixPreparedOwner(budget.state);planning:=EnerCubixPreparedOwner(budget.state)
      catalog:=EnerCubixCockpitCatalog(rs.toImmutable,TimeZone.utc,model,["p":"kWh"])
      consumer:=EnerCubixNonWorkingConsumer(q.toImmutable,profile.toImmutable,rs.toImmutable,boundary.toImmutable,catalog,state,output)
      ctx:=EnerCubixContext.shared(catalog,"space",false,planning)
      source:=EnerCubixCockpitStream.openCursor(point,cfg,a,b,q,rs,budget,read,ctx)
      try
      {
        (0..<2).each |i| {start:=a+1hr*i;end:=start+1hr;source.advance(end);EnerCubixCockpitStream.withFrames([source],budget.state) |h,frame| {consumer.addFrame(start,end,h,frame)}}
        source.close;facts:=consumer.finish;state.close
        actual:=EnerCubixCockpitRules.project(q,rs,[Str:Obj?][,],owned,boundary,budgetResult,"snapshot",|Str id->Str:Obj?| {verifyEq(id,"rule");return facts})
        verifyEq(actual,expected);verifyEq(EnerCubixMath.maps(actual["evaluations"]).first["actual"],80f)
        verifyEq(budget.nativeReads,1);verifyEq(budget.state.unprepared.val,0)
        output.close;verify(facts.isEmpty)
      }
      finally {source.close;state.close;output.close;planning.close;model.close}
      verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
    }
  }
}

using haystack
using util

class EnerCubixRegistryFlowTest : Test
{
  Void testUnavailableOptionalFlowDeclaresNoFallbackHistoryReport()
  {
    a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+1hr
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c"]]
    q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"metering","nodeIds":["m"],"categoryIds":["c"],"_cockpitCategoryId":"c","period":"day","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC"]
    budget:=EnerCubixStreamBudget()
    registry:=EnerCubixCockpitRegistry(q.toImmutable,rs.toImmutable,Str:Obj?["id":"boundary","meterIds":["m"],"sourcePointIds":["p"]].toImmutable,["trend","balance"],["mode":"none"],null,[:],budget,["p":"kWh"],["p"],[:],Str:Obj?["error":true].toImmutable)
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])
    source:=EnerCubixCockpitStream.openCursor(point,null,a,b,q,rs,budget,|Dict p,Span span,|HisItem| sink| {(0..1).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(10)))}},registry.planning)
    try
    {
      verify(!registry.keys.contains("energy-flow"))
      source.advance(b);EnerCubixCockpitStream.withFrames([source],budget.state) |h,frame| {registry.addFrame(a,b,h,frame)}
      source.close;registry.finish
      verifyEq(EnerCubixMath.maps(((Map)registry.read("profile-energy",q)["summary"])["totals"]).first["value"],10f)
      verifyErr(ArgErr#) {registry.read("energy-flow",q.dup.set("kind","energyFlow"))}
    }
    finally {source.close;registry.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
  Void testSharedFramesKeepFlowCatalogPermissionsAliasesAndFinalPoolFlags()
  {
    [0,1,2].each |variant|
    {
      a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+2hr
      rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"t","kind":"totalMeter","name":"T","pointId":"pt","categoryId":"c"],["id":"m","kind":"meter","name":"M","pointId":"pm","categoryId":"c","meterParentId":"t"]]
      if(variant==1) rs.add(["id":"hidden","kind":"meter","name":"Hidden","categoryId":"c","pointId":"ph","meterParentId":"t","_comparisonReadable":false])
      if(variant==2) {rs[1]["nativeEquip"]=true;rs[2]["nativeEquip"]=true;rs.add(["id":"old","kind":"meter","name":"Legacy","pointId":"pm","categoryId":"c","meterParentId":"t"])}
      q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"metering","nodeIds":["t"],"categoryIds":["c"],"_cockpitCategoryId":"c","_cockpitDiagnosticCapture":true,"_cockpitExplicitObjects":true,"period":"day","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC"]
      flowPlan:=EnerCubixCockpitFlow.prepare(q,rs,"cubeTest",true)
      flowQuery:=(Str:Obj?)flowPlan["request"]
      points:=Str:Dict[:]
      ["pt","pm"].each |id| {points[id]=Etc.makeDict(["id":Ref(id),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])}
      read:=|Dict point,Span span,|HisItem| sink|
      {(0..2).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(point.id.id=="pt" ? 10 : 4)))}}
      expected:=EnerCubixHistory.report(flowQuery,([Str:Obj?][])flowPlan["records"],EnerCubixCockpitStream.prepare(flowQuery,([Str:Obj?][])flowPlan["records"],points,[:],read,EnerCubixStreamBudget()))
      budget:=EnerCubixStreamBudget()
      scope:=EnerCubixCockpitRequestScope("registry-owned-flow-"+variant,"a",budget)
      registry:=EnerCubixCockpitRegistry(q.toImmutable,rs.toImmutable,Str:Obj?["id":"boundary","meterIds":["t"],"sourcePointIds":["pt"]].toImmutable,["trend","balance"],["mode":"none"],null,[:],budget,["pt":"kWh","pm":"kWh"],points.keys,[:],flowPlan.toImmutable)
      sources:=EnerCubixCockpitStream[,]
      try
      {
        verifyEq(budget.nativeReads,0);verify(registry.keys.contains("energy-flow"))
        verifyErr(ArgErr#) {registry.read("energy-flow",flowQuery)}
        points.keys.sort.each |id| {sources.add(EnerCubixCockpitStream.openCursor(points[id],null,a,b,q,rs,budget,read,registry.planning))}
        (0..<2).each |i| {start:=a+1hr*i;end:=start+1hr;sources.each |s| {s.advance(end)};EnerCubixCockpitStream.withFrames(sources,budget.state) |h,frame| {registry.addFrame(start,end,h,frame)}}
        sources.each |s| {s.close};registry.finish
        result:=registry.read("energy-flow",flowQuery)
        if(variant==2)
        {
          registry.prepareReportBorrows(scope);result=registry.freezeReport("energy-flow",flowQuery,scope)
          verify(result.isImmutable)
          history:=(EnerCubixPreparedOwner?)EnerCubixCockpitRequestScope#.field("historyOwner").get(scope)
          verify(history!=null && history.entries>4,"completed flow facts must remain paid after their numeric/graph producer closes")
        }
        verifyEq(business(result),business(expected))
        rows:=EnerCubixMath.maps(((Map)((Map)result["extra"])["energyFlowOverview"])["rows"])
        verifyEq(rows.size,2)
        rows.each |row|
        {
          proof:=EnerCubixMath.maps(registry.diagnostics["entries"]).find |entry| {entry["id"]==row["periodsDiagnosticRef"]}
          verifyEq(proof["kind"],"coveragePeriods");verifyEq(proof["returnedCount"],((List)row["periods"]).size);verifyEq(row["periodRecordTotalCount"],2)
        }
        verifyErr(ArgErr#) {registry.read("energy-flow",flowQuery.dup.set("metric","cost"))}
        verifyEq(budget.state.unprepared.val,0);verify((Int)registry.diagnostics["returnedCount"]<=1000)
        scope.releaseReportBorrows;registry.close
        if(variant==2) {verifyEq(business(result),business(expected));verify(scope.frozenReport("energy-flow")===result)}
        else verify(result.isEmpty)
      }
      finally {sources.each |s| {s.close};scope.releaseReportBorrows;registry.close;scope.close}
      verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
    }
  }
  private Str:Obj? business(Str:Obj? report)
  {
    copy:=(Str:Obj?)JsonInStream(JsonOutStream.writeJsonToStr(report).in).readJson
    extra:=(Map)copy["extra"];extra.remove("knownUsage")
    overview:=(Map)extra["energyFlowOverview"];overview.remove("knownUsage")
    [EnerCubixMath.maps(copy["rows"]),EnerCubixMath.maps(overview["rows"])].each |rows|
    {rows.each |row| {["periods","periodsCaptureId","periodRecordTotalCount","periodsReturnedCount","periodsTruncated","periodsTruncationReason","periodsDiagnosticRef"].each |key| {row.remove(key)}}}
    return copy
  }
}

using haystack
using util

class FinEnergyReportFinishMetadataTest : Test
{
  Void testFinalizationUsesFrozenMembershipAndAreaInsteadOfWholeCatalogScratch()
  {
    [false,true].each |perArea|
    {
      a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+2hr
      rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":"space","name":"Site","area":100f,"areaUnit":"m²"],["id":"t","kind":"totalMeter","name":"T","pointId":"pt","categoryId":"c","spaceId":"s"],["id":"m","kind":"meter","name":"M","pointId":"pm","categoryId":"c","meterParentId":"t","spaceId":"s"]]
      (0..<900).each |i| {rs.add(["id":"unused"+i,"kind":"utility","name":"Unselected"+i])}
      q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"space","nodeIds":["s"],"categoryIds":["c"],"_cockpitCategoryId":"c","period":"day","perArea":perArea,"from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC"]
      points:=Str:Dict[:]
      ["pt","pm"].each |id| {points[id]=Etc.makeDict(["id":Ref(id),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"kWh","tz":"UTC"])}
      read:=|Dict point,Span span,|HisItem| sink|
      {(0..2).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(point.id.id=="pt" ? 10 : 4)))}}
      expected:=FinEnergyEngine.report(q,rs,FinEnergyCockpitStream.prepare(q,rs,points,[:],read,FinEnergyStreamBudget()))
      budget:=FinEnergyStreamBudget();model:=FinEnergyPreparedOwner(budget.state);state:=FinEnergyPreparedOwner(budget.state);output:=FinEnergyPreparedOwner(budget.state);diagnostics:=FinEnergyPreparedOwner(budget.state);peer:=FinEnergyPreparedOwner(budget.state)
      catalog:=FinEnergyCockpitCatalog(rs.toImmutable,TimeZone.utc,model)
      ctx:=FinEnergyContext.shared(catalog,"space",false,state);ctx.orderWarnings
      report:=FinEnergyReport(ctx,q,a,b,"profile","day","energy",state)
      cursor:=report.openLine("s","c")
      pool:=FinEnergyCockpitCapture(["report":["kind":"sourceUsage","grain":"sourceRead","reportRefs":["report"]]],diagnostics)
      consumer:=FinEnergyReportConsumer(ctx,report,[cursor],a,b,"day",state,output,pool,"report")
      sources:=FinEnergyCockpitStream[,]
      try
      {
        points.keys.sort.each |id| {sources.add(FinEnergyCockpitStream.openCursor(points[id],null,a,b,q,rs,budget,read,ctx))}
        (0..<2).each |i| {end:=a+1hr*(i+1);sources.each |source| {source.advance(end)};FinEnergyCockpitStream.withFrames(sources,budget.state) |histories,frame| {consumer.addFrame(histories,frame)}}
        sources.each |source| {source.close}
        peer.hold(budget.state.remaining-5000);peerEntries:=peer.entries
        result:=consumer.finish
        pool.freeze
        verifyEq(business(result),business(expected))
        verifyEq(peer.entries,peerEntries);verifyEq(budget.state.unprepared.val,0)
        output.close;verifyEq(peer.entries,peerEntries)
      }
      finally {sources.each |source| {source.close};state.close;output.close;diagnostics.close;model.close;peer.close}
      verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
    }
  }
  private Str:Obj? business(Str:Obj? value)
  {
    result:=(Str:Obj?)JsonInStream(JsonOutStream.writeJsonToStr(value).in).readJson
    ((Map)result["extra"]).remove("knownUsage")
    return result
  }
}

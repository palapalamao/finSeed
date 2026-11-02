using haystack

** Actual private producer frames; no FIN data or project mutation.
class EnerCubixContextOwnerTest : Test
{
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
      verifyEq(ctx.node("m","c",at,at+1hr).value,10f)
      verifyEq(known.node("m","c",at,at+1hr).value,10f);verify(!known.knownReads.isEmpty)
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

  private EnerCubixCockpitStream source(EnerCubixStreamBudget budget,HisItem[] raw)
  {
    cfg:=Etc.makeDict(["defNull":Marker.val]);p:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":cfg])
    q:=Str:Obj?["from":at.toIso,"to":(at+4hr).toIso,"asOf":(at+4hr).toIso,"tz":"UTC"]
    return EnerCubixCockpitStream.openCursor(p,cfg,at,at+4hr,q,records,budget,|Dict point,Span span,|HisItem| sink| {raw.each |row| {if(row.ts>=span.start && row.ts<span.end) sink(row)}})
  }
  private [Str:Obj?][] records() {[["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","pointId":"p","categoryId":"c"]]}
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

using haystack

class EnerCubixSourceHeaderTest : Test
{
  Void testCleanedHeaderAndAdmissionFailureKeepDiagnosticsAndPeerSeparate()
  {
    a:=DateTime.fromIso("2026-10-01T00:00:00Z");b:=a+2hr
    cfg:=Etc.makeDict(["defNull":Marker.val,"deltaMax":Number(50)])
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":cfg])
    q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"metering","nodeIds":["m"],"categoryIds":["c"],"from":a.toIso,"to":b.toIso,"asOf":b.toIso,"period":"hour","tz":"UTC"]
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","categoryId":"c","pointId":"p"]]
    budget:=EnerCubixStreamBudget();peer:=EnerCubixPreparedOwner(budget.state)
    source:=EnerCubixCockpitStream.openCursor(point,cfg,a,b,q,rs,budget,|Dict p,Span span,|HisItem| sink| {[HisItem(a,Number(0)),HisItem(a+1hr,Number(10)),HisItem(b,Number(100))].each |row| {if(row.ts>=span.start && row.ts<span.end) sink(row)}})
    try
    {
      (0..<2).each |i| {source.advance(a+1hr*(i+1));EnerCubixCockpitStream.withFrames([source],budget.state) |h,frame| {}}
      peer.hold(budget.state.remaining);before:=peer.entries;delivered:=0
      verifyErr(EnerCubixHttpErr#) {source.withHeaderMetadata |meta| {delivered++}}
      verifyEq(delivered,0);verifyEq(peer.entries,before);peer.close
      reads:=budget.nativeReads
      source.withHeaderMetadata |meta| {verifyEq(meta["mode"],"interval");verifyEq(meta["quality"],"cleaned");verifyEq(meta["simulated"],false);verify(!meta.containsKey("cleaning"));verify(!meta.containsKey("_preparedBudget"))}
      source.withCleaningMetadata |meta| {verify(EnerCubixMath.num(meta["rejectedCount"])>0f)}
      verifyEq(budget.nativeReads,reads)
    }
    finally {source.close;peer.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
  Void testConsumedCursorCanDetachOnlyFinalHeaderWithoutEscapingItsFrames()
  {
    a:=DateTime.fromIso("2026-10-01T00:00:00Z");b:=a+2hr
    point:=Etc.makeDict(["id":Ref("p"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","simulated":Marker.val])
    q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"metering","nodeIds":["m"],"categoryIds":["c"],"from":a.toIso,"to":b.toIso,"asOf":b.toIso,"period":"hour","tz":"UTC"]
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"m","kind":"meter","categoryId":"c","pointId":"p"]]
    budget:=EnerCubixStreamBudget()
    source:=EnerCubixCockpitStream.openCursor(point,null,a,b,q,rs,budget,|Dict p,Span span,|HisItem| sink| {(0..2).each |i| {ts:=a+1hr*i;if(ts>=span.start && ts<span.end) sink(HisItem(ts,Number(i*10)))}})
    EnerCubixHistoryData? expired;Map? borrowed;Map? detached
    try
    {
      verifyErr(ArgErr#) {source.withHeaderMetadata |meta| {fail("Header must not be published before consumption")}}
      (0..<2).each |i| {source.advance(a+1hr*(i+1));EnerCubixCockpitStream.withFrames([source],budget.state) |h,frame| {expired=h["p"];verifyErr(ArgErr#) {source.withHeaderMetadata |meta| {fail("Active frames cannot escape")}}}}
      verifyErr(ArgErr#) {source.view}
      reads:=budget.nativeReads;before:=budget.state.temporary.val
      source.withHeaderMetadata |meta| {borrowed=meta;detached=(Map)meta.toImmutable}
      verify(borrowed.isEmpty);verify(detached.isImmutable)
      verifyEq(detached.keys.sort,["dataCutoff","mode","pointId","quality","simulated","sourceIds","sourceLastObservedAt","unit"])
      verifyEq(detached["pointId"],"p");verifyEq(detached["unit"],"kWh");verifyEq(detached["sourceIds"],["p"])
      verifyEq(detached["mode"],"cumulative");verifyEq(detached["quality"],"ok");verifyEq(detached["simulated"],true)
      verifyEq(detached["dataCutoff"],b.toIso);verifyEq(detached["sourceLastObservedAt"],b.toIso)
      verifyEq(budget.nativeReads,reads);verifyEq(budget.state.temporary.val,before)
      verifyErr(ArgErr#) {expired.read(a,a+1hr)}
      verifyErr(IOErr#) {source.withHeaderMetadata |meta| {borrowed=meta;throw IOErr("projection test")}}
      verify(borrowed.isEmpty);verifyEq(budget.state.temporary.val,before)
      source.close;verifyErr(ArgErr#) {source.withHeaderMetadata |meta| {fail("Closed cursor cannot provide metadata")}}
    }
    finally {source.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
}

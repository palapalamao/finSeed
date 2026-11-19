** Coverage arithmetic is deterministic over the unchanged contribution rows.
class FinEnergyCoverageOrderTest : Test
{
  Void testSubsecondCoverageUsesBusinessTimeInsteadOfHashIteration()
  {
    rows:=[Str:Obj?][,];expected:=0f
    for(i:=0;i<744;i++)
    {
      start:=at+Duration(i*1hr.ticks);ticks:=(i*123456789123)%3600000000000+1
      rows.add(["from":start.toIso,"to":(start+Duration(ticks)).toIso,"value":1f,"quality":"cleaned"])
      expected+=ticks.toFloat/1sec.ticks.toFloat
    }
    history:=Str:Obj?["pointId":"p","unit":"kWh","mode":"interval","quality":"cleaned","intervals":rows]
    q:=query(at,at+744hr)
    normal:=FinEnergyEngine.report(q,records,[history])
    actual:=FinEnergyMath.maps(((Map)normal["extra"])["usageCoverage"]).first
    verifyEq(actual["coveredSeconds"],expected)
    verifyEq(actual["coverage"],expected/(744f*3600f));verifyEq(actual["complete"],false)
    // Preserve the original row set but force the opposite insertion order.
    ctx:=FinEnergyContext(records,[history],TimeZone.utc)
    report:=FinEnergyReport(ctx,q,at,at+744hr,"profile","day","energy")
    line:=report.line("m","c")
    known:=(FinEnergyContext)FinEnergyReport#.field("knownCtx").get(report)
    reads:=known.knownReads.dup
    known.knownReads=Str:[Str:Obj?][:] {ordered=true}
    reads.keys.reverse.each |key| {known.knownReads[key]=reads[key]}
    reverse:=FinEnergyMath.maps(((Map)report.finish([line])["extra"])["usageCoverage"]).first
    verifyEq(reverse,actual)
    verifyEq(known.knownReads.size,744)
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());owner:=FinEnergyPreparedOwner(budget)
    fold:=FinEnergyCoverageFold(["p"],at,at+744hr,owner)
    ordered:=FinEnergyKnownUsage.coverageOrder(reads.vals)
    for(i:=0;i<ordered.size;i+=13)
    {
      frame:=FinEnergyPreparedOwner(budget)
      fold.addFrame(ordered[i..<(i+13).min(ordered.size)].reverse,frame);frame.close
    }
    folded:=fold.finish
    folded.each |value,key| {verifyEq(value,actual[key])}
    owner.close;verifyEq(budget.temporary.val,0)
  }

  Void testStableSubpairAndAliasOrderUsesInstantsAcrossDstFold()
  {
    a:=Str:Obj?["from":"2026-11-01T01:30:00-04:00","to":"2026-11-01T01:45:00-04:00","nodeId":"z","pointId":"p"]
    b:=Str:Obj?["from":"2026-11-01T01:00:00-05:00","to":"2026-11-01T01:15:00-05:00","nodeId":"a","pointId":"p"]
    alias:=a.dup.set("nodeId","a")
    shorter:=a.dup.set("to","2026-11-01T01:40:00-04:00")
    first:=FinEnergyKnownUsage.coverageOrder([b,a,alias,shorter])
    verifyEq(first,[shorter,alias,a,b])
    verifyEq(FinEnergyKnownUsage.coverageOrder(first.dup.reverse),first)
    times:=Str:DateTime[:]
    cached:=FinEnergyKnownUsage#.method("coverageOrder").callList([first.dup.reverse,times])
    verifyEq(cached,first);verify(!times.isEmpty)
  }

  private [Str:Obj?][] records() {[["id":"c","kind":"category","unit":"kWh"],["id":"m","name":"M","kind":"meter","categoryId":"c","pointId":"p"]]}
  private Str:Obj? query(DateTime a,DateTime b) {["kind":"profile","nodeIds":["m"],"metric":"energy","period":"day","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":a.tz.name]}
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

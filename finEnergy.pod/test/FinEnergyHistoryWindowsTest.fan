using haystack

class FinEnergyHistoryWindowsTest : Test
{
  Void testSeparatedPeriodsKeepTariffPrefixesAndPointEligibility()
  {
    q:=request
    windows:=FinEnergyHistoryWindows.plan(q,records)
    verifyEq(windows.size,2)
    verifyEq(windows.first.from,at)
    verifyEq(windows.last.from,at+10day)
    q["metric"]="cost";rs:=records;rs.last["mode"]="monthlyBlock"
    verify(FinEnergyHistoryWindows.plan(q,rs).isEmpty,"same monthly prefix overlaps")
    q["from"]="2026-11-01T00:00:00Z";q["to"]="2026-11-02T00:00:00Z"
    q["otherFrom"]="2025-11-01T00:00:00Z";q["otherTo"]="2025-11-02T00:00:00Z";rs.last["mode"]="yearlyBlock"
    windows=FinEnergyHistoryWindows.plan(q,rs)
    verifyEq(windows.first.from,DateTime.fromIso("2025-01-01T00:00:00Z"))
    verifyEq(windows.last.from,DateTime.fromIso("2026-01-01T00:00:00Z"))
    p:=point
    verify(FinEnergyHistoryWindows.eligible(p,"auto",false))
    verify(!FinEnergyHistoryWindows.eligible(p,"interval",false))
    p=Etc.dictSet(p,"hisFunc","finEnergyCleanHis")
    verify(!FinEnergyHistoryWindows.eligible(p,"auto",false))
    verify(FinEnergyHistoryWindows.eligible(p,"auto",true))
    verify(!FinEnergyHistoryWindows.eligible(Etc.makeDict(["id":Ref("p"),"hisMode":"consumption"]),"auto",false))
  }

  Void testSparseCumulativeComparisonKeepsCompleteReportAndReferences()
  {
    all:=samples;windows:=FinEnergyHistoryWindows.plan(request,records)
    timing:=Str:Int[:]
    sparse:=FinEnergyHistoryWindows.read(windows,|DateTime from,DateTime to,|HisItem| sink| {emitRead(all,from,to,sink)},timing)
    verifyNotNull(sparse)
    verify(sparse.size<all.size)
    verifyEq(timing["nativeReads"],2)
    verifyEq(timing["sparsePoints"],1)
    ["energy","cost","coal","co2"].each |metric|
    {
      q:=request.set("metric",metric)
      q["referenceIds"]=["p"]
      old:=FinEnergyHistory.normalize(point,all,at,at+11day)
      fast:=FinEnergyHistory.normalize(point,sparse,at,at+11day)
      verifyEq(FinEnergyHistory.report(q,records,[fast]),FinEnergyHistory.report(q,records,[old]),metric)
    }
  }

  Void testMissingBoundsOrConflictingOverlapReturnToWholeRead()
  {
    windows:=FinEnergyHistoryWindows.plan(request,records);timing:=Str:Int[:]
    answer:=FinEnergyHistoryWindows.read(windows,|DateTime from,DateTime to,|HisItem| sink| {sink(HisItem(from+2day,Number(1)))},timing)
    verifyNull(answer);verifyEq(timing["sparseFallbacks"],1)
    count:=0
    answer=FinEnergyHistoryWindows.read(windows,|DateTime from,DateTime to,|HisItem| sink|
      {sink(HisItem(at,Number((count++).toFloat)));sink(HisItem(from,Number(2)));sink(HisItem(to,Number(3)))},timing)
    verifyNull(answer)
    verifyErr(ArgErr#) {FinEnergyHistoryWindows.read(windows,|DateTime from,DateTime to,|HisItem| sink| {samples.each |item| {sink(item)}},null,2)}
  }

  Void testDifferentBillingCyclesRetainExactCanonicalPrefixes()
  {
    ["monthlyBlock","yearlyBlock"].each |mode|
    {
      q:=request.set("metric","cost").set("from","2026-11-01T00:00:00Z").set("to","2026-11-02T00:00:00Z").set("asOf","2026-11-03T00:00:00Z")
      q["otherFrom"]=mode=="monthlyBlock" ? "2026-09-01T00:00:00Z" : "2025-11-01T00:00:00Z"
      q["otherTo"]=mode=="monthlyBlock" ? "2026-09-02T00:00:00Z" : "2025-11-02T00:00:00Z"
      rs:=records;rs.last["mode"]=mode;rs.last["blocks"]=[["limit":100f,"rate":1f],["rate":2f]]
      windows:=FinEnergyHistoryWindows.plan(q,rs)
      verifyEq(windows.size,2)
      from:=windows.first.from;to:=windows.last.to
      raw:=HisItem[,];hours:=(to-from).ticks/1hr.ticks
      (-24..hours+24).each |i| {raw.add(HisItem(from+1hr*i,Number((i+24).toFloat)))}
      [false,true].each |missingPrefix|
      {
        data:=raw.dup
        if(missingPrefix) data[30]=HisItem(data[30].ts,NA.val)
        sparse:=FinEnergyHistoryWindows.read(windows,|DateTime left,DateTime right,|HisItem| sink| {emitRead(data,left,right,sink)})
        verifyNotNull(sparse);verify(sparse.size<data.size)
        old:=FinEnergyHistory.normalize(point,data,from,to)
        fast:=FinEnergyHistory.normalize(point,sparse,from,to)
        verifyEq(FinEnergyHistory.report(q,rs,[fast]),FinEnergyHistory.report(q,rs,[old]),"$mode missingPrefix=$missingPrefix")
      }
    }
  }
  private Void emitRead(HisItem[] all,DateTime from,DateTime to,|HisItem| sink)
  {
    before:=all.findAll |row| {row.ts<from}.last
    if(before!=null) sink(before)
    all.findAll |row| {row.ts>=from && row.ts<=to}.each |row| {sink(row)}
    after:=all.find |row| {row.ts>to}
    if(after!=null) sink(after)
  }
  private HisItem[] samples()
  {
    out:=HisItem[,]
    (-24..12*24).each |i| {out.add(HisItem(at+1hr*i,Number(i<5*24 ? (i+24).toFloat : (i-5*24).toFloat)))}
    return out
  }
  private Str:Obj? request() {["kind":"comparison","nodeIds":["m"],"from":(at+10day).toIso,"to":(at+11day).toIso,"otherFrom":at.toIso,"otherTo":(at+1day).toIso,"asOf":(at+12day).toIso,"tz":"UTC","period":"day","metric":"energy"]}
  private [Str:Obj?][] records() {[["id":"m","kind":"meter","name":"Meter","categoryId":"e","pointId":"p"],["id":"e","kind":"category","unit":"kWh"],["id":"b","kind":"binding","pointId":"p","role":"reference","name":"Raw"],["id":"t","kind":"tariff","categoryId":"e","isDefault":true,"mode":"flat","rate":2f]]}
  private Dict point() {Etc.makeDict(["id":Ref("p"),"unit":"kWh","hisTotalized":Marker.val])}
  private DateTime at() {DateTime.fromIso("2026-11-01T00:00:00Z")}
}

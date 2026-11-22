** Construction may shrink; public quotas, values, coverage and headers may not.
class FinEnergyKnownCaptureBudgetTest : Test
{
  Void testFullEvidenceBuildsOnlyTheExistingRequestQuota()
  {
    ctx:=context(rows(1002,0).addAll(rows(1002,1)),true)
    first:=ctx.node("m","e",at,at+1hr)
    second:=ctx.node("m","e",at+1hr,at+2hr)
    verifyEq(first.value,1002f);verifyEq(second.value,1002f)
    verifyEq(ctx.byPoint["p"].knownDiagnosticRows,1000)
    headers:=ctx.knownReads.vals.sort |a,b| {a["from"].toStr<=>b["from"].toStr}
    verifyEq(((List)headers.first["intervals"]).size,1000)
    verify(!headers.first.containsKey("intervalsCaptureId"))
    verifyEq(((List)headers.last["intervals"]).size,0)
    verify(headers.last["intervalsCaptureId"] is Str)
    verifyEq(headers.last["intervalCount"],1002)
  }

  Void testFullHeadersMatchTheOriginalCaptureAtEveryQuotaEdge()
  {
    [0,17,999,1000].each |remaining|
    {
      [0,1,remaining,remaining+1,1002].unique.each |count|
      {
        data:=rows(1000-remaining,0).addAll(rows(count,1))
        before:=context(data,false);after:=context(data,true)
        [at,at+1hr].each |from|
        {
          old:=before.node("m","e",from,from+1hr);value:=after.node("m","e",from,from+1hr)
          sameValue(old,value)
        }
        verifyEq(evidence(after),evidence(before),"remaining=$remaining count=$count")
        verify(after.byPoint["p"].knownDiagnosticRows<=before.byPoint["p"].knownDiagnosticRows)
      }
    }
  }

  Void testRepeatedKeysAndOverlapKeepLegacyHeaderShapes()
  {
    [0,17,999,1000].each |remaining|
    {
      [2,1002].each |count|
      {
        data:=rows(1000-remaining,0).addAll(rows(count,1))
        start:=at+1hr+1sec*count-500ms
        data.add(["from":start.toIso,"to":(start+1sec).toIso,"value":1f,"quality":"cleaned"])
        before:=context(data,false);after:=context(data,true)
        [at,at+1hr,at+1hr].each |from|
        {
          old:=before.node("m","e",from,from+1hr,"energy",["scope"])
          value:=after.node("m","e",from,from+1hr,"energy",["scope"])
          sameValue(old,value)
        }
        verifyEq(evidence(after),evidence(before))
      }
    }
  }

  Void testFractionalTariffRefundKeepsCompleteCostEvidence()
  {
    data:=rows(1002,0).addAll(rows(1002,1))
    before:=context(data,false,true);after:=context(data,true,true)
    [at,at+1hr].each |from| {sameValue(before.node("m","e",from,from+1hr,"cost"),after.node("m","e",from,from+1hr,"cost"))}
    verifyEq(evidence(after),evidence(before))
  }

  private FinEnergyContext context([Str:Obj?][] intervals,Bool bounded,Bool fee := false)
  {
    rs:=[Str:Obj?][["id":"e","kind":"category","unit":"kWh"],["id":"m","kind":"meter","name":"Meter","pointId":"p","categoryId":"e","tariffId":"t"],
      ["id":"t","kind":"tariff","mode":"weekly","rate":1f,"rules":[["startHour":0.5f,"endHour":24f,"rate":3f]]]]
    strict:=FinEnergyContext(rs,[["pointId":"p","unit":"kWh","mode":"interval","quality":"cleaned","intervals":intervals]],TimeZone.utc)
    strict.boundedKnownDetails=bounded
    return FinEnergyContext.known(strict,at+2hr)
  }
  private [Str:Obj?][] rows(Int count,Int hour)
  {(0..<count).map |i->[Str:Obj?]| {start:=at+1hr*hour+1sec*i;return ["from":start.toIso,"to":(start+1sec).toIso,"value":1f,"quality":"cleaned"]}}
  private [Str:Obj?][] evidence(FinEnergyContext ctx)
  {ctx.knownReads.keys.sort.map |key->[Str:Obj?]| {r:=ctx.knownReads[key].dup;if(r.containsKey("intervalsCaptureId")) r["intervalsCaptureId"]="capture";return r}}
  private Void sameValue(FinEnergyValue a,FinEnergyValue b)
  {verifyEq(a.value,b.value);verifyEq(a.quality,b.quality);verifyEq(a.sources,b.sources)}
  private DateTime at() {DateTime.fromIso("2026-11-01T00:00:00Z")}
}

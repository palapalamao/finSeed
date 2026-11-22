** Full reports retain every output; shared input projections need only one parse.
class FinEnergyFullQueryCoreTest : Test
{
  Void testSameRawAndProcessedProjectionParsesOnce()
  {
    rows:=samples
    data:=Str:Obj?["pointId":"p","mode":"cumulative","samples":rows,"rawSamples":rows]
    parsed:=FinEnergyHistoryData(data)
    verify(parsed.samples===parsed.rawSamples)
    verifyEq(parsed.samples.size,3)
    verifyEq(parsed.samples.first.value,1f)
    verifyEq(parsed.samples[1].value,5f)
    separate:=FinEnergyHistoryData(data.dup.set("rawSamples",rows.dup))
    verify(separate.samples!==separate.rawSamples)
    verifyEq(parsed.read(at,at+1hr).value,separate.read(at,at+1hr).value)
    verifyEq(parsed.read(at,at+1hr,true).value,separate.read(at,at+1hr,true).value)
  }

  Void testEquivalentCutoffFiltersKeepSharedProjection()
  {
    rows:=samples
    h:=Str:Obj?["pointId":"p","mode":"cumulative","samples":rows,"rawSamples":rows]
    clipped:=FinEnergyKnownUsage.clip([h],at+90min).first
    verify(clipped["samples"]===clipped["rawSamples"])
    verifyEq(FinEnergyMath.maps(clipped["samples"]).size,3)
    verifyEq(FinEnergyMath.maps(h["samples"]).size,4)
    h["mode"]="interval";h["intervals"]=[Str:Obj?][,]
    clipped=FinEnergyKnownUsage.clip([h],at+90min).first
    verify(clipped["samples"]===clipped["rawSamples"])
  }

  Void testUnclosedImplicitIntervalKeepsDifferentRawCutoff()
  {
    rows:=samples
    h:=Str:Obj?["pointId":"p","mode":"interval","samples":rows,"rawSamples":rows]
    clipped:=FinEnergyKnownUsage.clip([h],at+90min).first
    verify(clipped["samples"]!==clipped["rawSamples"])
    verifyEq(FinEnergyMath.maps(clipped["samples"]).size,1)
    verifyEq(FinEnergyMath.maps(clipped["rawSamples"]).size,3)
  }

  private [Str:Obj?][] samples()
  {[["ts":(at+1hr).toIso,"value":3f],["ts":at.toIso,"value":1f],["ts":(at+1hr).toIso,"value":5f],["ts":(at+2hr).toIso,"value":7f]]}
  private DateTime at() {DateTime.fromIso("2026-11-01T00:00:00Z")}
}

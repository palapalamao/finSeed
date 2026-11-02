class EnerCubixCapturePeriodsTest : Test
{
  Void testPeriodFlagsFinalizeAfterLaterGroupsEvictSamples()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    target:=Str:Obj?["id":"m"];output.watch |->Void| {target.clear}
    pool:=EnerCubixCockpitCapture(plan,owner)
    try
    {
      (0..<1000).each |i| {pool.put("periods",row(i))}
      pool.periodEnvelope("periods",target,output,1000);pool.seal("periods")
      before:=((List)target["periods"]).size
      verifyEq(target["_capturePending"],true)
      (0..<3000).each |i| {pool.put("late",row(i))}
      pool.seal("late");metadata:=pool.freeze
      verify(!target.containsKey("_capturePending"));verify(((List)target["periods"]).size<before)
      verifyEq(target["periodRecordTotalCount"],1000);verifyEq(target["periodsReturnedCount"],((List)target["periods"]).size)
      verifyEq(target["periodsTruncated"],true);verifyEq(target["periodsTruncationReason"],"snapshotDiagnosticBudget")
      entry:=EnerCubixMath.maps(metadata["entries"]).find |r| {r["id"]==target["periodsDiagnosticRef"]}
      verifyEq(entry["kind"],"coveragePeriods");verifyEq(entry["returnedCount"],target["periodsReturnedCount"])
      verifyEq(entry["totalCount"],1000);verifyEq(metadata["returnedCount"],1000)
      verify(target["periodsCaptureId"] is Str)
      verifyErr(ArgErr#) {owner.close}
    }
    finally {output.close;owner.close}
    verify(target.isEmpty);verifyEq(budget.temporary.val,0)
  }
  Void testExpiredPeriodOutputCannotPublishMetadata()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    pool:=EnerCubixCockpitCapture(plan,owner);target:=Str:Obj?["id":"m"];output.watch |->Void| {target.clear}
    pool.put("periods",row(0));pool.periodEnvelope("periods",target,output,1)
    pool.seal("periods");pool.seal("late");output.close
    verifyErr(ArgErr#) {pool.freeze}
    owner.close;verifyEq(budget.temporary.val,0)
  }
  Void testWrongGroupCountAndForeignOwnerDoNotChangeTarget()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    other:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());foreign:=EnerCubixPreparedOwner(other)
    pool:=EnerCubixCockpitCapture(plan,owner);target:=Str:Obj?["id":"m"]
    try
    {
      verifyErr(ArgErr#) {pool.periodEnvelope("late",target,output,0)}
      verifyErr(ArgErr#) {pool.periodEnvelope("periods",target,output,3)}
      verifyErr(ArgErr#) {pool.periodEnvelope("periods",target,foreign,0)}
      verifyEq(target.keys,["id"])
    }
    finally {foreign.close;output.close;owner.close}
    verifyEq(budget.temporary.val,0);verifyEq(other.temporary.val,0)
  }
  private Str:[Str:Obj?] plan() {["periods":["kind":"coveragePeriods","grain":"hour"],"late":["kind":"cleaningEvents","grain":"cleaningEvent"]]}
  private Str:Obj? row(Int i)
  {at:=DateTime.fromIso("2026-01-01T00:00:00Z")+1hr*i;return ["from":at.toIso,"to":(at+1hr).toIso,"value":1f,"quality":"ok","pointId":"p"]}
}

class EnerCubixAlarmEpisodesTest : Test
{
  Void testContinuousHighMissingNormalAndReentry()
  {
    events:=[event("a",13),event("b",14),event("c",17),event("d",19)]
    samples:=[sample(13,10f),sample(14,12f),sample(15,null),sample(16,11f,"missing"),sample(17,9f),sample(18,7f),sample(19,8f)]
    plan:=EnerCubixAlarmEpisodes.plan(events,samples)
    verifyEq(plan.size,2)
    verifyEq(plan[0]["rootId"],"a")
    verifyEq(plan[0]["memberIds"],Str["a","b","c"])
    verifyEq(plan[0]["recoveredAt"],"2026-10-23T19:00:00+08:00")
    verifyEq(plan[1]["rootId"],"d")
    verifyEq(plan[1]["recoveredAt"],null)
  }

  Void testRescanKeepsRecoveryBoundariesAndNativeOwner()
  {
    a:=event("a",13); a["episodeId"]="a"; a["recoveredAt"]="2026-10-23T15:00:00+08:00"
    b:=event("b",16); b["nativeAlarmId"]="b_offNormal"
    plan:=EnerCubixAlarmEpisodes.plan([event("legacy",12),a,b,event("c",17)],[sample(17,10f)])
    verifyEq(plan.size,2)
    verifyEq(plan[0]["rootId"],"a")
    verifyEq(plan[1]["rootId"],"b")
    verifyEq(plan[1]["memberIds"],Str["b","c"])
    verifyEq(EnerCubixAlarmEpisodes.plan([b,event("c",17)],[sample(17,10f)]),[plan[1]])
  }

  Void testNoRecoveryFromUncertainLowValue()
  {
    plan:=EnerCubixAlarmEpisodes.plan([event("a",13)],[sample(14,1f,"missing"),sample(15,null)])
    verifyEq(plan.size,1)
    verifyEq(plan[0]["recoveredAt"],null)
  }

  Void testCleaningEvidenceDoesNotPretendSubstitutionIsRecovery()
  {
    ["filtered","substituted","na"].each |quality|
    {
      plan:=EnerCubixAlarmEpisodes.plan([event("a",13)],[sample(14,1f,quality)])
      verifyNull(plan.first["recoveredAt"])
    }
    ["cleaned","corrected"].each |quality|
    {
      plan:=EnerCubixAlarmEpisodes.plan([event("a",13)],[sample(14,1f,quality)])
      verifyEq(plan.first["recoveredAt"],"2026-10-23T15:00:00+08:00")
    }
  }

  private [Str:Obj?] event(Str id, Int hour)
  { ["id":id,"ts":"2026-10-23T${hour}:00:00+08:00","state":"open"] }
  private [Str:Obj?] sample(Int hour, Float? value, Str quality := "ok")
  { ["ts":"2026-10-23T${hour}:00:00+08:00","value":value,"limit":7f,"quality":quality] }
}

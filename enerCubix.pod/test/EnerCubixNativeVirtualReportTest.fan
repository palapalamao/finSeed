using haystack

class EnerCubixNativeVirtualReportTest : Test
{
  private Str prefix:="p:virtualRead:r:"
  private Str virtualId() {prefix+"virtual"}
  private Str pointId() {prefix+"enerCubix-formula-"+virtualId.toBuf.toDigest("SHA-256").toHex[0..<24]}
  private Str start:="2026-10-25T10:00:00Z"
  private Str end:="2026-10-25T10:01:00Z"

  Void testNativeMetadataUsesTheCommittedHistoryPointIdentity()
  {
    row:=virtualRecord
    verifyEq(row["historyPointId"],pointId)
    verifyEq(row["includeInTotals"],false)
  }

  Void testExplicitVirtualReportsReadItsArchiveWhileExcludedFromScopeTotals()
  {
    ["profile","ranking","proportion","comparison"].each |kind|
    {
      result:=EnerCubixEngine.report(request(kind),records,[history(pointId,46f),history(prefix+"physical-p",999f)])
      totals:=EnerCubixMath.maps(((Map)result["summary"])["knownTotals"])
      verifyEq(totals.first["value"],46f,kind)
      verifyEq(EnerCubixMath.strings(totals.first["sourceIds"]),[pointId])
      if(kind=="proportion")verifyEq(EnerCubixMath.maps(result["rows"]).first["knownPercentage"],100f)
    }
    q:=request("dashboard");q["dimension"]="space";q["nodeIds"]=[prefix+"space"]
    r:=EnerCubixEngine.report(q,records,[history(pointId,46f),history(prefix+"physical-p",23f)])
    total:=EnerCubixMath.maps(((Map)r["summary"])["selectionTotals"]).first
    verifyEq(total["knownValue"],23f)
    verifyEq(EnerCubixMath.strings(total["meterIds"]),[prefix+"physical"])
  }

  Void testMissingArchiveDoesNotRecomputeExpressionOrUseAnotherProject()
  {
    [Str:Obj?][,].add(history(prefix+"physical-p",23f)).with |own|
    {
      result:=EnerCubixEngine.report(request("profile"),records,own)
      verifyNull(EnerCubixMath.maps(((Map)result["summary"])["knownTotals"]).first["value"])
    }
    foreign:=pointId.replace(prefix,"p:other:r:")
    result:=EnerCubixEngine.report(request("profile"),records,[history(foreign,46f)])
    verifyNull(EnerCubixMath.maps(((Map)result["summary"])["knownTotals"]).first["value"])
  }

  Void testUnprefixedStandaloneMetadataRemainsCompatible()
  {
    record:=EnerCubixNativeEquip.decode(Etc.makeDict(["id":Ref("v"),"equip":Marker.val,"dis":"v","enerCubixKind":"meter","enerCubixExpressionRef":Ref("e"),"enerCubixCategoryRef":Ref("c")]))
    verifyEq(record["historyPointId"],EnerCubixMeterHistory.formulaId(Ref("v")).id)
  }

  private Str:Obj? request(Str kind)
  { ["kind":kind,"dimension":"metering","nodeIds":[virtualId],"from":start,"to":end,"asOf":end,"period":"hour","metric":"energy","perArea":false] }
  private Str:Obj? virtualRecord()
  {
    return EnerCubixNativeEquip.decode(Etc.makeDict(["id":Ref(virtualId),"equip":Marker.val,"dis":"Virtual","enerCubixKind":"meter","enerCubixExpressionRef":Ref(prefix+"expression"),"enerCubixCategoryRef":Ref(prefix+"category"),"enerCubixSpaceRef":Ref(prefix+"space"),"enerCubixIncludeInTotals":false]))
  }
  private [Str:Obj?][] records()
  {
    return [virtualRecord,["id":prefix+"category","kind":"category","name":"Electricity","unit":"kWh"],
      ["id":prefix+"expression","kind":"expression","name":"Double","formula":"a * 2","variables":["a":prefix+"physical"]],
      ["id":prefix+"physical","kind":"meter","name":"Physical","pointId":prefix+"physical-p","categoryId":prefix+"category","spaceId":prefix+"space","includeInTotals":true],
      ["id":prefix+"space","kind":"space","name":"Space"]]
  }
  private Str:Obj? history(Str point,Float value)
  { ["pointId":point,"unit":"kWh","mode":"interval","quality":"cleaned","samples":Obj?[,],"intervals":[["from":start,"to":end,"value":value,"quality":"cleaned"]]] }
}

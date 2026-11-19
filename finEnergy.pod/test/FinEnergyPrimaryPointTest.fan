using haystack

class FinEnergyPrimaryPointTest : Test
{
  private DateTime from:=DateTime.fromIso("2026-10-27T00:00:00Z")
  private DateTime to:=DateTime.fromIso("2026-10-27T01:00:00Z")

  Void testEveryMeterReadsOnlyItsExplicitPrimaryPoint()
  {
    ["physical","autoSum","formula"].each |mode|
    {
      row:=meter(mode)
      ctx:=FinEnergyContext(records(row),[history("primary",7f),history("oldArchive",999f),history("childPoint",100f)],TimeZone.utc)
      value:=ctx.node("meter","energy",from,to,"energy")
      verifyEq(value.value,7f,mode)
      verifyEq(value.sources,["primary"],mode)
    }
  }

  Void testMissingPrimaryNeverUsesArchiveOrExpressionInputs()
  {
    ["physical","autoSum","formula"].each |mode|
    {
      row:=meter(mode);row.remove("pointId")
      ctx:=FinEnergyContext(records(row),[history("oldArchive",999f),history("childPoint",100f)],TimeZone.utc)
      verifyNull(ctx.node("meter","energy",from,to,"energy").value,mode)
      row=meter(mode)
      ctx=FinEnergyContext(records(row),[history("oldArchive",999f),history("childPoint",100f)],TimeZone.utc)
      verifyNull(ctx.node("meter","energy",from,to,"energy").value,mode)
    }
  }

  Void testDependenciesReadPrimaryAndNeverCollectFormulaInputs()
  {
    ["physical","autoSum","formula"].each |mode|
    {
      ["", "metering", "space", "organization"].each |dimension|
      {
        req:=request("profile");if (!dimension.isEmpty) req["dimension"]=dimension
        verifyEq(FinEnergyHistory.pointIds(req,records(meter(mode))),["primary"],mode+dimension)
      }
    }
  }

  Void testReportsUseTheSameMainPointInBothLegacyAndDimensionViews()
  {
    ["profile","ranking","proportion","comparison"].each |kind|
    {
      ["", "metering"].each |dimension|
      {
        req:=request(kind);if (!dimension.isEmpty) req["dimension"]=dimension
        result:=FinEnergyEngine.report(req,records(meter("formula")),[history("primary",7f),history("oldArchive",999f),history("childPoint",100f)])
        totals:=FinEnergyMath.maps(((Map)result["summary"])["knownTotals"])
        verifyEq(totals.first["value"],7f,kind+dimension)
        verifyEq(FinEnergyMath.strings(totals.first["sourceIds"]),["primary"])
      }
    }
  }

  Void testNativeFormulaMetadataDoesNotInventAPoint()
  {
    tags:=Str:Obj?["id":Ref("v"),"equip":Marker.val,"finEnergyKind":"meter","finEnergyExpressionRef":Ref("expr")]
    decoded:=FinEnergyNativeEquip.decode(Etc.makeDict(tags))
    verifyNull(decoded["historyPointId"]);verifyNull(decoded["pointId"])
    tags["finEnergyPointRef"]=Ref("primary")
    decoded=FinEnergyNativeEquip.decode(Etc.makeDict(tags))
    verifyEq(decoded["pointId"],"primary");verifyNull(decoded["historyPointId"])
  }

  Void testFlowReferencesReadEachPrimaryWithoutReplacingVirtualOwnValue()
  {
    req:=request("energyFlow");req["dimension"]="metering";req["categoryId"]="energy"
    rows:=records(meter("formula"))
    verifyEq(FinEnergyHistory.pointIds(req,rows),["childPoint","primary"])
    result:=FinEnergyEngine.report(req,rows,[history("primary",7f),history("oldArchive",999f),history("childPoint",100f)])
    graphs:=FinEnergyMath.maps(((Map)result["extra"])["energyFlowGraphs"])
    nodes:=FinEnergyMath.maps(graphs.first["nodes"])
    verifyEq(nodes.find |r| {r["nodeId"] == "meter"}["value"],7f)
    verifyEq(nodes.find |r| {r["nodeId"] == "child"}["value"],100f)
  }

  Void testNativeHistoryFunctionsCannotRedirectAStoredPrimaryRead()
  {
    ["hfTotalized","finEnergyCleanHis","customFormula"].each |func|
    {
      point:=Etc.makeDict(["id":Ref("primary"),"hisFunc":func,"hisTotalized":Marker.val,"his":Marker.val])
      verify(FinEnergyHistory.readOptions(point).has("raw"),func)
      verifyEq(FinEnergyHistory.outputMode(point),"auto")
    }
  }

  Void testEnergyReferencesCannotReadAnAuxiliaryHistory()
  {
    rows:=records(meter("physical"))
    auxiliary:=Etc.makeDict(["id":Ref("auxiliary"),"unit":"kWh"])
    verifyFalse(FinEnergyHistory.primaryReadAllowed(auxiliary,rows))
    rows.add(["id":"reference","kind":"binding","role":"reference","pointId":"auxiliary"])
    verifyFalse(FinEnergyHistory.primaryReadAllowed(auxiliary,rows))
    verify(FinEnergyHistory.primaryReadAllowed(Etc.makeDict(["id":Ref("primary"),"unit":"kWh"]),rows))
    verifyFalse(FinEnergyHistory.primaryReadAllowed(Etc.makeDict(["id":Ref("primary"),"unit":"kWh","finEnergyComputed":Marker.val]),rows))
    verify(FinEnergyHistory.primaryReadAllowed(Etc.makeDict(["id":Ref("temperature"),"unit":"°C"]),rows))
    req:=request("comparison");req["referenceIds"]=["oldArchive"]
    verifyEq(FinEnergyHistory.pointIds(req,rows),["primary"])
  }

  private Str:Obj? meter(Str mode)
  {
    row:=Str:Obj?["id":"meter","kind":"meter","name":mode,"categoryId":"energy","pointId":"primary","historyPointId":"oldArchive","unit":"kWh"]
    if (mode == "autoSum") row["autoSum"]=true
    if (mode == "formula") row["expressionId"]="expr"
    return row
  }
  private [Str:Obj?][] records(Str:Obj? row)
  { [row,["id":"energy","kind":"category","name":"Energy","unit":"kWh"],["id":"child","kind":"meter","name":"Child","pointId":"childPoint","categoryId":"energy","meterParentId":"meter"],["id":"expr","kind":"expression","formula":"a * 2","variables":["a":"child"]]] }
  private Str:Obj? request(Str kind)
  { ["kind":kind,"nodeIds":["meter"],"from":from.toIso,"to":to.toIso,"asOf":to.toIso,"period":"hour","metric":"energy","perArea":false] }
  private Str:Obj? history(Str point,Float value)
  { ["pointId":point,"unit":"kWh","mode":"interval","quality":"ok","samples":Obj?[,],"intervals":[["from":from.toIso,"to":to.toIso,"value":value,"quality":"ok"]]] }
}

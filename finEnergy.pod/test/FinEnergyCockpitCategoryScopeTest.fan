** Internal range reports respect their own energy; auxiliary reports remain independent.
class FinEnergyCockpitCategoryScopeTest : Test
{
  Void testElectricAndAuxiliaryWaterDetailsStayInTheirOwnEnergy()
  {
    q:=query
    r:=FinEnergyEngine.report(q,records,histories)
    verifyEq(detailIds(r),["e"])
    verifyEq(FinEnergyMath.maps(((Map)r["summary"])["totals"]).first["value"],100f)
    water:=FinEnergyCockpitReports.metricQuery(q,"auxiliary","cw")
    r=FinEnergyEngine.report(water,records,histories)
    verifyEq(detailIds(r),["w"])
    verifyEq(FinEnergyMath.maps(((Map)r["summary"])["totals"]).first["value"],50f)
  }
  Void testRangeDependenciesKeepAuxiliaryUnionAndCrossEnergyRatioOperands()
  {
    q:=query
    e:=(Str[])FinEnergyDimension.dependencies(q,records)["points"]
    w:=(Str[])FinEnergyDimension.dependencies(FinEnergyCockpitReports.metricQuery(q,"auxiliary","cw"),records)["points"]
    verifyEq(e,["pe"]);verifyEq(w,["pw"]);verifyEq(e.dup.addAll(w).unique.sort,["pe","pw"])
    rs:=records;rs.add(["id":"ratio","kind":"cop","numeratorId":"w","denominatorId":"e"])
    verifyEq(FinEnergyDimension.dependencies(q.dup.set("nodeIds",["ratio"]),rs)["points"],["pe","pw"])
    verifyEq(FinEnergyDimension.dependencies(q.dup.setAll(["kind":"cop","nodeIds":["ratio"]]),rs)["points"],["pe","pw"])
  }
  Void testExplicitObjectsAndOrdinaryReportsRetainTheirExistingDetailScope()
  {
    q:=query.dup.setAll(["_cockpitExplicitObjects":true,"nodeIds":["e","w"]])
    verifyEq(detailIds(FinEnergyEngine.report(q,records,histories)),["e","w"])
    verifyEq(FinEnergyDimension.dependencies(q,records)["points"],["pe","pw"])
    q=query;q.remove("_cockpitCategoryId");q.remove("_cockpitExplicitObjects")
    verifyEq(detailIds(FinEnergyEngine.report(q,records,histories)),["e","w"])
    verifyEq(FinEnergyDimension.dependencies(q,records)["points"],["pe","pw"])
  }
  Void testRangeEndUseUsesTheSameSingleEnergySelection()
  {
    q:=query.dup.set("kind","utility");r:=FinEnergyEngine.report(q,records,histories)
    totals:=FinEnergyMath.maps(((Map)r["summary"])["totals"])
    verifyEq(totals.size,1);verifyEq(totals.first["categoryId"],"ce");verifyEq(totals.first["value"],100f)
    verifyEq(FinEnergyDimension.dependencies(q,records)["points"],["pe"])
  }
  Void testCockpitHistoryPlanOmitsUnusedWaterButIncludesTheAuxiliaryCard()
  {
    a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+1hr
    [false,true].each |auxiliary|
    {
      rs:=records;rs.find |r| {r["id"]=="s"}["nativeSourceKind"]="site"
      rs.findAll |r| {r["kind"]=="meter"}.each |r| {r.setAll(["nativeEquip":true,"nativeTreeParentId":"s","nativeSpaceId":"s"])}
      input:=Str:Obj?["schemaVersion":1,"requestId":"category-scope","reportScope":["dimension":"space","nodeIds":["s"],"selectionIntent":"range"],"focusCategoryId":"ce","time":["preset":"custom","period":"hour","from":a.toIso,"to":b.toIso],"asOf":b.toIso,"comparison":["mode":"none"],"modules":["kpis","trend"]]
      if(auxiliary) input["auxiliaryCategoryId"]="cw"
      wanted:=auxiliary ? ["pe","pw"] : ["pe"];loaded:=Str[,]
      result:=FinEnergyCockpit.execute(input,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]|
      {
        loaded=FinEnergyMath.strings(q["_cockpitPointIds"]);verifyEq(loaded,wanted)
        return histories.findAll |h| {loaded.contains(h["pointId"].toStr)}
      },"test",TimeZone.utc,b)
      verifyEq(loaded,wanted)
      plan:=FinEnergyMath.maps(((Map)result["provenance"])["historyPlan"])
      verifyEq(plan.map |r->Str[]| {FinEnergyMath.strings(r["pointIds"])}.flatten.map |v->Str| {v.toStr}.unique.sort,wanted)
    }
  }
  Void testConflictingInternalCategoryInputsAreRejected()
  {
    q:=query.dup.set("categoryIds",["cw"])
    verifyErr(ArgErr#) {FinEnergyDimension.dependencies(q,records)}
    verifyErr(ArgErr#) {FinEnergyEngine.report(q,records,histories)}
  }
  private Str[] detailIds(Str:Obj? r)
  {FinEnergyMath.maps(((Map)r["extra"])["details"]).map |d->Str| {d["nodeId"].toStr}.sort}
  private Str:Obj? query()
  {["kind":"profile","metric":"energy","dimension":"space","nodeIds":["s"],"categoryIds":["ce"],"_cockpitCategoryId":"ce","_cockpitExplicitObjects":false,"from":"2026-01-01T00:00:00Z","to":"2026-01-01T01:00:00Z","asOf":"2026-01-01T01:00:00Z","tz":"UTC","period":"hour"]}
  private [Str:Obj?][] records()
  {[["id":"ce","kind":"category","unit":"kWh"],["id":"cw","kind":"category","unit":"m³"],["id":"s","kind":"space"],["id":"e","kind":"meter","spaceId":"s","pointId":"pe","categoryId":"ce"],["id":"w","kind":"meter","spaceId":"s","pointId":"pw","categoryId":"cw"]]}
  private [Str:Obj?][] histories()
  {[["pointId":"pe","mode":"interval","samples":[["ts":"2026-01-01T00:00:00Z","value":100f],["ts":"2026-01-01T01:00:00Z","value":0f]]],["pointId":"pw","mode":"interval","samples":[["ts":"2026-01-01T00:00:00Z","value":50f],["ts":"2026-01-01T01:00:00Z","value":0f]]]]}
}

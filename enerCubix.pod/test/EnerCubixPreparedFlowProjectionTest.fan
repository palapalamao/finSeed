** Flow presentation consumes exact own-device values after all source frames
** expire. An owned context without an active frame makes any hidden history
** fallback fail, rather than quietly supplying empty or child-summed history.
class EnerCubixPreparedFlowProjectionTest : Test
{
  Void testPhysicalAndVirtualGraphsKeepOriginalWholePeriodArithmetic()
  {
    [false,true].each |missingVirtual|
    {
      rs:=records;hs:=histories
      if(missingVirtual) hs=hs.findAll |h| {h["pointId"]!="pv"}
      q:=query
      dim:=EnerCubixDimension("metering",EnerCubixEnergyFlow.normalizeRecords(rs))
      request:=dim.normalizeRequest(q)
      scope:=EnerCubixEnergyFlow.scope(request,dim)
      ids:=EnerCubixMath.maps(scope["selected"]).map |m->Str| {m["id"].toStr}
      // The read set is established from metadata, before calculating fixtures.
      verifyEq(ids.sort,["a","b","t","v"])
      source:=EnerCubixContext(dim.records,hs,TimeZone.utc,dim)
      known:=EnerCubixContext.known(source,to)
      totals:=Str:EnerCubixValue[:]
      warnings:=Str:Str[][:]
      ids.each |Str id|
      {
        source.warnings.clear
        [false,true].each |isKnown|
        {
          fold:=isKnown ? EnerCubixValueFold.known : EnerCubixValueFold.strict
          at:=from
          while(at<to) {fold.add((isKnown ? known : source).node(id,"c",at,at+1hr));at+=1hr}
          totals[id+"|"+isKnown]=fold.finish
        }
        warnings[id]=source.warnings.dup
      }
      overview:=EnerCubixFlowOverview.build(request,dim.records,hs,ids)
      expected:=EnerCubixEngine.report(q,rs,hs)
      budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
      ctx:=EnerCubixContext(dim.records,[Str:Obj?][,],TimeZone.utc,dim);ctx.useOwner(owner)
      calls:=Str[,]
      try
      {
        result:=EnerCubixEnergyFlow.projectPrepared(ctx,request,from,to,|Str id,Bool isKnown->EnerCubixValue| {key:=id+"|"+isKnown;calls.add(key);if(!isKnown) warnings[id].each |warning| {ctx.warn(warning)};return totals[key] ?: throw ArgErr("flowOwnValueNotPrepared")},overview)
        // Apply the same two outer Engine report fields, not a numeric normalizer.
        result["asOf"]=to.toIso;((Map)result["extra"])["relationBasis"]="current"
        verifyEq(result,expected)
        verifyEq(calls.unique.sort,totals.keys.sort)
        verifyEq(budget.unprepared.val,0)
        graphs:=EnerCubixMath.maps(((Map)result["extra"])["energyFlowGraphs"])
        virtualNode:=EnerCubixMath.maps(graphs.find |g| {g["objectId"]=="v"}["nodes"]).find |n| {n["nodeId"]=="v"}
        verifyEq(virtualNode["value"],missingVirtual ? null : 18f)
        verifyEq(EnerCubixMath.maps(graphs.find |g| {g["objectId"]=="t"}["nodes"]).find |n| {n["nodeId"]=="t"}["difference"],-2f)
        verifyErr(ArgErr#) {EnerCubixEnergyFlow.projectPrepared(ctx,request,from,to,|Str id,Bool isKnown->EnerCubixValue| {throw ArgErr("flowOwnValueNotPrepared")},overview)}
        verifyErr(ArgErr#) {EnerCubixEnergyFlow.projectPrepared(ctx,request.dup.set("metric","cost"),from,to,|Str id,Bool isKnown->EnerCubixValue| {EnerCubixValue()},overview)}
      }
      finally {owner.close}
      verifyEq(budget.temporary.val,0)
    }
  }

  private DateTime from() {DateTime.fromIso("2026-01-01T00:00:00Z")}
  private DateTime to() {from+2hr}
  private Str:Obj? query() {["kind":"energyFlow","dimension":"metering","nodeIds":["t","v"],"categoryId":"c","period":"day","metric":"energy","from":from.toIso,"to":to.toIso,"asOf":to.toIso,"tz":"UTC","_cockpitExplicitObjects":true]}
  private [Str:Obj?][] records()
  {[["id":"c","kind":"category","unit":"kWh"],["id":"t","kind":"totalMeter","name":"Total","pointId":"pt","categoryId":"c"],["id":"a","kind":"meter","name":"A","pointId":"pa","categoryId":"c","meterParentId":"t"],["id":"b","kind":"meter","name":"B","pointId":"pb","categoryId":"c","meterParentId":"t"],["id":"v","kind":"totalMeter","name":"Virtual","pointId":"pv","categoryId":"c","expressionId":"e"],["id":"e","kind":"expression","formula":"x+y","variables":["x":"a","y":"b"]]]}
  private [Str:Obj?][] histories()
  {return ["pt","pa","pb","pv"].map |id,i->[Str:Obj?]| {amount:=[10f,4f,7f,9f][i];return ["pointId":id,"mode":"interval","unit":"kWh","samples":[["ts":from.toIso,"value":amount],["ts":(from+1hr).toIso,"value":amount]]]}}
}


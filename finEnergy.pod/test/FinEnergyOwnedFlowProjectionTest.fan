class FinEnergyOwnedFlowProjectionTest : Test
{
  Void testRejectedProjectionReleasesOnlyItsOwnEntriesAndNeverPublishesHalfGraph()
  {
    from:=DateTime.fromIso("2026-01-01T00:00:00Z");to:=from+1hr
    records:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"t","kind":"totalMeter","categoryId":"c","pointId":"pt"],["id":"a","kind":"meter","categoryId":"c","pointId":"pa","meterParentId":"t"]]
    q:=Str:Obj?["kind":"energyFlow","dimension":"metering","nodeIds":["t"],"categoryId":"c","metric":"energy","from":from.toIso,"to":to.toIso,"asOf":to.toIso,"tz":"UTC"]
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());model:=FinEnergyPreparedOwner(budget);layout:=FinEnergyPreparedOwner(budget);output:=FinEnergyPreparedOwner(budget);peer:=FinEnergyPreparedOwner(budget)
    catalog:=FinEnergyCockpitCatalog(records.toImmutable,TimeZone.utc,model);ctx:=FinEnergyContext.shared(catalog,"metering",false,layout)
    values:=Str:FinEnergyValue["t":FinEnergyValue(10f,"ok",["pt"]),"a":FinEnergyValue(4f,"ok",["pa"])]
    Map? published;calls:=0
    try
    {
      peer.hold(budget.remaining-450);peerEntries:=peer.entries
      verifyErr(FinEnergyHttpErr#)
      {published=FinEnergyEnergyFlow.projectPrepared(ctx,q,from,to,|Str id,Bool known->FinEnergyValue| {calls++;return values[id]},["rows":[Str:Obj?][,]],output)}
      verifyEq(published,null);verify(calls>0,"reject an in-progress graph, not just initial planning")
      output.close;verifyEq(peer.entries,peerEntries);verifyEq(values["t"].sources,["pt"])
      verifyEq(budget.temporary.val,model.entries+layout.entries+peer.entries)
    }
    finally {output.close;layout.close;model.close;peer.close}
    verifyEq(budget.temporary.val,0)
  }
  Void testTwoHundredMetersWideAndDeepKeepExactGraphsWithinExistingLimit()
  {
    [false,true].each |deep|
    {
      records:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"]]
      (0..<200).each |i|
      {
        r:=Str:Obj?["id":"m"+i,"kind":"totalMeter","name":"M"+i,"categoryId":"c","pointId":"p"+i]
        if(i>0) r["meterParentId"]="m"+(deep ? i-1 : 0)
        records.add(r)
      }
      assertGraph(records,["m0"])
    }
  }
  Void testSharedDiamondAliasesCycleAndMissingOwnPrimaryNeverMergeOccurrences()
  {
    [0,1,2,3].each |variant|
    {
      records:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"r","kind":"totalMeter","name":"R","categoryId":"c","pointId":"pr","expressionId":"er"],["id":"v","kind":"totalMeter","name":"V","categoryId":"c","pointId":"pv","expressionId":"ev"],["id":"w","kind":"totalMeter","name":"W","categoryId":"c","pointId":"pw","expressionId":"ew"],["id":"a","kind":"meter","name":"A","categoryId":"c","pointId":"pa"],["id":"b","kind":"meter","name":"B","categoryId":"c","pointId":"pb"],["id":"er","kind":"expression","formula":"x+y","variables":["x":"v","y":"w"]],["id":"ev","kind":"expression","formula":"x+y","variables":["x":"a","y":"b"]],["id":"ew","kind":"expression","formula":"x+y","variables":["x":"a","y":"b"]]]
      if(variant==1) records[5]["pointId"]="pa"
      if(variant==2) {((Map)records[8]["variables"])["x"]="r";records[7]["formula"]="x*2"}
      assertGraph(records,["r","v"],variant==3 ? "pv" : null)
    }
  }
  Void testSpaceAndOrganizationScopesKeepTheirOwnBoundariesAndRepeatedRows()
  {
    ["space","organization"].each |dimension|
    {
      records:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"s","kind":dimension,"name":"Site"],["id":"f","kind":dimension,"name":"Floor","parentId":"s"],["id":"t","kind":"totalMeter","name":"T","categoryId":"c","pointId":"pt","spaceId":"s","organizationId":"s"],["id":"a","kind":"meter","name":"A","categoryId":"c","pointId":"pa","meterParentId":"t","spaceId":"f","organizationId":"f"],["id":"b","kind":"meter","name":"B","categoryId":"c","pointId":"pb","meterParentId":"t","spaceId":"f","organizationId":"f"]]
      assertGraph(records,["s","f"],null,dimension)
    }
  }
  private Void assertGraph([Str:Obj?][] records,Str[] selected,Str? missingPoint := null,Str dimension := "metering")
  {
    from:=DateTime.fromIso("2026-01-01T00:00:00Z");to:=from+1hr
    q:=Str:Obj?["kind":"energyFlow","dimension":dimension,"nodeIds":selected,"categoryId":"c","period":"day","metric":"energy","from":from.toIso,"to":to.toIso,"asOf":to.toIso,"tz":"UTC","_cockpitExplicitObjects":true]
    histories:=[Str:Obj?][,];points:=Str[,]
    records.each |r,i|
    {
      p:=r["pointId"] as Str;if(p==null || p==missingPoint || points.contains(p)) return
      points.add(p);histories.add(["pointId":p,"mode":"interval","unit":"kWh","samples":[["ts":from.toIso,"value":1000f-i.toFloat]]])
    }
    expected:=FinEnergyEngine.report(q,records,histories)
    dim:=FinEnergyDimension(dimension,FinEnergyEnergyFlow.normalizeRecords(records))
    ids:=dim.records.findAll |r| {["meter","totalMeter"].contains(r["kind"])}.map |r->Str| {r["id"].toStr}
    strict:=FinEnergyContext(dim.records,histories,TimeZone.utc,dim);known:=FinEnergyContext.known(strict,to)
    values:=Str:FinEnergyValue[:];warnings:=Str:Str[][:]
    ids.each |Str id|
    {
      strict.warnings.clear
      values[id+"|false"]=strict.node(id,"c",from,to);warnings[id]=strict.warnings.dup
      values[id+"|true"]=known.node(id,"c",from,to)
    }
    scope:=FinEnergyEnergyFlow.scope(q,dim);ownIds:=FinEnergyMath.maps(scope["selected"]).map |r->Str| {r["id"].toStr}
    overview:=FinEnergyFlowOverview.build(q,dim.records,histories,ownIds)
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());model:=FinEnergyPreparedOwner(budget);layout:=FinEnergyPreparedOwner(budget);output:=FinEnergyPreparedOwner(budget)
    catalog:=FinEnergyCockpitCatalog(records.toImmutable,TimeZone.utc,model);ctx:=FinEnergyContext.shared(catalog,dimension,false,layout)
    borrowed:=Obj[,];count(overview,Obj[,],borrowed);values.each |v| {borrowed.add(v.sources)}
    try
    {
      result:=FinEnergyEnergyFlow.projectPrepared(ctx,q,from,to,|Str id,Bool observed->FinEnergyValue| {if(!observed) warnings[id].each |warning| {ctx.warn(warning)};return values[id+"|"+observed]},overview,output)
      result["asOf"]=to.toIso;((Map)result["extra"])["relationBasis"]="current"
      verifyEq(difference(result,expected,"report"),null)
      containers:=Obj[,];cells:=count(result,borrowed,containers)
      verify(output.entries>=cells,"all distinct output containers and their entries are admitted: $cells / ${output.entries}")
      verify(budget.peak.val<=200000);verifyEq(budget.unprepared.val,0)
      echo("flow projection: meters=${ids.size} dimension=$dimension retained=$cells admitted=${output.entries} peak=${budget.peak.val}")
      layout.close;output.close
      containers.each |container| {verify(container is Map ? ((Map)container).isEmpty : ((List)container).isEmpty,"unexpired owned container: $container")}
      values.each |v| {verify(!v.sources.isEmpty,"borrowed primary-source lineage survives output close")}
    }
    finally {layout.close;output.close;model.close}
    verifyEq(budget.temporary.val,0)
  }
  private Int count(Obj? value,Obj[] borrowed,Obj[] seen)
  {
    if(value isnot Map && value isnot List) return 0
    if(borrowed.any |v| {v===value} || seen.any |v| {v===value}) return 0
    seen.add(value);n:=1
    if(value is Map) {n+=((Map)value).size;((Map)value).each |child| {n+=count(child,borrowed,seen)}}
    else {n+=((List)value).size;((List)value).each |child| {n+=count(child,borrowed,seen)}}
    return n
  }
  private Str? difference(Obj? a,Obj? b,Str path)
  {
    if(a is Map && b is Map)
    {
      left:=(Map)a;right:=(Map)b
      if(left.size!=right.size) return "$path map size"
      keys:=left.keys
      for(i:=0;i<keys.size;i++) {key:=keys[i];if(!right.containsKey(key)) return "$path missing $key";d:=difference(left[key],right[key],path+"."+key);if(d!=null) return d}
      return null
    }
    if(a is List && b is List)
    {
      left:=(List)a;right:=(List)b
      if(left.size!=right.size) return "$path list size ${left.size} / ${right.size}"
      for(i:=0;i<left.size;i++) {d:=difference(left[i],right[i],path+"["+i+"]");if(d!=null) return d}
      return null
    }
    return a==b ? null : "$path : $a / $b"
  }
  Void testOutputLeaseExpiresGraphWithoutClearingBorrowedPrimaryValues()
  {
    from:=DateTime.fromIso("2026-01-01T00:00:00Z");to:=from+1hr
    records:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"t","kind":"totalMeter","name":"T","categoryId":"c","pointId":"pt"],["id":"a","kind":"meter","name":"A","categoryId":"c","pointId":"pa","meterParentId":"t"]]
    histories:=[Str:Obj?][["pointId":"pt","mode":"interval","unit":"kWh","samples":[["ts":from.toIso,"value":10f]]],["pointId":"pa","mode":"interval","unit":"kWh","samples":[["ts":from.toIso,"value":4f]]]]
    q:=Str:Obj?["kind":"energyFlow","dimension":"metering","nodeIds":["t"],"categoryId":"c","period":"day","metric":"energy","from":from.toIso,"to":to.toIso,"asOf":to.toIso,"tz":"UTC"]
    overview:=FinEnergyFlowOverview.build(q,records,histories,["t","a"])
    expected:=FinEnergyEngine.report(q,records,histories)
    values:=Str:FinEnergyValue["t":FinEnergyValue(10f,"ok",["pt"]),"a":FinEnergyValue(4f,"ok",["pa"])]
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());model:=FinEnergyPreparedOwner(budget);layout:=FinEnergyPreparedOwner(budget);output:=FinEnergyPreparedOwner(budget)
    catalog:=FinEnergyCockpitCatalog(records.toImmutable,TimeZone.utc,model)
    ctx:=FinEnergyContext.shared(catalog,"metering",false,layout)
    try
    {
      result:=FinEnergyEnergyFlow.projectPrepared(ctx,q,from,to,|Str id,Bool known->FinEnergyValue| {values[id]},overview,output)
      result["asOf"]=to.toIso;((Map)result["extra"])["relationBasis"]="current"
      verifyEq(result,expected)
      nodes:=FinEnergyMath.maps(((Map)((Map)result["extra"])["energyFlow"])["nodes"])
      node:=nodes.first;verifyEq(node["value"],10f)
      layout.close
      verifyEq(result["warnings"],Str[,],"output warnings survive context closure")
      output.close
      verify(result.isEmpty);verify(node.isEmpty,"all escaped graph DTOs expire with their owner")
      verifyEq(values["t"].sources,["pt"]);verifyEq(FinEnergyMath.maps(overview["rows"]).size,2)
    }
    finally {layout.close;output.close;model.close}
    verifyEq(budget.temporary.val,0)
  }
}

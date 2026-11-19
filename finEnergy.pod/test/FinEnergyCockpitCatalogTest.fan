class FinEnergyCockpitCatalogTest : Test
{
  Void testRequestOwnedUnchangedBusinessFactsShareIdentityButCanonicalChangesStayOwned()
  {
    rows:=records;rows.add(["id":"child","kind":"meter","meterParentId":"alias","categoryId":"c"])
    source:=rows.toImmutable;budget:=FinEnergyStreamBudget().state;owner:=FinEnergyPreparedOwner(budget)
    dim:=FinEnergyDimension.owned("metering",source,false,owner,true,true)
    try
    {
      verify(dim.byId["a"]===source[1]);verify(dim.byId["c"]===source.first);verify(dim.byId["s"]===source[3])
      verify(dim.byId["child"]!==source.last);verifyEq(dim.byId["child"]["meterParentId"],"a")
      verify(dim.byId["expression"]!==source[4]);verifyEq(((Map)dim.byId["expression"]["variables"])["x"],"a")
      ["space","metering","organization"].each |name| {verifyEq(FinEnergyDimension.projected(name,dim,false).records,FinEnergyDimension(name,source).records)}
    }
    finally {owner.close}
    verifyEq(source[1]["name"],"Original A");verifyEq(source.last["meterParentId"],"alias");verifyEq(budget.temporary.val,0)
  }

  Void testOnlyRequestOwnedNonBusinessMetadataCanShareFrozenMapHeads()
  {
    rows:=records;rows.add(["id":"rawPoint","kind":"nativePoint","name":"Raw metadata"]);source:=rows.toImmutable
    budget:=FinEnergyStreamBudget().state;owner:=FinEnergyPreparedOwner(budget)
    dim:=FinEnergyDimension.owned("metering",source,false,owner,true)
    verify(dim.byId["rawPoint"]===source.last);verify(dim.byId["a"]!==source[1])
    verifyEq(((Map)dim.byId["expression"]["variables"])["x"],"a")
    copied:=dim.byId["a"];owner.close;verify(copied.isEmpty);verifyEq(source.last["name"],"Raw metadata");verifyEq(budget.temporary.val,0)
  }

  Void testProjectionMapCopiesAreAdmittedAndClearedWithoutTouchingSource()
  {
    source:=records.toImmutable
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());owner:=FinEnergyPreparedOwner(budget)
    dim:=FinEnergyDimension.owned("metering",source,false,owner)
    // The projection owns new map heads, references and a canonical variables
    // map; those are different objects from the frozen source catalog.
    verify(dim.byId["a"] !== source[1])
    Int copied:=dim.records.reduce(0) |Int n,r->Int| {n+1+r.size}
    copied+=1+((Map)dim.byId["expression"]["variables"]).size
    verify(owner.entries>=copied,"canonical projection copies must be admitted")
    escaped:=dim.byId["a"];vars:=(Map)dim.byId["expression"]["variables"]
    owner.close;verify(escaped.isEmpty);verify(vars.isEmpty);verify(dim.records.isEmpty)
    verifyEq(source[1]["name"],"Original A");verifyEq(((Map)source.last["variables"])["x"],"alias")
    verifyEq(budget.temporary.val,0)
  }
  Void testViewsContextsAndAreaIndicesShareOneProjectionUntilAllOwnersClose()
  {
    source:=records.toImmutable;before:=source.toStr
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());model:=FinEnergyPreparedOwner(budget)
    catalog:=FinEnergyCockpitCatalog(source,TimeZone.utc,model)
    state:=FinEnergyPreparedOwner(budget);other:=FinEnergyPreparedOwner(budget);output:=FinEnergyPreparedOwner(budget)
    a:=FinEnergyContext.shared(catalog,"space",true,state);b:=FinEnergyContext.shared(catalog,"metering",false,other)
    verify(a.byId===b.byId);verify(a.children===b.children);verify(a.dimension.records===b.dimension.records)
    verify(a.dimension!==b.dimension);verify(a.dimension===catalog.view("space",true));verifyEq(((Map)a.byId["expression"]["variables"])["x"],"a")
    held:=model.entries;catalog.bind(state);verifyEq(model.entries,held)
    from:=DateTime.fromIso("2026-01-01T00:00:00Z");q:=Str:Obj?["kind":"profile","from":from.toIso,"to":(from+1hr).toIso,"asOf":(from+1hr).toIso,"metric":"energy"]
    r:=FinEnergyReport(a,q,from,from+1hr,"profile","hour","energy",state)
    s:=FinEnergyReport(b,q,from,from+1hr,"profile","hour","energy",other)
    verify(FinEnergyReport#.field("areas").get(r)===FinEnergyReport#.field("areas").get(s))
    catalog.bind(output);escaped:=catalog.byId["a"];variables:=(Map)catalog.byId["expression"]["variables"]
    verifyErr(ArgErr#) {model.close}
    state.close;verify(a.byId.isEmpty);verifyEq(b.byId["a"]["name"],"Original A")
    other.close;verifyEq(escaped["name"],"Original A");verifyErr(ArgErr#) {model.close}
    output.close;model.close
    verify(escaped.isEmpty);verify(variables.isEmpty);verify(catalog.protectedRoots.isEmpty)
    verifyErr(ArgErr#) {catalog.view("space")};verifyEq(source.toStr,before);verifyEq(budget.temporary.val,0)
  }

  Void testProjectionRejectionAndCanonicalFailurePreservePeerAndSource()
  {
    source:=records.toImmutable;before:=source.toStr
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());peer:=FinEnergyPreparedOwner(budget);model:=FinEnergyPreparedOwner(budget)
    peer.hold(budget.remaining-80);held:=peer.entries
    verifyErr(FinEnergyHttpErr#) {rejected:=FinEnergyCockpitCatalog(source,TimeZone.utc,model)}
    model.close;verifyEq(budget.temporary.val,held);peer.close;verifyEq(budget.temporary.val,0);verifyEq(source.toStr,before)
    bad:=records;bad.last["variables"]=["x":"notFound"]
    model=FinEnergyPreparedOwner(budget)
    // canonical() preserves unknown ordinary IDs; an explicit unknown alias is invalid.
    bad[2]["canonicalId"]="notFound"
    verifyErr(ArgErr#) {rejected:=FinEnergyCockpitCatalog(bad.toImmutable,TimeZone.utc,model)}
    model.close;verifyEq(budget.temporary.val,0)
  }

  Void testForeignAndAlreadyClosedBorrowersAreRejected()
  {
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());model:=FinEnergyPreparedOwner(budget)
    catalog:=FinEnergyCockpitCatalog(records.toImmutable,TimeZone.utc,model)
    foreign:=FinEnergyPreparedOwner(FinEnergyPreparedBudget(FinEnergyCockpitDeadline()))
    closed:=FinEnergyPreparedOwner(budget);closed.close
    verifyErr(ArgErr#) {catalog.bind(foreign)};verifyErr(ArgErr#) {catalog.bind(model)};verifyErr(ArgErr#) {catalog.bind(closed)}
    foreign.close;model.close;verifyEq(budget.temporary.val,0)
  }
  Void testFailedStateCloseWithAnActiveFrameStillProtectsModel()
  {
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());model:=FinEnergyPreparedOwner(budget)
    catalog:=FinEnergyCockpitCatalog(records.toImmutable,TimeZone.utc,model)
    state:=FinEnergyPreparedOwner(budget);ctx:=FinEnergyContext.shared(catalog,"metering",false,state)
    frame:=FinEnergyPreparedOwner(budget);ctx.beginFrame(frame,Str:FinEnergyHistoryData[:])
    verifyErr(ArgErr#) {state.close};verifyErr(ArgErr#) {model.close}
    verifyEq(catalog.byId["a"]["name"],"Original A");verify(state.entries>0)
    frame.close;state.close;model.close;verifyEq(budget.temporary.val,0)
  }

  Void testAllNewProjectionAndIndexContainersAreCountedOnceAcrossViews()
  {
    rs:=records
    for(i:=0;i<1000;i++) rs.add(["id":"point$i","kind":"nativePoint","name":"Point $i","unit":"kWh","nativeSourceId":"point$i","nativeSourceKind":"point","nativeTreeParentId":"a","nativeHis":true,"nativePoint":true,"siteRef":"site","equipRef":"a","writable":false,"nativeDis":"Original $i","nativeMod":"fixed","moreMetadata":true])
    source:=rs.toImmutable;borrowed:=Obj[,];collect(source,borrowed)
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());model:=FinEnergyPreparedOwner(budget)
    catalog:=FinEnergyCockpitCatalog(source,TimeZone.utc,model)
    ["space","metering","organization"].each |name| {verifyEq(catalog.view(name).records,FinEnergyDimension(name,source).records)}
    projection:=(FinEnergyDimension)FinEnergyCockpitCatalog#.field("projection").get(catalog)
    roots:=Obj?[catalog.records,catalog.byId,catalog.children,catalog.protectedRoots,FinEnergyDimension#.field("originals").get(projection),FinEnergyCockpitCatalog#.field("views").get(catalog),FinEnergyCockpitCatalog#.field("pointUnits").get(catalog),FinEnergyArea#.field("byId").get(catalog.areas),FinEnergyArea#.field("nativeIds").get(catalog.areas)]
    seen:=Obj[,];Int retained:=roots.reduce(0) |Int n,r->Int| {n+count(r,borrowed,seen)}
    verify(model.entries>=retained,"all new canonical record heads, variable maps, indices and protection references are admitted")
    echo("CATALOG_GRAPH retained="+retained+" admitted="+model.entries+" peak="+budget.peak.val)
    model.close;verifyEq(budget.temporary.val,0);verifyEq(source[1]["name"],"Original A")
  }
  Void testPrimaryPointUnitIsAvailableBeforeFirstHistoryFrame()
  {
    rs:=records;rs.first.remove("unit");units:=Str:Str["pa":"kWh"]
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());model:=FinEnergyPreparedOwner(budget)
    catalog:=FinEnergyCockpitCatalog(rs.toImmutable,TimeZone.utc,model,units)
    state:=FinEnergyPreparedOwner(budget);ctx:=FinEnergyContext.shared(catalog,"metering",false,state)
    units["pa"]="m³"
    verifyEq(ctx.unit("a","c","energy"),"kWh","metadata-only report definition must retain the frozen primary point unit")
    known:=FinEnergyContext.known(ctx,DateTime.fromIso("2026-01-01T00:00:00Z"));verifyEq(known.unit("a","c","energy"),"kWh")
    state.close;model.close;verifyEq(budget.temporary.val,0)
  }
  private Void collect(Obj? value,Obj[] borrowed)
  {
    if(value isnot Map && value isnot List) return
    if(borrowed.any |v| {v===value}) return
    borrowed.add(value)
    if(value is Map) ((Map)value).each |v| {collect(v,borrowed)}
    else ((List)value).each |v| {collect(v,borrowed)}
  }
  private Int count(Obj? value,Obj[] borrowed,Obj[] seen)
  {
    if(value isnot Map && value isnot List) return 0
    if(borrowed.any |v| {v===value} || seen.any |v| {v===value}) return 0
    seen.add(value)
    if(value is Map) return ((Map)value).vals.reduce(1+((Map)value).size) |Int n,v->Int| {n+count(v,borrowed,seen)}
    return ((List)value).reduce(1+((List)value).size) |Int n,v->Int| {n+count(v,borrowed,seen)}
  }
  private [Str:Obj?][] records()
  {
    [["id":"c","kind":"category","unit":"kWh"],
     ["id":"a","kind":"meter","name":"Original A","pointId":"pa","categoryId":"c","parentId":"s","nativeArea":["value":10f,"unit":"m²"]],
     ["id":"alias","kind":"meter","canonicalId":"a","pointId":"pa","categoryId":"c"],
     ["id":"s","kind":"space","area":100f],
     ["id":"expression","kind":"expression","variables":["x":"alias"],"expression":"x"]]
  }
}

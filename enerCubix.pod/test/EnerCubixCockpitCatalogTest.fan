class EnerCubixCockpitCatalogTest : Test
{
  Void testOnlyRequestOwnedNonBusinessMetadataCanShareFrozenMapHeads()
  {
    rows:=records;rows.add(["id":"rawPoint","kind":"nativePoint","name":"Raw metadata"]);source:=rows.toImmutable
    budget:=EnerCubixStreamBudget().state;owner:=EnerCubixPreparedOwner(budget)
    dim:=EnerCubixDimension.owned("metering",source,false,owner,true)
    verify(dim.byId["rawPoint"]===source.last);verify(dim.byId["a"]!==source[1])
    verifyEq(((Map)dim.byId["expression"]["variables"])["x"],"a")
    copied:=dim.byId["a"];owner.close;verify(copied.isEmpty);verifyEq(source.last["name"],"Raw metadata");verifyEq(budget.temporary.val,0)
  }

  Void testProjectionMapCopiesAreAdmittedAndClearedWithoutTouchingSource()
  {
    source:=records.toImmutable
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
    dim:=EnerCubixDimension.owned("metering",source,false,owner)
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
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());model:=EnerCubixPreparedOwner(budget)
    catalog:=EnerCubixCockpitCatalog(source,TimeZone.utc,model)
    state:=EnerCubixPreparedOwner(budget);other:=EnerCubixPreparedOwner(budget);output:=EnerCubixPreparedOwner(budget)
    a:=EnerCubixContext.shared(catalog,"space",true,state);b:=EnerCubixContext.shared(catalog,"metering",false,other)
    verify(a.byId===b.byId);verify(a.children===b.children);verify(a.dimension.records===b.dimension.records)
    verify(a.dimension!==b.dimension);verify(a.dimension===catalog.view("space",true));verifyEq(((Map)a.byId["expression"]["variables"])["x"],"a")
    held:=model.entries;catalog.bind(state);verifyEq(model.entries,held)
    from:=DateTime.fromIso("2026-01-01T00:00:00Z");q:=Str:Obj?["kind":"profile","from":from.toIso,"to":(from+1hr).toIso,"asOf":(from+1hr).toIso,"metric":"energy"]
    r:=EnerCubixReport(a,q,from,from+1hr,"profile","hour","energy",state)
    s:=EnerCubixReport(b,q,from,from+1hr,"profile","hour","energy",other)
    verify(EnerCubixReport#.field("areas").get(r)===EnerCubixReport#.field("areas").get(s))
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
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());peer:=EnerCubixPreparedOwner(budget);model:=EnerCubixPreparedOwner(budget)
    peer.hold(budget.remaining-80);held:=peer.entries
    verifyErr(EnerCubixHttpErr#) {rejected:=EnerCubixCockpitCatalog(source,TimeZone.utc,model)}
    model.close;verifyEq(budget.temporary.val,held);peer.close;verifyEq(budget.temporary.val,0);verifyEq(source.toStr,before)
    bad:=records;bad.last["variables"]=["x":"notFound"]
    model=EnerCubixPreparedOwner(budget)
    // canonical() preserves unknown ordinary IDs; an explicit unknown alias is invalid.
    bad[2]["canonicalId"]="notFound"
    verifyErr(ArgErr#) {rejected:=EnerCubixCockpitCatalog(bad.toImmutable,TimeZone.utc,model)}
    model.close;verifyEq(budget.temporary.val,0)
  }

  Void testForeignAndAlreadyClosedBorrowersAreRejected()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());model:=EnerCubixPreparedOwner(budget)
    catalog:=EnerCubixCockpitCatalog(records.toImmutable,TimeZone.utc,model)
    foreign:=EnerCubixPreparedOwner(EnerCubixPreparedBudget(EnerCubixCockpitDeadline()))
    closed:=EnerCubixPreparedOwner(budget);closed.close
    verifyErr(ArgErr#) {catalog.bind(foreign)};verifyErr(ArgErr#) {catalog.bind(model)};verifyErr(ArgErr#) {catalog.bind(closed)}
    foreign.close;model.close;verifyEq(budget.temporary.val,0)
  }
  Void testFailedStateCloseWithAnActiveFrameStillProtectsModel()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());model:=EnerCubixPreparedOwner(budget)
    catalog:=EnerCubixCockpitCatalog(records.toImmutable,TimeZone.utc,model)
    state:=EnerCubixPreparedOwner(budget);ctx:=EnerCubixContext.shared(catalog,"metering",false,state)
    frame:=EnerCubixPreparedOwner(budget);ctx.beginFrame(frame,Str:EnerCubixHistoryData[:])
    verifyErr(ArgErr#) {state.close};verifyErr(ArgErr#) {model.close}
    verifyEq(catalog.byId["a"]["name"],"Original A");verify(state.entries>0)
    frame.close;state.close;model.close;verifyEq(budget.temporary.val,0)
  }

  Void testAllNewProjectionAndIndexContainersAreCountedOnceAcrossViews()
  {
    rs:=records
    for(i:=0;i<1000;i++) rs.add(["id":"point$i","kind":"nativePoint","name":"Point $i","unit":"kWh","nativeSourceId":"point$i","nativeSourceKind":"point","nativeTreeParentId":"a","nativeHis":true,"nativePoint":true,"siteRef":"site","equipRef":"a","writable":false,"nativeDis":"Original $i","nativeMod":"fixed","moreMetadata":true])
    source:=rs.toImmutable;borrowed:=Obj[,];collect(source,borrowed)
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());model:=EnerCubixPreparedOwner(budget)
    catalog:=EnerCubixCockpitCatalog(source,TimeZone.utc,model)
    ["space","metering","organization"].each |name| {verifyEq(catalog.view(name).records,EnerCubixDimension(name,source).records)}
    projection:=(EnerCubixDimension)EnerCubixCockpitCatalog#.field("projection").get(catalog)
    roots:=Obj?[catalog.records,catalog.byId,catalog.children,catalog.protectedRoots,EnerCubixDimension#.field("originals").get(projection),EnerCubixCockpitCatalog#.field("views").get(catalog),EnerCubixCockpitCatalog#.field("pointUnits").get(catalog),EnerCubixArea#.field("byId").get(catalog.areas),EnerCubixArea#.field("nativeIds").get(catalog.areas)]
    seen:=Obj[,];Int retained:=roots.reduce(0) |Int n,r->Int| {n+count(r,borrowed,seen)}
    verify(model.entries>=retained,"all new canonical record heads, variable maps, indices and protection references are admitted")
    echo("CATALOG_GRAPH retained="+retained+" admitted="+model.entries+" peak="+budget.peak.val)
    model.close;verifyEq(budget.temporary.val,0);verifyEq(source[1]["name"],"Original A")
  }
  Void testPrimaryPointUnitIsAvailableBeforeFirstHistoryFrame()
  {
    rs:=records;rs.first.remove("unit");units:=Str:Str["pa":"kWh"]
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());model:=EnerCubixPreparedOwner(budget)
    catalog:=EnerCubixCockpitCatalog(rs.toImmutable,TimeZone.utc,model,units)
    state:=EnerCubixPreparedOwner(budget);ctx:=EnerCubixContext.shared(catalog,"metering",false,state)
    units["pa"]="m³"
    verifyEq(ctx.unit("a","c","energy"),"kWh","metadata-only report definition must retain the frozen primary point unit")
    known:=EnerCubixContext.known(ctx,DateTime.fromIso("2026-01-01T00:00:00Z"));verifyEq(known.unit("a","c","energy"),"kWh")
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

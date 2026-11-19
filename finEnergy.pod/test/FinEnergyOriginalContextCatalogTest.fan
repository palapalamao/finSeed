** COP's ordinary path indexes the original records while its dimension resolves
** aliases. Preserve that combination; a canonical context is not interchangeable.
class FinEnergyOriginalContextCatalogTest : Test
{
  Void testOriginalIndexAreaAndCanonicalCopiesAreAllAdmittedWithoutOwningInput()
  {
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"a","kind":"meter","pointId":"pa","categoryId":"c"]]
    (0..<50).each |i| {rs.add(["id":"alias"+i,"kind":"meter","canonicalId":"a","pointId":"pa","categoryId":"c"])}
    (0..<500).each |i| {rs.add(["id":"point"+i,"kind":"nativePoint","unit":"kWh","nativeTreeParentId":"a"])}
    source:=rs.toImmutable;borrowed:=Obj[,];collect(source,borrowed)
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());model:=FinEnergyPreparedOwner(budget)
    catalog:=FinEnergyCockpitCatalog(source,TimeZone.utc,model,[:],true)
    ["space","metering","organization"].each |view| {catalog.view(view)}
    projection:=(FinEnergyDimension)FinEnergyCockpitCatalog#.field("projection").get(catalog)
    roots:=Obj?[catalog.records,catalog.byId,catalog.children,catalog.protectedRoots,FinEnergyDimension#.field("originals").get(projection),projection.byId,projection.records,FinEnergyCockpitCatalog#.field("views").get(catalog),FinEnergyCockpitCatalog#.field("pointUnits").get(catalog),FinEnergyArea#.field("byId").get(catalog.areas),FinEnergyArea#.field("nativeIds").get(catalog.areas)]
    seen:=Obj[,];cells:=0;roots.each |root| {cells+=count(root,borrowed,seen)}
    verify(model.entries>=cells,"original lookup plus canonical projection/area/protection indices are admitted")
    index:=catalog.byId;fact:=index["alias0"]
    model.close;verify(index.isEmpty);verifyEq(fact["canonicalId"],"a");verify(fact.isImmutable)
    verifyEq(source.size,552);verifyEq(budget.temporary.val,0)
  }
  private Void collect(Obj? value,Obj[] roots)
  {
    if(value isnot Map && value isnot List) return
    if(roots.any |r| {r===value}) return
    roots.add(value)
    if(value is Map) ((Map)value).each |child| {collect(child,roots)}
    else ((List)value).each |child| {collect(child,roots)}
  }
  private Int count(Obj? value,Obj[] borrowed,Obj[] seen)
  {
    if(value isnot Map && value isnot List) return 0
    if(borrowed.any |r| {r===value} || seen.any |r| {r===value}) return 0
    seen.add(value);cells:=1+(value is Map ? ((Map)value).size : ((List)value).size)
    if(value is Map) ((Map)value).each |child| {cells+=count(child,borrowed,seen)}
    else ((List)value).each |child| {cells+=count(child,borrowed,seen)}
    return cells
  }
  Void testOriginalLookupAndCanonicalDimensionMatchOrdinaryCopContext()
  {
    source:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"a","kind":"meter","name":"A","pointId":"pa","categoryId":"c"],["id":"alias","kind":"meter","name":"Legacy","pointId":"pa","categoryId":"c","canonicalId":"a","configurationError":"invalidPrimaryPoint"],["id":"e","kind":"expression","variables":["x":"alias"],"formula":"x"]].toImmutable
    original:=FinEnergyContext(source,[Str:Obj?][,],TimeZone.utc,FinEnergyDimension("metering",source))
    from:=DateTime.fromIso("2026-01-01T00:00:00Z");to:=from+1hr
    expected:=original.nodeTotal("alias",from,to)
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());model:=FinEnergyPreparedOwner(budget);state:=FinEnergyPreparedOwner(budget);frame:=FinEnergyPreparedOwner(budget)
    catalog:=FinEnergyCockpitCatalog(source,TimeZone.utc,model,[:],true)
    ctx:=FinEnergyContext.shared(catalog,"metering",false,state)
    try
    {
      verify(ctx.byId.containsKey("alias"));verify(!ctx.dimension.byId.containsKey("alias"))
      verifyEq(((Map)ctx.byId["e"]["variables"])["x"],"alias")
      verifyEq(((Map)ctx.dimension.byId["e"]["variables"])["x"],"a")
      ctx.beginFrame(frame,Str:FinEnergyHistoryData[:]);actual:=ctx.nodeTotal("alias",from,to)
      verifyEq(actual.value,expected.value);verifyEq(actual.quality,expected.quality);verifyEq(actual.sources,expected.sources);verifyEq(ctx.warnings,original.warnings)
      verifyErr(ArgErr#) {model.close}
    }
    finally {frame.close;state.close;model.close}
    verifyEq(source[2]["name"],"Legacy");verifyEq(((Map)source[3]["variables"])["x"],"alias")
    verifyEq(budget.temporary.val,0);verifyEq(budget.unprepared.val,0)
  }
}

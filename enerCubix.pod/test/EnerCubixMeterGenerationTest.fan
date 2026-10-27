using haystack
using folio

** Legacy background entrypoints must neither create points nor change histories.
class EnerCubixMeterGenerationTest : Test
{
  Void testRetiredBackgroundPreservesPrimaryAndLegacyArchiveRecords()
  {
    dir:=Env.cur.tempDir+`primary-only-${Uuid()}/`;dir.create
    db:=(Folio)Type.find("hxFolio::HxFolio").method("open").call(FolioConfig {name="primaryOnly";it.dir=dir;log=Log.get("primaryOnly")})
    try
    {
      at:=DateTime.fromIso("2026-10-27T00:00:00Z")
      eq:=db.commit(Diff.makeAdd(Etc.makeDict(["equip":Marker.val,"enerCubix":Marker.val,"enerCubixKind":"meter","enerCubixPointRef":Ref("primary"),"enerCubixCleaningEnabled":Marker.val]),Ref("meter"))).newRec
      primary:=db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"kind":"Number","unit":"kWh","tz":"UTC","equipRef":eq.id]),Ref("primary"))).newRec
      db.his.write(primary.id,[HisItem(at,Number(100,Unit("kWh"))),HisItem(at+1hr,Number(107,Unit("kWh")))],null).get(30sec)
      archive:=db.commit(Diff.makeAdd(Etc.makeDict(["enerCubixIntervalBatch":Marker.val,"enerCubixIntervals":"legacy data retained"]))).newRec
      before:=db.readAllList(Filter.has("id")).map |r->Str| {ZincWriter.valToStr(r)}.sort
      EnerCubixMeterGeneration.update(db,at);EnerCubixMeterGeneration.update(db,at+3min)
      EnerCubixMeterGeneration.ensure(db,EnerCubixNativeEquip.decode(eq),[Str:Obj?][,],at)
      verifyEq(db.readAllList(Filter.has("id")).map |r->Str| {ZincWriter.valToStr(r)}.sort,before)
      verifyNull(EnerCubixMeterHistory.loadDb(db,primary,at,at+1hr))
      verifyErr(ArgErr#) {EnerCubixMeterGeneration.recalculate(db,[Str:Obj?][,],at,at+1hr)}
      verifyErr(ArgErr#) {EnerCubixMeterGeneration.publish(db,primary,archive,at,at+1min,EnerCubixValue(2f,"derived"),at,false)}
      samples:=HisItem[,];db.his.read(primary.id,null,null) |item| {samples.add(item)}
      verifyEq(samples.size,2);verifyEq(samples.last.val,Number(107,Unit("kWh")))
    }
    finally {db.close;if (dir.parent.normalize == Env.cur.tempDir.normalize) dir.delete}
  }
}

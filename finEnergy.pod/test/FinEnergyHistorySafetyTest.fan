using haystack
using folio

class FinEnergyHistorySafetyTest : Test
{
  Void testRepairRequiresExplicitRangeAndConfirmation()
  {
    verifyErr(ArgErr#) { FinEnergyHistorySafety.repairRequested([:]) }
    verifyErr(ArgErr#) { FinEnergyHistorySafety.repairRequested(["from":"2026-01-01","to":"2026-01-02"]) }
    verifyErr(ArgErr#) { FinEnergyHistorySafety.repairRequested(["confirmHistoryRewrite":true]) }
    verifyErr(ArgErr#) {FinEnergyHistorySafety.repairRequested(["confirmHistoryRewrite":true,"from":"2026-01-01","to":"2026-01-02"])}
    verifyErr(ArgErr#) {FinEnergyHistorySafety.repairRequested(["confirmHistoryRewrite":true],true)}
  }

  Void testMetadataCannotTrashOrDeleteHistoryButCanRemoveConfiguration()
  {
    withDb |db|
    {
      ["point","his","finEnergyIntervalBatch","finEnergyMeterGeneration","finEnergyIntervalCorrection"].each |tag|
      {
        record:=db.commit(Diff.makeAdd(Etc.makeDict([tag:Marker.val]))).newRec
        verifyErr(ArgErr#) { FinEnergyHistorySafety.metadata(db,[Diff(record,null,Diff.remove)]) }
        verifyErr(ArgErr#) { FinEnergyHistorySafety.metadata(db,[Diff(record,Etc.makeDict(["trash":Marker.val]))]) }
        verifyNotNull(db.readById(record.id))
        verifyFalse(db.readById(record.id).has("trash"))
      }
      configuration:=db.commit(Diff.makeAdd(Etc.makeDict(["finEnergyKind":"template"]))).newRec
      FinEnergyHistorySafety.metadata(db,[Diff(configuration,null,Diff.remove)])
      FinEnergyHistorySafety.metadata(db,[Diff(configuration,Etc.makeDict(["trash":Remove.val]))])
      verifyErr(ArgErr#) { FinEnergyHistorySafety.metadata(db,[Diff.makeAdd(Etc.makeDict(["trash":Marker.val]))]) }
    }
  }

  Void testAppendReplayConflictAndExplicitRepair()
  {
    withDb |db|
    {
      point:=db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"finEnergyComputed":Marker.val,"kind":"Number","unit":"kWh","tz":"UTC"]))).newRec
      at:=DateTime.fromIso("2026-01-01T00:00:00Z")
      first:=HisItem(at,Number(7,Unit("kWh")))
      verifyErr(ArgErr#) {FinEnergyHistorySafety.write(db,point,[first])}
      verifyErr(ArgErr#) {FinEnergyHistorySafety.write(db,point,[first],true)}
      rows:=HisItem[,];db.his.read(point.id,null,null) |item| {rows.add(item)}
      verify(rows.isEmpty)

    }
  }

  private Void withDb(|Folio| work)
  {
    dir:=Env.cur.tempDir+`finEnergy-history-safety-${Uuid()}/`;dir.create
    db:=(Folio)Type.find("hxFolio::HxFolio").method("open").call(FolioConfig {name="historySafety";it.dir=dir;log=Log.get("historySafety")})
    try {work(db)}
    finally {db.close;if (dir.parent.normalize == Env.cur.tempDir.normalize) dir.delete}
  }
}

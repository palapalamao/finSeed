** The frame consumer gets the same own-meter requests as original finalization.
class FinEnergyReportLedgerTest : Test
{
  Void testSelectionThenDetailsIncludeOtherCategoriesAndExplicitExcludedMeter()
  {
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"water","kind":"category","unit":"m³"],["id":"s","kind":"space","nativeSourceKind":"site"],["id":"t","kind":"totalMeter","pointId":"pt","categoryId":"c","spaceId":"s","nativeSpaceId":"s"],["id":"a","kind":"meter","pointId":"pa","categoryId":"c","spaceId":"s","nativeSpaceId":"s","meterParentId":"t"],["id":"b","kind":"meter","pointId":"pb","categoryId":"c","spaceId":"s","nativeSpaceId":"s","meterParentId":"t"],["id":"x","kind":"meter","pointId":"px","categoryId":"c","spaceId":"s","nativeSpaceId":"s","meterParentId":"t","includeInTotals":false],["id":"w","kind":"meter","pointId":"pw","categoryId":"water","spaceId":"s","nativeSpaceId":"s"]]
    dimension:=FinEnergyDimension("space",rs,true)
    ctx:=FinEnergyContext(dimension.records,[Str:Obj?][,],TimeZone.utc,dimension)
    q:=Str:Obj?["kind":"profile","dimension":"space","spaceSource":"fin","nodeIds":["s","x"],"metric":"energy","period":"day","from":at.toIso,"to":(at+2hr).toIso,"asOf":(at+2hr).toIso,"tz":"UTC"]
    report:=FinEnergyReport(ctx,q,at,at+2hr,"profile","day","energy")
    lines:=[report.openLine("s","c").line,report.openLine("x","c").line]
    ledger:=report.frameLedger(lines)
    verifyEq(ledger.map |r->Str| {r["id"].toStr},["t","a","b","w","x"])
    verifyEq(ledger.map |r->Str| {r["category"].toStr},["c","c","c","water","c"])
    verifyEq(ledger.first["phase"],1)
    verify(ledger[1..-1].all |r| {r["phase"] == 3})
    verifyEq(ledger.map |r->Str| {r["id"].toStr}.unique.size,ledger.size)
  }

  Void testLegacyMasterSuppressesChildrenForRangeButNotExplicitOwnReads()
  {
    rs:=[Str:Obj?][["id":"c","kind":"category","unit":"kWh"],["id":"g","kind":"group"],["id":"t","kind":"totalMeter","pointId":"pt","categoryId":"c","parentId":"g"],["id":"a","kind":"meter","pointId":"pa","categoryId":"c","parentId":"g"]]
    ctx:=FinEnergyContext(rs,[Str:Obj?][,],TimeZone.utc)
    q:=Str:Obj?["from":at.toIso,"to":(at+2hr).toIso,"asOf":(at+2hr).toIso,"metric":"energy"]
    report:=FinEnergyReport(ctx,q,at,at+2hr,"profile","day","energy")
    ledger:=report.frameLedger([report.openLine("g","c").line,report.openLine("a","c").line])
    verifyEq(ledger.map |r->Str| {r["id"].toStr},["a","t"])
    verify(ledger.all |r| {r["phase"] == 1})
  }

  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

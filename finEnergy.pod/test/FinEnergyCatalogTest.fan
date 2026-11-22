using haystack
using util

class FinEnergyCatalogTest : Test
{
  Void testOperationalBodiesAreNotParsedInAnalysisCatalog()
  {
    ["alarm","job"].each |kind|
    {
      rec:=Etc.makeDict(["id":Ref("operational"),"mod":DateTime.now,"finEnergy":Marker.val,"finEnergyKind":kind,"dis":"Original name","finEnergyConfig":"not-json"])
      light:=FinEnergyCatalog.decode(rec,true)
      verifyEq(light["id"],"operational");verifyEq(light["kind"],kind);verifyEq(light["name"],"Original name")
      verifyEq(light["catalogDeferred"],true);verifyFalse(light.containsKey("snapshot"))
      verifyErr(NullErr#) {FinEnergyCatalog.decode(rec,false)}
    }
  }
  Void testTemplatesAndBusinessRecordsRetainEverySelectionField()
  {
    ["template","meter","totalMeter","category","binding","settings"].each |kind|
    {
      rec:=Etc.makeDict(["id":Ref("business"),"finEnergy":Marker.val,"finEnergyKind":kind,"dis":"Business","finEnergyConfig":JsonOutStream.writeJsonToStr(["unit":"kWh","request":["nodeIds":["site","floor"],"from":"2026-01-01","to":"2026-11-01"],"pointId":"primary"] )])
      verifyEq(FinEnergyCatalog.decode(rec,true),FinEnergyCatalog.decode(rec,false))
    }
  }
}

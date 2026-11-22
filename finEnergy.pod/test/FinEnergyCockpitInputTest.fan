using haystack
using util

class FinEnergyCockpitInputTest : Test
{
  Void testArchiveHeavy1113RecordInputFitsTheUnchangedRequestBudget()
  {
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline(30sec))
    preparation:=FinEnergyPreparedOwner(budget);output:=FinEnergyPreparedOwner(budget)
    try
    {
      rows:=[Str:Obj?][,]
      archive:=(0..<100).map |i->Str:Obj?| {["id":"prior-"+i,"nested":["rules":[1,2,3,4],"before":["setting":"retained only for recovery"]]]}
      config:=JsonOutStream.writeJsonToStr(["unit":"kWh","before":archive,"after":archive,"snapshot":archive])
      for(i:=0;i<1113;i++)
      {
        kind:=i<702 ? "alarm" : (i<1084 ? "job" : "category")
        json:=i<1084 ? config : "{\"unit\":\"kWh\"}"
        r:=Etc.makeDict(["id":Ref("row-"+i),"finEnergy":Marker.val,"finEnergyKind":kind,"finEnergyConfig":json,"dis":"record "+i,"finEnergyCategoryRef":Ref("category")])
        rows.add(FinEnergyCockpitInput.decode(r,preparation))
      }
      frozen:=(List)FinEnergyCockpitFreeze.value(rows,output)
      verifyEq(frozen.size,1113)
      verify(frozen.isImmutable);verify(budget.peak.val<200000)
      first:=(Map)frozen.first
      verifyEq(first["unit"],"kWh");verifyEq(first["categoryId"],"category")
      verify(!first.containsKey("before"));verify(!first.containsKey("snapshot"))
    }
    finally {output.close;preparation.close}
    verifyEq(budget.prepared.val+budget.temporary.val,0)
  }
  Void testOperationalHeadersKeepUnitsIdentityAndPermissionCompatibility()
  {
    raw:=Etc.makeDict(["id":Ref("native-point-collision"),"finEnergyKind":"alarm","dis":"Customer event",
      "finEnergyCategoryRef":Ref("category"),"finEnergyCanonicalRef":Ref("other"),
      "finEnergyConfig":"{\"unit\":\"Wh\",\"enabled\":false,\"zero\":0,\"before\":{\"large\":[1,2]},\"nativeAlarmArchive\":\"retained in FIN\"}"])
    value:=FinEnergyCockpitInput.decode(raw,null)
    verifyEq(value["id"],"native-point-collision");verifyEq(value["categoryId"],"category")
    verifyEq(value["canonicalId"],"other");verifyEq(value["name"],"Customer event")
    verifyEq(value["unit"],"Wh");verifyEq(value["enabled"],false);verifyEq(value["zero"],0)
    verify(!value.containsKey("before"));verify(!value.containsKey("nativeAlarmArchive"))
    ordinary:=FinEnergyRepo.decode(raw)
    verify(ordinary["before"] is Map);verifyEq(ordinary["nativeAlarmArchive"],"retained in FIN")
  }
  Void testConfigurationTokenRetainsUnitInferenceButIgnoresOperationalProgress()
  {
    category:=Str:Obj?["id":"c","kind":"category","name":"Energy"]
    alarm:=Str:Obj?["id":"a","kind":"alarm","categoryId":"c","unit":"kWh","state":"open"]
    records:=[category,alarm]
    first:=FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc)
    token:=FinEnergyCockpitInput.token(first,records,[:],"test","UTC")
    alarm["state"]="acknowledged";alarm["lastRun"]="later"
    verifyEq(FinEnergyCockpitInput.token(FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc),records,[:],"test","UTC"),token)
    alarm["unit"]="Wh"
    verify(FinEnergyCockpitInput.token(FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc),records,[:],"test","UTC")!=token)
    category["unit"]="kWh"
    configured:=FinEnergyCockpitInput.token(FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc),records,[:],"test","UTC")
    alarm["unit"]="MWh"
    verifyEq(FinEnergyCockpitInput.token(FinEnergyContext(records,[Str:Obj?][,],TimeZone.utc),records,[:],"test","UTC"),configured)
  }
}

class FinEnergyUtilityMeteringTest : Test
{
  Void testExplicitlySelectedExcludedMetersRemainAnalyzable()
  {
    rs:=records
    rs.findAll |r| { ["meter","totalMeter"].contains(r["kind"]?.toStr ?: "") }.each |r| { r["includeInTotals"]=false }
    master:=rs.find |r| { r["id"] == "master" }; master["utilityId"]="lighting"
    req:=request("master")
    report:=FinEnergyEngine.report(req,rs,histories)
    shares:=FinEnergyMath.maps(((Map)report["extra"])["utilityShares"])
    verifyEq(shares.size,1); verifyEq(shares.first["value"],100f)
    verifyEq(shares.first["sourceIds"],["pm"])
    verifyEq(FinEnergyDimension.dependencies(req,rs)["points"],["pm"])
    req["nodeIds"]=["a"]
    leaf:=FinEnergyEngine.report(req,rs,histories)
    verifyEq(FinEnergyMath.maps(FinEnergyMath.maps(leaf["series"]).first["points"]).first["value"],20f)
    // Explicit selection does not opt this branch into automatic parent totals.
    verifyEq(FinEnergyDimension("metering",rs).roots.size,0)
    verifyEq(master["includeInTotals"],false)
  }

  Void testMeterScopeExpandsToNonoverlappingOwnLeafReadings()
  {
    rs:=records; req:=request("master")
    report:=FinEnergyEngine.report(req,rs,histories)
    shares:=FinEnergyMath.maps(((Map)report["extra"])["utilityShares"])
    verifyEq(shares.size,3)
    verifyEq(shares.find |r| {r["utilityId"]=="lighting"}["value"],20f)
    verifyEq(shares.find |r| {r["utilityId"]=="cooling"}["value"],10f)
    verifyEq(shares.find |r| {r["utilityId"]==""}["value"],5f)
    details:=FinEnergyMath.maps(((Map)report["extra"])["utilityMembers"])
    verifyEq(details.map |r->Str| {r["nodeId"].toStr},["a","b","c"])
    verifyEq(FinEnergyMath.maps(((Map)report["extra"])["scopeTotals"]).first["value"],35f)
    req["kind"]="profile"
    verifyEq(FinEnergyMath.maps(FinEnergyMath.maps(FinEnergyEngine.report(req,rs,histories)["series"]).first["points"]).first["value"],100f)
  }

  Void testLeafScopeDependenciesAndMissingRemainExplicit()
  {
    req:=request("a")
    report:=FinEnergyEngine.report(req,records,histories)
    verifyEq(FinEnergyMath.maps(report["series"]).size,1)
    verifyEq(FinEnergyMath.maps(FinEnergyMath.maps(report["series"]).first["points"]).first["value"],20f)
    verifyEq(FinEnergyDimension.dependencies(request("master"),records)["points"],["pa","pb","pc"])
    hs:=histories.findAll |h| { h["pointId"] != "pa" }
    report=FinEnergyEngine.report(req,records,hs)
    p:=FinEnergyMath.maps(FinEnergyMath.maps(report["series"]).first["points"]).first
    verifyNull(p["value"]); verifyEq(p["quality"],"missing")
    verifyErr(ArgErr#) { FinEnergyEngine.report(request("sensor"),records,histories) }
  }

  private [Str:Obj?][] records()
  {
    return [
      [Str:Obj?]["id":"electric","kind":"category","name":"electric","unit":"kWh"],
      [Str:Obj?]["id":"lighting","kind":"utility","name":"lighting"],
      [Str:Obj?]["id":"cooling","kind":"utility","name":"cooling"],
      meter("master","pm",null,null,"totalMeter"),meter("middle","pmed","master","lighting","totalMeter"),
      meter("a","pa","middle","lighting"),meter("b","pb","middle","cooling"),meter("c","pc","master",null),
      meter("sensor","ps","master",null,"sensor"),
    ]
  }
  private Str:Obj? meter(Str id,Str point,Str? parent,Str? utility,Str kind:="meter")
  { ["id":id,"kind":kind,"name":id,"pointId":point,"meterParentId":parent,"utilityId":utility,"categoryId":"electric","unit":"kWh"] }
  private [Str:Obj?][] histories()
  { [history("pm",100f),history("pmed",40f),history("pa",20f),history("pb",10f),history("pc",5f)] }
  private Str:Obj? history(Str point,Float val)
  { ["pointId":point,"unit":"kWh","mode":"interval","samples":[[Str:Obj?]["ts":"2026-01-01T00:00:00Z","value":val]]] }
  private Str:Obj? request(Str id)
  { ["kind":"utility","dimension":"metering","nodeIds":[id],"from":"2026-01-01T00:00:00Z","to":"2026-01-01T01:00:00Z","period":"hour","metric":"energy","tz":"UTC"] }
}

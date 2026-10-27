class EnerCubixUtilityMeteringTest : Test
{
  Void testExplicitlySelectedExcludedMetersRemainAnalyzable()
  {
    rs:=records
    rs.findAll |r| { ["meter","totalMeter"].contains(r["kind"]?.toStr ?: "") }.each |r| { r["includeInTotals"]=false }
    master:=rs.find |r| { r["id"] == "master" }; master["utilityId"]="lighting"
    req:=request("master")
    report:=EnerCubixEngine.report(req,rs,histories)
    shares:=EnerCubixMath.maps(((Map)report["extra"])["utilityShares"])
    verifyEq(shares.size,1); verifyEq(shares.first["value"],100f)
    verifyEq(shares.first["sourceIds"],["pm"])
    verifyEq(EnerCubixDimension.dependencies(req,rs)["points"],["pm"])
    req["nodeIds"]=["a"]
    leaf:=EnerCubixEngine.report(req,rs,histories)
    verifyEq(EnerCubixMath.maps(EnerCubixMath.maps(leaf["series"]).first["points"]).first["value"],20f)
    // Explicit selection does not opt this branch into automatic parent totals.
    verifyEq(EnerCubixDimension("metering",rs).roots.size,0)
    verifyEq(master["includeInTotals"],false)
  }

  Void testMeterScopeUsesOnlyItsOwnMeasuredTotal()
  {
    rs:=records; req:=request("master")
    report:=EnerCubixEngine.report(req,rs,histories)
    shares:=EnerCubixMath.maps(((Map)report["extra"])["utilityShares"])
    verifyEq(shares.size,1);verifyEq(shares.first["utilityId"],"")
    verifyEq(shares.first["value"],100f);verifyEq(shares.first["percentage"],100f)
    verifyEq(shares.first["meterIds"],["master"])
    details:=EnerCubixMath.maps(((Map)report["extra"])["utilityMembers"])
    verifyEq(details.map |r->Str| {r["nodeId"].toStr},["master"])
    verifyEq(EnerCubixMath.maps(((Map)report["extra"])["scopeTotals"]).first["value"],100f)
    req["kind"]="profile"
    verifyEq(EnerCubixMath.maps(EnerCubixMath.maps(EnerCubixEngine.report(req,rs,histories)["series"]).first["points"]).first["value"],100f)
  }

  Void testLeafScopeDependenciesAndMissingRemainExplicit()
  {
    req:=request("a")
    report:=EnerCubixEngine.report(req,records,histories)
    verifyEq(EnerCubixMath.maps(report["series"]).size,1)
    verifyEq(EnerCubixMath.maps(EnerCubixMath.maps(report["series"]).first["points"]).first["value"],20f)
    verifyEq(EnerCubixDimension.dependencies(request("master"),records)["points"],["pm"])
    hs:=histories.findAll |h| { h["pointId"] != "pa" }
    report=EnerCubixEngine.report(req,records,hs)
    p:=EnerCubixMath.maps(EnerCubixMath.maps(report["series"]).first["points"]).first
    verifyNull(p["value"]); verifyEq(p["quality"],"missing")
    verifyErr(ArgErr#) { EnerCubixEngine.report(request("sensor"),records,histories) }
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

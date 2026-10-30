class EnerCubixServiceAreaTest : Test
{
  Void testExplicitServiceSpaceOverridesUnusedCustomArea()
  {
    rs:=records
    rs.add(space("floor",1000f))
    rs.first.setAll(["areaSource":"space","areaSpaceId":"floor","area":17f])
    ["metering","space"].each |dimension|
    {
      r:=report(rs,dimension,["a"])
      near(firstValue(r),0.1f)
      basis:=areaBasis(r).find |row| {row["nodeId"] == "a"}
      near((Float?)basis["baseValue"],100f)
      area:=(Str:Obj?)basis["area"]
      near((Float?)area["value"],1000f)
      verifyEq(((Map)((List)area["sources"]).first)["id"],"floor")
    }
  }

  Void testSharedServiceSpaceIsCountedOnce()
  {
    rs:=records.add(meter("b","pb"));rs.add(space("floor",1000f))
    rs.findAll |r| {r["kind"] == "meter"}.each |r| {r.setAll(["areaSource":"space","areaSpaceId":"floor","area":1000f])}
    r:=report(rs,"metering",["a","b"])
    near(selection(r),0.3f)
    area:=(Str:Obj?)((Str:Obj?)r["extra"])["normalizationArea"]
    near((Float?)area["value"],1000f);verifyEq(((List)area["sources"]).size,1)
    near((Float?)areaBasis(r).find |row| {row["nodeId"] == "__selection__"}["baseValue"],300f)
  }

  Void testNativeAndProjectedIdsShareOneAreaAndParentWins()
  {
    rs:=records.add(meter("b","pb"))
    rs.add(space("site",2000f).setAll(["nativeSourceKind":"site","nativeSourceId":"native-site"]))
    rs.add(space("floor",1000f).setAll(["parentId":"site","nativeSourceId":"native-floor"]))
    rs.first.setAll(["areaSource":"space","areaSpaceId":"native-floor","area":100f])
    rs[2].setAll(["areaSource":"space","areaSpaceId":"site","area":100f])
    r:=report(rs,"metering",["a","b"])
    near(selection(r),0.15f)
    area:=(Str:Obj?)((Str:Obj?)r["extra"])["normalizationArea"]
    verifyEq(((List)area["sources"]).size,1)
    verifyEq(((Map)((List)area["sources"]).first)["id"],"native-site")
  }

  Void testMissingReferencedSpaceDoesNotUseCustomFallback()
  {
    rs:=records;rs.first.setAll(["areaSource":"space","areaSpaceId":"missing","area":20f])
    r:=report(rs,"metering",["a"])
    verifyNull(firstValue(r))
    basis:=areaBasis(r).find |row| {row["nodeId"] == "a"}
    near((Float?)basis["baseValue"],100f)
    verifyEq(((Map)basis["area"])["quality"],"missingArea")
  }

  Void testLegacyCustomAreaStillWorksButUnknownMultiCustomIsNotSummed()
  {
    rs:=records;rs.first["area"]=20f
    r:=report(rs,"metering",["a"]);near(firstValue(r),5f)
    verifyEq(((Map)((List)((Map)areaBasis(r).first["area"])["sources"]).first)["source"],"custom")
    rs.add(meter("b","pb").set("area",20f))
    r=report(rs,"metering",["a","b"])
    verifyNull(selection(r))
    area:=(Str:Obj?)((Str:Obj?)r["extra"])["normalizationArea"]
    verifyEq(area["quality"],"ambiguousArea")
    near((Float?)areaBasis(r).find |row| {row["nodeId"] == "__selection__"}["baseValue"],300f)
  }

  Void testLeakBranchesUseMastersExplicitServiceSpace()
  {
    rs:=records
    rs.first.setAll(["kind":"totalMeter","areaSource":"space","areaSpaceId":"floor","area":3f])
    rs.add(space("floor",10f))
    rs.add(meter("b","pb").setAll(["meterParentId":"a","area":999f]))
    req:=request("metering",["a"]);req["kind"]="leak"
    r:=EnerCubixEngine.report(req,rs,histories)
    branches:=([Str:Obj?][])((Str:Obj?)r["extra"])["leakBranches"]
    near((Float?)branches.first["value"],20f)
    near((Float?)areaBasis(r).find |row| {row["nodeId"] == "a"}["baseValue"],-100f)
    basis:=areaBasis(r).find |row| {row["nodeId"] == "a"}
    verifyEq(basis["basis"],"difference")
    totals:=([Str:Obj?][])((Str:Obj?)r["extra"])["leakTotals"]
    original:=(Str:Obj?)totals.first["baseUsage"]
    near((Float?)original["total"],100f);near((Float?)original["submeter"],200f)
    verifyEq(original["unit"],"kWh")
  }

  Void testForecastAlsoFreezesAreaAndOriginalHistoryTotal()
  {
    rs:=records;rs.first["area"]=20f
    req:=request("metering",["a"]);req["kind"]="forecast"
    req["to"]=ts(672);req["period"]="day";req["trainingDays"]=28;req["forecastDays"]=7
    samples:=[Str:Obj?][,]
    (0..<672).each |h| {samples.add(["ts":ts(h),"value":1f])}
    r:=EnerCubixEngine.report(req,rs,[["pointId":"pa","unit":"kWh","mode":"interval","samples":samples]])
    verifyNotNull(((Map)r["extra"])["areaBasis"])
    basis:=areaBasis(r).find |row| {row["nodeId"] == "a"}
    near((Float?)basis["baseValue"],672f)
    rs.first["area"]=999f;rs.first["name"]="Renamed"
    source:=(Map)((List)((Map)basis["area"])["sources"]).first
    near((Float?)source["area"],20f);verifyEq(source["name"],"a")
  }

  Void testInvalidAreasKeepOriginalUsageWithoutIntensity()
  {
    [-1f,0f,Float.nan,Float.posInf,Float.negInf].each |invalid|
    {
      rs:=records;rs.first["area"]=invalid
      r:=report(rs,"metering",["a"])
      verifyNull(firstValue(r))
      basis:=areaBasis(r).find |row| {row["nodeId"] == "a"}
      near((Float?)basis["baseValue"],100f)
      verifyEq(((Map)basis["area"])["quality"],"missingArea")
    }
  }

  Void testEquipmentSpaceCannotSupplyServiceArea()
  {
    rs:=records;rs.add(space("equipment",1000f).set("nativeSourceKind","equip"))
    rs.first.setAll(["areaSource":"space","areaSpaceId":"equipment"])
    r:=report(rs,"metering",["a"])
    verifyNull(firstValue(r))
    near((Float?)areaBasis(r).find |row| {row["nodeId"] == "a"}["baseValue"],100f)
  }

  Void testEachEnergyUsesItsOwnSelectedServiceSpaces()
  {
    rs:=records.add(meter("b","pb").set("categoryId","other"))
    rs.add(["id":"other","kind":"category","name":"Other energy","unit":"kWh"])
    rs.add(space("floor-a",1000f));rs.add(space("floor-b",2000f))
    rs.first.setAll(["areaSource":"space","areaSpaceId":"floor-a"])
    rs.find |r| {r["id"] == "b"}.setAll(["areaSource":"space","areaSpaceId":"floor-b"])
    result:=report(rs,"metering",["a","b"])
    totals:=EnerCubixMath.maps(((Map)result["summary"])["selectionTotals"])
    near((Float?)totals.find |r| {r["categoryId"] == "electric"}["value"],0.1f)
    near((Float?)totals.find |r| {r["categoryId"] == "other"}["value"],0.1f)
  }

  private [Str:Obj?][] records() { [meter("a","pa"),["id":"electric","kind":"category","name":"Electricity","unit":"kWh"]] }
  private Str:Obj? meter(Str id,Str point) { ["id":id,"kind":"meter","name":id,"pointId":point,"categoryId":"electric","unit":"kWh","includeInTotals":true] }
  private Str:Obj? space(Str id,Float area) { ["id":id,"kind":"space","name":id,"area":area,"nativeSourceId":id,"nativeSourceKind":"floor"] }
  private [Str:Obj?][] histories() { [history("pa",100f),history("pb",200f)] }
  private Str:Obj? history(Str id,Float n) { ["pointId":id,"unit":"kWh","mode":"interval","samples":[["ts":ts(0),"value":n]]] }
  private Str ts(Int hour) { (DateTime.fromIso("2026-10-01T00:00:00Z")+Duration(hour*1hr.ticks)).toIso }
  private Str:Obj? request(Str dim,Str[] ids) { ["kind":"profile","dimension":dim,"nodeIds":ids,"from":ts(0),"to":ts(1),"period":"hour","metric":"energy","perArea":true,"tz":"UTC"] }
  private Str:Obj? report([Str:Obj?][] rs,Str dim,Str[] ids) { EnerCubixEngine.report(request(dim,ids),rs,histories) }
  private Float? firstValue(Str:Obj? r) { (Float?)((Map)((List)((Map)((List)r["series"]).first)["points"]).first)["value"] }
  private Float? selection(Str:Obj? r) { (Float?)((Map)((List)((Map)r["summary"])["selectionTotals"]).first)["value"] }
  private [Str:Obj?][] areaBasis(Str:Obj? r) { ([Str:Obj?][])((Str:Obj?)r["extra"])["areaBasis"] }
  private Void near(Float? actual,Float expected) { verifyNotNull(actual);verify(((Float)actual-expected).abs < 0.000001f) }
}

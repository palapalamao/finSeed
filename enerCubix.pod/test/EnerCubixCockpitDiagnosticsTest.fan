using util

class EnerCubixCockpitDiagnosticsTest : Test
{
  Void testTruncatedMatchingPrefixNeedsProvenCaptureIdentity()
  {
    [null,"different","same"].each |mode|
    {
      input:=snapshot(1,1);first:=(Map)((Map)input["reports"])["flow"]
      row:=EnerCubixMath.maps(first["rows"]).first
      row.setAll(["periodRecordTotalCount":1001,"periodsTruncated":true])
      if(mode != null) row["periodsCaptureId"]="capture-left"
      other:=row.dup
      second:=first.dup.set("rows",[other]).set("extra",["energyFlowOverview":["rows":[other]]])
      if(mode == "different")
      {
        other["periodsCaptureId"]="capture-right"
        EnerCubixMath.maps(((Map)((Map)second["extra"])["energyFlowOverview"])["rows"]).first["periodsCaptureId"]="capture-right"
      }
      // Same captured prefix/count can describe two different unreturned tails.
      ((Map)input["reports"])["other"]=second
      p:=project(input)
      entries:=EnerCubixMath.maps(((Map)p["diagnostics"])["entries"]).findAll |m| {m["kind"] == "coveragePeriods"}
      // Each report has a row and overview copy: only an explicit shared server
      // capture ID permits their sampled evidence to share a packet allocation.
      verifyEq(entries.size,mode == "same" ? 1 : (mode == "different" ? 2 : 4))
    }
    input:=snapshot(0,0);one:=(Map)((Map)input["reports"])["flow"]
    ((Map)one["extra"])["knownUsage"]=["sourceUsageTruncated":true,"sourceUsage":Obj?[,]]
    ((Map)one["extra"])["cleaning"]=[["detailsTruncated":true,"details":Obj?[,]]]
    ((Map)input["reports"])["other"]=JsonInStream(JsonOutStream.writeJsonToStr(one).in).readJson
    entries:=EnerCubixMath.maps(((Map)project(input)["diagnostics"])["entries"])
    verifyEq(entries.findAll |e| {e["kind"] == "sourceUsage"}.size,2)
    verifyEq(entries.findAll |e| {e["kind"] == "cleaningEvents"}.size,2)
  }
  Void testPacketBudgetSharesDuplicateEvidenceAndKeepsBusinessResults()
  {
    input:=snapshot(3,600);before:=JsonOutStream.writeJsonToStr(input)
    projected:=project(input);diag:=(Map)projected["diagnostics"]
    verifyEq(diag["rowBudget"],1000);verifyEq(diag["returnedCount"],1000);verifyEq(diag["truncated"],true)
    rows:=EnerCubixMath.maps(((Map)((Map)projected["reports"])["flow"])["rows"])
    overview:=EnerCubixMath.maps(((Map)((Map)((Map)((Map)projected["reports"])["flow"])["extra"])["energyFlowOverview"])["rows"])
    verifyEq(rows.map |r->Int| {((List)r["periods"]).size}.sort,[333,333,334])
    rows.each |r,i| {verifyEq(r["periodsDiagnosticRef"],overview[i]["periodsDiagnosticRef"]);verifyEq(r["periods"],overview[i]["periods"])}
    verifyEq(business(projected),business(input));verifyEq(JsonOutStream.writeJsonToStr(input),before)
    verifySame(project(projected),projected)
  }
  Void testZeroEqualityLimitAndUnknownUpstreamCounts()
  {
    [0,1000,1001].each |count|
    {
      p:=project(snapshot(1,count));meta:=EnerCubixMath.maps(((Map)p["diagnostics"])["entries"]).first
      verifyEq(meta["totalCount"],count);verifyEq(meta["returnedCount"],count.min(1000))
      verifyEq(meta["truncated"],count>1000);if(count==0) verifyNull(meta["returnedRange"])
    }
    input:=snapshot(0,0)
    extra:=(Map)((Map)((Map)input["reports"])["flow"])["extra"]
    extra["knownUsage"]=["sourceUsageTruncated":true,"sourceUsageRowCount":5000,"sourceUsage":[["pointId":"p","from":at.toIso,"to":(at+1hr).toIso,"intervalCount":2000,"detailsTruncated":true,"intervals":[["intervalStart":at.toIso,"intervalEnd":(at+1hr).toIso,"value":0f]]]]]
    extra["cleaning"]=[["pointId":"p","profileId":"clean","profileVersion":2,"parameters":["mode":"drop"],"detailsTruncated":true,"details":[["ts":at.toIso,"reason":"filtered"]]]]
    p:=project(input);metas:=EnerCubixMath.maps(((Map)p["diagnostics"])["entries"])
    verifyEq(metas.find |m| {m["kind"] == "sourceUsage"}["totalCount"],5000)
    verifyNull(metas.find |m| {m["kind"] == "cleaningEvents"}["totalCount"])
    verifyEq(metas.find |m| {m["kind"] == "sourceIntervals"}["totalCount"],2000)
    verify(metas.find |m| {m["kind"] == "sourceIntervals"}["truncated"] == true)
    verifyEq(business(p),business(input))
  }
  Void test116MissingResponseShapeCapturesOnlyPacketBudget()
  {
    // Response-layer pressure fixture, separate from production Stream execution.
    // Sparse preparation is exercised with the captured 82-point plan elsewhere.
    input:=snapshot(116,8760,true)
    p:=project(input);diag:=(Map)p["diagnostics"]
    verifyEq(diag["returnedCount"],1000);verifyEq(((List)diag["entries"]).size,116)
    verify(EnerCubixMath.maps(diag["entries"]).all |m| {m["totalCount"] == 8760 && m["truncated"] == true})
    fullReport:=(Map)((Map)input["reports"])["flow"];actual:=(Map)((Map)p["reports"])["flow"]
    verifyEq(p["modules"],input["modules"]);verifyEq(actual["series"],fullReport["series"]);verifyEq(actual["summary"],fullReport["summary"])
    codec:=EnerCubixCockpitPayload.encode(p)
    bytes:=JsonOutStream.writeJsonToStr(["ok":true,"data":codec]).toBuf.size
    verify(bytes <= 8388608)
    echo("RESPONSE_SHAPE_116 originalPeriodRows=1016160 returnedUniqueDiagnostics=1000 wireBytes=$bytes")
    fixture:=Env.cur.vars["ENERCUBIX_MISSING_RESPONSE_FIXTURE"]
    if(fixture != null) {File.os(fixture).out.writeChars(JsonOutStream.writeJsonToStr(p)).close;File.os(fixture+".wire.json").out.writeChars(JsonOutStream.writeJsonToStr(codec)).close}
  }

  internal Str:Obj? project(Str:Obj? value)
  {t:=Type.find("enerCubix::EnerCubixCockpitDiagnostics",false);verifyNotNull(t,"packet diagnostic projection missing");return (Str:Obj?)t.method("project").call(value)}
  internal Str:Obj? snapshot(Int meters,Int count,Bool nativeShape := false)
  {
    rows:=[Str:Obj?][,]
    starts:=(0..<count).map |h->Str| {(at+1hr*h).toIso}
    ends:=(0..<count).map |h->Str| {(at+1hr*(h+1)).toIso}
    (0..<meters).each |i|
    {
      id:=nativeShape ? "p:zeda:r:"+(0x7f000000+i).toHex(8)+"-1a000001" : "m$i"
      point:=nativeShape ? "p:zeda:r:"+(0x7e000000+i).toHex(8)+"-1a000001" : "p$i"
      periods:=[Str:Obj?][,]
      (0..<count).each |h| {periods.add(["from":starts[h],"to":ends[h],"value":nativeShape || h%4==0 ? null : (h%4==1 ? 0f : (h%4==2 ? -2f : 3f)),"quality":nativeShape ? "missing" : (h%4==0 ? "na" : "ok"),"pointId":point])}
      rows.add(["id":id,"nodeId":id,"name":nativeShape ? "一号楼能源分表中文名称"+i : id,"pointId":point,"value":nativeShape ? null : -1f,"valueType":nativeShape ? "null" : "number","knownValue":null,"completeValue":null,"quality":"missing","coveredSeconds":nativeShape ? 0f : 3600f,"activeSeconds":nativeShape ? count*3600f : 7200f,"periods":periods,"sourceIds":[point]])
    }
    report:=Str:Obj?["kind":"energyFlow","from":at.toIso,"to":(at+8784hr).toIso,"period":"month","series":[["points":[["value":0f],["value":null,"quality":"na"]]]],"rows":rows,"summary":["value":0f],"extra":["details":[["value":-1f]],"energyFlowOverview":["rows":rows]]]
    result:=Str:Obj?["schemaVersion":1,"snapshotId":"capacity-fixture","context":["asOf":(at+8784hr).toIso,"time":["from":at.toIso,"to":(at+8784hr).toIso],"reportScope":["nodeIds":["site"]]],"modules":["kpis":["data":["values":[["value":0f,"valueType":"number","quality":"ok"]]]]],"reports":["flow":report]]
    if(nativeShape)
    {
      // All nine module statuses are explicit unavailable/empty; no energy,
      // price or emission number is manufactured by this shape-only fixture.
      modules:=Str:Obj?["kpis":["status":"unavailable","data":["values":[["id":"energy","value":null,"valueType":"null","quality":"missing","unit":"kWh"]]]]]
      ["space","time","endUse","organization","balance","efficiency","issues"].each |face| {modules[face]=["status":"unavailable","reasonCodes":["missing"]]}
      modules["trend"]=["status":"partial","data":["reportRef":"flow"]]
      result["modules"]=modules
      finish:=at+1hr*count;report["to"]=finish.toIso
      ((Map)((Map)result["context"])["time"])["to"]=finish.toIso
      ((Map)result["context"])["asOf"]=finish.toIso
      ((Map)result["context"])["comparison"]=["mode":"custom","referenceRange":["from":"2024-01-01T00:00:00+08:00","to":at.toIso]]
      report["summary"]=["value":null,"quality":"missing"]
      report["series"]=[["id":"capacity-series","unit":"kWh","points":(1..12).map |m->[Str:Obj?]| {["ts":DateTime(2025,Month.vals[m-1],1,0,0,0,0,TimeZone("Shanghai")).toIso,"value":null,"valueType":"null","quality":"missing"]}]]
      ((Map)report["extra"])["details"]=rows.map |row->[Str:Obj?]| {r:=row.dup;r.remove("periods");return r}
      reference:=report.dup;reference["kind"]="profile";reference["from"]="2024-01-01T00:00:00+08:00";reference["to"]=at.toIso
      reference["rows"]=Obj?[,];reference["extra"]=Str:Obj?[:]
      reference["series"]=[["id":"reference-capacity","unit":"kWh","points":(1..12).map |m->[Str:Obj?]| {["ts":DateTime(2024,Month.vals[m-1],1,0,0,0,0,TimeZone("Shanghai")).toIso,"value":null,"valueType":"null","quality":"missing"]}]]
      ((Map)result["reports"])["reference-profile-energy"]=reference
    }
    return result
  }
  private Obj? business(Str:Obj? s)
  {
    copy:=(Str:Obj?)JsonInStream(JsonOutStream.writeJsonToStr(s).in).readJson;copy.remove("diagnostics")
    report:=(Map)((Map)copy["reports"])["flow"];extra:=(Map)report["extra"]
    [EnerCubixMath.maps(report["rows"]),EnerCubixMath.maps(((Map)extra["energyFlowOverview"])["rows"])].each |rows| {rows.each |r| {r.remove("periods");r.remove("periodsDiagnosticRef")}}
    if(extra["knownUsage"] is Map) {known:=(Map)extra["knownUsage"];known.remove("sourceUsage");known.remove("sourceUsageDiagnosticRef")}
    EnerCubixMath.maps(extra["cleaning"]).each |c| {c.remove("details");c.remove("detailsDiagnosticRef")}
    return copy
  }
  private DateTime at() {DateTime.fromIso("2025-01-01T00:00:00+08:00")}
}

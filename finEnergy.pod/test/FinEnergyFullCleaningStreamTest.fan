using haystack

class FinEnergyFullCleaningStreamTest : Test
{
  Void testScalarBatchesRetainWholeCleaningResult()
  {
    cases:=Obj?[][
      [[10,10,5,NA.val,null,20,24],["deltaMin":0,"defNull":true]],
      [[10,5,8,2,20,22,21],["deltaMin":0,"defVal":["type":"number","value":2]]],
      [[10,5,8,2,20,22,21],["deltaMin":0,"defVal":["type":"na"]]],
      [[32760,12,15,10,20,50,55],["deltaMax":100,"hisTotalizedRollover":32768]],
      [[10,NA.val,14,16,NA.val,20,24],["removeNA":true,"timeMax":"1h","defNull":true]]]
    cases.each |c|
    {
      raw:=HisItem[,];((Obj?[])c[0]).each |v,i| {raw.add(HisItem(at+1hr*i,v is Num ? Number.makeNum(v) : v))}
      cfg:=FinEnergyCleaning.config((Str:Obj?)c[1],"kWh")
      expected:=oracle(raw,cfg,at,at+6hr)
      [1,2,3,7].each |batch|
      {
        stream:=FinEnergyFullCleaning(point,cfg,at,at+6hr)
        for(i:=0;i<raw.size;i+=batch) raw[i..<(i+batch).min(raw.size)].each |item| {stream.push(item)}
        actual:=stream.finish
        verifyEq(mismatch(actual["cleaning"],expected["cleaning"]),null,"$c batch=$batch")
        q:=Str:Obj?["kind":"profile","nodeIds":["m"],"from":at.toIso,"to":(at+6hr).toIso,"asOf":(at+6hr).toIso,"period":"hour","metric":"energy"]
        verifyEq(FinEnergyHistory.report(q,records,[actual]),FinEnergyHistory.report(q,records,[expected]))
      }
    }
  }

  Void testGapEvidenceAndThousandQuotaKeepOriginalCountsAndSort()
  {
    cfg:=FinEnergyCleaning.config(["deltaMin":0,"removeNA":true,"defNull":true],"kWh")
    raw:=HisItem[,]
    (0..2100).each |i| {raw.add(HisItem(at+1min*i,i%3==0 ? NA.val : Number(i%2==0 ? 10 : 5)))}
    expected:=oracle(raw,cfg,at,at+40hr)
    stream:=FinEnergyFullCleaning(point,cfg,at,at+40hr)
    raw.each |item| {stream.push(item)}
    actual:=stream.finish
    verifyEq(mismatch(actual["cleaning"],expected["cleaning"]),null)
    verifyEq(((Map)actual["cleaning"])["detailsTruncated"],true)
    verifyEq(FinEnergyMath.maps(((Map)actual["cleaning"])["details"]).size,1000)
  }

  Void testInputOrderLimitDuplicatesAndFractionalOffsetStayExact()
  {
    cfg:=FinEnergyCleaning.config(["defNull":true],"kWh")
    stream:=FinEnergyFullCleaning(point,cfg,at,at+6hr,2)
    stream.push(HisItem(at,Number(1)));stream.push(HisItem(at,Number(2)))
    verifyErr(ArgErr#) {stream.push(HisItem(at+1hr,Number(3)))}
    order:=FinEnergyFullCleaning(point,cfg,at,at+6hr)
    order.push(HisItem(at+1hr,Number(1)))
    verifyErr(FinEnergyFullCleaningOrderErr#) {order.push(HisItem(at,Number(2)))}
    tz:=TimeZone.fromStr("Lord_Howe");start:=DateTime(2026,Month.apr,5,0,0,0,0,tz)
    raw:=HisItem[,];(0..24).each |i| {raw.add(HisItem(start+15min*i,Number(i.toFloat)))}
    expected:=oracle(raw,cfg,start,start+6hr)
    stream=FinEnergyFullCleaning(point,cfg,start,start+6hr)
    raw.each |item| {stream.push(item)}
    verifyEq(mismatch(stream.finish["cleaning"],expected["cleaning"]),null)
  }

  Void testAllNonRawReportKindsRetainCompleteResponse()
  {
    cfg:=FinEnergyCleaning.config(["deltaMin":0,"defVal":["type":"number","value":2]],"kWh")
    cfg=Etc.makeDict(Etc.dictToMap(cfg).set("finEnergyProfileRef",Ref("profile")).set("finEnergyProfileVersion",Number(2)))
    original:=[Str:Obj?][,];actual:=[Str:Obj?][,]
    ["p","cp"].each |id|
    {
      raw:=HisItem[,];Obj?[10,12,10,13,NA.val,20,25].each |v,i| {raw.add(HisItem(at+1hr*i,v is Num ? Number.makeNum(v) : v))}
      original.add(oracle(raw,cfg,at,at+6hr,id))
      stream:=FinEnergyFullCleaning(point(id),cfg,at,at+6hr)
      raw.each |item| {stream.push(item)};actual.add(stream.finish)
    }
    rs:=records
    rs.first["kind"]="totalMeter";rs.first["utilityId"]="u"
    rs.addAll([["id":"c","kind":"meter","pointId":"cp","categoryId":"e","meterParentId":"m","utilityId":"u"],
      ["id":"u","kind":"utility","name":"Lighting","categoryId":"e"],
      ["id":"t","kind":"tariff","categoryId":"e","isDefault":true,"mode":"flat","rate":2f],
      ["id":"cal","kind":"calendar","isDefault":true,"workHours":[1],"workDays":[1,2,3,4,5]],
      ["id":"cop","kind":"cop","numeratorId":"m","denominatorId":"c"]])
    ["profile","ranking","proportion","utility","daily","comparison","primary","cop","leak","workingHours","workingDays","dashboard","energyFlow"].each |kind|
    {
      ["energy","cost"].each |metric|
      {
        q:=Str:Obj?["kind":kind,"dimension":"metering","nodeIds":["m"],"from":at.toIso,"to":(at+3hr).toIso,"asOf":(at+6hr).toIso,"period":"hour","metric":metric,"categoryId":"e"]
        if(kind=="cop") {q.remove("dimension");q["nodeIds"]=["cop"]}
        if(kind=="comparison") {q["otherFrom"]=(at+3hr).toIso;q["otherTo"]=(at+6hr).toIso}
        verifyEq(FinEnergyHistory.report(q,rs,actual),FinEnergyHistory.report(q,rs,original),"$kind $metric")
      }
    }
  }
  private Str? mismatch(Obj? a,Obj? b,Str path:="root")
  {
    if(a==b) return null
    if(a is Map && b is Map)
    {
      left:=(Map)a;right:=(Map)b
      if(left.keys.sort!=right.keys.sort) return "$path keys ${left.keys.sort} != ${right.keys.sort}"
      Str? error
      left.keys.each |key| {if(error==null) error=mismatch(left[key],right[key],"${path}.$key")}
      return error
    }
    if(a is List && b is List)
    {
      left:=(List)a;right:=(List)b
      if(left.size!=right.size) return "$path size ${left.size} != ${right.size}"
      for(i:=0;i<left.size;i++) {error:=mismatch(left[i],right[i],"${path}[$i]");if(error!=null) return error}
      return null
    }
    return "$path $a != $b"
  }
  private Str:Obj? oracle(HisItem[] raw,Dict cfg,DateTime from,DateTime to,Str id:="p")
  {
    result:=FinEnergyCleaning.clean(point(id),raw,cfg)
    result.summary.setAll(["sourceIds":[id],"pointId":id,"profileId":(cfg["finEnergyProfileRef"] as Ref)?.id,"profileVersion":(cfg["finEnergyProfileVersion"] as Number)?.toInt,"parameters":FinEnergyCleaning.jsonConfig(cfg)])
    return FinEnergyHistory.normalizeClean(point(id),result,from,to)
  }
  private [Str:Obj?][] records() {[["id":"m","kind":"meter","pointId":"p","categoryId":"e"],["id":"e","kind":"category","unit":"kWh"]]}
  private Dict point(Str id:="p") {Etc.makeDict(["id":Ref(id),"unit":"kWh","hisFunc":"finEnergyCleanHis"])}
  private DateTime at() {DateTime.fromIso("2026-11-01T00:00:00Z")}
}

using haystack
using folio
using skyarcd
using util

** Replays bounded, independently captured raw samples in the isolated project.
** Only test-owned records are written; the source project's histories are untouched.
class EnerCubixQueryReplayAcceptance
{
  Context cx
  Ref[] owned := [,]
  new make(Context cx) { this.cx=cx }

  Str:Obj? run(Str json)
  {
    if (!["finseed_acceptance","enerCubix_acceptance"].contains(cx.proj.name)) throw ArgErr("Query replay requires the isolated acceptance project")
    repo:=EnerCubixRepo(cx); repo.mustWrite
    input:=(Str:Obj?)JsonInStream(json.in).readJson
    from:=DateTime.fromIso(input["from"].toStr).toTimeZone(TimeZone.fromStr("Shanghai"))
    to:=DateTime.fromIso(input["to"].toStr).toTimeZone(from.tz)
    rows:=EnerCubixMath.maps(input["rows"])
    if (input["offsetSamples"] is List)
      rows=((List)input["offsetSamples"]).map |Obj? item->[Str:Obj?]|
      {
        pair:=item as List ?: throw ArgErr("Invalid compact replay sample")
        seconds:=EnerCubixMath.num(pair[0]) ?: throw ArgErr("Invalid replay timestamp offset")
        Obj? sampleValue:=pair[1]
        kind:=pair.size > 2 ? pair[2].toStr : (sampleValue == null ? "null" : "number")
        return ["ts":(from+Duration((seconds*1sec.ticks.toFloat).toInt)).toIso,"value":sampleValue,"valueType":kind]
      }
    if (to <= from || to-from > 1day || rows.isEmpty || rows.size > 1000) throw ArgErr("Replay requires 1-1000 samples within one day")
    prefix:="Own query replay "+DateTime.nowTicks
    try
    {
      category:=repo.save(["kind":"category","name":prefix,"unit":"kWh"]); owned.add(Ref(category["id"].toStr))
      profile:=repo.save(["kind":"cleaningProfile","name":prefix+" clean","mode":"drop","parameters":["deltaMin":0,"deltaMax":1000,"timeMax":"1h","defNull":true]]); owned.add(Ref(profile["id"].toStr))
      equip:=add(["equip":Marker.val,"dis":prefix,"enerCubix":Marker.val,"enerCubixKind":"totalMeter","enerCubixAutoSum":true,"enerCubixCategoryRef":Ref(category["id"].toStr),"enerCubixAlias":prefix,"enerCubixIncludeInTotals":true])
      point:=add(["point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"hisMode":"consumption","hisCollectInterval":Number(10,Unit("s")),"kind":"Number","unit":"kWh","tz":"Shanghai","dis":prefix+" source","equipRef":equip.id])
      cx.db.commit(Diff(cx.db.readById(equip.id),Etc.makeDict(["enerCubixPointRef":point.id])))
      repo.save(["id":equip.id.id,"mod":EnerCubixRepo.iso(cx.db.readById(equip.id)["mod"]),"kind":"totalMeter","name":prefix,"pointId":point.id.id,"categoryId":category["id"],"autoSum":true,"includeInTotals":true,"cleaningEnabled":true,"cleaningProfileId":profile["id"]])
      HisItem[] samples:=rows.map |row->HisItem|
      {
        ts:=DateTime.fromIso(row["ts"].toStr).toTimeZone(from.tz)
        if (ts < from || ts >= to) throw ArgErr("Replay sample outside requested range")
        Obj? value:=row["valueType"] == "na" ? NA.val : (row["value"] == null ? null : Number(EnerCubixMath.num(row["value"]) ?: throw ArgErr("Invalid replay value"),Unit("kWh")))
        return HisItem(ts,value)
      }
      cx.rt.his.write(cx.db.readById(point.id),samples,null).get(1min)
      // Current unrelated sources deliberately lack history. The own-history query must remain usable.
      add(["equip":Marker.val,"dis":prefix+" new child","enerCubix":Marker.val,"enerCubixKind":"meter","enerCubixCategoryRef":Ref(category["id"].toStr),"enerCubixMeterParentRef":equip.id,"enerCubixPointRef":Ref.gen])
      request:=Str:Obj?["kind":"trend","dimension":"metering","nodeIds":[equip.id.id],"from":from.toIso,"to":to.toIso,"period":"hour","metric":"energy","perArea":false]
      report:=repo.report(request)
      points:=EnerCubixMath.maps(EnerCubixMath.maps(report["series"]).first["points"])
      if (points.size != rows.size) throw Err("Replay changed raw sample count")
      points.each |p,i|
      {
        original:=rows[i]
        if (p["ts"] != original["ts"] || EnerCubixMath.num(p["value"]) != EnerCubixMath.num(original["value"]) || p["valueType"] != original["valueType"])
          throw Err("Replay changed a raw timestamp, value or null/NA type at sample $i")
        if (EnerCubixMath.strings(p["sourceIds"]) != [point.id.id]) throw Err("Replay unexpectedly expanded child history")
      }
      preserved:=HisItem[,]
      cx.rt.his.read(cx.db.readById(point.id),Span.makeAbs(from,to),Etc.makeDict(["raw":Marker.val])) |s| { if (s.ts >= from && s.ts < to) preserved.add(s) }
      if (preserved.map |s->Obj?| { s.val } != samples.map |s->Obj?| { s.val }) throw Err("Query changed replay source raw history")
      return ["status":"passed","project":cx.proj.name,"checks":points.size+2,"count":points.size,"first":points.first,"last":points.last,"report":report]
    }
    finally
    {
      owned.dup.reverse.each |id| { r:=cx.db.readById(id,false); if (r != null) cx.db.commit(Diff(r,null,Diff.remove)) }
    }
  }

  private Dict add(Str:Obj? tags)
  { r:=cx.db.commit(Diff.makeAdd(Etc.makeDict(tags))).newRec; owned.add(r.id); return cx.db.readById(r.id) }
}

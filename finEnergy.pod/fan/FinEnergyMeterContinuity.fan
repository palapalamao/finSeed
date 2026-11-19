using haystack
using folio
using util

** Persistent continuity index; source membership never imports old counter values.
internal class FinEnergyMeterContinuity
{
  static Ref key(Ref point) { Ref("finEnergy-continuity-"+point.id.toBuf.toDigest("SHA-256").toHex[0..<24]) }

  static Dict advance(Dict point, Dict? previous, [Str:Obj?][] inputs, DateTime at)
  {
    state:=previous == null ? Str:Obj?[:] : (Str:Obj?)JsonInStream(previous["finEnergyContinuity"].toStr.in).readJson
    unit:=point["unit"]?.toStr ?: ""
    own:=FinEnergyMath.num(state["value"])
    if (own == null || state["unit"] != unit) own=point["curVal"] is Number ? ((Number)point["curVal"]).toFloat : 0f
    Map before:=state["inputs"] as Map ?: Str:Obj?[:]
    after:=Str:Obj?[:]; quality:="ok"; hasGap:=state["hasGap"] == true
    inputs.each |input|
    {
      id:=input["id"].toStr; value:=FinEnergyMath.num(input["value"]); prior:=before[id] as Map
      signature:=input["signature"]?.toStr ?: ""
      if (value == null || input["quality"] != "ok") { quality="missing"; hasGap=true }
      else if (prior != null && prior["signature"] == signature && FinEnergyMath.num(prior["value"]) != null)
      {
        delta:=value-FinEnergyMath.num(prior["value"])
        if (delta < 0f)
        {
          period:=FinEnergyMath.num(input["rollover"]); last:=FinEnergyMath.num(prior["value"])
          if (period != null && last >= 0f && last < period && value >= 0f && value < period) delta=period-last+value
          else { delta=0f; quality="reset"; hasGap=true }
        }
        own+=delta
      }
      after[id]=["value":value,"signature":signature]
    }
    if (inputs.isEmpty) { quality="missingBranches"; hasGap=true }
    next:=Str:Obj?["value":own,"unit":unit,"inputs":after,"hasGap":hasGap]
    tags:=Str:Obj?["status":quality,"state":JsonOutStream.writeJsonToStr(next),"stateMod":FinEnergyRepo.iso(previous?.get("mod")),"hasGap":hasGap]
    if (quality == "ok") tags["val"]=Number(own,Unit.fromStr(unit,false))
    return Etc.makeDict(tags)
  }

  static Diff? change(Folio db, Dict point, Dict calculated, DateTime at)
  {
    previous:=db.readById(key(point.id),false)
    if (FinEnergyRepo.iso(previous?.get("mod")) != calculated["stateMod"]) throw ArgErr("表计累计状态已被其他任务更新，请稍后重试")
    if (previous?.get("finEnergyContinuity") == calculated["state"]) return null
    tags:=Etc.makeDict(["finEnergyMeterContinuity":Marker.val,"finEnergyMainRef":point.id,"finEnergyContinuity":calculated["state"],"finEnergyContinuityAt":at,"dis":"FinEnergy meter continuity"])
    return previous == null ? Diff.makeAdd(tags,key(point.id)) : Diff(previous,tags)
  }

  static Diff? release(Folio db, Dict point, DateTime at)
  {
    previous:=db.readById(key(point.id),false)
    if (previous == null) return null
    state:=(Str:Obj?)JsonInStream(previous["finEnergyContinuity"].toStr.in).readJson
    state["inputs"]=Str:Obj?[:]
    if (point["curVal"] is Number) state["value"]=((Number)point["curVal"]).toFloat
    return Diff(previous,Etc.makeDict(["finEnergyContinuity":JsonOutStream.writeJsonToStr(state),"finEnergyContinuityAt":at]))
  }
}

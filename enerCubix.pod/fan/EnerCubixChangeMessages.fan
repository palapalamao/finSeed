using haystack
using folio
using util

** Read-only projection of configuration evidence. Never used by calculation paths.
internal class EnerCubixChangeMessages
{
  static [Str:Obj?] page(Folio db, |Dict->Bool| canRead, Bool admin, Int offset:=0, Int limit:=30)
  {
    if (offset < 0 || limit < 1 || limit > 200) throw ArgErr("offset >= 0; 1 <= limit <= 200")
    meta:=db.readById(EnerCubixMeterTimeline.key,false)
    start:=meta?.get("enerCubixTimelineStart") as DateTime
    epochs:=db.readAllList(Filter.has("enerCubixMeterEpoch"))
    valid:=Dict[,]
    damaged:=Str:Bool[:]
    epochs.each |e|
    {
      if (e["enerCubixRecordRef"] is Ref && e["enerCubixEffectiveFrom"] is DateTime && e["enerCubixEpochSequence"] is Number) valid.add(e)
      else
      {
        ref:=e["enerCubixRecordRef"] as Ref
        if (ref != null) damaged[absolute(db,ref).id]=true
        Log.get("enerCubix").warn("Skipping malformed configuration message epoch")
      }
    }
    valid.sort |a,b|
    {
      order:=((DateTime)a["enerCubixEffectiveFrom"]) <=> ((DateTime)b["enerCubixEffectiveFrom"])
      if (order == 0) order=((Number)a["enerCubixEpochSequence"]).toInt <=> ((Number)b["enerCubixEpochSequence"]).toInt
      return order == 0 ? a.id.id <=> b.id.id : order
    }
    previous:=Str:[Str:Obj?]?[:]
    known:=Str:Bool[:]
    out:=[Str:Obj?][,]
    valid.each |e|
    {
      id:=absolute(db,(Ref)e["enerCubixRecordRef"]).id
      try
      {
        removed:=e.has("enerCubixEpochRemoved")
        [Str:Obj?]? after:=removed ? null : (Str:Obj?)JsonInStream((e["enerCubixEpochConfig"] as Str ?: throw ArgErr("Missing epoch configuration")).in).readJson
        before:=previous[id]
        ts:=(DateTime)e["enerCubixEffectiveFrom"]
        sequence:=((Number)e["enerCubixEpochSequence"]).toInt
        initial:=e.has("enerCubixEpochInitial") || sequence <= 1
        // The first post-cutover epoch is a creation only if its predecessor
        // is known absent. A broken predecessor is never treated as absence.
        comparable:=known[id] == true || (!previous.containsKey(id) && !damaged.containsKey(id) && start != null && ts >= start && sequence > 1)
        previous[id]=after
        known[id]=true
        if (initial || !comparable || (before == null && after == null)) return
        action:=after == null ? "deleted" : (before == null ? "created" : "updated")
        current:=db.readById(Ref(id),false)
        if (current != null && !canRead(current)) return
        if ((action == "deleted" || current == null) && !admin) return
        record:=after ?: before
        changes:=[Str:Obj?][,]
        restricted:=false
        categories:=Str[,]
        fields.each |field|
        {
          a:=before?.get(field); b:=after?.get(field)
          if (a == b) return
          categories.add(category(field))
          try
          {
            safeA:=safe(db,canRead,field,a); safeB:=safe(db,canRead,field,b)
            if (safeA != safeB) changes.add(["field":field,"before":safeA,"after":safeB])
          }
          catch (Err err) { restricted=true }
        }
        if (changes.isEmpty && !restricted) return
        message:=Str:Obj?["id":e.id.id,"ts":ts.toIso,"action":action,"category":categories.contains("relationship") ? "relationship" : (categories.contains("source") ? "source" : "configuration"),"objectId":id,"objectName":record["name"] as Str ?: id,"objectKind":record["kind"] as Str ?: "","changes":changes]
        actor:=e["enerCubixEpochActor"] as Str
        if (actor != null && !actor.trim.isEmpty) message["actor"]=actor
        if (restricted) message["detailsRestricted"]=true
        out.add(message)
      }
      catch (Err err)
      {
        previous[id]=null; known[id]=false; damaged[id]=true
        Log.get("enerCubix").warn("Skipping unreadable configuration message epoch")
      }
    }
    // Epoch traversal already orders timestamp, sequence, and immutable ID.
    out.reverse
    end:=(offset.min(out.size)+limit).min(out.size)
    return ["items":offset >= out.size ? [Str:Obj?][,] : out[offset..<end],"total":out.size,"offset":offset,"limit":limit]
  }

  private static const Str[] relationships:=["parentId","spaceId","meterParentId","organizationId","categoryId","subcategoryId","utilityId","canonicalId"]
  private static const Str[] sources:=["pointId","expressionId","formula","variables"]
  private static const Str[] fields:=relationships.dup.addAll(sources).addAll(["kind","name","autoSum","includeInTotals","historyMode","maximum","unit","cleaningEnabled","cleaningProfileId","mode","parameters","alarmEnabled","alarmLimit","alarmLimits"])
  private static const Str[] parameters:=["deltaMin","deltaMax","timeMax","derivMin","derivMax","defVal","defNull","removeNA","hisTotalizedRollover"]

  private static Str category(Str field)
  { relationships.contains(field) ? "relationship" : (sources.contains(field) ? "source" : "configuration") }

  ** Only supported shapes cross the boundary; unknown nested keys and cached
  ** Ref names are never serialized. A restricted reference drops the field.
  private static Obj? safe(Folio db, |Dict->Bool| canRead, Str field, Obj? value)
  {
    if (value == null) return null
    if (EnerCubixRepo.refTags.containsKey(field)) return readableRef(db,canRead,value)
    if (field == "variables")
    {
      vars:=value as Map ?: throw ArgErr("Invalid variables")
      result:=Str:Obj?[:]
      vars.each |v,k| { result[k.toStr]=readableRef(db,canRead,v) }
      return result
    }
    if (field == "parameters")
    {
      config:=value as Map ?: throw ArgErr("Invalid parameters")
      result:=Str:Obj?[:]
      parameters.each |key|
      {
        if (!config.containsKey(key)) return
        v:=config[key]
        if (v is Map)
        {
          source:=(Map)v
          if (key == "defVal" && source["type"] == "na") { result[key]=["type":"na"]; return }
          if (source["type"] != "number" || (source["value"] isnot Int && source["value"] isnot Float)) throw ArgErr("Unsupported parameter type")
          typed:=Str:Obj?["type":"number","value":source["value"]]
          if (source.containsKey("unit"))
          {
            unit:=source["unit"] as Str ?: throw ArgErr("Unsupported parameter unit")
            if (Unit.fromStr(unit,false) == null) throw ArgErr("Unknown parameter unit")
            typed["unit"]=unit
          }
          result[key]=typed
        }
        else
        {
          if (["defNull","removeNA"].contains(key))
          {
            if (v isnot Bool) throw ArgErr("Unsupported flag")
          }
          else if (key == "timeMax")
          {
            duration:=v as Str ?: throw ArgErr("Unsupported duration")
            if (!Regex<|[0-9. ]+(ns|ms|sec|min|hr|h|day|d|s)|>.matches(duration)) throw ArgErr("Unsupported duration")
          }
          else if (v isnot Int && v isnot Float) throw ArgErr("Unsupported parameter number")
          result[key]=scalar(v)
        }
      }
      return result
    }
    if (field == "alarmLimits")
    {
      rows:=value as List ?: throw ArgErr("Invalid alarm limits")
      return rows.map |v->Obj?|
      {
        row:=v as Map ?: throw ArgErr("Invalid alarm limit")
        return ["categoryId":readableRef(db,canRead,row["categoryId"]),"limit":scalar(row["limit"])]
      }
    }
    return scalar(value)
  }

  private static Obj? scalar(Obj? value)
  {
    if (value == null || value is Str || value is Bool || value is Int || value is Float) return value
    throw ArgErr("Unsupported message value")
  }
  private static Str readableRef(Folio db, |Dict->Bool| canRead, Obj? value)
  {
    if (value isnot Str && value isnot Ref) throw ArgErr("Invalid reference")
    ref:=absolute(db,value is Ref ? (Ref)value : Ref(value.toStr))
    record:=db.readById(ref,false)
    if (record == null || !canRead(record)) throw ArgErr("Restricted reference")
    return ref.id
  }
  private static Ref absolute(Folio db, Ref ref) { db.idPrefix == null || !ref.isRel ? ref : ref.toAbs(db.idPrefix) }
}

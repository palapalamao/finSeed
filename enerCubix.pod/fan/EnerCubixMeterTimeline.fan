using haystack
using folio
using util

** Effective-time configuration evidence. It does not manufacture pre-upgrade membership.
internal class EnerCubixMeterTimeline
{
  static const Ref key:=Ref("enerCubix-meter-timeline")

  static Void initialize(Folio db, DateTime at:=DateTime.now)
  {
    if (db.readById(key,false) != null) return
    diffs:=capture(db,Diff[,],at)
    if (!diffs.isEmpty) db.commitAll(diffs)
  }

  ** Append these to the same optimistic transaction as the engineering change.
  static Diff[] capture(Folio db, Diff[] changes, DateTime at:=DateTime.now, Str? actor:=null)
  {
    prior:=db.readById(key,false)
    before:=Str:Dict[:]
    db.readAllList(Filter.has("enerCubixKind")).each |r| { if (tracked(r)) before[r.id.id]=r }
    after:=before.dup
    changes.each |d|
    {
      if (d.isTransient) return
      id:=absolute(db,d.id)
      original:=db.readById(id,false)
      if (d.isRemove) { after.remove(id.id); return }
      tags:=Etc.dictToMap(original ?: Etc.emptyDict)
      d.changes.each |v,k| { if (v is Remove) tags.remove(k); else tags[k]=v }
      candidate:=Etc.makeDict(tags.set("id",id))
      if (tracked(candidate)) after[id.id]=candidate
      else after.remove(id.id)
    }
    diffs:=Diff[,]
    sequence:=((prior?.get("enerCubixTimelineRevision") as Number)?.toInt ?: 0)+1
    if (prior == null)
    {
      diffs.add(Diff.makeAdd(Etc.makeDict(["enerCubixMeterTimeline":Marker.val,"enerCubixTimelineStart":at,"enerCubixTimelineRevision":Number(sequence),"dis":"EnerCubix meter history configuration"]),key))
      // Snapshot the committed post-change graph, starting only at this cutover.
      after.each |record,id| { diffs.add(epoch(record.id,configuration(db,record),at,sequence,null,true)) }
      return diffs
    }
    ids:=before.keys.dup.addAll(after.keys).unique
    ids.each |id|
    {
      a:=before[id] == null ? null : configuration(db,before[id])
      b:=after[id] == null ? null : configuration(db,after[id])
      if (json(a) != json(b)) diffs.add(epoch(Ref(id),b,at,sequence,actor))
    }
    if (!diffs.isEmpty) diffs.add(Diff(prior,Etc.makeDict(["enerCubixTimelineRevision":Number(sequence)])))
    return diffs
  }

  static [Str:Obj?][] segments(Folio db, [Str:Obj?][] currentRecords, DateTime from, DateTime to)
  {
    if (to <= from) return [Str:Obj?][,]
    meta:=db.readById(key,false)
    start:=meta?.get("enerCubixTimelineStart") as DateTime
    epochs:=db.readAllList(Filter.has("enerCubixMeterEpoch")).dup.sort |a,b|
    {
      order:=(a["enerCubixEffectiveFrom"] as DateTime) <=> (b["enerCubixEffectiveFrom"] as DateTime)
      return order != 0 ? order : (((a["enerCubixEpochSequence"] as Number)?.toInt ?: 0) <=> ((b["enerCubixEpochSequence"] as Number)?.toInt ?: 0))
    }
    bounds:=[from,to]
    if (start != null && start > from && start < to) bounds.add(start)
    epochs.each |e| { ts:=e["enerCubixEffectiveFrom"] as DateTime; if (ts != null && ts > from && ts < to) bounds.add(ts) }
    bounds=bounds.unique.sort
    answer:=[Str:Obj?][,]
    for (i:=0;i<bounds.size-1;i++)
    {
      at:=bounds[i]
      known:=start != null && at >= start
      records:=currentRecords
      if (known)
      {
        state:=Str:[Str:Obj?][:]
        epochs.each |e|
        {
          effective:=e["enerCubixEffectiveFrom"] as DateTime
          if (effective == null || effective > at) return
          id:=absolute(db,(Ref)e["enerCubixRecordRef"]).id
          if (e.has("enerCubixEpochRemoved")) state.remove(id)
          else state[id]=normalize(db,(Str:Obj?)JsonInStream(e["enerCubixEpochConfig"].toStr.in).readJson)
        }
        // Nontracked, non-meter presentation records retain existing behavior.
        records=currentRecords.findAll |r| { !kinds.contains(r["kind"]) }.dup.addAll(state.vals)
      }
      answer.add(["from":at.toIso,"to":bounds[i+1].toIso,"known":known,"records":records])
    }
    return answer
  }

  static [Str:Obj?][] recordsAt(Folio db, DateTime at)
  { EnerCubixMath.maps(segments(db,current(db),at,at+1sec).first["records"]) }

  static Str revision(Folio db, DateTime from, DateTime to)
  { JsonOutStream.writeJsonToStr(segments(db,current(db),from.toTimeZone(TimeZone.utc),to.toTimeZone(TimeZone.utc))).toBuf.toDigest("SHA-256").toHex }

  static [Str:Obj?][] current(Folio db)
  { db.readAllList(Filter.has("enerCubixKind")).findAll |r| { tracked(r) }.map |r->[Str:Obj?]| { configuration(db,r) } }

  private static const Str[] kinds:=["meter","totalMeter","sensor","category","subcategory","utility","expression","cleaningProfile","organization","space"]
  private static Bool tracked(Dict r)
  {
    kind:=r["enerCubixKind"] as Str
    return kind != null && kinds.contains(kind) && (r.has("enerCubix") || r.has("equip"))
  }
  private static [Str:Obj?] configuration(Folio db, Dict r)
  {
    out:=EnerCubixRepo.decode(r).dup
    ["mod","updatedAt","updatedBy","nativeDis","configurationError"].each |key| { out.remove(key) }
    return normalize(db,out)
  }

  private static Ref absolute(Folio db, Ref id)
  { db.idPrefix == null || !id.isRel ? id : id.toAbs(db.idPrefix) }

  ** Match Folio's commit identity before serializing a new snapshot, and read
  ** pre-fix local IDs in memory without rewriting their historical evidence.
  private static [Str:Obj?] normalize(Folio db, [Str:Obj?] record)
  {
    if (db.idPrefix == null) return record
    out:=record.dup
    oldId:=record["id"] as Str
    fields:=["id","historyPointId"].addAll(EnerCubixRepo.refTags.keys)
    fields.each |key|
    {
      value:=record[key] as Str
      if (value != null) out[key]=absolute(db,Ref(value)).id
    }
    // Initial virtual-equipment snapshots also derived this key from the local
    // equipment ID. Only that deterministic legacy key is corrected.
    history:=record["historyPointId"] as Str
    if (oldId != null && out["id"] != oldId && record["expressionId"] != null && record["pointId"] == null && history != null && Ref(history).toRel(db.idPrefix).id == EnerCubixMeterHistory.formulaId(Ref(oldId)).id)
      out["historyPointId"]=absolute(db,EnerCubixMeterHistory.formulaId(Ref(out["id"].toStr))).id
    if (record["kind"] == "expression" && record["variables"] is Map)
    {
      refs:=((Map)record["variables"]).dup
      refs.each |value,key| { if (value is Str) refs[key]=absolute(db,Ref(value.toStr)).id }
      out["variables"]=refs
    }
    return out
  }
  private static Str json(Obj? value) { JsonOutStream.writeJsonToStr(value) }
  private static Diff epoch(Ref id, [Str:Obj?]? record, DateTime at, Int sequence, Str? actor:=null, Bool initial:=false)
  {
    tags:=Str:Obj?["enerCubixMeterEpoch":Marker.val,"enerCubixRecordRef":id,"enerCubixEffectiveFrom":at,"enerCubixEpochSequence":Number(sequence),"dis":"EnerCubix meter configuration version"]
    if (actor != null && !actor.trim.isEmpty) tags["enerCubixEpochActor"]=actor
    if (initial) tags["enerCubixEpochInitial"]=Marker.val
    if (record == null) tags["enerCubixEpochRemoved"]=Marker.val
    else tags["enerCubixEpochConfig"]=json(record)
    return Diff.makeAdd(Etc.makeDict(tags))
  }
}

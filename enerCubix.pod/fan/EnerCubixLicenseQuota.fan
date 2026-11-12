using folio
using haystack
using skyarcd

** Counts the project's effective energy meters across all project permissions.
internal class EnerCubixLicenseQuota
{
  static const Int trialLimit := 10
  private static const Str[] kinds := ["meter","totalMeter"]
  private static const Str[] meterTags := ["enerCubixKind","enerCubix","equip","enerCubixStorageModel",
    "enerCubixCategoryRef","enerCubixCanonicalRef","enerCubixPointRef","enerCubixExpressionRef","enerCubixConfig"]
  private static const Filter enrolled := Filter.has("enerCubixKind").and(Filter.has("enerCubix").or(Filter.has("equip")))

  static Int used(Folio db) { count(rows(db),model(db)?.get("enerCubixStorageModel")=="nativeEquip") }

  static Bool allowed(Sys sys, Folio db)
  {
    EnerCubixLicenseStore.forSys(sys).active(EnerCubixLicenseStore.hostId(sys)) || used(db)<=trialLimit
  }

  static Void checkWrite(Sys sys, Folio db, Diff[] changes)
  {
    if (!changes.any |d| { d.isRemove || meterTags.any |tag| {d.changes.has(tag)} }) return
    if (EnerCubixLicenseStore.forSys(sys).active(EnerCubixLicenseStore.hostId(sys))) return
    current:=rows(db)
    ids:=Str:Bool[:]
    current.each |r| { ids[r.id.id]=true }
    changes.each |d|
    {
      if (d.isAdd || d.isRemove || ids.containsKey(d.id.id) || !d.changes.has("enerCubixKind")) return
      before:=db.readById(d.id,false)
      if (before!=null) current.add(before)
    }
    storage:=model(db)
    check(current,storage?.get("enerCubixStorageModel")=="nativeEquip",changes,storage?.id)
  }

  ** Preflight mixed enrollment before the native storage migration commits.
  static Void checkMigration(Sys sys, Folio db, [Str:Obj?][] input, [Str:Obj?] plan)
  {
    if (EnerCubixLicenseStore.forSys(sys).active(EnerCubixLicenseStore.hostId(sys))) return
    current:=rows(db)
    planned:=Str:[Str:Obj?][:]
    current.findAll |r| { eligible(r,true) }.each |r| { planned[r.id.id]=meterConfig(r) }
    EnerCubixMath.maps(plan["records"]).each |r| { planned[r["id"].toStr]=r }
    aliases:=(Str:Str)plan["mapping"]
    input.each |source|
    {
      if (source["kind"]==null) return  // Tree operations also pass id/mod receipts.
      r:=EnerCubixNativeEquip.rewrite(source,aliases)
      id:=r["id"] as Str
      if (id==null && r["pointId"] is Str)
        id=(db.readById(Ref(r["pointId"].toStr),false)?.get("equipRef") as Ref)?.id
      if (id==null) return
      planned[id]=r.dup.set("id",id)
    }
    enforce(count(current,false),uniqueCount(planned))
  }

  internal static Void check(Dict[] current, Bool nativeOnly, Diff[] changes, Ref? modelRef := null)
  {
    pending:=Str:Dict[:]
    current.each |r| { pending[r.id.id]=r }
    nextNative:=nativeOnly
    changes.each |diff|
    {
      if (diff.changes.has("enerCubixStorageModel") || (diff.isRemove && diff.id==modelRef))
        nextNative=!diff.isRemove && diff.changes["enerCubixStorageModel"]=="nativeEquip"
      if (diff.isRemove) { pending.remove(diff.id.id); return }
      before:=pending[diff.id.id]
      tags:=Etc.dictToMap(before ?: Etc.emptyDict)
      diff.changes.each |v,k| { if (v is Remove) tags.remove(k); else tags[k]=v }
      updated:=Etc.makeDict(tags.set("id",diff.id))
      if (eligible(updated,false)) pending[diff.id.id]=updated
      else pending.remove(diff.id.id)
    }
    enforce(count(current,nativeOnly),count(pending.vals,nextNative))
  }

  internal static Int count(Dict[] records, Bool nativeOnly)
  {
    meters:=Str:[Str:Obj?][:]
    records.findAll |r| { eligible(r,nativeOnly) }.each |r| { meters[r.id.id]=meterConfig(r) }
    return uniqueCount(meters)
  }

  private static [Str:Obj?] meterConfig(Dict record)
  {
    fields:=Str:Obj?["kind":record["enerCubixKind"]]
    if (!record.has("equip"))
    {
      try { return EnerCubixRepo.decode(record) }
      catch (Err ignored) { return fields }
    }
    ["categoryId","canonicalId","pointId","expressionId"].each |key|
    {
      fields[key]=(record[EnerCubixRepo.refTags[key]] as Ref)?.id
    }
    return fields
  }

  private static Int uniqueCount(Str:[Str:Obj?] meters)
  {
    total:=0
    meters.each |r|
    {
      if (!isMeter(r["kind"])) return
      id:=r["canonicalId"] as Str
      target:=id==null ? null : meters[id]
      if (target==null || !isMeter(target["kind"]) || target["canonicalId"]!=null ||
        target["categoryId"]!=r["categoryId"] || target["pointId"]!=r["pointId"] ||
        target["expressionId"]!=r["expressionId"] || r["pointId"]==null) total++
    }
    return total
  }

  private static Void enforce(Int before, Int after)
  {
    if (after>trialLimit && after>before) throw EnerCubixHttpErr(409,"LICENSE_LIMIT","licenseMeterLimit")
  }

  private static Bool eligible(Dict r, Bool nativeOnly)
  { isMeter(r["enerCubixKind"]) && (r.has("equip") || (!nativeOnly && r.has("enerCubix"))) }

  private static Bool isMeter(Obj? kind)
  { kind is Str && kinds.contains(kind) }

  private static Dict[] rows(Folio db)
  { db.readAllList(enrolled).findAll |r| { eligible(r,false) } }

  private static Dict? model(Folio db)
  { db.read(Filter.has("enerCubixStorageModel"),false) }
}

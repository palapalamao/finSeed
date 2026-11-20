using haystack
using folio
using skyarcd
using hx
using alarmExt
using util
using concurrent
using [java] java.util.concurrent.locks::ReentrantLock
using [java] fanx.interop::Interop
using [java] java.io::File as JavaFile
using [java] java.nio.file::Files
using [java] java.nio.file::CopyOption
using [java] java.nio.file::StandardCopyOption

** Explicit administrator-only namespace upgrade. Record IDs and history stay intact.
class FinEnergyNamespace
{
  private static const Unsafe maintenanceLock := Unsafe(ReentrantLock())

  internal static Dict? singleton(Folio db,Str marker)
  {
    matches:=db.readAllList(Filter.has(marker))
    if (matches.size > 1) throw ArgErr("Duplicate FIN Energy singleton: "+marker)
    return matches.first
  }

  static Dict changes(Dict original, Str from, Str to)
  {
    out:=Str:Obj?[:]
    original.each |v,name|
    {
      if (runtimeTag(name)) return
      target:=name.startsWith(from) ? to+name[from.size..-1] : name
      value:=rewrite(v,from,to)
      if ([from+"Config",from+"EpochConfig",from+"LegacyData"].contains(name) && v is Str)
        value=JsonOutStream.writeJsonToStr(rewrite(JsonInStream(v.toStr.in).readJson,from,to))
      if (name == "hisFunc" && v == from+"CleanHis") value=to+"CleanHis"
      if (name == "jobExpr" && v == from+"Scheduled()") value=to+"Scheduled()"
      if (target != name)
      {
        if (original.has(target) && !sameValue(original[target],value)) throw ArgErr("Namespace target collision: "+target)
        out[name]=Remove.val; out[target]=value
      }
      else if (!sameValue(value,v)) out[name]=value
    }
    if (original.has(from+"TaskLock")) out["dis"]="FIN Energy shared calculation lock"
    if (original["jobExpr"] == from+"Scheduled()") out["dis"]="FIN Energy hourly calculation and alarms"
    return Etc.makeDict(out)
  }

  private static Obj? rewrite(Obj? value, Str from, Str to)
  {
    if (value is Dict)
    {
      d:=(Dict)value
      edits:=changes(d,from,to)
      return edits.isEmpty ? d : merge(d,edits)
    }
    if (value is Map)
    {
      m:=(Map)value
      result:=Str:Obj?[:]
      m.each |v,k|
      {
        name:=k.toStr
        target:=name.startsWith(from) ? to+name[from.size..-1] : name
        converted:=name == "hisFunc" && v == from+"CleanHis" ? to+"CleanHis" : rewrite(v,from,to)
        if (name == "snapshot" && m["action"] == "nativeEquipSnapshot" && v is Map)
          converted=rewriteEquipmentSnapshot((Map)v,from,to)
        if (result.containsKey(target) && !sameValue(result[target],converted)) throw ArgErr("Namespace snapshot collision: "+target)
        result[target]=converted
      }
      return result
    }
    if (value is List) return ((List)value).map |v->Obj?| { rewrite(v,from,to) }
    return value
  }

  private static Map rewriteEquipmentSnapshot(Map snapshot,Str from,Str to)
  {
    result:=(Map)rewrite(snapshot,from,to)
    ["before","after"].each |key|
    {
      text:=snapshot[key] as Str
      if (text == null) return
      rows:=Dict[,]
      ZincReader(text.in).readGrid.each |r| { rows.add(merge(r,changes(r,from,to))) }
      result[key]=grid(rows)
    }
    text:=snapshot["afterBusiness"] as Str
    if (text != null) result["afterBusiness"]=JsonOutStream.writeJsonToStr(rewrite(JsonInStream(text.in).readJson,from,to))
    return result
  }

  private static Dict merge(Dict original, Dict edits)
  {
    out:=Etc.dictToMap(original)
    edits.each |v,k| { if (v == Remove.val) out.remove(k); else out[k]=v }
    return Etc.makeDict(out)
  }

  static Alarm? alarmChange(Dict original, Str from, Str to)
  {
    edits:=changes(original,from,to)
    return edits.isEmpty ? null : Alarm.wrap(merge(original,edits))
  }

  ** Preview is mandatory. Snapshot files and a recovery journal precede writes.
  ** This is a maintenance operation: stop business jobs before apply/rollback.
  static Dict run(Str from, Str to, Bool apply, Str? expected)
  {
    gate:=(ReentrantLock)maintenanceLock.val
    gate.lock
    try {return runImpl(from,to,apply,expected)}
    finally {gate.unlock}
  }

  private static Dict runImpl(Str from,Str to,Bool apply,Str? expected)
  {
    cx:=Context.cur
    administrator
    migrationDirection(from,to)
    if (apply) FinEnergyNamespaceFence.requireAvailable(cx.db)
    records:=persistentRecords(cx.db).sort |a,b->Int| { a.id.toStr <=> b.id.toStr }
    originals:=Dict[,]; updated:=Dict[,]; diffs:=Diff[,]
    records.each |r|
    {
      edits:=changes(r,from,to)
      if (edits.isEmpty) return
      originals.add(r); updated.add(merge(r,edits)); diffs.add(Diff(r,edits))
    }
    validateGraph(records.map |r->Dict| { merge(r,changes(r,from,to)) },to)
    alarmOriginals:=Dict[,]; alarmUpdated:=Dict[,]
    AlarmFuncs.alarms().each |alarm|
    {
      next:=alarmChange(alarm,from,to)
      if (next == null) return
      alarmOriginals.add(alarm); alarmUpdated.add(next)
    }
    files:=assetPlan(records,cx.proj.dir,cx.proj.id,from,to)
    before:=grid(originals); after:=grid(updated)
    alarmBefore:=grid(alarmOriginals); alarmAfter:=grid(alarmUpdated)
    revision:=(from+"|"+to+"|"+fingerprint(originals,updated)+fingerprint(alarmOriginals,alarmUpdated)+JsonOutStream.writeJsonToStr(files)).toBuf.toDigest("SHA-256").toHex
    report:=Str:Obj?["project":cx.proj.name,"from":from,"to":to,"records":Number(diffs.size),"alarms":Number(alarmUpdated.size),"files":Number(files.size),"revision":revision,"applied":false]
    if (!apply) return Etc.makeDict(report)
    if (expected != revision) throw ArgErr("Namespace preview changed; inspect again")
    report["backupDigest"]=(from+"|"+to+"|"+before+after+alarmBefore+alarmAfter+JsonOutStream.writeJsonToStr(files)).toBuf.toDigest("SHA-256").toHex
    folder:=cx.proj.ioDir+`namespace-${Uuid()}/`
    folder.create
    write(folder+`records-before.zinc`,before); write(folder+`records-after.zinc`,after)
    write(folder+`alarms-before.zinc`,alarmBefore); write(folder+`alarms-after.zinc`,alarmAfter)
    write(folder+`files.json`,JsonOutStream.writeJsonToStr(files))
    report["backup"]=folder.name
    report["phase"]="prepared"
    journal(folder,report)
    try { return resume(folder.name) }
    catch (Err e) { throw Err("Namespace migration interrupted; backup="+folder.name+"; resume or rollback this same backup",e) }
  }

  ** Resume the original journal, never create a second overlapping migration.
  ** Delta merges retain native updates and accept already-applied resources.
  static Dict resume(Str backup)
  {
    gate:=(ReentrantLock)maintenanceLock.val
    gate.lock
    try {return resumeImpl(backup)}
    catch (Err e) {throw Err("Namespace resume interrupted; backup="+backup,e)}
    finally {gate.unlock}
  }

  private static Dict resumeImpl(Str backup)
  {
    cx:=Context.cur
    administrator
    folder:=backupFolder(backup)
    report:=(Str:Obj?)JsonInStream((folder+`progress.json`).readAllStr.in).readJson
    if (report["project"] != cx.proj.name || report["phase"] == "rolledBack") throw ArgErr("Namespace journal cannot resume this project/state")
    from:=report["from"].toStr; to:=report["to"].toStr
    migrationDirection(from,to)
    verifyBackup(folder,report)
    verifyJournalIdentity(folder,cx.proj.name,report)
    if (report["phase"] == "complete")
    {
      finishMaintenance(cx.db,cx.proj.name,cx.proj.ioDir,folder.name)
      return Etc.makeDict(report)
    }
    FinEnergyNamespaceFence.acquire(cx.db,cx.proj.name,report)
    before:=readGrid(folder+`records-before.zinc`); after:=readGrid(folder+`records-after.zinc`)
    alarmBefore:=readGrid(folder+`alarms-before.zinc`); alarmAfter:=readGrid(folder+`alarms-after.zinc`)
    files:=(List)JsonInStream((folder+`files.json`).readAllStr.in).readJson
    diffs:=Diff[,];projected:=Str:Dict[:]
    before.each |prior,i|
    {
      current:=cx.db.readById(prior.id,false)
      patch:=safeRestore(current,after[i],prior)
      projected[prior.id.id]=merge(cx.db.readByIdPersistentTags(prior.id),patch)
      if (!patch.isEmpty) diffs.add(Diff(current,patch))
    }
    graph:=persistentRecords(cx.db).map |r->Dict| {projected[r.id.id] ?: r}
    validateGraph(graph,to)
    if (graph.any |r| {!changes(r,from,to).isEmpty}) throw ArgErr("Namespace source configuration changed after backup; backup="+backup)
    alarmUpdates:=resumeAlarms(alarmBefore,alarmAfter)
    // First validate all files, then complete missing backup copies, then publish.
    files.each |raw|
    {
      item:=(Map)raw; name:=item["name"].toStr
      source:=assetFile(cx.proj.dir,from,name); target:=assetFile(cx.proj.dir,to,name); copy:=folder+`assets/`+name.toUri
      if ((source.exists && digest(source) != item["hash"]) || (copy.exists && digest(copy) != item["hash"]) || (target.exists && digest(target) != item["hash"]) || (!source.exists && !copy.exists)) throw ArgErr("Namespace resume asset conflict; backup="+backup)
    }
    files.each |raw|
    {
      item:=(Map)raw; name:=item["name"].toStr; copy:=folder+`assets/`+name.toUri
      if (!copy.exists) {copy.parent.create;assetFile(cx.proj.dir,from,name).copyTo(copy)}
    }
    report["phase"]="backedUp"; journal(folder,report)
    files.each |raw|
    {
      item:=(Map)raw;name:=item["name"].toStr;target:=assetFile(cx.proj.dir,to,name)
      if (!target.exists) {target.parent.create;(folder+`assets/`+name.toUri).copyTo(target)}
      if (digest(target) != item["hash"]) throw IOErr("Namespace resume verification failed; backup="+backup)
    }
    report["phase"]="filesCopied"; journal(folder,report)
    if (!diffs.isEmpty) cx.db.commitAll(diffs)
    report["phase"]="recordsApplied"; journal(folder,report)
    // Capture current native acknowledgement/state immediately before merging.
    alarmUpdates=resumeAlarms(alarmBefore,alarmAfter)
    writeAlarms(alarmUpdates)
    report["phase"]="complete";report["applied"]=true;journal(folder,report)
    finishMaintenance(cx.db,cx.proj.name,cx.proj.ioDir,folder.name)
    return Etc.makeDict(report)
  }

  private static Dict[] resumeAlarms(Dict[] before,Dict[] after)
  {
    current:=Str:Dict[:];updates:=Dict[,]
    AlarmFuncs.alarms().each |r| {current[r.id.id]=r}
    before.each |prior,i|
    {
      alarm:=current[prior.id.id]
      patch:=safeRestore(alarm,after[i],prior)
      if (!patch.isEmpty) updates.add(merge(alarm,patch))
    }
    return updates
  }

  ** Restore only unchanged pre/post migration states. Never overwrite later edits.
  ** Safe to repeat after interruption; the source files were never moved/deleted.
  static Dict rollback(Str backup)
  {
    gate:=(ReentrantLock)maintenanceLock.val
    gate.lock
    try {return rollbackImpl(backup)}
    catch (Err e) {throw Err("Namespace rollback interrupted; backup="+backup,e)}
    finally {gate.unlock}
  }

  private static Dict rollbackImpl(Str backup)
  {
    cx:=Context.cur
    administrator
    folder:=backupFolder(backup)
    report:=(Str:Obj?)JsonInStream((folder+`progress.json`).readAllStr.in).readJson
    if (report["project"] != cx.proj.name) throw ArgErr("Namespace backup project mismatch")
    from:=report["from"].toStr; to:=report["to"].toStr
    migrationDirection(from,to)
    verifyBackup(folder,report)
    verifyJournalIdentity(folder,cx.proj.name,report)
    if (report["phase"] == "rolledBack")
    {
      finishMaintenance(cx.db,cx.proj.name,cx.proj.ioDir,folder.name)
      return Etc.makeDict(report)
    }
    priorFence:=FinEnergyNamespaceFence.current(cx.db)
    if (priorFence != null) FinEnergyNamespaceFence.verifyOwner(priorFence,cx.proj.name,report)
    // Change the terminal journal before acquiring its fence, so restart
    // reconciliation cannot clear maintenance while rollback is planning.
    report["phase"]="rollbackPlanning";journal(folder,report)
    FinEnergyNamespaceFence.acquire(cx.db,cx.proj.name,report)
    before:=readGrid(folder+`records-before.zinc`); after:=readGrid(folder+`records-after.zinc`)
    alarmBefore:=readGrid(folder+`alarms-before.zinc`); alarmAfter:=readGrid(folder+`alarms-after.zinc`)
    files:=(List)JsonInStream((folder+`files.json`).readAllStr.in).readJson
    diffs:=Diff[,]
    before.each |prior,i|
    {
      current:=cx.db.readById(prior.id,false)
      patch:=safeRestore(current,prior,after[i])
      if (!patch.isEmpty) diffs.add(Diff(current,patch))
    }
    alarms:=Str:Dict[:]
    AlarmFuncs.alarms().each |r| { alarms[r.id.id]=r }
    alarmRestore:=Dict[,]
    alarmBefore.each |prior,i|
    {
      current:=alarms[prior.id.id]
      patch:=safeRestore(current,prior,alarmAfter[i])
      if (!patch.isEmpty) alarmRestore.add(merge(current,patch))
    }
    // Validate every resource before the first restoration.
    files.each |raw|
    {
      item:=(Map)raw; name:=item["name"].toStr
      source:=assetFile(cx.proj.dir,from,name); target:=assetFile(cx.proj.dir,to,name)
      copy:=folder+`assets/`+name.toUri
      if ((!copy.exists && !source.exists) || (copy.exists && digest(copy) != item["hash"]) || (source.exists && digest(source) != item["hash"]) || (target.exists && digest(target) != item["hash"])) throw ArgErr("Namespace rollback asset conflict")
    }
    report["phase"]="rollbackPrepared"; journal(folder,report)
    if (!diffs.isEmpty) cx.db.commitAll(diffs)
    report["phase"]="recordsRestored"; journal(folder,report)
    writeAlarms(alarmRestore)
    files.each |raw|
    {
      item:=(Map)raw; name:=item["name"].toStr
      source:=assetFile(cx.proj.dir,from,name); target:=assetFile(cx.proj.dir,to,name)
      if (!source.exists) { source.parent.create; (folder+`assets/`+name.toUri).copyTo(source) }
      if (item["created"] == true && target.exists) target.delete
    }
    report["phase"]="rolledBack"; report["applied"]=false; journal(folder,report)
    finishMaintenance(cx.db,cx.proj.name,cx.proj.ioDir,folder.name)
    return Etc.makeDict(report)
  }

  ** Only keys changed by this migration enter the preview fingerprint. Native
  ** collection/current values and acknowledgements may continue between calls.
  internal static Str fingerprint(Dict[] before,Dict[] after)
  {
    rows:=Dict[,]
    before.each |r,i| {rows.add(Etc.makeDict(["id":r.id,"delta":deltaFingerprint(r,after[i])]))}
    return grid(rows.sort |a,b| {a.id.id <=> b.id.id})
  }
  private static Dict deltaFingerprint(Dict before,Dict after)
  {
    values:=Str:Obj?[:]
    restoreChanges(before,after).each |unused,key|
    {
      if (before[key] is Dict && after[key] is Dict)
        values[key]=deltaFingerprint(before[key],after[key])
      else
      {
        item:=Str:Obj?["beforePresent":before.has(key),"afterPresent":after.has(key)]
        if (before.has(key)) item["beforeValue"]=before[key]
        if (after.has(key)) item["afterValue"]=after[key]
        values[key]=Etc.makeDict(item)
      }
    }
    return Etc.makeDict(values)
  }

  ** Validate the complete post-upgrade graph before any backup or publication.
  internal static Void validateGraph(Dict[] records,Str target)
  {
    ["Revision","StorageModel","CockpitAssetManifest","CockpitManifest","MeterTimeline","TaskLock"].each |suffix|
    {
      if (records.findAll |r| {r.has(target+suffix)}.size > 1) throw ArgErr("Namespace singleton collision: "+target+suffix)
    }
    if (records.findAll |r| {r["jobExpr"] == target+"Scheduled()"}.size > 1) throw ArgErr("Namespace scheduled job collision")
    owners:=Ref:Bool[:]
    records.each |r|
    {
      if (!r.has(target+"MeterContinuity")) return
      owner:=r[target+"MainRef"] as Ref ?: throw ArgErr("Namespace continuity owner missing")
      if (owners[owner] == true) throw ArgErr("Namespace continuity owner collision")
      owners[owner]=true
    }
  }

  internal static Dict safeRestore(Dict? current,Dict prior,Dict next)
  {
    if (current == null || current.id != prior.id || next.id != prior.id) throw ArgErr("Namespace rollback identity conflict")
    return restoreOwned(current,prior,next)
  }

  private static Dict restoreOwned(Dict current,Dict prior,Dict next)
  {
    patch:=Str:Obj?[:]
    // Only migration-owned changes are restored. Native curVal/history status,
    // alarm acknowledgements and other subsequent user edits remain current.
    restoreChanges(prior,next).each |unused,key|
    {
      if (current[key] is Dict && prior[key] is Dict && next[key] is Dict)
      {
        nested:=restoreOwned(current[key],prior[key],next[key])
        if (!nested.isEmpty) patch[key]=merge(current[key],nested)
        return
      }
      wasPrior:=current.has(key) == prior.has(key) && sameValue(current[key],prior[key])
      wasNext:=current.has(key) == next.has(key) && sameValue(current[key],next[key])
      if (!wasPrior && !wasNext) throw ArgErr("Namespace rollback conflicts with a later tag edit: "+key)
      if (!wasPrior) patch[key]=prior.has(key) ? prior[key] : Remove.val
    }
    return Etc.makeDict(patch)
  }

  internal static Dict restoreChanges(Dict current,Dict target)
  {
    patch:=Str:Obj?[:]
    names:=Etc.dictToMap(current).keys.addAll(Etc.dictToMap(target).keys).unique
    names.each |key|
    {
      if (key == "id" || key == "mod" || runtimeTag(key)) return
      if (!target.has(key)) patch[key]=Remove.val
      else if (!current.has(key) || !sameValue(current[key],target[key])) patch[key]=target[key]
    }
    return Etc.makeDict(patch)
  }

  ** Haystack Dict equality is identity-based. A persisted Zinc journal rebuilds
  ** Dicts (including those nested in lists), so compare their exact values and
  ** presence instead of rejecting an unchanged configuration after restart.
  private static Bool sameValue(Obj? a,Obj? b)
  {
    if (a == b) return true
    if (a == null || b == null) return false
    if (a is Dict && b is Dict)
    {
      left:=(Dict)a;right:=(Dict)b;equal:=true
      left.each |v,k| {if (v != null && (!right.has(k) || !sameValue(v,right[k]))) equal=false}
      right.each |v,k| {if (v != null && !left.has(k)) equal=false}
      return equal
    }
    if (a is Map && b is Map)
    {
      left:=(Map)a;right:=(Map)b
      if (left.size != right.size) return false
      equal:=true
      left.each |v,k| {if (!right.containsKey(k) || !sameValue(v,right[k])) equal=false}
      return equal
    }
    if (a is List && b is List)
    {
      left:=(List)a;right:=(List)b
      if (left.size != right.size) return false
      equal:=true
      left.each |v,i| {if (!sameValue(v,right[i])) equal=false}
      return equal
    }
    return false
  }
  private static Bool same(Dict a,Dict b) { restoreChanges(a,b).isEmpty }

  ** Persistent migration never publishes or deletes a transient cache. Read
  ** Folio's authoritative projection rather than guessing from tag spelling.
  internal static Dict[] persistentRecords(Folio db)
  { db.readAllList(Filter.has("id")).map |r->Dict| {db.readByIdPersistentTags(r.id)} }

  ** Both supported legacy MeterRollup implementations write exactly these four
  ** product tags with Diff.transient (plus native curVal/curStatus/curErr).
  ** Ignore them in old journals too; runtime refresh regenerates the new tags.
  private static Bool runtimeTag(Str name)
  {
    return ["enerCubix","enercubix","finEnergy"].any |prefix|
    {
      name.startsWith(prefix) && ["RollupRef","RollupAt","RollupStatus","RollupHasGap"].contains(name[prefix.size..-1])
    }
  }

  internal static Bool needsMigration(Folio db)
  {
    if (FinEnergyNamespaceFence.blocked(db)) return true
    names:=Str[,]
    ["enerCubix","enercubix"].each |prefix|
    {
      ["","Kind","Revision","StorageModel","CockpitAssetManifest","CockpitManifest","MeterTimeline","TaskLock","MeterContinuity","CleaningOwnerRef"].each |suffix| {names.add(prefix+suffix)}
    }
    filter:=Filter.has(names.first)
    names[1..-1].each |name| {filter=filter.or(Filter.has(name))}
    return db.readAllList(filter).any |r|
    {
      persistent:=db.readByIdPersistentTags(r.id)
      return names.any |name| {persistent.has(name)}
    }
  }
  ** Restart reconciliation only releases a verified terminal journal. Missing,
  ** changed or incomplete recovery materials keep every business entry paused.
  internal static Bool recoverMaintenance(Folio db,Str project,File ioDir)
  {
    gate:=(ReentrantLock)maintenanceLock.val
    if (!gate.tryLock) return FinEnergyNamespaceFence.blocked(db)
    try {return recoverMaintenanceImpl(db,project,ioDir)}
    finally {gate.unlock}
  }

  private static Bool recoverMaintenanceImpl(Folio db,Str project,File ioDir)
  {
    if (!FinEnergyNamespaceFence.blocked(db)) return false
    try
    {
      fence:=FinEnergyNamespaceFence.current(db)
      folder:=maintenanceFolder(ioDir,fence["finEnergyMigrationBackup"].toStr)
      report:=(Str:Obj?)JsonInStream((folder+`progress.json`).readAllStr.in).readJson
      verifyJournalIdentity(folder,project,report)
      FinEnergyNamespaceFence.verifyOwner(fence,project,report)
      if (!["complete","rolledBack"].contains(report["phase"])) return true
      verifyBackup(folder,report)
      FinEnergyNamespaceFence.release(db,project,report)
      return FinEnergyNamespaceFence.blocked(db)
    }
    catch (Err e) {return true}
  }

  private static Void finishMaintenance(Folio db,Str project,File ioDir,Str backup)
  {
    folder:=maintenanceFolder(ioDir,backup)
    report:=(Str:Obj?)JsonInStream((folder+`progress.json`).readAllStr.in).readJson
    verifyJournalIdentity(folder,project,report)
    verifyBackup(folder,report)
    FinEnergyNamespaceFence.release(db,project,report)
  }

  private static Void verifyJournalIdentity(File folder,Str project,Map report)
  {
    if (report["project"] != project || report["backup"] != folder.name) throw ArgErr("Namespace journal ownership mismatch")
    migrationDirection(report["from"].toStr,report["to"].toStr)
  }

  private static Void migrationDirection(Str from,Str to)
  {
    if (!["enerCubix","enercubix"].contains(from) || to != "finEnergy") throw ArgErr("Only the legacy FIN Energy namespace upgrade is supported")
  }
  private static File backupFolder(Str backup) { maintenanceFolder(Context.cur.proj.ioDir,backup) }
  private static File maintenanceFolder(File root,Str backup)
  {
    if (!Regex<|namespace-[0-9a-fA-F-]{36}|>.matches(backup)) throw ArgErr("Invalid namespace backup")
    folder:=root+(backup+"/").toUri
    if (!Interop.toJava(folder).getCanonicalPath.startsWith(Interop.toJava(root).getCanonicalPath+JavaFile.separator)) throw ArgErr("Namespace backup escapes project")
    return folder
  }
  private static Void verifyBackup(File folder,Map report)
  {
    proof:=report["from"].toStr+"|"+report["to"]+"|"+(folder+`records-before.zinc`).readAllStr+(folder+`records-after.zinc`).readAllStr+(folder+`alarms-before.zinc`).readAllStr+(folder+`alarms-after.zinc`).readAllStr+(folder+`files.json`).readAllStr
    if (proof.toBuf.toDigest("SHA-256").toHex != report["backupDigest"]) throw ArgErr("Namespace backup integrity mismatch")
  }
  private static Bool namespace(Str name) { Regex<|[a-z][A-Za-z0-9]*|>.matches(name) }
  private static Void administrator() { if (!Context.cur.user.isAdmin) throw ArgErr("Administrator required") }
  private static Str grid(Dict[] rows) { ZincWriter.gridToStr(Etc.makeDictsGrid(null,rows)) }
  private static Dict[] readGrid(File f) { rows:=Dict[,]; ZincReader(f.readAllStr.in).readGrid.each |r| { rows.add(r) }; return rows }
  private static Void write(File f,Str text) { f.out.print(text).close }
  private static Void journal(File folder,Str:Obj? report)
  {
    pending:=folder+`progress.pending.json`
    write(pending,JsonOutStream.writeJsonToStr(report))
    // Same-directory atomic replacement: a crash retains the previous journal.
    options:=CopyOption[StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE]
    Files.move(Interop.toJava(pending).toPath,Interop.toJava(folder+`progress.json`).toPath,options)
  }
  private static Void verifyAlarms(Dict[] expected)
  {
    current:=Str:Dict[:]
    AlarmFuncs.alarms().each |r| {current[r.id.id]=r}
    expected.each |r|
    {
      actual:=current[r.id.id]
      if (actual == null || !same(actual,r)) throw ArgErr("Namespace alarm changed during maintenance: "+r.id)
    }
  }
  private static Void writeAlarms(Dict[] records)
  {
    if (records.isEmpty) return
    AlarmLib lib:=HxContext.curHx.rt.lib("alarm")
    lib.db.createOrUpdate(records.map |r->Alarm| { Alarm.wrap(r) },false).get(30sec)
  }
  internal static [Str:Obj?][] assetPlan(Dict[] records,File projectDir,Ref projectRef,Str from,Str to)
  {
    out:=[Str:Obj?][,]; seen:=Str:Bool[:]
    records.each |record|
    {
      if (!record.has(from+"CockpitAsset") || record[from+"AssetProjectRef"] != projectRef) return
      name:=record[from+"AssetFile"] as Str ?: throw ArgErr("Namespace asset filename missing")
      if (seen[name] == true) return
      seen[name]=true
      source:=assetFile(projectDir,from,name); target:=assetFile(projectDir,to,name)
      if (!source.exists || digest(source) != record[from+"AssetHash"]) throw ArgErr("Namespace source asset hash mismatch")
      hash:=digest(source)
      if (target.exists && digest(target) != hash) throw ArgErr("Namespace target asset collision")
      out.add(["name":name,"hash":hash,"created":!target.exists])
    }
    return out.sort |a,b| { a["name"].toStr <=> b["name"].toStr }
  }
  private static Str digest(File file) { file.readAllBuf.toDigest("SHA-256").toHex }
  private static File assetFile(File projectDir,Str ns,Str name)
  {
    if (!namespace(ns) || !Regex<|[0-9a-f]{32}\.(png|jpg)|>.matches(name)) throw ArgErr("Invalid namespace asset")
    root:=Interop.toJava(projectDir).getCanonicalPath+JavaFile.separator
    file:=projectDir+(ns+"-private/cockpit-assets/"+name).toUri
    if (!Interop.toJava(file).getCanonicalPath.startsWith(root)) throw ArgErr("Namespace asset escapes project")
    return file
  }
}

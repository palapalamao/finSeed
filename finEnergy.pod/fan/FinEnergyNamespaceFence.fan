using haystack
using folio

** Project-local maintenance ownership survives restart and partially committed
** cross-store upgrades. This record never owns a point or a history stream.
internal class FinEnergyNamespaceFence
{
  static const Ref key := Ref("finEnergy-namespace-maintenance")
  static const Str marker := "finEnergyNamespaceMaintenance"

  static Bool blocked(Folio db)
  { db.readById(key,false) != null || db.read(Filter.has(marker),false) != null }

  static Dict? current(Folio db)
  {
    atKey:=db.readById(key,false)
    marked:=db.readAllList(Filter.has(marker))
    if (atKey == null && marked.isEmpty) return null
    if (atKey == null || !atKey.has(marker) || marked.size != 1 || marked.first.id != atKey.id ||
      ["point","his","equip","site","floor","finEnergyKind"].any |tag| {atKey.has(tag)})
      throw ArgErr("Namespace maintenance record collision")
    return atKey
  }

  static Void requireAvailable(Folio db)
  {
    fence:=current(db)
    if (fence != null) throw ArgErr("Namespace maintenance already owns backup="+fence["finEnergyMigrationBackup"])
  }

  static Dict acquire(Folio db,Str project,Map report)
  {
    validateReport(project,report)
    fence:=current(db)
    if (fence != null) {verifyOwner(fence,project,report);return fence}
    tags:=Etc.makeDict([marker:Marker.val,"finEnergyMigrationProject":project,
      "finEnergyMigrationBackup":report["backup"],"finEnergyMigrationDigest":report["backupDigest"],
      "finEnergyMigrationStartedAt":DateTime.now])
    try {return db.commit(Diff.makeAdd(tags,key)).newRec}
    catch (Err e)
    {
      // Reconcile an add collision or an uncertain acknowledgement by reading
      // the fixed record. Never adopt a competing journal or delete its fence.
      winner:=current(db)
      if (winner == null) throw e
      verifyOwner(winner,project,report)
      return winner
    }
  }

  static Void verifyOwner(Dict fence,Str project,Map report)
  {
    validateReport(project,report)
    if (fence["finEnergyMigrationProject"] != project ||
      fence["finEnergyMigrationBackup"] != report["backup"] ||
      fence["finEnergyMigrationDigest"] != report["backupDigest"])
      throw ArgErr("Namespace maintenance belongs to another project or backup")
  }

  ** Caller must first verify this report against its original on-disk journal
  ** and immutable snapshots. A nonterminal report can never release the fence.
  static Bool release(Folio db,Str project,Map verifiedReport)
  {
    validateReport(project,verifiedReport)
    if (!["complete","rolledBack"].contains(verifiedReport["phase"])) throw ArgErr("Namespace maintenance is not complete")
    fence:=current(db)
    if (fence == null) return false
    verifyOwner(fence,project,verifiedReport)
    try {db.commit(Diff(fence,null,Diff.remove))}
    catch (Err e) {if (current(db) != null) throw e}
    return true
  }

  private static Void validateReport(Str project,Map report)
  {
    backup:=report["backup"] as Str ?: ""
    digest:=report["backupDigest"] as Str ?: ""
    if (report["project"] != project || !Regex<|namespace-[0-9a-fA-F-]{36}|>.matches(backup) ||
      !Regex<|[0-9a-f]{64}|>.matches(digest)) throw ArgErr("Invalid namespace maintenance ownership")
  }
}

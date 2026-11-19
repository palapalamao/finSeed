using haystack
using folio
using folio3
using util
using concurrent
using [java] java.util.concurrent::CountDownLatch
using [java] java.util.concurrent::TimeUnit

class FinEnergyNamespaceFenceTest : Test
{
  private static const Str backupA := "namespace-12345678-1234-1234-1234-123456789012"
  private static const Str backupB := "namespace-87654321-4321-4321-4321-210987654321"

  Void testPartiallyAppliedMigrationStaysBlockedAfterRestart()
  {
    home:=Env.cur.tempDir+("finEnergy-maintenance-"+Uuid()+"/").toUri
    db:=Folio3.open(FolioConfig {it.dir=home;it.idPrefix="p:test:r:"})
    try
    {
      // Folio is already upgraded, but alarm/file publication is interrupted.
      db.commitAll([
        Diff.makeAdd(Etc.makeDict(["finEnergyKind":"meter"]),Ref("original-meter")),
        Diff.makeAdd(Etc.makeDict(["finEnergyNamespaceMaintenance":Marker.val,
          "finEnergyMigrationBackup":"namespace-12345678-1234-1234-1234-123456789012",
          "finEnergyMigrationProject":"test","finEnergyMigrationDigest":"a"*64]),Ref("finEnergy-namespace-maintenance"))])
      verify(FinEnergyNamespace.needsMigration(db))
      db.close
      db=Folio3.open(FolioConfig {it.dir=home;it.idPrefix="p:test:r:"})
      verify(FinEnergyNamespace.needsMigration(db))
      verifyEq(db.readById(Ref("original-meter"))["finEnergyKind"],"meter")
    }
    finally {db.close}
  }

  Void testSameJournalReacquiresButDifferentOwnerCannotPublishOrRelease()
  {
    fixture |db,io|
    {
      a:=report(backupA)
      first:=FinEnergyNamespaceFence.acquire(db,"test",a)
      verifyEq(FinEnergyNamespaceFence.acquire(db,"test",a)["mod"],first["mod"])
      verify(FinEnergyNamespace.needsMigration(db))
      verifyErr(ArgErr#) {FinEnergyNamespaceFence.requireAvailable(db)}
      verifyErr(ArgErr#) {FinEnergyNamespaceFence.acquire(db,"test",report(backupB))}
      wrongDigest:=a.dup;wrongDigest["backupDigest"]="b"*64
      verifyErr(ArgErr#) {FinEnergyNamespaceFence.acquire(db,"test",wrongDigest)}
      verifyErr(ArgErr#) {FinEnergyNamespaceFence.acquire(db,"other",a)}
      verifyErr(ArgErr#) {FinEnergyNamespaceFence.release(db,"test",a)}
      verifyEq(db.readCount(Filter.has(FinEnergyNamespaceFence.marker)),1)
      verifyEq(FinEnergyNamespaceFence.current(db).id,first.id)
      verifyEq(db.readById(Ref("native-point"))["curVal"],Number(123))
    }
  }

  Void testVerifiedCompleteJournalClearsFenceAfterRestartAndRepeatIsNoOp()
  {
    home:=Env.cur.tempDir+("finEnergy-fence-restart-"+Uuid()+"/").toUri
    io:=home+`io/`
    db:=Folio3.open(FolioConfig {it.dir=home+`db/`;it.idPrefix="p:test:r:"})
    try
    {
      a:=writeJournal(io,backupA,"recordsApplied")
      FinEnergyNamespaceFence.acquire(db,"test",a)
      db.close
      db=Folio3.open(FolioConfig {it.dir=home+`db/`;it.idPrefix="p:test:r:"})
      verify(FinEnergyNamespace.recoverMaintenance(db,"test",io))
      verify(FinEnergyNamespace.needsMigration(db))
      a["phase"]="complete";publish(io,a)
      verify(!FinEnergyNamespace.recoverMaintenance(db,"test",io))
      verify(!FinEnergyNamespace.needsMigration(db))
      verify(!FinEnergyNamespace.recoverMaintenance(db,"test",io))
      verify(!FinEnergyNamespaceFence.release(db,"test",a))
    }
    finally {db.close}
  }

  Void testEveryIncompletePhaseStaysFencedAndRollbackCompletionReleases()
  {
    fixture |db,io|
    {
      a:=writeJournal(io,backupA,"prepared")
      FinEnergyNamespaceFence.acquire(db,"test",a)
      ["prepared","backedUp","filesCopied","recordsApplied","rollbackPlanning","rollbackPrepared","recordsRestored"].each |phase|
      {
        a["phase"]=phase;publish(io,a)
        verify(FinEnergyNamespace.recoverMaintenance(db,"test",io))
        verify(FinEnergyNamespace.needsMigration(db))
      }
      a["phase"]="rolledBack";publish(io,a)
      verify(!FinEnergyNamespace.recoverMaintenance(db,"test",io))
      verify(!FinEnergyNamespace.needsMigration(db))
      verifyEq(db.readById(Ref("native-point"))["curVal"],Number(123))
    }
  }

  Void testMissingTamperedOrForeignJournalCannotClearMaintenance()
  {
    fixture |db,io|
    {
      a:=writeJournal(io,backupA,"complete")
      FinEnergyNamespaceFence.acquire(db,"test",a)
      folder:=io+(backupA+"/").toUri
      progress:=folder+`progress.json`
      progress.delete
      verify(FinEnergyNamespace.recoverMaintenance(db,"test",io))
      publish(io,a)
      wrong:=a.dup;wrong["project"]="foreign";publish(io,wrong)
      verify(FinEnergyNamespace.recoverMaintenance(db,"test",io))
      wrong=a.dup;wrong["backup"]=backupB
      progress.out.print(JsonOutStream.writeJsonToStr(wrong)).close
      verify(FinEnergyNamespace.recoverMaintenance(db,"test",io))
      publish(io,a)
      (folder+`records-after.zinc`).out.print("corrupted snapshot").close
      verify(FinEnergyNamespace.recoverMaintenance(db,"test",io))
      verify(FinEnergyNamespace.needsMigration(db))
      verifyEq(FinEnergyNamespaceFence.current(db)["finEnergyMigrationBackup"],backupA)
    }
  }

  Void testStaleCleanupCannotDeleteAnotherJournalOrNativeRecord()
  {
    fixture |db,io|
    {
      a:=writeJournal(io,backupA,"complete")
      FinEnergyNamespaceFence.acquire(db,"test",a)
      verify(!FinEnergyNamespace.recoverMaintenance(db,"test",io))
      b:=writeJournal(io,backupB,"recordsApplied")
      FinEnergyNamespaceFence.acquire(db,"test",b)
      verifyErr(ArgErr#) {FinEnergyNamespaceFence.release(db,"test",a)}
      verifyEq(FinEnergyNamespaceFence.current(db)["finEnergyMigrationBackup"],backupB)
    }
    fixture |db,io|
    {
      nativeRecord:=db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"dis":"native"]),FinEnergyNamespaceFence.key)).newRec
      verify(FinEnergyNamespace.needsMigration(db))
      verifyErr(ArgErr#) {FinEnergyNamespaceFence.acquire(db,"test",report(backupA))}
      verify(FinEnergyNamespace.recoverMaintenance(db,"test",io))
      verifyEq(db.readById(nativeRecord.id),nativeRecord)
    }
  }

  Void testConcurrentDifferentJournalsHaveOnePersistentWinner()
  {
    fixture |db,io|
    {
      pool:=ActorPool();ready:=CountDownLatch(2);start:=CountDownLatch(1)
      try
      {
        actors:=[Actor(pool,|Obj? message->Obj?| {race(message)}),Actor(pool,|Obj? message->Obj?| {race(message)})]
        one:=actors[0].send(Unsafe([db,report(backupA),ready,start]))
        two:=actors[1].send(Unsafe([db,report(backupB),ready,start]))
        verify(ready.await(10,TimeUnit.SECONDS));start.countDown
        result:=[one.get(10sec).toStr,two.get(10sec).toStr].sort
        verifyEq(result,["conflict","ok"])
        verifyEq(db.readCount(Filter.has(FinEnergyNamespaceFence.marker)),1)
        verify(FinEnergyNamespace.needsMigration(db))
      }
      finally {start.countDown;pool.stop;pool.join(20sec)}
    }
  }

  private static Obj? race(Obj? message)
  {
    args:=(List)((Unsafe)message).val
    ready:=(CountDownLatch)args[2];start:=(CountDownLatch)args[3]
    ready.countDown;start.await
    try {FinEnergyNamespaceFence.acquire(args[0],"test",args[1]);return "ok"}
    catch (ArgErr e) {return "conflict"}
  }

  private static Str:Obj? report(Str backup)
  { ["project":"test","backup":backup,"backupDigest":"a"*64,"phase":"recordsApplied","from":"enerCubix","to":"finEnergy"] }

  private static Str:Obj? writeJournal(File io,Str backup,Str phase)
  {
    folder:=io+(backup+"/").toUri;folder.create
    zinc:=ZincWriter.gridToStr(Etc.makeDictsGrid(null,Dict[,]))
    ["records-before.zinc","records-after.zinc","alarms-before.zinc","alarms-after.zinc"].each |name| {(folder+name.toUri).out.print(zinc).close}
    (folder+`files.json`).out.print("[]").close
    result:=report(backup);result["phase"]=phase
    result["backupDigest"]=("enerCubix|finEnergy|"+zinc+zinc+zinc+zinc+"[]").toBuf.toDigest("SHA-256").toHex
    publish(io,result)
    return result
  }

  private static Void publish(File io,Map report)
  { (io+(report["backup"].toStr+"/progress.json").toUri).out.print(JsonOutStream.writeJsonToStr(report)).close }

  private Void fixture(|Folio,File| body)
  {
    home:=Env.cur.tempDir+("finEnergy-fence-"+Uuid()+"/").toUri
    db:=Folio3.open(FolioConfig {it.dir=home+`db/`;it.idPrefix="p:test:r:"})
    try
    {
      point:=db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val]),Ref("native-point"))).newRec
      db.commit(Diff(point,Etc.makeDict(["curVal":Number(123)]),Diff.transient))
      body(db,home+`io/`)
    }
    finally {db.close}
  }
}

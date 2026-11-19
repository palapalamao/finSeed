using util
using haystack
using folio

class FinEnergyJobsTest : Test
{
  Void testArchivedCalculationActionsAreRejectedBeforeJobsCanWrite()
  {
    ["recalculate","setCalculationEnabled","unknown"].each |action| {verifyErr(ArgErr#) {FinEnergyJobs.checkAction(action)}}
    FinEnergyJobs.checkAction("scanAlarms");FinEnergyJobs.checkAction("setAlarmEnabled")
  }

  Void testNativeHourlyScheduleCreationAndLegacyRepair()
  {
    withDb |db|
    {
      key:=Ref("finEnergy-native-hourly-job")
      FinEnergyJobs.ensureSchedule(db)
      created:=db.readById(key)
      verifyEq(created["jobSchedule"],"every 1hr")
      rule:=Type.find("jobExt::ScheduleRule").method("fromStr").call(created["jobSchedule"])
      verifyNotNull(rule)
      now:=DateTime.now
      verifyEq(rule->isReady(now-2hr,now),true)
      verifyEq(rule->isReady(now-30min,now),false)
      FinEnergyJobs.ensureSchedule(db)
      verifyEq(db.readById(key)["mod"],created["mod"])

      db.commit(Diff(created,Etc.makeDict(["jobSchedule":"hourly"])))
      FinEnergyJobs.ensureSchedule(db)
      repaired:=db.readById(key)
      verifyEq(repaired["jobSchedule"],"every 1hr")
      verifyEq(repaired["jobExpr"],"finEnergyScheduled()")

      db.commit(Diff(repaired,Etc.makeDict(["jobSchedule":"every 2hr"])))
      custom:=db.readById(key)
      FinEnergyJobs.ensureSchedule(db)
      verifyEq(db.readById(key)["mod"],custom["mod"])
      verifyEq(db.readById(key)["jobSchedule"],"every 2hr")
    }
  }

  Void testNativeHourlyScheduleRejectsUnrelatedRecord()
  {
    withDb |db|
    {
      key:=Ref("finEnergy-native-hourly-job")
      unrelated:=db.commit(Diff.makeAdd(Etc.makeDict(["job":Marker.val,"jobExpr":"otherFunction()","jobSchedule":"every 2hr"]),key)).newRec
      verifyErr(ArgErr#) { FinEnergyJobs.ensureSchedule(db) }
      verifyEq(db.readById(key)["mod"],unrelated["mod"])
    }
  }

  Void testOneOwnerAndFailureReleases()
  {
    withDb |db|
    {
      now:=DateTime.now
      FinEnergyTaskLock.acquire(db,"first",now)
      verifyErr(FinEnergyHttpErr#) { FinEnergyTaskLock.acquire(db,"second",now+1min) }
      verify(!FinEnergyTaskLock.release(db,"second"))
      verify(FinEnergyTaskLock.release(db,"first"))
      verifyErr(ArgErr#) { FinEnergyTaskLock.withLock(db,"failing") |held->Obj?| { throw ArgErr("expected failure") } }
      FinEnergyTaskLock.acquire(db,"afterFailure")
      verify(FinEnergyTaskLock.release(db,"afterFailure"))
    }
  }

  Void testLeaseHeartbeatTakeoverAndOwnerSafeRelease()
  {
    withDb |db|
    {
      now:=DateTime.now
      FinEnergyTaskLock.acquire(db,"old",now)
      FinEnergyTaskLock.heartbeat(db,"old",Ref("old-job"),now+20min)
      verifyErr(FinEnergyHttpErr#) { FinEnergyTaskLock.acquire(db,"new",now+40min) }
      taken:=FinEnergyTaskLock.acquire(db,"new",now+51min)
      verifyEq(taken["finEnergyPreviousJob"],Ref("old-job"))
      verify(!FinEnergyTaskLock.release(db,"old"))
      verifyErr(FinEnergyHttpErr#) { FinEnergyTaskLock.heartbeat(db,"old",null,now+52min) }
      verify(FinEnergyTaskLock.release(db,"new"))
    }
  }

  Void testAcquireUsesFolioCompareAndSwap()
  {
    withDb |db|
    {
      now:=DateTime.now
      a:=FinEnergyTaskLock.acquisition(null,"a",now)
      b:=FinEnergyTaskLock.acquisition(null,"b",now)
      db.commit(a)
      try { db.commit(b); fail("Two initial lock owners were accepted") }
      catch (Err e) { verifyEq(e.typeof.name,"CommitErr"); verifyEq(db.readById(FinEnergyTaskLock.key)["finEnergyOwner"],"a") }
      prior:=db.readById(FinEnergyTaskLock.key)
      first:=FinEnergyTaskLock.acquisition(prior,"c",now+31min)
      second:=FinEnergyTaskLock.acquisition(prior,"d",now+31min)
      db.commit(first)
      try { db.commit(second); fail("A stale lock revision was accepted") }
      catch (Err e) { verifyEq(e.typeof.name,"ConcurrentChangeErr") }
    }
  }

  private Void withDb(|Folio| work)
  {
    dir:=Env.cur.tempDir+`finEnergy-job-test-${Uuid()}/`; dir.create
    db:=(Folio)Type.find("hxFolio::HxFolio").method("open").call(FolioConfig { name="finEnergyJobsTest";it.dir=dir;log=Log.get("finEnergyJobsTest") })
    try { work(db) }
    finally
    {
      db.close
      if (dir.parent.normalize == Env.cur.tempDir.normalize) dir.delete
    }
  }
}

using util
using haystack
using folio

class EnerCubixJobsTest : Test
{
  Void testArchivedCalculationActionsAreRejectedBeforeJobsCanWrite()
  {
    ["recalculate","setCalculationEnabled","unknown"].each |action| {verifyErr(ArgErr#) {EnerCubixJobs.checkAction(action)}}
    EnerCubixJobs.checkAction("scanAlarms");EnerCubixJobs.checkAction("setAlarmEnabled")
  }

  Void testNativeHourlyScheduleCreationAndLegacyRepair()
  {
    withDb |db|
    {
      key:=Ref("enerCubix-native-hourly-job")
      EnerCubixJobs.ensureSchedule(db)
      created:=db.readById(key)
      verifyEq(created["jobSchedule"],"every 1hr")
      rule:=Type.find("jobExt::ScheduleRule").method("fromStr").call(created["jobSchedule"])
      verifyNotNull(rule)
      now:=DateTime.now
      verifyEq(rule->isReady(now-2hr,now),true)
      verifyEq(rule->isReady(now-30min,now),false)
      EnerCubixJobs.ensureSchedule(db)
      verifyEq(db.readById(key)["mod"],created["mod"])

      db.commit(Diff(created,Etc.makeDict(["jobSchedule":"hourly"])))
      EnerCubixJobs.ensureSchedule(db)
      repaired:=db.readById(key)
      verifyEq(repaired["jobSchedule"],"every 1hr")
      verifyEq(repaired["jobExpr"],"enerCubixScheduled()")

      db.commit(Diff(repaired,Etc.makeDict(["jobSchedule":"every 2hr"])))
      custom:=db.readById(key)
      EnerCubixJobs.ensureSchedule(db)
      verifyEq(db.readById(key)["mod"],custom["mod"])
      verifyEq(db.readById(key)["jobSchedule"],"every 2hr")
    }
  }

  Void testNativeHourlyScheduleRejectsUnrelatedRecord()
  {
    withDb |db|
    {
      key:=Ref("enerCubix-native-hourly-job")
      unrelated:=db.commit(Diff.makeAdd(Etc.makeDict(["job":Marker.val,"jobExpr":"otherFunction()","jobSchedule":"every 2hr"]),key)).newRec
      verifyErr(ArgErr#) { EnerCubixJobs.ensureSchedule(db) }
      verifyEq(db.readById(key)["mod"],unrelated["mod"])
    }
  }

  Void testOneOwnerAndFailureReleases()
  {
    withDb |db|
    {
      now:=DateTime.now
      EnerCubixTaskLock.acquire(db,"first",now)
      verifyErr(EnerCubixHttpErr#) { EnerCubixTaskLock.acquire(db,"second",now+1min) }
      verify(!EnerCubixTaskLock.release(db,"second"))
      verify(EnerCubixTaskLock.release(db,"first"))
      verifyErr(ArgErr#) { EnerCubixTaskLock.withLock(db,"failing") |held->Obj?| { throw ArgErr("expected failure") } }
      EnerCubixTaskLock.acquire(db,"afterFailure")
      verify(EnerCubixTaskLock.release(db,"afterFailure"))
    }
  }

  Void testLeaseHeartbeatTakeoverAndOwnerSafeRelease()
  {
    withDb |db|
    {
      now:=DateTime.now
      EnerCubixTaskLock.acquire(db,"old",now)
      EnerCubixTaskLock.heartbeat(db,"old",Ref("old-job"),now+20min)
      verifyErr(EnerCubixHttpErr#) { EnerCubixTaskLock.acquire(db,"new",now+40min) }
      taken:=EnerCubixTaskLock.acquire(db,"new",now+51min)
      verifyEq(taken["enerCubixPreviousJob"],Ref("old-job"))
      verify(!EnerCubixTaskLock.release(db,"old"))
      verifyErr(EnerCubixHttpErr#) { EnerCubixTaskLock.heartbeat(db,"old",null,now+52min) }
      verify(EnerCubixTaskLock.release(db,"new"))
    }
  }

  Void testAcquireUsesFolioCompareAndSwap()
  {
    withDb |db|
    {
      now:=DateTime.now
      a:=EnerCubixTaskLock.acquisition(null,"a",now)
      b:=EnerCubixTaskLock.acquisition(null,"b",now)
      db.commit(a)
      try { db.commit(b); fail("Two initial lock owners were accepted") }
      catch (Err e) { verifyEq(e.typeof.name,"CommitErr"); verifyEq(db.readById(EnerCubixTaskLock.key)["enerCubixOwner"],"a") }
      prior:=db.readById(EnerCubixTaskLock.key)
      first:=EnerCubixTaskLock.acquisition(prior,"c",now+31min)
      second:=EnerCubixTaskLock.acquisition(prior,"d",now+31min)
      db.commit(first)
      try { db.commit(second); fail("A stale lock revision was accepted") }
      catch (Err e) { verifyEq(e.typeof.name,"ConcurrentChangeErr") }
    }
  }

  private Void withDb(|Folio| work)
  {
    dir:=Env.cur.tempDir+`enerCubix-job-test-${Uuid()}/`; dir.create
    db:=(Folio)Type.find("hxFolio::HxFolio").method("open").call(FolioConfig { name="enerCubixJobsTest";it.dir=dir;log=Log.get("enerCubixJobsTest") })
    try { work(db) }
    finally
    {
      db.close
      if (dir.parent.normalize == Env.cur.tempDir.normalize) dir.delete
    }
  }
}

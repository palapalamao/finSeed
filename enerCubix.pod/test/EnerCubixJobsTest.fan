using util
using haystack
using folio

class EnerCubixJobsTest : Test
{
  Void testHistoricalDerivedIdentityIsReused()
  {
    withDb |db|
    {
      s:=series
      historical:=Ref("historic-derived-"+EnerCubixJobs.derivedId(s).split('-').last)
      point:=db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"kind":"Number","unit":"kWh","tz":"UTC","hisMode":"consumption","enerCubixComputed":Marker.val,"enerCubixResultKey":s["id"],"enerCubixResultCategory":s["categoryId"]]),historical)).newRec
      verifyEq(EnerCubixJobs.findDerived(db,s).id,historical)
      EnerCubixJobs.checkOwned(point,s)
      verifyNull(db.readById(Ref(EnerCubixJobs.derivedId(s)),false))
    }
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

  Void testDerivedOwnershipUnitsAndTimestampOverwrite()
  {
    withDb |db|
    {
      s:=series
      id:=EnerCubixJobs.derivedId(s)
      point:=db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"kind":"Number","unit":"kWh","tz":"UTC","hisMode":"consumption","enerCubixComputed":Marker.val,"enerCubixResultKey":"g|electric","enerCubixResultCategory":"electric"]),Ref(id))).newRec
      EnerCubixJobs.checkOwned(point,s)
      original:=Etc.makeDict(["id":Ref("original"),"point":Marker.val,"his":Marker.val,"unit":"kWh"])
      verifyErr(ArgErr#) { EnerCubixJobs.checkOwned(original,s) }
      items:=EnerCubixJobs.historyItems(s,TimeZone.utc)
      verifyEq(items[0].ts,DateTime.fromIso("2026-01-01T01:00:00Z"))
      verifyEq(((Number)items[0].val).unit,Unit("kWh"))
      db.his.write(point.id,items,null).get
      (([Str:Obj?][])s["points"])[0]["value"]=null
      db.his.write(point.id,EnerCubixJobs.historyItems(s,TimeZone.utc),null).get
      read:=HisItem[,]
      db.his.read(point.id,null,null) |item| { read.add(item) }
      verifyEq(read.size,1); verifyEq(read[0].val,NA.val)
    }
  }

  Void testQualityEvidenceIsBoundedAndComplete()
  {
    s:=series; points:=[Str:Obj?][,]; start:=DateTime.fromIso("2026-01-01T00:00:00Z")
    (0..<1440).each |i| { points.add(["ts":(start+Duration(i*1hr.ticks)).toIso,"value":null,"quality":"missingTariffBaseline"]) }
    s["points"]=points
    chunks:=EnerCubixJobs.qualityEvidence(s,"derivedPoint","jobId")
    verify(chunks.size > 2)
    total:=0
    chunks.each |chunk|
    {
      verify(JsonOutStream.writeJsonToStr(chunk).size < 30000)
      total+=((Map)chunk["quality"]).size
      verifyEq(chunk["parentJobId"],"jobId")
    }
    verifyEq(total,1440)
    verify(chunks[0]["name"] != EnerCubixJobs.qualityEvidence(s,"derivedPoint","anotherJob")[0]["name"])
  }

  private [Str:Obj?] series()
  { ["id":"g|electric","name":"Group","categoryId":"electric","unit":"kWh","points":[[Str:Obj?]["ts":"2026-01-01T00:00:00Z","value":10f,"quality":"ok"]]] }

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

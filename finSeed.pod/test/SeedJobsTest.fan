using util
using haystack
using folio

class SeedJobsTest : Test
{
  Void testOneOwnerAndFailureReleases()
  {
    withDb |db|
    {
      now:=DateTime.now
      SeedTaskLock.acquire(db,"first",now)
      verifyErr(SeedHttpErr#) { SeedTaskLock.acquire(db,"second",now+1min) }
      verify(!SeedTaskLock.release(db,"second"))
      verify(SeedTaskLock.release(db,"first"))
      verifyErr(ArgErr#) { SeedTaskLock.withLock(db,"failing") |held->Obj?| { throw ArgErr("expected failure") } }
      SeedTaskLock.acquire(db,"afterFailure")
      verify(SeedTaskLock.release(db,"afterFailure"))
    }
  }

  Void testLeaseHeartbeatTakeoverAndOwnerSafeRelease()
  {
    withDb |db|
    {
      now:=DateTime.now
      SeedTaskLock.acquire(db,"old",now)
      SeedTaskLock.heartbeat(db,"old",Ref("old-job"),now+20min)
      verifyErr(SeedHttpErr#) { SeedTaskLock.acquire(db,"new",now+40min) }
      taken:=SeedTaskLock.acquire(db,"new",now+51min)
      verifyEq(taken["seedPreviousJob"],Ref("old-job"))
      verify(!SeedTaskLock.release(db,"old"))
      verifyErr(SeedHttpErr#) { SeedTaskLock.heartbeat(db,"old",null,now+52min) }
      verify(SeedTaskLock.release(db,"new"))
    }
  }

  Void testAcquireUsesFolioCompareAndSwap()
  {
    withDb |db|
    {
      now:=DateTime.now
      a:=SeedTaskLock.acquisition(null,"a",now)
      b:=SeedTaskLock.acquisition(null,"b",now)
      db.commit(a)
      try { db.commit(b); fail("Two initial lock owners were accepted") }
      catch (Err e) { verifyEq(e.typeof.name,"CommitErr"); verifyEq(db.readById(SeedTaskLock.key)["seedOwner"],"a") }
      prior:=db.readById(SeedTaskLock.key)
      first:=SeedTaskLock.acquisition(prior,"c",now+31min)
      second:=SeedTaskLock.acquisition(prior,"d",now+31min)
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
      id:=SeedJobs.derivedId(s)
      point:=db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"kind":"Number","unit":"kWh","tz":"UTC","hisMode":"consumption","seedComputed":Marker.val,"seedResultKey":"g|electric","seedResultCategory":"electric"]),Ref(id))).newRec
      SeedJobs.checkOwned(point,s)
      original:=Etc.makeDict(["id":Ref("original"),"point":Marker.val,"his":Marker.val,"unit":"kWh"])
      verifyErr(ArgErr#) { SeedJobs.checkOwned(original,s) }
      items:=SeedJobs.historyItems(s,TimeZone.utc)
      verifyEq(items[0].ts,DateTime.fromIso("2026-01-01T01:00:00Z"))
      verifyEq(((Number)items[0].val).unit,Unit("kWh"))
      db.his.write(point.id,items,null).get
      (([Str:Obj?][])s["points"])[0]["value"]=null
      db.his.write(point.id,SeedJobs.historyItems(s,TimeZone.utc),null).get
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
    chunks:=SeedJobs.qualityEvidence(s,"derivedPoint","jobId")
    verify(chunks.size > 2)
    total:=0
    chunks.each |chunk|
    {
      verify(JsonOutStream.writeJsonToStr(chunk).size < 30000)
      total+=((Map)chunk["quality"]).size
      verifyEq(chunk["parentJobId"],"jobId")
    }
    verifyEq(total,1440)
    verify(chunks[0]["name"] != SeedJobs.qualityEvidence(s,"derivedPoint","anotherJob")[0]["name"])
  }

  private [Str:Obj?] series()
  { ["id":"g|electric","name":"Group","categoryId":"electric","unit":"kWh","points":[[Str:Obj?]["ts":"2026-01-01T00:00:00Z","value":10f,"quality":"ok"]]] }

  private Void withDb(|Folio| work)
  {
    dir:=Env.cur.tempDir+`finseed-job-test-${Uuid()}/`; dir.create
    db:=(Folio)Type.find("hxFolio::HxFolio").method("open").call(FolioConfig { name="seedJobsTest";it.dir=dir;log=Log.get("seedJobsTest") })
    try { work(db) }
    finally
    {
      db.close
      if (dir.parent.normalize == Env.cur.tempDir.normalize) dir.delete
    }
  }
}

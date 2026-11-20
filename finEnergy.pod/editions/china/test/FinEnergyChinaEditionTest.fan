using haystack
using folio
using folio3
using util
using concurrent
using [java] java.util.concurrent::CountDownLatch
using [java] java.util.concurrent::TimeUnit

class FinEnergyChinaEditionTest : Test
{
  Void testLegacyGrantPathAndTrialStatusPermissions()
  {
    folder:=Env.cur.tempDir+("finEnergy-cn-grant-"+Uuid()+"/").toUri
    store:=FinEnergyLicenseStore(folder,Str:Str[:])
    verifyEq(store.path,folder+`enerCubix/license.json`)
    ordinary:=store.status("test-host",10,false,false)
    verifyEq(ordinary["status"],"trial");verifyEq(ordinary["limit"],10)
    verifyEq(ordinary["canImport"],false);verifyEq(ordinary["canDelete"],false)
    verify(!ordinary.containsKey("hostId"));verify(!ordinary.containsKey("deleteToken"))
    administrator:=store.status("test-host",11,true,false)
    verifyEq(administrator["hostId"],"test-host");verifyEq(administrator["overLimit"],true)
    verifyEq(administrator["canImport"],false)
    verifyEq(FinEnergyEditionLicense.calculationReason,"licenseProjectOverLimit")
  }

  Void testProjectLocalReferencesCannotConsumeAnExtraAliasSlot()
  {
    fixture |db|
    {
      10.times |i| {db.commit(Diff.makeAdd(meter(i),Ref("m"+i)))}
      verifyEq(FinEnergyLicenseQuota.used(db),10)
      alias:=Etc.makeDict(["equip":Marker.val,"finEnergyKind":"meter","finEnergyCategoryRef":Ref("electricity"),
        "finEnergyPointRef":Ref("point0"),"finEnergyCanonicalRef":Ref("m0")])
      db.commit(Diff.makeAdd(alias,Ref("alias")))
      verifyEq(FinEnergyLicenseQuota.used(db),10)
      all:=db.readAllList(Filter.has("finEnergyKind"))
      invalid:=Etc.makeDict(["equip":Marker.val,"finEnergyKind":"meter","finEnergyCategoryRef":Ref("electricity"),
        "finEnergyPointRef":Ref("different-point"),"finEnergyCanonicalRef":Ref("m0")])
      verifyErr(FinEnergyHttpErr#) {FinEnergyLicenseQuota.check(all,false,[Diff.makeAdd(invalid,Ref("invalid-alias"))])}
    }
  }

  Void testWaterElectricityVirtualAndPhysicalShareFinalStateQuota()
  {
    current:=Dict[,]
    10.times |i| {tags:=Etc.dictToMap(meter(i));tags["id"]=Ref("m"+i);tags["mod"]=DateTime.now;current.add(Etc.makeDict(tags))}
    verifyEq(FinEnergyLicenseQuota.count(current,false),10)
    extra:=Diff.makeAdd(meter(10),Ref("m10"))
    verifyErr(FinEnergyHttpErr#) {FinEnergyLicenseQuota.check(current,false,[extra])}
    // A single transaction that releases one and adds one ends at ten.
    FinEnergyLicenseQuota.check(current,false,[Diff(current.first,null,Diff.remove),extra])
    over:=current.dup.add(Etc.makeDict(["id":Ref("m10"),"mod":DateTime.now,"equip":Marker.val,"finEnergyKind":"totalMeter"]))
    // Recovery and unrelated configuration edits remain possible over quota.
    FinEnergyLicenseQuota.check(over,false,[Diff(over.first,Etc.makeDict(["finEnergyKind":Remove.val]))])
    FinEnergyLicenseQuota.check(over,false,[Diff(over.first,Etc.makeDict(["dis":"renamed"]))])
    verifyErr(FinEnergyHttpErr#) {FinEnergyLicenseQuota.check(over,false,[Diff.makeAdd(meter(11),Ref("m11"))])}
    // Excluding a meter from totals must not exclude it from licensing.
    ignored:=current.map |r->Dict| {Etc.makeDict(Etc.dictToMap(r).set("finEnergyIncluded",false))}
    verifyEq(FinEnergyLicenseQuota.count(ignored,false),10)
  }

  Void testOnlyMeterAffectingEventsNeedQuotaRevision()
  {
    fixture |db|
    {
      prior:=db.commit(Diff.makeAdd(meter(0),Ref("m0"))).newRec
      verify(FinEnergyLicenseQuota.requiresRevision(db,[Diff(prior,Etc.makeDict(["finEnergyKind":Remove.val]))]))
      verify(FinEnergyLicenseQuota.requiresRevision(db,[Diff.makeAdd(meter(1),Ref("m1"))]))
      verify(!FinEnergyLicenseQuota.requiresRevision(db,[Diff.makeAdd(Etc.makeDict(["finEnergyKind":"alarm"]),Ref("alarm"))]))
      verify(!FinEnergyLicenseQuota.requiresRevision(db,[Diff.makeAdd(Etc.makeDict(["finEnergyKind":"job"]),Ref("job"))]))
    }
  }

  Void testConcurrentTenthEnrollmentUsesOneConfigurationRevision()
  {
    fixture |db|
    {
      9.times |i| {db.commit(Diff.makeAdd(meter(i),Ref("m"+i)))}
      db.commit(Diff.makeAdd(Etc.makeDict(["finEnergyRevision":Number(1)]),Ref("revision")))
      pool:=ActorPool();ready:=CountDownLatch(2);start:=CountDownLatch(1)
      try
      {
        first:=Actor(pool,|Obj? msg->Obj?| {enroll(msg)}).send(Unsafe([db,"tenth-a",ready,start]))
        second:=Actor(pool,|Obj? msg->Obj?| {enroll(msg)}).send(Unsafe([db,"tenth-b",ready,start]))
        verify(ready.await(10,TimeUnit.SECONDS));start.countDown
        verifyEq([first.get(15sec).toStr,second.get(15sec).toStr].sort,["conflict","ok"])
        verifyEq(FinEnergyLicenseQuota.used(db),10)
        verifyErr(FinEnergyHttpErr#) {FinEnergyLicenseQuota.check(db.readAllList(Filter.has("finEnergyKind")),false,[Diff.makeAdd(meter(11),Ref("eleventh"))])}
      }
      finally {start.countDown;pool.stop;pool.join(20sec)}
    }
  }

  Void testManagedVerificationResourceContainsPublicKeysOnly()
  {
    resource:=FinEnergyLicenseStore#.pod.file(`/res/license-keys.json`,false)
    verifyNotNull(resource)
    text:=resource.readAllStr
    verify(!text.contains("PRIVATE KEY"))
    keys:=(Map)JsonInStream(text.in).readJson
    verify(!keys.isEmpty)
    keys.each |value,key| {verify(key is Str);verify(value is Str);verify(!Buf.fromBase64(value.toStr).isEmpty)}
  }

  Void testSeparateProjectsEachKeepTenFreeMeters()
  {
    fixture |first|
    {
      fixture |second|
      {
        10.times |i|
        {
          first.commit(Diff.makeAdd(meter(i),Ref("m"+i)))
          second.commit(Diff.makeAdd(meter(i),Ref("m"+i)))
        }
        verifyEq(FinEnergyLicenseQuota.used(first),10)
        verifyEq(FinEnergyLicenseQuota.used(second),10)
        verifyErr(FinEnergyHttpErr#) {FinEnergyLicenseQuota.check(first.readAllList(Filter.has("finEnergyKind")),false,[Diff.makeAdd(meter(10),Ref("m10"))])}
        verifyEq(FinEnergyLicenseQuota.used(second),10)
      }
    }
  }

  private static Obj? enroll(Obj? msg)
  {
    args:=(List)((Unsafe)msg).val;db:=(Folio)args[0]
    revision:=db.readById(Ref("revision"));current:=db.readAllList(Filter.has("finEnergyKind"))
    ready:=(CountDownLatch)args[2];start:=(CountDownLatch)args[3]
    ready.countDown;start.await
    change:=Diff.makeAdd(meter(10),Ref(args[1].toStr))
    FinEnergyLicenseQuota.check(current,false,[change])
    try {db.commitAll([change,Diff(revision,Etc.makeDict(["finEnergyRevision":Number(2)]))]);return "ok"}
    catch (Err e)
    {
      if (["ConcurrentChangeErr","DuplicateRecErr"].contains(e.typeof.name)) return "conflict"
      throw e
    }
  }

  private static Dict meter(Int i)
  { Etc.makeDict(["equip":Marker.val,"finEnergyKind":i%3==0 ? "totalMeter" : "meter",
      "finEnergyCategoryRef":Ref(i%2==0 ? "electricity" : "water"),"finEnergyPointRef":Ref("point"+i)]) }
  private Void fixture(|Folio| body)
  {
    home:=Env.cur.tempDir+("finEnergy-cn-quota-"+Uuid()+"/").toUri
    db:=Folio3.open(FolioConfig {it.dir=home;it.idPrefix="p:test:r:"})
    try {body(db)} finally {db.close}
  }
}

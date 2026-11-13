using util
using haystack
using folio
using [java] java.security::KeyPairGenerator
using [java] java.security::KeyPair
using [java] java.security::Signature
using [java] java.time::Instant
using [java] fanx.interop::Interop

class EnerCubixLicenseTest : Test
{
  private Instant now() { Instant.parse("2026-11-13T10:00:00Z") }

  Void testSignedHostAndTrainingScope()
  {
    keys := keyPair
    host := EnerCubixLicenseGrant.verify(file(keys, "host", "HID-example"), keyring(keys))
    verifyEq(host.state("HID-example", now), "active")
    verifyEq(host.state("HID-other", now), "invalid")
    verifyEq(host.state(null, now), "hostUnavailable")
    verifyEq(host.state("HID-example", now.minusSeconds(1)), "notYetValid")
    verifyEq(host.state("HID-example", now.plusSeconds(86400)), "expired")

    training := EnerCubixLicenseGrant.verify(file(keys, "training"), keyring(keys))
    verifyEq(training.state("HID-other", now), "active")
    verifyEq(training.state(null, now), "active")
    verifyEq(training.state(null, now.plusSeconds(86400)), "expired")
    verifyErr(EnerCubixHttpErr#) { EnerCubixLicenseGrant.verify(file(keys,"training"),["other":keyring(keys)["test"]]) }
    altered:=(Str:Obj?)JsonInStream(file(keys,"training").in).readJson
    altered["payload"]=JsonOutStream.writeJsonToStr(["type":"training"]).toBuf.toBase64
    verifyErr(EnerCubixHttpErr#) { EnerCubixLicenseGrant.verify(JsonOutStream.writeJsonToStr(altered),keyring(keys)) }
    verifyErr(EnerCubixHttpErr#) { EnerCubixLicenseGrant.verify(file(keys,"training","HID-example"),keyring(keys)) }
    verifyErr(EnerCubixHttpErr#) { EnerCubixLicenseGrant.verify(file(keys,"host"),keyring(keys)) }
  }

  Void testImportPreservesExistingLicense()
  {
    keys := keyPair
    ring := keyring(keys)
    // A test-specific instance directory avoids any live FIN license state.
    directory := Env.cur.tempDir + ("enerCubix-license-"+Uuid().toStr+"/").toUri
    try
    {
      store := EnerCubixLicenseStore(directory,ring)
      original := file(keys,"host","HID-example")
      verifyEq(store.status("HID-example",11,true,true,now)["overLimit"],true)
      verifyEq(store.install(original,"HID-example",now).licenseType,"host")
      verifyEq(store.status("HID-example",11,true,true,now)["limit"],null)
      verifyEq(store.status("HID-example",11,false,false,now)["hostId"],null)
      verifyErr(EnerCubixHttpErr#) { store.install(file(keys,"host","HID-other"),"HID-example",now) }
      verifyErr(EnerCubixHttpErr#) { store.install("{}", "HID-example", now) }
      verifyErr(EnerCubixHttpErr#) { store.install(original,"HID-example",now.minusSeconds(1)) }
      verifyErr(EnerCubixHttpErr#) { store.install(original,"HID-example",now.plusSeconds(86400)) }
      verifyEq(store.path.readAllStr,original)
      replacement := file(keys,"training")
      store.install(replacement,null,now)
      reloaded := EnerCubixLicenseStore(directory,ring)
      verifyEq(reloaded.path.readAllStr,replacement)
      verifyEq(reloaded.status(null,11,true,true,now)["licenseType"],"training")
      verifyEq(reloaded.status(null,11,true,true,now.plusSeconds(86400))["overLimit"],true)
    }
    finally { if(directory.exists)directory.delete }
  }

  Void testTrialQuotaUsesFinalProjectState()
  {
    rows:=Dict[,]
    (0..<10).each |i| { rows.add(meter("m"+i)) }
    rows.add(meter("reference","sensor"))
    rows.add(meter("alias","totalMeter","m0","point-m0"))
    verifyEq(EnerCubixLicenseQuota.count(rows,false),10)
    legacy:=Etc.makeDict(["id":Ref("legacy"),"dis":"Old meter","enerCubix":Marker.val,"enerCubixKind":"meter"])
    verifyEq(EnerCubixLicenseQuota.count(rows.dup.add(legacy),false),11)
    verifyEq(EnerCubixLicenseQuota.count(rows.dup.add(legacy),true),10)
    model:=Etc.makeDict(["id":Ref("p:cubeTest:r:enerCubix-native-equip-model"),"mod":DateTime.now,
      "enerCubixStorageModel":"nativeEquip"])
    rollback:=Diff(model,null,Diff.remove)
    verifyErr(EnerCubixHttpErr#) { EnerCubixLicenseQuota.check(rows.dup.add(legacy),true,[rollback],model.id) }
    unrelated:=Diff.makeAdd(Etc.makeDict(["point":Marker.val]),Ref("new-point"))
    extra:=Diff.makeAdd(Etc.makeDict(["equip":Marker.val,"enerCubixKind":"meter"]),Ref("m10"))
    verifyErr(EnerCubixHttpErr#) { EnerCubixLicenseQuota.check(rows,false,[unrelated,extra]) }
    EnerCubixLicenseQuota.check(rows,false,[unrelated,Diff(rows.first,Etc.makeDict(["enerCubixIncludeInTotals":false]))])
    badAlias:=Diff(rows.last,Etc.makeDict(["enerCubixPointRef":Ref("different-point")]))
    verifyErr(EnerCubixHttpErr#) { EnerCubixLicenseQuota.check(rows,false,[badAlias]) }
    rows.add(meter("over"))
    EnerCubixLicenseQuota.check(rows,false,[Diff(rows.last,Etc.makeDict(["enerCubixKind":Remove.val]))])
    verifyErr(EnerCubixHttpErr#) { EnerCubixLicenseQuota.check(rows,false,[extra]) }
  }

  Void testDeleteRequiresCurrentInstalledFile()
  {
    keys := keyPair
    directory := Env.cur.tempDir + ("enerCubix-license-delete-"+Uuid().toStr+"/").toUri
    try
    {
      store := EnerCubixLicenseStore(directory,keyring(keys),true)
      original := file(keys,"host","HID-example")
      store.install(original,"HID-example",now)
      verify(store.active("HID-example",now))
      administrator := store.status("HID-example",11,true,false,now)
      verifyEq(administrator["canDelete"],false)
      verifyEq(administrator["deleteToken"],null)
      first := store.status("HID-example",11,true,true,now)
      verifyEq(first["canDelete"],true)
      replacement := file(keys,"training")
      store.install(replacement,"HID-example",now)
      verifyErr(EnerCubixHttpErr#) { store.remove(first["deleteToken"] as Str) }
      verifyEq(store.path.readAllStr,replacement)

      expired := store.status("HID-example",11,true,true,now.plusSeconds(86400))
      verifyEq(expired["status"],"expired")
      store.remove(expired["deleteToken"] as Str)
      verifyFalse(store.path.exists)
      verifyFalse(store.active("HID-example",now))
      trial := store.status("HID-example",11,true,true,now)
      verifyEq(trial["status"],"trial")
      verifyEq(trial["limit"],10)
      verifyEq(trial["overLimit"],true)
      verifyEq(trial["canDelete"],false)
      verifyErr(EnerCubixHttpErr#) { store.remove(expired["deleteToken"] as Str) }

      store.path.out.writeChars("invalid license").close
      invalid := store.status("HID-example",11,true,true,now)
      verifyEq(invalid["status"],"invalid")
      verifyEq(invalid["canDelete"],true)
      store.remove(invalid["deleteToken"] as Str)
      verifyFalse(store.path.exists)
    }
    finally { if(directory.exists) directory.delete }
  }

  Void testSignedFarFutureExpiry()
  {
    keys := keyPair
    ring := keyring(keys)
    expiry := "2106-11-13T10:00:00.123456789Z"
    raw := file(keys,"host","HID-example",now.toString,expiry)
    grant := EnerCubixLicenseGrant.verify(raw,ring)
    verifyEq(grant.state("HID-example",now),"active")
    directory := Env.cur.tempDir + ("enerCubix-license-future-"+Uuid().toStr+"/").toUri
    try
    {
      store := EnerCubixLicenseStore(directory,ring)
      store.install(raw,"HID-example",now)
      verifyEq(store.status("HID-example",11,true,true,now)["expiresAt"],expiry)
    }
    finally { if(directory.exists) directory.delete }
    boundary := EnerCubixLicenseGrant.verify(file(keys,"training",null,"2099-12-31T23:59:59Z","2100-01-01T00:00:00Z"),ring)
    verifyEq(boundary.state(null,Instant.parse("2099-12-31T23:59:58Z")),"notYetValid")
    verifyEq(boundary.state(null,Instant.parse("2099-12-31T23:59:59Z")),"active")
    verifyEq(boundary.state(null,Instant.parse("2100-01-01T00:00:00Z")),"expired")
    verifyEq(grant.state("HID-example",Instant.parse(expiry).minusNanos(1)),"active")
    verifyEq(grant.state("HID-example",Instant.parse(expiry)),"expired")
  }

  Void testSignedInvalidUtcDatesAreReportedSeparately()
  {
    keys := keyPair
    ring := keyring(keys)
    ["2100-02-29T10:00:00Z","2106-11-13T24:00:00Z","2106-11-13T10:00:60Z",now.toString].each |expiry|
    {
      verifyErrMsg(EnerCubixHttpErr#,"licenseInvalidPeriod")
        { EnerCubixLicenseGrant.verify(file(keys,"training",null,now.toString,expiry),ring) }
    }
  }

  private static Dict meter(Str id, Str kind:="meter", Str? alias:=null, Str? point:=null)
  {
    tags:=Str:Obj?["id":Ref(id),"mod":DateTime.now,"equip":Marker.val,"enerCubix":Marker.val,"enerCubixKind":kind,
                   "enerCubixCategoryRef":Ref("electric"),"enerCubixPointRef":Ref(point ?: "point-"+id)]
    if(alias!=null)tags["enerCubixCanonicalRef"]=Ref(alias)
    return Etc.makeDict(tags)
  }

  private static KeyPair keyPair()
  {
    generator := KeyPairGenerator.getInstance("RSA")
    generator.initialize(3072)
    return generator.generateKeyPair
  }

  private static Str:Str keyring(KeyPair keys)
  {
    der := keys.getPublic.getEncoded
    buf := Buf(der.size)
    der.size.times |i| { buf.write(der.get(i)) }
    return ["test":buf.toBase64]
  }

  private Str file(KeyPair keys, Str licenseType, Str? hostId:=null, Str notBefore:=now.toString, Str expiresAt:=now.plusSeconds(86400).toString)
  {
    data:=Str:Obj?["version":1,"product":"enerCubix","type":licenseType,"licenseId":Uuid().toStr,
      "issuedAt":now.toString,"notBefore":notBefore,"expiresAt":expiresAt]
    if(hostId!=null)data["hostId"]=hostId
    payload:=JsonOutStream.writeJsonToStr(data).toBuf
    signing:=Signature.getInstance("SHA256withRSA")
    signing.initSign(keys.getPrivate)
    signing.update(Interop.toJava(payload.trim).array)
    signature:=signing.sign
    buf:=Buf(signature.size)
    signature.size.times |i| { buf.write(signature.get(i)) }
    return JsonOutStream.writeJsonToStr(["keyId":"test","payload":payload.toBase64,"signature":buf.toBase64])
  }
}

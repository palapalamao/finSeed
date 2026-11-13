using util
using concurrent
using skyarcd
using [java] java.io::FileInputStream
using [java] java.nio.file::CopyOption
using [java] java.nio.file::Files
using [java] java.nio.file::StandardCopyOption
using [java] java.security::MessageDigest
using [java] java.util.concurrent.locks::ReentrantLock
using [java] fanx.interop::ByteArray
using [java] fanx.interop::Interop

** One license file per FIN instance. No application project owns the grant.
internal class EnerCubixLicenseStore
{
  private static const Unsafe fileLock := Unsafe(ReentrantLock())
  private static const AtomicRef runtimeCache := AtomicRef()
  private static const Str:Str bundledKeys := loadKeyring
  private static const Regex deleteTokenPattern := Regex<|[0-9a-f]{64}|>
  private const Str:Str keys
  private const Bool runtime
  const File path

  new make(File instanceDir, Str:Str keys, Bool runtime := false)
  {
    this.keys=keys.toImmutable
    this.runtime=runtime
    this.path=instanceDir + `enerCubix/license.json`
  }

  static new forSys(Sys sys) { make(sys.varDir,bundledKeys,true) }

  static Str? hostId(Sys sys)
  {
    try { return sys.host.hostId.toStr.trimToNull }
    catch (Err ignored) { return null }
  }

  Bool active(Str? host, DateTime now := DateTime.now)
  { read.grant?.state(host,now) == "active" }

  [Str:Obj?] status(Str? host, Int used, Bool canViewHost, Bool canImport, DateTime now := DateTime.now)
  {
    saved := read(canImport)
    grant := saved.grant
    fallback := host == null ? "hostUnavailable" : "trial"
    if (saved.exists) fallback="invalid"
    state := grant?.state(host,now) ?: fallback
    out := Str:Obj?["status":state,"used":used,"limit":state=="active" ? null : EnerCubixLicenseQuota.trialLimit,
      "overLimit":state!="active" && used>EnerCubixLicenseQuota.trialLimit,"canImport":canImport,
      "canDelete":canImport && saved.deleteToken!=null]
    if (canImport && saved.deleteToken != null) out["deleteToken"]=saved.deleteToken
    if (canViewHost && host != null) out["hostId"]=host
    if (grant != null)
    {
      out["licenseType"]=grant.licenseType
      out["licenseId"]=grant.licenseId
      out["notBefore"]=grant.notBefore.toUtc.toIso
      out["expiresAt"]=grant.expiresAt.toUtc.toIso
    }
    return out
  }

  EnerCubixLicenseGrant install(Str raw, Str? host, DateTime now := DateTime.now)
  {
    lock := (ReentrantLock)fileLock.val
    lock.lock
    try
    {
      grant := EnerCubixLicenseGrant.verify(raw,keys)
      switch (grant.state(host,now))
      {
        case "hostUnavailable": throw EnerCubixHttpErr(400,"LICENSE_HOST_UNAVAILABLE","licenseHostUnavailable")
        case "invalid": throw EnerCubixHttpErr(400,"LICENSE_HOST_MISMATCH","licenseHostMismatch")
        case "notYetValid": throw EnerCubixHttpErr(400,"LICENSE_NOT_YET_VALID","licenseNotYetValid")
        case "expired": throw EnerCubixHttpErr(400,"LICENSE_EXPIRED","licenseExpired")
      }
      save(raw)
      if (runtime) runtimeCache.val=null
      return grant
    }
    finally { lock.unlock }
  }

  Void remove(Str? expected)
  {
    if (expected==null || !deleteTokenPattern.matches(expected)) throw EnerCubixLicenseGrant.invalid
    lock := (ReentrantLock)fileLock.val
    lock.lock
    try
    {
      try
      {
        if (!path.exists || fingerprint != expected || !Files.deleteIfExists(Interop.toJava(path).toPath))
          throw EnerCubixHttpErr(409,"LICENSE_CHANGED","licenseChanged")
      }
      catch (EnerCubixHttpErr e) { throw e }
      catch (Err ignored) { throw EnerCubixHttpErr(503,"LICENSE_STORE","licenseStoreFailed") }
      if (runtime) runtimeCache.val=null
    }
    finally { lock.unlock }
  }

  private Str fingerprint()
  {
    // Include every byte, including files too large or malformed to verify.
    digest := MessageDigest.getInstance("SHA-256")
    chunk := ByteArray.make(8192)
    input := FileInputStream(Interop.toJava(path))
    try
    {
      while (true)
      {
        count := input.read(chunk)
        if (count < 0) break
        digest.update(chunk,0,count)
      }
    }
    finally { input.close }
    bytes := digest.digest
    result := Buf(bytes.size)
    bytes.size.times |i| { result.write(bytes.get(i)) }
    return result.toHex
  }

  private Void save(Str raw)
  {
    File? temp
    try
    {
      path.parent.create
      temp=File.createTemp("license-",".tmp",path.parent)
      out:=temp.out
      try { out.writeChars(raw).sync }
      finally { out.close }
      Files.move(Interop.toJava(temp).toPath,Interop.toJava(path).toPath,
        CopyOption[StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING])
    }
    catch (Err ignored) { throw EnerCubixHttpErr(503,"LICENSE_STORE","licenseStoreFailed") }
    finally
    {
      try { if (temp?.exists == true) temp.delete }
      catch (Err ignored) {}
    }
  }

  private EnerCubixLicenseCache read(Bool includeDeleteToken := false)
  {
    lock := (ReentrantLock)fileLock.val
    lock.lock
    try
    {
      if (!path.exists) return EnerCubixLicenseCache(path.uri,false,null,null,null)
      modified := path.modified
      size := path.size
      prior := runtime ? (runtimeCache.val as EnerCubixLicenseCache) : null
      if (!includeDeleteToken && prior != null && prior.path==path.uri && prior.modified==modified && prior.size==size) return prior
      Str? token
      if (includeDeleteToken && !path.isDir)
      {
        try { token=fingerprint }
        catch (Err ignored) {} // An unavailable deletion token does not invalidate the grant.
      }
      EnerCubixLicenseGrant? grant
      try
      {
        if (size != null && size <= EnerCubixLicenseGrant.maxBytes)
          grant=EnerCubixLicenseGrant.verify(path.readAllStr,keys)
      }
      catch (Err ignored) {}
      fresh:=EnerCubixLicenseCache(path.uri,true,modified,size,grant,token)
      if (runtime) runtimeCache.val=fresh
      return fresh
    }
    catch (Err ignored) { return EnerCubixLicenseCache(path.uri,true,null,null,null) }
    finally { lock.unlock }
  }

  private static Str:Str loadKeyring()
  {
    file := EnerCubixLicenseStore#.pod.file(`/res/license-keys.json`,false)
    if (file == null) return Str:Str[:].toImmutable
    keys := Str:Str[:]
    ((Map)JsonInStream(file.in).readJson).each |value,key| { keys[(Str)key]=(Str)value }
    return keys.toImmutable
  }
}

internal const class EnerCubixLicenseCache
{
  const Uri path
  const Bool exists
  const DateTime? modified
  const Int? size
  const EnerCubixLicenseGrant? grant
  const Str? deleteToken

  new make(Uri path, Bool exists, DateTime? modified, Int? size, EnerCubixLicenseGrant? grant, Str? deleteToken := null)
  { this.path=path; this.exists=exists; this.modified=modified; this.size=size; this.grant=grant; this.deleteToken=deleteToken }
}

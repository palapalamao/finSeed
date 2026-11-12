using util
using concurrent
using skyarcd
using [java] java.nio.file::CopyOption
using [java] java.nio.file::Files
using [java] java.nio.file::StandardCopyOption
using [java] java.util.concurrent.locks::ReentrantLock
using [java] fanx.interop::Interop

** One license file per FIN instance. No application project owns the grant.
internal class EnerCubixLicenseStore
{
  private static const Unsafe fileLock := Unsafe(ReentrantLock())
  private static const AtomicRef runtimeCache := AtomicRef()
  private static const Str:Str bundledKeys := loadKeyring
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
    saved := read
    grant := saved.grant
    fallback := host == null ? "hostUnavailable" : "trial"
    if (saved.exists) fallback="invalid"
    state := grant?.state(host,now) ?: fallback
    out := Str:Obj?["status":state,"used":used,"limit":state=="active" ? null : EnerCubixLicenseQuota.trialLimit,
      "overLimit":state!="active" && used>EnerCubixLicenseQuota.trialLimit,"canImport":canImport]
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

  private EnerCubixLicenseCache read()
  {
    lock := (ReentrantLock)fileLock.val
    lock.lock
    try
    {
      if (!path.exists) return EnerCubixLicenseCache(path.uri,false,null,null,null)
      modified := path.modified
      size := path.size
      prior := runtime ? (runtimeCache.val as EnerCubixLicenseCache) : null
      if (prior != null && prior.path==path.uri && prior.modified==modified && prior.size==size) return prior
      EnerCubixLicenseGrant? grant
      try
      {
        if (size != null && size <= EnerCubixLicenseGrant.maxBytes)
          grant=EnerCubixLicenseGrant.verify(path.readAllStr,keys)
      }
      catch (Err ignored) {}
      fresh:=EnerCubixLicenseCache(path.uri,true,modified,size,grant)
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

  new make(Uri path, Bool exists, DateTime? modified, Int? size, EnerCubixLicenseGrant? grant)
  { this.path=path; this.exists=exists; this.modified=modified; this.size=size; this.grant=grant }
}

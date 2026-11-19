using util
using [java] java.security::KeyFactory
using [java] java.security::Signature
using [java] java.security.interfaces::RSAPublicKey
using [java] java.security.spec::X509EncodedKeySpec
using [java] java.time::Instant
using [java] java.time::LocalDateTime
using [java] java.time::ZoneOffset
using [java] fanx.interop::Interop

** A signed grant. Its time window is checked against the FIN clock on each use.
internal const class FinEnergyLicenseGrant
{
  internal static const Int maxBytes := 16 * 1024
  private static const Regex uuid := Regex.fromStr("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
  private static const Regex utc := Regex.fromStr("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]{1,9})?Z")

  const Str licenseType
  const Str licenseId
  const Str? hostId
  const Str notBefore
  const Str expiresAt
  private const Int startSecond
  private const Int startNano
  private const Int endSecond
  private const Int endNano

  private new make(Str:Obj? payload)
  {
    if (payload["version"] != 1 || payload["product"] != "finEnergy") throw invalid
    licenseType = payload["type"] as Str ?: throw invalid
    licenseId = payload["licenseId"] as Str ?: throw invalid
    if (!uuid.matches(licenseId)) throw invalid
    hostId = payload["hostId"] as Str
    if (licenseType == "host")
    {
      if (hostId == null || hostId.isEmpty || hostId != hostId.trim) throw invalid
    }
    else if (licenseType != "training" || payload.containsKey("hostId")) throw invalid
    timestamp(payload["issuedAt"])
    start := timestamp(payload["notBefore"])
    end := timestamp(payload["expiresAt"])
    if (!start.isBefore(end)) throw invalidPeriod
    notBefore = start.toString
    expiresAt = end.toString
    startSecond = start.getEpochSecond
    startNano = start.getNano
    endSecond = end.getEpochSecond
    endNano = end.getNano
  }

  static FinEnergyLicenseGrant verify(Str raw, Str:Str keyring)
  {
    try
    {
      if (raw.toBuf.size > maxBytes) throw invalid
      envelope := (Str:Obj?) JsonInStream(raw.in).readJson
      keyId := envelope["keyId"] as Str ?: throw invalid
      der := Buf.fromBase64(keyring[keyId] ?: throw invalid)
      key := KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(Interop.toJava(der.trim).array)) as RSAPublicKey
      if (key == null || key.getModulus.bitLength != 3072) throw invalid
      payload := decode(envelope["payload"])
      signature := decode(envelope["signature"])
      if (signature.size != 384) throw invalid
      verifier := Signature.getInstance("SHA256withRSA")
      verifier.initVerify(key)
      verifier.update(Interop.toJava(payload.trim).array)
      if (!verifier.verify(Interop.toJava(signature.trim).array)) throw invalid
      return make((Str:Obj?) JsonInStream(payload.in).readJson)
    }
    catch (FinEnergyHttpErr e) { throw e }
    catch (Err ignored) { throw invalid }
  }

  Str state(Str? currentHost, Instant now)
  {
    if (licenseType == "host")
    {
      if (currentHost == null) return "hostUnavailable"
      if (hostId != currentHost) return "invalid"
    }
    if (compareTo(now,startSecond,startNano) < 0) return "notYetValid"
    if (compareTo(now,endSecond,endNano) >= 0) return "expired"
    return "active"
  }

  private static Int compareTo(Instant now, Int second, Int nano)
  {
    seconds := now.getEpochSecond <=> second
    return seconds == 0 ? now.getNano <=> nano : seconds
  }

  private static Instant timestamp(Obj? value)
  {
    raw := value as Str ?: throw invalidPeriod
    if (!utc.matches(raw)) throw invalidPeriod
    // FIN's Fantom DateTime stops at 2099. Parse UTC strictly without accepting leap-second or 24:00 normalization.
    try { return LocalDateTime.parse(raw[0..<-1]).toInstant(ZoneOffset.UTC) }
    catch (Err ignored) { throw invalidPeriod }
  }

  private static Buf decode(Obj? value)
  {
    raw := value as Str ?: throw invalid
    bytes:=Buf.fromBase64(raw)
    if (bytes.isEmpty || bytes.toBase64!=raw) throw invalid
    return bytes
  }

  internal static FinEnergyHttpErr invalid()
  { FinEnergyHttpErr(400,"LICENSE_INVALID","licenseInvalid") }

  private static FinEnergyHttpErr invalidPeriod()
  { FinEnergyHttpErr(400,"LICENSE_INVALID_PERIOD","licenseInvalidPeriod") }
}

using util
using [java] java.security::KeyFactory
using [java] java.security::Signature
using [java] java.security.interfaces::RSAPublicKey
using [java] java.security.spec::X509EncodedKeySpec
using [java] fanx.interop::Interop

** A signed grant. Its time window is checked against the FIN clock on each use.
internal const class EnerCubixLicenseGrant
{
  internal static const Int maxBytes := 16 * 1024
  private static const Regex uuid := Regex.fromStr("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
  private static const Regex utc := Regex.fromStr("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]{1,9})?Z")

  const Str licenseType
  const Str licenseId
  const Str? hostId
  const DateTime notBefore
  const DateTime expiresAt

  private new make(Str:Obj? payload)
  {
    if (payload["version"] != 1 || payload["product"] != "enerCubix") throw invalid
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
    notBefore = timestamp(payload["notBefore"])
    expiresAt = timestamp(payload["expiresAt"])
    if (notBefore >= expiresAt) throw invalid
  }

  static EnerCubixLicenseGrant verify(Str raw, Str:Str keyring)
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
    catch (Err ignored) { throw invalid }
  }

  Str state(Str? currentHost, DateTime now)
  {
    if (licenseType == "host")
    {
      if (currentHost == null) return "hostUnavailable"
      if (hostId != currentHost) return "invalid"
    }
    if (now < notBefore) return "notYetValid"
    if (now >= expiresAt) return "expired"
    return "active"
  }

  private static DateTime timestamp(Obj? value)
  {
    raw := value as Str ?: throw invalid
    if (!utc.matches(raw)) throw invalid
    return DateTime.fromIso(raw)
  }

  private static Buf decode(Obj? value)
  {
    raw := value as Str ?: throw invalid
    bytes:=Buf.fromBase64(raw)
    if (bytes.isEmpty || bytes.toBase64!=raw) throw invalid
    return bytes
  }

  internal static EnerCubixHttpErr invalid()
  { EnerCubixHttpErr(400,"LICENSE_INVALID","licenseInvalid") }
}

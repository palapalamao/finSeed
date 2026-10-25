using haystack

** Current measurement source, independent of historical cleaning and balance quality.
const class EnerCubixMeterOrigin
{
  static [Str:Obj?][] decorate([Str:Obj?][] records, |Str->Dict?| point, |Ref->Dict?| connector)
  {
    return records.map |record->[Str:Obj?]|
    {
      if (record["kind"] != "totalMeter") return record
      canonical:=record["canonicalId"] == null ? null : records.find |r| { r["id"] == record["canonicalId"] }
      meter:=canonical ?: record
      id:=meter["pointId"] as Str
      source:=id == null || meter["autoSum"] == true || meter["expressionId"] != null ? null : point(id)
      out:=record.dup; out["meterOrigin"]=classify(meter,source,connector)
      return out
    }
  }

  static [Str:Obj?] classify([Str:Obj?] meter, Dict? point, |Ref->Dict?| connector)
  {
    if (meter["autoSum"] == true) return ["type":"virtual","reason":"submeterSum"]
    if (meter["expressionId"] is Str && !meter["expressionId"].toStr.isEmpty) return ["type":"virtual","reason":"expression"]
    source:=Str:Obj?["type":"unconfirmed","reason":"unconfirmed"]
    pointId:=meter["pointId"] as Str
    if (pointId == null || point == null || point.id.id != pointId) return source
    source["pointId"]=pointId
    // A connected point has both a protocol reference and a current-value path.
    // Equipment membership, history functions and online status are not evidence.
    tags:=Str[,]; point.each |value,tag| { if (tag.endsWith("ConnRef")) tags.add(tag) }
    tags.sort.each |tag|
    {
      if (source["type"] == "physical" || !tag.endsWith("ConnRef")) return
      protocol:=tag[0..<-7]
      ref:=point[tag] as Ref
      path:=point[protocol+"Cur"] as Str
      if (ref == null || path == null || path.trim.isEmpty) return
      conn:=connector(ref)
      if (conn == null || conn.id != ref || !conn.has(protocol+"Conn")) return
      source["type"]="physical"; source["reason"]="connector"
      source["connectorId"]=ref.id; source["protocol"]=protocol
    }
    return source
  }
}

** Detached request-local provenance. It retains configuration facts, never
** source histories, prepared cells, raw samples, or their enclosing maps.
internal class EnerCubixCockpitHistoryMeta
{
  new make(Str[] pointIds, DateTime effectiveEnd)
  {this.pointIds=(Str[])pointIds.toImmutable;this.effectiveEnd=effectiveEnd}

  private Str[] pointIds
  private DateTime effectiveEnd
  private [Str:Obj?][] refs := [,]
  private [Str:Obj?][] cleaning := [,]
  private [Str:Obj?][] limitations := [,]
  private Obj?[] streams := [,]
  private DateTime[] starts := [,]
  private DateTime[] ends := [,]
  private DateTime? lastObserved

  Void observe(Str:Obj? history)
  {
    refs.addAll((([Str:Obj?][])EnerCubixMath.maps(history["configRefs"]).toImmutable))
    profile:=history["cleaning"] as Map
    if(profile != null) cleaning.add((Str:Obj?)Str:Obj?["pointId":history["pointId"],"profileId":profile["profileId"],"profileVersion":profile["profileVersion"],"parameters":profile["parameters"]].toImmutable)
    if(history["historyConfigObservedFrom"] is Str) starts.add(DateTime.fromIso(history["historyConfigObservedFrom"].toStr))
    if(history["historyConfigObservedTo"] is Str) ends.add(DateTime.fromIso(history["historyConfigObservedTo"].toStr))
    streams.add(history["streaming"]?.toImmutable)
    if(history["limitation"] != null) limitations.add((Str:Obj?)Str:Obj?["pointId":history["pointId"],"reason":history["limitation"]].toImmutable)
    if(!pointIds.contains(history["pointId"])) return
    observed(history["sourceLastObservedAt"] as Str)
    rows:=EnerCubixMath.maps(history["rawSamples"] ?: history["samples"])
    rows.each |row| {observed(row["ts"]?.toStr)}
    if(rows.isEmpty) EnerCubixMath.maps(history["intervals"]).each |row| {observed(row["to"]?.toStr)}
  }

  private Void observed(Str? text)
  {
    at:=DateTime.fromIso(text ?: "",false)
    if(at != null && at <= effectiveEnd && (lastObserved == null || at > lastObserved)) lastObserved=at
  }

  Str:Obj? snapshot()
  {
    return (Str:Obj?)Str:Obj?["configRefs":refs,"appliedCleaning":cleaning.unique.sort |a,b| {a["pointId"].toStr <=> b["pointId"].toStr},
      "streaming":streams.unique,"historyLimitations":limitations,"sourceLastObservedAt":lastObserved?.toIso,
      "historyConfigObservedFrom":starts.isEmpty ? null : ((DateTime)starts.min).toIso,
      "historyConfigObservedTo":ends.isEmpty ? null : ((DateTime)ends.max).toIso].toImmutable
  }
}

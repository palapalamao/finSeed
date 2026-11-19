** Detached request-local provenance. It retains configuration facts, never
** source histories, prepared cells, raw samples, or their enclosing maps.
internal class FinEnergyCockpitHistoryMeta
{
  new make(Str[] pointIds, DateTime effectiveEnd,FinEnergyPreparedOwner? work := null,FinEnergyPreparedOwner? output := null)
  {
    if((work==null)!=(output==null) || (work!=null && work.budget!==output.budget)) throw ArgErr("cockpitHistoryMetadataOwner")
    this.work=work;this.output=output
    work?.hold(1+pointIds.size)
    this.pointIds=(Str[])pointIds.toImmutable;this.effectiveEnd=effectiveEnd
    work?.watch |->Void|
    {this.pointIds=null;refs.clear;cleaning.each |r| {r.clear};cleaning.clear;limitations.each |r| {r.clear};limitations.clear;streams.clear;starts.clear;ends.clear}
  }

  private Str[]? pointIds
  private FinEnergyPreparedOwner? work
  private FinEnergyPreparedOwner? output
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
    check
    withRows(history["configRefs"]) |sourceRefs|
    {
      work?.hold(sourceRefs.size)
      refs.addAll(work==null ? ([Str:Obj?][])sourceRefs.toImmutable : sourceRefs)
    }
    profile:=history["cleaning"] as Map
    if(profile != null)
    {work?.hold(6);row:=Str:Obj?["pointId":history["pointId"],"profileId":profile["profileId"],"profileVersion":profile["profileVersion"],"parameters":profile["parameters"]];cleaning.add(work==null ? (Str:Obj?)row.toImmutable : row)}
    if(history["historyConfigObservedFrom"] is Str) {work?.hold(1);starts.add(DateTime.fromIso(history["historyConfigObservedFrom"].toStr))}
    if(history["historyConfigObservedTo"] is Str) {work?.hold(1);ends.add(DateTime.fromIso(history["historyConfigObservedTo"].toStr))}
    work?.hold(1);streams.add(output==null ? history["streaming"]?.toImmutable : FinEnergyCockpitFreeze.value(history["streaming"],output))
    if(history["limitation"] != null)
    {work?.hold(4);row:=Str:Obj?["pointId":history["pointId"],"reason":history["limitation"]];limitations.add(work==null ? (Str:Obj?)row.toImmutable : row)}
    if(!pointIds.contains(history["pointId"])) return
    observed(history["sourceLastObservedAt"] as Str)
    raw:=history["rawSamples"] ?: history["samples"]
    withRows(raw) |rows|
    {
      rows.each |row| {observed(row["ts"]?.toStr)}
      if(rows.isEmpty) withRows(history["intervals"]) |intervals| {intervals.each |row| {observed(row["to"]?.toStr)}}
    }
  }

  ** Filtering/mapping vectors expire within one observation. Only retained
  ** reference/configuration rows above continue to charge this owner.
  private Void withRows(Obj? value,|[Str:Obj?][]| consume)
  {
    charge:=2+2*((value as List)?.size ?: 0);work?.hold(charge);[Str:Obj?][]? rows
    try {rows=FinEnergyMath.maps(value);consume(rows)}
    finally {rows?.clear;work?.release(charge)}
  }

  private Void observed(Str? text)
  {
    at:=DateTime.fromIso(text ?: "",false)
    if(at != null && at <= effectiveEnd && (lastObserved == null || at > lastObserved)) lastObserved=at
  }

  Str:Obj? snapshot()
  {
    check;work?.hold(10+cleaning.size+streams.size)
    data:=Str:Obj?["configRefs":refs,"appliedCleaning":cleaning.unique.sort |a,b| {a["pointId"].toStr <=> b["pointId"].toStr},
      "streaming":streams.unique,"historyLimitations":limitations,"sourceLastObservedAt":lastObserved?.toIso,
      "historyConfigObservedFrom":starts.isEmpty ? null : ((DateTime)starts.min).toIso,
      "historyConfigObservedTo":ends.isEmpty ? null : ((DateTime)ends.max).toIso]
    return output==null ? (Str:Obj?)data.toImmutable : (Str:Obj?)FinEnergyCockpitFreeze.value(data,output)
  }
  private Void check() {if(work!=null && work.entries==0) throw ArgErr("cockpitHistoryMetadataClosed");work?.budget?.deadline?.check}
}

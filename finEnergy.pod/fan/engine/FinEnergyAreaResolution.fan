** Typed, immutable serialization of an existing area result; no second calculation.
internal const class FinEnergyAreaResolution
{
  new make(Str:Obj? area, Str boundaryId)
  {
    status=area["quality"] as Str ?: "missingArea"
    areaM2=FinEnergyMath.num(area["value"])
    sources:=FinEnergyMath.maps(area["sources"])
    kinds:=sources.map |s->Str| {s["source"].toStr}.unique
    basis=kinds.isEmpty ? "unknown" : (kinds.size > 1 ? "mixed" : (kinds.first == "space" ? "nativeSpace" : "custom"))
    spaceRefs=sources.findAll |s| {s["source"] == "space"}.map |s->Str| {s["id"].toStr}.unique.sort.toImmutable
    customBoundaryIds=sources.findAll |s| {s["source"] == "custom"}.map |s->Str| {s["id"].toStr}.unique.sort.toImmutable
    excludedOverlaps=FinEnergyMath.maps(area["excludedOverlaps"]).toImmutable
    energyBoundaryId=boundaryId
    sourceRevisions=sources.toImmutable
    reasonCodes=status == "ok" ? Str#.emptyList : [status].toImmutable
  }

  const Str status
  const Float? areaM2
  const Str basis
  const Str[] spaceRefs
  const Str[] customBoundaryIds
  const [Str:Obj?][] excludedOverlaps
  const Str energyBoundaryId
  const [Str:Obj?][] sourceRevisions
  const Str[] reasonCodes

  Str:Obj? toMap()
  {
    return ["status":status,"areaM2":areaM2,"basis":basis,"spaceRefs":spaceRefs,
      "customBoundaryIds":customBoundaryIds,"excludedOverlaps":excludedOverlaps,
      "energyBoundaryId":energyBoundaryId,"sourceRevisions":sourceRevisions,"reasonCodes":reasonCodes]
  }
}

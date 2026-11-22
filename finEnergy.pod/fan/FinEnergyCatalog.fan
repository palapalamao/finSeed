using haystack

** A navigation catalog is not an alarm/job evidence archive. Keep all identities
** for native projection collisions; full management DTOs remain a separate read.
internal const class FinEnergyCatalog
{
  static Str:Obj? decode(Dict record,Bool analysis)
  {
    if(!analysis || record.has("equip") || !["alarm","job"].contains(record["finEnergyKind"])) return FinEnergyRepo.decode(record)
    return ["id":record.id.id,"mod":FinEnergyRepo.iso(record["mod"]),"kind":record["finEnergyKind"],"name":record.dis,"catalogDeferred":true]
  }
}

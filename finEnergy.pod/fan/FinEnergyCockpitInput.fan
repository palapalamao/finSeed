using haystack

** Private analytical view; management and event queries retain their full DTOs.
internal const class FinEnergyCockpitInput
{
  static Bool operational(Obj? kind) {["alarm","job","template"].contains(kind)}
  static Str:Obj? decode(Dict record,FinEnergyPreparedOwner? owner)
  {
    if(!operational(record["finEnergyKind"]) || record.has("equip"))
      return owner==null ? FinEnergyRepo.decode(record) : FinEnergyRepo.decodeOwned(record,owner)
    // Validate the original JSON with the existing parser, but retain just one
    // operational document at a time. No recovery tree enters the input owner.
    scratch:=owner==null ? null : FinEnergyPreparedOwner(owner.budget)
    try
    {
      raw:=scratch==null ? FinEnergyRepo.decode(record) : FinEnergyRepo.decodeOwned(record,scratch)
      out:=Str:Obj?[:]
      raw.each |v,k|
      {
        if(["before","after","snapshot","afterBusiness","nativeAlarmArchive"].contains(k)) return
        if(v isnot Map && v isnot List) out[k]=v
      }
      // The canonicalizer historically examines variables on every kind. Keep
      // abnormal dependency maps fail-closed rather than hiding a bad reference.
      if(raw["variables"]!=null)
        return owner==null ? FinEnergyRepo.decode(record) : FinEnergyRepo.decodeOwned(record,owner)
      owner?.hold(2+out.size);owner?.watch |->Void| {out.clear}
      return out
    }
    finally {scratch?.close}
  }

  ** Token depends on analytical facts, including the exact legacy unit fallback;
  ** alarm acknowledgements and job progress do not invalidate an observation.
  static Str token(FinEnergyContext ctx,[Str:Obj?][] records,Str:Obj? owned,Str project,Str tz,FinEnergyPreparedBudget? budget := null)
  {
    work:=budget==null ? null : FinEnergyPreparedOwner(budget)
    try
    {
      work?.hold(12+2*records.size+2*FinEnergyMath.maps(owned["modelRecords"]).size)
      model:=FinEnergyMath.maps(owned["modelRecords"])
      facts:=(model.isEmpty ? records : model).findAll |r| {!operational(r["kind"])}
      units:=Str:Obj?[:]
      records.findAll |r| {r["kind"]=="category"}.each |r|
      {units[r["id"].toStr]=ctx.unit("__unit_inference__",r["id"].toStr,"energy")}
      config:=owned.dup;config.remove("modelRecords")
      return FinEnergyCockpitDigest.encoded(["project":project,"tz":tz,"facts":facts,"owned":config,"units":units],budget?.deadline,budget).sha256
    }
    finally {work?.close}
  }
}

using fin

class VerifyFinEnergyEdition
{
  Void main(Str[] args)
  {
    if (args.size != 1 || !["china","hq"].contains(args.first))
      throw ArgErr("Expected China or HQ")

    edition := args.first
    pod := Pod.find("finEnergy")
    ext := pod.type("FinEnergyExt")
    feature := ext.facet(FinExtMeta#, false) as FinExtMeta
    if (pod.meta["finEnergy.edition"] != edition)
      throw Err("Compiled edition differs from the requested edition")

    if (edition == "hq")
    {
      if (!ext.fits(FinExt#) || feature?.licFeature != "fin energy")
        throw Err("HQ must use the exact FIN native feature gate")
    }
    else if (feature != null)
      throw Err("China package has an unexpected native gate")

    echo("Loaded and verified " + pod.name + " " + pod.version + " / " + edition)
  }
}

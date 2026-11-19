class FinEnergyValueFoldTest : Test
{
  Void testOwnedStateChargesNewSourcesAndClosesWithoutAliasingFinishedValues()
  {
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());budget.holdOwned(13)
    owner:=FinEnergyPreparedOwner(budget)
    fold:=FinEnergyValueFold.strict(owner)
    initial:=owner.entries
    fold.add(FinEnergyValue(1f,"ok",["p"]))
    verifyEq(owner.entries,initial,"a single source fits the already-owned scalar field without a map")
    fold.add(FinEnergyValue(2f,"ok",["p"]))
    verifyEq(owner.entries,initial)
    result:=fold.finish;owner.close
    verifyEq(result.value,3f);verifyEq(result.sources,["p"]);verifyEq(budget.temporary.val,13)
    verifyErr(ArgErr#) {fold.add(FinEnergyValue(1f,"ok"))}
    verifyErr(ArgErr#) {fold.finish}
    budget.releaseTemporary(13)
  }
  Void testSecondSourceAdmitsItsOrderedMapBeforePublishingAndKeepsPeerOwnership()
  {
    budget:=FinEnergyPreparedBudget(FinEnergyCockpitDeadline());owner:=FinEnergyPreparedOwner(budget)
    fold:=FinEnergyValueFold.known(owner);input:=["p"]
    fold.add(FinEnergyValue(1f,"ok",input));input.clear
    first:=fold.finish;first.sources.add("caller-only");verifyEq(fold.finish.sources,["p"])
    peer:=FinEnergyPreparedOwner(budget);peer.hold(budget.remaining-2);held:=peer.entries;ownHeld:=owner.entries
    verifyErr(FinEnergyHttpErr#) {fold.add(FinEnergyValue(2f,"ok",["q"]))}
    verifyEq(owner.entries,ownHeld);verifyEq(peer.entries,held)
    verifyValue(fold.finish,1f,"ok",["p"])
    peer.close;fold.add(FinEnergyValue(2f,"ok",["q","p","r"]))
    verifyValue(fold.finish,3f,"ok",["p","q","r"])
    result:=fold.finish;owner.close;verifyEq(result.sources,["p","q","r"]);verifyEq(budget.temporary.val,0)
  }
  Void testIndependentStrictAndKnownExpectedStates()
  {
    verifyValue(FinEnergyValueFold.strict().finish,null,"missing",Str[,])
    verifyValue(FinEnergyValueFold.known().finish,null,"missing",Str[,])
    strict:=FinEnergyValueFold.strict();known:=FinEnergyValueFold.known()
    filtered:=FinEnergyValue(null,"filtered",["p"]);strict.add(filtered);known.add(filtered)
    verifyValue(strict.finish,null,"filtered",["p"]);verifyValue(known.finish,null,"missing",["p"])
    strict=FinEnergyValueFold.strict();known=FinEnergyValueFold.known()
    [FinEnergyValue(null,"na",["p"]),FinEnergyValue(0f,"ok",["q"])].each |v| {strict.add(v);known.add(v)}
    verifyValue(strict.finish,null,"na",["p","q"]);verifyValue(known.finish,0f,"filtered",["p","q"])
    known=FinEnergyValueFold.known();known.add(FinEnergyValue(null,"na",["p"]))
    verifyValue(known.finish,null,"na",["p"])
  }

  Void testInputAndFinishedValuesNeverAliasState()
  {
    fold:=FinEnergyValueFold.strict();v:=FinEnergyValue(3f,"cleaned",["p","q"]);fold.add(v)
    v.value=999f;v.quality="na";v.sources.add("input-later")
    first:=fold.finish;verifyValue(first,3f,"cleaned",["p","q"])
    first.value=444f;first.quality="na";first.sources.add("output-later")
    fold.add(FinEnergyValue(2f,"corrected",["q","p","r"]))
    verifyValue(fold.finish,5f,"cleaned",["p","q","r"])
    verifyValue(fold.finish,5f,"cleaned",["p","q","r"])
    verifyEq(first.sources,["p","q","output-later"])
  }

  Void testFinishDoesNotResetOrReassociateScalarAdds()
  {
    fold:=FinEnergyValueFold.strict();fold.add(FinEnergyValue(10000000000000000f,"ok",["p"]))
    fold.add(FinEnergyValue(1f,"ok",["p"]));verifyEq(fold.finish.value,10000000000000000f)
    fold.add(FinEnergyValue(1f,"ok",["q"]));fold.add(FinEnergyValue(1f,"ok",["p"]))
    verifyValue(fold.finish,10000000000000000f,"ok",["p","q"])
    // Summing a later two-scalar block as a subtotal would produce ...002.
    verify(fold.finish.value != 10000000000000002f)
  }

  Void testKnownFirstInvalidStillRetainsLaterSourcesAndNonfiniteValues()
  {
    fold:=FinEnergyValueFold.known();fold.add(FinEnergyValue(null,"invalidA",["p"]))
    fold.add(FinEnergyValue(2f,"corrected",["q"]));fold.add(FinEnergyValue(null,"invalidB",["r","p"]))
    verifyValue(fold.finish,null,"invalidA",["p","q","r"])
    numeric:=FinEnergyValueFold.strict();numeric.add(FinEnergyValue(Float.nan,"ok",["p"]))
    verify(numeric.finish.value.isNaN)
    numeric=FinEnergyValueFold.known();numeric.add(FinEnergyValue(Float.posInf,"ok",["p"]))
    verifyEq(numeric.finish.value,Float.posInf)
  }

  private Void verifyValue(FinEnergyValue actual,Float? value,Str quality,Str[] sources)
  {verifyEq(actual.value,value);verifyEq(actual.quality,quality);verifyEq(actual.sources,sources)}
}

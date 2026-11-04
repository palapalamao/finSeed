class EnerCubixValueFoldTest : Test
{
  Void testOwnedStateChargesNewSourcesAndClosesWithoutAliasingFinishedValues()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());budget.holdOwned(13)
    owner:=EnerCubixPreparedOwner(budget)
    fold:=EnerCubixValueFold.strict(owner)
    initial:=owner.entries
    fold.add(EnerCubixValue(1f,"ok",["p"]))
    verifyEq(owner.entries,initial,"a single source fits the already-owned scalar field without a map")
    fold.add(EnerCubixValue(2f,"ok",["p"]))
    verifyEq(owner.entries,initial)
    result:=fold.finish;owner.close
    verifyEq(result.value,3f);verifyEq(result.sources,["p"]);verifyEq(budget.temporary.val,13)
    verifyErr(ArgErr#) {fold.add(EnerCubixValue(1f,"ok"))}
    verifyErr(ArgErr#) {fold.finish}
    budget.releaseTemporary(13)
  }
  Void testSecondSourceAdmitsItsOrderedMapBeforePublishingAndKeepsPeerOwnership()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
    fold:=EnerCubixValueFold.known(owner);input:=["p"]
    fold.add(EnerCubixValue(1f,"ok",input));input.clear
    first:=fold.finish;first.sources.add("caller-only");verifyEq(fold.finish.sources,["p"])
    peer:=EnerCubixPreparedOwner(budget);peer.hold(budget.remaining-2);held:=peer.entries;ownHeld:=owner.entries
    verifyErr(EnerCubixHttpErr#) {fold.add(EnerCubixValue(2f,"ok",["q"]))}
    verifyEq(owner.entries,ownHeld);verifyEq(peer.entries,held)
    verifyValue(fold.finish,1f,"ok",["p"])
    peer.close;fold.add(EnerCubixValue(2f,"ok",["q","p","r"]))
    verifyValue(fold.finish,3f,"ok",["p","q","r"])
    result:=fold.finish;owner.close;verifyEq(result.sources,["p","q","r"]);verifyEq(budget.temporary.val,0)
  }
  Void testIndependentStrictAndKnownExpectedStates()
  {
    verifyValue(EnerCubixValueFold.strict().finish,null,"missing",Str[,])
    verifyValue(EnerCubixValueFold.known().finish,null,"missing",Str[,])
    strict:=EnerCubixValueFold.strict();known:=EnerCubixValueFold.known()
    filtered:=EnerCubixValue(null,"filtered",["p"]);strict.add(filtered);known.add(filtered)
    verifyValue(strict.finish,null,"filtered",["p"]);verifyValue(known.finish,null,"missing",["p"])
    strict=EnerCubixValueFold.strict();known=EnerCubixValueFold.known()
    [EnerCubixValue(null,"na",["p"]),EnerCubixValue(0f,"ok",["q"])].each |v| {strict.add(v);known.add(v)}
    verifyValue(strict.finish,null,"na",["p","q"]);verifyValue(known.finish,0f,"filtered",["p","q"])
    known=EnerCubixValueFold.known();known.add(EnerCubixValue(null,"na",["p"]))
    verifyValue(known.finish,null,"na",["p"])
  }

  Void testInputAndFinishedValuesNeverAliasState()
  {
    fold:=EnerCubixValueFold.strict();v:=EnerCubixValue(3f,"cleaned",["p","q"]);fold.add(v)
    v.value=999f;v.quality="na";v.sources.add("input-later")
    first:=fold.finish;verifyValue(first,3f,"cleaned",["p","q"])
    first.value=444f;first.quality="na";first.sources.add("output-later")
    fold.add(EnerCubixValue(2f,"corrected",["q","p","r"]))
    verifyValue(fold.finish,5f,"cleaned",["p","q","r"])
    verifyValue(fold.finish,5f,"cleaned",["p","q","r"])
    verifyEq(first.sources,["p","q","output-later"])
  }

  Void testFinishDoesNotResetOrReassociateScalarAdds()
  {
    fold:=EnerCubixValueFold.strict();fold.add(EnerCubixValue(10000000000000000f,"ok",["p"]))
    fold.add(EnerCubixValue(1f,"ok",["p"]));verifyEq(fold.finish.value,10000000000000000f)
    fold.add(EnerCubixValue(1f,"ok",["q"]));fold.add(EnerCubixValue(1f,"ok",["p"]))
    verifyValue(fold.finish,10000000000000000f,"ok",["p","q"])
    // Summing a later two-scalar block as a subtotal would produce ...002.
    verify(fold.finish.value != 10000000000000002f)
  }

  Void testKnownFirstInvalidStillRetainsLaterSourcesAndNonfiniteValues()
  {
    fold:=EnerCubixValueFold.known();fold.add(EnerCubixValue(null,"invalidA",["p"]))
    fold.add(EnerCubixValue(2f,"corrected",["q"]));fold.add(EnerCubixValue(null,"invalidB",["r","p"]))
    verifyValue(fold.finish,null,"invalidA",["p","q","r"])
    numeric:=EnerCubixValueFold.strict();numeric.add(EnerCubixValue(Float.nan,"ok",["p"]))
    verify(numeric.finish.value.isNaN)
    numeric=EnerCubixValueFold.known();numeric.add(EnerCubixValue(Float.posInf,"ok",["p"]))
    verifyEq(numeric.finish.value,Float.posInf)
  }

  private Void verifyValue(EnerCubixValue actual,Float? value,Str quality,Str[] sources)
  {verifyEq(actual.value,value);verifyEq(actual.quality,quality);verifyEq(actual.sources,sources)}
}

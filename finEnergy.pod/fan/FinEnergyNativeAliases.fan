using util

** A single configuration read within the cockpit preparation lifetime only.
** Ordinary catalog/edit requests retain their existing fresh mapping behavior.
internal class FinEnergyNativeAliases
{
  new make(FinEnergyPreparedOwner owner)
  {
    this.owner=owner;owner.hold(3)
    owner.watch |->Void| {cached?.clear;cached=null}
  }
  private FinEnergyPreparedOwner owner
  private [Str:Str]? cached
  Str:Str read(|->Str| json)
  {
    owner.hold(0);owner.budget.deadline.check
    if(cached!=null) return cached
    source:=(Map)FinEnergyOwnedJson.parse(json(),owner)
    owner.hold(1+source.size);result:=Str:Str[:]
    source.each |v,k| {result[k.toStr]=v.toStr}
    cached=result;return result
  }
}

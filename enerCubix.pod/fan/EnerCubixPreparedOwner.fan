** Request-local owner for consumer state. Drop registered roots before releasing
** only this owner's charge; never reset the shared request counter.
internal class EnerCubixPreparedOwner
{
  new make(EnerCubixPreparedBudget budget)
  {this.budget=budget;budget.holdOwned(4);held=4}
  const EnerCubixPreparedBudget budget
  private Int held
  private Bool closed := false
  private |->Void|[] drops := [,]
  Int entries() {held}
  Void hold(Int n)
  {
    if(closed) throw ArgErr("preparedOwnerClosed")
    budget.holdOwned(n);held+=n
  }
  ** Release an explicitly discarded part of this owner's mutable graph only.
  Void release(Int n)
  {
    if(closed || n<0 || n>held) throw ArgErr("preparedOwnerRelease")
    budget.releaseTemporary(n);held-=n
  }
  Void watch(|->Void| drop) {hold(1);drops.add(drop)}
  Void close()
  {
    if(closed) return
    while(!drops.isEmpty) {drop:=drops.first;drop();drops.removeAt(0)}
    budget.releaseTemporary(held);held=0;closed=true
  }
}

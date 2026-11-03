** Request-local owner for consumer state. Drop registered roots before releasing
** only this owner's charge; never reset the shared request counter.
internal class EnerCubixPreparedOwner
{
  new make(EnerCubixPreparedBudget budget,EnerCubixCockpitCapture? samples := null)
  {
    if(samples!=null && samples.budget!==budget) throw ArgErr("preparedOwnerDiagnosticBudget")
    n:=samples==null ? 4 : 5
    samples?.reclaimForBusiness(n)
    budget.holdOwned(n);this.budget=budget;this.samples=samples;held=n
  }
  const EnerCubixPreparedBudget budget
  private EnerCubixCockpitCapture? samples
  private Int held
  private Bool closed := false
  private |->Void|[] drops := [,]
  Int entries() {held}
  EnerCubixPreparedOwner fork()
  {if(closed) throw ArgErr("preparedOwnerClosed");return EnerCubixPreparedOwner(budget,samples)}
  Void hold(Int n)
  {
    if(closed) throw ArgErr("preparedOwnerClosed")
    samples?.reclaimForBusiness(n)
    budget.holdOwned(n);held+=n
  }
  ** Release an explicitly discarded part of this owner's mutable graph only.
  Void release(Int n)
  {
    if(closed || n<0 || n>held) throw ArgErr("preparedOwnerRelease")
    budget.releaseTemporary(n);held-=n
  }
  Void watch(|->Void| drop) {hold(1);drops.add(drop)}
  ** A finished consumer may replace its private roots with its already-admitted
  ** public graph. The caller must first sever every other private state root.
  ** Keep this owner identity so existing catalog/diagnostic bindings stay valid.
  internal Void retainPublic(Int n,|->Void| drop)
  {
    if(closed || n<6 || n>held) throw ArgErr("preparedOwnerRetain")
    drops.clear;drops.add(drop)
    budget.releaseTemporary(held-n);held=n
  }
  Void close()
  {
    if(closed) return
    while(!drops.isEmpty) {drop:=drops.first;drop();drops.removeAt(0)}
    budget.releaseTemporary(held);held=0;samples=null;closed=true
  }
}

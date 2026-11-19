** Request-local scalar reduction. Call add in the original visit order;
** never substitute a block subtotal. No input value or source array is retained.
internal class FinEnergyValueFold
{
  new strict(FinEnergyPreparedOwner? owner := null) {useOwner(owner)}
  new known(FinEnergyPreparedOwner? owner := null) {knownMode=true;useOwner(owner)}

  private Bool knownMode := false
  private Bool seen := false
  private Bool missing := false
  private Bool allNA := true
  private Int numeric := 0
  private Float total := 0f
  private Str quality := "ok"
  private Str? invalidReason
  private [Str:Bool]? sources
  private Str? lastSource
  private FinEnergyPreparedOwner? owner
  private Bool closed := false
  private Void useOwner(FinEnergyPreparedOwner? owner)
  {this.owner=owner;owner?.watch |->Void| {close};owner?.hold(12)}
  private Void close()
  {sources?.clear;sources=null;lastSource=null;invalidReason=null;total=0f;numeric=0;seen=false;missing=false;quality="ok";owner=null;closed=true}
  internal Int sourceCount() {if(closed) throw ArgErr("valueFoldClosed");return sources?.size ?: (lastSource==null ? 0 : 1)}

  Void add(FinEnergyValue value)
  {
    if(closed) throw ArgErr("valueFoldClosed")
    seen=true
    ids:=value.sources
    for(i:=0;i<ids.size;i++)
    {
      id:=ids[i]
      if(id==lastSource) continue
      if(sources==null)
      {
        if(lastSource==null) {lastSource=id;continue}
        // Twelve scalar fields already own the singleton reference. A second
        // distinct source needs one real map header and both ordered entries.
        owner?.hold(3)
        promoted:=Str:Bool[:];promoted.ordered=true;promoted[lastSource]=true;promoted[id]=true
        sources=promoted;lastSource=id;continue
      }
      if(!sources.containsKey(id)) {owner?.hold(1);sources[id]=true}
      lastSource=id
    }
    if(!knownMode)
    {
      if(value.value == null && value.quality != "filtered") missing=true
      else if(value.value != null) {total+=value.value;numeric++}
      quality=FinEnergyValue.worse(quality,value.quality)
      return
    }
    if(value.value != null)
    {total+=value.value;numeric++;allNA=false;quality=FinEnergyValue.worse(quality,value.quality)}
    else
    {
      missing=true
      if(value.quality != "na") allNA=false
      if(invalidReason == null && !knownNullQualities.contains(value.quality)) invalidReason=value.quality
    }
  }

  FinEnergyValue finish()
  {
    if(closed) throw ArgErr("valueFoldClosed")
    if(!seen) return FinEnergyValue()
    ids:=sources==null ? (lastSource==null ? Str[,] : Str[lastSource]) : sources.keys.dup
    if(!knownMode) return FinEnergyValue(missing || numeric == 0 ? null : total,quality,ids)
    if(invalidReason != null) return FinEnergyValue(null,invalidReason,ids)
    if(numeric == 0) return FinEnergyValue(null,allNA ? "na" : "missing",ids)
    return FinEnergyValue(total,missing ? FinEnergyValue.worse(quality,"filtered") : quality,ids)
  }
  private static const Str[] knownNullQualities := ["missing","incompleteInterval","filtered","substituted","na","reset","negative","maximum"]
}

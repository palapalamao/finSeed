** Request-local scalar reduction. Call add in the original visit order;
** never substitute a block subtotal. No input value or source array is retained.
internal class EnerCubixValueFold
{
  new strict(EnerCubixPreparedOwner? owner := null) {sources.ordered=true;useOwner(owner)}
  new known(EnerCubixPreparedOwner? owner := null) {knownMode=true;sources.ordered=true;useOwner(owner)}

  private Bool knownMode := false
  private Bool seen := false
  private Bool missing := false
  private Bool allNA := true
  private Int numeric := 0
  private Float total := 0f
  private Str quality := "ok"
  private Str? invalidReason
  private Str:Bool sources := [:]
  private Str? lastSource
  private EnerCubixPreparedOwner? owner
  private Bool closed := false
  private Void useOwner(EnerCubixPreparedOwner? owner)
  {this.owner=owner;owner?.watch |->Void| {close};owner?.hold(13)}
  private Void close()
  {sources.clear;lastSource=null;invalidReason=null;total=0f;numeric=0;seen=false;missing=false;quality="ok";owner=null;closed=true}
  internal Int sourceCount() {if(closed) throw ArgErr("valueFoldClosed");return sources.size}

  Void add(EnerCubixValue value)
  {
    if(closed) throw ArgErr("valueFoldClosed")
    seen=true
    ids:=value.sources
    for(i:=0;i<ids.size;i++)
    {
      id:=ids[i]
      if(id==lastSource) continue
      if(!sources.containsKey(id)) {owner?.hold(1);sources[id]=true}
      lastSource=id
    }
    if(!knownMode)
    {
      if(value.value == null && value.quality != "filtered") missing=true
      else if(value.value != null) {total+=value.value;numeric++}
      quality=EnerCubixValue.worse(quality,value.quality)
      return
    }
    if(value.value != null)
    {total+=value.value;numeric++;allNA=false;quality=EnerCubixValue.worse(quality,value.quality)}
    else
    {
      missing=true
      if(value.quality != "na") allNA=false
      if(invalidReason == null && !knownNullQualities.contains(value.quality)) invalidReason=value.quality
    }
  }

  EnerCubixValue finish()
  {
    if(closed) throw ArgErr("valueFoldClosed")
    if(!seen) return EnerCubixValue()
    ids:=sources.keys.dup
    if(!knownMode) return EnerCubixValue(missing || numeric == 0 ? null : total,quality,ids)
    if(invalidReason != null) return EnerCubixValue(null,invalidReason,ids)
    if(numeric == 0) return EnerCubixValue(null,allNA ? "na" : "missing",ids)
    return EnerCubixValue(total,missing ? EnerCubixValue.worse(quality,"filtered") : quality,ids)
  }
  private static const Str[] knownNullQualities := ["missing","incompleteInterval","filtered","substituted","na","reset","negative","maximum"]
}

** Request-local scalar reduction. Call add in the original visit order;
** never substitute a block subtotal. No input value or source array is retained.
internal class EnerCubixValueFold
{
  new strict() {sources.ordered=true}
  new known() {knownMode=true;sources.ordered=true}

  private Bool knownMode := false
  private Bool seen := false
  private Bool missing := false
  private Bool allNA := true
  private Int numeric := 0
  private Float total := 0f
  private Str quality := "ok"
  private Str? invalidReason
  private Str:Bool sources := [:]

  Void add(EnerCubixValue value)
  {
    seen=true
    value.sources.each |id| {if(!sources.containsKey(id)) sources[id]=true}
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
      if(invalidReason == null && !["missing","incompleteInterval","filtered","substituted","na","reset","negative","maximum"].contains(value.quality)) invalidReason=value.quality
    }
  }

  EnerCubixValue finish()
  {
    if(!seen) return EnerCubixValue()
    ids:=sources.keys.dup
    if(!knownMode) return EnerCubixValue(missing || numeric == 0 ? null : total,quality,ids)
    if(invalidReason != null) return EnerCubixValue(null,invalidReason,ids)
    if(numeric == 0) return EnerCubixValue(null,allNA ? "na" : "missing",ids)
    return EnerCubixValue(total,missing ? EnerCubixValue.worse(quality,"filtered") : quality,ids)
  }
}

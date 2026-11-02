** Ordered line reduction without retaining its input ticks.
internal class EnerCubixLineFold
{
  new make(EnerCubixLine line,Str mode := "value",EnerCubixPreparedOwner? owner := null)
  {
    if(!["value","known","baseValue","baseKnown"].contains(mode)) throw ArgErr("lineFoldMode")
    this.mode=mode;ratio=mode == "value" && line.ratio;gauge=mode == "value" && line.gauge
    this.owner=owner;owner?.watch |->Void| {close};owner?.hold(12)
    if(ratio) {numerator=EnerCubixValueFold.strict(owner);denominator=EnerCubixValueFold.strict(owner)}
    else total=mode == "known" || mode == "baseKnown" ? EnerCubixValueFold.known(owner) : EnerCubixValueFold.strict(owner)
  }
  private Str mode
  private Bool ratio
  private Bool gauge
  private Int count := 0
  private Float duration := 0f
  private EnerCubixValue? incomplete
  private EnerCubixValueFold? total
  private EnerCubixValueFold? numerator
  private EnerCubixValueFold? denominator
  private EnerCubixPreparedOwner? owner
  private Bool closed := false
  private Void close() {incomplete=null;total=null;numerator=null;denominator=null;owner=null;closed=true}

  internal Int outputEntries()
  {
    if(closed) throw ArgErr("lineFoldClosed")
    if(ratio) return 4+numerator.sourceCount+denominator.sourceCount
    return 4+(gauge && incomplete != null ? incomplete.sources.size : total.sourceCount)
  }
  internal Int outputScratchEntries()
  {
    if(closed) throw ArgErr("lineFoldClosed")
    return ratio ? 10+3*(numerator.sourceCount+denominator.sourceCount) : 4+total.sourceCount
  }

  Void add(EnerCubixTick tick)
  {
    if(closed) throw ArgErr("lineFoldClosed")
    count++
    if(ratio)
    {
      numerator.add(tick.numerator ?: EnerCubixValue())
      denominator.add(tick.denominator ?: EnerCubixValue())
      return
    }
    v:=mode == "known" ? (tick.known ?: EnerCubixValue()) :
      (mode == "baseValue" ? (tick.baseValue ?: tick.value) :
      (mode == "baseKnown" ? ((tick.baseKnown ?: tick.known) ?: EnerCubixValue()) : tick.value))
    if(gauge)
    {
      if(incomplete == null && !v.reliable) {owner?.hold(2+v.sources.size);incomplete=EnerCubixValue(null,v.quality,v.sources.dup)}
      ticks:=(tick.end-tick.ts).ticks.toFloat;duration+=ticks
      total.add(v.scale(ticks))
    }
    else total.add(v)
  }
  EnerCubixValue finish()
  {
    if(closed) throw ArgErr("lineFoldClosed")
    if(ratio) return EnerCubixValue.divide(numerator.finish,denominator.finish)
    if(gauge && count > 0)
    {
      if(incomplete != null) return EnerCubixValue(null,incomplete.quality,incomplete.sources.dup)
      return total.finish.scale(1f/duration)
    }
    return total.finish
  }
}

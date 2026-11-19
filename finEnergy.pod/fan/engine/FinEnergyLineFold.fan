** Ordered line reduction without retaining its input ticks.
internal class FinEnergyLineFold
{
  new make(FinEnergyLine line,Str mode := "value",FinEnergyPreparedOwner? owner := null)
  {
    if(!["value","known","baseValue","baseKnown"].contains(mode)) throw ArgErr("lineFoldMode")
    this.mode=mode;ratio=mode == "value" && line.ratio;gauge=mode == "value" && line.gauge
    this.owner=owner;owner?.watch |->Void| {close};owner?.hold(12)
    if(ratio) {numerator=FinEnergyValueFold.strict(owner);denominator=FinEnergyValueFold.strict(owner)}
    else total=mode == "known" || mode == "baseKnown" ? FinEnergyValueFold.known(owner) : FinEnergyValueFold.strict(owner)
  }
  private Str mode
  private Bool ratio
  private Bool gauge
  private Int count := 0
  private Float duration := 0f
  private FinEnergyValue? incomplete
  private FinEnergyValueFold? total
  private FinEnergyValueFold? numerator
  private FinEnergyValueFold? denominator
  private FinEnergyPreparedOwner? owner
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

  Void add(FinEnergyTick tick)
  {
    if(closed) throw ArgErr("lineFoldClosed")
    count++
    if(ratio)
    {
      numerator.add(tick.numerator ?: FinEnergyValue())
      denominator.add(tick.denominator ?: FinEnergyValue())
      return
    }
    v:=mode == "known" ? (tick.known ?: FinEnergyValue()) :
      (mode == "baseValue" ? (tick.baseValue ?: tick.value) :
      (mode == "baseKnown" ? ((tick.baseKnown ?: tick.known) ?: FinEnergyValue()) : tick.value))
    if(gauge)
    {
      if(incomplete == null && !v.reliable) {owner?.hold(2+v.sources.size);incomplete=FinEnergyValue(null,v.quality,v.sources.dup)}
      ticks:=(tick.end-tick.ts).ticks.toFloat;duration+=ticks
      total.add(v.scale(ticks))
    }
    else total.add(v)
  }
  FinEnergyValue finish()
  {
    if(closed) throw ArgErr("lineFoldClosed")
    if(ratio) return FinEnergyValue.divide(numerator.finish,denominator.finish)
    if(gauge && count > 0)
    {
      if(incomplete != null) return FinEnergyValue(null,incomplete.quality,incomplete.sources.dup)
      return total.finish.scale(1f/duration)
    }
    return total.finish
  }
}

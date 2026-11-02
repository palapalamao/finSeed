** Ordered line reduction without retaining its input ticks.
internal class EnerCubixLineFold
{
  new make(EnerCubixLine line,Str mode := "value")
  {
    if(!["value","known","baseValue","baseKnown"].contains(mode)) throw ArgErr("lineFoldMode")
    this.mode=mode;ratio=mode == "value" && line.ratio;gauge=mode == "value" && line.gauge
    if(ratio) {numerator=EnerCubixValueFold.strict();denominator=EnerCubixValueFold.strict()}
    else total=mode == "known" || mode == "baseKnown" ? EnerCubixValueFold.known() : EnerCubixValueFold.strict()
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

  Void add(EnerCubixTick tick)
  {
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
      if(incomplete == null && !v.reliable) incomplete=EnerCubixValue(null,v.quality,v.sources.dup)
      ticks:=(tick.end-tick.ts).ticks.toFloat;duration+=ticks
      total.add(v.scale(ticks))
    }
    else total.add(v)
  }
  EnerCubixValue finish()
  {
    if(ratio) return EnerCubixValue.divide(numerator.finish,denominator.finish)
    if(gauge && count > 0)
    {
      if(incomplete != null) return EnerCubixValue(null,incomplete.quality,incomplete.sources.dup)
      return total.finish.scale(1f/duration)
    }
    return total.finish
  }
}

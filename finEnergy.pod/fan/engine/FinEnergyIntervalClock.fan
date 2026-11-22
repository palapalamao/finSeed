** Observable legacy ISO boundary semantics for private closed-interval readers.
** No project timezone name escapes: these readers use instants and ISO text.
internal class FinEnergyIntervalClock
{
  static DateTime serialized(DateTime value)
  {
    // The target native SDK converts ISO offsets to GMT zones with integer
    // offsetSeconds/3600. Whole-hour offsets preserve both instant and ISO text;
    // fractional and historical second offsets retain the original parser.
    offset:=value.tz.offset(value.year).ticks
    if(value.dst) offset+=value.tz.dstOffset(value.year)?.ticks ?: 0
    return offset % 1hr.ticks==0 ? value : DateTime.fromIso(value.toIso)
  }

  private DateTime? previousEnd
  private DateTime? originalEnd
  FinEnergyInterval interval(DateTime start,DateTime end,Float? value,Str quality,Str valueType)
  {
    adjacent:=originalEnd
    sameBoundary:=adjacent!=null && adjacent.ticks==start.ticks &&
      ((adjacent.tz==start.tz && adjacent.dst==start.dst) || adjacent.toIso==start.toIso)
    left:=(sameBoundary ? previousEnd : null) ?: serialized(start)
    right:=serialized(end)
    previousEnd=right;originalEnd=end
    return FinEnergyInterval(left,right,value,quality,valueType)
  }
}

** Internal seam for the existing report's ordered hourly leaf calculation.
internal class EnerCubixLineCursor
{
  new make(EnerCubixLine line,DateTime start,DateTime end,Bool durationAligned,
    |DateTime,DateTime->EnerCubixTick| read,|->Void| complete)
  {this.line=line;at=start;this.end=end;this.durationAligned=durationAligned;this.read=read;this.complete=complete}
  EnerCubixLine line
  private DateTime at
  private DateTime end
  private Bool durationAligned
  private |DateTime,DateTime->EnerCubixTick|? read
  private |->Void|? complete
  private Bool completed := false
  private Err? failure
  DateTime watermark() {at}
  Bool more() {at < end}
  EnerCubixTick next()
  {
    if(failure != null) throw failure
    if(!more) throw ArgErr("lineCursorComplete")
    to:=durationAligned ? at+1hr : EnerCubixMath.floorHour(at)+1hr
    if(to > end) to=end
    try {tick:=read(at,to);at=to;return tick}
    catch(Err e) {failure=e;read=null;complete=null;throw e}
  }
  EnerCubixLine finish()
  {
    if(failure != null) throw failure
    if(more) throw ArgErr("lineCursorIncomplete")
    if(!completed)
    {
      try {complete();completed=true;read=null;complete=null}
      catch(Err e) {failure=e;read=null;complete=null;throw e}
    }
    return line
  }
}

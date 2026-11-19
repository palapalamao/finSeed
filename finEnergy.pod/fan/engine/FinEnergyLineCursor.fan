** Internal seam for the existing report's ordered hourly leaf calculation.
internal class FinEnergyLineCursor
{
  new make(FinEnergyLine line,DateTime start,DateTime end,Bool durationAligned,
    |DateTime,DateTime->FinEnergyTick| read,|->Void| complete)
  {this.line=line;at=start;this.end=end;this.durationAligned=durationAligned;this.read=read;this.complete=complete}
  FinEnergyLine line
  private DateTime at
  private DateTime end
  private Bool durationAligned
  private |DateTime,DateTime->FinEnergyTick|? read
  private |->Void|? complete
  private Bool completed := false
  private Err? failure
  DateTime watermark() {at}
  Bool more() {at < end}
  FinEnergyTick next()
  {
    if(failure != null) throw failure
    if(!more) throw ArgErr("lineCursorComplete")
    to:=durationAligned ? at+1hr : FinEnergyMath.floorHour(at)+1hr
    if(to > end) to=end
    try {tick:=read(at,to);at=to;return tick}
    catch(Err e) {failure=e;read=null;complete=null;throw e}
  }
  FinEnergyLine finish()
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

** Private lifetime for a producer's borrowed prepared prefix. Consumers retain
** only their detached reductions/evidence, charged separately from this prefix.
internal class FinEnergyPreparedFrame
{
  private Bool active := true
  private FinEnergyHistoryData[] readers := [,]
  Void check() {if(!active) throw ArgErr("preparedFrameExpired")}
  Void attach(FinEnergyHistoryData reader) {check;readers.add(reader)}
  Void expire()
  {
    if(!active) return
    active=false
    readers.each |reader| {reader.expireFrame}
    readers.clear
  }
}

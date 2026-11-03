using util

** A final JSON envelope, serialized once before a sender may commit a status.
** Buffer ownership lasts through the callback; it does not escape this scope.
internal const class EnerCubixCockpitWire
{
  static Void withBody(Str:Obj? body,EnerCubixPreparedBudget budget,|Buf| send,Int maxBytes := 8388608)
  {
    if(maxBytes<1 || maxBytes>8388608) throw ArgErr("cockpitWireLimit")
    budget.deadline.check
    owner:=EnerCubixPreparedOwner(budget);EnerCubixCockpitJsonOut? out;Err? failure
    try
    {
      owner.hold(16);out=EnerCubixCockpitJsonOut(maxBytes,budget.deadline)
      JsonOutStream(out).writeJson(body)
      budget.deadline.check
      send(out.bytes.flip)
    }
    catch(Err e) {failure=e;throw e}
    finally
    {
      try {out?.bytes?.clear;owner.close}
      catch(Err cleanup)
      {if(failure==null) throw cleanup;Log.get("enerCubix").err("Cockpit wire cleanup failed after an earlier failure",cleanup)}
    }
  }
}

internal class EnerCubixCockpitJsonOut : OutStream
{
  new make(Int limit,EnerCubixCockpitDeadline deadline) : super(null)
  {this.limit=limit;this.deadline=deadline;bytes=Buf(limit.min(1024));charset=Charset.utf8}
  const Int limit
  const EnerCubixCockpitDeadline deadline
  Buf bytes
  override This write(Int byte)
  {
    if(bytes.size>=limit) throw EnerCubixHttpErr(413,"RESPONSE_LIMIT","cockpitResponseLimit")
    if(bytes.size%8192==0) deadline.check
    bytes.write(byte);return this
  }
  override This writeBuf(Buf source,Int n := source.remaining)
  {
    if(n<0 || n>source.remaining) throw IOErr("Invalid JSON buffer range")
    n.times {write(source.read ?: throw IOErr("Unexpected JSON buffer end"))}
    return this
  }
  override This flush() {this}
  override Bool close() {true}
}

using util
using [java] java.security::MessageDigest

** Hash the exact JSON UTF-8 stream without keeping its full Str or Buf.
** The final response's byte limit does not apply to internal hash input.
internal const class EnerCubixCockpitDigest
{
  ** Match the existing codec's ordered-map hash without cloning unchanged
  ** immutable business containers. New encoding/table builders retain their
  ** original iteration order; only borrowed business maps are sorted here.
  static EnerCubixCockpitDigestValue encoded(Obj? value,EnerCubixCockpitDeadline? deadline := null,EnerCubixPreparedBudget? budget := null)
  {
    if(budget!=null) {if(deadline!=null && deadline!==budget.deadline) throw ArgErr("cockpitDigestDeadline");deadline=budget.deadline}
    deadline?.check;EnerCubixPreparedOwner? owner
    try
    {
      if(budget!=null) {owner=EnerCubixPreparedOwner(budget);owner.hold(64)}
      out:=EnerCubixCockpitDigestOut(deadline);writeEncoded(out,value,owner);deadline?.check;return out.result
    }
    finally {owner?.close}
  }
  private static Void writeEncoded(OutStream out,Obj? value,EnerCubixPreparedOwner? owner)
  {
    if(value is Map)
    {
      m:=(Map)value;out.writeChar('{');first:=true
      emit:=|Obj k|
      {if(!first) out.writeChar(',');first=false;JsonOutStream(out).writeJson(k.toStr);out.writeChar(':');writeEncoded(out,m[k],owner)}
      if(m.isImmutable)
      {
        charge:=2+2*m.size;owner?.hold(charge);List? keys
        try {keys=m.keys.sort;keys.each |k| {emit(k)}}
        finally {keys?.clear;owner?.release(charge)}
      }
      else m.each |v,k| {emit(k)}
      out.writeChar('}');return
    }
    if(value is List)
    {out.writeChar('[');((List)value).each |v,i| {if(i>0) out.writeChar(',');writeEncoded(out,v,owner)};out.writeChar(']');return}
    JsonOutStream(out).writeJson(value)
  }
  static EnerCubixCockpitDigestValue json(Obj? value,EnerCubixCockpitDeadline? deadline := null,EnerCubixPreparedBudget? budget := null)
  {
    if(budget!=null)
    {if(deadline!=null && deadline!==budget.deadline) throw ArgErr("cockpitDigestDeadline");deadline=budget.deadline}
    deadline?.check;EnerCubixPreparedOwner? owner
    try
    {
      if(budget!=null) {owner=EnerCubixPreparedOwner(budget);owner.hold(64)}
      out:=EnerCubixCockpitDigestOut(deadline)
      JsonOutStream(out).writeJson(value);deadline?.check
      return out.result
    }
    finally {owner?.close}
  }
}

internal const class EnerCubixCockpitDigestValue
{
  new make(Str sha256,Int size) {this.sha256=sha256;this.size=size}
  const Str sha256
  const Int size
}

internal class EnerCubixCockpitDigestOut : OutStream
{
  new make(EnerCubixCockpitDeadline? deadline) : super(null)
  {this.deadline=deadline;digest=MessageDigest.getInstance("SHA-256");charset=Charset.utf8}
  private EnerCubixCockpitDeadline? deadline
  private MessageDigest digest
  private Int size
  override This write(Int byte)
  {if(size%8192==0) deadline?.check;digest.update(byte);size++;return this}
  override This writeBuf(Buf source,Int n := source.remaining)
  {
    if(n<0 || n>source.remaining) throw IOErr("Invalid JSON buffer range")
    n.times {write(source.read ?: throw IOErr("Unexpected JSON buffer end"))};return this
  }
  EnerCubixCockpitDigestValue result()
  {
    bytes:=digest.digest;buf:=Buf(32)
    (0..<32).each |Int i| {buf.write(bytes.get(i))}
    return EnerCubixCockpitDigestValue(buf.toHex,size)
  }
  override This flush() {this}
  override Bool close() {true}
}

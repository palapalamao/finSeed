using util

** Negotiated, lossless representation of one cockpit response. It does not
** alter reports, arithmetic, source identity or the legacy /report contract.
internal class EnerCubixCockpitPayload
{
  static Str:Obj? encode(Str:Obj? snapshot)
  {
    codec:=EnerCubixCockpitPayload()
    body:=codec.value(snapshot,"")
    return (Str:Obj?)["payloadEncoding":"compact-v1","codecVersion":1,"snapshot":body,"evidence":codec.entries].toImmutable
  }
  private Str:Obj? entries := [:]
  private static const Str[] shared := ["periods","sourceUsage","cleaning","usageCoverage","tariffSnapshot","energyFlow"]

  private Obj? value(Obj? input,Str key)
  {
    Obj? out:=input
    if (input is Map)
    {
      m:=(Map)input;map:=Str:Obj?[:];map.ordered=true
      m.keys.map |k->Str| {k.toStr}.sort.each |field| {map[field]=value(m[field],field)}
      out=m.keys.any |field| {["\$cockpitRef","\$cockpitTable","\$cockpitLiteral"].contains(field)} ? ["\$cockpitLiteral":map] : map
    }
    else if (input is List)
    {
      list:=(List)input
      Bool table:=false
      if (["periods","heatmap"].contains(key) && !list.isEmpty && list.all |v| {v is Map})
      {
        first:=(Map)list.first;columns:=first.keys.map |k->Str| {k.toStr}.sort
        if (list.all |v| {((Map)v).keys.map |k->Str| {k.toStr}.sort == columns})
        {
          table=true
          out=["\$cockpitTable":["columns":columns,"rows":list.map |v->Obj?| {columns.map |c->Obj?| {value(((Map)v)[c],"")}}]]
        }
      }
      if (!table) out=list.map |v->Obj?| {value(v,"")}
    }
    if (shared.contains(key) && (out is Map || out is List))
    {
      json:=JsonOutStream.writeJsonToStr(out)
      if (json.toBuf.size > 512)
      {
        id:=json.toBuf.toDigest("SHA-256").toHex
        if (!entries.containsKey(id)) entries[id]=out
        return ["\$cockpitRef":id]
      }
    }
    return out
  }
}

using util

** Negotiated, lossless representation of one cockpit response. It does not
** alter reports, arithmetic, source identity or the legacy /report contract.
internal class EnerCubixCockpitPayload
{
  static Str:Obj? encode(Str:Obj? snapshot, EnerCubixCockpitDeadline? deadline := null,EnerCubixPreparedBudget? budget := null,EnerCubixPreparedOwner? output := null)
  {
    if(output!=null)
    {
      if(budget!=null && output.budget!==budget) throw ArgErr("cockpitPayloadBudget")
      budget=output.budget
      if(deadline!=null && deadline!==budget.deadline) throw ArgErr("cockpitPayloadDeadline")
      deadline=budget.deadline
    }
    deadline?.check;EnerCubixPreparedOwner? work;EnerCubixCockpitPayload? codec;Obj? body;Map? envelope
    try
    {
      if(output!=null) {work=EnerCubixPreparedOwner(budget);work.hold(8)}
      codec=EnerCubixCockpitPayload();codec.work=work;codec.deadline=deadline;codec.budget=budget
      body=codec.value(snapshot,"")
      codec.hold(5);envelope=["payloadEncoding":"compact-v1","codecVersion":1,"snapshot":body,"evidence":codec.entries]
      return output==null ? (Str:Obj?)envelope.toImmutable : (Str:Obj?)EnerCubixCockpitFreeze.value(envelope,output)
    }
    finally {clear(body);clear(codec?.entries);envelope?.clear;work?.close}
  }
  private Str:Obj? entries := [:]
  private EnerCubixCockpitDeadline? deadline
  private EnerCubixPreparedBudget? budget
  private EnerCubixPreparedOwner? work
  private Int visited := 0
  private Void check() {if(++visited % 256 == 0) deadline?.check}
  private static const Str[] shared := ["periods","sourceUsage","cleaning","usageCoverage","tariffSnapshot","energyFlow"]
  private Void hold(Int n) {work?.hold(n)}
  private static Void clear(Obj? value)
  {
    if(value==null || value.isImmutable) return
    if(value is Map) {((Map)value).each |Obj? v| {clear(v)};((Map)value).clear}
    else if(value is List) {((Obj?[])value).each |Obj? v| {clear(v)};((List)value).clear}
  }

  private Obj? value(Obj? input,Str key)
  {
    check
    if(input isnot Map && input isnot List) return input
    local:=work==null ? null : EnerCubixPreparedOwner(work.budget)
    try
    {
    Obj? out:=input
    if (input is Map)
    {
      m:=(Map)input;hold(1+m.size);local?.hold(2+2*m.size)
      map:=Str:Obj?[:];map.ordered=true
      fields:=m.keys.map |k->Str| {k.toStr}.sort
      fields.each |field| {map[field]=value(m[field],field)}
      if(fields.any |field| {["\$cockpitRef","\$cockpitTable","\$cockpitLiteral"].contains(field)})
      {hold(2);out=["\$cockpitLiteral":map]}
      else out=map
    }
    else if (input is List)
    {
      list:=(List)input
      Bool table:=false
      if (["periods","heatmap"].contains(key) && !list.isEmpty && list.all |v| {v is Map})
      {
        first:=(Map)list.first;local?.hold(2+2*first.size);columns:=first.keys.map |k->Str| {k.toStr}.sort
        if (list.all |v| {check;return sameKeys((Map)v,columns)})
        {
          table=true
          hold(1)
          constants:=Str:Obj?[:]
          columns.each |c| {if(list.all |v| {check;return ((Map)v)[c] == first[c]}) {hold(1);constants[c]=value(first[c],"")}}
          variableCount:=0;columns.each |c| {if(!constants.containsKey(c)) variableCount++}
          hold(1+variableCount)
          variable:=columns.findAll |c| {!constants.containsKey(c)}
          hold(1+list.size)
          rows:=list.map |v->Obj?| {hold(1+variable.size);return variable.map |c->Obj?| {value(((Map)v)[c],"")}}
          hold(constants.isEmpty ? 3 : 4)
          data:=Str:Obj?["columns":variable,"rows":rows]
          if (!constants.isEmpty) data["constants"]=constants
          hold(2)
          out=["\$cockpitTable":data]
        }
      }
      if (!table) {hold(1+list.size);out=list.map |v->Obj?| {value(v,"")}}
    }
    if (shared.contains(key) && (out is Map || out is List))
    {
      hash:=EnerCubixCockpitDigest.json(out,deadline,budget)
      if (hash.size > 512)
      {
        id:=hash.sha256
        if (!entries.containsKey(id)) {hold(1);entries[id]=out}
        hold(2)
        return ["\$cockpitRef":id]
      }
    }
    return out
    }
    finally {local?.close}
  }
  private Bool sameKeys(Map row,Str[] columns)
  {
    if(row.size!=columns.size) return false
    local:=work==null ? null : EnerCubixPreparedOwner(work.budget)
    try {local?.hold(1+row.size);return row.keys.all |k| {columns.contains(k.toStr)}}
    finally {local?.close}
  }
}

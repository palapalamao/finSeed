using util
using [java] java.util::IdentityHashMap

** Negotiated, lossless representation of one cockpit response. It does not
** alter reports, arithmetic, source identity or the legacy /report contract.
** Owned encoding borrows unchanged immutable business containers; the caller
** must keep their original owner alive until the payload owner expires.
internal class FinEnergyCockpitPayload
{
  static Str:Obj? encode(Str:Obj? snapshot, FinEnergyCockpitDeadline? deadline := null,FinEnergyPreparedBudget? budget := null,FinEnergyPreparedOwner? output := null,FinEnergyCockpitRequestScope? sourceScope := null)
  {
    if(output!=null)
    {
      if(budget!=null && output.budget!==budget) throw ArgErr("cockpitPayloadBudget")
      budget=output.budget
      if(deadline!=null && deadline!==budget.deadline) throw ArgErr("cockpitPayloadDeadline")
      deadline=budget.deadline
    }
    deadline?.check;FinEnergyPreparedOwner? work;FinEnergyCockpitPayload? codec;Obj? body;Map? envelope
    try
    {
      if(output!=null) {work=FinEnergyPreparedOwner(budget);work.hold(12)}
      codec=FinEnergyCockpitPayload();codec.work=work;codec.deadline=deadline;codec.budget=budget
      codec.canBorrow=output!=null && sourceScope?.canBorrowPayload(snapshot,output)==true
      body=codec.value(snapshot,"")
      codec.hold(5);envelope=["payloadEncoding":"compact-v1","codecVersion":1,"snapshot":body,"evidence":codec.entries]
      return output==null ? (Str:Obj?)envelope.toImmutable : (Str:Obj?)FinEnergyCockpitFreeze.value(envelope,output,null,|Obj value|
      {
        // Only the codec's newly admitted builder is consumed. The immutable
        // business snapshot and borrowed values are never changed or released.
        count:=1+(value is Map ? ((Map)value).size : ((List)value).size)
        if(value is Map) ((Map)value).clear;else ((List)value).clear
        // The empty container remains referenced by the freezer memo.
        work.release(count-1)
      })
    }
    finally {clear(body);clear(codec?.entries);codec?.sharedMemo?.clear;codec?.sourceMemo?.clear;envelope?.clear;work?.close}
  }
  private IdentityHashMap sharedMemo := IdentityHashMap()
  private Str:Obj? sourceMemo := [:]
  private Str:Obj? entries := [:]
  private FinEnergyCockpitDeadline? deadline
  private FinEnergyPreparedBudget? budget
  private FinEnergyPreparedOwner? work
  private Int visited := 0
  private Bool canBorrow := false
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
    memoize:=work!=null && input.isImmutable && shared.contains(key)
    memo:=memoize ? (sharedMemo.get(input) as Map) : null
    if(memo!=null && memo.containsKey(key)) return memo[key]
    Str? sourceKey
    if(memoize)
    {
      // Separate report freezes may detach equal evidence lists. Reuse their
      // existing encoded reference before allocating a second discarded graph.
      sourceHash:=FinEnergyCockpitDigest.json(input,deadline,budget)
      if(sourceHash.size>512)
      {
        sourceKey=key+"|"+sourceHash.sha256
        if(sourceMemo.containsKey(sourceKey))
        {cached:=sourceMemo[sourceKey];remember(input,key,cached,memoize,memo,sourceKey);return cached}
      }
    }
    local:=work==null ? null : FinEnergyPreparedOwner(work.budget)
    try
    {
    Obj? out:=input
    if (input is Map)
    {
      m:=(Map)input;local?.hold(2+2*m.size)
      fields:=m.keys.map |k->Str| {k.toStr}.sort
      literal:=fields.any |field| {["\$cockpitRef","\$cockpitTable","\$cockpitLiteral"].contains(field)}
      borrow:=canBorrow && input.isImmutable && m.keys.all |k| {k is Str}
      [Str:Obj?]? map
      if(!borrow || literal) {hold(1+m.size);map=Str:Obj?[:];map.ordered=true}
      fields.each |field,i|
      {
        original:=m[field];encoded:=value(original,field)
        if(map==null && encoded!==original)
        {
          hold(1+m.size);map=Str:Obj?[:];map.ordered=true
          for(j:=0;j<i;j++) map[fields[j]]=m[fields[j]]
        }
        if(map!=null) map[field]=encoded
      }
      out=map ?: input
      if(literal) {hold(2);out=["\$cockpitLiteral":map]}
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
      if(!table)
      {
        if(canBorrow && input.isImmutable)
        {
          Obj?[]? changed
          list.each |v,i|
          {
            encoded:=value(v,"")
            if(changed==null && encoded!==v)
            {
              hold(1+list.size);changed=Obj?[,]
              for(j:=0;j<i;j++) changed.add(list[j])
            }
            changed?.add(encoded)
          }
          out=changed ?: input
        }
        else {hold(1+list.size);out=list.map |v->Obj?| {value(v,"")}}
      }
    }
    if (shared.contains(key) && (out is Map || out is List))
    {
      hash:=canBorrow ? FinEnergyCockpitDigest.encoded(out,deadline,budget) : FinEnergyCockpitDigest.json(out,deadline,budget)
      if (hash.size > 512)
      {
        id:=hash.sha256
        if (!entries.containsKey(id)) {hold(1);entries[id]=out}
        hold(2)
        result:=Str:Obj?["\$cockpitRef":id];remember(input,key,result,memoize,memo,sourceKey);return result
      }
    }
    remember(input,key,out,memoize,memo,sourceKey);return out
    }
    finally {local?.close}
  }
  private Void remember(Obj input,Str key,Obj? encoded,Bool enabled,Map? memo,Str? sourceKey := null)
  {
    if(!enabled) return
    if(memo==null) {hold(4);memo=Str:Obj?[:];sharedMemo.put(input,memo)}
    hold(1);memo[key]=encoded
    if(sourceKey!=null && !sourceMemo.containsKey(sourceKey)) {hold(2);sourceMemo[sourceKey]=encoded}
  }
  private Bool sameKeys(Map row,Str[] columns)
  {
    if(row.size!=columns.size) return false
    local:=work==null ? null : FinEnergyPreparedOwner(work.budget)
    try {local?.hold(1+row.size);return row.keys.all |k| {columns.contains(k.toStr)}}
    finally {local?.close}
  }
}

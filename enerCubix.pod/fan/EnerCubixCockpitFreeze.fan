using [java] java.util::IdentityHashMap

** Immutable copies retain DAG aliases. New container entries are admitted
** before allocation; existing immutable values remain borrowed from their owner.
internal const class EnerCubixCockpitFreeze
{
  static Obj? value(Obj? source,EnerCubixPreparedOwner output,|Obj->Obj?|? borrow := null,|Obj|? consume := null,Bool consumeParentBeforeChildren := false,|Obj,Obj|? completed := null)
  {
    if(consumeParentBeforeChildren && consume==null) throw ArgErr("cockpitSnapshotConsumeRequired")
    if(source==null || source.isImmutable) return source
    work:=EnerCubixPreparedOwner(output.budget);EnerCubixCockpitFreezer? freezer
    try
    {
      work.hold(18);freezer=EnerCubixCockpitFreezer(output,work,borrow,consume,consumeParentBeforeChildren,completed)
      result:=freezer.copy(source)
      output.hold(2);roots:=Obj?[result]
      output.watch |->Void| {roots.clear}
      return result
    }
    finally {freezer?.clear;work.close}
  }
}

internal class EnerCubixCockpitFreezer
{
  new make(EnerCubixPreparedOwner output,EnerCubixPreparedOwner work,|Obj->Obj?|? borrow,|Obj|? consume,Bool consumeParentBeforeChildren,|Obj,Obj|? completed)
  {this.output=output;this.work=work;this.borrow=borrow;this.consume=consume;this.consumeParentBeforeChildren=consumeParentBeforeChildren;this.completed=completed}
  private EnerCubixPreparedOwner output
  private EnerCubixPreparedOwner work
  private |Obj|? consume
  private |Obj->Obj?|? borrow
  private Bool consumeParentBeforeChildren
  private |Obj,Obj|? completed
  private IdentityHashMap memo := IdentityHashMap()
  Obj? copy(Obj? source)
  {
    work.budget.deadline.check
    if(source==null || source.isImmutable) return source
    if(source isnot Map && source isnot List) throw NotImmutableErr("cockpitSnapshotMutableValue")
    borrowed:=borrow?.call(source)
    if(borrowed!=null)
    {
      if(!borrowed.isImmutable || source.typeof!=borrowed.typeof) throw NotImmutableErr("cockpitSnapshotBorrowedValue")
      return borrowed
    }
    cached:=memo.get(source)
    if(cached is Str) throw NotImmutableErr("cockpitSnapshotCycle")
    if(cached!=null) return cached
    work.hold(3);memo.put(source,"pending")
    node:=EnerCubixPreparedOwner(work.budget);Obj? builder
    try
    {
      size:=source is Map ? ((Map)source).size : ((List)source).size
      node.hold(1+size)
      node.watch |->Void| {if(builder is Map) ((Map)builder).clear;else if(builder is List) ((List)builder).clear;builder=null}
      if(source is Map)
      {
        sourceMap:=(Obj:Obj?)source;target:=sourceMap.dup;builder=target
        // An owned report may retire this parent's links once the admitted
        // private builder holds every child. Each child and the empty source
        // header remain paid until their own original lifetime ends.
        if(consumeParentBeforeChildren) consume.call(source)
        visit:=consumeParentBeforeChildren ? target : sourceMap
        visit.each |Obj? v,Obj k|
        {if(!k.isImmutable) throw NotImmutableErr("cockpitSnapshotMutableKey");target[k]=copy(v)}
      }
      else
      {
        sourceList:=(Obj?[])source;target:=sourceList.dup;builder=target
        if(consumeParentBeforeChildren) consume.call(source)
        visit:=consumeParentBeforeChildren ? target : sourceList
        visit.each |Obj? v,Int i| {target[i]=copy(v)}
      }
      // All children are now immutable. This final shallow copy preserves the
      // input's map/list types and ordering without recopying shared children.
      output.hold(1+size);result:=builder.toImmutable
      memo.put(source,result);completed?.call(source,result)
      if(!consumeParentBeforeChildren) consume?.call(source);return result
    }
    finally {node.close}
  }
  Void clear() {memo.clear}
}

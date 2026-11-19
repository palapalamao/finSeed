using util

** Admit new Folio JSON Map/List entries before the existing parser runs.
** The original parser remains responsible for syntax and value semantics.
internal const class FinEnergyOwnedJson
{
  static Obj? parse(Str text,FinEnergyPreparedOwner output)
  {
    count:=entries(text,output.budget)
    output.hold(2+count);Obj? root
    output.watch |->Void| {clear(root);root=null}
    root=JsonInStream(text.in).readJson;return root
  }
  private static Int entries(Str text,FinEnergyPreparedBudget budget)
  {
    scratch:=FinEnergyPreparedOwner(budget);Int[]? stack;Bool[]? pending
    try
    {
      scratch.hold(8);stack=Int[,];pending=Bool[,]
      count:=0;maxDepth:=0;quoted:=false;escaped:=false
      text.each |Int c,Int i|
      {
        if(i%8192==0) budget.deadline.check
        if(quoted)
        {if(escaped) escaped=false;else if(c=='\\') escaped=true;else if(c=='"') quoted=false;return}
        if(c.isSpace) return
        if(c==',') {if(!stack.isEmpty && stack.last=='[') pending[-1]=true;return}
        if(c==']' || c=='}')
        {
          if(!stack.isEmpty) {stack.removeAt(stack.size-1);pending.removeAt(pending.size-1)}
          return
        }
        if(!stack.isEmpty && stack.last=='[' && pending.last) {count++;pending[-1]=false}
        if(c=='[' || c=='{')
        {
          count++
          if(stack.size==maxDepth) {scratch.hold(2);maxDepth++}
          stack.add(c);pending.add(c=='[')
        }
        else if(c==':') count++
        else if(c=='"') quoted=true
      }
      budget.deadline.check;return count
    }
    finally {stack?.clear;pending?.clear;scratch.close}
  }
  private static Void clear(Obj? value)
  {
    if(value is Map) {((Map)value).each |Obj? v| {clear(v)};((Map)value).clear}
    else if(value is List) {((Obj?[])value).each |Obj? v| {clear(v)};((List)value).clear}
  }
}

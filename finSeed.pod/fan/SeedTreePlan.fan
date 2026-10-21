** Pure tree operations; only Seed records participate, never native FIN assets.
const class SeedTreePlan
{
  static Str[] roots([Str:Obj?][] all, Str[] ids)
  {
    if (ids.isEmpty || ids.size > 1000) throw ArgErr("请选择 1 至 1000 个对象")
    ids=ids.unique
    ids.each |id|
    {
      r:=all.find |x| { x["id"] == id }
      if (r == null || !SeedConfig.nodeKinds.contains(r["kind"])) throw ArgErr("请选择现有的计量树对象")
    }
    return ids.findAll |id|
    {
      seen:=[id]; parent:=all.find |x| { x["id"] == id }?.get("parentId") as Str
      while (parent != null)
      {
        if (seen.contains(parent)) throw ArgErr("管理树存在循环，请先修复")
        if (ids.contains(parent)) return false
        seen.add(parent); parent=all.find |x| { x["id"] == parent }?.get("parentId") as Str
      }
      return true
    }
  }

  static Str:Obj? deletion([Str:Obj?][] all, Str[] ids)
  {
    top:=roots(all,ids); selected:=top.dup
    for (i:=0;i<selected.size;i++)
    {
      id:=selected[i]
      all.findAll |r| { r["parentId"] == id && SeedConfig.nodeKinds.contains(r["kind"]) }.each |r|
      {
        child:=r["id"].toStr
        if (selected.contains(child)) throw ArgErr("管理树存在循环，请先修复")
        selected.add(child)
      }
      if (selected.size > 5000) throw ArgErr("单次删除最多 5000 个配置对象")
    }
    blockers:=[Str:Obj?][,]
    all.each |r|
    {
      if (selected.contains(r["id"]) || ["alarm","job"].contains(r["kind"])) return
      refs:=selected.findAll |id| { SeedConfig.references(r,id) }
      if (!refs.isEmpty) blockers.add(["id":r["id"],"kind":r["kind"],"name":r["name"],"referencedIds":refs])
    }
    return ["roots":top,"records":all.findAll |r| { selected.contains(r["id"]) },"blockers":blockers]
  }

  static [Str:Obj?][] move([Str:Obj?][] all, Str[] ids, Str? parent)
  {
    top:=roots(all,ids)
    edits:=top.map |id->[Str:Obj?]| { rec:=all.find |r| { r["id"] == id }.dup; rec["parentId"]=parent; return rec }
    candidate:=all.findAll |r| { !top.contains(r["id"]) }.dup.addAll(edits)
    edits.each |r| { SeedConfig.validate(r,candidate) }
    return edits
  }
}

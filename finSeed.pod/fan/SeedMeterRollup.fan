using haystack
using folio

** Recalculate direct-child meter sums from one current-value snapshot.
internal class SeedMeterRollup
{
  ** Current values are transient: no bus writes and no history writes.
  static Void update(Folio db, DateTime ts:=DateTime.now)
  {
    equips:=db.readAllList(Filter("equip and seed and seedKind"))
    refs:=equips.map |eq->Ref?| { eq["seedPointRef"] as Ref }.exclude |r| { r == null }.unique
    points:=db.readByIdsList((Ref[])refs,false).exclude |p| { p == null }
    sums:=calculate(equips,(Dict[])points)
    targets:=Ref[,]
    equips.each |eq| { if (sums.containsKey(eq.id.id) && eq["seedPointRef"] is Ref) targets.add(eq["seedPointRef"]) }
    diffs:=Diff[,]
    // Release points after detaching/rebinding a parent. An old computed value
    // must not become a leaf input when the same graph changes shape.
    db.readAllList(Filter("point and seedRollupRef")).each |p|
    {
      if (targets.contains(p.id)) return
      changes:=Str:Obj?["seedRollupRef":Remove.val,"seedRollupAt":Remove.val,"seedRollupStatus":Remove.val]
      owner:=equips.find |eq| { eq.id == p["seedRollupRef"] }
      if (owner?.get("seedAutoSum") == true && !collected(p))
      {
        changes["curVal"]=Remove.val; changes["curStatus"]="fault"; changes["curErr"]="rollupDetached"
        for (i:=0;i<points.size;i++) { if (points[i].id == p.id) points[i]=Etc.makeDict(Etc.dictToMap(p).set("curVal",null).set("curStatus","fault")) }
      }
      diffs.add(Diff(p,Etc.makeDict(changes),Diff.transient))
    }
    // Re-evaluate if releasing a former parent changed a leaf snapshot.
    if (!diffs.isEmpty) sums=calculate(equips,(Dict[])points)
    equips.each |eq|
    {
      sum:=sums[eq.id.id]
      if (sum == null) return
      point:=points.find |p| { p.id == eq["seedPointRef"] }
      // Never mutate another equipment's source, even after manual tag edits.
      if (point == null || point["equipRef"] != eq.id || !point.has("point") || point.has("seedComputed")) return
      ok:=sum["status"] == "ok"
      changes:=Str:Obj?["seedRollupRef":eq.id,"seedRollupAt":ts,"seedRollupStatus":sum["status"],"curVal":ok ? sum["val"] : Remove.val,"curStatus":ok ? "ok" : "fault","curErr":ok ? Remove.val : "rollup:"+sum["status"].toStr]
      diffs.add(Diff(point,Etc.makeDict(changes),Diff.transient))
    }
    if (!diffs.isEmpty) db.commitAll(diffs)
  }

  private Str:Dict meters := [:]
  private Str:Dict sources := [:]
  private Str:Str[] children := [:]
  private Str:Dict values := [:]
  private Str:Bool visiting := [:]

  private new make(Dict[] equips, Dict[] points)
  {
    equips.each |eq|
    {
      if (eq.has("equip") && eq.has("seed") && ["meter","totalMeter"].contains(eq["seedKind"]) && !eq.has("seedCanonicalRef")) meters[eq.id.id]=eq
    }
    points.each |p| { sources[p.id.id]=p }
    meters.each |eq,id|
    {
      parent:=eq["seedMeterParentRef"] as Ref
      if (parent == null || !meters.containsKey(parent.id)) return
      if (!children.containsKey(parent.id)) children[parent.id]=Str[,]
      children[parent.id].add(id)
    }
  }

  static Str:Dict calculate(Dict[] equips, Dict[] points)
  {
    calc:=SeedMeterRollup(equips,points)
    out:=Str:Dict[:]
    calc.children.keys.sort.each |id|
    {
      eq:=calc.meters[id]; point:=calc.sources[(eq["seedPointRef"] as Ref)?.id ?: ""]
      if (enabled(eq,point)) out[id]=calc.value(id)
    }
    return out
  }

  private Dict value(Str id)
  {
    if (values.containsKey(id)) return values[id]
    if (visiting[id] == true) return result("cycle")
    visiting[id]=true
    answer:=compute(id)
    visiting.remove(id); values[id]=answer
    return answer
  }

  private Dict compute(Str id)
  {
    eq:=meters[id]; point:=sources[(eq["seedPointRef"] as Ref)?.id ?: ""]
    if (point == null || !point.has("point") || point["equipRef"] != eq.id || point.has("seedComputed")) return result("invalidPoint")
    unit:=Unit.fromStr(point["unit"] as Str ?: "",false)
    if (unit == null) return result("incompatibleUnit")
    // A measured intermediate meter contributes its own reading, preserving
    // the measured boundary even if it has configured downstream meters.
    parts:=enabled(eq,point) ? children[id] : null
    if (parts == null)
    {
      status:=point["curStatus"] as Str
      n:=point["curVal"] as Number
      if ((status != null && status != "ok") || n == null || SeedMath.num(n.toFloat) == null) return result("missing")
      factor:=SeedMath.unitFactor(n.unit?.symbol ?: unit.symbol,unit.symbol)
      return factor == null ? result("incompatibleUnit") : result("ok",Number(n.toFloat*factor,unit))
    }
    sum:=0f
    for (i:=0;i<parts.size;i++)
    {
      child:=meters[parts[i]]
      if (child["seedCategoryRef"] != eq["seedCategoryRef"]) return result("incompatibleCategory")
      v:=value(parts[i])
      if (v["status"] != "ok") return v
      n:=(Number)v["val"]
      factor:=SeedMath.unitFactor(n.unit.symbol,unit.symbol)
      if (factor == null) return result("incompatibleUnit")
      sum+=n.toFloat*factor
    }
    return SeedMath.num(sum) == null ? result("missing") : result("ok",Number(sum,unit))
  }

  private static Dict result(Str status, Number? val:=null)
  {
    tags:=Str:Obj?["status":status]
    if (val != null) tags["val"]=val
    return Etc.makeDict(tags)
  }

  private static Bool enabled(Dict equip, Dict? point)
  { equip["seedAutoSum"] == true && !collected(point) }

  ** A collection source always takes precedence over the calculation flag.
  static Bool collected(Dict? point)
  {
    if (point == null) return false
    return point.eachWhile |v,name->Obj?| { name.endsWith("ConnRef") ? true : null } == true
  }
}

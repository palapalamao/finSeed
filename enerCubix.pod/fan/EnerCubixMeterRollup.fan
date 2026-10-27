using haystack
using folio

** Recalculate direct-child meter sums from one current-value snapshot.
internal class EnerCubixMeterRollup
{
  ** Missing settings retain the one-second default, including existing projects.
  static Int intervalSeconds(Obj? value := null)
  {
    if (value == null) return 1
    if (value isnot Int && value isnot Float && value isnot Decimal) throw ArgErr("计算总表更新间隔必须为 1 至 3600 的整数秒数")
    n:=EnerCubixConfig.number(value)
    if (n.isNaN || n < 1f || n > 3600f || n != n.floor) throw ArgErr("计算总表更新间隔必须为 1 至 3600 的整数秒数")
    return n.toInt
  }

  static Int configuredInterval(Folio db)
  {
    rec:=db.readAllList(Filter("enerCubix and enerCubixKind == \"settings\"")).first
    return intervalSeconds(rec == null ? null : EnerCubixRepo.decode(rec)["meterRollupSeconds"])
  }

  ** Monotonic ticks avoid wall-clock changes; the FIN extension actor serializes runs.
  static Bool isDue(Int previous, Int now, Int seconds)
  { previous < 0 || now-previous >= seconds*1sec.ticks }

  ** Current values are transient: no bus writes and no history writes.
  static Void update(Folio db, DateTime ts:=DateTime.now)
  {
    EnerCubixMeterTimeline.initialize(db,ts)
    equips:=db.readAllList(Filter("enerCubix and enerCubixKind"))
    refs:=configuredMeters(equips).dup.addAll(equips.findAll |r| {r["enerCubixKind"] == "sensor"}).map |eq->Ref?| { eq["enerCubixPointRef"] as Ref }.exclude |r| { r == null }.unique
    points:=db.readByIdsList((Ref[])refs,false).exclude |p| { p == null }
    sums:=continuous(db,equips,(Dict[])points,ts)
    targets:=Ref[,]
    equips.each |eq| { if (sums.containsKey(eq.id.id) && eq["enerCubixPointRef"] is Ref) targets.add(eq["enerCubixPointRef"]) }
    diffs:=Diff[,]; stateDiffs:=Diff[,]
    // Release points after detaching/rebinding a parent. An old computed value
    // must not become a leaf input when the same graph changes shape.
    db.readAllList(Filter("point and enerCubixRollupRef")).each |p|
    {
      if (targets.contains(p.id)) return
      released:=EnerCubixMeterContinuity.release(db,p,ts)
      if (released != null) stateDiffs.add(released)
      changes:=Str:Obj?["enerCubixRollupRef":Remove.val,"enerCubixRollupAt":Remove.val,"enerCubixRollupStatus":Remove.val]
      owner:=equips.find |eq| { eq.id == p["enerCubixRollupRef"] }
      if (owner?.get("enerCubixAutoSum") == true && !collected(p))
      {
        changes["curVal"]=Remove.val; changes["curStatus"]="fault"; changes["curErr"]="rollupDetached"
        for (i:=0;i<points.size;i++) { if (points[i].id == p.id) points[i]=Etc.makeDict(Etc.dictToMap(p).set("curVal",null).set("curStatus","fault")) }
      }
      diffs.add(Diff(p,Etc.makeDict(changes),Diff.transient))
    }
    // Re-evaluate if releasing a former parent changed a leaf snapshot.
    if (!diffs.isEmpty) sums=continuous(db,equips,(Dict[])points,ts)
    equips.each |eq|
    {
      sum:=sums[eq.id.id]
      if (sum == null) return
      point:=points.find |p| { p.id == eq["enerCubixPointRef"] }
      // Never mutate another equipment's source, even after manual tag edits.
      if (!ownsPoint(eq,point)) return
      owner:=db.readById(point["equipRef"],false)
      if (owner == null || !owner.has("equip")) return
      ok:=sum["status"] == "ok"
      if (sum.has("state"))
      {
        stateChange:=EnerCubixMeterContinuity.change(db,point,sum,ts)
        if (stateChange != null) stateDiffs.add(stateChange)
      }
      changes:=Str:Obj?["enerCubixRollupRef":eq.id,"enerCubixRollupAt":ts,"enerCubixRollupStatus":sum["status"],"enerCubixRollupHasGap":sum["hasGap"] == true,"curVal":ok ? sum["val"] : Remove.val,"curStatus":ok ? "ok" : "fault","curErr":ok ? Remove.val : "rollup:"+sum["status"].toStr]
      diffs.add(Diff(point,Etc.makeDict(changes),Diff.transient))
    }
    // Folio prohibits mixed persistent/transient commitAll. Persistent state is
    // authoritative; current readings are a reconstructible cache after restart.
    if (!stateDiffs.isEmpty) db.commitAll(stateDiffs)
    if (!diffs.isEmpty) db.commitAll(diffs)
  }

  private Str:Dict meters := [:]
  private Str:Dict sources := [:]
  private Str:Str[] children := [:]
  private Str:Dict values := [:]
  private Str:Dict expressions := [:]
  private Str:Dict sensors := [:]
  private Str:Str categoryUnits := [:]
  private Str:Bool visiting := [:]
  private Folio? continuityDb
  private DateTime continuityAt:=DateTime.now

  private new make(Dict[] equips, Dict[] points)
  {
    equips.findAll |r| {r["enerCubixKind"] == "expression"}.each |r| {expressions[r.id.id]=r}
    equips.findAll |r| {r["enerCubixKind"] == "sensor"}.each |r| {sensors[r.id.id]=r}
    equips.findAll |r| {r["enerCubixKind"] == "category"}.each |r| {categoryUnits[r.id.id]=EnerCubixRepo.decode(r)["unit"]?.toStr ?: ""}
    configuredMeters(equips).each |eq|
    {
      meters[eq.id.id]=eq
    }
    points.each |p| { sources[p.id.id]=p }
    meters.each |eq,id|
    {
      parent:=eq["enerCubixMeterParentRef"] as Ref
      if (parent == null || !meters.containsKey(parent.id)) return
      if (!children.containsKey(parent.id)) children[parent.id]=Str[,]
      children[parent.id].add(id)
    }
  }

  static Str:Dict calculate(Dict[] equips, Dict[] points)
  {
    calc:=EnerCubixMeterRollup(equips,points)
    out:=Str:Dict[:]
    calc.meters.keys.sort.each |id|
    {
      eq:=calc.meters[id]; point:=calc.sources[(eq["enerCubixPointRef"] as Ref)?.id ?: ""]
      if (enabled(eq,point) && (calc.children.containsKey(id) || eq["enerCubixExpressionRef"] is Ref)) out[id]=calc.value(id)
    }
    return out
  }

  private static Str:Dict continuous(Folio db, Dict[] equips, Dict[] points, DateTime at)
  {
    calc:=EnerCubixMeterRollup(equips,points); calc.continuityDb=db; calc.continuityAt=at
    out:=Str:Dict[:]
    calc.meters.keys.sort.each |id|
    {
      eq:=calc.meters[id]; point:=calc.sources[(eq["enerCubixPointRef"] as Ref)?.id ?: ""]
      if (enabled(eq,point) && (calc.children.containsKey(id) || eq["enerCubixExpressionRef"] is Ref)) out[id]=calc.value(id)
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
    eq:=meters[id]; point:=sources[(eq["enerCubixPointRef"] as Ref)?.id ?: ""]
    if (!ownsPoint(eq,point)) return result("invalidPoint")
    if (meters.vals.findAll |m| { m["enerCubixPointRef"] == point.id }.size != 1) return result("ambiguousPoint")
    unit:=Unit.fromStr(point["unit"] as Str ?: "",false)
    if (unit == null) return result("incompatibleUnit")
    exprId:=eq["enerCubixExpressionRef"] as Ref
    if (exprId != null && !collected(point))
    {
      expression:=expressions[exprId.id]
      if (expression == null) return result("missingExpression")
      config:=EnerCubixRepo.decode(expression)
      inputs:=Str:EnerCubixValue[:]
      Map vars:=config["variables"] as Map ?: Str:Obj?[:]
      vars.each |ref,name|
      {
        variableId:=ref.toStr
        source:=meters[variableId] ?: sensors[variableId]
        if (source == null) {inputs[name.toStr]=EnerCubixValue(null,"missingSource");return}
        sourcePoint:=sources[(source["enerCubixPointRef"] as Ref)?.id ?: ""]
        input:=sensors.containsKey(variableId) ? (sourcePoint == null || !ownsPoint(source,sourcePoint) || sourcePoint["curStatus"] != "ok" ? result("missing") : result("ok",sourcePoint["curVal"] as Number)) : value(variableId)
        n:=input["val"] as Number
        sourceUnit:=n?.unit?.symbol ?: (sourcePoint?.get("unit") as Str ?: "")
        categoryUnit:=sensors.containsKey(variableId) ? sourceUnit : (categoryUnits[(source["enerCubixCategoryRef"] as Ref)?.id ?: ""] ?: sourceUnit)
        factor:=EnerCubixMath.unitFactor(sourceUnit,categoryUnit)
        inputs[name.toStr]=input["status"] == "ok" && n != null && factor != null ? EnerCubixValue(n.toFloat*factor,"ok") : EnerCubixValue(null,"missing")
      }
      computed:=EnerCubixExpression(config["formula"]?.toStr ?: "",inputs).calculate
      categoryUnit:=categoryUnits[(eq["enerCubixCategoryRef"] as Ref)?.id ?: ""] ?: unit.symbol
      factor:=EnerCubixMath.unitFactor(categoryUnit,unit.symbol)
      if (factor == null) return result("incompatibleUnit")
      return computed.value == null ? result(computed.quality) : result("ok",Number(computed.value*factor,unit))
    }

    // A measured intermediate meter contributes its own reading, preserving
    // the measured boundary even if it has configured downstream meters.
    parts:=enabled(eq,point) ? children[id] : null
    if (parts == null)
    {
      status:=point["curStatus"] as Str
      n:=point["curVal"] as Number
      if ((status != null && status != "ok") || n == null || EnerCubixMath.num(n.toFloat) == null) return result("missing")
      factor:=EnerCubixMath.unitFactor(n.unit?.symbol ?: unit.symbol,unit.symbol)
      return factor == null ? result("incompatibleUnit") : result("ok",Number(n.toFloat*factor,unit))
    }
    sum:=0f
    inputs:=[Str:Obj?][,]
    for (i:=0;i<parts.size;i++)
    {
      child:=meters[parts[i]]
      if (child["enerCubixCategoryRef"] != eq["enerCubixCategoryRef"]) return result("incompatibleCategory")
      v:=value(parts[i])
      if (v["status"] != "ok")
      {
        if (continuityDb == null) return v
        inputs.add(["id":child.id.id,"signature":(child["enerCubixPointRef"] as Ref)?.id,"value":null,"quality":v["status"]]); continue
      }
      n:=(Number)v["val"]
      factor:=EnerCubixMath.unitFactor(n.unit.symbol,unit.symbol)
      if (factor == null) return result("incompatibleUnit")
      sum+=n.toFloat*factor
      childPoint:=sources[(child["enerCubixPointRef"] as Ref)?.id ?: ""]
      rollover:=childPoint?.get("enerCubixCleaningRollover") as Number
      inputs.add(["id":child.id.id,"signature":(child["enerCubixPointRef"] as Ref)?.id,"value":n.toFloat*factor,"quality":"ok","rollover":rollover == null ? null : rollover.toFloat*factor])
    }
    if (continuityDb != null)
      return EnerCubixMeterContinuity.advance(point,continuityDb.readById(EnerCubixMeterContinuity.key(point.id),false),inputs,continuityAt)
    return EnerCubixMath.num(sum) == null ? result("missing") : result("ok",Number(sum,unit))
  }

  private static Dict result(Str status, Number? val:=null)
  {
    tags:=Str:Obj?["status":status]
    if (val != null) tags["val"]=val
    return Etc.makeDict(tags)
  }

  private static Bool enabled(Dict equip, Dict? point)
  { (equip["enerCubixAutoSum"] == true || equip["enerCubixExpressionRef"] is Ref) && !collected(point) }

  private static Bool ownsPoint(Dict meter, Dict? point)
  { point != null && point.has("point") && (!point.has("enerCubixComputed") || point.has("enerCubixFormulaResult")) && point["equipRef"] is Ref && (!meter.has("equip") || point["equipRef"] == meter.id) }

  ** Retained bindings use the same native point; reading them never migrates data.
  private static Dict[] configuredMeters(Dict[] records)
  {
    meters:=records.findAll |r| { r.has("enerCubix") && ["meter","totalMeter"].contains(r["enerCubixKind"]) && !r.has("enerCubixCanonicalRef") }
    nativePoints:=meters.findAll |r| { r.has("equip") }.map |r->Obj?| { r["enerCubixPointRef"] }
    return meters.findAll |r| { r.has("equip") || !nativePoints.contains(r["enerCubixPointRef"]) }.map |r->Dict|
    {
      if (r.has("equip"))
      {
        return r
      }
      tags:=Etc.dictToMap(r)
      tags["enerCubixAutoSum"]=EnerCubixRepo.decode(r)["autoSum"] == true
      return Etc.makeDict(tags)
    }
  }

  ** A collection source always takes precedence over the calculation flag.
  static Bool collected(Dict? point)
  {
    if (point == null) return false
    return point.eachWhile |v,name->Obj?| { name.endsWith("ConnRef") ? true : null } == true
  }
}

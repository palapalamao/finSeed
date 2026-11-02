** Optional COP projection. Preparation freezes scoped configuration; projection
** consumes the shared primary-history union through the existing COP engine.
internal class EnerCubixCockpitEfficiency
{
  ** Hidden group members can only leave an opaque incomplete-boundary marker.
  static [Str:Obj?][] visible([Str:Obj?][] visible,[Str:Obj?][] all)
  {
    [Str:Obj?][] out:=visible.map |r->[Str:Obj?]| {r.dup}
    all.findAll |r| {!readable(r) && ["meter","totalMeter"].contains(r["kind"])}.each |hidden|
    {
      seen:=Str[,];cursor:=hidden["parentId"] as Str
      while (cursor != null && !seen.contains(cursor))
      {
        seen.add(cursor);target:=out.find |r| {r["id"] == cursor}
        if (target != null) target["_copBoundaryUnavailable"]=true
        cursor=all.find |r| {r["id"] == cursor}?.get("parentId") as Str
      }
    }
    return out
  }

  static Str:Obj? prepare(Str:Obj? q, [Str:Obj?][] records, Str project, Str[] categories)
  {
    dim:=EnerCubixDimension(q["dimension"].toStr,records,q["spaceSource"] == "fin")
    ctx:=EnerCubixContext(records,[Str:Obj?][,],TimeZone.fromStr(q["tz"].toStr),dim)
    selected:=EnerCubixMath.strings(q["nodeIds"])
    scoped:=selected.dup
    selected.each |id| {if (dim.scope(id)) scoped.addAll(dim.members(id).map |m->Str| {m["id"].toStr})}
    configs:=records.findAll |r|
    {
      if (r["kind"] != "cop" || !readable(r)) return false
      return ["numeratorId","denominatorId"].any |key|
      {
        id:=r[key] as Str ?: ""
        return scoped.contains(id) || side(ctx,id).any |m| {scoped.contains(m["id"])}
      }
    }.sort |a,b| {a["id"].toStr <=> b["id"].toStr}
    if (configs.size > 20) throw EnerCubixHttpErr(422,"COP_CONFIGURATION_LIMIT","cockpitCopConfigurationLimit")
    prepared:=[Str:Obj?][,]; meters:=[Str:Obj?][,]; devices:=[Str:Obj?][,]; configuration:=[Str:Obj?][,]; unavailable:=false
    admitted:=categories.dup.unique
    configs.each |config|
    {
      a:=ctx.byId[config["numeratorId"] as Str ?: ""];b:=ctx.byId[config["denominatorId"] as Str ?: ""]
      if ((a != null && !readable(a)) || (b != null && !readable(b))) {unavailable=true;return}
      aa:=a == null ? [Str:Obj?][,] : side(ctx,a["id"].toStr)
      bb:=b == null ? [Str:Obj?][,] : side(ctx,b["id"].toStr)
      both:=aa.dup.addAll(bb)
      if (both.any |m| {!readable(m)}) {unavailable=true;return}
      refs:=[config].addAll(both)
      if (a != null) refs.add(a)
      if (b != null) refs.add(b)
      refs.each |r| {checkRef(r["id"] as Str,project)}
      reason:=a == null || b == null || config["configurationError"] != null ? "COP_INVALID_CONFIGURATION" : null
      if (reason == null && (a["_copBoundaryUnavailable"] == true || b["_copBoundaryUnavailable"] == true)) reason="COP_BOUNDARY_UNAVAILABLE"
      if (reason == null && (aa.isEmpty || bb.isEmpty)) reason="COP_INVALID_CONFIGURATION"
      if (reason == null && both.any |m| {cat:=ctx.byId[m["categoryId"] as Str ?: ""];return cat == null || !readable(cat) || m["configurationError"] != null}) reason="COP_INVALID_CONFIGURATION"
      if (reason == null && both.any |m| {p:=m["pointId"] as Str;return p == null || p.isEmpty || m["nativeSourceMissing"] == true}) reason="COP_PRIMARY_REQUIRED"
      ac:=aa.map |m->Str| {m["categoryId"] as Str ?: ""}.unique
      bc:=bb.map |m->Str| {m["categoryId"] as Str ?: ""}.unique
      if (reason == null && (ac.size != 1 || bc.size != 1)) reason="COP_INCOMPATIBLE_UNITS"
      au:=ac.size == 1 ? ctx.unit(a["id"].toStr,ac.first,"energy") : ""
      bu:=bc.size == 1 ? ctx.unit(b["id"].toStr,bc.first,"energy") : ""
      factor:=au.isEmpty || bu.isEmpty ? null : EnerCubixMath.unitFactor(au,bu)
      // COP is an energy ratio, not a ratio of arbitrary matching dimensions.
      if (reason == null && (factor == null || EnerCubixMath.unitFactor(au,"kWh") == null)) reason="COP_INCOMPATIBLE_UNITS"
      ab:=coverage(aa,records);cb:=coverage(bb,records)
      if (reason == null && (ab.isEmpty || cb.isEmpty || ab != cb)) reason="COP_BOUNDARY_MISMATCH"
      points:=both.map |m->Str| {m["pointId"] as Str ?: ""}
      if (reason == null && points.unique.size != points.size) reason="COP_DUPLICATE_SOURCE"
      needed:=ac.dup.addAll(bc).unique
      if (reason == null && admitted.dup.addAll(needed).unique.size > 2) reason="COP_CATEGORY_LIMIT"
      originals:=[Str:Obj?][,]
      if (reason == null)
      {
        points.each |p| {checkRef(p,project)}
        originals=originalSide(ctx,a["id"].toStr).addAll(originalSide(ctx,b["id"].toStr))
        refs.addAll(originals)
      }
      both.each |m|
      {
        cat:=ctx.byId[m["categoryId"] as Str ?: ""];if (cat != null && readable(cat)) refs.add(cat)
        boundary:=service(m,records);if (boundary != null) refs.add(boundary)
      }
      if (refs.any |r| {!readable(r)}) {unavailable=true;return}
      refs.each |r| {checkRef(r["id"] as Str,project);checkRef(r["nativeSourceId"] as Str,project)}
      if (reason == null)
      {
        admitted.addAll(needed);admitted=admitted.unique
        meters.addAll(both);devices.addAll(originals)
      }
      configuration.addAll(refs)
      prepared.add(["config":config,"numerator":a,"denominator":b,"numeratorUnit":au,"denominatorUnit":bu,"factor":factor,"reason":reason,"coverageIds":ab])
    }
    return ["items":prepared,"meters":meters.unique,"devices":devices.unique,"configuration":configuration.unique,"opaqueUnavailable":unavailable,"request":q,"records":records]
  }

  static Void attach(Str:Obj? prepared,[Str:Obj?][] histories,Str:Obj? boundary,Str:Obj? reports,Str:Obj? modules,|Str->Str:Obj?|? preparedCop := null)
  {
    try
    {
      q:=(Str:Obj?)prepared["request"];rs:=([Str:Obj?][])prepared["records"]
      EnerCubixContext? ctx
      if(preparedCop==null)
      {
        dim:=EnerCubixDimension(q["dimension"].toStr,rs,q["spaceSource"] == "fin")
        ctx=EnerCubixContext(rs,EnerCubixKnownUsage.clip(EnerCubixCockpitMetrics.histories(q,histories),DateTime.fromIso(q["asOf"].toStr)),TimeZone.fromStr(q["tz"].toStr),dim)
      }
      zone:=TimeZone.fromStr(q["tz"].toStr)
      from:=DateTime.fromIso(q["from"].toStr).toTimeZone(zone);to:=DateTime.fromIso(q["to"].toStr).toTimeZone(zone)
      items:=[Str:Obj?][,]
      EnerCubixMath.maps(prepared["items"]).each |p|
      {
        config:=(Str:Obj?)p["config"];id:=config["id"].toStr;reason:=p["reason"] as Str
        numerator:=EnerCubixValue();denominator:=EnerCubixValue();ratio:=EnerCubixValue();result:=Str:Obj?[:]
        if(preparedCop!=null)
        {
          data:=preparedCop(id)
          numerator=(EnerCubixValue)data["numerator"];denominator=(EnerCubixValue)data["denominator"];ratio=(EnerCubixValue)data["ratio"];result=(Str:Obj?)data["report"]
        }
        else
        {
        report:=EnerCubixReport(ctx,q.dup.set("kind","cop"),from,to,"cop",q["period"].toStr,"energy")
        line:=report.line(id,"")
        numerator=EnerCubixValue.sum(line.ticks.map |t->EnerCubixValue| {t.numerator ?: EnerCubixValue()})
        denominator=EnerCubixValue.sum(line.ticks.map |t->EnerCubixValue| {t.denominator ?: EnerCubixValue()})
        // Preserve actual quantities/units; normalize only the ratio operands.
        factor:=EnerCubixMath.num(p["factor"]) ?: 1f
        line.ticks.each |t|
        {
          t.numerator=t.numerator?.scale(factor)
          if (reason != null) t.numerator=EnerCubixValue(null,reason)
          else if (t.numerator?.value == null || t.denominator?.value == null || t.numerator?.reliable != true || t.denominator?.reliable != true)
            t.numerator=EnerCubixValue(null,EnerCubixValue.worse(t.numerator?.quality ?: "missing",t.denominator?.quality ?: "missing"),t.numerator?.sources ?: Str[,])
        }
        ratio=line.total
        if (DateTime.fromIso(q["asOf"].toStr) < to) ratio=EnerCubixValue(null,"COP_INCOMPLETE_HISTORY",ratio.sources)
        result=report.finish([line])
        if (ratio.value == null && reason != null)
        {
          numerator=EnerCubixValue(null,reason);denominator=EnerCubixValue(null,reason)
        }
        }
        ref:="cop:"+id
        item:=Str:Obj?["configId":id,"name":config["name"] ?: id,"configRef":["id":id,"mod":config["mod"]],"numerator":metric("numerator",numerator,p["numeratorUnit"].toStr,boundary),"denominator":metric("denominator",denominator,p["denominatorUnit"].toStr,boundary),"ratio":metric("cop",ratio,"COP",boundary),"from":q["from"],"to":q["to"],"asOf":q["asOf"],"coverageIds":p["coverageIds"],"reportRef":ref]
        ["actualEfficiency","baselineEfficiency"].each |key| {if (config[key] != null) item[key]=config[key]}
        reports[ref]=result;items.add(item)
      }
      valid:=items.findAll |item| {((Map)item["ratio"])["value"] != null}
      reason:=items.isEmpty ? (prepared["opaqueUnavailable"] == true ? "COP_CONFIGURATION_UNAVAILABLE" : "COP_NOT_CONFIGURED") : "COP_UNAVAILABLE"
      modules["efficiency"]=["status":items.isEmpty || valid.isEmpty ? "unavailable" : (valid.size == items.size && prepared["opaqueUnavailable"] != true ? "ok" : "partial"),"boundaryId":boundary["id"],"data":["items":items],"reasonCodes":valid.size == items.size && !items.isEmpty ? Str[,] : [reason]]
    }
    catch (EnerCubixHttpErr e) {throw e}
    catch (Err e) {modules["efficiency"]=EnerCubixCockpitFlow.error}
  }

  private static Str:Obj? metric(Str id,EnerCubixValue v,Str unit,Str:Obj? boundary)
  {["id":id,"value":v.value,"valueType":v.valueType,"completeValue":v.reliable ? v.value : null,"knownValue":null,"valueBasis":v.value == null || !v.reliable ? "unavailable" : "complete","unit":unit,"quality":v.quality,"sourceIds":v.sources,"reasonCodes":v.value == null || !v.reliable ? [v.quality] : Str[,],"boundaryId":boundary["id"]]}
  private static [Str:Obj?][] side(EnerCubixContext ctx,Str id)
  {ctx.categories(id).map |c->[Str:Obj?][]| {ctx.scopeMeters(id,c)}.flatten.unique}
  private static [Str:Obj?][] originalSide(EnerCubixContext ctx,Str id,Str[] path := Str[,])
  {
    r:=ctx.byId[id];if (r == null || path.contains(id)) return [Str:Obj?][,]
    if (["meter","totalMeter"].contains(r["kind"])) return [r]
    if (ctx.dimension?.scope(id) == true) return ctx.dimension.members(id)
    if (r["kind"] != "group") return [Str:Obj?][,]
    return (ctx.children[id] ?: [Str:Obj?][,]).findAll |m| {ctx.included(m)}.map |m->[Str:Obj?][]| {originalSide(ctx,m["id"].toStr,path.dup.add(id))}.flatten.unique
  }
  private static Bool readable(Str:Obj? r) {r["_comparisonReadable"] != false && r["_comparisonPointReadable"] != false && r["nativeHidden"] != true}
  private static [Str:Obj?]? service(Str:Obj? meter,[Str:Obj?][] records)
  {
    // Explicit service coverage only. Native tree/floor placement is not proof.
    id:=meter["areaSource"] == "space" ? (meter["areaSpaceId"] as Str) : (meter["spaceId"] as Str)
    return records.find |r| {r["kind"] == "space" && (r["id"] == id || (id != null && r["nativeSourceId"] == id)) && readable(r) && ["site","floor"].contains(r["nativeSourceKind"])}
  }
  private static Str[] coverage([Str:Obj?][] meters,[Str:Obj?][] records)
  {
    refs:=meters.map |m->[Str:Obj?]?| {service(m,records)}
    if (refs.isEmpty || refs.any |r| {r == null}) return Str[,]
    return refs.map |[Str:Obj?]? r->Str| {r["nativeSourceId"] as Str ?: r["id"].toStr}.unique.sort
  }
  private static Void checkRef(Str? id,Str project)
  {if (id != null && (id.isEmpty || id.trim != id || id.any |c| {c.isSpace || c < 32} || (id.startsWith("p:") && !id.startsWith("p:"+project+":r:")))) throw ArgErr("cockpitRef")}
}

** Historical topology is evidence supplied by the native adapter, never inferred
** from today's parent tags. Readings remain meter-owned in every segment.
internal const class EnerCubixTemporalReport
{
  static [Str:Obj?][] recordsFor([Str:Obj?][] current, Str:Obj? segment)
  {
    if (segment["known"] != true) return current
    byId:=Str:[Str:Obj?][:]
    current.findAll |r| { !["meter","totalMeter","sensor"].contains(r["kind"]) }.each |r| { byId[r["id"].toStr]=r }
    captured:=EnerCubixMath.maps(segment["records"])
    aliases:=Str:Str[:]
    captured.findAll |r| { r["nativeEquip"] != true && ["meter","totalMeter","sensor"].contains(r["kind"]) && r["pointId"] != null }.each |old|
    {
      matches:=captured.findAll |r| { r["nativeEquip"] == true && r["pointId"] == old["pointId"] }
      if (matches.size == 1) aliases[old["id"].toStr]=matches.first["id"].toStr
    }
    captured.findAll |r| { !aliases.containsKey(r["id"].toStr) }.each |r|
    {
      normalized:=EnerCubixNativeEquip.rewrite(r,aliases)
      byId[normalized["id"].toStr]=normalized
    }
    return byId.vals
  }

  static Str:Obj? report(Str:Obj? request, [Str:Obj?][] current, [Str:Obj?][] histories)
  {
    from:=DateTime.fromIso(request["from"].toStr); to:=DateTime.fromIso(request["to"].toStr)
    if (to <= from) throw ArgErr("to must be later than from")
    if ((to-from).ticks/1hr.ticks > 100000) throw ArgErr("Report range exceeds 100000 hours")
    if (request["kind"] == "energyFlow")
    {
      if (request["dimension"] != "metering" || request["metric"] != "energy" || request["perArea"] == true)
        throw ArgErr("能流图仅支持计量视角的区间能耗，不支持费用或面积归一化")
      category:=request["categoryId"] as Str ?: ""
      cats:=current.dup
      EnerCubixMath.maps(request["meterHistorySegments"]).each |s| { cats.addAll(EnerCubixMath.maps(s["records"])) }
      if (!cats.any |r| { r["id"] == category && r["kind"] == "category" && !(r["unit"]?.toStr ?: "").isEmpty })
        throw ArgErr("能流图请选择有计量单位的能源类型")
    }
    supplied:=EnerCubixMath.maps(request["meterHistorySegments"])
    overview:=request["kind"] == "energyFlow" ? EnerCubixFlowOverview.build(request,current,histories) : null
    if (request["kind"] == "energyFlow")
      supplied=supplied.map |s->[Str:Obj?][]| { flowSections(request,current,histories,s,from,to) }.flatten
    reports:=[Str:Obj?][,]; segments:=[Str:Obj?][,]; cursor:=from
    supplied.each |segment|
    {
      start:=DateTime.fromIso(segment["from"].toStr); end:=DateTime.fromIso(segment["to"].toStr)
      if (end <= from || start >= to) return
      if (start < from) start=from
      if (end > to) end=to
      if (start.ticks != cursor.ticks || end <= start) throw ArgErr("历史计量关系时段必须连续且不能重叠")
      req:=request.dup; req.remove("meterHistorySegments"); req["from"]=start.toIso; req["to"]=end.toIso
      rs:=recordsFor(current,segment)
      available:=EnerCubixMath.strings(req["nodeIds"]).all |id| { rs.any |r| { r["id"] == id } }
      if (segment["known"] != true && request["kind"] == "energyFlow") rs=EnerCubixFlowOverview.inventory(request,current)
      result:=segment["known"] == true && available ? EnerCubixEngine.report(req,rs,histories) : unknown(req,rs,histories)
      reports.add(result)
      entry:=Str:Obj?["from":start.toIso,"to":end.toIso,"known":segment["known"] == true]
      if (request["kind"] == "energyFlow")
      {
        graph:=((Str:Obj?)((Str:Obj?)result["extra"])["energyFlow"]).dup
        graph["from"]=start.toIso; graph["to"]=end.toIso
        entry.setAll(["energyFlow":graph,"rows":result["rows"],"series":result["series"],"summary":result["summary"],"warnings":result["warnings"]])
        entry["energyFlowOverview"]=((Str:Obj?)result["extra"])["energyFlowOverview"]
      }
      segments.add(entry); cursor=end
    }
    if (reports.isEmpty || cursor != to) throw ArgErr("历史计量关系时段必须覆盖完整查询范围")
    out:=reports.first.dup; out["from"]=from.toIso; out["to"]=to.toIso
    warnings:=Str[,]; reports.each |r| { warnings.addAll(EnerCubixMath.strings(r["warnings"])) }; out["warnings"]=warnings.unique
    extra:=((Str:Obj?)reports.first["extra"]).dup
    if (request["kind"] == "energyFlow")
    {
      extra["energyFlowSegments"]=segments
      extra["energyFlowOverview"]=overview
      extra["usageBasis"]="knownUsage"
      extra["knownUsage"]=overview["knownUsage"]
      extra["selectionTotals"]=overview["selectionTotals"]
      extra["energyFlow"]=segments.first["energyFlow"]
      out["rows"]=overview["rows"]
      out["series"]=[Str:Obj?][,]
      out["summary"]=["segmentCount":segments.size,"selectionTotals":overview["selectionTotals"]]
    }
    else
    {
      out["rows"]=mergeRows(reports.map |r->[Str:Obj?][]| { EnerCubixMath.maps(r["rows"]) }.flatten,["nodeId","categoryId","unit","ts"],["value","total","submeter","difference"])
      out["series"]=mergeSeries(reports)
      totals:=mergeRows(reports.map |r->[Str:Obj?][]| { EnerCubixMath.maps(((Str:Obj?)r["summary"])["totals"]) }.flatten,["id","categoryId","unit"],["value"])
      out["summary"]=["totals":totals]
      extra["leakTotals"]=mergeRows(extraRows(reports,"leakTotals"),["nodeId","categoryId","unit"],["value","total","submeter","difference"])
      extra["leakBranches"]=mergeRows(extraRows(reports,"leakBranches"),["nodeId","branchId","categoryId","unit","ts"],["value"])
      extra["details"]=mergeRows(extraRows(reports,"details"),["scopeId","nodeId","categoryId","unit"],["value"])
      extra["meterHistorySegments"]=segments
    }
    out["extra"]=extra
    return out
  }

  ** Split only at boundaries shared by each selected meter's own history.
  ** Complete windows remain comparable; gaps and unfinished tails stay visible.
  private static [Str:Obj?][] flowSections(Str:Obj? request, [Str:Obj?][] current, [Str:Obj?][] histories, Str:Obj? segment, DateTime from, DateTime to)
  {
    if (segment["known"] != true) return [segment]
    start:=DateTime.fromIso(segment["from"].toStr); end:=DateTime.fromIso(segment["to"].toStr)
    if (start < from) start=from
    if (end > to) end=to
    if (end <= start) return [Str:Obj?][,]
    records:=recordsFor(current,segment)
    if (!EnerCubixMath.strings(request["nodeIds"]).all |id| { records.any |r| { r["id"] == id } }) return [segment]
    dimension:=EnerCubixDimension("metering",records)
    plan:=EnerCubixEnergyFlow.scope(dimension.normalizeRequest(request),dimension)
    ids:=EnerCubixMath.maps(plan["selected"]).map |r->Str| { r["historyPointId"]?.toStr ?: (r["pointId"]?.toStr ?: "") }.unique
    if (ids.isEmpty) return [segment]
    inputs:=EnerCubixHistoryData[,]; common:=Int[,]; first:=true
    ids.each |id|
    {
      data:=histories.find |h| { h["pointId"] == id }
      h:=EnerCubixHistoryData(data ?: ["pointId":id,"quality":"missing"])
      inputs.add(h)
      ticks:=Int[,]
      if (h.intervals != null) h.intervals.each |row| { ticks.add(row.start.ticks).add(row.end.ticks) }
      else h.samples.each |sample| { ticks.add(sample.ts.ticks); if (h.mode == "interval") ticks.add((sample.ts+1hr).ticks) }
      index:=Int:Bool[:]; ticks.each |tick| { if (tick > start.ticks && tick < end.ticks) index[tick]=true }
      common=first ? index.keys : common.findAll |tick| { index.containsKey(tick) }
      first=false
    }
    bounds:=[start.ticks].addAll(common).add(end.ticks).unique.sort
    answer:=[Str:Obj?][,]; Bool? previous:=null
    for (i:=0;i<bounds.size-1;i++)
    {
      a:=DateTime.makeTicks(bounds[i],from.tz); b:=DateTime.makeTicks(bounds[i+1],from.tz)
      complete:=inputs.all |h|
      {
        value:=h.read(a,b)
        return value.value != null && value.value >= 0f && ["ok","good","derived","estimated","cleaned","corrected"].contains(value.quality)
      }
      if (previous == complete) answer.last["to"]=b.toIso
      else answer.add(segment.dup.set("from",a.toIso).set("to",b.toIso))
      previous=complete
    }
    return answer
  }

  private static [Str:Obj?][] extraRows([Str:Obj?][] reports, Str key)
  { reports.map |r->[Str:Obj?][]| { EnerCubixMath.maps(((Str:Obj?)r["extra"])[key]) }.flatten }

  private static [Str:Obj?][] mergeSeries([Str:Obj?][] reports)
  {
    grouped:=Str:[Str:Obj?][][:]; order:=Str[,]
    reports.each |r|
    {
      EnerCubixMath.maps(r["series"]).each |s|
      {
        id:=s["id"].toStr
        if (!grouped.containsKey(id)) { grouped[id]=[Str:Obj?][,]; order.add(id) }
        grouped[id].add(s)
      }
    }
    return order.map |id->[Str:Obj?]| { parts:=grouped[id]; out:=parts.first.dup; out["points"]=mergeRows(parts.map |s->[Str:Obj?][]| { EnerCubixMath.maps(s["points"]) }.flatten,["ts"],["value"]); return out }
  }

  private static [Str:Obj?][] mergeRows([Str:Obj?][] rows, Str[] keys, Str[] fields)
  {
    grouped:=Str:[Str:Obj?][][:]; order:=Str[,]
    rows.each |row|
    {
      key:=keys.map |name->Str| { row[name]?.toStr ?: "" }.join("|")
      if (!grouped.containsKey(key)) { grouped[key]=[Str:Obj?][,]; order.add(key) }
      grouped[key].add(row)
    }
    return order.map |key->[Str:Obj?]|
    {
      parts:=grouped[key]; out:=parts.first.dup
      fields.each |field|
      {
        qualityKey:=field == "total" ? "totalQuality" : (field == "submeter" ? "submeterQuality" : "quality")
        EnerCubixValue[] values:=parts.map |p->EnerCubixValue|
        {
          quality:=(p[qualityKey] as Str) ?: ((p["quality"] as Str) ?: "ok")
          return EnerCubixValue(EnerCubixMath.num(p[field]),quality,EnerCubixMath.strings(p["sourceIds"]))
        }
        sum:=EnerCubixValue.sum(values)
        if (values.any |v| { v.value == null || !v.reliable }) sum=EnerCubixValue(null,sum.quality,sum.sources)
        out[field]=sum.value; out[qualityKey]=sum.quality; out["sourceIds"]=sum.sources
        if (field == "value") out["valueType"]=sum.valueType
      }
      if (parts.any |p| { p["balanceMode"] != null })
      {
        modes:=parts.map |p->Str| { p["balanceMode"] as Str ?: "independent" }.unique
        mode:=modes.size == 1 ? modes.first : "mixed"
        out["balanceMode"]=mode
        total:=EnerCubixValue(EnerCubixMath.num(out["total"]),out["totalQuality"] as Str ?: "missing")
        sub:=EnerCubixValue(EnerCubixMath.num(out["submeter"]),out["submeterQuality"] as Str ?: "missing")
        out["lossEligible"]=EnerCubixBalance.eligible(mode,total,sub) && parts.all |p| { p["lossEligible"] == true }
        difference:=EnerCubixValue(EnerCubixMath.num(out["difference"]),out["quality"] as Str ?: "missing")
        out["percentage"]=mode == "independent" ? EnerCubixValue.divide(difference,total).scale(100f).value : null
      }
      return out
    }
  }

  private static Str:Obj? unknown(Str:Obj? request, [Str:Obj?][] records, [Str:Obj?][] histories)
  {
    own:=request.dup; own["kind"]="profile"
    if (request["kind"] == "energyFlow") own["nodeIds"]=EnerCubixFlowOverview.members(request,records,false).map |r->Str| { r["id"].toStr }
    report:=EnerCubixEngine.report(own,records,histories)
    out:=report.dup; out["kind"]=request["kind"]
    warning:="历史计量关系尚未确认，保留表计自身历史，不推定当时的分表或差额。"
    out["warnings"]=EnerCubixMath.strings(report["warnings"]).dup.add(warning)
    if (request["kind"] == "energyFlow")
    {
      req:=request.dup; req["meterHistorySegments"]=[["from":request["from"],"to":request["to"],"known":false]]
      overview:=EnerCubixFlowOverview.build(req,records,histories)
      [Str:Obj?][] nodes:=EnerCubixMath.maps(overview["rows"]).map |row->[Str:Obj?]|
      {
        id:=row["id"].toStr.split('|').first
        return ["id":id,"nodeId":id,"name":row["name"],"nodeType":"meter","categoryId":request["categoryId"],"unit":row["unit"],"value":row["value"],"quality":row["quality"],"sourceIds":row["sourceIds"],"submeter":null,"difference":null,"balanceQuality":"topologyUnknown","balanceMode":"unknown","lossEligible":false,"hasChildren":false,"percentage":null]
      }
      category:=request["categoryId"].toStr; focus:=nodes.first?.get("id") ?: "__energyFlow__:$category"
      unit:=records.find |r| { r["id"] == category }?.get("unit")?.toStr ?: ""
      graph:=["categoryId":category,"unit":unit,"focusId":focus,"rootIds":nodes.map |n->Str| { n["id"].toStr },"nodes":nodes,"links":[Str:Obj?][,],"unassigned":[Str:Obj?][,]]
      out["rows"]=overview["rows"]; out["series"]=[Str:Obj?][,]; out["extra"]=["energyFlow":graph,"energyFlowOverview":overview]
    }
    else
    {
      out["rows"]=EnerCubixMath.maps(report["rows"]).map |row->[Str:Obj?]| { unknownBalance(row) }
      totals:=EnerCubixMath.maps(((Str:Obj?)report["summary"])["totals"]).map |row->[Str:Obj?]| { unknownBalance(row) }
      out["summary"]=["totals":totals]
      out["series"]=EnerCubixMath.maps(report["series"]).map |s->[Str:Obj?]| { copy:=s.dup; copy["points"]=EnerCubixMath.maps(s["points"]).map |p->[Str:Obj?]| { unknownBalance(p) }; return copy }
      out["extra"]=["leakTotals":totals,"leakBranches":[Str:Obj?][,]]
    }
    return out
  }

  private static Str:Obj? unknownBalance(Str:Obj? row)
  {
    out:=row.dup; out["total"]=row["value"]; out["totalQuality"]=row["quality"]
    if (out["nodeId"] == null && row["id"] != null) out["nodeId"]=row["id"].toStr.split('|').first
    out["value"]=null; out["valueType"]="null"; out["quality"]="topologyUnknown"
    out["submeter"]=null; out["submeterQuality"]="topologyUnknown"; out["difference"]=null; out["percentage"]=null
    out["balanceMode"]="unknown"; out["lossEligible"]=false
    return out
  }
}

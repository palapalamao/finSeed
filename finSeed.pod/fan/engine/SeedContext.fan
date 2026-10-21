internal class SeedContext
{
  new make([Str:Obj?][] records, [Str:Obj?][] histories, TimeZone tz, SeedDimension? dimension := null)
  {
    this.tz=tz
    this.dimension=dimension
    records.each |r|
    {
      id := r["id"]?.toStr
      if (id != null) byId[id] = r
    }
    histories.each |h| { parsed:=SeedHistoryData(h); byPoint[parsed.id]=parsed }
    records.each |r|
    {
      parent := r["parentId"]?.toStr
      if (parent == null) return
      if (!children.containsKey(parent)) children[parent]=[Str:Obj?][,]
      children[parent].add(r)
    }
    calendars:=records.findAll |r| { r["kind"] == "calendar" }
    defaults:=calendars.findAll |r| { r["isDefault"] == true }
    if (defaults.size == 1) calendar=defaults.first
    else if (defaults.isEmpty && calendars.size == 1) calendar=calendars.first
  }
  TimeZone tz
  SeedDimension? dimension
  Str:[Str:Obj?] byId := [:]
  Str:SeedHistoryData byPoint := [:]
  Str:[Str:Obj?][] children := [:]
  [Str:Obj?]? calendar
  Str[] warnings := [,]
  private Str:SeedValue cache := [:]
  private Str:SeedValue tariffBaseline := [:]
  private Str:[Str:Obj?] dimensionPlans := [:]

  Void warn(Str message) { if (!warnings.contains(message)) warnings.add(message) }

  Str displayName(Str id)
  {
    record:=byId[id]
    if (record == null)
    {
      bindings:=byId.vals.findAll |r| { r["kind"] == "binding" && r["pointId"]?.toStr == id }
      record=bindings.find |r| { r["role"] == "reference" } ?: bindings.first
    }
    alias:=record?.get("alias") as Str
    if (alias != null && !alias.trim.isEmpty) return alias.trim
    name:=record?.get("name") as Str
    return name != null && !name.trim.isEmpty ? name : id
  }

  Str[] categories(Str id, Str[] visited := Str[,])
  {
    r := byId[id]
    if (r == null || visited.contains(id)) return Str[,]
    if (dimension?.scope(id) == true) return dimension.members(id).map |m->Str| { m["categoryId"]?.toStr ?: "" }.unique.sort
    if (r["kind"] != "group") return [r["categoryId"]?.toStr ?: ""]
    out := Str[,]
    (children[id] ?: [Str:Obj?][,]).each |child|
    {
      if (!included(child)) return
      out.addAll(categories(child["id"].toStr,visited.dup.add(id)))
    }
    return out.unique.sort
  }

  Bool included(Str:Obj? r)
  {
    k := r["kind"]?.toStr
    if (k == "sensor") return false
    if (k == "group") return true
    if (k != "meter" && k != "totalMeter") return false
    return (Bool?)r["includeInTotals"] ?: (r["expressionId"] == null)
  }

  Str[] utilities(Str id, Str category, Str[] path := Str[,])
  {
    if (path.contains(id)) return Str[,]
    if (dimension?.scope(id) == true) return dimension.usageFrontier(dimension.members(id).findAll |m| { (m["categoryId"]?.toStr ?: "") == category }).map |m->Str| { m["utilityId"]?.toStr ?: "" }.unique.sort
    out:=Str[,]
    (children[id] ?: [Str:Obj?][,]).each |r|
    {
      if (!included(r) || (r["kind"] == "totalMeter" && r["utilityId"] == null)) return
      if (r["kind"] == "group") out.addAll(utilities(r["id"].toStr,category,path.dup.add(id)))
      else if ((r["categoryId"]?.toStr ?: "") == category) out.add(r["utilityId"]?.toStr ?: "")
    }
    return out.unique.sort
  }

  ** Exclude only this group's master; each child group's master remains authoritative.
  SeedValue branch(Str id, Str category, DateTime start, DateTime end, Str metric)
  {
    values:=SeedValue[,]
    (children[id] ?: [Str:Obj?][,]).each |r|
    {
      if (!included(r) || r["kind"] == "totalMeter") return
      child:=r["id"].toStr
      if (categories(child).contains(category)) values.add(node(child,category,start,end,metric,[id]))
    }
    return SeedValue.sum(values)
  }

  SeedValue node(Str id, Str category, DateTime from, DateTime to, Str metric := "energy", Str[] path := Str[,], Str? utility := null, Bool useMaster := true)
  {
    if (path.contains(id)) return SeedValue(null,"cycle")
    key := "$id|$category|${from.ticks}|${to.ticks}|$metric|$utility|$useMaster"
    if (path.isEmpty && cache.containsKey(key)) return cache[key]
    r := byId[id]
    if (r == null) return SeedValue(null,"unknownNode")
    nextPath := path.dup.add(id)
    SeedValue result := SeedValue()
    if (dimension?.scope(id) == true)
    {
      planKey:="$id|$category|$utility"
      plan:=dimensionPlans[planKey]
      if (plan == null)
      {
        members:=dimension.members(id).findAll |m| { (m["categoryId"]?.toStr ?: "") == category }
        authoritative:=(utility == null ? dimension.frontier(members) : dimension.usageFrontier(members)).findAll |m| { utility == null || (m["utilityId"]?.toStr ?: "") == utility }
        plan=["members":authoritative,"quality":dimension.quality(members)]
        dimensionPlans[planKey]=plan
      }
      authoritative:=([Str:Obj?][])plan["members"]
      values:=authoritative.map |m->SeedValue| { node(m["id"].toStr,category,from,to,metric,nextPath) }
      result=SeedValue.sum(values)
      quality:=plan["quality"] as Str
      if (quality != null) result=SeedValue(null,quality,result.sources)
    }
    else if (r["kind"] == "group")
    {
      members := children[id] ?: [Str:Obj?][,]
      masters := members.findAll |m| { m["kind"] == "totalMeter" && m["categoryId"]?.toStr == category && included(m) && (utility == null || (m["utilityId"] != null && m["utilityId"]?.toStr == utility)) }
      if (useMaster && !masters.isEmpty)
      {
        if (masters.size > 1) result=SeedValue(null,"ambiguousMaster")
        else result=node(masters.first["id"].toStr,category,from,to,metric,nextPath,utility,useMaster)
      }
      else
      {
        values := SeedValue[,]
        members.each |m|
        {
          if (!included(m) || m["kind"] == "totalMeter") return
          if (m["kind"] == "group")
          {
            if (utility != null && !utilities(m["id"].toStr,category).contains(utility)) return
            if (categories(m["id"].toStr).contains(category)) values.add(node(m["id"].toStr,category,from,to,metric,nextPath,utility,useMaster))
          }
          else if ((m["categoryId"]?.toStr ?: "") == category && (utility == null || (m["utilityId"]?.toStr ?: "") == utility)) values.add(node(m["id"].toStr,category,from,to,metric,nextPath,utility,useMaster))
        }
        result=SeedValue.sum(values)
      }
    }
    else if (r["kind"] == "cop")
    {
      a := r["numeratorId"]?.toStr ?: ""; b := r["denominatorId"]?.toStr ?: ""
      result=SeedValue.divide(nodeTotal(a,from,to,nextPath),nodeTotal(b,from,to,nextPath))
    }
    else
    {
      raw := rawNode(r,from,to,nextPath)
      if (metric == "energy") result=raw
      else if (r["kind"] == "sensor") result=SeedValue(null,"invalidMetric",raw.sources)
      else if (metric == "cost") result=cost(r,raw,from,to,nextPath)
      else
      {
        sub := byId[r["subcategoryId"]?.toStr ?: ""]
        factor := sub == null ? null : SeedMath.num(sub[metric+"Factor"])
        result=factor == null ? SeedValue(null,"missingCoefficient",raw.sources) : raw.scale(factor)
      }
    }
    if (result.value == null) { label:=r["name"] ?: id; warn("$label : ${result.quality}") }
    if (path.isEmpty) cache[key]=result
    return result
  }

  SeedValue nodeTotal(Str id, DateTime from, DateTime to, Str[] path := Str[,])
  {
    cats := categories(id)
    return SeedValue.sum(cats.map |cat->SeedValue| { node(id,cat,from,to,"energy",path) })
  }

  private SeedValue rawNode(Str:Obj? r, DateTime from, DateTime to, Str[] path)
  {
    if (r["kind"] == "nativePoint") return SeedValue(null,"notEnergyPoint")
    if (dimension?.nativeSpace == true && r["nativeSourceMissing"] == true) return SeedValue(null,"nativeSourceMissing")
    SeedValue raw := SeedValue()
    exprId := r["expressionId"]?.toStr
    if (exprId != null)
    {
      expr := byId[exprId]
      if (expr == null) return SeedValue(null,"missingExpression")
      variables := Str:SeedValue[:]
      map := expr["variables"] as Map
      if (map != null) map.each |Obj? id, Obj name| { variables[name.toStr]=nodeTotal(id.toStr,from,to,path) }
      raw = SeedExpression(expr["formula"]?.toStr ?: "",variables).calculate
    }
    else
    {
      point := r["pointId"]?.toStr ?: ""
      his := byPoint[point]
      if (his == null) return SeedValue(null,"missing",point.isEmpty ? Str[,] : [point])
      if (!["ok","estimated","derived"].contains(his.quality)) return SeedValue(null,his.quality,[point])
      if (r["kind"] != "sensor" && his.mode != "interval" && his.mode != "cumulative") return SeedValue(null,"notEnergyHistory",[point])
      raw=his.read(from,to)
    }
    max := SeedMath.num(r["maximum"])
    durationFactor:=r["kind"] == "sensor" ? 1f : (to-from).ticks.toFloat/1hr.ticks.toFloat
    if (raw.value != null && max != null && raw.value > max*durationFactor) return SeedValue(null,"maximum",raw.sources)
    if (exprId == null && r["kind"] != "sensor")
    {
      his:=byPoint[r["pointId"]?.toStr ?: ""]
      sourceUnit:=his?.unit ?: ""
      if (sourceUnit.isEmpty) sourceUnit=r["unit"]?.toStr ?: ""
      targetUnit:=categoryUnit(r["categoryId"]?.toStr ?: "")
      factor:=SeedMath.unitFactor(sourceUnit,targetUnit)
      if (factor == null) return SeedValue(null,"incompatibleUnit",raw.sources)
      raw=raw.scale(factor)
    }
    return raw
  }

  private SeedValue cost(Str:Obj? r, SeedValue raw, DateTime from, DateTime to, Str[] path)
  {
    t := tariff(r)
    if (t == null) return SeedValue(null,"missingTariff",raw.sources)
    mode := t["mode"]?.toStr ?: "flat"
    if (mode == "monthlyBlock" || mode == "yearlyBlock")
    {
      cycle := SeedMath.bucket(from,mode == "yearlyBlock" ? "year" : "month")
      // Baseline is meter-specific. Missing preceding hours invalidate the price band.
      meterId:=r["id"].toStr
      baselineKey:="$meterId|${cycle.ticks}|${from.ticks}"
      baseline:=tariffBaseline[baselineKey]
      if (baseline == null)
      {
        values := SeedValue[,]; cursor:=cycle
        while (cursor < from)
        {
          end:=SeedMath.floorHour(cursor)+1hr; if (end > from) end=from
          values.add(rawNode(r,cursor,end,path)); cursor=end
        }
        baseline=values.isEmpty ? SeedValue(0f,"ok") : SeedValue.sum(values)
        tariffBaseline[baselineKey]=baseline
      }
      nextKey:="$meterId|${cycle.ticks}|${to.ticks}"
      tariffBaseline[nextKey]=SeedValue.sum([baseline,raw])
      if (baseline.value == null) return SeedValue(null,"missingTariffBaseline",raw.sources)
      if (raw.value == null) return raw
      lo:=blockPrice(t,baseline.value); hi:=blockPrice(t,baseline.value+raw.value)
      if (lo == null || hi == null) return SeedValue(null,"invalidTariff",raw.sources)
      return SeedValue(hi-lo,SeedValue.worse(baseline.quality,raw.quality),raw.sources)
    }
    if (raw.value == null) return raw
    // Split within an hour for absolute dates and fractional start/endHour rules.
    bounds := [from,to]
    rules := SeedMath.maps(t["rules"]).addAll(SeedMath.maps(t["exceptions"]))
    rules.each |rule|
    {
      ["from","to"].each |key|
      {
        text:=rule[key]?.toStr
        if (text == null) return
        at:=DateTime.fromIso(text,false)
        if (at != null && at > from && at < to) bounds.add(at.toTimeZone(tz))
      }
      ["startHour","endHour"].each |key|
      {
        hour:=SeedMath.num(rule[key]); if (hour == null) return
        at:=from.date.toDateTime(Time.defVal,tz)+Duration((hour*1hr.ticks.toFloat).toInt)
        if (at > from && at < to) bounds.add(at)
      }
    }
    bounds=bounds.unique.sort
    parts:=SeedValue[,]
    for (i:=0;i<bounds.size-1;i++)
    {
      a:=bounds[i]; b:=bounds[i+1]
      energy:=bounds.size == 2 ? raw : rawNode(r,a,b,path)
      rate:=rateAt(t,a)
      parts.add(rate == null ? SeedValue(null,"missingTariff",raw.sources) : energy.scale(rate))
    }
    return SeedValue.sum(parts)
  }

  private Float? blockPrice(Str:Obj? tariff, Float use)
  {
    if (use < 0f) return null
    lower:=0f; total:=0f
    blocks:=SeedMath.maps(tariff["blocks"])
    for (i:=0;i<blocks.size;i++)
    {
      block:=blocks[i]; rate:=SeedMath.num(block["rate"]); limit:=SeedMath.num(block["limit"])
      if (rate == null || rate < 0f || (limit != null && limit <= lower)) return null
      if (use <= lower) return total
      upper:=limit ?: use
      total+=(use.min(upper)-lower).max(0f)*rate
      if (limit == null || use <= upper) return total
      lower=upper
    }
    return use == lower ? total : null
  }

  private Float? rateAt(Str:Obj? tariff, DateTime at)
  {
    Float? rate:=SeedMath.num(tariff["rate"])
    if (tariff["mode"] != "flat") SeedMath.maps(tariff["rules"]).each |rule| { if (matches(rule,at)) rate=SeedMath.num(rule["rate"]) }
    // Exceptions take precedence in all tariff modes; [from,to) is consistent with reports.
    SeedMath.maps(tariff["exceptions"]).each |rule| { if (matches(rule,at)) rate=SeedMath.num(rule["rate"]) }
    return rate
  }

  private Bool matches(Str:Obj? rule, DateTime at)
  {
    from:=rule["from"]?.toStr; to:=rule["to"]?.toStr
    if (from != null && !dateMatch(from,at,true)) return false
    if (to != null && !dateMatch(to,at,false)) return false
    day:=SeedMath.num(rule["weekday"])
    if (day != null && day != SeedMath.isoDay(at).toFloat) return false
    start:=SeedMath.num(rule["startHour"]) ?: 0f; end:=SeedMath.num(rule["endHour"]) ?: 24f
    hour:=at.hour.toFloat+at.min.toFloat/60f+at.sec.toFloat/3600f
    return start <= end ? hour >= start && hour < end : hour >= start || hour < end
  }

  private Bool dateMatch(Str s, DateTime at, Bool lower)
  {
    if (s.size == 10)
    {
      date:=Date.fromStr(s,false); if (date == null) return false
      return lower ? at.date >= date : at.date < date
    }
    dt:=DateTime.fromIso(s,false); if (dt == null) return false
    return lower ? at >= dt : at < dt
  }

  Bool working(DateTime at, Bool hours, Obj? overrideHours := null)
  {
    if (hours) return SeedMath.containsNum(overrideHours ?: calendar?.get("workHours"),at.hour)
    if (calendar == null) return false
    day:=SeedMath.containsNum(calendar["workDays"],SeedMath.isoDay(at))
    SeedMath.maps(calendar["exceptions"]).each |e| { if (e["date"]?.toStr == at.date.toStr) day=e["working"] == true }
    return day
  }

  [Str:Obj?]? tariff(Str:Obj? record)
  {
    id:=record["tariffId"]?.toStr
    if (id != null) return byId[id]
    defaults:=byId.vals.findAll |r| { r["kind"] == "tariff" && r["categoryId"] == record["categoryId"] && r["isDefault"] == true }
    return defaults.size == 1 ? defaults.first : null
  }

  Str unit(Str id, Str category, Str metric)
  {
    if (metric == "cost") return "元"
    if (metric == "coal") return "kgce"
    if (metric == "co2") return "kgCO2"
    if (metric == "rawcoal") return "kg raw coal"
    if (metric == "oil") return "kg oil"
    r:=byId[id]
    if (r?.get("kind") != "sensor")
    {
      canonical:=categoryUnit(category)
      if (!canonical.isEmpty) return canonical
    }
    own:=r?.get("unit")?.toStr
    if (own != null) return own
    return byPoint[r?.get("pointId")?.toStr ?: ""]?.unit ?: ""
  }

  private Str categoryUnit(Str category)
  {
    configured:=byId[category]?.get("unit")?.toStr
    if (configured != null) return configured
    first:=byId.vals.find |r| { r["categoryId"]?.toStr == category && r["kind"] != "sensor" && r["unit"] != null }
    return first?.get("unit")?.toStr ?: ""
  }
}






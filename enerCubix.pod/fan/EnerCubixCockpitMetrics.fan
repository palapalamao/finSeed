** Request-local projections over the existing report engine and its strict/known values.
internal class EnerCubixCockpitMetrics
{
  static Str:Obj? comparison(Str:Obj? input, Str:Obj? request, TimeZone tz)
  {
    Str:Obj? config:=input["comparison"] as Map ?: Str:Obj?["mode":"presetDefault"]
    preset:=((Map)input["time"])["preset"]
    mode:=config["mode"]
    if (mode == "none" || (mode == "presetDefault" && preset == "custom")) return ["mode":"none"]
    from:=DateTime.fromIso(request["from"].toStr).toTimeZone(tz)
    to:=DateTime.fromIso(request["to"].toStr).toTimeZone(tz)
    cutoff:=DateTime.fromIso(request["asOf"].toStr).toTimeZone(tz)
    reasons:=Str[,]
    adjustments:=[Str:Obj?][,]
    a:=from; b:=to; kind:="custom"
    if (mode == "custom")
    {
      a=DateTime.fromIso(config["from"] as Str ?: "",false) ?: throw ArgErr("cockpitComparisonRange")
      b=DateTime.fromIso(config["to"] as Str ?: "",false) ?: throw ArgErr("cockpitComparisonRange")
      a=a.toTimeZone(tz); b=b.toTimeZone(tz); kind="custom"
      if (b <= a || b > cutoff || b.date-a.date > 366day) throw ArgErr("cockpitComparisonRange")
    }
    else
    {
      kind=preset == "today" ? "previousDaySameCutoff" : "yearSameElapsedCalendar"
      a=calendarShift(from,preset == "today",reasons,adjustments,"from")
      b=calendarShift(to,preset == "today",reasons,adjustments,"to")
      if (b <= a) throw ArgErr("cockpitComparisonRange")
    }
    if (from.toRel.ticks-from.ticks != a.toRel.ticks-a.ticks || to.toRel.ticks-to.ticks != b.toRel.ticks-b.ticks) reasons.add("TIMEZONE_OFFSET_CHANGED")
    delta:=((to-from)-(b-a)).ticks/1sec.ticks
    if (delta != 0) reasons.add("DURATION_DIFFERENCE")
    return ["mode":mode,"kind":kind,"from":a.toIso,"to":b.toIso,"currentRange":["from":from.toIso,"to":to.toIso],"referenceRange":["from":a.toIso,"to":b.toIso],"reasonCodes":reasons.unique,"adjustments":adjustments,"durationDifferenceSeconds":delta]
  }

  private static DateTime calendarShift(DateTime at, Bool day, Str[] reasons, [Str:Obj?][] adjustments, Str boundary)
  {
    date:=day ? at.date-1day : Date(at.year-1,at.month,at.month == Month.feb && at.day == 29 ? 28 : at.day)
    leap:=!day && at.month == Month.feb && at.day == 29
    if (leap) reasons.add("LEAP_DAY_CLAMPED")
    shifted:=date.toDateTime(at.time,at.tz)
    // Native timezone resolution defines gaps/folds. Roundtrip exposes any gap adjustment.
    normalized:=DateTime.makeTicks(shifted.ticks,at.tz)
    reason:=leap ? "LEAP_DAY_CLAMPED" : null
    if (normalized.date != date || normalized.time != at.time) {reason="LOCAL_TIME_ADJUSTED";reasons.add(reason)}
    dst:=at.tz.dstOffset(date.year)
    if (dst != null && dst != 0sec)
    {
      alternatives:=[normalized+dst,normalized-dst]
      if (alternatives.any |t| {t.date == date && t.time == at.time}) {reason="LOCAL_TIME_AMBIGUOUS";reasons.add(reason)}
    }
    if (reason != null) adjustments.add(["boundary":boundary,"reasonCode":reason,"requestedLocal":(leap ? (at.year-1).toStr+"-02-29" : date.toStr)+"T"+at.time.toStr,"resolved":normalized.toIso])
    return normalized
  }

  ** Per-point union: only billing baselines expand a period, never the gap between periods.
  static [Str:Obj?][] plan(Str:Obj? request, Str:Obj? comparison, EnerCubixContext ctx, Str? auxiliary, Bool explicit := false, Bool billing := true, [Str:Obj?][] evidence := [Str:Obj?][,])
  {
    periods:=[request]
    if (comparison["mode"] != "none") periods.add(request.dup.setAll((Map)comparison["referenceRange"]))
    candidates:=[Str:Obj?][,]
    categories:=EnerCubixMath.strings(request["categoryIds"])
    if (auxiliary != null) categories.add(auxiliary)
    periods.each |q|
    {
      end:=DateTime.fromIso(q["to"].toStr); cutoff:=DateTime.fromIso(q["asOf"].toStr)
      if (end > cutoff) end=cutoff
      start:=DateTime.fromIso(q["from"].toStr)
      if (end <= start) return
      categories.each |category|
      {
        members:=[Str:Obj?][,]
        EnerCubixMath.strings(q["nodeIds"]).each |id| {members.addAll(ctx.scopeMeters(id,category))}
        (explicit ? members.unique : ctx.selectionMeters(members)).each |m|
        {
          point:=m["pointId"] as Str
          if (point == null || point.isEmpty) return
          left:=start
          if (billing && category == categories.first)
          {
            mode:=ctx.tariff(m)?.get("mode")
            if (mode == "monthlyBlock" || mode == "yearlyBlock") left=EnerCubixMath.bucket(start,mode == "monthlyBlock" ? "month" : "year")
          }
          candidates.add(["from":left.toIso,"to":end.toIso,"pointIds":[point]])
        }
      }
    }
    end:=DateTime.fromIso(request["to"].toStr); cutoff:=DateTime.fromIso(request["asOf"].toStr)
    if (end > cutoff) end=cutoff
    if (end > DateTime.fromIso(request["from"].toStr)) evidence.each |m|
    {
      point:=m["pointId"] as Str
      if (point != null && !point.isEmpty) candidates.add(["from":request["from"],"to":end.toIso,"pointIds":[point]])
    }
    out:=[Str:Obj?][,]
    candidates.map |r->Str| {((Str[])r["pointIds"]).first}.unique.sort.each |point|
    {
      ranges:=candidates.findAll |r| {((Str[])r["pointIds"]).contains(point)}.sort |a,b| {DateTime.fromIso(a["from"].toStr) <=> DateTime.fromIso(b["from"].toStr)}
      ranges.each |r|
      {
        previous:=out.last
        if (previous != null && previous["pointIds"] == [point] && DateTime.fromIso(r["from"].toStr) <= DateTime.fromIso(previous["to"].toStr))
        {
          if (DateTime.fromIso(r["to"].toStr) > DateTime.fromIso(previous["to"].toStr)) previous["to"]=r["to"]
        }
        else out.add(r.dup)
      }
    }
    // Coalesce equal ranges across different points without introducing extra hours.
    grouped:=[Str:Obj?][,]
    out.each |r|
    {
      same:=grouped.find |g| {g["from"] == r["from"] && g["to"] == r["to"]}
      if (same == null) grouped.add(r.dup)
      else same["pointIds"]=EnerCubixMath.strings(same["pointIds"]).addAll(EnerCubixMath.strings(r["pointIds"]))
    }
    return grouped.sort |a,b| {DateTime.fromIso(a["from"].toStr) <=> DateTime.fromIso(b["from"].toStr)}
  }

  static [Str:Obj?][] histories(Str:Obj? q, [Str:Obj?][] all)
  {
    from:=DateTime.fromIso(q["from"].toStr); to:=DateTime.fromIso(q["to"].toStr)
    return all.findAll |h|
    {h["_cockpitFrom"] == null || (DateTime.fromIso(h["_cockpitFrom"].toStr) < to && DateTime.fromIso(h["_cockpitTo"].toStr) > from)}
  }

  ** Only participating business configuration belongs in a configuration fingerprint.
  ** Connected meter relationships can change a boundary even without being read.
  static [Str:Obj?][] configuration(EnerCubixContext ctx, Str[] ids, Str[] categories)
  {
    selected:=ids.dup.addAll(categories)
    ids.each |id|
    {
      if (ctx.dimension?.scope(id) == true)
        selected.addAll(ctx.dimension.members(id).findAll |m| {categories.contains(m["categoryId"])}.map |m->Str| {m["id"].toStr})
      categories.each |category| {selected.addAll(ctx.scopeMeters(id,category).map |m->Str| {m["id"].toStr})}
    }
    if (ctx.calendar != null) selected.add(ctx.calendar["id"].toStr)
    changed:=true
    while (changed)
    {
      previous:=selected.unique.size
      ctx.byId.vals.each |r|
      {
        if (["meter","totalMeter"].contains(r["kind"]) && categories.contains(r["categoryId"] as Str ?: "") && selected.contains(r["meterParentId"] as Str ?: "")) selected.add(r["id"].toStr)
        if (!selected.contains(r["id"] as Str ?: "") && !selected.contains(r["nativeSourceId"] as Str ?: "")) return
        selected.add(r["id"].toStr)
        ["parentId","meterParentId","categoryId","subcategoryId","utilityId","expressionId","tariffId","cleaningProfileId","spaceId","nativeSpaceId","organizationId","areaSpaceId","canonicalId","nativeTreeParentId"].each |key| {if (r[key] is Str) selected.add(r[key].toStr)}
        if (["meter","totalMeter"].contains(r["kind"]))
        {
          tariff:=ctx.tariff(r)
          if (tariff != null) selected.add(tariff["id"].toStr)
        }
      }
      selected=selected.unique
      changed=selected.size != previous
    }
    return ctx.byId.vals.findAll |r| {selected.contains(r["id"] as Str ?: "") && ["meter","totalMeter","space","organization","category","subcategory","utility","expression","tariff","calendar","cleaningProfile"].contains(r["kind"])}.sort |a,b| {a["id"].toStr <=> b["id"].toStr}
  }

  static [Str:Obj?][] values(Str:Obj? q, [Str:Obj?][] records, [Str:Obj?][] all, Str:Obj? energy, Str:Obj? boundary, Str? auxiliary, Str:Obj? reports, Str prefix := "")
  {
    category:=EnerCubixMath.strings(q["categoryIds"]).first
    selected:=histories(q,all)
    values:=[energy]
    ["cost","co2"].each |id|
    {
      rq:=q.dup.set("metric",id)
      report:=EnerCubixHistory.report(rq,records,selected)
      reports[prefix+"profile-"+id]=report
      value:=metric(report,id,category,boundary)
      if (id == "cost")
      {
        tariffs:=EnerCubixMath.maps(((Map)report["extra"])["tariffSnapshot"])
        // Old tariffs have no currency tag; the existing engine's 元 means CNY.
        currencies:=tariffs.map |t->Str| {t["currency"] as Str ?: "CNY"}.unique
        value["unit"]=currencies.size == 1 ? currencies.first : ""
        value["details"]=["estimate":true,"tariffs":tariffs]
        if (currencies.size > 1) invalidate(value,"INCOMPATIBLE_CURRENCY")
      }
      else
      {
        refs:=records.findAll |r| {r["kind"] == "subcategory" && r["co2Factor"] != null}
        value["details"]=["coefficients":refs]
      }
      values.add(value)
    }
    Str:Obj? third:=[:]
    if (auxiliary != null)
    {
      rq:=q.dup.set("categoryIds",[auxiliary]).set("_cockpitCategoryId",auxiliary)
      report:=EnerCubixHistory.report(rq,records,selected)
      reports[prefix+"profile-auxiliary"]=report
      third=metric(report,"auxiliaryEnergy",auxiliary,boundary)
      dimension:=EnerCubixDimension(q["dimension"].toStr,records,q["spaceSource"] == "fin")
      ctx:=EnerCubixContext(dimension.records,[Str:Obj?][,],TimeZone(q["tz"].toStr),dimension)
      scopes:=EnerCubixMath.strings(q["nodeIds"]).map |id->[Str:Obj?][]| {ctx.scopeMeters(id,auxiliary)}
      candidates:=([Str:Obj?][])scopes.flatten
      points:=ctx.selectionMeters(candidates).map |m->Str| {m["pointId"] as Str ?: ""}.findAll |Str p->Bool| {!p.isEmpty}
      if (points.size != points.unique.size) invalidate(third,"duplicateSource")
      if (q["_cockpitExplicitObjects"] == true)
      {
        scopes.each |[Str:Obj?][] own,Int i|
        {
          for (j:=0;j<i;j++)
          {
            both:=own.dup.addAll(([Str:Obj?][])scopes[j])
            ids:=both.map |m->Str| {m["id"].toStr}
            if (ids.size != ids.unique.size || ctx.selectionMeters(both).size != ids.unique.size) invalidate(third,"overlappingScopes")
          }
        }
      }
    }
    else
    {
      report:=EnerCubixHistory.report(q.dup.set("perArea",true),records,selected)
      reports[prefix+"profile-area"]=report
      third=metric(report,"areaIntensity",category,boundary)
      extra:=(Map)report["extra"]
      selection:=EnerCubixMath.maps(extra["areaBasis"]).find |r| {r["nodeId"] == "__selection__" && r["categoryId"] == category}
      area:=EnerCubixAreaResolution(selection?.get("area") as Map ?: Str:Obj?[:],boundary["id"].toStr).toMap
      // Preserve raw energy even when no reliable denominator exists. The
      // formula is a frozen audit description of the engine's result.
      numerator:=Str:Obj?["value":energy["value"],"completeValue":energy["completeValue"],"knownValue":energy["knownValue"],"valueBasis":energy["valueBasis"],"unit":energy["unit"],"sourceIds":energy["sourceIds"]]
      formula:=Str:Obj?["version":1,"expression":"energy / areaM2","energyBoundaryId":boundary["id"],"numerator":numerator,
        "denominator":["value":area["areaM2"],"unit":"m²","sourceRevisions":area["sourceRevisions"]],"value":third["value"],"unit":third["unit"]]
      third["details"]=["areaBasis":extra["areaBasis"],"areaResolution":area,"formula":formula]
    }
    values.insert(2,third)
    return values
  }

  static Str:Obj? metric(Str:Obj? report, Str id, Str category, Str:Obj? boundary)
  {
    row:=EnerCubixMath.maps(((Map)report["summary"])["selectionTotals"]).find |r| {r["categoryId"] == category}
    strict:=row == null ? null : EnerCubixMath.num(row["value"])
    known:=row == null ? null : EnerCubixMath.num(row["knownValue"])
    quality:=row?.get("quality") as Str ?: "missing"
    if (["filtered","substituted","na"].contains(quality)) strict=null
    na:=row?.get("valueType") == "na" || row?.get("knownValueType") == "na"
    if (strict == null && known == null && na) quality="na"
    reason:=row?.get("scopeQuality") as Str
    if (boundary["aggregateAllowed"] == false) reason=boundary["reasonCode"] as Str ?: "overlappingScopes"
    if (reason != null) {strict=null;known=null;quality=reason}
    basis:=strict != null ? "complete" : (known != null ? "knownSubtotal" : "unavailable")
    if ((strict ?: known) != null && (quality == "substituted" || row?.get("knownQuality") == "substituted")) basis="cleanedWithReplacement"
    return ["id":id,"categoryId":category,"value":strict ?: known,"valueType":(strict ?: known) != null ? "number" : (na ? "na" : "null"),"unit":row?.get("unit") ?: "","quality":strict == null && known != null ? "partial" : quality,"valueBasis":basis,"completeValue":strict,"knownValue":known,"sourceIds":row?.get("sourceIds") ?: Str[,],"reasonCodes":strict == null ? [quality] : Str[,],"boundaryId":boundary["id"],"coverage":((Map)report["extra"])["usageCoverage"] ?: Obj?[,]]
  }

  private static Void invalidate(Str:Obj? value, Str reason)
  {value.setAll(["value":null,"valueType":"null","quality":reason,"valueBasis":"unavailable","completeValue":null,"knownValue":null,"reasonCodes":[reason]])}

  static Str:Obj? comparisonValue(Str:Obj? current, [Str:Obj?]? previous, Str:Obj? context)
  {
    reasons:=EnerCubixMath.strings(context["reasonCodes"])
    a:=EnerCubixMath.num(current["value"]);b:=previous == null ? null : EnerCubixMath.num(previous["value"])
    valid:=previous != null && current["completeValue"] != null && previous["completeValue"] != null
    if (a == null) reasons.add("CURRENT_UNAVAILABLE")
    if (b == null) reasons.add("REFERENCE_UNAVAILABLE")
    if (!valid) reasons.add("INCOMPLETE_COVERAGE")
    if (previous != null && (current["unit"] != previous["unit"] || current["categoryId"] != previous["categoryId"])) {valid=false;reasons.add("INCOMPATIBLE_UNIT")}
    if (current["valueBasis"] == "cleanedWithReplacement" || previous?.get("valueBasis") == "cleanedWithReplacement") {valid=false;reasons.add("REPLACEMENT_HISTORY")}
    if (EnerCubixMath.maps(current["coverage"]).any |c| {c["complete"] != true} || (previous != null && EnerCubixMath.maps(previous["coverage"]).any |c| {c["complete"] != true})) {valid=false;reasons.add("INCOMPLETE_COVERAGE")}
    delta:=EnerCubixValue.sum([EnerCubixValue(valid ? a : null,"ok"),EnerCubixValue(valid ? b : null,"ok").scale(-1f)])
    rate:=EnerCubixValue.divide(delta,EnerCubixValue(valid ? b : null,"ok")).scale(100f)
    if (b == 0f) reasons.add("ZERO_REFERENCE")
    return ["kind":context["kind"],"currentRange":context["currentRange"],"referenceRange":context["referenceRange"],"current":a,"reference":b,"comparable":valid,"difference":delta.value,"changeRate":rate.value,"reasonCodes":reasons.unique,"durationDifferenceSeconds":context["durationDifferenceSeconds"]]
  }

  static Str:Obj? events(Str:Obj? observation, Str category, Str:Obj? boundary)
  {
    reasons:=EnerCubixMath.strings(observation["reasonCodes"])
    value:=Str:Obj?["id":"activeAlarms","categoryId":category,"value":null,"valueType":"null","unit":"count","quality":"missing","valueBasis":"unavailable","completeValue":null,"knownValue":null,"sourceIds":Str[,],"reasonCodes":reasons,"boundaryId":boundary["id"],"stateObservedAt":observation["stateObservedAt"]]
    if (!reasons.isEmpty) return value
    roots:=EnerCubixMath.maps(observation["episodes"]).findAll |e| {EnerCubixCockpitIssues.active(e)}.map |e->Str| {e["episodeId"] as Str ?: e["id"].toStr}.unique.sort
    value.setAll(["value":roots.size.toFloat,"valueType":"number","quality":"ok","valueBasis":"currentState","completeValue":roots.size.toFloat,"knownValue":roots.size.toFloat,"sourceIds":roots])
    return value
  }

  static [Str:Obj?][] conclusions([Str:Obj?][] values, Str:Obj? events, Str:Obj? request)
  {
    result:=[Str:Obj?][,]
    limited:=values.find |v| {v["completeValue"] == null}
    if (limited != null) result.add(conclusion("dataQuality","cockpit.conclusion.dataQuality",["metricId":limited["id"],"reasonCodes":limited["reasonCodes"],"value":limited["value"],"from":request["from"],"to":request["to"]],EnerCubixMath.strings(limited["sourceIds"]),1))
    energy:=values.find |v| {v["id"] == "energy"}
    comparison:=energy?.get("comparison") as Map
    if (limited == null && comparison != null && comparison["changeRate"] == null)
      result.add(conclusion("dataQuality","cockpit.conclusion.dataQuality",["metricId":"energy","reasonCodes":comparison["reasonCodes"],"value":energy["value"],"from":request["from"],"to":request["to"],"comparison":comparison],EnerCubixMath.strings(energy["sourceIds"]),1))
    count:=EnerCubixMath.num(events["value"])
    if (count != null && count > 0f) result.add(conclusion("activeEvents","cockpit.conclusion.activeEvents",["count":count,"stateObservedAt":events["stateObservedAt"]],EnerCubixMath.strings(events["sourceIds"]),2))
    if (result.size < 2 && comparison?.get("changeRate") != null)
      result.add(conclusion("comparableChange","cockpit.conclusion.comparableChange",["metricId":"energy","current":comparison["current"],"reference":comparison["reference"],"changeRate":comparison["changeRate"],"unit":energy["unit"],"currentRange":comparison["currentRange"],"referenceRange":comparison["referenceRange"]],EnerCubixMath.strings(energy["sourceIds"]),3))
    return result.size > 2 ? result[0..<2] : result
  }

  private static Str:Obj? conclusion(Str rule, Str key, Str:Obj? args, Str[] refs, Int priority)
  { ["id":rule,"ruleId":"CPT02-"+rule,"ruleVersion":1,"messageKey":key,"args":args,"evidenceRefs":refs,"priority":priority] }
}

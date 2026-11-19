** Available meter-owned use is evidence, not a replacement for strict balance.
** Confirmed direct membership controls child contributions, never query bounds.
internal const class FinEnergyLeakUsage
{
  static Str[] meterIds(Str:Obj? request, [Str:Obj?][] current)
  {
    masters:=FinEnergyMath.strings(FinEnergyDimension("metering",current).normalizeRequest(request)["nodeIds"])
    comparison:=FinEnergyComparisonScope.of(request,current)
    if (comparison != null) return masters.dup.addAll(masters.map |id->Str[]| {comparison.members(id).map |r->Str| {r["id"].toStr}}.flatten).unique
    all:=current.dup
    FinEnergyMath.maps(request["meterHistorySegments"]).findAll |s| {s["known"] == true}.each |s| {all.addAll(FinEnergyTemporalReport.recordsFor(current,s))}
    ids:=all.findAll |r| { ["meter","totalMeter"].contains(r["kind"]) && r["canonicalId"] == null && (masters.contains(r["id"]) || masters.contains(r["meterParentId"]?.toStr ?: "")) }.map |r->Str| {r["id"].toStr}
    FinEnergyLegacyMembership.edges(request).findAll |e| {masters.contains(e["parentId"])}.each |e| {ids.add(e["childId"].toStr)}
    return ids.unique
  }

  static Void attach(Str:Obj? result, Str:Obj? request, [Str:Obj?][] current, [Str:Obj?][] histories)
  {
    extra:=(Str:Obj?)result["extra"]
    recovered:=FinEnergyLegacyMembership.edges(request)
    FinEnergyLegacyMembership.validate(recovered)
    ensureRows(result,request,current)
    totals:=FinEnergyMath.maps(extra["leakTotals"])
    comparison:=FinEnergyComparisonScope.of(request,current)
    from:=DateTime.fromIso(request["from"].toStr); to:=DateTime.fromIso(request["to"].toStr)
    period:=request["period"] as Str ?: "day"
    segments:=FinEnergyMath.maps(request["meterHistorySegments"])
    if (segments.isEmpty) segments=[["from":from.toIso,"to":to.toIso,"known":true,"records":current]]
    ownRows:=[Str:Obj?][,]; branches:=FinEnergyMath.maps(extra["leakBranches"])
    totals.each |total|
    {
      master:=total["nodeId"].toStr; category:=total["categoryId"].toStr
      req:=request.dup.set("categoryId",category).set("nodeIds",[master])
      ids:=meterIds(req,current)
      if (!ids.contains(master)) return // Keep legacy group reports unchanged.
      overview:=FinEnergyFlowOverview.build(req,current,histories,ids)
      own:=FinEnergyMath.maps(overview["rows"])
      area:=FinEnergyArea(current).node(master)
      if (request["perArea"] == true) own.each |r| {normalize(r,area,total["unit"].toStr)}
      own.each |row| {ownRows.add(row.dup.set("masterId",master))}
      main:=own.find |row| {row["nodeId"] == master}
      windows:=[Str:Obj?][,]; unknown:=false
      segments.each |segment|
      {
        start:=DateTime.fromIso(segment["from"].toStr); end:=DateTime.fromIso(segment["to"].toStr)
        if (start < from) start=from
        if (end > to) end=to
        if (end <= start) return
        if (segment["known"] != true) {unknown=true; return}
        rs:=FinEnergyTemporalReport.recordsFor(current,segment)
        dim:=FinEnergyDimension("metering",rs)
        (comparison?.members(master) ?: dim.directChildren(master)).findAll |r| {r["categoryId"] == category}.each |child|
        {
          id:=child["id"].toStr
          last:=windows.findAll |w| {w["id"] == id}.last
          // Coalesce unchanged bindings so unrelated edits cannot split a
          // closed source interval. Never prorate a counter interval.
          if (last != null && last["to"] == start.toIso && binding((Str:Obj?)last["record"]) == binding(child)) last["to"]=end.toIso
          else windows.add(["id":id,"from":start.toIso,"to":end.toIso,"record":child])
        }
      }
      recoveredWindows:=FinEnergyLegacyMembership.windows(req,current,segments,master,category,false)
      windows=mergeWindows(windows.dup.addAll(recoveredWindows.findAll |w| {w["participating"] != false}))
      contributions:=[Str:Obj?][,]
      windows.each |window|
      {
        id:=window["id"].toStr; child:=(Str:Obj?)window["record"]
        if (comparison != null)
        {
          ownUse:=own.find |row| {row["nodeId"] == id}
          if (ownUse != null) contributions.add(ownUse.dup.set("from",from.toIso).set("to",to.toIso))
          return
        }
        source:=current.findAll |r| {r["id"] != id}.dup.add(child)
        part:=req.dup; part.remove("meterHistorySegments"); part["from"]=window["from"]; part["to"]=window["to"]; part["nodeIds"]=[id]
        row:=FinEnergyMath.maps(FinEnergyFlowOverview.build(part,source,histories,[id])["rows"]).first
        if (row != null)
        {
          if (request["perArea"] == true) normalize(row,area,total["unit"].toStr)
          contributions.add(row.dup.set("from",window["from"]).set("to",window["to"]))
        }
      }
      // Removed children remain independently readable during their evidenced
      // binding periods, including a transfer to another master in this range.
      ids.findAll |id| {id != master && !own.any |r| {r["nodeId"] == id}}.each |id|
      {
        parts:=[Str:Obj?][,]
        recovered.findAll |e| {e["childId"] == id && e["categoryId"] == category}.each |e|
        {
          part:=req.dup;part.remove("meterHistorySegments");part["from"]=e["from"];part["to"]=e["to"];part["nodeIds"]=[id]
          a:=DateTime.fromIso(part["from"].toStr);b:=DateTime.fromIso(part["to"].toStr)
          if (a < from) part["from"]=from.toIso
          if (b > to) part["to"]=to.toIso
          if (DateTime.fromIso(part["to"].toStr) <= DateTime.fromIso(part["from"].toStr)) return
          rs:=current.findAll |r| {r["id"] != id}.dup.add(FinEnergyLegacyMembership.record(current,e))
          parts.addAll(FinEnergyMath.maps(FinEnergyFlowOverview.build(part,rs,histories,[id])["rows"]))
        }
        if (parts.isEmpty) return
        combined:=FinEnergyKnownUsage.combine(parts.map |r->FinEnergyValue| {FinEnergyValue(FinEnergyMath.num(r["value"]),r["quality"].toStr,FinEnergyMath.strings(r["sourceIds"]))})
        row:=parts.first.dup;row.setAll(["value":combined.value,"valueType":combined.valueType,"quality":combined.quality,"sourceIds":combined.sources,"removed":true])
        row["activeSeconds"]=parts.reduce(0f) |Float subtotal,r->Float| {subtotal+(FinEnergyMath.num(r["activeSeconds"]) ?: 0f)}
        row["coveredSeconds"]=parts.reduce(0f) |Float subtotal,r->Float| {subtotal+(FinEnergyMath.num(r["coveredSeconds"]) ?: 0f)}
        duration:=FinEnergyMath.num(row["activeSeconds"]) ?: 0f
        row["coverage"]=duration > 0f ? (FinEnergyMath.num(row["coveredSeconds"]) ?: 0f)/duration : 0f
        row["periods"]=parts.map |r->[Str:Obj?][]| {FinEnergyMath.maps(r["periods"])}.flatten
        strict:=FinEnergyValue.sum(parts.map |r->FinEnergyValue| {FinEnergyValue(FinEnergyMath.num(r["completeValue"]),r["completeQuality"].toStr)})
        row["completeValue"]=strict.value;row["completeQuality"]=strict.quality;row["complete"]=parts.all |r| {r["complete"] == true}
        if (request["perArea"] == true) normalize(row,area,total["unit"].toStr)
        own.add(row);ownRows.add(row.dup.set("masterId",master))
      }
      rows:=FinEnergyMath.maps(result["rows"]).findAll |row| {row["nodeId"] == master && row["categoryId"] == category && row["unit"] == total["unit"]}
      rows.each |row|
      {
        bucket:=DateTime.fromIso(row["ts"].toStr).toTimeZone(TimeZone.fromStr(request["tz"] as Str ?: from.tz.name))
        start:=bucket < from ? from : bucket
        end:=FinEnergyMath.nextBucket(bucket,period); if (end > to) end=to
        apply(row,main,contributions,start,end,unknownIn(segments,start,end))
        if (comparison != null) row["membershipQuality"]=comparison.quality(master) ?: "ok"
        if (FinEnergyLegacyMembership.used(recoveredWindows,start,end)) row["membershipQuality"]="snapshotRecovered"
        ids.findAll |id| {id != master}.each |id|
        {
          member:=own.find |r| {r["nodeId"] == id}
          active:=contributions.findAll |r| {r["nodeId"] == id}
          v:=amount(active,start,end)
          existing:=branches.find |r| {r["nodeId"] == master && r["branchId"] == id && r["categoryId"] == category && r["unit"] == total["unit"] && r["ts"] == row["ts"]}
          if (existing == null)
          {
            existing=["nodeId":master,"branchId":id,"name":member?.get("name") ?: id,"categoryId":category,"unit":total["unit"],"ts":row["ts"],"value":null,"quality":"topologyUnknown"]
            branches.add(existing)
          }
          seconds:=activeSeconds(active,start,end)
          participation:=seconds > 0f ? (FinEnergyLegacyMembership.used(recoveredWindows,start,end,id) ? "snapshotRecovered" : "ok") : (FinEnergyLegacyMembership.excluded(recoveredWindows,id,start,end) ? "notParticipating" : (unknownIn(segments,start,end) ? "topologyUnknown" : "notParticipating"))
          existing.setAll(["knownValue":v.value,"knownQuality":v.quality,"activeSeconds":seconds,"participationQuality":participation])
        }
      }
      apply(total,main,contributions,from,to,unknown)
      if (comparison != null) total["membershipQuality"]=comparison.quality(master) ?: "ok"
      if (FinEnergyLegacyMembership.used(recoveredWindows,from,to)) total["membershipQuality"]="snapshotRecovered"
    }
    extra["leakOwnUsage"]=ownRows
    extra["leakBranches"]=branches
    if (comparison != null)
    {
      union:=[Str:Obj?][,];members:=comparison.unionMembers
      members.map |m->Str| {m["categoryId"].toStr}.unique.sort.each |category|
      {
        ids:=members.findAll |m| {m["categoryId"] == category}.map |m->Str| {m["id"].toStr}
        // Reuse the already-read own-use rows. A shared member is counted once,
        // without another history calculation or summing overlapping groups.
        [Str:Obj?][] selected:=ids.map |id->[Str:Obj?]| {existing:=ownRows.find |row| {row["nodeId"] == id && row["categoryId"] == category};return existing ?: ["quality":"missing","completeQuality":"missing"]}
        known:=FinEnergyKnownUsage.combine(selected.map |r->FinEnergyValue| {FinEnergyValue(FinEnergyMath.num(r["value"]),r["quality"].toStr,FinEnergyMath.strings(r["sourceIds"]))})
        strict:=FinEnergyValue.sum(selected.map |r->FinEnergyValue| {FinEnergyValue(FinEnergyMath.num(r["completeValue"]),r["completeQuality"].toStr,FinEnergyMath.strings(r["sourceIds"]))})
        unit:=selected.first?.get("unit") as Str ?: ""
        combinedRow:=Str:Obj?["categoryId":category,"unit":unit,"meterIds":ids,"sourceIds":known.sources,"value":strict.value,"quality":strict.quality]
        combinedRow.setAll(FinEnergyKnownUsage.fields(known))
        rows:=[combinedRow]
        rows.each |row|
        {
          limits:=comparison.snapshots.findAll |s| {s["categoryId"] == category}.map |s->Str| {s["quality"].toStr}.findAll |q| {q != "ok"}
          row["scopeQuality"]=limits.isEmpty ? "ok" : limits.first
          if (!limits.isEmpty) {row["value"]=null;row["quality"]=limits.first}
          if (limits.contains("comparisonUnresolved")) {row["knownValue"]=null;row["knownQuality"]="comparisonUnresolved"}
          if (request["perArea"] == true)
          {
            row["value"]=null;row["knownValue"]=null;row["quality"]="ambiguousArea";row["knownQuality"]="ambiguousArea"
            row["unit"]=unit
          }
          union.add(row)
        }
      }
      extra["comparisonUnion"]=union
    }
    if (!recovered.isEmpty) extra["legacyMembership"]=recovered.map |e->[Str:Obj?]| {e.findAll |v,k| {["childId","parentId","name","from","to","proofId","basis"].contains(k)}}
  }

  private static [Str:Obj?][] mergeWindows([Str:Obj?][] windows)
  {
    sorted:=windows.dup.sort |a,b| { order:=a["id"].toStr <=> b["id"].toStr; return order == 0 ? DateTime.fromIso(a["from"].toStr) <=> DateTime.fromIso(b["from"].toStr) : order }
    out:=[Str:Obj?][,]
    sorted.each |w|
    {
      last:=out.last
      if (last != null && last["id"] == w["id"] && last["to"] == w["from"] && binding((Str:Obj?)last["record"]) == binding((Str:Obj?)w["record"])) last["to"]=w["to"]
      else out.add(w.dup)
    }
    return out
  }

  ** Strict temporal sections may predate registration of the selected meter.
  ** Retain the full requested axis so its own stored history is still visible.
  private static Void ensureRows(Str:Obj? result, Str:Obj? request, [Str:Obj?][] current)
  {
    dim:=FinEnergyDimension(request["dimension"].toStr,current,request["spaceSource"] == "fin")
    req:=dim.normalizeRequest(request)
    ctx:=FinEnergyContext(dim.records,[Str:Obj?][,],DateTime.fromIso(request["from"].toStr).tz)
    extra:=(Str:Obj?)result["extra"]; totals:=FinEnergyMath.maps(extra["leakTotals"])
    rows:=FinEnergyMath.maps(result["rows"]); series:=FinEnergyMath.maps(result["series"])
    FinEnergyMath.strings(req["nodeIds"]).each |id|
    {
      meter:=ctx.byId[id]
      if (meter == null || !["meter","totalMeter"].contains(meter["kind"])) return
      category:=meter["categoryId"].toStr
      if (request["categoryId"] != null && request["categoryId"] != category) return
      unit:=ctx.unit(id,category,request["metric"] as Str ?: "energy")+(request["perArea"] == true ? "/m²" : "")
      total:=totals.find |r| {r["nodeId"] == id && r["categoryId"] == category && r["unit"] == unit}
      if (total == null)
      {
        total=["id":"$id|$category","nodeId":id,"name":meter["name"],"categoryId":category,"unit":unit,"value":null,"quality":"topologyUnknown","total":null,"submeter":null,"difference":null,"percentage":null,"balanceMode":"unknown","lossEligible":false]
        totals.add(total)
      }
      line:=series.find |s| {s["nodeId"] == id && s["categoryId"] == category && s["unit"] == unit}
      if (line == null) {line=["id":"$id|$category","nodeId":id,"name":meter["name"],"categoryId":category,"unit":unit,"points":[Str:Obj?][,]];series.add(line)}
      points:=FinEnergyMath.maps(line["points"])
      period:=request["period"] as Str ?: "day"
      cursor:=FinEnergyMath.bucket(DateTime.fromIso(request["from"].toStr).toTimeZone(TimeZone.fromStr(request["tz"] as Str ?: ctx.tz.name)),period)
      to:=DateTime.fromIso(request["to"].toStr)
      while (cursor < to)
      {
        if (!rows.any |r| {r["nodeId"] == id && r["categoryId"] == category && r["unit"] == unit && r["ts"] == cursor.toIso}) rows.add(total.dup.set("ts",cursor.toIso))
        if (!points.any |p| {p["ts"] == cursor.toIso}) points.add(["ts":cursor.toIso,"value":null,"quality":"topologyUnknown","sourceIds":Str[,]])
        cursor=FinEnergyMath.nextBucket(cursor,period)
      }
      line["points"]=points
    }
    extra["leakTotals"]=totals; result["rows"]=rows; result["series"]=series
  }

  private static Str:Obj? binding(Str:Obj? record)
  { record.findAll |v,k| {["id","kind","pointId","expressionId","categoryId","subcategoryId","tariffId","unit","maximum","configurationError"].contains(k)} }

  private static Bool unknownIn([Str:Obj?][] segments, DateTime from, DateTime to)
  { segments.any |s| {s["known"] != true && DateTime.fromIso(s["from"].toStr) < to && DateTime.fromIso(s["to"].toStr) > from} }

  private static Void normalize(Str:Obj? row, Str:Obj? areaBasis, Str unit)
  {
    area:=FinEnergyMath.num(areaBasis["value"])
    row["baseValue"]=row["value"];row["baseUnit"]=row["unit"]
    values:=FinEnergyMath.maps(row["periods"]).dup.add(row)
    values.each |value|
    {
      n:=FinEnergyMath.num(value["value"])
      value["value"]=area != null && area > 0f && n != null ? n/area : null
      if (area == null || area <= 0f) value["quality"]=areaBasis["quality"]
    }
    n:=FinEnergyMath.num(row["completeValue"])
    row["completeValue"]=area != null && area > 0f && n != null ? n/area : null
    if (area == null || area <= 0f) row["completeQuality"]=areaBasis["quality"]
    row["unit"]=unit
  }

  private static Void apply(Str:Obj? row, [Str:Obj?]? main, [Str:Obj?][] contributions, DateTime from, DateTime to, Bool unknown)
  {
    a:=main == null ? FinEnergyValue() : amount([main],from,to)
    b:=amount(contributions,from,to)
    if (activeSeconds(contributions,from,to) == 0f) b=FinEnergyValue(null,unknown ? "topologyUnknown" : "notParticipating")
    row.setAll(["knownTotal":a.value,"knownTotalQuality":a.quality,"knownSubmeter":b.value,"knownSubmeterQuality":b.quality,"membershipQuality":unknown ? "topologyUnknown" : "ok"])
  }

  private static FinEnergyValue amount([Str:Obj?][] rows, DateTime from, DateTime to)
  {
    values:=FinEnergyValue[,]
    rows.each |row|
    {
      FinEnergyMath.maps(row["periods"]).each |p|
      {
        at:=DateTime.fromIso(p["from"].toStr)
        if (at >= from && at < to) values.add(FinEnergyValue(FinEnergyMath.num(p["value"]),p["quality"].toStr,[p["pointId"].toStr]))
      }
    }
    return FinEnergyKnownUsage.combine(values)
  }

  private static Float activeSeconds([Str:Obj?][] rows, DateTime from, DateTime to)
  {
    total:=0f
    rows.each |r|
    {
      start:=DateTime.fromIso(r["from"].toStr); end:=DateTime.fromIso(r["to"].toStr)
      if (start < from) start=from
      if (end > to) end=to
      if (end > start) total+=(end-start).ticks.toFloat/1sec.ticks.toFloat
    }
    return total
  }
}

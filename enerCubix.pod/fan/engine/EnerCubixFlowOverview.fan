** Independent meter history over the requested range. Topology only decides
** membership during confirmed periods; it never manufactures meter readings.
internal const class EnerCubixFlowOverview
{
  static [Str:Obj?][] inventory(Str:Obj? request, [Str:Obj?][] current)
  {
    byId:=Str:[Str:Obj?][:]
    // The earliest captured binding indexes the unconfirmed past. Later bindings
    // are used only in their own effective periods.
    EnerCubixMath.maps(request["meterHistorySegments"]).each |s|
    {
      if (s["known"] != true) return
      EnerCubixTemporalReport.recordsFor(current,s).each |r| { if (!byId.containsKey(r["id"].toStr)) byId[r["id"].toStr]=r }
    }
    current.each |r| { if (!byId.containsKey(r["id"].toStr)) byId[r["id"].toStr]=r }
    return byId.vals
  }

  static [Str:Obj?][] members(Str:Obj? request, [Str:Obj?][] records, Bool known)
  {
    ids:=EnerCubixMath.strings(request["nodeIds"])
    meters:=records.findAll |r| { ["meter","totalMeter"].contains(r["kind"]) && r["categoryId"] == request["categoryId"] }
    if (ids.isEmpty) return meters
    // Unconfirmed topology permits the explicitly selected meter only.
    if (!known) return meters.findAll |r| { ids.contains(r["id"]) }
    if (!meters.any |r| { ids.contains(r["id"]) }) return [Str:Obj?][,]
    dim:=EnerCubixDimension("metering",records)
    return EnerCubixMath.maps(EnerCubixEnergyFlow.scope(dim.normalizeRequest(request),dim)["selected"])
  }

  static Str:Obj? build(Str:Obj? request, [Str:Obj?][] current, [Str:Obj?][] histories, Str[]? ownIds := null)
  {
    from:=DateTime.fromIso(request["from"].toStr); to:=DateTime.fromIso(request["to"].toStr)
    cutoff:=EnerCubixKnownUsage.cutoff(request); limit:=to < cutoff ? to : cutoff
    index:=inventory(request,current); candidates:=Str:[Str:Obj?][:]
    segments:=EnerCubixMath.maps(request["meterHistorySegments"])
    if (segments.isEmpty) segments=[["from":from.toIso,"to":to.toIso,"known":true,"records":current]]
    unknownSeconds:=0f; active:=Str:Float[:]
    segments.each |segment|
    {
      start:=DateTime.fromIso(segment["from"].toStr); end:=DateTime.fromIso(segment["to"].toStr)
      if (start < from) start=from
      if (end > to) end=to
      if (end <= start) return
      known:=segment["known"] == true
      if (!known) unknownSeconds+=(end-start).ticks.toFloat/1sec.ticks.toFloat
      records:=known ? EnerCubixTemporalReport.recordsFor(current,segment) : index
      selected:=ownIds == null ? members(request,records,known) : records.findAll |r| {ownIds.contains(r["id"]) && r["categoryId"] == request["categoryId"] && ["meter","totalMeter"].contains(r["kind"])}
      selected.each |meter|
      {
        id:=meter["id"].toStr; candidates[id]=meter
        active[id]=(active[id] ?: 0f)+(end-start).ticks.toFloat/1sec.ticks.toFloat
      }
    }
    if (ownIds != null) index.findAll |r| {ownIds.contains(r["id"]) && r["categoryId"] == request["categoryId"]}.each |r| {if (!candidates.containsKey(r["id"].toStr)) candidates[r["id"].toStr]=r}
    // Unknown topology does not remove a meter's own stored consumption. Current
    // unassigned meters remain visible, independently from verified flow/balance.
    if (EnerCubixMath.strings(request["nodeIds"]).isEmpty)
      index.findAll |r| {["meter","totalMeter"].contains(r["kind"]) && r["categoryId"] == request["categoryId"]}.each |r| {if (!candidates.containsKey(r["id"].toStr)) candidates[r["id"].toStr]=r}
    [Str:Obj?][] shared:=index.map |record->[Str:Obj?]|
    {
      latest:=current.find |r| {r["id"] == record["id"]}
      oldPoint:=record["pointId"] as Str ?: ""
      newPoint:=latest?.get("pointId") as Str ?: ""
      return latest != null && oldPoint == newPoint ? latest : record
    }
    strict:=EnerCubixContext(shared,histories,from.tz)
    strict.comparison=EnerCubixComparisonScope.of(request,shared)
    known:=EnerCubixContext.known(strict,limit)
    duration:=(to-from).ticks.toFloat/1sec.ticks.toFloat
    [Str:Obj?][] result:=candidates.keys.sort.map |id->[Str:Obj?]|
    {
      meter:=candidates[id]
      if (strict.comparison != null && meter["_comparisonPointReadable"] == false)
        return ["id":id,"nodeId":id,"name":meter["name"],"categoryId":meter["categoryId"],"unit":meter["unit"] ?: "","value":null,"valueType":"null","quality":"forbidden","completeValue":null,"completeQuality":"forbidden","sourceIds":Str[,],"activeSeconds":duration,"coveredSeconds":0f,"coverage":0f,"complete":false,"periods":[Str:Obj?][,],"meterIds":[id]]
      latest:=current.find |r| {r["id"] == id && ["meter","totalMeter"].contains(r["kind"])}
      point:=meter["pointId"] as Str ?: ""
      latestPoint:=latest?.get("pointId") as Str ?: ""
      if (latest != null && latestPoint == point) meter=latest
      bindings:=[point]
      segments.findAll |segment| {segment["known"] == true}.each |segment|
      {
        own:=EnerCubixTemporalReport.recordsFor(current,segment).find |r| {r["id"] == id}
        if (own != null) bindings.add(own["pointId"] as Str ?: "")
      }
      if (latest != null) bindings.add(latestPoint)
      windows:=[Str:Obj?][,]
      if (latest != null && bindings.unique.size == 1) windows.add(["from":from.toIso,"to":to.toIso,"pointId":point])
      else segments.each |segment|
      {
        records:=segment["known"] == true ? EnerCubixTemporalReport.recordsFor(current,segment) : index
        own:=records.find |r| {r["id"] == id}
        if (own == null) return
        start:=DateTime.fromIso(segment["from"].toStr); end:=DateTime.fromIso(segment["to"].toStr)
        if (start < from) start=from
        if (end > to) end=to
        if (end <= start) return
        source:=own["pointId"] as Str ?: ""
        last:=windows.last
        if (last != null && last["to"] == start.toIso && last["pointId"] == source) last["to"]=end.toIso
        else windows.add(["from":start.toIso,"to":end.toIso,"pointId":source])
      }
      values:=EnerCubixValue[,]; completeValues:=EnerCubixValue[,]; periods:=[Str:Obj?][,]
      metric:=ownIds == null ? "energy" : (request["metric"] as Str ?: "energy")
      category:=meter["categoryId"].toStr; unit:=strict.unit(id,category,metric)
      covered:=0f; lifetime:=0f
      windows.each |window|
      {
        start:=DateTime.fromIso(window["from"].toStr); finish:=DateTime.fromIso(window["to"].toStr)
        lifetime+=(finish-start).ticks.toFloat/1sec.ticks.toFloat
        source:=window["pointId"].toStr
        binding:=meter.dup.set("pointId",source)
        own:=EnerCubixContext.bound(strict,id,binding)
        observed:=EnerCubixContext.known(own,finish < limit ? finish : limit)
        cursor:=start
        while (cursor < finish)
        {
          end:=EnerCubixMath.floorHour(cursor)+1hr; if (end > finish) end=finish
          v:=observed.node(id,category,cursor,end,metric)
          values.add(v); completeValues.add(own.node(id,category,cursor,end,metric))
          last:=periods.last
          if (ownIds == null && last != null && last["quality"] == v.quality && last["to"] == cursor.toIso && last["pointId"] == source)
          {
            last["to"]=end.toIso
            if (v.value != null) last["value"]=(EnerCubixMath.num(last["value"]) ?: 0f)+v.value
          }
          else periods.add(["from":cursor.toIso,"to":end.toIso,"value":v.value,"quality":v.quality,"pointId":source])
          cursor=end
        }
        observed.knownReads.vals.findAll |read| {read["pointId"] == source}.each |read| {covered+=EnerCubixMath.num(read["coveredSeconds"]) ?: 0f}
        known.knownReads.setAll(observed.knownReads)
      }
      value:=EnerCubixKnownUsage.combine(values)
      completeValue:=EnerCubixValue.sum(completeValues)
      complete:=value.value != null && completeValue.value != null && completeValue.reliable && covered >= lifetime
      return ["id":id,"nodeId":id,"name":meter["name"],"categoryId":category,"unit":unit,"value":value.value,"valueType":value.valueType,"quality":value.quality,"completeValue":completeValue.value,"completeQuality":completeValue.quality,"sourceIds":value.sources,"activeSeconds":lifetime,"topologyActiveSeconds":active[id] ?: 0f,"coveredSeconds":covered,"coverage":lifetime > 0f ? (covered/lifetime).min(1f) : 0f,"complete":complete,"periods":periods,"substituted":value.quality == "substituted","removed":latest == null,"pointId":point,"meterIds":[id]]
    }
    ids:=EnerCubixMath.strings(request["nodeIds"])
    totals:=[Str:Obj?][,]
    // A selected master is an independent source. Never add its descendant
    // rows to it merely because they also appear in the overview.
    roots:=ids.isEmpty ? current.findAll |r| {r["kind"] == "totalMeter" && r["meterParentId"] == null && r["categoryId"] == request["categoryId"]} : shared.findAll |r| {ids.contains(r["id"])}
    roots=strict.selectionMeters(roots)
    selected:=result.findAll |row| {roots.any |root| {root["id"] == row["id"]}}
    strictValue:=EnerCubixValue.sum(selected.map |row->EnerCubixValue| {EnerCubixValue(EnerCubixMath.num(row["completeValue"]),row["completeQuality"].toStr,EnerCubixMath.strings(row["sourceIds"]))})
    knownValue:=EnerCubixKnownUsage.combine(selected.map |row->EnerCubixValue| {EnerCubixValue(EnerCubixMath.num(row["value"]),row["quality"].toStr,EnerCubixMath.strings(row["sourceIds"]))})
    unit:=result.first?.get("unit") as Str ?: ""
    row:=Str:Obj?["id":request["categoryId"].toStr+"|"+unit,"categoryId":request["categoryId"],"unit":unit,"value":strictValue.value,"quality":strictValue.quality,"meterIds":roots.map |root->Str| {root["id"].toStr},"sourceIds":knownValue.sources]
    row.setAll(EnerCubixKnownUsage.fields(knownValue)); totals.add(row)
    return ["from":from.toIso,"to":to.toIso,"asOf":cutoff.toIso,"unknownTopologySeconds":unknownSeconds,"rows":result,"basis":"closedSourceIntervals","selectionTotals":totals,"knownUsage":["basis":"closedSourceIntervals","asOf":cutoff.toIso,"sourceUsage":EnerCubixKnownUsage.evidence(known.knownReads.vals)]]
  }
}

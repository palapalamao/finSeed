** Independent meter history over the requested range. Topology only decides
** membership during confirmed periods; it never manufactures meter readings.
internal const class FinEnergyFlowOverview
{
  static [Str:Obj?][] inventory(Str:Obj? request, [Str:Obj?][] current)
  {
    byId:=Str:[Str:Obj?][:]
    // The earliest captured binding indexes the unconfirmed past. Later bindings
    // are used only in their own effective periods.
    FinEnergyMath.maps(request["meterHistorySegments"]).each |s|
    {
      if (s["known"] != true) return
      FinEnergyTemporalReport.recordsFor(current,s).each |r| { if (!byId.containsKey(r["id"].toStr)) byId[r["id"].toStr]=r }
    }
    current.each |r| { if (!byId.containsKey(r["id"].toStr)) byId[r["id"].toStr]=r }
    return byId.vals
  }

  static [Str:Obj?][] members(Str:Obj? request, [Str:Obj?][] records, Bool known)
  {
    ids:=FinEnergyMath.strings(request["nodeIds"])
    meters:=records.findAll |r| { ["meter","totalMeter"].contains(r["kind"]) && r["categoryId"] == request["categoryId"] }
    if (ids.isEmpty) return meters
    // Unconfirmed topology permits the explicitly selected meter only.
    if (!known) return meters.findAll |r| { ids.contains(r["id"]) }
    if (!meters.any |r| { ids.contains(r["id"]) }) return [Str:Obj?][,]
    dim:=FinEnergyDimension("metering",records)
    return FinEnergyMath.maps(FinEnergyEnergyFlow.scope(dim.normalizeRequest(request),dim)["selected"])
  }

  static Str:Obj? build(Str:Obj? request, [Str:Obj?][] current, [Str:Obj?][] histories, Str[]? ownIds := null)
  {
    from:=DateTime.fromIso(request["from"].toStr); to:=DateTime.fromIso(request["to"].toStr)
    cutoff:=FinEnergyKnownUsage.cutoff(request); limit:=to < cutoff ? to : cutoff
    index:=inventory(request,current); candidates:=Str:[Str:Obj?][:]
    segments:=FinEnergyMath.maps(request["meterHistorySegments"])
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
      records:=known ? FinEnergyTemporalReport.recordsFor(current,segment) : index
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
    if (FinEnergyMath.strings(request["nodeIds"]).isEmpty)
      index.findAll |r| {["meter","totalMeter"].contains(r["kind"]) && r["categoryId"] == request["categoryId"]}.each |r| {if (!candidates.containsKey(r["id"].toStr)) candidates[r["id"].toStr]=r}
    [Str:Obj?][] shared:=index.map |record->[Str:Obj?]|
    {
      latest:=current.find |r| {r["id"] == record["id"]}
      oldPoint:=record["pointId"] as Str ?: ""
      newPoint:=latest?.get("pointId") as Str ?: ""
      return latest != null && oldPoint == newPoint ? latest : record
    }
    strict:=FinEnergyContext(shared,histories,from.tz)
    strict.comparison=FinEnergyComparisonScope.of(request,shared)
    known:=FinEnergyContext.known(strict,limit)
    duration:=(to-from).ticks.toFloat/1sec.ticks.toFloat
    idsByOrder:=candidates.keys.sort
    capture:=request["_cockpitDiagnosticCapture"] == true && request["_cockpitCategoryId"] != null
    [Str:Obj?][] result:=idsByOrder.map |id,position->[Str:Obj?]|
    {
      quota:=capture ? periodQuota(idsByOrder.size,position) : 0
      periodCount:=0
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
        own:=FinEnergyTemporalReport.recordsFor(current,segment).find |r| {r["id"] == id}
        if (own != null) bindings.add(own["pointId"] as Str ?: "")
      }
      if (latest != null) bindings.add(latestPoint)
      windows:=[Str:Obj?][,]
      if (latest != null && bindings.unique.size == 1) windows.add(["from":from.toIso,"to":to.toIso,"pointId":point])
      else segments.each |segment|
      {
        records:=segment["known"] == true ? FinEnergyTemporalReport.recordsFor(current,segment) : index
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
       values:=FinEnergyValueFold.known; completeValues:=FinEnergyValueFold.strict; periods:=[Str:Obj?][,]
      metric:=request["metric"] as Str ?: "energy"
      category:=meter["categoryId"].toStr; unit:=strict.unit(id,category,metric)
      covered:=0f; lifetime:=0f
      windows.each |window|
      {
        start:=DateTime.fromIso(window["from"].toStr); finish:=DateTime.fromIso(window["to"].toStr)
        lifetime+=(finish-start).ticks.toFloat/1sec.ticks.toFloat
        source:=window["pointId"].toStr
        binding:=meter.dup.set("pointId",source)
        own:=FinEnergyContext.bound(strict,id,binding)
        observed:=FinEnergyContext.known(own,finish < limit ? finish : limit)
        cursor:=start
        while (cursor < finish)
        {
          end:=FinEnergyMath.floorHour(cursor)+1hr; if (end > finish) end=finish
          v:=observed.node(id,category,cursor,end,metric)
          values.add(v); completeValues.add(own.node(id,category,cursor,end,metric))
          last:=periods.last
          if(capture)
          {
            periodCount++
            if(periods.size < quota) periods.add(["from":cursor.toIso,"to":end.toIso,"value":v.value,"quality":v.quality,"pointId":source])
          }
          else if (ownIds == null && last != null && last["quality"] == v.quality && last["to"] == cursor.toIso && last["pointId"] == source)
          {
            last["to"]=end.toIso
            if (v.value != null) last["value"]=(FinEnergyMath.num(last["value"]) ?: 0f)+v.value
          }
          else periods.add(["from":cursor.toIso,"to":end.toIso,"value":v.value,"quality":v.quality,"pointId":source])
          cursor=end
        }
        observed.knownReads.vals.findAll |read| {read["pointId"] == source}.each |read| {covered+=FinEnergyMath.num(read["coveredSeconds"]) ?: 0f}
        known.mergeKnown(observed)
      }
       value:=values.finish
       completeValue:=completeValues.finish
      complete:=value.value != null && completeValue.value != null && completeValue.reliable && covered >= lifetime
      row:=Str:Obj?["id":id,"nodeId":id,"name":meter["name"],"categoryId":category,"unit":unit,"value":value.value,"valueType":value.valueType,"quality":value.quality,"completeValue":completeValue.value,"completeQuality":completeValue.quality,"sourceIds":value.sources,"activeSeconds":lifetime,"topologyActiveSeconds":active[id] ?: 0f,"coveredSeconds":covered,"coverage":lifetime > 0f ? (covered/lifetime).min(1f) : 0f,"complete":complete,"periods":periods,"substituted":value.quality == "substituted","removed":latest == null,"pointId":point,"meterIds":[id]]
      if(capture) row.setAll(["periodsCaptureId":Uuid().toStr,"periodRecordTotalCount":periodCount,"periodsReturnedCount":periods.size,"periodsTruncated":periodCount > periods.size,"periodsTruncationReason":periodCount > periods.size ? "cockpitPeriodCaptureLimit" : null])
      return row
    }
    ids:=FinEnergyMath.strings(request["nodeIds"])
    totals:=[Str:Obj?][,]
    // A selected master is an independent source. Never add its descendant
    // rows to it merely because they also appear in the overview.
    roots:=ids.isEmpty ? current.findAll |r| {r["kind"] == "totalMeter" && r["meterParentId"] == null && r["categoryId"] == request["categoryId"]} : shared.findAll |r| {ids.contains(r["id"])}
    roots=strict.selectionMeters(roots)
    selected:=result.findAll |row| {roots.any |root| {root["id"] == row["id"]}}
    strictValue:=FinEnergyValue.sum(selected.map |row->FinEnergyValue| {FinEnergyValue(FinEnergyMath.num(row["completeValue"]),row["completeQuality"].toStr,FinEnergyMath.strings(row["sourceIds"]))})
    knownValue:=FinEnergyKnownUsage.combine(selected.map |row->FinEnergyValue| {FinEnergyValue(FinEnergyMath.num(row["value"]),row["quality"].toStr,FinEnergyMath.strings(row["sourceIds"]))})
    unit:=result.first?.get("unit") as Str ?: ""
    row:=Str:Obj?["id":request["categoryId"].toStr+"|"+unit,"categoryId":request["categoryId"],"unit":unit,"value":strictValue.value,"quality":strictValue.quality,"meterIds":roots.map |root->Str| {root["id"].toStr},"sourceIds":knownValue.sources]
    row.setAll(FinEnergyKnownUsage.fields(knownValue)); totals.add(row)
    return ["from":from.toIso,"to":to.toIso,"asOf":cutoff.toIso,"unknownTopologySeconds":unknownSeconds,"rows":result,"basis":"closedSourceIntervals","selectionTotals":totals,"knownUsage":known.knownEvidence(false).set("asOf",cutoff.toIso)]
  }
  internal static Int periodQuota(Int objects,Int position)
  {1000/objects+(position < 1000%objects ? 1 : 0)}
}

** Context observations are appended only after the business report is complete.
** They never enter usage, conversion, tariff, share or balance calculations.
internal class EnerCubixReferenceCurves
{
  static Bool supported(Str:Obj? request)
  {
    kind:=request["kind"]?.toStr ?: "profile"
    return ["profile","daily","utility","primary","leak"].contains(kind) ||
      (kind == "comparison" && request["otherFrom"] != null && request["otherTo"] != null)
  }

  static Str[] pointIds(Str:Obj? request, [Str:Obj?][] records)
  {
    if (!supported(request)) return Str[,]
    ids:=EnerCubixMath.strings(request["referenceIds"])
    return records.findAll |r| { ["sensor","binding"].contains(r["kind"]) && r["pointId"] != null && (ids.contains(r["pointId"].toStr) || ids.contains(r["id"]?.toStr ?: "")) }
      .map |r->Str| {r["pointId"].toStr}.unique
  }

  static Void attach(Str:Obj? result, Str:Obj? request, [Str:Obj?][] records, [Str:Obj?][] histories)
  {
    ids:=pointIds(request,records)
    if (ids.isEmpty) return
    from:=DateTime.fromIso(request["from"].toStr)
    tz:=TimeZone.fromStr(request["tz"]?.toStr ?: from.tz.name)
    from=from.toTimeZone(tz)
    to:=DateTime.fromIso(request["to"].toStr).toTimeZone(tz)
    series:=EnerCubixMath.maps(result["series"]); rows:=EnerCubixMath.maps(result["rows"])
    warnings:=EnerCubixMath.strings(result["warnings"])
    metadata:=[Str:Obj?][,]
    ids.each |id|
    {
      bindings:=records.findAll |r| {["sensor","binding"].contains(r["kind"]) && r["pointId"] == id}
      record:=bindings.find |r| {r["role"] == "reference"} ?: bindings.first
      data:=histories.find |h| {h["pointId"] == id}
      // Even when an energy point is explicitly used for context, read its raw
      // observations, not cleaned interval use or a converted business metric.
      if (data != null)
      {
        data=data.dup
        if (data["rawSamples"] != null) data["samples"]=data["rawSamples"]
        if (data["rawQuality"] != null) data["quality"]=data["rawQuality"]
      }
      history:=data == null ? null : EnerCubixHistoryData(data)
      unit:=history?.unit ?: (record["unit"]?.toStr ?: "")
      alias:=record["alias"]?.toStr?.trim
      name:=alias != null && !alias.isEmpty ? alias : (record["name"]?.toStr ?: id)
      ranges:=[["from":from,"to":to,"period":"current"]]
      if (request["kind"] == "comparison") ranges.add(["from":DateTime.fromIso(request["otherFrom"].toStr).toTimeZone(tz),"to":DateTime.fromIso(request["otherTo"].toStr).toTimeZone(tz),"period":"comparison"])
      ranges.each |range|
      {
        start:=(DateTime)range["from"]; end:=(DateTime)range["to"]
        points:=aggregate(history,request,start,end)
        role:=range["period"].toStr
        seriesId:=id+"|reference"+(role == "comparison" ? "|comparison" : "")
        line:=Str:Obj?["id":seriesId,"nodeId":record["id"],"name":name,"unit":unit,"role":"reference","referencePeriod":role,"points":points]
        series.add(line)
        points.each |point| {row:=point.dup.setAll(["key":seriesId+"|"+point["ts"],"id":seriesId,"nodeId":record["id"],"name":name,"unit":unit,"role":"reference","referencePeriod":role]); rows.add(row)}
        valid:=0; expected:=0; na:=0; missing:=0
        points.each |point| {valid+=(Int)point["validSamples"];expected+=(Int)point["expectedSamples"];na+=(Int)point["naSamples"];missing+=(Int)point["missingSamples"]}
        metadata.add(["id":seriesId,"pointId":id,"referencePeriod":role,"from":start.toIso,"to":end.toIso,"aggregation":"availableHourlyMean","validSamples":valid,"expectedSamples":expected,"naSamples":na,"missingSamples":missing])
        if (valid < expected) warnings.add("$name : "+(valid == 0 ? "referenceMissingData" : "referencePartialCoverage"))
      }
    }
    result["series"]=series;result["rows"]=rows;result["warnings"]=warnings.unique
    extra:=(Str:Obj?)(result["extra"] ?: Str:Obj?[:]);extra["referenceCurves"]=metadata;result["extra"]=extra
  }

  private static [Str:Obj?][] aggregate(EnerCubixHistoryData? history, Str:Obj? request, DateTime from, DateTime to)
  {
    daily:=request["kind"] == "daily"
    period:=request["period"]?.toStr ?: "day"
    duration:=request["kind"] == "comparison" && request["comparisonAlignment"] == "duration"
    cutoff:=EnerCubixKnownUsage.cutoff(request)
    buckets:=Str:[Str:Obj?][][:]; dates:=Str:DateTime[:]
    if (daily) (0..23).each |hour| {at:=from.date.toDateTime(Time(hour,0),from.tz);buckets[at.toIso]=[Str:Obj?][,];dates[at.toIso]=at}
    at:=from
    while (at < to)
    {
      bucket:=daily ? from.date.toDateTime(Time(at.hour,0),from.tz) : EnerCubixMath.bucket(at,period)
      next:=EnerCubixMath.floorHour(at)+1hr
      if (duration)
      {
        span:=period == "hour" ? 1hr : (period == "week" ? 7day : 1day)
        bucket=from+Duration(((at-from).ticks/span.ticks)*span.ticks)
        if (bucket+span < next) next=bucket+span
      }
      if (next > to) next=to
      readTo:=next < cutoff ? next : cutoff
      value:=at < readTo ? (history?.read(at,readTo,true) ?: EnerCubixValue()) : EnerCubixValue()
      key:=bucket.toIso
      if (!buckets.containsKey(key)) {buckets[key]=[Str:Obj?][,];dates[key]=bucket}
      buckets[key].add(["value":value.value,"quality":value.quality,"partial":readTo < next,"seconds":(readTo-at).ticks.max(0).toFloat/1sec.ticks.toFloat])
      at=next
    }
    points:=[Str:Obj?][,]
    dates.keys.sort |a,b| {dates[a]<=>dates[b]}.each |key|
    {
      values:=buckets[key];valid:=values.findAll |v| {v["value"] != null}
      na:=values.findAll |v| {v["quality"] == "na"}.size
      weight:=0f;total:=0f
      valid.each |v| {seconds:=(Float)v["seconds"];weight+=seconds;total+=(Float)v["value"]*seconds}
      value:=weight > 0f ? total/weight : null
      quality:=value == null ? (na > 0 ? "na" : "missing") : (valid.size < values.size || values.any |v| {v["partial"] == true} ? "partial" : "ok")
      point:=EnerCubixValue(value,quality,history?.sources ?: Str[,]).point(dates[key])
      point.setAll(["validSamples":valid.size,"expectedSamples":values.size,"naSamples":na,"missingSamples":values.size-valid.size-na])
      if (daily) point["hour"]=dates[key].hour
      points.add(point)
    }
    return points
  }
}

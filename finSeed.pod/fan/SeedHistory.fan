using haystack
using skyarcd

** Read-only native FIN history adapter; all arithmetic remains in SeedEngine.
class SeedHistory
{
  static [Str:Obj?][] load(Context cx, Str:Obj? request, [Str:Obj?][] records)
  {
    plan:=range(request,records)
    from:=(DateTime)plan["from"]; to:=(DateTime)plan["to"]
    out:=[Str:Obj?][,]
    modeRecords:=SeedDimension.active(request) ? SeedDimension(request["dimension"].toStr,records,request["spaceSource"] == "fin").records : records
    pointIds(request,records).each |id|
    {
      Dict? point:=null
      try
      {
        point=cx.db.readById(Ref(id),false)
        if (point == null || !point.has("his")) { out.add(unavailable(id,"missing")); return }
        if (!cx.canRead(point)) { out.add(unavailable(id,"forbidden")); return }
        items:=HisItem[,]
        pointTz:=TimeZone.fromStr(point["tz"]?.toStr ?: from.tz.name,false) ?: from.tz
        // HxHisService may supply leading/trailing items. A modest extra day also
        // covers subdaily interval-end values on implementations that clip the span.
        readStart:=(from-1day).toTimeZone(pointTz); readEnd:=(to+1day).toTimeZone(pointTz)
        cx.rt.his.read(point,Span.makeAbs(readStart,readEnd),readOptions(point)) |HisItem item|
        {
          if (items.size >= 1000000) throw ArgErr("History exceeds 1000000 raw samples")
          items.add(item)
        }
        overrides:=modeRecords.findAll |r| { r["pointId"] == id && r["historyMode"] != null && r["historyMode"] != "auto" }.map |r->Str| { r["historyMode"].toStr }.unique
        if (overrides.size > 1) throw ArgErr("Conflicting Seed history modes")
        out.add(normalize(point,items,from,to,request["kind"] == "trend",overrides.first))
      }
      catch (Err e) { out.add(unavailable(id,"historyReadError")) }
    }
    return out
  }

  internal static Str[] pointIds(Str:Obj? request, [Str:Obj?][] records)
  {
    plan:=dependencies(request,records)
    return ((Str[])plan["points"]).sort
  }

  internal static Str:Obj? range(Str:Obj? request, [Str:Obj?][] records)
  {
    from:=DateTime.fromIso(request["from"]?.toStr ?: ""); to:=DateTime.fromIso(request["to"]?.toStr ?: "")
    tz:=TimeZone.fromStr(request["tz"]?.toStr ?: from.tz.name)
    from=from.toTimeZone(tz); to=to.toTimeZone(tz)
    if (request["otherFrom"] != null && request["otherTo"] != null)
    {
      otherFrom:=DateTime.fromIso(request["otherFrom"].toStr).toTimeZone(tz)
      otherTo:=DateTime.fromIso(request["otherTo"].toStr).toTimeZone(tz)
      if (otherTo <= otherFrom) throw ArgErr("Invalid comparison range")
      if (otherFrom < from) from=otherFrom
      if (otherTo > to) to=otherTo
    }
    if (to <= from) throw ArgErr("Invalid history range")
    if (request["metric"] == "cost")
    {
      plan:=dependencies(request,records); nodes:=(Str[])plan["nodes"]
      ctx:=SeedContext(records,[Str:Obj?][,],tz)
      records.each |r|
      {
        if (!nodes.contains(r["id"]?.toStr ?: "")) return
        tariff:=ctx.tariff(r)
        mode:=tariff?.get("mode")?.toStr
        if (mode == "yearlyBlock") from=SeedMath.bucket(from,"year")
        else if (mode == "monthlyBlock") from=SeedMath.bucket(from,"month")
      }
    }
    from=SeedMath.floorHour(from)
    end:=SeedMath.floorHour(to); if (end < to) end+=1hr
    if ((end-from).ticks/1hr.ticks > 100000) throw ArgErr("History range exceeds 100000 hours")
    return ["from":from,"to":end]
  }

  internal static Str:Obj? normalize(Dict point, HisItem[] items, DateTime from, DateTime to, Bool raw := false, Str? historyMode := null)
  {
    mode:=historyMode ?: "auto"
    if (mode == "auto")
    {
      mode=point["hisMode"]?.toStr ?: "sampled"
      if (point.has("hisTotalized")) mode="cumulative"
      else if (mode == "consumption") mode="interval"
    }
    byTime:=Int:HisItem[:]; items.each |item| { byTime[item.ts.ticks]=item }
    sorted:=byTime.vals.sort |a,b| { a.ts <=> b.ts }
    out:=[Str:Obj?]["pointId":point.id.toStr,"unit":point["unit"]?.toStr ?: "","mode":mode,"quality":"ok"]
    samples:=[Str:Obj?][,]
    rawSamples:=sorted.map |item->[Str:Obj?]| { ["ts":item.ts.toTimeZone(from.tz).toIso,"value":number(item.val)] }
    out["rawSamples"]=rawSamples; out["rawQuality"]="ok"
    if (mode != "interval" || raw)
    {
      out["samples"]=rawSamples; return out
    }
    interval:=cadence(point,sorted)
    if (interval == null) { out["quality"]="missingInterval"; out["samples"]=samples; return out }
    known:=point["hisCollectInterval"] != null || point["hisInterval"] != null
    estimated:=!known
    hours:=Int:SeedHourAccumulator[:]
    sorted.each |item|
    {
      end:=item.ts.toTimeZone(from.tz); start:=end-interval
      if (end <= from || start >= to) return
      at:=SeedMath.floorHour(start)
      v:=number(item.val)
      while (at < end)
      {
        finish:=at+1hr
        left:=start > at ? start : at; right:=end < finish ? end : finish
        if (right > left && at >= from && at < to)
        {
          if (!hours.containsKey(at.ticks)) hours[at.ticks]=SeedHourAccumulator()
          acc:=hours[at.ticks]; overlap:=(right-left).ticks
          acc.covered+=overlap
          if (v == null) acc.invalid=true
          else acc.value+=v*overlap.toFloat/interval.ticks.toFloat
          if (overlap != interval.ticks) estimated=true
        }
        at=finish
      }
    }
    cursor:=from
    while (cursor < to)
    {
      acc:=hours[cursor.ticks]
      valid:=acc != null && !acc.invalid && acc.covered == 1hr.ticks
      samples.add(["ts":cursor.toIso,"value":valid ? acc.value : null])
      cursor+=1hr
    }
    out["quality"]=estimated ? "estimated" : "ok"
    out["samples"]=samples
    return out
  }

  ** 'raw' also disables hisFunc in FIN. Preserve a computed function while
  ** explicitly disabling totalization/interpolation transforms instead.
  internal static Dict readOptions(Dict point)
  {
    if (!point.has("hisFunc")) return Etc.makeDict(["raw":Marker.val])
    return Etc.makeDict(["hisTotalized":Remove.val,"hisMode":Remove.val,"hisAppendNA":Remove.val])
  }

  private static Str:Obj? unavailable(Str id, Str quality)
  { ["pointId":id,"mode":"sampled","quality":quality,"samples":[Str:Obj?][,]] }

  private static Float? number(Obj? value)
  {
    if (value is Number) return SeedMath.num(((Number)value).toFloat)
    if (value is Bool) return value == true ? 1f : 0f
    return SeedMath.num(value)
  }

  private static Duration? cadence(Dict point, HisItem[] items)
  {
    for (i:=0;i<2;i++)
    {
      v:=point[["hisCollectInterval","hisInterval"][i]]
      if (v is Duration && ((Duration)v).ticks > 0) return v
      if (v is Number)
      {
        duration:=((Number)v).toDuration(false)
        if (duration != null && duration.ticks > 0) return duration
      }
    }
    deltas:=Int[,]
    for (i:=1;i<items.size;i++)
    {
      delta:=(items[i].ts-items[i-1].ts).ticks
      if (delta > 0) deltas.add(delta)
    }
    // A repeated shortest interval is evidence of cadence; a single gap is not.
    if (deltas.size < 2) return null
    smallest:=deltas.min
    if (deltas.findAll |d| { d == smallest }.size < 2) return null
    if (deltas.any |d| { d % smallest != 0 }) return null
    return Duration(smallest)
  }

  private static Str:Obj? dependencies(Str:Obj? request, [Str:Obj?][] records)
  {
    if (SeedDimension.active(request)) return SeedDimension.dependencies(request,records)
    ctx:=SeedContext(records,[Str:Obj?][,],TimeZone.utc)
    selected:=SeedMath.strings(request["nodeIds"])
    if (selected.isEmpty && request["kind"] == "dashboard")
    {
      selected=records.findAll |r| { r["kind"] == "group" && r["parentId"] == null }.map |r->Str| { r["id"].toStr }
      if (selected.isEmpty) selected=records.findAll |r| { ctx.included(r) && r["parentId"] == null }.map |r->Str| { r["id"].toStr }
    }
    selected=selected.dup.addAll(SeedMath.strings(request["referenceIds"]))
    ["xId","yId"].each |key| { if (request[key] != null) selected.add(request[key].toStr) }
    points:=Str[,]; nodes:=Str[,]
    selected.each |id| { collect(ctx,id,points,nodes,request["kind"] == "trend") }
    return ["points":points.unique,"nodes":nodes.unique]
  }

  private static Void collect(SeedContext ctx, Str id, Str[] points, Str[] nodes, Bool trend)
  {
    if (nodes.contains(id)) return
    nodes.add(id)
    r:=ctx.byId[id]
    if (r == null) { points.add(id); return }
    if (r["kind"] == "nativePoint") return
    if (r["pointId"] != null && !r["pointId"].toStr.isEmpty) points.add(r["pointId"].toStr)
    if (r["kind"] == "group")
    {
      (ctx.children[id] ?: [Str:Obj?][,]).each |child|
      {
        if (ctx.included(child) || (trend && child["kind"] == "sensor")) collect(ctx,child["id"].toStr,points,nodes,trend)
      }
    }
    if (r["kind"] == "cop") ["numeratorId","denominatorId"].each |key| { if (r[key] != null) collect(ctx,r[key].toStr,points,nodes,trend) }
    expression:=ctx.byId[r["expressionId"]?.toStr ?: ""]
    variables:=expression?.get("variables") as Map
    if (variables != null) variables.each |Obj? value| { if (value != null) collect(ctx,value.toStr,points,nodes,trend) }
  }
}

internal class SeedHourAccumulator
{
  Float value := 0f
  Int covered := 0
  Bool invalid := false
}


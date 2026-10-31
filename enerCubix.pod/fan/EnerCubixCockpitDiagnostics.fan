** Cockpit response-only diagnostic capture. Full arithmetic, series, coverage,
** configuration and graphs have already completed and are never recalculated.
internal class EnerCubixCockpitDiagnostics
{
  static Str:Obj? project(Str:Obj? snapshot)
  {
    if (snapshot["diagnostics"] is Map) return snapshot
    capture:=EnerCubixCockpitDiagnostics()
    out:=snapshot.dup;reports:=Str:Obj?[:]
    Map context:=snapshot["context"] as Map ?: Str:Obj?[:]
    Map time:=context["time"] as Map ?: Str:Obj?[:]
    scope:=EnerCubixMath.strings((context["reportScope"] as Map)?.get("nodeIds"))
    ((Map)snapshot["reports"]).each |raw,ref|
    {
      report:=((Map)raw).dup
      range:=Str:Obj?["from":report["from"] ?: time["from"],"to":report["to"] ?: time["to"],"asOf":context["asOf"]]
      ctx:=Str:Obj?["reportRef":ref.toStr,"range":range,"objects":scope]
      Map extra:=report["extra"] as Map ?: Str:Obj?[:];extra=extra.dup
      if (report["kind"] == "energyFlow")
      {
        report["rows"]=capture.periodRows(report["rows"],ctx)
        if (extra["energyFlowOverview"] is Map)
        {
          overview:=((Map)extra["energyFlowOverview"]).dup
          overview["rows"]=capture.periodRows(overview["rows"],ctx)
          if (overview["knownUsage"] is Map) overview["knownUsage"]=capture.known((Map)overview["knownUsage"],ctx)
          extra["energyFlowOverview"]=overview
        }
      }
      if (extra["knownUsage"] is Map) extra["knownUsage"]=capture.known((Map)extra["knownUsage"],ctx)
      if (extra["cleaning"] is List) extra["cleaning"]=EnerCubixMath.maps(extra["cleaning"]).map |row->[Str:Obj?]|
      {
        copy:=row.dup
        capture.register(copy,"details","cleaningEvents","cleaningEvent",ctx,Str[,],row["detailsTruncated"] == true ? null : EnerCubixMath.maps(row["details"]).size,row["detailsTruncated"] == true)
        return copy
      }
      report["extra"]=extra;reports[ref.toStr]=report
    }
    // Equal evidence copied into multiple reports shares one sample and ID.
    // First allocate across object/hour, source-read and cleaning lists fairly.
    capture.allocate(capture.groups.dup)
    intervals:=[Str:Obj?][,]
    capture.groups.dup.findAll |g| {g["kind"] == "sourceUsage"}.each |g|
    {
      kept:=(List)g["kept"]
      kept.each |raw|
      {
        row:=(Map)raw
        if (row["intervals"] isnot List) return
        ctx:=Str:Obj?["reportRef":((List)((Map)g["meta"])["reportRefs"]).first,"reportRefs":((Map)g["meta"])["reportRefs"],"range":["from":row["from"],"to":row["to"],"asOf":context["asOf"]],"objects":((Map)g["meta"])["objectIds"]]
        count:=EnerCubixMath.num(row["intervalCount"])
        registered:=capture.register(row,"intervals","sourceIntervals","sourceInterval",ctx,Str[,],count == null ? null : count.toInt,row["detailsTruncated"] == true)
        if (registered != null && !intervals.contains(registered)) intervals.add(registered)
      }
    }
    capture.allocate(intervals)
    out["reports"]=reports
    [Str:Obj?][] entries:=capture.groups.map |g->[Str:Obj?]| {(Str:Obj?)g["meta"]}
    byKind:=Str:Int[:];entries.each |m| {key:=m["kind"].toStr;byKind[key]=(byKind[key] ?: 0)+(Int)m["returnedCount"]}
    out["diagnostics"]=["schemaVersion":1,"rowBudget":1000,"returnedCount":1000-capture.remaining,"returnedByKind":byKind,"truncated":entries.any |m| {m["truncated"] == true},"entries":entries]
    return (Str:Obj?)out.toImmutable
  }
  private Int remaining := 1000
  private [Str:Obj?][] groups := [,]
  private Str:[Str:Obj?][] index := [:]

  private [Str:Obj?][] periodRows(Obj? value,Str:Obj? ctx)
  {
    return EnerCubixMath.maps(value).map |r->[Str:Obj?]|
    {
      if (r["periods"] isnot List) return r
      copy:=r.dup;id:=r["nodeId"] as Str ?: r["id"] as Str
      register(copy,"periods","coveragePeriods","hour",ctx,id == null ? Str[,] : [id],((List)r["periods"]).size,false)
      return copy
    }
  }
  private Map known(Map original,Str:Obj? ctx)
  {
    copy:=original.dup;rows:=copy["sourceUsage"] as List
    if (rows == null) return copy
    upstream:=copy["sourceUsageTruncated"] == true
    n:=EnerCubixMath.num(copy["sourceUsageRowCount"])
    register(copy,"sourceUsage","sourceUsage","sourceRead",ctx,Str[,],upstream ? (n == null ? null : n.toInt) : rows.size,upstream)
    return copy
  }
  private [Str:Obj?]? register(Map parent,Str field,Str kind,Str grain,Str:Obj? ctx,Str[] objects,Int? total,Bool upstream)
  {
    rows:=parent[field] as List;if (rows == null) return null
    if (total != null && total < rows.size) total=null
    ids:=objects.isEmpty ? EnerCubixMath.strings(ctx["objects"]) : objects
    reportRefs:=EnerCubixMath.strings(ctx["reportRefs"])
    if(reportRefs.isEmpty) reportRefs=[ctx["reportRef"].toStr]
    range:=(Map)ctx["range"]
    key:=kind+"|"+ids.join("|")+"|"+range["from"].toStr+"|"+range["to"].toStr+"|"+range["asOf"].toStr+"|"+rows.size+"|"+(rows.first?.hash ?: 0)+"|"+(rows.last?.hash ?: 0)+"|"+(total?.toStr ?: "unknown")+"|"+upstream
    bucket:=index[key] ?: [Str:Obj?][,]
    group:=bucket.find |g| {g["rows"] == rows}
    if (group == null)
    {
      sources:=Str:Bool[:]
      source:=parent["pointId"] as Str;if (source != null) sources[source]=true
      EnerCubixMath.strings(parent["sourceIds"]).each |id| {sources[id]=true}
      rows.each |v|
      {
        r:=v as Map;if(r == null) return
        p:=r["pointId"] as Str;if(p != null) sources[p]=true
        EnerCubixMath.strings(r["sourceIds"]).each |id| {sources[id]=true}
      }
      meta:=Str:Obj?["id":"diagnostic-"+groups.size,"kind":kind,"grain":grain,"totalCount":total,"returnedCount":0,"truncated":upstream,"reason":upstream ? "upstreamDiagnosticLimit" : "complete","objectIds":ids,"sourceIds":sources.keys.sort,"sourceIdsComplete":!upstream || source != null,"requestRange":range,"returnedRange":null,"reportRefs":reportRefs.dup]
      group=["kind":kind,"rows":rows,"meta":meta,"upstream":upstream,"targets":[["parent":parent,"field":field]]]
      groups.add(group);bucket.add(group);index[key]=bucket
    }
    else
    {
      ((List)group["targets"]).add(["parent":parent,"field":field])
      refs:=(List)((Map)group["meta"])["reportRefs"];reportRefs.each |ref| {if(!refs.contains(ref)) refs.add(ref)}
    }
    parent[field+"DiagnosticRef"]=((Map)group["meta"])["id"]
    return group
  }
  private Void allocate([Str:Obj?][] list)
  {
    active:=list.findAll |g| {!((List)g["rows"]).isEmpty}.size
    list.each |g|
    {
      rows:=(List)g["rows"];n:=rows.isEmpty ? 0 : rows.size.min(remaining/active)
      if(!rows.isEmpty) active--
      remaining-=n
      List kept:=n == 0 ? Obj?[,] : rows[0..<n]
      // Interval children receive the remaining packet budget in a second pass.
      if (g["kind"] == "sourceUsage") kept=kept.map |v->Obj?| {v is Map ? ((Map)v).dup : v}
      g["kept"]=kept
      meta:=(Str:Obj?)g["meta"];upstream:=g["upstream"] == true;limited:=n < rows.size
      meta["returnedCount"]=n;meta["truncated"]=upstream || limited
      meta["reason"]=limited ? (upstream ? "upstreamAndSnapshotLimit" : "snapshotDiagnosticBudget") : (upstream ? "upstreamDiagnosticLimit" : "complete")
      meta["returnedRange"]=returnedRange(kept)
      ((List)g["targets"]).each |target| {t:=(Map)target;((Map)t["parent"])[t["field"]]=kept}
    }
  }
  private static [Str:Obj?]? returnedRange(List rows)
  {
    starts:=DateTime[,];ends:=DateTime[,]
    rows.each |v|
    {
      r:=v as Map;if(r == null) return
      a:=r["from"] ?: (r["intervalStart"] ?: r["ts"]);b:=r["to"] ?: (r["intervalEnd"] ?: r["ts"])
      x:=DateTime.fromIso(a as Str ?: "",false);y:=DateTime.fromIso(b as Str ?: "",false)
      if(x != null) starts.add(x);if(y != null) ends.add(y)
    }
    return starts.isEmpty || ends.isEmpty ? null : Str:Obj?["from":((DateTime)starts.min).toIso,"to":((DateTime)ends.max).toIso]
  }
}

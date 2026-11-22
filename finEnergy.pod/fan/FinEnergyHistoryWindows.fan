using haystack

** Query-local sparse reader for cumulative comparisons only. Cleaning summaries
** expose gap evidence and inferred interval modes depend on the whole span;
** those readers deliberately retain their original contiguous observation.
internal class FinEnergyHistoryWindows
{
  static FinEnergyReadWindow[] plan(Str:Obj? request,[Str:Obj?][] records)
  {
    if(request["kind"]!="comparison" || request["otherFrom"]==null || request["otherTo"]==null ||
       request.keys.any |key| {key.startsWith("_cockpit")}) return FinEnergyReadWindow[,]
    current:=request.dup;current.remove("otherFrom");current.remove("otherTo")
    other:=current.dup.set("from",request["otherFrom"]).set("to",request["otherTo"])
    FinEnergyReadWindow[] windows:=[FinEnergyHistory.range(current,records),FinEnergyHistory.range(other,records)].map |row->FinEnergyReadWindow| {FinEnergyReadWindow((DateTime)row["from"],(DateTime)row["to"])}
    windows.sort |a,b| {a.from <=> b.from}
    // Include the same native one-day halo. Adjacent/overlapping halos gain
    // nothing from a second native observation, so keep the established path.
    if(windows[0].to+1day>=windows[1].from-1day) return FinEnergyReadWindow[,]
    return windows
  }

  static Bool eligible(Dict point,Str configured, Bool raw)
  {
    if(point["hisFunc"]=="finEnergyCleanHis" && !raw) return false
    if(configured!="auto") return configured=="cumulative"
    return point.has("hisTotalized") || point["hisMode"]=="cumulative"
  }

  ** Return null if either window lacks its own bracketing observations. The
  ** caller then rereads the original whole span; a gap never fabricates a bound.
  static HisItem[]? read(FinEnergyReadWindow[] windows,
    |DateTime,DateTime,|HisItem| | reader,[Str:Int]? timing:=null,Int limit:=1000000)
  {
    byTime:=Int:HisItem[:]; conflict:=false;count:=0
    for(w:=0;w<windows.size;w++)
    {
      window:=windows[w];DateTime? first:=null;DateTime? last:=null
      started:=Duration.nowTicks;observed:=0
      try
      {
        reader(window.from-1day,window.to+1day) |HisItem item|
        {
          if(count>=limit) throw ArgErr("History exceeds $limit raw samples")
          count++;observed++
          if(first==null || item.ts<first) first=item.ts
          if(last==null || item.ts>last) last=item.ts
          prior:=byTime[item.ts.ticks]
          if(prior!=null && prior.val!=item.val) conflict=true
          byTime[item.ts.ticks]=item
        }
      }
      finally
      {
        add(timing,"nativeReadNs",Duration.nowTicks-started)
        add(timing,"nativeReads",1);add(timing,"rawRows",observed)
      }
      if(conflict || first==null || last==null || first>window.from || last<window.to)
      {add(timing,"sparseFallbacks",1);return null}
    }
    add(timing,"sparsePoints",1)
    return byTime.vals.sort |a,b| {a.ts <=> b.ts}
  }
  private static Void add([Str:Int]? timing,Str key,Int n)
  {if(timing!=null) timing[key]=(timing[key] ?: 0)+n}
}

internal const class FinEnergyReadWindow
{
  new make(DateTime from,DateTime to) {this.from=from;this.to=to}
  const DateTime from
  const DateTime to
}

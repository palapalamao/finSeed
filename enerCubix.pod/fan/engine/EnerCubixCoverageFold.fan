** Detached request-local coverage scalars. Frame rows are borrowed, never kept;
** callers charge retained output independently. No source or alias deduplication.
internal class EnerCubixCoverageFold
{
  new make(Str[] points,DateTime from,DateTime to,EnerCubixPreparedOwner owner)
  {
    this.from=from;this.to=to;budget=owner.budget
    owner.watch |->Void| {close};owner.hold(6+6*points.unique.size)
    points.unique.each |point| {totals[point]=0f}
  }
  private const EnerCubixPreparedBudget budget
  private const DateTime from
  private const DateTime to
  private Str:Float totals := [:]
  private Str:[Str:Obj?] last := [:]
  private DateTime? firstAt
  private DateTime? lastAt
  private Bool closed := false

  Void addFrame([Str:Obj?][] reads,EnerCubixPreparedOwner frame)
  {
    check
    if(frame.budget !== budget) throw ArgErr("coverageFrameOwner")
    // Filtering and sorting vectors expire here, before another hourly fold.
    charge:=5+2*reads.size;frame.hold(charge)
    [Str:Obj?][]? filtered;[Str:Obj?][]? ordered
    try
    {
      filtered=reads.findAll |r|
      {totals.containsKey(r["pointId"] as Str ?: "") && DateTime.fromIso(r["from"].toStr)>=from && DateTime.fromIso(r["to"].toStr)<=to}
      ordered=EnerCubixKnownUsage.coverageOrder(filtered)
      // Validate the whole frame before changing any earlier contribution.
      ordered.each |r|
      {
        previous:=last[r["pointId"].toStr]
        if(previous != null && EnerCubixKnownUsage.coverageCompare(previous,r)>0) throw ArgErr("coverageFrameOrder")
      }
      ordered.each |r|
      {
        point:=r["pointId"].toStr
        totals[point]=totals[point]+(EnerCubixMath.num(r["coveredSeconds"]) ?: 0f)
        last[point]=["from":r["from"],"to":r["to"],"nodeId":r["nodeId"],"pointId":point]
        start:=r["intervalStart"] == null ? null : DateTime.fromIso(r["intervalStart"].toStr)
        end:=r["intervalEnd"] == null ? null : DateTime.fromIso(r["intervalEnd"].toStr)
        if(start != null && (firstAt == null || start<firstAt)) firstAt=start
        if(end != null && (lastAt == null || end>lastAt)) lastAt=end
      }
    }
    finally {filtered?.clear;ordered?.clear;frame.release(charge)}
  }
  Str:Obj? finish()
  {
    check
    seconds:=(to-from).ticks.toFloat/1sec.ticks.toFloat
    amount:=totals.isEmpty ? 0f : (Float)totals.vals.min
    return ["coveredSeconds":amount,"expectedSeconds":seconds,"coverage":seconds>0f ? (amount/seconds).min(1f) : 0f,"coverageStart":firstAt?.toIso,"coverageEnd":lastAt?.toIso]
  }
  private Void check() {if(closed) throw ArgErr("coverageFoldClosed")}
  private Void close() {totals.clear;last.clear;firstAt=null;lastAt=null;closed=true}
}

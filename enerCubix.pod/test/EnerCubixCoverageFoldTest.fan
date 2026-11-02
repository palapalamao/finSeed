** Coverage uses the same rows, per-source time order and original scalar adds.
class EnerCubixCoverageFoldTest : Test
{
  Void testSubsecondRowsAreBitwiseEqualAcrossFrameSizesAndInputOrders()
  {
    rows:=[Str:Obj?][,];seconds:=0f
    for(i:=0;i<744;i++)
    {
      hour:=at+Duration(i*1hr.ticks);ticks:=(i*123456789123)%3600000000000+1
      value:=ticks.toFloat/1sec.ticks.toFloat;seconds+=value
      rows.add(row("m","p",hour,hour+1hr,value,hour,hour+Duration(ticks)))
    }
    [1,7,50,744].each |width|
    {
      budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
      fold:=EnerCubixCoverageFold(["p"],at,at+744hr,owner);retained:=owner.entries
      cursor:=0
      while(cursor<rows.size)
      {
        end:=(cursor+width).min(rows.size);frame:=EnerCubixPreparedOwner(budget)
        fold.addFrame(rows[cursor..<end].reverse,frame);frame.close
        verifyEq(owner.entries,retained);verifyEq(budget.temporary.val,retained)
        cursor=end
      }
      result:=fold.finish
      verifyEq(result["coveredSeconds"],seconds);verifyEq(result["coverage"],seconds/(744f*3600f))
      verifyEq(result["coverageStart"],rows.first["intervalStart"]);verifyEq(result["coverageEnd"],rows.last["intervalEnd"])
      owner.close;verifyEq(budget.temporary.val,0)
      verifyEq(result["coveredSeconds"],seconds);verifyErr(ArgErr#) {fold.finish}
    }
  }

  Void testPerSourceMinimumLongIntervalsAliasRowsAndMissingSourceStayUnchanged()
  {
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
    fold:=EnerCubixCoverageFold(["p","q"],at,at+4hr,owner)
    frame:=EnerCubixPreparedOwner(budget)
    fold.addFrame([row("a","p",at,at+1hr,7200f,at,at+2hr),row("b","q",at+1hr,at+2hr,3600f,at+1hr,at+2hr)],frame)
    frame.close
    result:=fold.finish;verifyEq(result["coveredSeconds"],3600f);verifyEq(result["coverage"],0.25f)
    verifyEq(result["coverageStart"],at.toIso);verifyEq(result["coverageEnd"],(at+2hr).toIso)
    alias:=EnerCubixCoverageFold(["p"],at,at+4hr,owner)
    missing:=EnerCubixCoverageFold(["p","missing"],at,at+4hr,owner)
    frame=EnerCubixPreparedOwner(budget)
    rows:=[row("a","p",at,at+1hr,1f),row("b","p",at,at+1hr,2f)]
    alias.addFrame(rows,frame);missing.addFrame(rows,frame);frame.close
    verifyEq(alias.finish["coveredSeconds"],3f);verifyEq(missing.finish["coveredSeconds"],0f)
    owner.close;verifyEq(budget.temporary.val,0)
  }

  Void testQueryFilterDstAndFailedFrameDoNotChangePriorContributions()
  {
    zone:=TimeZone("New_York")
    start:=Date(2026,Month.nov,1).toDateTime(Time.defVal,zone);end:=Date(2026,Month.nov,2).toDateTime(Time.defVal,zone)
    budget:=EnerCubixPreparedBudget(EnerCubixCockpitDeadline());owner:=EnerCubixPreparedOwner(budget)
    fold:=EnerCubixCoverageFold(["p"],start,end,owner)
    for(i:=0;i<25;i++)
    {
      a:=start+Duration(i*1hr.ticks);frame:=EnerCubixPreparedOwner(budget)
      fold.addFrame([row("m","p",a,a+1hr,3600f)],frame);frame.close
    }
    verifyEq(fold.finish["expectedSeconds"],90000f);verifyEq(fold.finish["coverage"],1f)
    frame:=EnerCubixPreparedOwner(budget)
    verifyErr(ArgErr#) {fold.addFrame([row("m","p",start,start+1hr,3600f)],frame)}
    verifyEq(fold.finish["coveredSeconds"],90000f)
    fold.addFrame([row("m","p",start-1hr,start,3600f),row("m","p",end,end+1hr,3600f),row("other","x",start,end,90000f)],frame)
    frame.close;verifyEq(fold.finish["coveredSeconds"],90000f)
    foreign:=EnerCubixPreparedOwner(EnerCubixPreparedBudget(EnerCubixCockpitDeadline()))
    verifyErr(ArgErr#) {fold.addFrame([Str:Obj?][,],foreign)}
    foreign.close;owner.close;verifyEq(budget.temporary.val,0)
  }

  private Str:Obj? row(Str node,Str point,DateTime a,DateTime b,Float seconds,DateTime? first := null,DateTime? last := null)
  {["nodeId":node,"pointId":point,"from":a.toIso,"to":b.toIso,"coveredSeconds":seconds,"intervalStart":(first ?: a).toIso,"intervalEnd":(last ?: b).toIso]}
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

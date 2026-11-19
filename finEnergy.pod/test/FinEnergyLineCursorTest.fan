class FinEnergyLineCursorTest : Test
{
  Void testPartialHourCursorUsesExistingLeafCalculationWithoutRetainingTicks()
  {
    start:=at+13min;end:=at+1hr+17min
    q:=query.dup.setAll(["from":start.toIso,"to":end.toIso])
    ctx:=FinEnergyContext(records,[history("pa",[60f,120f]),history("pb",[0f,0f])],TimeZone.utc)
    report:=FinEnergyReport(ctx,q,start,end,"profile","day","energy")
    cursor:=report.openLine("a","c")
    verifyEq(cursor.watermark,start);verifyEq(cursor.line.ticks.size,0)
    verifyErr(ArgErr#) {cursor.finish}
    first:=cursor.next
    verifyEq(first.ts,start);verifyEq(first.end,at+1hr)
    verify(first.value.value.approx(47f));verifyEq(first.value.sources,["pa"])
    second:=cursor.next
    verifyEq(second.ts,at+1hr);verifyEq(second.end,end)
    verify(second.value.value.approx(34f));verifyEq(cursor.more,false)
    verifyEq(cursor.finish.ticks.size,0)
    verifyErr(ArgErr#) {cursor.next}
    verifySame(cursor.finish,cursor.line)
  }

  Void testCopOperandsRemainAvailableWhenFirstHourlyRatioIsNull()
  {
    rs:=records;rs.add(["id":"cop","kind":"cop","numeratorId":"a","denominatorId":"b"])
    ctx:=FinEnergyContext(rs,[history("pa",[10f,10f]),history("pb",[0f,10f])],TimeZone.utc)
    report:=FinEnergyReport(ctx,query,at,at+2hr,"cop","day","energy")
    cursor:=report.openLine("cop","c")
    first:=cursor.next;verifyNull(first.value.value);verifyEq(first.value.quality,"divisionByZero")
    verifyEq(first.numerator.value,10f);verifyEq(first.denominator.value,0f)
    second:=cursor.next;verifyEq(second.value.value,1f)
    verifyEq(second.numerator.value,10f);verifyEq(second.denominator.value,10f)
    verifyEq(cursor.finish.ratio,true)
    period:=FinEnergyValue.divide(FinEnergyValue.sum([first.numerator,second.numerator]),FinEnergyValue.sum([first.denominator,second.denominator]))
    verifyEq(period.value,2f)
  }

  Void testDurationAlignmentAndFailureDoNotRepeatLeafCalls()
  {
    line:=FinEnergyLine("m|c","m","Meter","c","kWh");calls:=0;finished:=0
    start:=at+13min;end:=at+2hr+17min
    cursor:=FinEnergyLineCursor(line,start,end,true,|a,b->FinEnergyTick| {calls++;return FinEnergyTick(a,b,FinEnergyValue(1f,"ok"))},|->Void| {finished++})
    first:=cursor.next;verifyEq(first.end,at+1hr+13min)
    second:=cursor.next;verifyEq(second.end,at+2hr+13min)
    third:=cursor.next;verifyEq(third.end,end)
    cursor.finish;cursor.finish;verifyEq(calls,3);verifyEq(finished,1)
    cursor=FinEnergyLineCursor(line,at,at+1hr,false,|a,b->FinEnergyTick| {calls++;throw IOErr("controlled leaf failure")},|->Void| {finished++})
    verifyErr(IOErr#) {cursor.next};verifyErr(IOErr#) {cursor.next};verifyErr(IOErr#) {cursor.finish}
    verifyEq(calls,4);verifyEq(finished,1);verifyEq(cursor.watermark,at)
  }

  private Str:Obj? query() {["from":at.toIso,"to":(at+2hr).toIso,"asOf":(at+2hr).toIso,"tz":"UTC"]}
  private [Str:Obj?][] records() {[ ["id":"c","kind":"category","unit":"kWh"],["id":"a","kind":"meter","pointId":"pa","categoryId":"c"],["id":"b","kind":"meter","pointId":"pb","categoryId":"c"] ]}
  private Str:Obj? history(Str id,Float[] values) {["pointId":id,"unit":"kWh","mode":"interval","samples":values.map |v,i->[Str:Obj?]| {["ts":(at+Duration(i*1hr.ticks)).toIso,"value":v]}]}
  private DateTime at() {DateTime.fromIso("2026-01-01T00:00:00Z")}
}

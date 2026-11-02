** Natural-month allocation. FIN histories and prices are supplied by the caller;
** this class allocates configuration only and never imputes actual consumption.
internal class EnerCubixBudgetMath
{
  static Date monthStart(Str text)
  {
    if(!Regex<|\d{4}-\d{2}|>.matches(text)) throw ArgErr("cockpitBudgetMonth")
    date:=Date.fromStr(text+"-01",false) ?: throw ArgErr("cockpitBudgetMonth")
    return date
  }
  static Date nextMonth(Date d) {d.month == Month.dec ? Date(d.year+1,Month.jan,1) : Date(d.year,Month.vals[d.month.ordinal+1],1)}
  static Float number(Obj? v,Bool positive := false)
  {
    n:=EnerCubixMath.num(v)
    if(n == null || (positive ? n <= 0f : n < 0f)) throw ArgErr("cockpitConfigNumber")
    return n
  }
  static Void validate(Str:Obj? b)
  {
    date:=monthStart(b["month"] as Str ?: "")
    amount:=number(b["amount"],true)
    distribution:=b["distribution"]
    if(distribution != "uniform" && distribution != "daily") throw ArgErr("cockpitBudgetDistribution")
    if(distribution == "daily")
    {
      rows:=b["dailyAmounts"] as List ?: throw ArgErr("cockpitBudgetDailyAmounts")
      if(rows.size != (nextMonth(date)-date).toDay) throw ArgErr("cockpitBudgetDailyAmounts")
      total:=0f;rows.each |v| {total+=number(v)}
      if((total-amount).abs > amount.max(1f)*0.000000001f) throw ArgErr("cockpitBudgetDailyTotal")
    }
    else if(b["dailyAmounts"] != null && (b["dailyAmounts"] isnot List || !((List)b["dailyAmounts"]).isEmpty)) throw ArgErr("cockpitBudgetDailyAmounts")
  }

  static Str:Obj? period([Str:Obj?][] budgets,DateTime from,DateTime to,DateTime asOf,Float? actualCost,TimeZone tz)
  {
    from=from.toTimeZone(tz);to=to.toTimeZone(tz);asOf=asOf.toTimeZone(tz)
    end:=to < asOf ? to : asOf
    if(end <= from) return unavailable("BUDGET_EMPTY_PERIOD")
    months:=[Str:Obj?][,];curve:=[Str:Obj?][["ts":from.toIso,"cumulativeBudget":0f,"periodBudget":0f]]
    cursor:=from;periodBudget:=0f;monthBudget:=0f;selectedDays:=0f;monthDays:=0
    reasons:=Str[,]
    while(cursor < end)
    {
      first:=Date(cursor.year,cursor.month,1);next:=nextMonth(first)
      key:=first.toStr[0..<7];days:=(next-first).toDay;monthDays+=days
      finish:=next.toDateTime(Time.defVal,tz);if(finish > end) finish=end
      found:=budgets.findAll |b| {b["month"] == key}
      if(found.size != 1)
      {
        reasons.add(found.isEmpty ? "BUDGET_MONTH_MISSING" : "BUDGET_CONFLICT")
        months.add(["month":key,"status":"unavailable","amount":null,"periodAmount":null]);cursor=finish;continue
      }
      b:=found.first
      try {validate(b)}
      catch(ArgErr e) {reasons.add("BUDGET_CONFIG_INVALID");months.add(["month":key,"status":"unavailable","amount":null,"periodAmount":null]);cursor=finish;continue}
      amount:=number(b["amount"],true);monthBudget+=amount;subtotal:=0f
      while(cursor < finish)
      {
        day:=cursor.date;nextDay:=(day+1day).toDateTime(Time.defVal,tz)
        dayStart:=day.toDateTime(Time.defVal,tz);partEnd:=nextDay < finish ? nextDay : finish
        fraction:=(partEnd-cursor).ticks.toFloat/(nextDay-dayStart).ticks.toFloat
        daily:=b["distribution"] == "daily" ? number(((List)b["dailyAmounts"])[day.day-1]) : amount/days.toFloat
        value:=daily*fraction;subtotal+=value;periodBudget+=value;selectedDays+=fraction
        curve.add(["ts":partEnd.toIso,"month":key,"periodBudget":value,"cumulativeBudget":periodBudget,"dayBudget":daily,"actualDaySeconds":(nextDay-dayStart).toSec,"from":cursor.toIso,"to":partEnd.toIso])
        cursor=partEnd
      }
      months.add(["month":key,"status":"ok","configRef":b["id"],"version":b["version"],"mod":b["mod"],"amount":amount,"periodAmount":subtotal,"distribution":b["distribution"]])
    }
    if(actualCost == null) reasons.add("BUDGET_COST_INCOMPLETE")
    if(periodBudget <= 0f) reasons.add("BUDGET_ZERO_PERIOD")
    valid:=reasons.isEmpty
    return ["status":valid ? "ok" : "unavailable","reasonCodes":reasons.unique,"monthBudget":reasons.any |r| {r == "BUDGET_MONTH_MISSING" || r == "BUDGET_CONFLICT" || r == "BUDGET_CONFIG_INVALID"} ? null : monthBudget,"periodBudget":valid ? periodBudget : null,"periodActualCost":actualCost,"deviationAmount":valid ? actualCost-periodBudget : null,"variancePct":valid ? (actualCost-periodBudget)/periodBudget*100f : null,"monthUsagePct":valid && monthBudget > 0f ? actualCost/monthBudget*100f : null,"calendarProgressPct":monthDays > 0 ? selectedDays/monthDays.toFloat*100f : null,"calendarProgressBasis":"selectedLocalDayFractionsOverInvolvedNaturalMonthDays","months":months,"curve":valid ? curve : [Str:Obj?][,],"from":from.toIso,"to":to.toIso,"effectiveTo":end.toIso,"asOf":asOf.toIso,"timeZone":tz.name,"formulas":["periodBudget":"sum(dailyBudget * overlapSeconds / actualLocalDaySeconds)","variancePct":"(periodActualCost - periodBudget) / periodBudget * 100","monthUsagePct":"periodActualCost / sum(involvedFullMonthAmounts) * 100","calendarProgressPct":"sum(selectedLocalDayFractions) / sum(involvedMonthDays) * 100"]]
  }
  static Str:Obj? unavailable(Str reason)
  {["status":"unavailable","reasonCodes":[reason],"monthBudget":null,"periodBudget":null,"periodActualCost":null,"variancePct":null,"deviationAmount":null,"monthUsagePct":null,"calendarProgressPct":null,"months":[Str:Obj?][,],"curve":[Str:Obj?][,],"fallback":"comparison"]}
}

** Snapshot-only budget reference. It reuses the canonical cost value and frozen
** native configuration; matching never reads histories or reallocates a parent.
internal class FinEnergyCockpitBudget
{
  static Bool localError(Err e) {[Err#,NullErr#,CastErr#,IndexErr#].contains(e.typeof) && (e.cause == null || localError(e.cause))}
  ** Exclude only provably unrelated configurations. Invalid public DTOs remain
  ** sanitized; private attribution is read solely from the server capture.
  static [Str:Obj?][] related(Str type,Str:Obj? q,[Str:Obj?][] records,Str:Obj? owned,Str:Obj? boundary)
  {
    category:=FinEnergyMath.strings(q["categoryIds"]).first
    rows:=FinEnergyMath.maps(owned[type == "budget" ? "budgets" : "rules"])
    Map attribution:=(owned[type == "budget" ? "budgetAttribution" : "ruleAttribution"] as Map) ?: Str:Obj?[:]
    model:=FinEnergyMath.maps(owned["modelRecords"]);if(model.isEmpty) model=records
    months:=Str[,]
    if(type == "budget")
    {
      tz:=TimeZone(q["tz"].toStr)
      cursor:=FinEnergyMath.bucket(DateTime.fromIso(q["from"].toStr).toTimeZone(tz),"month")
      to:=DateTime.fromIso(q["to"].toStr).toTimeZone(tz);asOf:=DateTime.fromIso(q["asOf"].toStr).toTimeZone(tz);end:=to < asOf ? to : asOf
      while(cursor < end) {months.add(cursor.date.toStr[0..<7]);cursor=FinEnergyMath.nextBucket(cursor,"month")}
    }
    return rows.findAll |r|
    {
      invalid:=r["validation"] == "invalid"
      Map? basis:=invalid ? (attribution[r["id"]] as Map) : r
      if(basis == null) return true
      if(basis["categoryRef"] is Str && basis["categoryRef"] != category) return false
      month:=basis["month"] as Str
      if(type == "budget" && month != null && !months.isEmpty)
      {
        try {FinEnergyBudgetMath.monthStart(month);if(!months.contains(month)) return false}
        catch(ArgErr e) {} // Malformed attribution cannot establish irrelevance.
      }
      if(owned["modelComplete"] != true || (invalid && basis["scopeReadable"] != true) || basis["categoryRef"] != category || basis["scopeKind"] isnot Str || basis["scopeRef"] isnot Str) return true
      try
      {
        match:=FinEnergyBudgetScope.match(basis["scopeKind"].toStr,basis["scopeRef"].toStr,category,q,boundary,model,owned["projectRef"] as Str)
        return !FinEnergyMath.strings(match["reasonCodes"]).contains("BUDGET_SCOPE_MISMATCH")
      }
      catch(ArgErr e) {return true}
    }
  }
  ** A view's ownership warning is not a different physical expense boundary.
  ** Explicit overlap and all physical/source errors remain disqualifying.
  static Str:Obj? canonical(Str:Obj? q,[Str:Obj?][] records,[Str:Obj?][] histories,Str:Obj? boundary,Str:Obj? reports,|Str,Str:Obj?->Str:Obj?|? preparedReport := null)
  {
    own:=physicalBoundary(boundary)
    request:=FinEnergyCockpitReports.budgetQuery(q,boundary)
    report:=FinEnergyCockpitReports.read("budget-canonical-cost",request,records,FinEnergyCockpitMetrics.histories(request,histories),preparedReport)
    category:=FinEnergyMath.strings(q["categoryIds"]).first
    cost:=FinEnergyCockpitMetrics.metric(report,"cost",category,own)
    tariffs:=FinEnergyMath.maps(((Map)report["extra"])["tariffSnapshot"])
    currencies:=tariffs.map |t->Str| {t["currency"] as Str ?: "CNY"}.unique
    cost["unit"]=currencies.size == 1 ? currencies.first : ""
    cost["details"]=["estimate":true,"tariffs":tariffs]
    currency:=FinEnergyCockpitCurrency.observe(report)
    cost=FinEnergyCockpitCurrency.metric(cost,currency)
    report=FinEnergyCockpitCurrency.report(report,currency)
    reports["budget-canonical-cost"]=report
    return ["boundary":own,"cost":cost,"request":request.findAll |v,k| {!k.startsWith("_")}]
  }
  static Str:Obj? physicalBoundary(Str:Obj? boundary)
  {
    out:=boundary.dup
    if(boundary["reasonCode"] == "accountingIncomplete" && FinEnergyMath.maps(boundary["overlaps"]).isEmpty)
    {out["aggregateAllowed"]=true;out.remove("reasonCode")}
    return out
  }
  static Str:Obj? project(Str:Obj? q,[Str:Obj?][] records,Str:Obj? owned,Str:Obj? boundary,Str:Obj? cost)
  {
    category:=FinEnergyMath.strings(q["categoryIds"]).first
    configs:=related("budget",q,records,owned,boundary)
    configRefs:=configs.map |b->[Str:Obj?]| {["id":b["id"],"mod":b["mod"],"version":b["version"]]}
    result:=FinEnergyBudgetMath.unavailable("BUDGET_NOT_CONFIGURED")
    result.setAll(["boundaryId":boundary["id"],"periodActualCost":cost["value"],"costValueBasis":cost["valueBasis"],"costQuality":cost["quality"],"currency":cost["unit"],"comparisonFallback":cost["comparison"],"costReportRef":"profile-cost","configRefs":configRefs,"configuration":configs])
    if(owned["budgetsComplete"] == false) return fail(result,"BUDGET_CONFIG_UNREADABLE")
    if(configs.isEmpty) return result
    if(configs.any |b| {b["validation"] == "invalid"}) return fail(result,"BUDGET_CONFIG_INVALID")
    if(boundary["aggregateAllowed"] != true) return fail(result,FinEnergyMath.maps(boundary["overlaps"]).isEmpty ? "BUDGET_PHYSICAL_BOUNDARY_UNAVAILABLE" : "BUDGET_OVERLAP")
    currency:=currency(cost)
    if(currency["status"] != "ok") return fail(result,currency["reason"].toStr)
    result["currencyBasis"]=currency["basis"];result["currencySources"]=currency["sources"]
    result["tariffSnapshot"]=((Map)cost["details"])["tariffs"]
    tz:=TimeZone(q["tz"].toStr)
    from:=DateTime.fromIso(q["from"].toStr).toTimeZone(tz);to:=DateTime.fromIso(q["to"].toStr).toTimeZone(tz);asOf:=DateTime.fromIso(q["asOf"].toStr).toTimeZone(tz)
    end:=to < asOf ? to : asOf
    months:=Str[,];cursor:=FinEnergyMath.bucket(from,"month")
    while(cursor < end) {months.add(cursor.date.toStr[0..<7]);cursor=FinEnergyMath.nextBucket(cursor,"month")}
    model:=FinEnergyMath.maps(owned["modelRecords"]);if(model.isEmpty) model=records
    matching:=configs.findAll |b|
    {
      if(b["categoryRef"] != category || b["month"] isnot Str || !months.contains(b["month"]) || owned["modelComplete"] != true) return false
      try {return FinEnergyBudgetScope.match(b["scopeKind"].toStr,b["scopeRef"].toStr,category,q,boundary,model,owned["projectRef"] as Str)["eligible"] == true}
      catch(ArgErr e) {return false}
    }
    if(matching.isEmpty) return fail(result,"BUDGET_SCOPE_MISMATCH")
    sameCurrency:=matching.findAll |b| {b["currency"] == cost["unit"]}
    if(sameCurrency.isEmpty) return fail(result,"BUDGET_CURRENCY_MISMATCH")
    identities:=sameCurrency.map |b->Str| {b["scopeKind"].toStr+"|"+b["scopeRef"].toStr}.unique
    if(identities.size != 1) return fail(result,"BUDGET_SCOPE_CONFLICT")
    if(sameCurrency.any |b| {b["enabled"] != true}) return fail(result,"BUDGET_DISABLED")
    validCost:=cost["valueBasis"] == "complete" && FinEnergyMath.num(cost["completeValue"]) != null && FinEnergyMath.maps(cost["coverage"]).all |c| {c["complete"] == true}
    actual:=validCost ? FinEnergyMath.num(cost["value"]) : null
    amounts:=FinEnergyBudgetMath.period(sameCurrency,from,to,asOf,actual,TimeZone(q["tz"].toStr))
    result.setAll(amounts)
    result["scopeKind"]=sameCurrency.first["scopeKind"];result["scopeRef"]=sameCurrency.first["scopeRef"]
    result["categoryRef"]=category;result["currency"]=cost["unit"]
    result["configRefs"]=sameCurrency.map |b->[Str:Obj?]| {["id":b["id"],"mod":b["mod"],"version":b["version"]]}
    result["configuration"]=sameCurrency
    if(!validCost) {result["periodActualCost"]=cost["value"];result["costValueBasis"]=cost["valueBasis"]}
    // References reuse the already observed expense, never coverage-scaled or
    // substituted history. Strict eligibility above remains the rule input.
    known:=cost["valueType"] == "na" ? null : FinEnergyMath.num(cost["value"])
    if(result["budgetStatus"] == "ok" && known != null && ["complete","knownSubtotal"].contains(cost["valueBasis"]))
    {
      period:=FinEnergyMath.num(result["periodBudget"]);month:=FinEnergyMath.num(result["monthBudget"])
      result["referenceVariancePct"]=period != null && period > 0f ? (known-period)/period*100f : null
      result["referenceMonthUsagePct"]=month != null && month > 0f ? known/month*100f : null
      result["referenceBasis"]=["actualCost":known,"valueBasis":cost["valueBasis"],"quality":cost["quality"],"reasonCodes":FinEnergyMath.strings(cost["reasonCodes"]),"from":result["from"],"effectiveTo":result["effectiveTo"],"asOf":result["asOf"],"currency":cost["unit"],"method":"observedCostWithoutExtrapolation"]
    }
    return result
  }
  internal static Str:Obj? currency(Str:Obj? cost)
  {
    details:=cost["details"] as Map;tariffs:=FinEnergyMath.maps(details?.get("tariffs"))
    if(tariffs.isEmpty) return ["status":"unavailable","reason":"BUDGET_TARIFF_MISSING"]
    sources:=[Str:Obj?][,];invalid:=false
    tariffs.each |t|
    {
      raw:=t["currency"];legacy:=raw == null
      if(!legacy && (raw isnot Str || !Regex<|[A-Z]{3}|>.matches(raw.toStr))) {invalid=true;return}
      sources.add(["tariffId":t["id"],"mod":t["mod"],"nodeId":t["nodeId"],"currency":legacy ? "CNY" : raw,"basis":legacy ? "legacyCnyConvention" : "explicit"])
    }
    currencies:=sources.map |s->Str| {s["currency"].toStr}.unique
    if(invalid || currencies.size != 1 || cost["unit"] != currencies.first) return ["status":"unavailable","reason":invalid ? "BUDGET_CURRENCY_INVALID" : "BUDGET_CURRENCY_MISMATCH"]
    legacy:=sources.any |s| {s["basis"] == "legacyCnyConvention"};explicit:=sources.any |s| {s["basis"] == "explicit"}
    return ["status":"ok","currency":currencies.first,"sources":sources,"basis":legacy ? (explicit ? "mixedExplicitAndLegacyCny" : "legacyCnyConvention") : "explicit"]
  }
  private static Str:Obj? fail(Str:Obj? out,Str reason) {out["reasonCodes"]=[reason];return out}
}

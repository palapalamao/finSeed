** Cost response qualification only. The report engine, prices, native source
** units and arithmetic remain unchanged; no currency conversion is performed.
internal class EnerCubixCockpitCurrency
{
  static Str:Obj? observe(Str:Obj? report)
  {
    tariffs:=EnerCubixMath.maps(((Map)report["extra"])["tariffSnapshot"])
    candidates:=tariffs.map |t->Str| {t["currency"] == null ? "CNY" : (t["currency"] as Str ?: "")}.unique
    result:=EnerCubixCockpitBudget.currency(["unit":candidates.size == 1 ? candidates.first : "","details":["tariffs":tariffs]])
    if(result["status"] != "ok")
    {
      reason:=result["reason"]
      result["reason"]=reason == "BUDGET_TARIFF_MISSING" ? "COST_TARIFF_MISSING" : (reason == "BUDGET_CURRENCY_INVALID" ? "COST_CURRENCY_INVALID" : "COST_CURRENCY_MIXED")
    }
    return result
  }
  static Str:Obj? report(Str:Obj? source,Str:Obj? observed)
  {
    out:=source.dup;unit:=observed["currency"] as Str ?: "";qualified:=observed["status"] == "ok"
    ["series","rows"].each |key| {if(source.containsKey(key)) out[key]=rows(source[key],unit,qualified,key == "series")}
    summary:=((Map)source["summary"]).dup
    ["totals","knownTotals","selectionTotals"].each |key| {if(summary.containsKey(key)) summary[key]=rows(summary[key],unit,qualified)}
    out["summary"]=summary
    extra:=((Map)source["extra"]).dup
    ["selectionTotals","usageCoverage","details"].each |key| {if(extra.containsKey(key)) extra[key]=rows(extra[key],unit,qualified)}
    extra.setAll(["currencyStatus":qualified ? "ok" : "unavailable","currency":qualified ? unit : null,"currencyBasis":observed["basis"],"currencySources":observed["sources"] ?: [Str:Obj?][,],"currencyReasonCodes":qualified ? Str[,] : [observed["reason"].toStr]])
    out["extra"]=extra
    return out
  }
  static Str:Obj? metric(Str:Obj? source,Str:Obj? observed)
  {
    qualified:=observed["status"] == "ok";unit:=observed["currency"] as Str ?: ""
    out:=cell(source,unit,qualified)
    out.setAll(["unit":unit,"currencyStatus":qualified ? "ok" : "unavailable","currencyBasis":observed["basis"],"currencyReasonCodes":qualified ? Str[,] : [observed["reason"].toStr]])
    out["coverage"]=rows(source["coverage"],unit,qualified)
    if(!qualified)
    {
      out.setAll(["status":"unavailable","valueBasis":"unavailable","quality":"currencyUnconfirmed"])
      out["reasonCodes"]=EnerCubixMath.strings(source["reasonCodes"]).dup.add(observed["reason"].toStr).unique
    }
    return out
  }
  private static [Str:Obj?][] rows(Obj? value,Str unit,Bool qualified,Bool series := false)
  {
    EnerCubixMath.maps(value).map |row->[Str:Obj?]|
    {
      out:=cell(row,unit,qualified)
      if(series && row.containsKey("points")) out["points"]=rows(row["points"],unit,qualified)
      return out
    }
  }
  private static Str:Obj? cell(Str:Obj? source,Str unit,Bool qualified)
  {
    out:=source.dup
    if(out.containsKey("unit")) out["unit"]=unit
    if(!qualified)
    {
      ["value","knownValue","completeValue"].each |key| {if(out.containsKey(key)) out[key]=null}
      ["valueType","knownValueType"].each |key| {if(out.containsKey(key)) out[key]="null"}
      ["quality","knownQuality"].each |key| {if(out.containsKey(key)) out[key]="currencyUnconfirmed"}
    }
    return out
  }
}

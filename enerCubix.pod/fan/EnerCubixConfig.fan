** Pure configuration invariants; persistence and identity live in EnerCubixRepo.
const class EnerCubixConfig
{
  static const Str[] kinds := ["group", "space", "organization", "meter", "totalMeter", "sensor", "category", "subcategory", "utility", "tariff", "calendar", "expression", "cop", "template", "settings", "binding", "job", "alarm", "cleaningProfile"]
  static const Str[] nodeKinds := ["group", "space", "organization", "meter", "totalMeter", "sensor"]

  ** Existing legacy duplicates remain editable; new bindings always reuse a master.
  static Void validateNewBinding([Str:Obj?] rec, [Str:Obj?]? previous, [Str:Obj?][] all)
  {
    point:=rec["pointId"] as Str
    if (point == null || point.isEmpty || !EnerCubixRelations.meterKinds.contains(rec["kind"])) return
    if (previous != null && previous["pointId"] == point) return
    if (all.any |r| { r["id"] != rec["id"] && EnerCubixRelations.meterKinds.contains(r["kind"]) && r["pointId"] == point }) throw ArgErr("该 FIN 点已有计量档案，请定位并复用已有表计")
  }

  static Void validate([Str:Obj?] rec, [Str:Obj?][] all)
  {
    kind := rec["kind"] as Str ?: ""
    templateRequest:=kind == "template" ? (rec["request"] as Map) : null
    if (templateRequest?.get("flowMode") != null && !["relations","endUse"].contains(templateRequest["flowMode"])) throw ArgErr("endUseInvalidMode")
    if (rec["autoSum"] != null && rec["autoSum"] isnot Bool) throw ArgErr("autoSum 必须为布尔值")
    if (rec["autoSum"] == true && rec["expressionId"] != null) throw ArgErr("分表合计与计算公式不能同时启用")
    name := (rec["name"] as Str ?: "").trim
    if (!kinds.contains(kind)) throw ArgErr("不支持的配置类型")
    if (name.isEmpty || name.size > 160) throw ArgErr("名称不能为空，且不得超过160个字符")
    id := rec["id"] as Str
    if (!(rec["nativeEquip"] == true && rec["useAlias"] != true) && all.any |r| { r["kind"] != "nativePoint" && r["id"] != id && r["name"] == name && (["space","organization"].contains(kind) ? (r["kind"] == kind && r["parentId"] == rec["parentId"]) : (!["space","organization"].contains(r["kind"]) && ((nodeKinds.contains(kind) && nodeKinds.contains(r["kind"])) || r["kind"] == kind))) })
      throw ArgErr("名称已存在")
    ["area", "maximum", "coalFactor", "co2Factor", "rawcoalFactor", "oilFactor", "actualEfficiency", "baselineEfficiency", "alarmLimit", "rate"].each |key|
    {
      if (rec[key] != null && (number(rec[key]) < 0f || (number(rec[key]).isNaN || number(rec[key]).abs == Float.posInf))) throw ArgErr("$key 必须为非负有限数值")
    }
    if (nodeKinds.contains(kind))
    {
      parent := rec["parentId"] as Str
      if (parent != null && !parent.isEmpty)
      {
        requireRef(parent, ["space","organization"].contains(kind) ? [kind] : ["group"], all)
        seen := Str[,]
        while (parent != null && !parent.isEmpty)
        {
          if (parent == id || seen.contains(parent)) throw ArgErr("管理树不能形成循环")
          seen.add(parent)
          p := all.find |r| { r["id"] == parent }
          parent = p?.get("parentId") as Str
        }
      }
    }
    ["categoryId":"category", "subcategoryId":"subcategory", "utilityId":"utility", "tariffId":"tariff", "expressionId":"expression"].each |targetKind, key|
    {
      ref := rec[key] as Str
      if (ref != null && !ref.isEmpty) requireRef(ref, [targetKind], all)
    }
    if (["meter", "totalMeter"].contains(kind))
    {
      mode := rec["historyMode"] as Str ?: "auto"
      if (!["auto","cumulative","interval"].contains(mode)) throw ArgErr("请选择有效的历史读数类型")
      if (mode != "auto" && rec["pointId"] != null && all.any |r| { r["id"] != id && r["pointId"] == rec["pointId"] && r["historyMode"] != null && r["historyMode"] != "auto" && r["historyMode"] != mode }) throw ArgErr("同一 FIN 点的历史读数类型必须一致")
      if ((rec["categoryId"] as Str ?: "").isEmpty) throw ArgErr("请选择能耗分类")
      ["subcategoryId", "utilityId"].each |key|
      {
        child := all.find |r| { r["id"] == rec[key] }
        if (child != null && child["categoryId"] != rec["categoryId"]) throw ArgErr("子分类或分项不属于所选能耗分类")
      }
      if (kind == "totalMeter" && rec["parentId"] != null && all.any |r| { r["id"] != id && r["kind"] == kind && r["parentId"] == rec["parentId"] && r["categoryId"] == rec["categoryId"] })
        throw ArgErr("同一管理组每种能源只能有一块总表")
    }
    EnerCubixRelations.validate(rec,all)
    if (["subcategory", "utility"].contains(kind)) requireRef(rec["categoryId"] as Str ?: "", ["category"], all)
    if (kind == "expression")
    {
      formula := rec["formula"] as Str ?: ""
      Map vars := (rec["variables"] as Map) ?: Str:Obj?[:]
      if (formula.trim.isEmpty || !Regex<|[A-Za-z0-9_ .+*/()\-]+|>.matches(formula)) throw ArgErr("表达式只允许变量、数值、括号和四则运算")
      vars.each |v,k|
      {
        if (!Regex<|[A-Za-z_][A-Za-z0-9_]*|>.matches(k.toStr)) throw ArgErr("变量名无效")
        requireRef(v.toStr, ["meter", "totalMeter", "sensor"], all)
      }
      names := Regex<|[A-Za-z_][A-Za-z0-9_]*|>.matcher(formula)
      while (names.find) if (!vars.containsKey(names.group)) throw ArgErr("表达式含未定义的变量")
      if (!EnerCubixExpression.validate(formula,vars.keys.map |k->Str| { k.toStr })) throw ArgErr("表达式语法无效")
      // Follow meter -> expression -> variables before commit, including this edit.
      withEdit := all.findAll |r| { r["id"] != id }.dup.add(rec)
      if (id != null) verifyFormulaGraph(id, withEdit, Str[,])
    }
    if (rec["expressionId"] != null)
    {
      withEdit := all.findAll |r| { r["id"] != id }.dup.add(rec)
      verifyFormulaGraph(rec["expressionId"].toStr,withEdit,Str[,])
    }
    if (kind == "cop") ["numeratorId", "denominatorId"].each |key| { requireRef(rec[key] as Str ?: "", ["meter", "totalMeter", "group"], all) }
    if (kind == "tariff")
    {
      if (rec["isDefault"] == true && all.any |r| { r["id"] != id && r["kind"] == "tariff" && r["isDefault"] == true && r["categoryId"] == rec["categoryId"] }) throw ArgErr("每个分类只能有一个默认费率")
      mode := rec["mode"] as Str ?: "flat"
      if (!["flat", "absolute", "weekly", "monthlyBlock", "yearlyBlock"].contains(mode)) throw ArgErr("无效计费类型")
      if (rec["band"] != null && !["sharp","peak","flat","valley","unknown"].contains(rec["band"])) throw ArgErr("无效费率时段分类")
      last := 0f
      List blocks := (rec["blocks"] as List) ?: Obj?[,]
      if (mode.endsWith("Block") && blocks.isEmpty) throw ArgErr("请设置阶梯费率")
      blocks.each |v,i|
      {
        block := v as Map ?: throw ArgErr("阶梯格式无效")
        limit := block["limit"]
        if (number(block["rate"]) < 0f) throw ArgErr("费率不得为负数")
        if (limit == null) { if (i != blocks.size-1) throw ArgErr("无上限档必须在最后") }
        else { n := number(limit); if (n <= last) throw ArgErr("阶梯上限必须递增"); last = n }
      }
      ["rules", "exceptions"].each |key|
      {
        ((List)((rec[key] as List) ?: Obj?[,])).each |v|
        {
          rule := v as Map ?: throw ArgErr("费率规则格式无效")
          if (rule["band"] != null && !["sharp","peak","flat","valley","unknown"].contains(rule["band"])) throw ArgErr("无效费率时段分类")
          if (number(rule["rate"]) < 0f) throw ArgErr("费率不得为负数")
          start := number(rule["startHour"], 0f); end := number(rule["endHour"], 24f)
          if (start < 0f || end > 24f || start >= end) throw ArgErr("时段应满足 0≤开始<结束≤24")
          day := number(rule["weekday"], 1f)
          if (day < 1f || day > 7f) throw ArgErr("星期应为1至7")
        }
      }
    }
    if (kind == "calendar")
    {
      if (rec["isDefault"] == true && all.any |r| { r["id"] != id && r["kind"] == "calendar" && r["isDefault"] == true }) throw ArgErr("只能有一个默认日历")
      ["sharpHours", "peakHours", "valleyHours", "workHours"].each |key|
      {
        ((List)((rec[key] as List) ?: Obj?[,])).each |v| { n := number(v); if (n < 0f || n > 23f || n != n.floor) throw ArgErr("小时必须为0至23的整数") }
      }
      List peaks := (rec["peakHours"] as List) ?: Obj?[,]
      List valleys := (rec["valleyHours"] as List) ?: Obj?[,]
      List sharp := (rec["sharpHours"] as List) ?: Obj?[,]
      if (peaks.any |v| { valleys.contains(v) }) throw ArgErr("峰时段与谷时段不能重叠")
      if (sharp.any |v| {peaks.contains(v) || valleys.contains(v)}) throw ArgErr("尖、峰、谷时段不能重叠")
      ((List)((rec["workDays"] as List) ?: Obj?[,])).each |v| { n := number(v); if (n < 1f || n > 7f) throw ArgErr("工作日必须为1至7") }
      List exceptions := rec["exceptions"] as List ?: Obj?[,]
      dates := Str[,]
      exceptions.each |v|
      {
        e := (Map)v
        date := e["date"] as Str ?: throw ArgErr("调休日期不能为空")
        if (Date.fromStr(date,false) == null || e["working"] isnot Bool || dates.contains(date)) throw ArgErr("调休日期、工作日标志无效或日期重复")
        dates.add(date)
      }
    }
    if (kind == "binding" && !["energy","reference","runtime"].contains(rec["role"])) throw ArgErr("请选择点位用途")
    if (kind == "settings" && all.any |r| { r["id"] != id && r["kind"] == "settings" }) throw ArgErr("概览设置只能有一条")
    if (kind == "settings") EnerCubixMeterRollup.intervalSeconds(rec["meterRollupSeconds"])
    List alarmLimits := rec["alarmLimits"] as List ?: Obj?[,]
    alarmLimits.each |v|
    {
      limit := (Map)v
      requireRef(limit["categoryId"] as Str ?: "",["category"],all)
      if (number(limit["limit"]) < 0f) throw ArgErr("报警阈值不得为负数")
    }
  }

  static Void canDelete(Str id, [Str:Obj?][] all)
  {
    if (all.any |r| { r["id"] != id && !["alarm","job"].contains(r["kind"]) && references(r, id) }) throw ArgErr("该记录仍被引用或包含子项，请先解除关联")
  }

  static Bool references(Obj? value, Str id)
  {
    if (value is Map)
    {
      found := false
      ((Map)value).each |v,k|
      {
        if (k == "id" || k == "mod") return
        if (v == id || references(v, id)) found = true
      }
      return found
    }
    if (value is List) return ((List)value).any |v| { v == id || references(v,id) }
    return false
  }

  private static Void requireRef(Str id, Str[] expected, [Str:Obj?][] all)
  {
    ref := all.find |r| { r["id"] == id }
    if (ref == null || !expected.contains(ref["kind"])) throw ArgErr("引用的配置不存在或类型不符")
  }

  private static Void verifyFormulaGraph(Str id, [Str:Obj?][] all, Str[] path)
  {
    if (path.contains(id)) throw ArgErr("表达式依赖不能形成循环")
    expr := all.find |r| { r["id"] == id }
    if (expr == null) return
    Map vars := (expr["variables"] as Map) ?: Str:Obj?[:]
    vars.each |meterId|
    {
      meter := all.find |r| { r["id"] == meterId }
      next := meter?.get("expressionId") as Str
      if (next != null) verifyFormulaGraph(next, all, path.dup.add(id))
    }
  }

  static Float number(Obj? v, Float fallback := 0f)
  {
    if (v == null) return fallback
    if (v is Int) return ((Int)v).toFloat
    if (v is Float) return (Float)v
    if (v is Decimal) return ((Decimal)v).toFloat
    return Float.fromStr(v.toStr)
  }
}

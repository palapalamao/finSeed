internal class EnerCubixContext
{
  ** A separate report-only context keeps strict calculation and caches untouched.
  new known(EnerCubixContext strict, DateTime queryEnd)
  {
    tz=strict.tz; dimension=strict.dimension; comparison=strict.comparison; byId=strict.byId; byPoint=strict.byPoint
    children=strict.children; calendar=strict.calendar; strictContext=strict; knownEnd=queryEnd
    preparedBudget=strict.preparedBudget;deadline=strict.deadline
    inheritOwners(strict,false)
    retain(4,true);if(preparedBudget != null) tariffBaseline.ordered=true
  }
  new bound(EnerCubixContext source, Str id, Str:Obj? record)
  {
    tz=source.tz; dimension=source.dimension; comparison=source.comparison; byId=source.byId.dup.set(id,record)
    byPoint=source.byPoint; children=source.children; calendar=source.calendar
    preparedBudget=source.preparedBudget;deadline=source.deadline
    inheritOwners(source,true)
    retain(4+(persistentOwner == null ? 0 : byId.size));if(preparedBudget != null) tariffBaseline.ordered=true
  }
  new make([Str:Obj?][] records, [Str:Obj?][] histories, TimeZone tz, EnerCubixDimension? dimension := null)
  {
    this.tz=tz
    this.dimension=dimension
    records.each |r|
    {
      id := r["id"]?.toStr
      if (id != null) byId[id] = r
    }
    histories.each |h| { parsed:=EnerCubixHistoryData(h); byPoint[parsed.id]=parsed }
    preparedBudget=byPoint.vals.find |h| {h.preparedBudget != null}?.preparedBudget
    deadline=preparedBudget?.deadline
    if(preparedBudget != null) {preparedBudget.hold(1+5*byPoint.size);tariffBaseline.ordered=true}
    records.each |r|
    {
      parent := r["parentId"]?.toStr
      if (parent == null) return
      if (!children.containsKey(parent)) children[parent]=[Str:Obj?][,]
      children[parent].add(r)
    }
    calendars:=records.findAll |r| { r["kind"] == "calendar" }
    defaults:=calendars.findAll |r| { r["isDefault"] == true }
    if (defaults.size == 1) calendar=defaults.first
    else if (defaults.isEmpty && calendars.size == 1) calendar=calendars.first
  }
  TimeZone tz
  EnerCubixDimension? dimension
  EnerCubixComparisonScope? comparison
  Str:[Str:Obj?] byId := [:]
  Str:EnerCubixHistoryData byPoint := [:]
  Str:[Str:Obj?][] children := [:]
  [Str:Obj?]? calendar
  Str[] warnings := [,]
  private Str:EnerCubixValue cache := [:]
  private Str:EnerCubixValue tariffBaseline := [:]
  private Str:Obj? defaultTariffs := [:]
  private Str:[Str:Obj?] dimensionPlans := [:]
  private EnerCubixContext? strictContext
  private DateTime? knownEnd
  Str:[Str:Obj?] knownReads := [:]
  Str:[Str:Obj?] usedTariffs := [:]
  private Int knownDetailCount := 0
  EnerCubixPreparedBudget? preparedBudget
  EnerCubixCockpitDeadline? deadline
  private Int nodeCalls := 0
  private Bool omittedEmptyEvidence := false
  private Bool omittedUnpreparedEvidence := false
  private EnerCubixPreparedOwner? persistentOwner
  private EnerCubixPreparedOwner? frameOwner
  private Bool framed := false
  private Bool transientContext := false

  internal Void useOwner(EnerCubixPreparedOwner owner)
  {
    if(framed || preparedBudget != null || !byPoint.isEmpty) throw ArgErr("preparedContextAlreadyInitialized")
    framed=true
    index:=1+byId.size+children.size
    children.each |rows| {index+=rows.size}
    owner.watch |->Void| {dropPersistent};owner.hold(index)
    persistentOwner=owner;preparedBudget=owner.budget;deadline=owner.budget.deadline;tariffBaseline.ordered=true
  }
  internal Void beginFrame(EnerCubixPreparedOwner owner,Str:EnerCubixHistoryData histories)
  {
    if(persistentOwner == null || frameOwner != null || owner === persistentOwner || owner.budget !== preparedBudget) throw ArgErr("preparedContextOwner")
    histories.each |h,id| {if(h.id != id || !h.ownedFrame(owner.budget)) throw ArgErr("preparedContextSourceFrame")}
    if(strictContext != null)
    {
      if(strictContext.frameOwner !== owner || histories.size != strictContext.byPoint.size || histories.any |h,id| {h !== strictContext.byPoint[id]}) throw ArgErr("preparedContextStrictFrame")
    }
    owner.watch |->Void| {dropFrame}
    if(strictContext == null) {owner.hold(1+histories.size);byPoint=histories.dup}
    else byPoint=strictContext.byPoint
    frameOwner=owner
  }
  private Void inheritOwners(EnerCubixContext source,Bool temporary)
  {
    if(source.framed && source.persistentOwner == null) throw ArgErr("preparedContextClosed")
    if(source.persistentOwner == null) return
    transient:=source.transientContext || (temporary && source.frameOwner != null)
    source.frameOwner?.watch |->Void| {dropFrame}
    if(!transient) source.persistentOwner.watch |->Void| {dropPersistent}
    persistentOwner=source.persistentOwner;frameOwner=source.frameOwner;framed=true;transientContext=transient
  }
  private Void retain(Int n,Bool persistent := false)
  {
    owner:=transientContext ? frameOwner : (persistent ? persistentOwner : (frameOwner ?: persistentOwner))
    if(owner != null) owner.hold(n)
    else preparedBudget?.hold(n)
  }
  private Void frameCheck() {if(framed && frameOwner == null) throw ArgErr("preparedContextInactive")}
  private Void dropFrame()
  {
    cache.clear;knownReads.clear;byPoint=Str:EnerCubixHistoryData[:]
    knownDetailCount=0;omittedEmptyEvidence=false;omittedUnpreparedEvidence=false;frameOwner=null
    if(transientContext)
    {
      tariffBaseline.clear;defaultTariffs.clear;dimensionPlans.clear;usedTariffs.clear;warnings.clear
      byId=Str:[Str:Obj?][:];children=Str:[Str:Obj?][][:];calendar=null;strictContext=null;persistentOwner=null
    }
  }
  private Void dropPersistent()
  {
    if(frameOwner != null) throw ArgErr("preparedFrameActive")
    dropFrame;tariffBaseline.clear;defaultTariffs.clear;dimensionPlans.clear;usedTariffs.clear;warnings.clear
    byId=Str:[Str:Obj?][:];children=Str:[Str:Obj?][][:];calendar=null;strictContext=null;persistentOwner=null
  }

  ** Empty prepared lookups do not become a second dense cache. They have zero
  ** coverage and no source intervals; authoritative per-object coverage remains.
  Str:Obj? knownEvidence(Bool includeDetails := true)
  {
    frameCheck
    reads:=EnerCubixKnownUsage.evidence(knownReads.vals)
    out:=Str:Obj?["basis":"closedSourceIntervals","sourceUsage":reads]
    if(includeDetails || omittedEmptyEvidence || omittedUnpreparedEvidence) out["detailsTruncated"]=omittedEmptyEvidence || omittedUnpreparedEvidence || reads.any |r| {r["detailsTruncated"] == true}
    if(omittedEmptyEvidence || omittedUnpreparedEvidence) out.setAll(["sourceUsageCaptureId":Uuid().toStr,"sourceUsageTruncated":true,"sourceUsageRowCount":null,"truncationReason":"cockpitBoundedPreparedEvidence","omittedConfirmedEmpty":omittedEmptyEvidence,"omittedUnprepared":omittedUnpreparedEvidence])
    return out
  }
  Void mergeKnown(EnerCubixContext other)
  {
    frameCheck;other.frameCheck
    omittedEmptyEvidence=omittedEmptyEvidence || other.omittedEmptyEvidence
    omittedUnpreparedEvidence=omittedUnpreparedEvidence || other.omittedUnpreparedEvidence
    other.knownReads.each |v,k| {if(!knownReads.containsKey(k)) retain(1);knownReads[k]=v}
  }

  private EnerCubixValue sumValues(EnerCubixValue[] values)
  { strictContext == null ? EnerCubixValue.sum(values) : EnerCubixKnownUsage.combine(values) }

  Void warn(Str message)
  {
    if(!warnings.contains(message)) {if(persistentOwner != null) retain(1,true);warnings.add(message)}
  }

  Str displayName(Str id)
  {
    record:=byId[id]
    if (record == null)
    {
      bindings:=byId.vals.findAll |r| { r["kind"] == "binding" && r["pointId"]?.toStr == id }
      record=bindings.find |r| { r["role"] == "reference" } ?: bindings.first
    }
    alias:=record?.get("alias") as Str
    if (alias != null && !alias.trim.isEmpty) return alias.trim
    name:=record?.get("name") as Str
    return name != null && !name.trim.isEmpty ? name : id
  }

  Str[] categories(Str id, Str[] visited := Str[,])
  {
    r := byId[id]
    if (r == null || visited.contains(id)) return Str[,]
    if (dimension?.scope(id) == true) return dimension.members(id).map |m->Str| { m["categoryId"]?.toStr ?: "" }.unique.sort
    if (r["kind"] != "group") return [r["categoryId"]?.toStr ?: ""]
    out := Str[,]
    (children[id] ?: [Str:Obj?][,]).each |child|
    {
      if (!included(child)) return
      out.addAll(categories(child["id"].toStr,visited.dup.add(id)))
    }
    return out.unique.sort
  }

  Bool included(Str:Obj? r)
  {
    k := r["kind"]?.toStr
    if (k == "sensor") return false
    if (k == "group") return true
    if (k != "meter" && k != "totalMeter") return false
    return (Bool?)r["includeInTotals"] ?: (r["expressionId"] == null)
  }

  ** Effective meters, independent of the view used to select them. A selected
  ** physical meter owns its own history; a scope resolves the same frontier.
  [Str:Obj?][] scopeMeters(Str id, Str category, Str[] path := Str[,], Str? utility := null)
  {
    r:=byId[id]
    if (r == null || path.contains(id)) return [Str:Obj?][,]
    if (dimension?.scope(id) == true || (utility != null && dimension?.dimension == "metering"))
    {
      members:=(utility == null ? dimension.members(id) : dimension.usageMembers(id)).findAll |m| {m["categoryId"] == category}
      return utility == null ? dimension.frontier(members) : dimension.usageFrontier(members).findAll |m| {(m["utilityId"] as Str ?: "") == utility}
    }
    if (["meter","totalMeter"].contains(r["kind"]))
    {
      canonical:=r["canonicalId"] as Str
      return r["categoryId"] != category || (utility != null && (r["utilityId"] as Str ?: "") != utility) ? [Str:Obj?][,] : [canonical == null ? r : (byId[canonical] ?: r)]
    }
    if (r["kind"] != "group") return [Str:Obj?][,]
    members:=(children[id] ?: [Str:Obj?][,]).findAll |m| {included(m)}
    masters:=members.findAll |m| {m["kind"] == "totalMeter" && m["categoryId"] == category && (utility == null || m["utilityId"] == utility)}
    if (!masters.isEmpty) return masters
    return members.findAll |m| {m["kind"] != "totalMeter"}.map |m->[Str:Obj?][]| {scopeMeters(m["id"].toStr,category,path.dup.add(id),utility)}.flatten
  }

  [Str:Obj?][] selectionMeters([Str:Obj?][] members)
  {
    unique:=Str:[Str:Obj?][:]
    members.each |m| {unique[m["id"].toStr]=m}
    return unique.vals.findAll |m|
    {
      seen:=Str[,]; parent:=m["meterParentId"] as Str
      while (parent != null && !seen.contains(parent))
      {
        if (unique.containsKey(parent)) return false
        seen.add(parent); parent=byId[parent]?.get("meterParentId") as Str
      }
      return true
    }.sort |a,b| {a["id"].toStr <=> b["id"].toStr}
  }

  Str[] utilities(Str id, Str category, Str[] path := Str[,])
  {
    if (path.contains(id)) return Str[,]
    if (dimension?.scope(id) == true || dimension?.dimension == "metering") return dimension.usageFrontier(dimension.usageMembers(id).findAll |m| { (m["categoryId"]?.toStr ?: "") == category }).map |m->Str| { m["utilityId"]?.toStr ?: "" }.unique.sort
    out:=Str[,]
    (children[id] ?: [Str:Obj?][,]).each |r|
    {
      if (!included(r) || (r["kind"] == "totalMeter" && r["utilityId"] == null)) return
      if (r["kind"] == "group") out.addAll(utilities(r["id"].toStr,category,path.dup.add(id)))
      else if ((r["categoryId"]?.toStr ?: "") == category) out.add(r["utilityId"]?.toStr ?: "")
    }
    return out.unique.sort
  }

  ** Exclude only this group's master; each child group's master remains authoritative.
  EnerCubixValue branch(Str id, Str category, DateTime start, DateTime end, Str metric)
  {
    frameCheck
    values:=EnerCubixValue[,]
    (children[id] ?: [Str:Obj?][,]).each |r|
    {
      if (!included(r) || r["kind"] == "totalMeter") return
      child:=r["id"].toStr
      if (categories(child).contains(category)) values.add(node(child,category,start,end,metric,[id]))
    }
    return EnerCubixValue.sum(values)
  }

  EnerCubixValue node(Str id, Str category, DateTime from, DateTime to, Str metric := "energy", Str[] path := Str[,], Str? utility := null, Bool useMaster := true)
  {
    frameCheck
    if(++nodeCalls % 128 == 0) deadline?.check
    if (path.contains(id)) return EnerCubixValue(null,"cycle")
    key := preparedBudget == null ? "$id|$category|${from.ticks}|${to.ticks}|$metric|$utility|$useMaster" : ""
    if (path.isEmpty && cache.containsKey(key)) return cache[key]
    r := byId[id]
    if (r == null) return EnerCubixValue(null,"unknownNode")
    if (comparison != null && (r["_comparisonReadable"] == false || r["_comparisonPointReadable"] == false)) return EnerCubixValue(null,"forbidden")
    if (r["configurationError"] != null)
    {
      warn(r["name"].toStr+"："+r["configurationError"])
      return EnerCubixValue(null,"invalidConfiguration")
    }
    stable:=emptyKey(r,category,from,to,metric)
    if(stable != null && cache.containsKey(stable)) {preparedBudget.contextEmptyHits.increment;return cache[stable]}
    nextPath := path.dup.add(id)
    EnerCubixValue result := EnerCubixValue()
    if (dimension?.scope(id) == true)
    {
      planKey:="$id|$category|$utility"
      plan:=dimensionPlans[planKey]
      if (plan == null)
      {
        members:=dimension.members(id).findAll |m| { (m["categoryId"]?.toStr ?: "") == category }
        authoritative:=(utility == null ? dimension.frontier(members) : dimension.usageFrontier(members)).findAll |m| { utility == null || (m["utilityId"]?.toStr ?: "") == utility }
        plan=["members":authoritative,"quality":dimension.quality(members)]
        retain(1+authoritative.size,true)
        dimensionPlans[planKey]=plan
      }
      authoritative:=([Str:Obj?][])plan["members"]
      values:=authoritative.map |m->EnerCubixValue| { node(m["id"].toStr,category,from,to,metric,nextPath) }
      result=sumValues(values)
      quality:=plan["quality"] as Str
      if (quality != null && (strictContext == null || quality != "accountingIncomplete")) result=EnerCubixValue(null,quality,result.sources)
    }
    else if (utility != null && dimension?.dimension == "metering")
    {
      members:=dimension.usageMembers(id).findAll |m| { (m["categoryId"]?.toStr ?: "") == category }
      authoritative:=dimension.usageFrontier(members).findAll |m| { (m["utilityId"]?.toStr ?: "") == utility }
      values:=authoritative.map |m->EnerCubixValue| { node(m["id"].toStr,category,from,to,metric,m["id"] == id ? path : nextPath) }
      result=sumValues(values)
      quality:=dimension.quality(members)
      if (quality != null && (strictContext == null || quality != "accountingIncomplete")) result=EnerCubixValue(null,quality,result.sources)
    }
    else if (r["kind"] == "group")
    {
      members := children[id] ?: [Str:Obj?][,]
      masters := members.findAll |m| { m["kind"] == "totalMeter" && m["categoryId"]?.toStr == category && included(m) && (utility == null || (m["utilityId"] != null && m["utilityId"]?.toStr == utility)) }
      if (useMaster && !masters.isEmpty)
      {
        if (masters.size > 1) result=EnerCubixValue(null,"ambiguousMaster")
        else result=node(masters.first["id"].toStr,category,from,to,metric,nextPath,utility,useMaster)
      }
      else
      {
        values := EnerCubixValue[,]
        members.each |m|
        {
          if (!included(m) || m["kind"] == "totalMeter") return
          if (m["kind"] == "group")
          {
            if (utility != null && !utilities(m["id"].toStr,category).contains(utility)) return
            if (categories(m["id"].toStr).contains(category)) values.add(node(m["id"].toStr,category,from,to,metric,nextPath,utility,useMaster))
          }
          else if ((m["categoryId"]?.toStr ?: "") == category && (utility == null || (m["utilityId"]?.toStr ?: "") == utility)) values.add(node(m["id"].toStr,category,from,to,metric,nextPath,utility,useMaster))
        }
        result=sumValues(values)
      }
    }
    else if (r["kind"] == "cop")
    {
      if (strictContext != null) return strictContext.node(id,category,from,to,metric,path,utility,useMaster)
      a := r["numeratorId"]?.toStr ?: ""; b := r["denominatorId"]?.toStr ?: ""
      result=EnerCubixValue.divide(nodeTotal(a,from,to,nextPath),nodeTotal(b,from,to,nextPath))
    }
    else
    {
      raw := rawNode(r,from,to,nextPath)
      if (metric == "energy") result=raw
      else if (r["kind"] == "sensor") result=EnerCubixValue(null,"invalidMetric",raw.sources)
      else if (metric == "cost") result=cost(r,raw,from,to,nextPath)
      else
      {
        sub := byId[r["subcategoryId"]?.toStr ?: ""]
        factor := sub == null ? null : EnerCubixMath.num(sub[metric+"Factor"])
        result=factor == null ? EnerCubixValue(null,"missingCoefficient",raw.sources) : raw.scale(factor)
      }
    }
    if (result.value == null) { label:=r["name"] ?: id; warn("$label : ${result.quality}") }
    if (path.isEmpty && preparedBudget == null) cache[key]=result
    if(stable != null && result.value == null)
    {if(!cache.containsKey(stable)) retain(2);cache[stable]=result}
    return result
  }

  private Str? emptyKey(Str:Obj? r,Str category,DateTime from,DateTime to,Str metric)
  {
    if(preparedBudget == null || !["meter","totalMeter"].contains(r["kind"])) return null
    if(metric == "cost")
    {
      mode:=tariff(r)?.get("mode")
      // A missing billing baseline has different precedence from the first
      // missing hour of a cycle. Leave every tiered-price call on the old path.
      if(mode == "monthlyBlock" || mode == "yearlyBlock") return null
    }
    h:=byPoint[r["pointId"] as Str ?: ""]
    // This source was not captured in this report. Keep the original fixed
    // not-loaded result; it is not evidence that FIN history was read and empty.
    if(h == null) return "notLoaded|"+r["id"]+"|"+category+"|"+metric
    if(!["ok","cleaned","estimated","derived","corrected"].contains(h.quality)) return null
    domain:=h.emptyDomain(from,to,knownEnd)
    if(domain == null && !h.unpreparedPair(from,to,knownEnd)) return null
    return "constant|"+r["id"]+"|"+category+"|"+metric+"|"+(domain?.toStr ?: "notPrepared")
  }

  DateTime? constantEnd(Str id,Str category,DateTime from,DateTime to,Str metric)
  {
    frameCheck
    r:=byId[id]
    if(r == null || preparedBudget == null || !["meter","totalMeter"].contains(r["kind"])) return null
    mode:=metric == "cost" ? tariff(r)?.get("mode") : null
    if(mode == "monthlyBlock" || mode == "yearlyBlock") return null
    h:=byPoint[r["pointId"] as Str ?: ""]
    return h == null ? to : h.constantEnd(from,to,knownEnd)
  }

  EnerCubixValue nodeTotal(Str id, DateTime from, DateTime to, Str[] path := Str[,])
  {
    frameCheck
    cats := categories(id)
    return EnerCubixValue.sum(cats.map |cat->EnerCubixValue| { node(id,cat,from,to,"energy",path) })
  }

  private EnerCubixValue rawNode(Str:Obj? r, DateTime from, DateTime to, Str[] path)
  {
    frameCheck
    if (r["kind"] == "nativePoint") return EnerCubixValue(null,"notEnergyPoint")
    if (dimension?.nativeSpace == true && r["nativeSourceMissing"] == true) return EnerCubixValue(null,"nativeSourceMissing")
    EnerCubixValue raw := EnerCubixValue()
    durationFactor:=r["kind"] == "sensor" ? 1f : (to-from).ticks.toFloat/1hr.ticks.toFloat
    point := r["pointId"]?.toStr ?: ""
      his := byPoint[point]
      if (his == null) return EnerCubixValue(null,"missing",point.isEmpty ? Str[,] : [point])
      if (!["ok","estimated","derived","cleaned","corrected","filtered","substituted","na"].contains(his.quality)) return EnerCubixValue(null,his.quality,[point])
      if (r["kind"] != "sensor" && his.mode != "interval" && his.mode != "cumulative") return EnerCubixValue(null,"notEnergyHistory",[point])
      if (strictContext == null) raw=his.read(from,to)
      else
      {
        data:=his.knownUsage(from,to,knownEnd); raw=(EnerCubixValue)data["value"]
        durationFactor=(EnerCubixMath.num(data["coveredSeconds"]) ?: 0f)/3600f
        details:=EnerCubixMath.maps(data["intervals"])
        empty:=preparedBudget != null && data["knownValue"] == null && data["knownQuality"] == "missing" && data["coveredSeconds"] == 0f && data["intervalCount"] == 0 && data["intervalStart"] == null && data["intervalEnd"] == null && details.isEmpty
        unprepared:=preparedBudget != null && raw.quality == "streamingReadNotPrepared" && data.size == 1
        if(empty) omittedEmptyEvidence=true
        else if(unprepared) omittedUnpreparedEvidence=true
        else
        {
          evidence:=data.dup; evidence.remove("value")
          remaining:=1000-knownDetailCount
          if (details.size > remaining)
          {
            evidence["intervals"]=remaining == 0 ? [Str:Obj?][,] : details[0..<remaining]
            evidence["detailsTruncated"]=true
            evidence["intervalsCaptureId"]=Uuid().toStr
          }
          knownDetailCount+=EnerCubixMath.maps(evidence["intervals"]).size
          evidence.setAll(["nodeId":r["id"],"pointId":point,"sourceIds":his.sources,"unit":his.unit,"from":from.toIso,"to":to.toIso])
          recordId:=r["id"].toStr
          key:="$recordId|$point|${from.ticks}|${to.ticks}"
          if(!knownReads.containsKey(key)) retain(2)
          knownReads[key]=evidence
        }
      }
    max := EnerCubixMath.num(r["maximum"])
    if (raw.value != null && max != null && raw.value > max*durationFactor) return EnerCubixValue(null,"maximum",raw.sources)
    if (r["kind"] != "sensor")
    {
      sourceHistory:=byPoint[r["pointId"]?.toStr ?: ""]
      sourceUnit:=sourceHistory?.unit ?: ""
      if (sourceUnit.isEmpty) sourceUnit=r["unit"]?.toStr ?: ""
      targetUnit:=categoryUnit(r["categoryId"]?.toStr ?: "")
      factor:=EnerCubixMath.unitFactor(sourceUnit,targetUnit)
      if (factor == null) return EnerCubixValue(null,"incompatibleUnit",raw.sources)
      raw=raw.scale(factor)
    }
    return raw
  }

  private EnerCubixValue cost(Str:Obj? r, EnerCubixValue raw, DateTime from, DateTime to, Str[] path)
  {
    t := tariff(r)
    if (t == null) return EnerCubixValue(null,"missingTariff",raw.sources)
    if (!usedTariffs.containsKey(r["id"].toStr))
    {
      snapshot:=t.findAll |value,key| {["id","mod","name","mode","rate","band","rules","exceptions","blocks","categoryId","currency"].contains(key)}
      if(persistentOwner != null) retain(2,true)
      usedTariffs[r["id"].toStr]=snapshot.dup.set("nodeId",r["id"])
    }
    mode := t["mode"]?.toStr ?: "flat"
    if (mode == "monthlyBlock" || mode == "yearlyBlock")
    {
      // A known subtotal cannot establish a cumulative billing tier.
      if (strictContext != null) return strictContext.node(r["id"].toStr,r["categoryId"].toStr,from,to,"cost")
      cycle := EnerCubixMath.bucket(from,mode == "yearlyBlock" ? "year" : "month")
      // Baseline is meter-specific. Missing preceding hours invalidate the price band.
      meterId:=r["id"].toStr
      baselineKey:="$meterId|${cycle.ticks}|${from.ticks}"
      baseline:=tariffBaseline[baselineKey]
      if (baseline == null)
      {
        values := EnerCubixValue[,]; cursor:=cycle
        while (cursor < from)
        {
          end:=EnerCubixMath.floorHour(cursor)+1hr; if (end > from) end=from
          values.add(rawNode(r,cursor,end,path)); cursor=end
        }
        baseline=values.isEmpty ? EnerCubixValue(0f,"ok") : EnerCubixValue.sum(values)
        saveBaseline(baselineKey,baseline)
      }
      nextKey:="$meterId|${cycle.ticks}|${to.ticks}"
      // Only one complete original hour extends the canonical prefix. A partial
      // or multi-hour raw query is not the cycle's ordered hourly reduction.
      if(from == EnerCubixMath.floorHour(from) && to == from+1hr)
        saveBaseline(nextKey,EnerCubixValue.sum([baseline,raw]))
      if (!baseline.reliable || !raw.reliable) return EnerCubixValue(null,EnerCubixValue.worse(baseline.quality,raw.quality),raw.sources)
      if (baseline.value == null) return EnerCubixValue(null,"missingTariffBaseline",raw.sources)
      if (raw.value == null) return raw
      lo:=blockPrice(t,baseline.value); hi:=blockPrice(t,baseline.value+raw.value)
      if (lo == null || hi == null) return EnerCubixValue(null,"invalidTariff",raw.sources)
      return EnerCubixValue(hi-lo,EnerCubixValue.worse(baseline.quality,raw.quality),raw.sources)
    }
    if (raw.value == null) return raw
    // Split within an hour for absolute dates and fractional start/endHour rules.
    bounds := tariffBounds(t,from,to)
    if (strictContext != null && bounds.size > 2)
    {
      recordId:=r["id"].toStr; point:=r["pointId"].toStr
      previous:=knownReads.remove("$recordId|$point|${from.ticks}|${to.ticks}")
      knownDetailCount-=EnerCubixMath.maps(previous?.get("intervals")).size
    }
    parts:=EnerCubixValue[,]
    for (i:=0;i<bounds.size-1;i++)
    {
      a:=bounds[i]; b:=bounds[i+1]
      energy:=bounds.size == 2 ? raw : rawNode(r,a,b,path)
      rate:=rateAt(t,a)
      parts.add(rate == null ? EnerCubixValue(null,"missingTariff",raw.sources) : energy.scale(rate))
    }
    return sumValues(parts)
  }

  private Void saveBaseline(Str key,EnerCubixValue value)
  {
    if(preparedBudget != null && !tariffBaseline.containsKey(key))
    {
      if(tariffBaseline.size >= 256) tariffBaseline.remove(tariffBaseline.keys.first)
      else retain(2,true)
    }
    tariffBaseline[key]=value
  }

  internal DateTime[] tariffBounds(Str:Obj? t, DateTime from, DateTime to)
  {
    bounds := [from,to]
    rules := EnerCubixMath.maps(t["rules"]).addAll(EnerCubixMath.maps(t["exceptions"]))
    rules.each |rule|
    {
      ["from","to"].each |key|
      {
        text:=rule[key]?.toStr
        if (text == null) return
        at:=text.size == 10 ? Date.fromStr(text,false)?.toDateTime(Time.defVal,tz) : DateTime.fromIso(text,false)
        if (at != null && at > from && at < to) bounds.add(at.toTimeZone(tz))
      }
      ["startHour","endHour"].each |key|
      {
        hour:=EnerCubixMath.num(rule[key]); if (hour == null) return
        at:=from.date.toDateTime(Time.defVal,tz)+Duration((hour*1hr.ticks.toFloat).toInt)
        if (at > from && at < to) bounds.add(at)
      }
    }
    return bounds.unique.sort
  }

  ** Bands are explicit tariff labels, never guessed from relative prices.
  ** The calendar remains a fallback for projects without a tariff.
  Str timeBand(Str id, Str category, DateTime from, DateTime to, Str? utility := null)
  {
    if(++nodeCalls % 128 == 0) deadline?.check
    bands:=Str[,]
    scopeMeters(id,category,Str[,],utility).each |meter|
    {
      t:=tariff(meter)
      if (t == null)
      {
        bands.add(calendar == null ? "unknown" : (EnerCubixMath.containsNum(calendar["sharpHours"],from.hour) ? "sharp" : (EnerCubixMath.containsNum(calendar["peakHours"],from.hour) ? "peak" : (EnerCubixMath.containsNum(calendar["valleyHours"],from.hour) ? "valley" : "flat"))))
        return
      }
      bounds:=tariffBounds(t,from,to)
      for (i:=0;i<bounds.size-1;i++) bands.add(bandAt(t,bounds[i]))
    }
    distinct:=bands.unique
    return distinct.size == 1 ? distinct.first : (distinct.isEmpty ? "unknown" : "mixed")
  }

  private Str bandAt(Str:Obj? tariff, DateTime at)
  {
    band:=tariff["band"] as Str ?: "unknown"
    if (tariff["mode"] != "flat") EnerCubixMath.maps(tariff["rules"]).each |rule| {if (matches(rule,at)) band=rule["band"] as Str ?: "unknown"}
    EnerCubixMath.maps(tariff["exceptions"]).each |rule| {if (matches(rule,at)) band=rule["band"] as Str ?: "unknown"}
    return ["sharp","peak","flat","valley"].contains(band) ? band : "unknown"
  }

  private Float? blockPrice(Str:Obj? tariff, Float use)
  {
    if (use < 0f) return null
    lower:=0f; total:=0f
    blocks:=EnerCubixMath.maps(tariff["blocks"])
    for (i:=0;i<blocks.size;i++)
    {
      block:=blocks[i]; rate:=EnerCubixMath.num(block["rate"]); limit:=EnerCubixMath.num(block["limit"])
      if (rate == null || rate < 0f || (limit != null && limit <= lower)) return null
      if (use <= lower) return total
      upper:=limit ?: use
      total+=(use.min(upper)-lower).max(0f)*rate
      if (limit == null || use <= upper) return total
      lower=upper
    }
    return use == lower ? total : null
  }

  private Float? rateAt(Str:Obj? tariff, DateTime at)
  {
    Float? rate:=EnerCubixMath.num(tariff["rate"])
    if (tariff["mode"] != "flat") EnerCubixMath.maps(tariff["rules"]).each |rule| { if (matches(rule,at)) rate=EnerCubixMath.num(rule["rate"]) }
    // Exceptions take precedence in all tariff modes; [from,to) is consistent with reports.
    EnerCubixMath.maps(tariff["exceptions"]).each |rule| { if (matches(rule,at)) rate=EnerCubixMath.num(rule["rate"]) }
    return rate
  }

  private Bool matches(Str:Obj? rule, DateTime at)
  {
    from:=rule["from"]?.toStr; to:=rule["to"]?.toStr
    if (from != null && !dateMatch(from,at,true)) return false
    if (to != null && !dateMatch(to,at,false)) return false
    day:=EnerCubixMath.num(rule["weekday"])
    if (day != null && day != EnerCubixMath.isoDay(at).toFloat) return false
    start:=EnerCubixMath.num(rule["startHour"]) ?: 0f; end:=EnerCubixMath.num(rule["endHour"]) ?: 24f
    hour:=at.hour.toFloat+at.min.toFloat/60f+at.sec.toFloat/3600f
    return start <= end ? hour >= start && hour < end : hour >= start || hour < end
  }

  private Bool dateMatch(Str s, DateTime at, Bool lower)
  {
    if (s.size == 10)
    {
      date:=Date.fromStr(s,false); if (date == null) return false
      return lower ? at.date >= date : at.date < date
    }
    dt:=DateTime.fromIso(s,false); if (dt == null) return false
    return lower ? at >= dt : at < dt
  }

  Bool working(DateTime at, Bool hours, Obj? overrideHours := null)
  {
    if (hours) return EnerCubixMath.containsNum(overrideHours ?: calendar?.get("workHours"),at.hour)
    if (calendar == null) return false
    day:=EnerCubixMath.containsNum(calendar["workDays"],EnerCubixMath.isoDay(at))
    EnerCubixMath.maps(calendar["exceptions"]).each |e| { if (e["date"]?.toStr == at.date.toStr) day=e["working"] == true }
    return day
  }

  [Str:Obj?]? tariff(Str:Obj? record)
  {
    id:=record["tariffId"]?.toStr
    if (id != null) return byId[id]
    category:=record["categoryId"] as Str ?: ""
    if(preparedBudget != null && defaultTariffs.containsKey(category)) return defaultTariffs[category] as Map
    defaults:=byId.vals.findAll |r| { r["kind"] == "tariff" && r["categoryId"] == record["categoryId"] && r["isDefault"] == true }
    result:=defaults.size == 1 ? defaults.first : null
    if(preparedBudget != null) {retain(2,true);defaultTariffs[category]=result}
    return result
  }

  Str unit(Str id, Str category, Str metric)
  {
    if (metric == "cost") return "元"
    if (metric == "coal") return "kgce"
    if (metric == "co2") return "kgCO2"
    if (metric == "rawcoal") return "kg raw coal"
    if (metric == "oil") return "kg oil"
    r:=byId[id]
    if (r?.get("kind") != "sensor")
    {
      canonical:=categoryUnit(category)
      if (!canonical.isEmpty) return canonical
    }
    own:=r?.get("unit")?.toStr
    if (own != null) return own
    return byPoint[r?.get("pointId")?.toStr ?: ""]?.unit ?: ""
  }

  private Str categoryUnit(Str category)
  {
    configured:=byId[category]?.get("unit")?.toStr
    if (configured != null) return configured
    first:=byId.vals.find |r| { r["categoryId"]?.toStr == category && r["kind"] != "sensor" && r["unit"] != null }
    return first?.get("unit")?.toStr ?: ""
  }
}






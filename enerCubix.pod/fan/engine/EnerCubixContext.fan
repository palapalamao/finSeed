internal class EnerCubixContext
{
  ** A separate report-only context keeps strict calculation and caches untouched.
  new known(EnerCubixContext strict, DateTime queryEnd)
  {
    tz=strict.tz; dimension=strict.dimension; comparison=strict.comparison; byId=strict.byId; byPoint=strict.byPoint
    children=strict.children; calendar=strict.calendar; strictContext=strict; knownEnd=queryEnd
    preparedBudget=strict.preparedBudget;deadline=strict.deadline
    inheritOwners(strict,false)
    retain(strict.persistentOwner == null ? 4 : 7,true);if(preparedBudget != null) tariffBaseline.ordered=true
    sharedModel=strict.sharedModel;if(sharedModel!=null) retain(1,true)
  }
  new bound(EnerCubixContext source, Str id, Str:Obj? record)
  {
    tz=source.tz; dimension=source.dimension; comparison=source.comparison; byId=source.byId.dup.set(id,record)
    byPoint=source.byPoint; children=source.children; calendar=source.calendar
    preparedBudget=source.preparedBudget;deadline=source.deadline
    inheritOwners(source,true)
    retain(4+(persistentOwner == null ? 0 : byId.size+3));if(preparedBudget != null) tariffBaseline.ordered=true
    sharedModel=source.sharedModel;if(sharedModel!=null) retain(1)
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
  internal new shared(EnerCubixCockpitCatalog catalog,Str dimension,Bool nativeSpace,EnerCubixPreparedOwner state)
  {
    if(state===catalog.owner || state.budget!==catalog.owner.budget) throw ArgErr("catalogBorrower")
    tz=catalog.tz
    state.watch |->Void| {dropPersistent};state.hold(24)
    catalog.bind(state);sharedModel=catalog
    framed=true;persistentOwner=state;preparedBudget=state.budget;deadline=state.budget.deadline;tariffBaseline.ordered=true
    this.dimension=catalog.view(dimension,nativeSpace)
    byId=catalog.byId;children=catalog.children;calendar=catalog.calendar
  }
  private EnerCubixCockpitCatalog? sharedModel
  internal EnerCubixCockpitCatalog? sharedCatalog() {sharedModel}
  TimeZone tz
  EnerCubixDimension? dimension
  EnerCubixComparisonScope? comparison
  Str:[Str:Obj?] byId := [:]
  Str:EnerCubixHistoryData byPoint := [:]
  Str:[Str:Obj?][] children := [:]
  [Str:Obj?]? calendar
  Str[] warnings := [,]
  private Str:EnerCubixValue cache := [:]
  private [Str:EnerCubixOwnFrameValue]? ownFrameValues
  private DateTime? ownFrameFrom
  private DateTime? ownFrameTo
  private Str? ownFrameCategory
  private Str? ownFrameMetric
  private Int ownFrameSlots := 0
  private Bool ownMemoDisabled := false
  private Str:EnerCubixValue tariffBaseline := [:]
  private Str:Obj? defaultTariffs := [:]
  private Str:EnerCubixTariffCursor tariffCursors := [:]
  private Str:[Str:Obj?] dimensionPlans := [:]
  private EnerCubixContext? strictContext
  private DateTime? knownEnd
  ** In owned frames this is a borrowed cache view: consume rows before another
  ** node evaluation can replace them. Retained evidence needs its output owner.
  Str:[Str:Obj?] knownReads := [:]
  Str:[Str:Obj?] usedTariffs := [:]
  private Int knownDetailCount := 0
  private Str:Int knownCharges := [:]
  private Int knownScratch := 0
  EnerCubixPreparedBudget? preparedBudget
  EnerCubixCockpitDeadline? deadline
  private Int nodeCalls := 0
  private Bool omittedEmptyEvidence := false
  private Bool omittedUnpreparedEvidence := false
  internal Bool emptyEvidenceOmitted() {omittedEmptyEvidence}
  internal Bool unpreparedEvidenceOmitted() {omittedUnpreparedEvidence}
  private EnerCubixPreparedOwner? persistentOwner
  private EnerCubixPreparedOwner? frameOwner
  private Bool framed := false
  private Bool transientContext := false
  private Bool frameConstantEmpty := false
  private Bool? tariffConfigured
  private [Str:Int[]]? warningRanks
  private [Str:Bool]? warningSeen
  private Int warningPhase := 0
  private Int warningLine := 0
  private Int warningTime := 0
  private Int warningSequence := 0

  internal Bool ownedCatalog(EnerCubixPreparedBudget budget)
  {framed && persistentOwner != null && preparedBudget === budget}

  internal Void useOwner(EnerCubixPreparedOwner owner)
  {
    if(framed || preparedBudget != null || !byPoint.isEmpty) throw ArgErr("preparedContextAlreadyInitialized")
    framed=true
    index:=1+byId.size+children.size
    children.each |rows| {index+=rows.size}
    owner.watch |->Void| {dropPersistent};owner.hold(index+3)
    persistentOwner=owner;preparedBudget=owner.budget;deadline=owner.budget.deadline;tariffBaseline.ordered=true
  }
  internal Void beginFrame(EnerCubixPreparedOwner owner,Str:EnerCubixHistoryData histories,Bool constantEmpty := false,Bool singlePassOwn := false)
  {
    if(persistentOwner == null || frameOwner != null || owner === persistentOwner || owner.budget !== preparedBudget) throw ArgErr("preparedContextOwner")
    indexReadOnly:=histories.isRO;borrowedIndex:=false
    histories.each |h,id|
    {
      if(h.id != id || !h.ownedFrame(owner.budget)) throw ArgErr("preparedContextSourceFrame")
      if(indexReadOnly && !borrowedIndex && h.ownsSourceIndex(histories,owner.budget)) borrowedIndex=true
    }
    if(strictContext != null)
    {
      if(strictContext.frameOwner !== owner || histories.size != strictContext.byPoint.size || (histories!==strictContext.byPoint && histories.any |h,id| {h !== strictContext.byPoint[id]})) throw ArgErr("preparedContextStrictFrame")
    }
    if(singlePassOwn) owner.hold(1)
    owner.watch |->Void| {dropFrame}
    // Every entry above still passes the original identity and lease checks.
    // An attested producer index cannot change its keys/values, so only its
    // borrowed reference is ours. Unattested/legacy maps keep an owned copy.
    if(strictContext == null) {owner.hold(borrowedIndex ? 1 : 1+histories.size);byPoint=borrowedIndex ? histories : histories.dup}
    else byPoint=strictContext.byPoint
    frameOwner=owner;frameConstantEmpty=constantEmpty;ownMemoDisabled=singlePassOwn
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
    cache.clear;knownReads.clear;knownCharges.clear;knownScratch=0;byPoint=Str:EnerCubixHistoryData[:]
    ownFrameValues?.clear;ownFrameValues=null;ownFrameFrom=null;ownFrameTo=null
    ownFrameCategory=null;ownFrameMetric=null;ownFrameSlots=0;ownMemoDisabled=false
    knownDetailCount=0;omittedEmptyEvidence=false;omittedUnpreparedEvidence=false;frameOwner=null;frameConstantEmpty=false
    if(transientContext)
    {
      tariffBaseline.clear;defaultTariffs.clear;dimensionPlans.clear;usedTariffs.clear;clearWarnings
      byId=Str:[Str:Obj?][:];children=Str:[Str:Obj?][][:];calendar=null;strictContext=null;persistentOwner=null
      if(sharedModel!=null) {dimension=null;sharedModel=null}
    }
  }
  private Void dropPersistent()
  {
    if(frameOwner != null) throw ArgErr("preparedFrameActive")
    dropFrame;ownMemoDisabled=false;tariffBaseline.clear;tariffCursors.clear;defaultTariffs.clear;dimensionPlans.clear;usedTariffs.clear;clearWarnings
    byId=Str:[Str:Obj?][:];children=Str:[Str:Obj?][][:];calendar=null;strictContext=null;persistentOwner=null
    if(sharedModel!=null) {dimension=null;sharedModel=null}
  }

  internal Void bindTariffCursor(Str id,EnerCubixTariffCursor cursor,EnerCubixPreparedOwner owner)
  {
    if(owner !== persistentOwner || strictContext != null || transientContext || tariffCursors.containsKey(id)) throw ArgErr("tariffCursorContext")
    retain(2,true);tariffCursors[id]=cursor
  }

  internal EnerCubixValue ownRaw(Str:Obj? record,DateTime from,DateTime to,Str[] path)
  {rawNode(record,from,to,path)}

  ** Empty prepared lookups do not become a second dense cache. They have zero
  ** coverage and no source intervals; authoritative per-object coverage remains.
  Str:Obj? knownEvidence(Bool includeDetails := true)
  {
    frameCheck
    if(framed) throw ArgErr("preparedEvidenceNeedsOutputOwner")
    reads:=EnerCubixKnownUsage.evidence(knownReads.vals)
    out:=Str:Obj?["basis":"closedSourceIntervals","sourceUsage":reads]
    if(includeDetails || omittedEmptyEvidence || omittedUnpreparedEvidence) out["detailsTruncated"]=omittedEmptyEvidence || omittedUnpreparedEvidence || reads.any |r| {r["detailsTruncated"] == true}
    if(omittedEmptyEvidence || omittedUnpreparedEvidence) out.setAll(["sourceUsageCaptureId":Uuid().toStr,"sourceUsageTruncated":true,"sourceUsageRowCount":null,"truncationReason":"cockpitBoundedPreparedEvidence","omittedConfirmedEmpty":omittedEmptyEvidence,"omittedUnprepared":omittedUnpreparedEvidence])
    return out
  }
  Void mergeKnown(EnerCubixContext other)
  {
    frameCheck;other.frameCheck
    if((framed || other.framed) && (frameOwner !== other.frameOwner || preparedBudget !== other.preparedBudget)) throw ArgErr("knownMergeOwner")
    omittedEmptyEvidence=omittedEmptyEvidence || other.omittedEmptyEvidence
    omittedUnpreparedEvidence=omittedUnpreparedEvidence || other.omittedUnpreparedEvidence
    other.knownReads.each |v,k| {if(!knownReads.containsKey(k)) retain(1);knownReads[k]=v}
  }

  private EnerCubixValue sumValues(EnerCubixValue[] values)
  { strictContext == null ? EnerCubixValue.sum(values) : EnerCubixKnownUsage.combine(values) }

  Void warn(Str message)
  {
    if(warningRanks != null)
    {
      previous:=warningRanks[message]
      if(previous == null)
      {retain(7,true);warningRanks[message]=[warningPhase,warningLine,warningTime,warningSequence];warnings.add(message)}
      else if(warningBefore(previous))
      {previous[0]=warningPhase;previous[1]=warningLine;previous[2]=warningTime;previous[3]=warningSequence}
      warningSequence++
      return
    }
    // Owned known-value contexts keep the same first-occurrence list without
    // scanning all prior messages on every physical meter/hour visit. Admit
    // this index before allocating or publishing a new warning.
    if(persistentOwner != null)
    {
      if(warningSeen == null)
      {retain(3+warnings.size,true);warningSeen=Str:Bool[:];warnings.each |existing| {warningSeen[existing]=true}}
      if(warningSeen.containsKey(message)) return
      retain(2,true);warningSeen[message]=true;warnings.add(message);return
    }
    if(!warnings.contains(message)) {if(persistentOwner != null) retain(1,true);warnings.add(message)}
  }
  private Void warnValue(Str:Obj? record,Str id,Str quality)
  {label:=(record["name"] ?: id).toStr;warn(sharedModel?.warningText(label,quality,false,7) ?: "$label : $quality")}
  internal Void warnLine(Str label,Str quality)
  {warn(sharedModel?.warningText(label,quality,true,7) ?: "$label: $quality")}

  internal Void orderWarnings()
  {
    if(persistentOwner == null || frameOwner != null || warningRanks != null) throw ArgErr("warningOrderContext")
    retain(5,true);warningRanks=Str:Int[][:]
    warnings.each |message,i| {retain(6,true);warningRanks[message]=[-1,i,0,0]}
  }
  internal Void warningScope(Int phase,Int line,Int time)
  {
    if(warningRanks == null || persistentOwner == null) throw ArgErr("warningOrderContext")
    warningPhase=phase;warningLine=line;warningTime=time;warningSequence=0
  }
  internal Str[] orderedWarnings()
  {
    if(warningRanks == null) return warnings
    return warnings.sort |a,b->Int|
    {
      x:=warningRanks[a];y:=warningRanks[b]
      for(i:=0;i<4;i++) {c:=x[i]<=>y[i];if(c!=0) return c}
      return 0
    }
  }
  private Bool warningBefore(Int[] previous)
  {
    if(warningPhase != previous[0]) return warningPhase<previous[0]
    if(warningLine != previous[1]) return warningLine<previous[1]
    if(warningTime != previous[2]) return warningTime<previous[2]
    return warningSequence<previous[3]
  }
  private Void clearWarnings() {warnings.clear;warningRanks?.clear;warningRanks=null;warningSeen?.clear;warningSeen=null}

  ** Each active frame keeps one maximum charge per header slot and one reusable
  ** copy workspace. Duplicate visits still replace evidence in the original
  ** order; they do not accumulate charges for maps no longer retained.
  private Void knownWorkspace(Int entries)
  {
    if(frameOwner == null || entries<=knownScratch) return
    frameOwner.hold(entries-knownScratch);knownScratch=entries
  }
  private Void knownHeader(Str key,Int entries)
  {
    if(frameOwner == null) return
    previous:=knownCharges[key]
    if(previous==null) {frameOwner.hold(1+entries);knownCharges[key]=entries}
    else if(entries>previous) {frameOwner.hold(entries-previous);knownCharges[key]=entries}
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

  EnerCubixValue node(Str id, Str category, DateTime from, DateTime to, Str metric := "energy", Str[] path := Str#.emptyList, Str? utility := null, Bool useMaster := true)
  {
    frameCheck
    if(++nodeCalls % 128 == 0) deadline?.check
    if (path.contains(id)) return EnerCubixValue(null,"cycle")
    key := preparedBudget == null ? "$id|$category|${from.ticks}|${to.ticks}|$metric|$utility|$useMaster" : ""
    if (preparedBudget == null && path.isEmpty && cache.containsKey(key)) return cache[key]
    r := byId[id]
    if (r == null) return EnerCubixValue(null,"unknownNode")
    if(frameOwner!=null && comparison==null && utility==null && metric!="cost" && sharedModel!=null && byId===sharedModel.byId)
    {
      // The exact group is only inspected here, never reset or allocated.
      // A stored proof came after all original validation of this immutable
      // canonical record. Replacing the byId entry forces the original path.
      prior:=peekOwnFrameValue(id,category,from,to,metric)
      if(prior!=null && prior.record===r)
      {
        if(prior.repeatWarning && prior.value.value==null) warnValue(r,id,prior.value.quality)
        return prior.value
      }
    }
    if (comparison != null && (r["_comparisonReadable"] == false || r["_comparisonPointReadable"] == false)) return EnerCubixValue(null,"forbidden")
    if (r["configurationError"] != null)
    {
      warn(r["name"].toStr+"："+r["configurationError"])
      return EnerCubixValue(null,"invalidConfiguration")
    }
    own:=frameOwner!=null && utility==null && metric!="cost" && (r["kind"]=="meter" || r["kind"]=="totalMeter")
    if(own)
    {
      cached:=ownFrameValue(id,category,from,to,metric)
      if(cached!=null)
      {
        if(cached.repeatWarning && cached.value.value==null) warnValue(r,id,cached.value.quality)
        return cached.value
      }
    }
    EnerCubixHistoryData? ownSource
    if(own && sharedModel!=null && byId===sharedModel.byId && r["nativeSourceMissing"]!=true)
      ownSource=byPoint[r["pointId"] as Str ?: ""]
    sharedStrict:=strictContext==null ? ownSource?.ownStrict(r,category,from,to,metric) : null
    if(sharedStrict!=null)
    {
      saveOwnFrameValue(id,category,from,to,metric,sharedStrict.value,false,r)
      return sharedStrict.value
    }
    queryEnd:=strictContext==null ? null : knownEnd
    // An admitted exact empty result already carries the original domain key.
    // Frozen records can borrow that text; mutable/bound/other ranges retain
    // their original domain calculation. Consumer cache still wins below.
    borrowEmptyKey:=ownSource!=null && r.isImmutable && emptyCacheQualities.contains(ownSource.quality)
    sharedEmpty:=borrowEmptyKey ? ownSource.ownEmpty(r,category,from,to,metric,queryEnd) : null
    stable:=sharedEmpty?.stableKey ?: emptyKey(r,category,from,to,metric)
    if(stable!=null && frameOwner!=null && metric=="cost") stable+="|${from.ticks}|${to.ticks}"
    if(stable != null && cache.containsKey(stable))
    {
      preparedBudget.contextEmptyHits.increment;value:=cache[stable]
      if(own) saveOwnFrameValue(id,category,from,to,metric,value,false,r)
      return value
    }
    // Consumer domain reuse takes precedence over source exact-pair reuse:
    // another partial pair must not repeat or reorder an existing warning.
    if(!borrowEmptyKey) sharedEmpty=stable==null ? null : ownSource?.ownEmpty(r,category,from,to,metric,queryEnd)
    if(stable==null) sharedEmpty=null
    if(sharedEmpty!=null)
    {
      if(strictContext!=null) omittedEmptyEvidence=true
      retain(2);cache[stable]=sharedEmpty.value
      warnValue(r,id,sharedEmpty.value.quality)
      saveOwnFrameValue(id,category,from,to,metric,sharedEmpty.value,false,r)
      return sharedEmpty.value
    }
    // A device always reads its own primary history. Reuse that exact result
    // within this borrowed frame, including recursive scope/detail visits.
    // Pricing retains its independent tariff/baseline execution path.
    Str? ownKey
    if(frameConstantEmpty && timeInvariantEmpty(metric))
    {
      if(!own && path.isEmpty) ownKey="emptyScope|$id|$category|$metric|$utility|$useMaster"
    }
    if(ownKey!=null && cache.containsKey(ownKey))
    {
      cached:=cache[ownKey]
      if(cached.value==null) warnValue(r,id,cached.quality)
      return cached
    }
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
    if (result.value == null) warnValue(r,id,result.quality)
    if(strictContext==null) ownSource?.rememberOwnStrict(r,category,from,to,metric,result)
    if (path.isEmpty && preparedBudget == null) cache[key]=result
    sharedEmpty=stable==null ? null : ownSource?.rememberOwnEmpty(r,category,from,to,metric,queryEnd,result,stable)
    if(sharedEmpty!=null)
    {
      if(!cache.containsKey(stable)) retain(2);cache[stable]=result
      saveOwnFrameValue(id,category,from,to,metric,result,false,r)
      return result
    }
    if(stable != null && result.value == null)
    {
      if(!cache.containsKey(stable)) retain(2);cache[stable]=result
      if(own) saveOwnFrameValue(id,category,from,to,metric,result,false,r)
    }
    else if(own) saveOwnFrameValue(id,category,from,to,metric,result,true,r)
    else if(ownKey!=null) {retain(2);cache[ownKey]=result}
    return result
  }

  ** A consumer frame usually evaluates one physical hour many times. Keep its
  ** exact range/category/metric as typed fields instead of rebuilding timestamp
  ** string keys on each recursive or detail visit. A different group discards
  ** the previous values; only the high-water slot count stays admitted until
  ** this frame expires. This is never a cross-frame or cross-request cache.
  private EnerCubixOwnFrameValue? ownFrameValue(Str id,Str category,DateTime from,DateTime to,Str metric)
  {
    if(ownMemoDisabled) return null
    if(ownFrameValues==null) {retain(7);ownFrameValues=Str:EnerCubixOwnFrameValue[:]}
    if(ownFrameFrom!=from || ownFrameTo!=to || ownFrameCategory!=category || ownFrameMetric!=metric)
    {ownFrameValues.clear;ownFrameFrom=from;ownFrameTo=to;ownFrameCategory=category;ownFrameMetric=metric}
    return ownFrameValues[id]
  }
  private EnerCubixOwnFrameValue? peekOwnFrameValue(Str id,Str category,DateTime from,DateTime to,Str metric)
  {
    if(ownMemoDisabled || ownFrameValues==null || ownFrameFrom!=from || ownFrameTo!=to || ownFrameCategory!=category || ownFrameMetric!=metric) return null
    return ownFrameValues[id]
  }
  private Void saveOwnFrameValue(Str id,Str category,DateTime from,DateTime to,Str metric,EnerCubixValue value,Bool repeatWarning,Map? record := null)
  {
    if(ownMemoDisabled) return
    // A recursive evaluation may have used another range/category/metric.
    // Restore this result's exact group before publishing its reusable slot.
    previous:=ownFrameValue(id,category,from,to,metric)
    proof:=record!=null && record.isImmutable && comparison==null && sharedModel!=null && byId===sharedModel.byId ? record : null
    if(previous!=null) {previous.record=proof;previous.value=value;previous.repeatWarning=repeatWarning;return}
    if(ownFrameValues.size>=ownFrameSlots) {retain(6);ownFrameSlots++}
    ownFrameValues[id]=EnerCubixOwnFrameValue(value,repeatWarning,proof)
  }

  private Str? emptyKey(Str:Obj? r,Str category,DateTime from,DateTime to,Str metric)
  {
    if(preparedBudget == null || (r["kind"]!="meter" && r["kind"]!="totalMeter")) return null
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
    if(!emptyCacheQualities.contains(h.quality)) return null
    domain:=h.emptyDomain(from,to,knownEnd)
    if(domain == null && !h.unpreparedPair(from,to,knownEnd)) return null
    return "constant|"+r["id"]+"|"+category+"|"+metric+"|"+(domain?.toStr ?: "notPrepared")
  }

  internal Bool timeInvariantEmpty(Str metric)
  {
    if(metric!="cost") return true
    // Missing tariff configuration is a frozen fact. Any configured tariff,
    // even an unused one, keeps pricing on its original hourly path.
    if(tariffConfigured==null) tariffConfigured=byId.any |record| {record["kind"]=="tariff"}
    return !tariffConfigured
  }

  DateTime? constantEnd(Str id,Str category,DateTime from,DateTime to,Str metric)
  {
    frameCheck
    r:=byId[id]
    if(r == null || preparedBudget == null || (r["kind"]!="meter" && r["kind"]!="totalMeter")) return null
    mode:=metric == "cost" ? tariff(r)?.get("mode") : null
    if(mode == "monthlyBlock" || mode == "yearlyBlock") return null
    h:=byPoint[r["pointId"] as Str ?: ""]
    return h == null ? to : h.constantEnd(from,to,knownEnd)
  }

  EnerCubixValue nodeTotal(Str id, DateTime from, DateTime to, Str[] path := Str#.emptyList)
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
    EnerCubixValue? raw
    durationFactor:=r["kind"] == "sensor" ? 1f : (to-from).ticks.toFloat/1hr.ticks.toFloat
    point := r["pointId"]?.toStr ?: ""
      his := byPoint[point]
      if (his == null) return EnerCubixValue(null,"missing",point.isEmpty ? Str[,] : [point])
      if (!readableQualities.contains(his.quality)) return EnerCubixValue(null,his.quality,[point])
      if (r["kind"] != "sensor" && his.mode != "interval" && his.mode != "cumulative") return EnerCubixValue(null,"notEnergyHistory",[point])
      if (strictContext == null) raw=his.read(from,to)
      else
      {
        // Another canonical consumer may already have admitted this exact
        // source/hour/cutoff header. Read its scalar facts before constructing
        // another known-usage map. Trimmed, bound and other-cutoff reads retain
        // the original path below. The source owner outlives this consumer.
        sharedSlot:=frameOwner!=null && sharedModel!=null && byId===sharedModel.byId && r.isImmutable ? his.knownEvidenceSlot(r,from,to,knownEnd) : null
        shared:=sharedSlot?.evidence
        sharedDetails:=shared?.get("intervals") as [Str:Obj?][]
        if(sharedDetails!=null && sharedDetails.size<=1000-knownDetailCount)
        {
          // Preserve every prepared lookup and its deadline cadence. Values
          // remain fresh; only the already-owned evidence header is borrowed.
          preparedBudget.lookup
          knownWorkspace(6)
          key:=sharedSlot.key
          if(key==null) {recordId:=r["id"].toStr;key="$recordId|$point|${from.ticks}|${to.ticks}"}
          knownHeader(key,2)
          raw=EnerCubixValue(EnerCubixMath.num(shared["knownValue"]),shared["knownQuality"].toStr,his.sources)
          durationFactor=(EnerCubixMath.num(shared["coveredSeconds"]) ?: 0f)/3600f
          knownDetailCount+=sharedDetails.size;knownReads[key]=shared
        }
        else
        {
        data:=frameOwner==null ? his.knownUsage(from,to,knownEnd) : his.borrowedKnownUsage(from,to,knownEnd); raw=(EnerCubixValue)data["value"]
        durationFactor=(EnerCubixMath.num(data["coveredSeconds"]) ?: 0f)/3600f
        // This is the source's already-proven empty domain. Reading it adds no
        // intervals or diagnostic header, so do not allocate filtered/mapped
        // empty lists or copy its map for each report/meter/hour visit.
        if(his.isBorrowedEmptyKnown(data)) omittedEmptyEvidence=true
        else
        {
        detailBound:=(data["intervals"] as List)?.size ?: 0
        // maps() may simultaneously hold its filtered and mapped reference lists.
        knownWorkspace(2+2*detailBound)
        // Prepared/native readers already return this typed map list. Borrow
        // it read-only; retain the filter path for other legacy input shapes.
        details:=data["intervals"] as [Str:Obj?][] ?: EnerCubixMath.maps(data["intervals"])
        empty:=preparedBudget != null && data["knownValue"] == null && data["knownQuality"] == "missing" && data["coveredSeconds"] == 0f && data["intervalCount"] == 0 && data["intervalStart"] == null && data["intervalEnd"] == null && details.isEmpty
        unprepared:=preparedBudget != null && raw.quality == "streamingReadNotPrepared" && data.size == 1
        if(empty) omittedEmptyEvidence=true
        else if(unprepared) omittedUnpreparedEvidence=true
        else
        {
          remaining:=1000-knownDetailCount
          recordId:=r["id"].toStr
          key:="$recordId|$point|${from.ticks}|${to.ticks}"
          trim:=details.size>remaining ? 1+remaining : 0
          header:=2+data.size+8+trim
          // Header fields, six source/boundary fields, possible trim flags/list,
          // and the slot index are admitted before copying the borrowed map.
          // The first details list remains live while the counter's maps()
          // creates its own filtered+mapped lists (at most three lists total).
          share:=frameOwner!=null && sharedModel!=null && byId===sharedModel.byId && r.isImmutable && details.size<=remaining
          evidence:=share ? his.knownEvidence(r,from,to,knownEnd) : null
          // A source-cache hit already has a complete map admitted under the
          // enclosing source owner. Retain this consumer's slot/key links only;
          // misses and trimmed replacements still admit their whole map. The
          // slot's high-water charge upgrades before any replacement is copied.
          knownWorkspace(header+3+3*detailBound);knownHeader(key,evidence==null ? header : 2)
          if(evidence==null)
          {
            evidence=data.dup; evidence.remove("value")
            if (details.size > remaining)
            {
              evidence["intervals"]=remaining == 0 ? [Str:Obj?][,] : details[0..<remaining]
              evidence["detailsTruncated"]=true
              evidence["intervalsCaptureId"]=Uuid().toStr
            }
            bounds:=his.exactBounds(from,to)
            evidence.setAll(["nodeId":r["id"],"pointId":point,"sourceIds":his.sources,"unit":his.unit,"from":bounds?.fromIso ?: from.toIso,"to":bounds?.toIso ?: to.toIso])
            if(share) his.rememberKnownEvidence(r,from,to,knownEnd,evidence,key)
          }
          knownDetailCount+=details.size.min(remaining)
          if(frameOwner == null && !knownReads.containsKey(key)) retain(2)
          knownReads[key]=evidence
        }
        }
        }
      }
    max := EnerCubixMath.num(r["maximum"])
    if (raw.value != null && max != null && raw.value > max*durationFactor) return EnerCubixValue(null,"maximum",raw.sources)
    if (r["kind"] != "sensor")
    {
      sourceUnit:=his.unit
      if (sourceUnit.isEmpty) sourceUnit=r["unit"]?.toStr ?: ""
      targetUnit:=categoryUnit(r["categoryId"]?.toStr ?: "")
      factor:=EnerCubixMath.unitFactor(sourceUnit,targetUnit)
      if (factor == null) return EnerCubixValue(null,"incompatibleUnit",raw.sources)
      raw=raw.scale(factor)
    }
    return raw
  }

  private static const Str[] emptyCacheQualities := ["ok","cleaned","estimated","derived","corrected"]
  private static const Str[] readableQualities := ["ok","estimated","derived","cleaned","corrected","filtered","substituted","na"]

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
      rolling:=tariffCursors[meterId]
      baseline:=rolling == null ? tariffBaseline[baselineKey] : rolling.baseline(from,to,path)
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
      if(rolling == null && from == EnerCubixMath.floorHour(from) && to == from+1hr)
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
    point:=r?.get("pointId")?.toStr ?: ""
    return byPoint[point]?.unit ?: (sharedModel?.primaryUnit(point) ?: "")
  }

  private Str categoryUnit(Str category)
  {
    configured:=byId[category]?.get("unit")?.toStr
    if (configured != null) return configured
    first:=byId.vals.find |r| { r["categoryId"]?.toStr == category && r["kind"] != "sensor" && r["unit"] != null }
    return first?.get("unit")?.toStr ?: ""
  }
}

** One admitted physical-result slot in the current consumer frame.
internal class EnerCubixOwnFrameValue
{
  new make(EnerCubixValue value,Bool repeatWarning,Map? record := null) {this.value=value;this.repeatWarning=repeatWarning;this.record=record}
  EnerCubixValue value
  Bool repeatWarning
  Map? record
}






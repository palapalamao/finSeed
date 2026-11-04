using haystack

** Private source-clock integration. Caller-frozen configuration is borrowed;
** this session owns its indices, source cursors, reports and detached headers.
** Native entry points remain unchanged until the complete request is admitted.
internal class EnerCubixCockpitSourceSession
{
  ** Reuse the native point/configuration freeze and final revision guards.
  ** No history callback is invoked until the returned session is loaded.
  static EnerCubixCockpitSourceSession prepare(Str:Obj? request,[Str:Obj?][] records,EnerCubixStreamBudget budget,
    |Str->Dict?| lookup,|Dict->Bool| readable,|Dict->Dict| cleaning,|Dict,Span,|HisItem|->Void| read,EnerCubixCockpitRequestScope? scope := null,|Dict,EnerCubixPreparedOwner->Dict|? ownedCleaning := null)
  {
    budget.check;checkDeadline(request,budget)
    if(scope==null)
    {
      prepared:=EnerCubixHistory.prepareConfiguration(request,records,lookup,readable,cleaning)
      budget.check
      return EnerCubixCockpitSourceSession(request,records,prepared.toImmutable,budget,read)
    }
    if(scope.stream!==budget) throw ArgErr("cockpitSourceSessionScope")
    if(ownedCleaning==null) throw ArgErr("cockpitOwnedCleaningRequired")
    output:=scope.configurationOutput;work:=EnerCubixPreparedOwner(budget.state);Map? prepared
    try
    {
      prepared=EnerCubixHistory.prepareConfiguration(request,records,lookup,readable,|Dict p->Dict| {ownedCleaning(p,work)},work)
      ((Map)prepared["configs"]).each |Dict config| {output.hold(1+EnerCubixHistory.configurationSize(config))}
      frozen:=(Str:Obj?)EnerCubixCockpitFreeze.value(prepared,output)
      budget.check
      return EnerCubixCockpitSourceSession(request,records,frozen,budget,read,scope)
    }
    finally {prepared?.clear;work.close}
  }
  new make(Str:Obj? request,[Str:Obj?][] records,Str:Obj? prepared,EnerCubixStreamBudget budget,|Dict,Span,|HisItem|->Void| read,EnerCubixCockpitRequestScope? requestScope := null)
  {
    this.budget=budget;owner=EnerCubixPreparedOwner(budget.state)
    try
    {
      checkDeadline(request,budget)
      if(requestScope!=null && requestScope.stream!==budget) throw ArgErr("cockpitSourceSessionScope")
      this.requestScope=requestScope
      if(!request.isImmutable || !records.isImmutable || !prepared.isImmutable || request["_cockpitConsumers"] isnot Map || prepared["points"] isnot Map || prepared["configs"] isnot Map || prepared["configRefs"] isnot Map) throw ArgErr("cockpitSourceSessionPlan")
      owner.hold(48);this.request=request;this.records=records;this.prepared=prepared;reader=read
      owner.watch |->Void|
      {
        headers.each |h| {if(!h.isImmutable) {(h["sourceIds"] as List)?.clear;(h["_cockpitRequestMeta"] as Map)?.clear;h.clear}};headers.clear
        if(!stats.isImmutable) stats.clear;windows.each |w| {w.unavailable?.clear;w.cleaning?.clear};detached.each |v| {if(v is Map) ((Map)v).clear;else ((List)v).clear};detached.clear;windows.clear;this.request=null;this.records=null;this.prepared=null;reader=null;this.requestScope=null
      }
      plan:=(Map)request["_cockpitConsumers"];q:=(Str:Obj?)plan["request"];tz:=TimeZone(q["tz"].toStr)
      clockFrom=EnerCubixMath.floorHour(DateTime.fromIso(q["from"].toStr).toTimeZone(tz));clockTo=ceiling(DateTime.fromIso(q["to"].toStr).toTimeZone(tz))
      scratch:=EnerCubixPreparedOwner(budget.state)
      units:=Str:Str[:]
      cleaningPlan:=Str:[Str:Obj?][:]
      List? ranges;List? normalized
      scratch.watch |->Void| {cleaningPlan.each |entry| {(entry["sourceIds"] as List)?.clear;(entry["requestRange"] as Map)?.clear;entry.clear};cleaningPlan.clear;normalized?.each |Map r| {((List)r["pointIds"]).clear;r.clear};normalized?.clear;ranges?.each |Map r| {r.clear};ranges?.clear;units.clear}
      try
      {
        List raw:=(request["_cockpitRanges"] as List) ?: Obj?[,]
        refs:=0;raw.each |Map r| {refs+=((List)r["pointIds"]).size}
        scratch.hold(32+64*(raw.size+refs+1));budget.originalWindows=refs
        ranges=raw.map |Map r->Str:Obj?| {["from":EnerCubixMath.floorHour(DateTime.fromIso(r["from"].toStr).toTimeZone(tz)).toIso,"to":ceiling(DateTime.fromIso(r["to"].toStr).toTimeZone(tz)).toIso,"pointIds":r["pointIds"]]}
        normalized=EnerCubixCockpitStream.normalizeRanges(ranges)
        normalized.each |Map r|
        {
          a:=DateTime.fromIso(r["from"].toStr).toTimeZone(tz);b:=DateTime.fromIso(r["to"].toStr).toTimeZone(tz)
          EnerCubixMath.strings(r["pointIds"]).each |id|
          {
            point:=((Map)prepared["points"])[id] as Dict
            owner.hold(12);window:=EnerCubixCockpitSourceWindow(id,a,b,point,((Map)prepared["configs"])[id] as Dict);windows.add(window)
            if(point==null || !point.has("his") || !EnerCubixHistory.primaryReadAllowed(point,records)) {owner.hold(4);window.unavailable=["pointId":id,"quality":"missing","mode":"cumulative"]}
            else if(point["unit"] is Str) units[id]=point["unit"].toStr
            if(window.unavailable==null && window.isCleaning)
            {
              key:=EnerCubixCockpitStream.diagnosticKey(id,a,b)
              cleaningPlan[key]=["kind":"cleaningEvents","grain":"cleaningEvent","objectIds":q["nodeIds"],"sourceIds":[id],"sourceIdsComplete":true,"requestRange":["from":a.toIso,"to":b.toIso,"asOf":q["asOf"]]]
            }
            if(a<clockFrom) clockFrom=a;if(b>clockTo) clockTo=b
          }
        }
        budget.normalizedWindows=windows.size
        expectHistoricalCoverage(q)
        enabled:=EnerCubixMath.strings(plan["enabled"]);comparison:=(Map)plan["comparison"]
        if(enabled.contains("kpis") && comparison["mode"]!="none")
        {
          ref:=(Map)comparison["referenceRange"];a:=EnerCubixMath.floorHour(DateTime.fromIso(ref["from"].toStr).toTimeZone(tz));b:=ceiling(DateTime.fromIso(ref["to"].toStr).toTimeZone(tz))
          if(a<clockFrom) clockFrom=a;if(b>clockTo) clockTo=b
        }
        registry=EnerCubixCockpitRegistry(q,records,(Str:Obj?)plan["boundary"],enabled,(Str:Obj?)comparison,plan["auxiliary"] as Str,(Str:Obj?)plan["owned"],budget,units,((Map)prepared["points"]).keys,cleaningPlan,(Str:Obj?)plan["flow"],(Str:Obj?)plan["efficiency"],requestScope?.sourceCatalog(records,tz,units))
      }
      finally {scratch.close}
    }
    catch(Err e) {close;throw e}
  }
  private EnerCubixStreamBudget budget
  private EnerCubixPreparedOwner owner
  private [Str:Obj?]? request
  private [Str:Obj?][]? records
  private [Str:Obj?]? prepared
  private |Dict,Span,|HisItem|->Void|? reader
  private EnerCubixCockpitRequestScope? requestScope
  private EnerCubixCockpitRegistry? registry
  private EnerCubixCockpitSourceWindow[] windows := [,]
  private [Str:Obj?][] headers := [,]
  private Str:Obj? stats := [:]
  private Obj[] detached := [,]
  private DateTime clockFrom := DateTime.defVal
  private DateTime clockTo := DateTime.defVal
  private Bool started := false
  private Int emptyGroups := 0
  private Bool done := false
  private Bool closed := false
  private Err? failure
  private static DateTime ceiling(DateTime at) {hour:=EnerCubixMath.floorHour(at);return hour<at ? hour+1hr : hour}
  private static Void checkDeadline(Str:Obj? request,EnerCubixStreamBudget budget)
  {if(request["_cockpitDeadline"]!=null && request["_cockpitDeadline"]!==budget.state.deadline) throw ArgErr("cockpitSourceSessionDeadline")}
  private Void expectHistoricalCoverage(Str:Obj? q)
  {
    from:=DateTime.fromIso(q["from"].toStr);to:=DateTime.fromIso(q["to"].toStr);cutoff:=DateTime.fromIso(q["asOf"].toStr)
    if(to>cutoff) to=cutoff
    if(to<=from) return
    left:=EnerCubixMath.floorHour(from);right:=ceiling(to)
    EnerCubixMath.strings(request["_cockpitPointIds"]).each |id|
    {budget.check;if(!windows.any |w| {w.id==id && w.from<=left && w.to>=right}) throw ArgErr("cockpitSourceSessionHistoricalPlan")}
  }

  [Str:Obj?][] load(Bool groupEmpty := true)
  {
    check;if(started) throw ArgErr("cockpitSourceSessionAlreadyRead");started=true
    try
    {
      registry.prepareMetadata
      windows.each |w|
      {
        if(w.unavailable!=null) return
        try {w.cursor=EnerCubixCockpitStream.openCursor(w.point,w.config,w.from,w.to,request,records,budget,|Dict point,Span span,|HisItem| sink| {nativeRead(point,span,sink)},registry.planning)}
        catch(ArgErr e)
        {
          if(!["missingCleaningProfile","Conflicting EnerCubix history modes","streamingEnergyModeRequired"].contains(e.msg)) throw e
          owner.hold(5);w.unavailable=["pointId":w.id,"quality":"streamingUnsupportedConfiguration","mode":"cumulative","limitation":e.msg]
          if(w.isCleaning) registry.omitCleaning(w.id,w.from,w.to)
        }
      }
      at:=clockFrom
      while(at<clockTo)
      {
        budget.check;next:=at+1hr;scratch:=EnerCubixPreparedOwner(budget.state)
        try
        {
          scratch.hold(8+3*windows.size)
          active:=windows.findAll |w| {at>=w.from && next<=w.to}
          streams:=active.findAll |w| {w.cursor!=null}.map |w->EnerCubixCockpitStream| {w.cursor}
          try
          {
            active.each |w| {w.cursor?.advance(next)}
            if(groupEmpty && registry.canGroupEmpty)
            {
              through:=at+24hr;if(through>clockTo) through=clockTo
              windows.each |w| {if(w.from>at && w.from<through) through=w.from}
              active.each |w|
              {
                end:=w.unavailable!=null ? w.to : (w.cursor?.confirmedEmptyThrough ?: next)
                if(end<through) through=end;if(w.to<through) through=w.to
              }
              if(through>next) {emptyGroups++;next=through;active.each |w| {w.cursor?.advance(next)}}
            }
            EnerCubixCockpitStream.withFrames(streams,budget.state) |h,frame|
            {
              missing:=0;active.each |w| {if(w.unavailable!=null) missing++}
              frame.hold(8+64*missing);unavailableFrame:=EnerCubixPreparedFrame()
              try
              {
                active.each |w| {if(w.unavailable!=null) h[w.id]=EnerCubixHistoryData(w.unavailable.dup.set("_preparedBudget",budget.state).set("_preparedFrame",unavailableFrame))}
                if(next>at+1hr) registry.addEmptyFrames(at,next,h,frame)
                else registry.addFrame(at,next,h,frame)
              }
              finally {unavailableFrame.expire}
            }
          }
          finally {streams.clear;active.clear}
        }
        finally {scratch.close}
        at=next
      }
      registry.finish
      windows.each |w|
      {
        if(w.cursor!=null && w.isCleaning) w.cursor.withCleaningMetadata |meta|
        {
          registry.cleaning(w.id,w.from,w.to,meta)
          owner.hold(8);w.cleaning=Str:Obj?["profileId":meta["profileId"],"profileVersion":meta["profileVersion"]]
          w.cleaning["parameters"]=detach(meta["parameters"])
        }
        if(w.cursor!=null) w.cursor.withHeaderMetadata |meta| {addHeader(w,meta)}
        else addHeader(w,w.unavailable)
        w.cursor?.close;w.cursor=null
      }
      owner.hold(48);observed:=budget.evidence;stats.setAll(observed);observed.clear
      if(requestScope!=null)
      {
        frozen:=requestScope.freezeSourceHeaders(headers,owner)
        owner.hold(1+frozen.size);headers=frozen.dup
        // All headers share this same admitted immutable statistics map. Keep
        // the request metadata alias on it instead of the consumed old map.
        if(!headers.isEmpty) stats=(Str:Obj?)headers.first["streaming"]
      }
      owner.hold(12)
      meta:=Str:Obj?["schemaVersion":1,"diagnostics":registry.diagnostics,"preparedBudget":budget.state,"streaming":stats,"publishDiagnostics":|Str:Obj? reports->Str:Obj?| {ready;return registry.publishDiagnostics(reports)}]
      if(requestScope!=null)
      {
        owner.hold(2);meta["releaseSources"]=|->Void| {close}
        meta["releasePlanning"]=|->Void| {ready;if(registry.retirePlanning) {requestScope.releaseReportBorrows;requestScope.finishPlanning}}
      }
      if(prepared["observedFrom"] is Str) meta["historyConfigObservedFrom"]=prepared["observedFrom"]
      if(prepared["observedTo"] is Str) meta["historyConfigObservedTo"]=prepared["observedTo"]
      if(requestScope!=null)
      {
        retireSourceScratch
        // Header freezer and source-only roots have expired before admitting
        // the report borrow index and compacting the completed public flow.
        registry.prepareReportBorrows(requestScope)
      }
      headers.add(["_cockpitRequestMeta":meta]);done=true;return headers
    }
    catch(EnerCubixCockpitNativeReadErr e)
    {
      Log.get("enerCubix").err("Cockpit native history read failed; unpublished query discarded",e.cause)
      failure=EnerCubixHttpErr(502,"HISTORY_READ_FAILED","cockpitHistoryReadFailed");close;throw failure
    }
    catch(Err e) {logAdmissionFailure(e);failure=e;close;throw e}
  }
  ** Failure diagnostics only: inspect scalar ownership before cleanup drops
  ** their roots. This never retries a read or changes resource admission.
  private Void logAdmissionFailure(Err error)
  {
    resource:=error as EnerCubixHttpErr
    if(resource==null || (resource.code!="PREPARED_READ_LIMIT" && resource.code!="QUERY_TIMEOUT")) return
    try
    {
      state:=budget.state
      text:=StrBuf().add("Cockpit resource census code=").add(resource.code)
      text.add(" retainedAfterUnwind=true prepared=").add(state.prepared.val).add(" temporary=").add(state.temporary.val)
      text.add(" peak=").add(state.peak.val).add(" peakTemporary=").add(state.peakTemporary.val)
      text.add(" sourceOwner=").add(owner.entries).add(" nativeReads=").add(budget.nativeReads)
      text.add(" scanned=").add(budget.scanned).add(" windows=").add(windows.size)
      if(requestScope!=null)
      {
        text.add(" scope{")
        ["owner","inputOwner","planningModel","planningState","sourcePlanOwner","configurationOwner","historyOwner","historyMetadataWork","reportOwner","reportBorrowOwner"].each |name|
        {text.add(name).addChar('=').add(ownerEntries(requestScope,name)).addChar(' ')}
        text.addChar('}')
      }
      if(registry!=null)
      {
        text.add(" registry{watermark=").add(fieldValue(registry,"watermark"))
        ["model","metadata","diagnosticOwner","flowModel","copModel"].each |name|
        {text.addChar(' ').add(name).addChar('=').add(ownerEntries(registry,name))}
        pool:=fieldValue(registry,"pool")
        if(pool!=null) text.add(" samples=").add(fieldValue(pool,"kept")).add(" sampleLimited=").add(fieldValue(pool,"preparedEntryLimited"))
        works:=fieldValue(registry,"works") as Map
        works?.each |work,key|
        {
          if(work==null || text.size>12000) return
          text.add(" work[").add(key).add("]{next=").add(fieldValue(work,"next"))
          text.add(" to=").add(fieldValue(work,"to")).add(" state=").add(ownerEntries(work,"state"))
          text.add(" stateWithDaily=").add(((EnerCubixCockpitReportWork)work).stateEntries)
          consumer:=fieldValue(work,"consumer");periodChildren:=0
          if(consumer!=null) (fieldValue(consumer,"periods") as List)?.each |period| {periodChildren+=ownerEntries(period,"periodOwner")}
          text.add(" periodChildren=").add(periodChildren).add(" output=").add(ownerEntries(work,"output")).addChar('}')
        }
        flow:=fieldValue(registry,"flowWork")
        if(flow!=null)
        {
          text.add(" flow{")
          ["state","numbers","graph"].each |name| {text.add(name).addChar('=').add(ownerEntries(flow,name)).addChar(' ')}
          flowConsumer:=fieldValue(flow,"consumer")
          if(flowConsumer!=null) text.add(" calc=").add(ownerEntries(flowConsumer,"calc"))
          text.addChar('}')
        }
        ["copWorks","ruleWorks"].each |name|
        {
          entries:=0;(fieldValue(registry,name) as Map)?.each |work|
          {["state","output","graph"].each |key| {entries+=ownerEntries(work,key)}}
          text.addChar(' ').add(name).addChar('=').add(entries)
        }
        catalog:=fieldValue(registry,"catalog")
        if(catalog!=null)
        {
          text.add(" catalogOwner=").add(ownerEntries(catalog,"owner"))
          ["nodeWarningTexts","lineWarningTexts"].each |name|
          {
            groups:=fieldValue(catalog,name) as Map;count:=0
            groups?.each |values| {count+=(values as Map)?.size ?: 0}
            text.addChar(' ').add(name).addChar('=').add(groups?.size ?: 0).addChar('/').add(count)
          }
        }
        text.addChar('}')
      }
      totalPrepared:=0;totalDetail:=0;totalInterval:=0
      windows.each |window,index|
      {
        cursor:=window.cursor;if(cursor==null) return
        prepared:=(Int)fieldValue(cursor,"cursorPreparedCharge");detail:=(Int)fieldValue(cursor,"cursorDetailCharge");interval:=(Int)fieldValue(cursor,"cursorIntervalCharge")
        totalPrepared+=prepared;totalDetail+=detail;totalInterval+=interval
        if(text.size<16000) text.add(" cursor[").add(index).add("]{prepared=").add(prepared).add(" detail=").add(detail).add(" interval=").add(interval).add(" hour=").add(fieldValue(cursor,"hour")).addChar('}')
      }
      text.add(" cursorTotals=").add(totalPrepared).addChar('/').add(totalDetail).addChar('/').add(totalInterval)
      Log.get("enerCubix").warn(text.toStr)
    }
    catch(Err ignored) {} // Diagnostics must never replace the original failure.
  }
  private static Obj? fieldValue(Obj source,Str name) {source.typeof.field(name,false)?.get(source)}
  private static Int ownerEntries(Obj source,Str name) {(fieldValue(source,name) as EnerCubixPreparedOwner)?.entries ?: 0}
  ** All source cursors are closed and every public header is immutable. Retire
  ** the consumed source builders/window metadata before report/provenance work;
  ** the registry, frozen headers and diagnostic/catalog owners remain alive.
  private Void retireSourceScratch()
  {
    windows.each |w| {if(w.cursor!=null) throw ArgErr("cockpitSourceCursorStillOpen");w.unavailable?.clear;w.cleaning?.clear}
    windows.clear
    detached.each |v| {if(v is Map) ((Map)v).clear;else ((List)v).clear};detached.clear
    request=null;records=null;prepared=null;reader=null
    // Preserve the conservative fixed session allowance, mutable header vector
    // and (only for an empty source plan) mutable statistics. Immutable header
    // facts are still charged to the request's history/configuration owners.
    retained:=68+headers.size+(stats.isImmutable ? 0 : 1+stats.size)
    owner.retainPublic(retained) |->Void|
    {
      headers.each |h| {if(!h.isImmutable) {(h["_cockpitRequestMeta"] as Map)?.clear;h.clear}};headers.clear
      if(!stats.isImmutable) stats.clear;this.requestScope=null
    }
  }
  private Void nativeRead(Dict point,Span span,|HisItem| sink)
  {
    Err? downstream
    try
    {
      reader(point,span,|HisItem item|
      {try {sink(item)} catch(Err e) {downstream=e;throw e}})
    }
    catch(Err e)
    {
      // Density bisection and global failures retain their existing semantics.
      // A consumer/sink failure is not an error from the native history store.
      if(e is EnerCubixHttpErr || e is EnerCubixStreamBlockErr) throw e
      Err? cause:=e
      while(cause!=null)
      {
        if(cause is EnerCubixHttpErr || cause is EnerCubixStreamBlockErr || cause===downstream) throw cause
        cause=cause.cause
      }
      throw EnerCubixCockpitNativeReadErr(e)
    }
  }
  private Void addHeader(EnerCubixCockpitSourceWindow w,Str:Obj? meta)
  {
    owner.hold(16+meta.size);header:=meta.dup
    ids:=EnerCubixMath.strings(meta["sourceIds"]);header["sourceIds"]=ids.isEmpty ? [w.id] : ids
    header["configRefs"]=((Map)prepared["configRefs"])[w.id]
    header["_cockpitFrom"]=w.from.toIso;header["_cockpitTo"]=w.to.toIso;header["streaming"]=stats
    if(w.cleaning!=null) header["cleaning"]=w.cleaning
    if(prepared["observedFrom"] is Str) header["historyConfigObservedFrom"]=prepared["observedFrom"]
    if(prepared["observedTo"] is Str) header["historyConfigObservedTo"]=prepared["observedTo"]
    headers.add(header)
  }
  private Obj? detach(Obj? value)
  {
    if(value is Map)
    {
      owner.hold(2+((Map)value).size);copy:=Str:Obj?[:];detached.add(copy)
      ((Map)value).each |v,k| {copy[k.toStr]=detach(v)};return copy
    }
    if(value is List)
    {
      owner.hold(2+((List)value).size);copy:=Obj?[,];detached.add(copy)
      ((List)value).each |v| {copy.add(detach(v))};return copy
    }
    if(value!=null && !value.isImmutable) throw ArgErr("cockpitSourceSessionMetadataValue")
    return value
  }
  Str:Obj? read(Str key,Str:Obj? query)
  {
    ready
    if(requestScope==null || key.startsWith("cop:")) return registry.read(key,query)
    registry.validateReport(key,query)
    cached:=requestScope.frozenReport(key);if(cached!=null) return cached
    return registry.freezeReport(key,query,requestScope)
  }
  Str:Obj? copData(Str id,Str:Obj? query) {ready;return registry.copData(id,query)}
  Str:Obj? ruleData(Str id,Str:Obj? query) {ready;return registry.ruleData(id,query)}
  private Void ready() {check;if(!done) throw ArgErr("cockpitSourceSessionNotReady")}
  private Void check() {if(failure!=null) throw failure;if(closed) throw ArgErr("cockpitSourceSessionClosed");budget.check}
  Void close()
  {
    if(closed) return
    requestScope?.releaseReportBorrows
    windows.each |w| {w.cursor?.close;w.cursor=null}
    owner.close;registry?.close;registry=null;closed=true
  }
}

internal const class EnerCubixCockpitNativeReadErr : Err
{
  new make(Err cause) : super("cockpitNativeHistoryRead",cause) {}
}

internal class EnerCubixCockpitSourceWindow
{
  new make(Str id,DateTime from,DateTime to,Dict? point,Dict? config) {this.id=id;this.from=from;this.to=to;this.point=point;this.config=config}
  Str id
  DateTime from
  DateTime to
  Dict? point
  Dict? config
  EnerCubixCockpitStream? cursor
  [Str:Obj?]? unavailable
  [Str:Obj?]? cleaning
  Bool isCleaning() {point!=null && point.has("his") && point["hisFunc"]=="enerCubixCleanHis"}
}

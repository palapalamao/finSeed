using haystack
using util

** Controlled cursor I/O; no native FIN reads or whole-request heap proof.
class EnerCubixCockpitSourceSessionTest : Test
{
  Void testFinalSnapshotCopyMustBeAdmittedBeforeExecuteCanReturn()
  {
    a:=DateTime.fromIso("2026-10-01T00:00:00Z");request:=input;request["modules"]=["trend"]
    point:=Etc.makeDict(["id":Ref("pd"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"])
    prepared:=Str:Obj?["points":["pd":point],"configs":Str:Dict[:],"configRefs":Str:[Str:Obj?][]["pd":[Str:Obj?][,]]].toImmutable
    scope:=EnerCubixCockpitRequestScope("test","controlled-final-copy");budget:=scope.stream;peer:=EnerCubixPreparedOwner(budget.state)
    EnerCubixCockpitSourceSession? session;late:=false;returned:=false;held:=0
    try
    {
      try
      {
        EnerCubixCockpit.execute(request,records,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]|
        {
          session=EnerCubixCockpitSourceSession(q,frozen,prepared,budget,|Dict p,Span span,|HisItem| sink| {(0..2).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(100f+10f*i))) }},scope)
          headers:=session.load;meta:=(Map)headers.last["_cockpitRequestMeta"];publish:=(|Str:Obj?->Str:Obj?|)meta["publishDiagnostics"]
          meta["publishDiagnostics"]=|Str:Obj? reports->Str:Obj?| {result:=publish(reports);late=true;peer.hold(budget.state.remaining);held=peer.entries;return result}
          return headers
        },"test",TimeZone.utc,a+2hr,false,null,null,null,scope.deadline,[:],|Str key,Str:Obj? q->Str:Obj?| {session.read(key,q)},null,null,scope)
        returned=true
      }
      catch(EnerCubixHttpErr e) {verifyEq(e.status,422);verifyEq(e.code,"PREPARED_READ_LIMIT")}
      verify(late);verify(!returned);verifyEq(budget.nativeReads,1);verify(!scope.responseStarted);verify(scope.canSendError)
      session.close;scope.close;verifyEq(budget.state.temporary.val,held)
    }
    finally {session?.close;scope.close;peer.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
  Void testInputCopyLimitRejectsBeforeAnySourceCallbackAndPreservesPeer()
  {
    scope:=EnerCubixCockpitRequestScope("test","controlled-input-limit");budget:=scope.stream
    peer:=EnerCubixPreparedOwner(budget.state);peer.hold(budget.state.remaining-100);held:=peer.entries;loads:=0
    request:=input;request["modules"]=["trend"]
    try
    {
      try
      {
        EnerCubixCockpit.execute(request,records,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {loads++;return [Str:Obj?][,]},"test",TimeZone.utc,DateTime.fromIso(request["asOf"].toStr),false,null,null,null,null,[:],null,null,null,scope)
        fail("Input clone admission must finish before a source callback")
      }
      catch(EnerCubixHttpErr e) {verifyEq(e.status,422);verifyEq(e.code,"PREPARED_READ_LIMIT")}
      verifyEq(loads,0);verifyEq(budget.nativeReads,0);verify(!scope.responseStarted);verify(scope.canSendError)
      verifyEq(peer.entries,held);scope.close;verifyEq(budget.state.temporary.val,held)
    }
    finally {scope.close;peer.close}
    verifyEq(budget.state.temporary.val,0)
  }
  Void testOneRequestDeadlineAndBudgetReachAllModulesAndTheFinalWire()
  {
    a:=DateTime.fromIso("2026-10-01T00:00:00Z");b:=a+2hr;request:=input;request["payloadEncoding"]="compact-v1"
    points:=Str:Dict[:]
    ["pn","pd"].each |id| {points[id]=Etc.makeDict(["id":Ref(id),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":id=="pn" ? "MWh" : "kWh","tz":"UTC"])}
    prepared:=Str:Obj?["points":points,"configs":Str:Dict[:],"configRefs":Str:[Str:Obj?][]["pn":[Str:Obj?][,],"pd":[Str:Obj?][,]]].toImmutable
    scope:=EnerCubixCockpitRequestScope("test","controlled-nine-wire");budget:=scope.stream;EnerCubixCockpitSourceSession? session;Buf? escaped;calls:=0
    try
    {
      snapshot:=EnerCubixCockpit.execute(request,records,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]|
      {verify(q["_cockpitDeadline"]===scope.deadline);session=EnerCubixCockpitSourceSession(q,frozen,prepared,budget,|Dict p,Span span,|HisItem| sink| {(0..2).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(p.id.id=="pn" ? 0.1f*i : 10f*i*i))) }},scope);return session.load},"test",TimeZone.utc,b,true,null,null,null,scope.deadline,configuration,|Str key,Str:Obj? q->Str:Obj?|
      {
        report:=session.read(key,q);verify(report.isImmutable);verify(session.read(key,q)===report)
        changed:=q.dup.set("from",(a-1hr).toIso);verifyErr(ArgErr#) {session.read(key,changed)}
        verifyErr(ArgErr#) {session.read("not-registered",q)}
        return report
      },|Str id,Str:Obj? q->Str:Obj?| {session.copData(id,q)},|Str id,Str:Obj? q->Str:Obj?| {session.ruleData(id,q)},scope)
      scope.deliver(snapshot,|Buf bytes|
      {
        calls++;escaped=bytes;verifyErr(EnerCubixHttpErr#) {EnerCubixCockpitGate.enter("test","controlled-nine-wire")}
        packet:=(Map)JsonInStream(bytes.in).readJson;verifyEq(packet["ok"],true)
        data:=(Map)packet["data"];verifyEq(data["payloadEncoding"],"compact-v1")
        values:=EnerCubixMath.maps(((Map)((Map)((Map)((Map)data["snapshot"])["modules"])["kpis"])["data"])["values"])
        verifyEq(values.find |v| {v["id"]=="energy"}["value"],50f)
        verify(!JsonOutStream.writeJsonToStr(data).contains("publishDiagnostics"))
      })
      verifyEq(calls,1);verifyEq(escaped.size,0);session.close;verifyEq(budget.state.temporary.val,scope.entries)
      verifyEq(budget.nativeReads,2);verifyEq(budget.state.unprepared.val,0)
    }
    finally {session?.close;scope.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
  Void testOptionalProjectionFailureOnlyPublishesDiagnosticsForReturnedReports()
  {
    a:=DateTime.fromIso("2026-10-01T00:00:00Z");request:=input;request["modules"]=["kpis","trend"]
    point:=Etc.makeDict(["id":Ref("pd"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"])
    prepared:=Str:Obj?["points":["pd":point],"configs":Str:Dict[:],"configRefs":Str:[Str:Obj?][]["pd":[Str:Obj?][,]]].toImmutable
    budget:=EnerCubixStreamBudget();EnerCubixCockpitSourceSession? session
    try
    {
      snapshot:=EnerCubixCockpit.execute(request,records,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]|
      {session=EnerCubixCockpitSourceSession(q,frozen,prepared,budget,|Dict p,Span span,|HisItem| sink| {(0..2).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(100f+10f*i)))}});return session.load},"test",TimeZone.utc,a+2hr,false,null,null,null,null,[:],|Str key,Str:Obj? q->Str:Obj?|
      {if(key=="profile-cost") throw Err("controlled optional projection failure");return session.read(key,q)})
      reports:=(Map)snapshot["reports"];verify(!reports.containsKey("profile-cost"));verify(reports.containsKey("profile-energy"))
      values:=EnerCubixMath.maps(((Map)((Map)((Map)snapshot["modules"])["kpis"])["data"])["values"])
      verifyEq(values.find |v| {v["id"]=="energy"}["value"],20f);verifyNull(values.find |v| {v["id"]=="cost"}["value"])
      diagnostic:=(Map)snapshot["diagnostics"];entries:=EnerCubixMath.maps(diagnostic["entries"])
      verify(entries.all |e| {EnerCubixMath.strings(e["reportRefs"]).all |ref| {reports.containsKey(ref)}})
      verifyEq(diagnostic["returnedCount"],entries.reduce(0) |Int n,Map entry->Int| {n+(Int)entry["returnedCount"]})
      verifyEq(budget.nativeReads,1);verifyEq(budget.state.unprepared.val,0)
    }
    finally {session?.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
  Void testFactoryRejectsAForeignDeadlineBeforeConfigurationOrHistoryReads()
  {
    request:=Str:Obj?["_cockpitDeadline":EnerCubixCockpitDeadline()].toImmutable
    budget:=EnerCubixStreamBudget();lookups:=0;reads:=0
    try
    {EnerCubixCockpitSourceSession.prepare(request,[Str:Obj?][,].toImmutable,budget,|Str id->Dict?| {lookups++;return null},|Dict p->Bool| {true},|Dict p->Dict| {Etc.emptyDict},|Dict p,Span span,|HisItem| sink| {reads++});fail("Foreign deadline must not start a new source session")}
    catch(ArgErr e) {verifyEq(e.msg,"cockpitSourceSessionDeadline")}
    verifyEq(lookups,0);verifyEq(reads,0);verifyEq(budget.state.temporary.val,0)
  }
  Void testMissingHistoricalPlanIsRejectedBeforeIoRatherThanTreatedAsFutureMissing()
  {
    a:=DateTime.fromIso("2026-10-01T00:00:00Z");request:=input;request["modules"]=["trend"]
    point:=Etc.makeDict(["id":Ref("pd"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"])
    prepared:=Str:Obj?["points":["pd":point],"configs":Str:Dict[:],"configRefs":Str:[Str:Obj?][]["pd":[Str:Obj?][,]]].toImmutable
    reads:=0;budget:=EnerCubixStreamBudget();EnerCubixCockpitSourceSession? session
    try
    {
      EnerCubixCockpit.execute(request,records,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]|
      {
        broken:=q.dup.set("_cockpitRanges",[["from":a.toIso,"to":(a+1hr).toIso,"pointIds":["pd"]]])
        session=EnerCubixCockpitSourceSession(broken.toImmutable,frozen,prepared,budget,|Dict p,Span span,|HisItem| sink| {reads++})
        return session.load
      },"test",TimeZone.utc,a+2hr,false,null,null,null,null,[:],|Str key,Str:Obj? q->Str:Obj?| {session.read(key,q)})
      fail("A historical plan hole must not turn into a successful missing-value snapshot")
    }
    catch(ArgErr e) {verifyEq(e.msg,"cockpitSourceSessionHistoricalPlan");verifyEq(reads,0);verifyEq(budget.nativeReads,0)}
    finally {session?.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
  Void testConfigurationFactoryGuardsBeforeIoAndKeepsFrozenPrimaryMetadata()
  {
    (0..<5).each |variant|
    {
      a:=DateTime.fromIso("2026-10-01T00:00:00Z");rs:=records;db:=Str:Dict[:]
      ["n","d"].each |id|
      {
        point:=id=="n" ? "pn" : "pd"
        db[id]=Etc.makeDict(["id":Ref(id),"equip":Marker.val,"mod":a,"navName":id,"enerCubixKind":"meter","enerCubixPointRef":Ref(point),"enerCubixCategoryRef":Ref(id=="n" ? "cn" : "cd")])
        db[point]=Etc.makeDict(["id":Ref(point),"point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"mod":a,"unit":id=="n" ? "MWh" : "kWh","equipRef":Ref(id),"tz":"UTC"])
        rs.find |r| {r["id"]==id}.setAll(EnerCubixNativeEquip.decode(db[id]))
      }
      if(variant==1) db["d"]=Etc.makeDict(Etc.dictToMap(db["d"]).set("mod",a+1sec))
      if(variant==2) db["pd"]=Etc.makeDict(Etc.dictToMap(db["pd"]).set("equipRef",Ref("n")))
      pointLookups:=0;reads:=0;request:=input;request["modules"]=["trend"]
      lookup:=|Str id->Dict?|
      {
        if(id=="pd") {pointLookups++;if(variant==3 && pointLookups==2) return Etc.makeDict(Etc.dictToMap(db[id]).set("mod",a+1sec))}
        return db[id]
      }
      raw:=|Dict point,Span span,|HisItem| sink|
      {reads++;verifyEq(point["unit"],"kWh");(0..2).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(100f+10f*i)))}}
      budget:=EnerCubixStreamBudget();EnerCubixCockpitSourceSession? session
      try
      {
        actual:=EnerCubixCockpit.execute(request,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]|
        {
          session=EnerCubixCockpitSourceSession.prepare(q,frozen,budget,lookup,|Dict p->Bool| {variant!=0 || p.id.id!="pd"},|Dict p->Dict| {fail("Unexpected cleaning lookup");return Etc.emptyDict},raw)
          verifyEq(reads,0)
          db["pd"]=Etc.makeDict(Etc.dictToMap(db["pd"]).set("unit","MWh").set("mod",a+1sec))
          return session.load
        },"test",TimeZone.utc,a+2hr,false,null,null,null,null,[:],|Str key,Str:Obj? q->Str:Obj?| {session.read(key,q)})
        verifyEq(variant,4);verifyEq(reads,1)
        report:=(Map)((Map)actual["reports"])["profile-energy"]
        verifyEq(EnerCubixMath.maps(((Map)report["summary"])["totals"]).first["value"],20f)
        verifyNotNull(((Map)actual["provenance"])["historyConfigObservedFrom"]);verifyNotNull(((Map)actual["provenance"])["historyConfigObservedTo"])
      }
      catch(EnerCubixHttpErr e) {verify(variant<4);verifyEq(e.status,variant==0 ? 403 : 409);verifyEq(reads,0);verifyEq(budget.nativeReads,0)}
      finally {session?.close}
      verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
    }
  }
  Void testRequestedFutureAndPartialBucketsMatchOriginalWithoutFutureZeros()
  {
    a:=DateTime.fromIso("2026-10-01T00:00:00Z")
    bounds:=[[a+15min,a+2hr,a+90min],[a,a+2hr,a],[a+30min,a+90min,a+2hr],[a,a+2hr,a+1hr],[a,a+3hr,a+90min],[a,a+3hr,a+150min],[a+1hr,a+3hr,a]]
    bounds.each |range,variant|
    {
      from:=(DateTime)range[0];to:=(DateTime)range[1];cutoff:=(DateTime)range[2]
      request:=input;request["time"]=["preset":"custom","period":"hour","from":from.toIso,"to":to.toIso];request["asOf"]=cutoff.toIso
      rs:=records;owned:=configuration
      points:=Str:Dict["pn":Etc.makeDict(["id":Ref("pn"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"MWh","tz":"UTC"]),"pd":Etc.makeDict(["id":Ref("pd"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"])]
      read:=|Dict point,Span span,|HisItem| sink|
      {
        (-2..3).each |i|
        {
          if(variant==4 && point.id.id=="pd" && i==1) return
          at:=a+1hr*i;Obj? value:=Number(point.id.id=="pn" ? 0.1f*i : 100f+10f*i*i)
          if(variant==5 && point.id.id=="pd") {if(i==1) value=Number(100);if(i==2) value=NA.val}
          if(at>=span.start && at<span.end) sink(HisItem(at,value))
        }
      }
      expected:=EnerCubixCockpit.execute(request,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]|
      {
        if(variant!=3 && variant!=4) return EnerCubixCockpitStream.prepare(q,frozen,points,[:],read,EnerCubixStreamBudget())
        // At an exact cutoff the old prepared path poisons valid earlier usage
        // with an unprepared future lookup. Use the original raw-history engine
        // as the independent oracle for this explicitly corrected boundary.
        return points.vals.map |point->Str:Obj?|
        {items:=HisItem[,];read(point,Span.makeAbs(from-1day,to+1day),|HisItem item| {if(item.ts<=cutoff) items.add(item)});return EnerCubixHistory.normalize(point,items,from,to)}
      },"test",TimeZone.utc,cutoff,true,|->DateTime| {cutoff},null,null,null,owned)
      prepared:=Str:Obj?["points":points,"configs":Str:Dict[:],"configRefs":Str:[Str:Obj?][]["pn":[Str:Obj?][,],"pd":[Str:Obj?][,]]].toImmutable
      budget:=EnerCubixStreamBudget();EnerCubixCockpitSourceSession? session
      try
      {
        actual:=EnerCubixCockpit.execute(request,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {session=EnerCubixCockpitSourceSession(q,frozen,prepared,budget,read);return session.load},"test",TimeZone.utc,cutoff,true,|->DateTime| {cutoff},null,null,null,owned,|Str key,Str:Obj? q->Str:Obj?| {session.read(key,q)},|Str id,Str:Obj? q->Str:Obj?| {session.copData(id,q)},|Str id,Str:Obj? q->Str:Obj?| {session.ruleData(id,q)})
        artifactDir:=Env.cur.vars["ENERCUBIX_SOURCE_SESSION_DIFF_DIR"]
        if(artifactDir!=null)
        {File.os(artifactDir+"/source-session-future-${variant}.expected.json").out.print(JsonOutStream.writeJsonToStr(normalize(expected["modules"],expected))).close;File.os(artifactDir+"/source-session-future-${variant}.actual.json").out.print(JsonOutStream.writeJsonToStr(normalize(actual["modules"],actual))).close}
        verifyEq(normalize(actual["modules"],actual),normalize(expected["modules"],expected),variant.toStr)
        report:=(Map)((Map)actual["reports"])["profile-energy"]
        old:=(Map)((Map)expected["reports"])["profile-energy"]
        ["from","to","asOf","summary","series","rows","warnings"].each |key| {verifyEq(report[key],old[key],variant.toStr+"/"+key)}
        verifyEq(report["from"],from.toIso);verifyEq(report["to"],to.toIso);verifyEq(budget.state.unprepared.val,0)
        if(to>cutoff) verify(((List)actual["limitations"]).contains("REQUEST_END_AFTER_AS_OF"))
        if(variant==1 || variant==6) verifyEq(budget.nativeReads,0)
        if(variant==3)
        {
          value:=EnerCubixMath.maps(((Map)((Map)((Map)actual["modules"])["kpis"])["data"])["values"]).find |v| {v["id"]=="energy"}
          verifyEq(value["value"],10f);verifyEq(value["completeValue"],null);verifyEq(value["valueBasis"],"knownSubtotal")
          coverage:=EnerCubixMath.maps(((Map)report["extra"])["usageCoverage"]).first
          verifyEq(coverage["expectedSeconds"],7200f);verifyEq(coverage["coveredSeconds"],3600f);verifyEq(coverage["complete"],false)
          future:=EnerCubixMath.maps(EnerCubixMath.maps(report["series"]).first["points"]).last
          verifyNull(future["value"]);verifyEq(future["quality"],"missing")
        }
        if(variant==4)
        {
          value:=EnerCubixMath.maps(((Map)((Map)((Map)actual["modules"])["kpis"])["data"])["values"]).find |v| {v["id"]=="energy"}
          verifyNull(value["value"]);verifyNull(value["knownValue"])
          verifyEq(EnerCubixMath.maps(((Map)report["extra"])["usageCoverage"]).first["coveredSeconds"],0f)
        }
        if(variant==5)
        {
          value:=EnerCubixMath.maps(((Map)((Map)((Map)actual["modules"])["kpis"])["data"])["values"]).find |v| {v["id"]=="energy"}
          verifyEq(value["knownValue"],0f);verifyNull(value["completeValue"])
          reads:=EnerCubixMath.maps(((Map)((Map)report["extra"])["knownUsage"])["sourceUsage"])
          verify(reads.any |row| {EnerCubixMath.maps(row["intervals"]).any |i| {i["quality"]=="na"}})
        }
      }
      finally {session?.close}
      verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
    }
  }
  Void testNativeWrapperAroundDensityControlStillBisectsAndKeepsUsage()
  {
    a:=DateTime.fromIso("2026-10-01T00:00:00Z");b:=a+1hr;request:=input;request["modules"]=["trend"];request["time"]=["preset":"custom","period":"hour","from":a.toIso,"to":b.toIso];request["asOf"]=b.toIso
    point:=Etc.makeDict(["id":Ref("pd"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"])
    prepared:=Str:Obj?["points":["pd":point],"configs":Str:Dict[:],"configRefs":Str:[Str:Obj?][]["pd":[Str:Obj?][,]]].toImmutable
    calls:=0;read:=|Dict p,Span span,|HisItem| sink|
    {
      calls++;at:=a-1hr
      while(at<b+1hr)
      {
        try {if(at>=span.start && at<span.end) sink(HisItem(at,Number(100000f+(at-a).ticks.toFloat/1min.ticks.toFloat)))}
        catch(Err e) {throw IOErr("native sink wrapper",e)}
        at+=1min
      }
    }
    budget:=EnerCubixStreamBudget(20);EnerCubixCockpitSourceSession? session
    try
    {
      actual:=EnerCubixCockpit.execute(request,records,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {session=EnerCubixCockpitSourceSession(q,frozen,prepared,budget,read);return session.load},"test",TimeZone.utc,b,false,null,null,null,null,[:],|Str key,Str:Obj? q->Str:Obj?| {session.read(key,q)})
      report:=(Map)((Map)actual["reports"])["profile-energy"]
      verifyEq(EnerCubixMath.maps(((Map)report["summary"])["totals"]).first["value"],60f)
      verify(calls>1);verifyEq(budget.nativeReads,calls);verifyEq(budget.state.unprepared.val,0)
    }
    finally {session?.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
  Void testWrappedGlobalReadFailuresPreserveTheirExactOriginalError()
  {
    [403,409,422,504].each |status|
    {
      request:=input;request["modules"]=["trend"];end:=DateTime.fromIso("2026-10-01T02:00:00Z")
      point:=Etc.makeDict(["id":Ref("pd"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"])
      prepared:=Str:Obj?["points":["pd":point],"configs":Str:Dict[:],"configRefs":Str:[Str:Obj?][]["pd":[Str:Obj?][,]]].toImmutable
      original:=EnerCubixHttpErr(status,"CONTROLLED_GLOBAL","controlled global error");calls:=0
      read:=|Dict p,Span span,|HisItem| sink| {calls++;throw IOErr("native wrapper",original)}
      budget:=EnerCubixStreamBudget();EnerCubixCockpitSourceSession? session;Err? observed
      try
      {
        try {EnerCubixCockpit.execute(request,records,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {session=EnerCubixCockpitSourceSession(q,frozen,prepared,budget,read);return session.load},"test",TimeZone.utc,end,false,null,null,null,null,[:],|Str key,Str:Obj? q->Str:Obj?| {session.read(key,q)})}
        catch(Err e) {observed=e}
        verify(observed===original);verifyEq(calls,1);verifyEq(budget.residentRaw,0)
      }
      finally {session?.close}
      verifyEq(budget.state.temporary.val,0)
    }
  }
  Void testNativeReadErrorsInFirstMiddleAndLastBlockPublishNothingAndKeepPeer()
  {
    [1,2,4].each |failureAt|
    {
      a:=DateTime.fromIso("2026-10-01T00:00:00Z");b:=a+12day;request:=input;request["modules"]=["trend"];request["time"]=["preset":"custom","period":"day","from":a.toIso,"to":b.toIso];request["asOf"]=b.toIso
      point:=Etc.makeDict(["id":Ref("pd"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC"])
      prepared:=Str:Obj?["points":["pd":point],"configs":Str:Dict[:],"configRefs":Str:[Str:Obj?][]["pd":[Str:Obj?][,]]].toImmutable
      calls:=0;read:=|Dict p,Span span,|HisItem| sink|
      {calls++;if(calls==failureAt) throw IOErr("private native source path must not reach the response");at:=span.start;while(at<span.end) {sink(HisItem(at,Number(1000f+(at-a).ticks.toFloat/1hr.ticks.toFloat)));at+=1hr}}
      budget:=EnerCubixStreamBudget();peer:=EnerCubixPreparedOwner(budget.state);peer.hold(37);held:=peer.entries
      EnerCubixCockpitSourceSession? session;published:=false
      try
      {
        try
        {
          EnerCubixCockpit.execute(request,records,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {session=EnerCubixCockpitSourceSession(q,frozen,prepared,budget,read);return session.load},"test",TimeZone.utc,b,false,null,null,null,null,[:],|Str key,Str:Obj? q->Str:Obj?| {published=true;return session.read(key,q)})
          fail("A failed native source must not publish any report")
        }
        catch(EnerCubixHttpErr e) {verifyEq(e.status,502);verifyEq(e.code,"HISTORY_READ_FAILED");verifyEq(e.msg,"cockpitHistoryReadFailed")}
        verify(!published);verifyEq(calls,failureAt);verifyEq(budget.nativeReads,failureAt)
        verifyEq(budget.state.temporary.val,held);verifyEq(peer.entries,held);verifyEq(budget.residentRaw,0)
        verifyErr(EnerCubixHttpErr#) {session.load}
        verifyEq(calls,failureAt)
      }
      finally {session?.close;peer.close}
      verifyEq(budget.state.temporary.val,0)
    }
  }
  Void testCleaningCountersParametersAndPooledRowsStaySeparateFromHeaders()
  {
    a:=DateTime.fromIso("2026-10-01T00:00:00Z");b:=a+2hr;rs:=records;request:=input;owned:=configuration
    cfg:=Etc.makeDict(["defNull":Marker.val,"deltaMax":Number(50)])
    points:=Str:Dict["pn":Etc.makeDict(["id":Ref("pn"),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":"MWh","tz":"UTC"]),"pd":Etc.makeDict(["id":Ref("pd"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":cfg])]
    configs:=Str:Dict["pd":cfg]
    read:=|Dict point,Span span,|HisItem| sink| {(0..2).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(point.id.id=="pn" ? 0.1f*i : (i==0 ? 0f : (i==1 ? 10f : 100f)))))}}
    expected:=EnerCubixCockpit.execute(request,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {EnerCubixCockpitStream.prepare(q,frozen,points,configs,read,EnerCubixStreamBudget())},"test",TimeZone.utc,b,true,|->DateTime| {b},null,null,null,owned)
    prepared:=Str:Obj?["points":points,"configs":configs,"configRefs":Str:[Str:Obj?][]["pn":[Str:Obj?][,],"pd":[Str:Obj?][,]]].toImmutable
    budget:=EnerCubixStreamBudget();EnerCubixCockpitSourceSession? session;[Str:Obj?][]? headers
    try
    {
      actual:=EnerCubixCockpit.execute(request,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {session=EnerCubixCockpitSourceSession(q,frozen,prepared,budget,read);verifyEq(budget.nativeReads,0);headers=session.load;return headers},"test",TimeZone.utc,b,true,|->DateTime| {b},null,null,null,owned,|Str key,Str:Obj? q->Str:Obj?| {session.read(key,q)},|Str id,Str:Obj? q->Str:Obj?| {session.copData(id,q)},|Str id,Str:Obj? q->Str:Obj?| {session.ruleData(id,q)})
      artifactDir:=Env.cur.vars["ENERCUBIX_SOURCE_SESSION_DIFF_DIR"]
      if(artifactDir!=null)
      {File.os(artifactDir+"/source-session-cleaning.expected-modules.json").out.print(JsonOutStream.writeJsonToStr(normalize(expected["modules"],expected))).close;File.os(artifactDir+"/source-session-cleaning.actual-modules.json").out.print(JsonOutStream.writeJsonToStr(normalize(actual["modules"],actual))).close}
      verifyEq(normalize(actual["modules"],actual),normalize(expected["modules"],expected))
      verifyEq(((Map)actual["provenance"])["appliedCleaning"],((Map)expected["provenance"])["appliedCleaning"])
      report:=(Map)((Map)actual["reports"])["profile-energy"]
      cleaned:=EnerCubixMath.maps(((Map)report["extra"])["cleaning"]).first
      verifyEq(cleaned["rejectedCount"],1);verifyEq(cleaned["pointId"],"pd")
      header:=headers.find |h| {h["pointId"]=="pd"}
      verifyEq(((Map)header["cleaning"]).keys.sort,["parameters","profileId","profileVersion"])
      entries:=EnerCubixMath.maps(((Map)actual["diagnostics"])["entries"])
      proof:=entries.find |entry| {entry["id"]==cleaned["detailsDiagnosticRef"]}
      verifyEq(proof["kind"],"cleaningEvents");verifyEq(proof["returnedCount"],((List)cleaned["details"]).size)
      verify(EnerCubixMath.strings(proof["reportRefs"]).contains("profile-energy"))
      verifyEq(budget.nativeReads,2);verifyEq(budget.state.unprepared.val,0)
    }
    finally {session?.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
  Void testEmptyMissingAndNoHistoryNeverBecomeNativeEmptyReadWindows()
  {
    (0..<5).each |variant|
    {
      rs:=records;request:=input;request["modules"]=["trend"]
      points:=Str:Dict?[:]
      if(variant==0) rs.find |r| {r["id"]=="d"}.remove("pointId")
      else points["pd"]=variant==1 ? null : Etc.makeDict(variant==2 ? ["id":Ref("pd"),"unit":"kWh","tz":"UTC"] : ["id":Ref("pd"),"his":Marker.val,"hisTotalized":Marker.val,"enerCubixComputed":Marker.val,"unit":"kWh","tz":"UTC"])
      if(variant==4) points["pd"]=Etc.makeDict(Etc.dictToMap(points["pd"]).set("hisFunc","enerCubixCleanHis"))
      reads:=0;read:=|Dict p,Span span,|HisItem| sink| {reads++;fail("Unavailable main points must never be read")}
      end:=DateTime.fromIso("2026-10-01T02:00:00Z")
      expected:=EnerCubixCockpit.execute(request,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {EnerCubixCockpitStream.prepare(q,frozen,points,[:],read,EnerCubixStreamBudget())},"test",TimeZone.utc,end)
      prepared:=Str:Obj?["points":points,"configs":Str:Dict[:],"configRefs":Str:[Str:Obj?][]["pd":[Str:Obj?][,]]].toImmutable
      budget:=EnerCubixStreamBudget();EnerCubixCockpitSourceSession? session
      try
      {
        actual:=EnerCubixCockpit.execute(request,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {session=EnerCubixCockpitSourceSession(q,frozen,prepared,budget,read);return session.load},"test",TimeZone.utc,end,false,null,null,null,null,[:],|Str key,Str:Obj? q->Str:Obj?| {session.read(key,q)})
        verifyEq(reads,0);verifyEq(budget.nativeReads,0);verifyEq(budget.logicalHours,0);verifyEq(budget.state.unprepared.val,0)
        verifyEq(normalize(actual["modules"],actual),normalize(expected["modules"],expected))
        oldReport:=(Map)((Map)expected["reports"])["profile-energy"];newReport:=(Map)((Map)actual["reports"])["profile-energy"]
        ["summary","series","rows","warnings"].each |key| {verifyEq(newReport[key],oldReport[key],variant.toStr+"/"+key)}
        verifyNull(((Map)actual["provenance"])["sourceLastObservedAt"])
        verifyEq(((Map)((List)((Map)actual["provenance"])["streaming"]).first)["nativeReadCount"],0)
      }
      finally {session?.close}
      verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
    }
  }
  Void testUnsupportedConfigurationKeepsMissingQualityWithoutNativeReads()
  {
    (0..<3).each |variant|
    {
      rs:=records;request:=input;request["modules"]=["trend"]
      tags:=Str:Obj?["id":Ref("pd"),"his":Marker.val,"unit":"kWh","tz":"UTC"]
      if(variant==0) tags.setAll(["hisFunc":"enerCubixCleanHis","hisTotalized":Marker.val])
      if(variant==1) tags["hisMode"]="sampled"
      if(variant==2)
      {rs.find |r| {r["id"]=="d"}["historyMode"]="cumulative";rs.add(["id":"alias","kind":"meter","pointId":"pd","historyMode":"interval","categoryId":"cd"])}
      points:=Str:Dict["pd":Etc.makeDict(tags)]
      read:=|Dict p,Span span,|HisItem| sink| {fail("Unsupported sources must not be read")}
      end:=DateTime.fromIso("2026-10-01T02:00:00Z")
      expected:=EnerCubixCockpit.execute(request,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {EnerCubixCockpitStream.prepare(q,frozen,points,[:],read,EnerCubixStreamBudget())},"test",TimeZone.utc,end)
      prepared:=Str:Obj?["points":points,"configs":Str:Dict[:],"configRefs":Str:[Str:Obj?][]["pd":[Str:Obj?][,]]].toImmutable
      budget:=EnerCubixStreamBudget();EnerCubixCockpitSourceSession? session
      try
      {
        actual:=EnerCubixCockpit.execute(request,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {session=EnerCubixCockpitSourceSession(q,frozen,prepared,budget,read);return session.load},"test",TimeZone.utc,end,false,null,null,null,null,[:],|Str key,Str:Obj? q->Str:Obj?| {session.read(key,q)})
        oldReport:=(Map)((Map)expected["reports"])["profile-energy"];newReport:=(Map)((Map)actual["reports"])["profile-energy"]
        ["summary","series","rows","warnings"].each |key| {verifyEq(newReport[key],oldReport[key],variant.toStr+"/"+key)}
        verifyEq(((Map)actual["provenance"])["appliedCleaning"],((Map)expected["provenance"])["appliedCleaning"])
        verifyEq(budget.nativeReads,0);verifyEq(budget.state.unprepared.val,0)
      }
      finally {session?.close}
      verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
    }
  }
  Void testNineModulesUseOneSourceClockAndDetachHeadersBeforeProjection()
  {
    a:=DateTime.fromIso("2026-10-01T00:00:00Z");b:=a+2hr
    rs:=records;request:=input;owned:=configuration
    points:=Str:Dict[:]
    ["pn","pd"].each |id| {points[id]=Etc.makeDict(["id":Ref(id),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":id=="pn" ? "MWh" : "kWh","tz":"UTC"])}
    read:=|Dict point,Span span,|HisItem| sink| {(0..2).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(point.id.id=="pn" ? 0.1f*i : 10f*i*i)))}}
    expected:=EnerCubixCockpit.execute(request,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]| {EnerCubixCockpitStream.prepare(q,frozen,points,[:],read,EnerCubixStreamBudget())},"test",TimeZone.utc,b,true,|->DateTime| {b},null,null,null,owned)
    prepared:=Str:Obj?["points":points,"configs":Str:Dict[:],"configRefs":Str:[Str:Obj?][]["pn":[Str:Obj?][,],"pd":[Str:Obj?][,]]].toImmutable
    budget:=EnerCubixStreamBudget()
    EnerCubixCockpitSourceSession? session;Map? sourceRequest;[Str:Obj?][]? headers
    try
    {
      actual:=EnerCubixCockpit.execute(request,rs,|Str:Obj? q,[Str:Obj?][] frozen->[Str:Obj?][]|
      {
        sourceRequest=(Map)((Map)q["_cockpitConsumers"])["request"]
        session=EnerCubixCockpitSourceSession(q,frozen,prepared,budget,read)
        verifyEq(budget.nativeReads,0);verifyErr(ArgErr#) {session.read("profile-energy",(Str:Obj?)sourceRequest)}
        headers=session.load;return headers
      },"test",TimeZone.utc,b,true,|->DateTime| {b},null,null,null,owned,|Str key,Str:Obj? q->Str:Obj?| {session.read(key,q)},|Str id,Str:Obj? q->Str:Obj?| {session.copData(id,q)},|Str id,Str:Obj? q->Str:Obj?| {session.ruleData(id,q)})
      verifyEq(budget.nativeReads,2);verifyEq(budget.logicalHours,4);verifyEq(budget.state.unprepared.val,0)
      verifyEq(EnerCubixMath.maps(((Map)((Map)((Map)actual["modules"])["kpis"])["data"])["values"]).find |v| {v["id"]=="energy"}["value"],50f)
      ratio:=(Map)EnerCubixMath.maps(((Map)((Map)((Map)actual["modules"])["efficiency"])["data"])["items"]).first["ratio"]
      verifyEq(ratio["value"],6f);verifyEq(ratio["quality"],"ok")
      verifyEq(normalize(actual["modules"],actual),normalize(expected["modules"],expected))
      ["configFingerprint","configRefs","appliedCleaning","sourceLastObservedAt","historyLimitations","historyConfigObservedFrom","historyConfigObservedTo","historyPlan"].each |key| {verifyEq(((Map)actual["provenance"])[key],((Map)expected["provenance"])[key],key)}
      verify((Int)((Map)actual["diagnostics"])["returnedCount"]<=1000)
      verify(headers.all |h| {!h.containsKey("samples") && !h.containsKey("_preparedReads") && !h.containsKey("_preparedSparse")})
      body:=JsonOutStream.writeJsonToStr(actual);verify(!body.contains("_cockpitRequestMeta"));verify(!body.contains("preparedBudget"));verify(!body.contains("publishDiagnostics"))
      verifyErr(ArgErr#) {session.load}
      report:=session.read("profile-energy",(Str:Obj?)sourceRequest);session.close;verify(report.isEmpty);verify(headers.isEmpty)
      verifyEq(ratio["value"],6f,"The committed immutable result survives source/output cleanup")
    }
    finally {session?.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
  private Obj? normalize(Obj? value,Map snapshot)
  {
    if(value==snapshot["snapshotId"]) return "<snapshot>"
    if(value==((Map)snapshot["boundary"])["id"]) return "<boundary>"
    if(value is Str && ((Str)value).startsWith("quality:"))
    {
      issue:=(Map)((Map)snapshot["modules"])["issues"];data:=issue["data"] as Map
      item:=EnerCubixMath.maps(data?.get("items")).find |row| {row["id"]==value && row["type"]=="dataQuality"}
      if(item!=null)
      {
        // The original quality identity includes a fresh boundary UUID, which
        // also breaks severity ties. Verify that identity before canonicalizing
        // this fixture's otherwise equal, independently generated snapshots.
        reasons:=EnerCubixMath.strings(item["reasonCodes"]).unique.sort.join("|")
        key:=((Map)snapshot["boundary"])["id"].toStr+"|"+item["metricId"].toStr+"|"+reasons
        verifyEq(value,"quality:"+key.toBuf.toDigest("SHA-256").toHex)
        return "quality:"+item["metricId"].toStr+"|"+reasons
      }
    }
    if(value is Map)
    {
      m:=(Map)value
      if(m["items"] is List && m["topIds"] is List)
      {ids:=EnerCubixMath.maps(m["items"]).map |row->Str| {row["id"].toStr};verifyEq(m["topIds"],ids[0..<ids.size.min(3)])}
      out:=Str:Obj?[:];m.each |v,k| {out[k.toStr]=normalize(v,snapshot)};return out
    }
    if(value is List)
    {
      out:=((List)value).map |v->Obj?| {normalize(v,snapshot)}
      if(!out.isEmpty && out.all |v| {v is Map && ((Map)v)["type"]=="dataQuality"}) out.sort |a,b| {((Map)a)["metricId"].toStr <=> ((Map)b)["metricId"].toStr}
      if(!out.isEmpty && out.size<=3 && out.all |v| {v is Str && ((Str)v).startsWith("quality:")}) out.sort
      return out
    }
    return value
  }
  private Str:Obj? input() {["schemaVersion":1,"requestId":"source-session","reportScope":["dimension":"space","nodeIds":["s"],"selectionIntent":"range"],"focusCategoryId":"cd","time":["preset":"custom","period":"hour","from":"2026-10-01T00:00:00Z","to":"2026-10-01T02:00:00Z"],"asOf":"2026-10-01T02:00:00Z","comparison":["mode":"none"],"modules":["kpis","trend","space","time","endUse","organization","balance","efficiency","issues"]]}
  private Str:Obj? configuration() {["projectRef":"p:test","modelComplete":true,"rulesComplete":true,"rules":[["id":"rule","version":1,"name":"Night usage","scopeKind":"project","scopeRef":"p:test","categoryRef":"cd","calendarRef":"cal","ruleType":"nonWorkingHighUsage","threshold":20f,"thresholdUnit":"kWh","enabled":true]]]}
  private [Str:Obj?][] records() {[["id":"cn","kind":"category","name":"Cooling","unit":"MWh"],["id":"cd","kind":"category","name":"Electricity","unit":"kWh"],["id":"s","kind":"space","name":"Test site","nativeSourceKind":"site","area":1000f],["id":"n","kind":"meter","name":"Cooling meter","nativeEquip":true,"nativeTreeParentId":"s","nativeSpaceId":"s","spaceId":"s","categoryId":"cn","pointId":"pn"],["id":"d","kind":"meter","name":"Electricity meter","nativeEquip":true,"nativeTreeParentId":"s","nativeSpaceId":"s","spaceId":"s","categoryId":"cd","pointId":"pd"],["id":"cop","kind":"cop","name":"System COP","numeratorId":"n","denominatorId":"d"],["id":"tariff","kind":"tariff","name":"Flat price","categoryId":"cd","mode":"flat","isDefault":true,"rate":1f],["id":"cal","kind":"calendar","isDefault":true,"workDays":[1,2,3,4,5],"workHours":[9,10,11,12,13,14,15,16,17]]]}
}

using haystack
using util

class FinEnergyCockpitPreparationTest : Test
{
  Void testScopedConfigurationFreezeSurvivesWorkspaceCleanupAndLaterSourceEdits()
  {
    db:=database;records:=catalog(db);request:=cockpitRequest
    expected:=FinEnergyCockpit.execute(request,records,|q,rs->[Str:Obj?][]| {histories(prepare(rs,db))},"test",TimeZone.utc,at+1hr)
    scope:=FinEnergyCockpitRequestScope("test","owned-configuration");peer:=FinEnergyPreparedOwner(scope.stream.state);peer.hold(31)
    FinEnergyCockpitSourceSession? session;FinEnergyPreparedOwner? workspace;Map[] decoded := [,];reads:=0;cleanings:=0
    try
    {
      actual:=FinEnergyCockpit.execute(request,records,|Str:Obj? q,[Str:Obj?][] rs->[Str:Obj?][]|
      {
        session=FinEnergyCockpitSourceSession.prepare(q,rs,scope.stream,|Str id->Dict?| {db[id]},|Dict p->Bool| {true},|Dict p->Dict| {fail("Scoped native configuration must use its admitted callback");return Etc.emptyDict},|Dict p,Span span,|HisItem| sink|
        {reads++;[at,at+1hr].each |ts| {if(ts>=span.start && ts<span.end) sink(HisItem(ts,Number(ts==at ? 0 : 10)))}},scope,|Dict p,FinEnergyPreparedOwner work->Dict|
        {
          cleanings++;workspace=work;profile:=FinEnergyRepo.decodeOwned(db["profile"],work);decoded.add(profile)
          work.hold(64+16*((Map)profile["parameters"]).size)
          return FinEnergyCleaningRepo.configFor(profile,p)
        })
        verifyEq(reads,0);verifyEq(workspace.entries,0);verify(decoded.all |row| {row.isEmpty})
        upgrade(db)
        return session.load
      },"test",TimeZone.utc,at+1hr,false,null,null,null,scope.deadline,[:],|Str key,Str:Obj? q->Str:Obj?| {session.read(key,q)},null,null,scope)
      verifyEq(reads,2);verifyEq(cleanings,2)
      values:=FinEnergyMath.maps(((Map)((Map)((Map)actual["modules"])["kpis"])["data"])["values"])
      verifyEq(values.first["value"],20f)
      ["configRefs","configFingerprint","appliedCleaning"].each |key| {verifyEq(((Map)actual["provenance"])[key],((Map)expected["provenance"])[key])}
      verify(FinEnergyMath.maps(((Map)actual["provenance"])["appliedCleaning"]).all |row| {row["profileVersion"]==1})
      verifyEq(scope.stream.state.temporary.val,scope.entries+peer.entries)
      scope.deliver(actual,|Buf bytes| {verify(!bytes.readAllStr.contains("releaseSources"))})
      scope.close;verifyEq(scope.stream.state.temporary.val,peer.entries)
    }
    finally {session?.close;scope.close;peer.close}
    verifyEq(scope.stream.state.temporary.val,0);verifyEq(scope.stream.residentRaw,0)
  }
  Void testScopedConfigurationAdmissionRejectsBeforeLookupAndKeepsPeer()
  {
    scope:=FinEnergyCockpitRequestScope("test","owned-configuration-limit");peer:=FinEnergyPreparedOwner(scope.stream.state)
    peer.hold(scope.stream.state.remaining-8);held:=peer.entries;lookups:=0;reads:=0
    try
    {
      verifyErr(FinEnergyHttpErr#)
      {
        unexpected:=FinEnergyCockpitSourceSession.prepare(request.toImmutable,[Str:Obj?][,].toImmutable,scope.stream,|Str id->Dict?| {lookups++;return null},|Dict p->Bool| {true},|Dict p->Dict| {Etc.emptyDict},|Dict p,Span span,|HisItem| sink| {reads++},scope,|Dict p,FinEnergyPreparedOwner work->Dict| {Etc.emptyDict})
        unexpected.close
      }
      verifyEq(lookups,0);verifyEq(reads,0);verifyEq(peer.entries,held)
      scope.close;verifyEq(scope.stream.state.temporary.val,held)
    }
    finally {scope.close;peer.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testScopedFactoryRequiresItsConfigurationAdapterBeforeLookup()
  {
    scope:=FinEnergyCockpitRequestScope("test","owned-adapter-required");lookups:=0
    try
    {
      verifyErr(ArgErr#)
      {
        unexpected:=FinEnergyCockpitSourceSession.prepare(request.toImmutable,[Str:Obj?][,].toImmutable,scope.stream,|Str id->Dict?| {lookups++;return null},|Dict p->Bool| {true},|Dict p->Dict| {Etc.emptyDict},|Dict p,Span span,|HisItem| sink| {fail("No source reader before a prepared adapter")},scope)
        unexpected.close
      }
      verifyEq(lookups,0);verifyEq(scope.stream.state.temporary.val,scope.entries)
    }
    finally {scope.close}
    verifyEq(scope.stream.state.temporary.val,0)
  }
  Void testScopedCleaningGlobalErrorsRemainTheOriginalWholeRequestFailure()
  {
    [401,403,409,422,429,504].each |status|
    {
      db:=database;scope:=FinEnergyCockpitRequestScope("test","owned-config-global");original:=FinEnergyHttpErr(status,"CONTROLLED_GLOBAL","controlled configuration failure")
      reads:=0;calls:=0;Err? observed
      try
      {
        try
        {
          unexpected:=FinEnergyCockpitSourceSession.prepare(request.toImmutable,catalog(db).toImmutable,scope.stream,|Str id->Dict?| {db[id]},|Dict p->Bool| {true},|Dict p->Dict| {fail("Wrong callback");return Etc.emptyDict},|Dict p,Span span,|HisItem| sink| {reads++},scope,|Dict p,FinEnergyPreparedOwner work->Dict| {calls++;throw original})
          unexpected.close
        }
        catch(Err e) {observed=e}
        verify(observed===original);verifyEq(reads,0);verifyEq(calls,1)
      }
      finally {scope.close}
      verifyEq(scope.stream.state.temporary.val,0)
    }
  }
  Void testConfigurationCallbackDoesNotDowngradeGlobalFailuresToMissingCleaning()
  {
    [401,403,409,422,429,504].each |status|
    {
      db:=database;rs:=catalog(db);original:=FinEnergyHttpErr(status,"CONTROLLED_GLOBAL","controlled configuration failure")
      Err? observed;calls:=0
      try {FinEnergyHistory.prepareConfiguration(request,rs,|Str id->Dict?| {db[id]},|Dict p->Bool| {true},|Dict p->Dict| {calls++;throw original})}
      catch(Err e) {observed=e}
      verify(observed===original);verifyEq(calls,1)
    }
  }
  Void testPreparedV1RejectsCurrentV2AsWholeRequest()
  {
    db:=database; records:=catalog(db)
    upgrade(db)
    conflict |->Void| {prepare(records,db)}
  }

  Void testSharedProfileUpdateBetweenPointFreezesRejectsWholeRequest()
  {
    db:=database; records:=catalog(db); calls:=0
    conflict |->Void|
    {
      FinEnergyHistory.prepareConfiguration(request,records,|Str id->Dict?| {db[id]},|Dict p->Bool| {true},|Dict p->Dict|
      {
        config:=(Dict)p["hisFuncConfig"]
        calls++
        if (calls == 1) upgrade(db)
        return config
      })
    }
    verify(calls >= 1)
  }

  Void testEqualVersionWithDifferentParametersOrProfileIdentityRejects()
  {
    db:=database; records:=catalog(db)
    p:=db["p1"]
    config:=Etc.makeDict(Etc.dictToMap((Dict)p["hisFuncConfig"]).set("deltaMax",Number(200,Unit("kWh"))))
    db["p1"]=changed(p,["hisFuncConfig":config])
    conflict |->Void| {prepare(records,db)}
    db=database
    db["p1"]=changed(db["p1"],["finEnergyCleaningProfileRef":Ref("other-profile")])
    conflict |->Void| {prepare(records,db)}
  }

  Void testChangedEquipmentBindingOrRevisionRejects()
  {
    db:=database; records:=catalog(db)
    db["m1"]=changed(db["m1"],["finEnergyPointRef":Ref("other-point")])
    conflict |->Void| {prepare(records,db)}
    db=database
    db["m1"]=changed(db["m1"],["mod":at+1sec])
    conflict |->Void| {prepare(records,db)}
  }

  Void testPointChangeDuringFreezeIsNotSilentlyAccepted()
  {
    db:=database; records:=catalog(db)
    conflict |->Void|
    {
      FinEnergyHistory.prepareConfiguration(request,records,|Str id->Dict?| {db[id]},|Dict p->Bool| {true},|Dict p->Dict|
      {
        db[p.id.id]=changed(p,["mod":at+1sec,"hisCollectInterval":5min])
        return (Dict)p["hisFuncConfig"]
      })
    }
  }

  Void testConsistentVersionSucceedsAndRemainsFrozenAfterPreparation()
  {
    db:=database; records:=catalog(db)
    prepared:=prepare(records,db)
    points:=(Str:Dict?)prepared["points"]; configs:=(Str:Dict)prepared["configs"]
    verifyEq(points["p1"]?.get("mod"),at)
    verifyEq(configs["p1"]["finEnergyProfileVersion"],Number(1))
    verifyEq(FinEnergyCleaning.jsonConfig(configs["p1"]),FinEnergyCleaning.jsonConfig(FinEnergyCleaningRepo.configFor(profile,points["p1"])))
    // A later edit does not invalidate a completed freeze or change either period's rules.
    upgrade(db)
    verifyEq(configs["p1"]["finEnergyProfileVersion"],Number(1))
    verifyEq(configs["p2"]["finEnergyProfileVersion"],Number(1))
    refs:=(Str:[Str:Obj?][])prepared["configRefs"]
    verifyEq(refs["p1"].find |r| {r["id"] == "profile"}["mod"],at.toIso)
    verifyEq(refs["p2"].find |r| {r["id"] == "profile"}["mod"],at.toIso)
    verify(DateTime.fromIso(prepared["observedTo"].toStr) >= DateTime.fromIso(prepared["observedFrom"].toStr))
  }

  Void testWholeCockpitRejectsPreparationConflictBeforeAnyHistoryAndPublishesMatchingEvidence()
  {
    db:=database; records:=catalog(db); reads:=0
    upgrade(db)
    conflict |->Void|
    {
      FinEnergyCockpit.execute(cockpitRequest,records,|rq,rs->[Str:Obj?][]|
      {
        prepared:=prepare(rs,db)
        reads++
        return histories(prepared)
      },"test",TimeZone.utc,at+1hr)
    }
    verifyEq(reads,0)
    db=database; records=catalog(db)
    first:=FinEnergyCockpit.execute(cockpitRequest,records,|rq,rs->[Str:Obj?][]|
    {
      prepared:=prepare(rs,db)
      upgrade(db) // Changes after the completed freeze do not alter applied rules.
      reads++
      return histories(prepared)
    },"test",TimeZone.utc,at+1hr)
    provenance:=(Map)first["provenance"]
    applied:=FinEnergyMath.maps(provenance["appliedCleaning"])
    verifyEq(applied.size,2)
    verify(applied.all |r| {r["profileVersion"] == 1})
    verifyEq(FinEnergyMath.maps(provenance["configRefs"]).find |r| {r["id"] == "profile"}["mod"],at.toIso)
    verifyNotNull(provenance["historyConfigObservedFrom"]);verifyNotNull(provenance["historyConfigObservedTo"])
    values:=FinEnergyMath.maps(((Map)((Map)((Map)first["modules"])["kpis"])["data"])["values"])
    verifyEq(values.first["value"],20f)
    records=catalog(db)
    second:=FinEnergyCockpit.execute(cockpitRequest,records,|rq,rs->[Str:Obj?][]| {histories(prepare(rs,db))},"test",TimeZone.utc,at+1hr)
    verify(provenance["configFingerprint"] != ((Map)second["provenance"])["configFingerprint"])
    verify(applied.all |r| {r["profileVersion"] == 1})
    fixture:=Env.cur.vars["FINENERGY_COCKPIT_PREPARATION_FIXTURE"]
    if (fixture != null) File.os(fixture).out.writeChars(JsonOutStream.writeJsonToStr(first)).close
  }

  private Void conflict(|->Void| action)
  {
    try {action(); fail("Expected whole-request configuration conflict")}
    catch (FinEnergyHttpErr e)
    {verifyEq(e.status,409);verifyEq(e.code,"CONFIGURATION_CHANGED");verifyEq(e.msg,"cockpitConfigurationChanged")}
  }

  private Str:Obj? prepare([Str:Obj?][] records, Str:Dict db)
  {FinEnergyHistory.prepareConfiguration(request,records,|Str id->Dict?| {db[id]},|Dict p->Bool| {true},|Dict p->Dict| {(Dict)p["hisFuncConfig"]})}
  private Str:Obj? request() {["_cockpitPointIds":["p1","p2"]]}
  private Str:Obj? cockpitRequest() {["schemaVersion":1,"requestId":"configuration-freeze","reportScope":["dimension":"metering","nodeIds":["m1","m2"],"selectionIntent":"range"],"focusCategoryId":"c","time":["preset":"custom","period":"hour","from":at.toIso,"to":(at+1hr).toIso],"asOf":(at+1hr).toIso,"modules":["kpis"],"comparison":["mode":"none"]]}
  private DateTime at() {DateTime.fromIso("2026-10-01T00:00:00Z")}
  private Str:Obj? profile() {["id":"profile","kind":"cleaningProfile","name":"Cleaning","version":1,"mode":"drop","parameters":["deltaMin":0,"deltaMax":100,"timeMax":"1h","defNull":true]]}
  private [Str:Obj?][] catalog(Str:Dict db)
  {[FinEnergyNativeEquip.decode(db["m1"]),FinEnergyNativeEquip.decode(db["m2"]),FinEnergyRepo.decode(db["profile"]),["id":"c","kind":"category","unit":"kWh"]]}
  private [Str:Obj?][] histories(Str:Obj? prepared)
  {
    points:=(Str:Dict?)prepared["points"]; configs:=(Str:Dict)prepared["configs"]; refs:=(Str:[Str:Obj?][])prepared["configRefs"]
    return ["p1","p2"].map |id->[Str:Obj?]|
    {
      point:=points[id];config:=configs[id]
      result:=FinEnergyCleaning.clean(point,[HisItem(at,Number(0)),HisItem(at+1hr,Number(10))],config)
      result.summary.setAll(["pointId":id,"profileId":((Ref)config["finEnergyProfileRef"]).id,"profileVersion":((Number)config["finEnergyProfileVersion"]).toInt,"parameters":FinEnergyCleaning.jsonConfig(config)])
      history:=FinEnergyHistory.normalizeClean(point,result,at,at+1hr)
      return history.setAll(["configRefs":refs[id],"historyConfigObservedFrom":prepared["observedFrom"],"historyConfigObservedTo":prepared["observedTo"]])
    }
  }
  private Str:Dict database()
  {
    db:=Str:Dict[:]
    db["profile"]=profileDict(profile,at)
    ["1","2"].each |suffix|
    {
      id:="m"+suffix; point:="p"+suffix
      db[id]=Etc.makeDict(["id":Ref(id),"equip":Marker.val,"mod":at,"navName":id,"finEnergyKind":"meter","finEnergyPointRef":Ref(point),"finEnergyCategoryRef":Ref("c"),"finEnergyCleaningEnabled":Marker.val,"finEnergyCleaningProfileRef":Ref("profile")])
      raw:=Etc.makeDict(["id":Ref(point),"point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"kind":"Number","unit":"kWh","equipRef":Ref(id),"mod":at])
      cfg:=FinEnergyCleaningRepo.configFor(profile,raw)
      db[point]=changed(raw,Etc.dictToMap(FinEnergyCleaningRepo.install(raw,Ref(id),cfg)))
    }
    return db
  }
  private Void upgrade(Str:Dict db)
  {
    newer:=profile.set("version",2).set("parameters",["deltaMin":0,"deltaMax":200,"timeMax":"1h","defNull":true])
    db["profile"]=profileDict(newer,at+1sec)
    ["p1","p2"].each |id|
    {
      p:=db[id]; cfg:=FinEnergyCleaningRepo.configFor(newer,p)
      db[id]=changed(p,Etc.dictToMap(FinEnergyCleaningRepo.install(p,p["equipRef"],cfg)).set("mod",at+1sec))
    }
  }
  private Dict profileDict(Str:Obj? input, DateTime mod)
  {Etc.makeDict(["id":Ref(input["id"].toStr),"finEnergy":Marker.val,"finEnergyKind":"cleaningProfile","finEnergyConfig":JsonOutStream.writeJsonToStr(input),"dis":"Cleaning","mod":mod])}
  private Dict changed(Dict original, Str:Obj? changes)
  {Etc.makeDict(Etc.dictToMap(original).setAll(changes))}
}

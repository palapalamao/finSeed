using haystack
using folio
using folio3
using concurrent
using util

class EnerCubixCockpitConfigStoreTest : Test
{
  Void testNativeRoundTripAuditRevisionAndDelete()
  {
    fixture |db,store|
    {
      before:=db.readCount(Filter.has("id"))
      verifyEq(((List)store.list("budget")["records"]).size,0);verifyEq(db.readCount(Filter.has("id")),before)
      // Existing global revision must update, not be added again on first owned save.
      db.commit(Diff.makeAdd(Etc.makeDict(["enerCubixRevision":Number(1)]),Ref("enerCubix-config-revision")))
      created:=store.save("budget",budget)
      r:=db.readById(Ref(created["id"].toStr))
      verify(r.has("enerCubixBudget"));verify(!r.has("enerCubixKind"));verify(r["scopeRef"] is Ref);verify(r["categoryRef"] is Ref);verify(r["amount"] is Number);verify(r["version"] is Number)
      read:=EnerCubixMath.maps(store.list("budget")["records"]).first
      listAfterCreate:=store.list("budget").set("projectRef","p:budgetFixture")
      verifyEq(read["scopeRef"],"p:budgetFixture:r:s");verifyEq(read["amount"],310000f)
      edit:=budget;edit["id"]=created["id"];edit["mod"]=created["mod"];edit["amount"]=320000f
      changed:=store.save("budget",edit);verifyEq(changed["version"],2f)
      verifyErr(EnerCubixHttpErr#) |->Void| {store.save("budget",edit)}
      verify(store.referencesId("c"))
      removed:=store.remove("budget",changed["id"].toStr,changed["mod"])
      verifyEq(((List)store.list("budget")["records"]).size,0)
      log:=EnerCubixMath.maps(store.history(changed["id"].toStr)["records"])
      verifyEq(log.size,3);verifyEq(log.map |a->Str| {a["action"].toStr},["create","update","delete"])
      audit:=db.readAllList(Filter.has("enerCubixCockpitAudit")).find |a| {a["action"] == "update"}
      verify(audit["before"] is Dict);verify(((Dict)audit["before"])["amount"] is Number)
      verify(((Dict)audit["after"])["scopeRef"] is Ref)
      output:=Env.cur.vars["ENERCUBIX_M4_STORE_FIXTURE"]
      if(output != null)
      {
        types:=Str:Obj?[:];r.each |v,k| {types[k]=v.typeof.qname}
        File.os(output).out.writeChars(JsonOutStream.writeJsonToStr(["evidenceLevel":"actualTemporaryFolio3","list":listAfterCreate,"created":created,"updated":changed,"deleted":removed,"audit":store.history(changed["id"].toStr),"nativeReadback":EnerCubixCockpitConfigStore.nativeJson(r),"nativeTypes":types])).close
      }
    }
  }
  Void testOverlappingNewCreatesAreAtomicAndUnique()
  {
    fixture |db,store|
    {
      a:=store.planSave("budget",budget);b:=store.planSave("budget",budget)
      store.apply(a)
      try {store.apply(b);fail("Stale manifest/revision must reject entire second transaction")}
      catch(EnerCubixHttpErr e) {verifyEq(e.status,409)}
      verifyEq(db.readCount(Filter.has("enerCubixBudget")),1)
      verifyEq(db.readCount(Filter.has("enerCubixCockpitAudit")),1)
      verifyErr(EnerCubixHttpErr#) |->Void| {store.save("budget",budget)}
    }
  }
  Void testPermissionsForeignRefsAndForgedOwnershipCannotWrite()
  {
    fixture |db,store|
    {
      readOnlyStore:=EnerCubixCockpitConfigStore(db,"budgetFixture",Ref("p:budgetFixture"),"reader",false)
      verifyErr(EnerCubixHttpErr#) |->Void| {readOnlyStore.save("budget",budget)}
      invalid:=budget;invalid["scopeRef"]="p:other:r:s"
      verifyErr(ArgErr#) |->Void| {store.save("budget",invalid)}
      invalid=budget;invalid["equip"]=true
      verifyErr(ArgErr#) |->Void| {store.save("budget",invalid)}
      fake:=db.commit(Diff.makeAdd(Etc.makeDict(["equip":Marker.val,"enerCubixBudget":Marker.val,"enerCubixOwnedSchema":Number(1),"version":Number(1),"createdAt":DateTime.now]),Ref("forged"))).newRec
      invalid=budget;invalid["id"]=fake.id.id;invalid["mod"]=EnerCubixRepo.iso(fake["mod"])
      verifyErr(EnerCubixHttpErr#) |->Void| {store.save("budget",invalid)}
      verifyEq(db.readCount(Filter.has("enerCubixCockpitAudit")),0)
      created:=store.save("budget",budget)
      denied:=EnerCubixCockpitConfigStore(db,"budgetFixture",Ref("p:budgetFixture"),"admin",true,|Dict r->Bool| {true},|Dict r->Bool| {!r.has("enerCubixBudget")})
      edit:=budget;edit["id"]=created["id"];edit["mod"]=created["mod"]
      verifyErr(EnerCubixHttpErr#) |->Void| {denied.save("budget",edit)}
      hidden:=EnerCubixCockpitConfigStore(db,"budgetFixture",Ref("p:budgetFixture"),"reader",false,|Dict r->Bool| {!r.has("enerCubixBudget")})
      verifyEq(hidden.list("budget")["complete"],false);verifyEq(((List)hidden.list("budget")["records"]).size,0)
      db.commit(Diff(db.readById(Ref("s")),null,Diff.remove))
      invalidRead:=EnerCubixMath.maps(store.list("budget")["records"]).first
      verifyEq(invalidRead["validation"],"invalid")
    }
  }
  Void testDailyNativeNumberListAndExplicitRuleProfile()
  {
    fixture |db,store|
    {
      b:=budget;b["distribution"]="daily";b["dailyAmounts"]=(0..<31).map |i->Float| {10000f}
      saved:=store.save("budget",b);nativeRec:=db.readById(Ref(saved["id"].toStr))
      verify(((List)nativeRec["dailyAmounts"]).all |v| {v is Number})
      rule:=Str:Obj?["name":"Explicit non-working test","scopeKind":"space","scopeRef":"s","categoryRef":"c","enabled":true,"ruleType":"nonWorkingHighUsage","calendarRef":"cal","threshold":1f,"thresholdUnit":"kWh"]
      saved=store.save("rule",rule);nativeRec=db.readById(Ref(saved["id"].toStr))
      verify(nativeRec.has("enerCubixCockpitRule"));verify(!nativeRec.has("enerCubixKind"));verify(nativeRec["calendarRef"] is Ref);verify(nativeRec["threshold"] is Number)
      verify(store.referencesId("cal"))
      output:=Env.cur.vars["ENERCUBIX_M4_RULE_STORE_FIXTURE"]
      if(output != null) File.os(output).out.writeChars(JsonOutStream.writeJsonToStr(["evidenceLevel":"actualTemporaryFolio3","list":store.list("rule").set("projectRef","p:budgetFixture"),"saved":saved,"audit":store.history(saved["id"].toStr)])).close
      // Legacy collection reads exactly the old nativeRec marker filter: owned configs/audits never enter it.
      verifyEq(db.readCount(Filter.has("enerCubixKind").and(Filter.has("enerCubix").or(Filter.has("equip")))),2)
    }
  }
  Void testConcurrentUpdatesRejectStaleAtomicBatchAndInvalidAllocationLeavesNoArtifacts()
  {
    fixture |db,store|
    {
      b:=budget;b["distribution"]="daily";b["dailyAmounts"]=[1f]
      verifyErr(ArgErr#) |->Void| {store.save("budget",b)}
      verifyEq(db.readCount(Filter.has("enerCubixCockpitAudit")),0)
      verifyNull(db.readById(Ref("enerCubix-cockpit-owned-config"),false))
      created:=store.save("budget",budget)
      edit:=budget;edit["id"]=created["id"];edit["mod"]=created["mod"]
      a:=store.planSave("budget",edit.dup.set("amount",320000f));other:=store.planSave("budget",edit.dup.set("amount",330000f))
      store.apply(a)
      try {store.apply(other);fail("Concurrent update must not replace newer version")}
      catch(EnerCubixHttpErr e) {verifyEq(e.status,409)}
      verifyEq(((Number)db.readById(Ref(created["id"].toStr))["amount"]).toFloat,320000f)
      verifyEq(db.readCount(Filter.has("enerCubixCockpitAudit")),2)
      r:=db.readById(Ref(created["id"].toStr));db.commit(Diff(r,Etc.makeDict(["amount":Number(0)])))
      verifyEq(EnerCubixMath.maps(store.list("budget")["records"]).first["validation"],"invalid")
      hiddenScope:=EnerCubixCockpitConfigStore(db,"budgetFixture",Ref("p:budgetFixture"),"reader",false,|Dict rec->Bool| {!rec.has("site")})
      verifyErr(EnerCubixHttpErr#) |->Void| {hiddenScope.history(created["id"].toStr)}
      verifyEq(hiddenScope.list("budget")["complete"],false)
      verifyEq(((List)hiddenScope.list("budget")["records"]).size,0)
    }
  }
  Void testRestartPersistenceAndOldMarkerReadIgnoresOwnedRecords()
  {
    dir:=(Env.cur.tempDir+`enerCubix-owned-reopen-${Uuid()}/`).normalize;dir.create
    pool:=ActorPool();Folio? db:=null
    try
    {
      settings:=FolioConfig {name="budgetFixture";it.dir=dir;idPrefix="p:budgetFixture:r:";it.pool=pool;log=Log.get("budgetFixture")}
      db=Folio3.open(settings)
      db.commit(Diff.makeAdd(Etc.makeDict(["enerCubix":Marker.val,"enerCubixKind":"category","dis":"Energy","unit":"kWh"]),Ref("c")))
      store:=EnerCubixCockpitConfigStore(db,"budgetFixture",Ref("p:budgetFixture"),"admin",true)
      b:=budget;b["scopeKind"]="project";b["scopeRef"]="p:budgetFixture"
      created:=store.save("budget",b)
      db.close;db=null;pool.stop.join;pool=ActorPool()
      settings=FolioConfig {name="budgetFixture";it.dir=dir;idPrefix="p:budgetFixture:r:";it.pool=pool;log=Log.get("budgetFixture")}
      db=Folio3.open(settings)
      store=EnerCubixCockpitConfigStore(db,"budgetFixture",Ref("p:budgetFixture"),"admin",true)
      verifyEq(EnerCubixMath.maps(store.list("budget")["records"]).first["amount"],310000f)
      verifyEq(EnerCubixMath.maps(store.history(created["id"].toStr)["records"]).size,1)
      verifyEq(db.readCount(Filter.has("enerCubixKind").and(Filter.has("enerCubix").or(Filter.has("equip")))),1)
      db.commit(Diff(db.readById(Ref("c")),null,Diff.remove))
      verifyEq(EnerCubixMath.maps(store.list("budget")["records"]).first["validation"],"invalid")
      verifyEq(db.readCount(Filter.has("enerCubixBudget")),1)
    }
    finally {if(db != null) db.close;pool.stop.join;if(dir.parent.normalize == Env.cur.tempDir.normalize && dir.name.startsWith("enerCubix-owned-reopen-")) dir.delete}
  }
  Void testUnrelatedDanglingNativeBudgetIsLocalAndPrivateAttributionDoesNotLeak()
  {
    fixture |db,store|
    {
      current:=store.save("budget",budget)
      old:=db.commit(Diff.makeAdd(Etc.makeDict(["site":Marker.val,"dis":"Old scope"]),Ref("old"))).newRec
      stale:=budget;stale["month"]="2026-09";stale["scopeRef"]=old.id.id
      store.save("budget",stale)
      db.commit(Diff(old,null,Diff.remove))
      captured:=store.capture("budget")
      owned:=Str:Obj?["projectRef":"p:budgetFixture","modelComplete":true,"budgetsComplete":captured["complete"],"budgets":captured["records"],"budgetAttribution":captured["attribution"]]
      prefix:="p:budgetFixture:r:"
      rs:=[Str:Obj?][["id":prefix+"c","kind":"category","unit":"kWh"],["id":prefix+"s","kind":"space","nativeSourceKind":"site"],["id":prefix+"m","kind":"meter","nativeEquip":true,"pointId":prefix+"p","categoryId":prefix+"c","spaceId":prefix+"s"]]
      q:=Str:Obj?["categoryIds":[prefix+"c"],"nodeIds":[prefix+"s"],"dimension":"space","from":"2026-10-01T00:00:00Z","to":"2026-10-02T00:00:00Z","asOf":"2026-10-02T00:00:00Z","tz":"UTC"]
      boundary:=Str:Obj?["id":"boundary","meterIds":[prefix+"m"],"aggregateAllowed":true]
      cost:=Str:Obj?["value":10f,"completeValue":10f,"valueBasis":"complete","unit":"CNY","coverage":[["complete":true]],"details":["tariffs":[["id":"tariff"]]]]
      result:=EnerCubixCockpitBudget.project(q,rs,owned,boundary,cost)
      verifyEq(result["status"],"ok");verifyEq(EnerCubixMath.maps(result["configRefs"]).first["id"],current["id"])
      publicList:=JsonOutStream.writeJsonToStr(store.list("budget"))
      verify(!publicList.contains("attribution"));verify(!publicList.contains(old.id.id))
      serialized:=JsonOutStream.writeJsonToStr(result)
      verify(!serialized.contains("Attribution"));verify(!serialized.contains(old.id.id))
      output:=Env.cur.vars["ENERCUBIX_M4_LOCALITY_FIXTURE"]
      if(output != null) File.os(output).out.writeChars(JsonOutStream.writeJsonToStr(["evidenceLevel":"actualTemporaryFolio3","budget":result,"publicList":store.list("budget")])).close
    }
  }
  private Str:Obj? budget() {["name":"Monthly test","scopeKind":"space","scopeRef":"s","categoryRef":"c","enabled":true,"month":"2026-10","currency":"CNY","amount":310000f,"distribution":"uniform"]}
  private Void fixture(|Folio,EnerCubixCockpitConfigStore| work)
  {
    root:=(Env.cur.tempDir+`enerCubix-owned-${Uuid()}/`).normalize;root.create
    pool:=ActorPool();db:=Folio3.open(FolioConfig {name="budgetFixture";dir=root;idPrefix="p:budgetFixture:r:";it.pool=pool;log=Log.get("budgetFixture")})
    try
    {
      db.commitAll([Diff.makeAdd(Etc.makeDict(["site":Marker.val,"dis":"Controlled scope"]),Ref("s")),Diff.makeAdd(Etc.makeDict(["enerCubix":Marker.val,"enerCubixKind":"category","unit":"kWh","dis":"Energy"]),Ref("c")),Diff.makeAdd(Etc.makeDict(["enerCubix":Marker.val,"enerCubixKind":"calendar","dis":"Explicit calendar"]),Ref("cal"))])
      work(db,EnerCubixCockpitConfigStore(db,"budgetFixture",Ref("p:budgetFixture"),"fixture-admin",true))
    }
    finally {db.close;pool.stop.join;if(root.parent.normalize == Env.cur.tempDir.normalize && root.name.startsWith("enerCubix-owned-")) root.delete}
  }
}

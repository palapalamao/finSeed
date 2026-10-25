using haystack
using folio
using util

class EnerCubixMeterGenerationTest : Test
{
  Void testContinuityNewCounterIsOnlyABaselineAndRestartIsIdempotent()
  {
    point:=Etc.makeDict(["id":Ref("main"),"unit":"kWh","curVal":Number(1000,Unit("kWh"))])
    from:=DateTime.fromIso("2026-10-25T00:00:00Z")
    input:=[Str:Obj?["id":"a","signature":"a-p","value":5000f,"quality":"ok"]]
    first:=EnerCubixMeterContinuity.advance(point,null,input,from)
    verifyEq(first["val"],Number(1000,Unit("kWh")))
    state:=Etc.makeDict(["id":Ref("state"),"enerCubixContinuity":first["state"]])
    input[0]["value"]=5012f
    second:=EnerCubixMeterContinuity.advance(point,state,input,from+1min)
    verifyEq(second["val"],Number(1012,Unit("kWh")))
    state=Etc.makeDict(["id":Ref("state"),"enerCubixContinuity":second["state"]])
    verifyEq(EnerCubixMeterContinuity.advance(point,state,input,from+2min)["val"],Number(1012,Unit("kWh")))
    input.add(["id":"new","signature":"new-p","value":90000f,"quality":"ok"])
    verifyEq(EnerCubixMeterContinuity.advance(point,state,input,from+2min)["val"],Number(1012,Unit("kWh")))
    added:=EnerCubixMeterContinuity.advance(point,state,input,from+2min)
    afterAdd:=Etc.makeDict(["id":Ref("state"),"enerCubixContinuity":added["state"]])
    input=input.findAll |r| { r["id"] != "new" }; input[0]["value"]=5017f
    verifyEq(EnerCubixMeterContinuity.advance(point,afterAdd,input,from+3min)["val"],Number(1017,Unit("kWh")))
    input=input.findAll |r| {r["id"] == "a"}; input[0]["signature"]="replacement-point"; input[0]["value"]=2f
    verifyEq(EnerCubixMeterContinuity.advance(point,state,input,from+3min)["val"],Number(1012,Unit("kWh")))
  }

  Void testCadenceAlignmentAndPublishedOwnHistorySurviveReplay()
  {
    withDb |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z")
      meter(db,"total",null,true); meter(db,"a","total"); meter(db,"b","total")
      counters(db,"a",at,10sec,5000f,1f); counters(db,"b",at,15sec,200f,1f)
      EnerCubixMeterTimeline.initialize(db,at)
      EnerCubixMeterGeneration.update(db,at)
      EnerCubixMeterGeneration.update(db,at+3min)
      point:=db.readById(Ref("total-p"))
      published:=EnerCubixMeterHistory.loadDb(db,point,at,at+1min)
      verifyNotNull(published)
      v:=EnerCubixHistoryData(published).read(at,at+1min)
      verifyEq(v.value,10f); verifyEq(v.quality,"derived")
      state:=db.readById(EnerCubixMeterHistory.stateId(point.id))
      count:=0; db.his.read(state["enerCubixUsageRef"],null,null) |item| {count++}
      verifyEq(count,2)
      before:=state["enerCubixGeneratedCumulative"]
      EnerCubixMeterGeneration.update(db,at+3min)
      verifyEq(db.readById(state.id)["enerCubixGeneratedCumulative"],before)
      again:=0; db.his.read(state["enerCubixUsageRef"],null,null) |item| {again++}
      verifyEq(again,count)
      // Own published interval is retained when the current branch disappears.
      child:=db.readById(Ref("b")); db.commit(Diff(child,Etc.makeDict(["enerCubixMeterParentRef":Remove.val])))
      verifyEq(EnerCubixHistoryData(EnerCubixMeterHistory.loadDb(db,point,at,at+1min)).read(at,at+1min).value,10f)
      verifyNull(EnerCubixMeterHistory.loadDb(db,point,at-1hr,at))
    }
  }

  Void testMembershipMidMinuteUsesCurrentMembersForTheWholeMinute()
  {
    withDb |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z")
      meter(db,"total",null,true); meter(db,"a","total"); meter(db,"b",null)
      counters(db,"a",at,10sec,5000f,1f); counters(db,"b",at,15sec,90000f,1f)
      EnerCubixMeterTimeline.initialize(db,at)
      EnerCubixMeterGeneration.update(db,at)
      prior:=db.readById(Ref("b")); edits:=[Diff(prior,Etc.makeDict(["enerCubixMeterParentRef":Ref("total")]))]
      edits.addAll(EnerCubixMeterTimeline.capture(db,edits,at+30sec)); db.commitAll(edits)
      EnerCubixMeterGeneration.update(db,at+3min)
      data:=EnerCubixMeterHistory.loadDb(db,db.readById(Ref("total-p")),at,at+1min)
      value:=EnerCubixHistoryData(data).read(at,at+1min)
      verifyEq(value.value,10f); verifyEq(value.quality,"derived")
    }
  }

  Void testFormulaAndNestedVirtualConsumePublishedOwnIntervals()
  {
    withDb |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z")
      meter(db,"root",null,true); meter(db,"virtual","root",true); meter(db,"a","virtual")
      counters(db,"a",at,10sec,100f,1f)
      expr:=Str:Obj?["id":"expr","kind":"expression","name":"twice","formula":"a * 2","variables":["a":"virtual"]]
      db.commit(Diff.makeAdd(Etc.makeDict(["enerCubix":Marker.val,"enerCubixKind":"expression","dis":"twice","enerCubixConfig":JsonOutStream.writeJsonToStr(expr)]),Ref("expr")))
      tags:=Str:Obj?["equip":Marker.val,"enerCubix":Marker.val,"enerCubixKind":"meter","enerCubixAlias":"formula","dis":"formula","enerCubixExpressionRef":Ref("expr"),"enerCubixCategoryRef":Ref("cat"),"enerCubixUnit":"kWh","enerCubixAutoSum":false]
      db.commit(Diff.makeAdd(Etc.makeDict(tags),Ref("formula")))
      EnerCubixMeterTimeline.initialize(db,at)
      EnerCubixMeterGeneration.update(db,at); EnerCubixMeterGeneration.update(db,at+3min)
      archived:=EnerCubixMeterHistory.loadDb(db,db.readById(Ref("virtual-p")),at,at+1min)
      root:=EnerCubixMeterHistory.loadDb(db,db.readById(Ref("root-p")),at,at+1min)
      formulaPoint:=db.readById(EnerCubixMeterHistory.formulaId(Ref("formula")))
      formula:=EnerCubixMeterHistory.loadDb(db,formulaPoint,at,at+1min)
      verifyEq(EnerCubixHistoryData(archived).read(at,at+1min).value,6f)
      verifyEq(EnerCubixHistoryData(root).read(at,at+1min).value,6f)
      verifyEq(EnerCubixHistoryData(formula).read(at,at+1min).value,12f)
      verifyFalse(formulaPoint.has("hisTotalized")); verify(formulaPoint.has("enerCubixFormulaResult"))
    }
  }

  Void testGenerationInterpolationIsExplicitAndMissingStaysMissing()
  {
    at:=DateTime.fromIso("2026-10-25T00:00:00Z")
    rows:=[Str:Obj?["from":(at-5sec).toIso,"to":(at+65sec).toIso,"value":70f,"valueType":"number","quality":"cleaned"]]
    v:=EnerCubixMeterGeneration.consume(rows,at,at+1min,["own"])
    verifyEq(v.value,60f); verifyEq(v.quality,"estimated")
    rows[0]["value"]=null; rows[0]["valueType"]="na"; rows[0]["quality"]="na"
    v=EnerCubixMeterGeneration.consume(rows,at,at+1min,["own"])
    verifyNull(v.value); verifyEq(v.quality,"na")
    rows[0]["from"]=(at+1sec).toIso; rows[0]["valueType"]="null"; rows[0]["quality"]="missing"
    verifyNull(EnerCubixMeterGeneration.consume(rows,at,at+1min,["own"]).value)
  }

  Void testPhysicalCleaningArchiveFreezesOldProfileAndContinuesAfterDisable()
  {
    withDb |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z")
      meter(db,"physical",null)
      profile:=profile(db,1000f,1)
      eq:=db.readById(Ref("physical"))
      db.commit(Diff(eq,Etc.makeDict(["enerCubixCleaningEnabled":Marker.val,"enerCubixCleaningProfileRef":Ref("profile")])))
      point:=db.readById(Ref("physical-p"))
      db.commit(Diff(point,Etc.makeDict(["modbusConnRef":Ref("conn"),"hisFunc":"enerCubixCleanHis","hisFuncConfig":Etc.makeDict(["deltaMin":Number(0),"deltaMax":Number(1000),"defNull":Marker.val]) ])))
      counters(db,"physical",at,10sec,5000f,1f)
      EnerCubixMeterTimeline.initialize(db,at); EnerCubixMeterGeneration.update(db,at)
      EnerCubixMeterGeneration.update(db,at+2min)
      v:=EnerCubixHistoryData(EnerCubixMeterHistory.loadDb(db,point,at,at+1min)).read(at,at+1min)
      verifyEq(v.value,6f); verifyEq(v.quality,"cleaned")
      rawBefore:=HisItem[,]; db.his.read(point.id,null,null) |item| {rawBefore.add(item)}
      changed:=profileMap(0.5f,2)
      edits:=[Diff(db.readById(Ref("profile")),Etc.makeDict(["enerCubixConfig":JsonOutStream.writeJsonToStr(changed)]))]
      edits.addAll(EnerCubixMeterTimeline.capture(db,edits,at+1min)); db.commitAll(edits)
      EnerCubixMeterGeneration.update(db,at+4min)
      verifyEq(EnerCubixHistoryData(EnerCubixMeterHistory.loadDb(db,point,at,at+1min)).read(at,at+1min).value,6f)
      v=EnerCubixHistoryData(EnerCubixMeterHistory.loadDb(db,point,at+1min,at+2min)).read(at+1min,at+2min)
      verifyNull(v.value); verifyEq(v.quality,"filtered")
      edits=[Diff(db.readById(Ref("physical")),Etc.makeDict(["enerCubixCleaningEnabled":Remove.val]))]
      edits.addAll(EnerCubixMeterTimeline.capture(db,edits,at+3min)); db.commitAll(edits)
      EnerCubixMeterGeneration.update(db,at+5min)
      v=EnerCubixHistoryData(EnerCubixMeterHistory.loadDb(db,point,at+3min,at+4min)).read(at+3min,at+4min)
      verifyEq(v.value,6f); verifyEq(v.quality,"derived")
      verifyEq(db.readById(point.id)["curVal"],Number(0f,Unit("kWh")))
      rawAfter:=HisItem[,]; db.his.read(point.id,null,null) |item| {rawAfter.add(item)}
      verifyEq(rawAfter.map |item->Str| {item.ts.toIso+"|"+item.val.toStr},rawBefore.map |item->Str| {item.ts.toIso+"|"+item.val.toStr})
    }
  }

  Void testExplicitRepairCascadesWithoutRewindingOrDoubleCounting()
  {
    withDb |db|
    {
      at:=DateTime.fromIso("2026-10-24T00:00:00Z")
      meter(db,"root",null,true); meter(db,"virtual","root",true); meter(db,"a","virtual")
      counters(db,"a",at,10sec,5000f,1f)
      db.his.write(Ref("a-p"),[HisItem(at+30sec,NA.val)],null).get(30sec)
      EnerCubixMeterTimeline.initialize(db,at); EnerCubixMeterGeneration.update(db,at); EnerCubixMeterGeneration.update(db,at+3min)
      root:=db.readById(Ref("root-p")); own:=db.readById(Ref("virtual-p"))
      verifyNull(EnerCubixHistoryData(EnerCubixMeterHistory.loadDb(db,root,at,at+1min)).read(at,at+1min).value)
      state:=db.readById(EnerCubixMeterHistory.stateId(root.id)); cursor:=state["enerCubixGenerationCursor"]; cumulative:=state["enerCubixGeneratedCumulative"]
      db.his.write(Ref("a-p"),[HisItem(at+30sec,Number(5003,Unit("kWh")))],null).get(30sec)
      records:=EnerCubixMeterTimeline.current(db)
      verifyEq(EnerCubixMeterGeneration.recalculate(db,records,at,at+1min),2)
      verifyEq(EnerCubixHistoryData(EnerCubixMeterHistory.loadDb(db,own,at,at+1min)).read(at,at+1min).value,6f)
      verifyEq(EnerCubixHistoryData(EnerCubixMeterHistory.loadDb(db,root,at,at+1min)).read(at,at+1min).value,6f)
      verifyEq(db.readById(state.id)["enerCubixGenerationCursor"],cursor)
      verifyEq(db.readById(state.id)["enerCubixGeneratedCumulative"],cumulative)
      corrections:=db.readAllList(Filter.has("enerCubixIntervalCorrection")).size
      verifyEq(corrections,2)
      EnerCubixMeterGeneration.recalculate(db,records,at,at+1min)
      verifyEq(db.readAllList(Filter.has("enerCubixIntervalCorrection")).size,corrections)
      verifyEq(db.readById(state.id)["enerCubixGeneratedCumulative"],cumulative)
      // Missing relationship logs do not block repair; unpublished intervals
      // remain untouched because the meter's own generation start is retained.
      verifyEq(EnerCubixMeterGeneration.recalculate(db,records,at-1min,at+1min),2)
      verifyNull(EnerCubixMeterHistory.loadDb(db,root,at-1min,at))
      verifyEq(db.readById(state.id)["enerCubixGeneratedCumulative"],cumulative)
    }
  }

  private Str:Obj? profileMap(Float max, Int version)
  { ["kind":"cleaningProfile","name":"profile","mode":"drop","version":version,"parameters":["deltaMin":0,"deltaMax":max,"defNull":true,"timeMax":"1h"]] }
  private Dict profile(Folio db, Float max, Int version)
  { db.commit(Diff.makeAdd(Etc.makeDict(["enerCubix":Marker.val,"enerCubixKind":"cleaningProfile","dis":"profile","enerCubixConfig":JsonOutStream.writeJsonToStr(profileMap(max,version))]),Ref("profile"))).newRec }

  Void testBadTargetDoesNotStarveOtherMeters()
  {
    withDb |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z")
      meter(db,"broken",null,true); meter(db,"good",null,true); meter(db,"a","good")
      counters(db,"a",at,10sec,10f,1f)
      occupied:=EnerCubixMeterHistory.usageId(Ref("broken-p"))
      db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"equipRef":Ref("unrelated"),"dis":"unrelated point"]),occupied))
      EnerCubixMeterTimeline.initialize(db,at)
      EnerCubixMeterGeneration.update(db,at); EnerCubixMeterGeneration.update(db,at+3min)
      value:=EnerCubixHistoryData(EnerCubixMeterHistory.loadDb(db,db.readById(Ref("good-p")),at,at+1min)).read(at,at+1min)
      verifyEq(value.value,6f)
      verify(db.readAllList(Filter.has("enerCubixGenerationIssue")).any |r| {r["enerCubixOwnerRef"] == Ref("broken") && r["enerCubixIssueActive"] == true})
      verifyEq(db.readById(occupied)["equipRef"],Ref("unrelated"))
    }
  }

  Void testOverflowRepairMovesTheOldRowAndUsesInstantIdentityAcrossTimezones()
  {
    withDb |db|
    {
      at:=DateTime.fromIso("2026-10-24T00:00:00Z")
      meter(db,"total",null,true); meter(db,"a","total")
      counters(db,"a",at,10sec,100f,1f)
      EnerCubixMeterTimeline.initialize(db,at); EnerCubixMeterGeneration.update(db,at); EnerCubixMeterGeneration.update(db,at+3min)
      point:=db.readById(Ref("total-p")); state:=db.readById(EnerCubixMeterHistory.stateId(point.id))
      hour:=db.readById(EnerCubixMeterHistory.batchId(point.id,at))
      rows:=EnerCubixMath.maps(JsonInStream(hour["enerCubixIntervals"].toStr.in).readJson)
      padding:=StrBuf(); for (i:=0;i<27000;i++) padding.addChar('x')
      rows[1]["retainedEvidence"]=padding.toStr
      json:=JsonOutStream.writeJsonToStr(rows); verify(json.size < 30000)
      db.commit(Diff(hour,Etc.makeDict(["enerCubixIntervals":json])))
      sources:=Str[,]
      for (i:=0;i<100;i++) sources.add("source-$i-abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
      local:=at.toTimeZone(TimeZone.fromStr("Shanghai"))
      EnerCubixMeterGeneration.publish(db,point,state,local,local+1min,EnerCubixValue(6f,"derived",sources),DateTime.now,false,true)
      data:=EnerCubixMeterHistory.loadDb(db,point,at,at+2min)
      verifyEq(EnerCubixMath.maps(data["intervals"]).size,2)
      verifyEq(EnerCubixHistoryData(data).read(at,at+2min).value,12f)
      kept:=EnerCubixMath.maps(JsonInStream(db.readById(hour.id)["enerCubixIntervals"].toStr.in).readJson)
      verifyFalse(kept.any |r| {DateTime.fromIso(r["from"].toStr).ticks == at.ticks})
      corrections:=db.readAllList(Filter.has("enerCubixIntervalCorrection")).size
      EnerCubixMeterGeneration.publish(db,point,db.readById(state.id),at,at+1min,EnerCubixValue(6f,"derived",sources),DateTime.now,false,true)
      verifyEq(db.readAllList(Filter.has("enerCubixIntervalCorrection")).size,corrections)
      verifyEq(db.readById(state.id)["enerCubixGenerationCursor"],at+2min)
      verifyEq(EnerCubixMeterHistory.batchId(point.id,at),EnerCubixMeterHistory.batchId(point.id,local))
    }
  }

  Void testSourceHistoryUnitWinsOverItsDisplayUnit()
  {
    withDb |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z")
      meter(db,"total",null,true); meter(db,"a","total")
      point:=db.readById(Ref("a-p"))
      db.commit(Diff(point,Etc.makeDict(["unit":"Wh"])))
      db.commit(Diff(db.readById(point.id),Etc.makeDict(["curVal":Number(0,Unit("Wh"))]),Diff.transient))
      counters(db,"a",at,10sec,5000000f,1000f,"Wh")
      EnerCubixMeterTimeline.initialize(db,at); EnerCubixMeterGeneration.update(db,at); EnerCubixMeterGeneration.update(db,at+3min)
      data:=EnerCubixMeterHistory.loadDb(db,db.readById(Ref("total-p")),at,at+1min)
      verifyEq(EnerCubixHistoryData(data).read(at,at+1min).value,6f)
      verifyEq(data["unit"],"kWh")
      verifyEq(db.readById(point.id)["unit"],"Wh")
    }
  }

  Void testFormulaKeepsEachVariablesCategoryUnitAndExplicitCoefficient()
  {
    withDb |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z")
      meter(db,"a",null); meter(db,"b",null)
      db.commit(Diff(db.readById(Ref("a")),Etc.makeDict(["enerCubixCategoryRef":Ref("whCat")])))
      db.commit(Diff(db.readById(Ref("a-p")),Etc.makeDict(["unit":"Wh"])))
      ["whCat":"Wh","cat":"kWh"].each |unit,id|
      {
        data:=Str:Obj?["kind":"category","name":id,"unit":unit]
        db.commit(Diff.makeAdd(Etc.makeDict(["enerCubix":Marker.val,"enerCubixKind":"category","dis":id,"enerCubixConfig":JsonOutStream.writeJsonToStr(data)]),Ref(id)))
      }
      expr:=Str:Obj?["kind":"expression","name":"formula","formula":"a / 1000 + b","variables":["a":"a","b":"b"]]
      db.commit(Diff.makeAdd(Etc.makeDict(["enerCubix":Marker.val,"enerCubixKind":"expression","dis":"formula","enerCubixConfig":JsonOutStream.writeJsonToStr(expr)]),Ref("expr")))
      db.commit(Diff.makeAdd(Etc.makeDict(["equip":Marker.val,"enerCubix":Marker.val,"enerCubixKind":"meter","dis":"formula","enerCubixAlias":"formula","enerCubixExpressionRef":Ref("expr"),"enerCubixCategoryRef":Ref("cat"),"enerCubixUnit":"Wh"]),Ref("formula")))
      counters(db,"a",at,10sec,5000000f,1000f,"Wh"); counters(db,"b",at,10sec,50f,1f)
      EnerCubixMeterTimeline.initialize(db,at); EnerCubixMeterGeneration.update(db,at); EnerCubixMeterGeneration.update(db,at+3min)
      point:=db.readById(EnerCubixMeterHistory.formulaId(Ref("formula")))
      data:=EnerCubixMeterHistory.loadDb(db,point,at,at+1min)
      verifyEq(EnerCubixHistoryData(data).read(at,at+1min).value,12f)
      verifyEq(data["unit"],"kWh")
    }
  }

  Void testIntervalChildIsNotDifferencedAgainAndHfTotalizedRawRemainsCounter()
  {
    withDb |db|
    {
      at:=DateTime.fromIso("2026-10-25T00:00:00Z")
      meter(db,"total",null,true); meter(db,"interval","total"); meter(db,"counter","total")
      ["interval","counter"].each |id|
      {
        db.commit(Diff(db.readById(Ref(id)),Etc.makeDict(["enerCubixHistoryMode":"interval"])))
        tags:=Str:Obj?["hisMode":"consumption","hisCollectInterval":Number(1,Unit("min"))]
        if (id == "counter") tags["hisFunc"]="hfTotalized"
        db.commit(Diff(db.readById(Ref(id+"-p")),Etc.makeDict(tags)))
      }
      rows:=HisItem[,]; counters:=HisItem[,]
      for (i:=0;i<=4;i++) {rows.add(HisItem(at+1min*i,Number(5,Unit("kWh")))); counters.add(HisItem(at+1min*i,Number(100f+i*7f,Unit("kWh"))))}
      db.his.write(Ref("interval-p"),rows,null).get(30sec); db.his.write(Ref("counter-p"),counters,null).get(30sec)
      EnerCubixMeterTimeline.initialize(db,at); EnerCubixMeterGeneration.update(db,at); EnerCubixMeterGeneration.update(db,at+3min)
      data:=EnerCubixMeterHistory.loadDb(db,db.readById(Ref("total-p")),at,at+1min)
      verifyEq(EnerCubixHistoryData(data).read(at,at+1min).value,12f)
      verifyEq(EnerCubixHistoryData(EnerCubixMeterHistory.loadDb(db,db.readById(Ref("total-p")),at+1min,at+2min)).read(at+1min,at+2min).value,12f)
    }
  }

  private Void meter(Folio db, Str id, Str? parent, Bool calculated:=false)
  {
    tags:=Str:Obj?["equip":Marker.val,"enerCubix":Marker.val,"enerCubixKind":"meter","enerCubixAlias":id,"dis":id,"enerCubixPointRef":Ref(id+"-p"),"enerCubixCategoryRef":Ref("cat"),"enerCubixUnit":"kWh","enerCubixAutoSum":calculated]
    if (parent != null) tags["enerCubixMeterParentRef"]=Ref(parent)
    db.commit(Diff.makeAdd(Etc.makeDict(tags),Ref(id)))
    point:=db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"hisTotalized":Marker.val,"unit":"kWh","kind":"Number","tz":"UTC","equipRef":Ref(id)]),Ref(id+"-p"))).newRec
    db.commit(Diff(point,Etc.makeDict(["curVal":Number(calculated ? 1000f : 0f,Unit("kWh")),"curStatus":"ok"]),Diff.transient))
  }
  private Void counters(Folio db, Str id, DateTime at, Duration cadence, Float baseline, Float step, Str unit:="kWh")
  {
    rows:=HisItem[,]
    for (i:=0;i<=4min.ticks/cadence.ticks;i++) rows.add(HisItem(at+cadence*i,Number(baseline+i*step,Unit(unit))))
    db.his.write(Ref(id+"-p"),rows,null).get(30sec)
  }
  private Void withDb(|Folio| work)
  {
    dir:=Env.cur.tempDir+`enerCubix-generation-test-${Uuid()}/`; dir.create
    db:=(Folio)Type.find("hxFolio::HxFolio").method("open").call(FolioConfig {name="generationTest";it.dir=dir;log=Log.get("generationTest")})
    try {work(db)} finally {db.close; dir.delete}
  }
}

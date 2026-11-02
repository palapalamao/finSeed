using haystack
using util

class EnerCubixCopConsumerTest : Test
{
  Void testRawQuantitiesAndPerHourNormalizedOperandsMatchOriginalCop()
  {
    [0,1,2,3,4,5,6,7].each |variant|
    {
      a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+2hr
      rs:=[Str:Obj?][["id":"cn","kind":"category","unit":"MWh"],["id":"cd","kind":"category","unit":"kWh"],["id":"s","kind":"space","nativeSourceKind":"site"],["id":"other","kind":"space","nativeSourceKind":"site"],["id":"n","kind":"meter","name":"Cooling","categoryId":"cn","pointId":"pn","spaceId":variant==2 ? "other" : "s"],["id":"d","kind":"meter","name":"Electricity","categoryId":"cd","pointId":"pd","spaceId":"s"],["id":"cop","kind":"cop","name":"System COP","numeratorId":"n","denominatorId":"d"]]
      if(variant==1) {rs[4]["expressionId"]="e";rs.add(["id":"e","kind":"expression","formula":"x","variables":["x":"d"]])}
      q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"space","nodeIds":["s"],"categoryIds":["cd"],"_cockpitCategoryId":"cd","period":"hour","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC"]
      prepared:=EnerCubixCockpitEfficiency.prepare(q,rs,"cubeTest",["cd","cn"])
      item:=EnerCubixMath.maps(prepared["items"]).first;verify(item!=null)
      points:=Str:Dict[:]
      ["pn","pd"].each |id| {points[id]=Etc.makeDict(["id":Ref(id),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":id=="pn" ? "MWh" : "kWh","tz":"UTC"])}
      configs:=Str:Dict[:]
      if(variant>=5)
      {
        cfg:=Etc.makeDict(variant==5 ? ["defNull":Marker.val,"deltaMax":Number(0.2f)] : ["defVal":variant==6 ? Number(0.05f) : NA.val,"deltaMax":Number(0.2f)])
        configs["pn"]=cfg;points["pn"]=Etc.makeDict(["id":Ref("pn"),"his":Marker.val,"hisTotalized":Marker.val,"unit":"MWh","tz":"UTC","hisFunc":"enerCubixCleanHis","hisFuncConfig":cfg])
      }
      read:=|Dict point,Span span,|HisItem| sink|
      {
        if(variant==1 && point.id.id=="pn") return
        (0..2).each |i|
        {
          at:=a+1hr*i;n:=variant==4 ? 0f : (variant>=5 && i==2 ? 1.5f : 0.1f*i)
          if(at>=span.start && at<span.end) sink(HisItem(at,Number(point.id.id=="pn" ? n : (variant==3 ? 0f : 10f*i*i))))
        }
      }
      histories:=EnerCubixCockpitStream.prepare(q,rs,points,configs,read,EnerCubixStreamBudget())
      reports:=Str:Obj?[:];modules:=Str:Obj?[:];boundary:=Str:Obj?["id":"boundary"]
      EnerCubixCockpitEfficiency.attach(prepared,histories,boundary,reports,modules)
      expectedItem:=EnerCubixMath.maps(((Map)((Map)modules["efficiency"])["data"])["items"]).first
      budget:=EnerCubixStreamBudget();model:=EnerCubixPreparedOwner(budget.state);state:=EnerCubixPreparedOwner(budget.state);output:=EnerCubixPreparedOwner(budget.state)
      catalog:=EnerCubixCockpitCatalog(rs.toImmutable,TimeZone.utc,model,["pn":"MWh","pd":"kWh"],true)
      actor:=EnerCubixCopConsumer(q.toImmutable,item.toImmutable,catalog,state,output)
      sources:=EnerCubixCockpitStream[,]
      try
      {
        planning:=EnerCubixContext.shared(catalog,"space",false,state)
        points.keys.sort.each |id| {sources.add(EnerCubixCockpitStream.openCursor(points[id],configs[id],a,b,q,rs,budget,read,planning))}
        (0..<2).each |i| {end:=a+1hr*(i+1);sources.each |source| {source.advance(end)};EnerCubixCockpitStream.withFrames(sources,budget.state) |h,frame| {actor.addFrame(h,frame)}}
        sources.each |source| {source.close};actual:=actor.finish
        actualReport:=(Map)actual["report"]
        verifyEq(json(actual["report"]),json(reports["cop:cop"]))
        ["numerator","denominator","ratio"].each |key|
        {
          value:=(EnerCubixValue)actual[key];expected:=(Map)expectedItem[key]
          verifyEq(value.value,expected["value"]);verifyEq(value.quality,expected["quality"]);verifyEq(value.sources,expected["sourceIds"])
        }
        // 100/10 and 200/40 aggregate to 300/50, not the mean of 10 and 5.
        // Scaling the final raw 0.1+0.2 would also change floating point order.
        if(variant==0) {verifyEq(((EnerCubixValue)actual["ratio"]).value,6f);verifyEq(((EnerCubixValue)actual["numerator"]).value,0.1f+0.2f)}
        if(variant==4) verifyEq(((EnerCubixValue)actual["ratio"]).value,0f)
        state.close;verifyEq(json(actual["report"]),json(reports["cop:cop"]))
        verifyEq(budget.state.unprepared.val,0)
        output.close;verify(actualReport.isEmpty)
      }
      finally {sources.each |source| {source.close};state.close;output.close;model.close}
      verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
    }
  }
  Void testTwoConfigurationsShareSourceClockAndKeepOriginalPrefixWarnings()
  {
    a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+2hr
    rs:=[Str:Obj?][["id":"cn","kind":"category","unit":"MWh"],["id":"cd","kind":"category","unit":"kWh"],["id":"s","kind":"space","nativeSourceKind":"site"],["id":"n","kind":"meter","name":"Cooling","categoryId":"cn","pointId":"pn","spaceId":"s"],["id":"x","kind":"meter","name":"Missing cooling","categoryId":"cn","pointId":"px","spaceId":"s"],["id":"d","kind":"meter","name":"Electricity","categoryId":"cd","pointId":"pd","spaceId":"s"],["id":"a","kind":"cop","name":"First COP","numeratorId":"x","denominatorId":"d"],["id":"b","kind":"cop","name":"Second COP","numeratorId":"n","denominatorId":"d"]]
    q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"space","nodeIds":["s"],"categoryIds":["cd"],"_cockpitCategoryId":"cd","period":"hour","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC"]
    prepared:=EnerCubixCockpitEfficiency.prepare(q,rs,"cubeTest",["cd","cn"])
    items:=EnerCubixMath.maps(prepared["items"]);verifyEq(items.size,2)
    points:=Str:Dict[:]
    ["pn","pd","px"].each |id| {points[id]=Etc.makeDict(["id":Ref(id),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":id=="pd" ? "kWh" : "MWh","tz":"UTC"])}
    read:=|Dict point,Span span,|HisItem| sink|
    {if(point.id.id=="px") return;(0..2).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) sink(HisItem(at,Number(point.id.id=="pn" ? 0.1f*i : 10f*i)))}}
    histories:=EnerCubixCockpitStream.prepare(q,rs,points,[:],read,EnerCubixStreamBudget())
    reports:=Str:Obj?[:];modules:=Str:Obj?[:];EnerCubixCockpitEfficiency.attach(prepared,histories,["id":"boundary"],reports,modules)
    budget:=EnerCubixStreamBudget();model:=EnerCubixPreparedOwner(budget.state);planning:=EnerCubixPreparedOwner(budget.state)
    catalog:=EnerCubixCockpitCatalog(rs.toImmutable,TimeZone.utc,model,[:],true)
    states:=EnerCubixPreparedOwner[,];outputs:=EnerCubixPreparedOwner[,];actors:=EnerCubixCopConsumer[,];sources:=EnerCubixCockpitStream[,]
    try
    {
      items.each |item| {state:=EnerCubixPreparedOwner(budget.state);output:=EnerCubixPreparedOwner(budget.state);states.add(state);outputs.add(output);actors.add(EnerCubixCopConsumer(q.toImmutable,item.toImmutable,catalog,state,output))}
      ctx:=EnerCubixContext.shared(catalog,"space",false,planning)
      points.keys.sort.each |id| {sources.add(EnerCubixCockpitStream.openCursor(points[id],null,a,b,q,rs,budget,read,ctx))}
      (0..<2).each |i| {end:=a+1hr*(i+1);sources.each |source| {source.advance(end)};EnerCubixCockpitStream.withFrames(sources,budget.state) |h,frame| {actors.each |actor| {actor.addFrame(h,frame)}}}
      sources.each |source| {source.close}
      first:=actors[0].finish;prefix:=(Str[])((Map)first["report"])["warnings"];verify(!prefix.isEmpty)
      second:=actors[1].finish(prefix)
      verifyEq(json(first["report"]),json(reports["cop:a"]));verifyEq(json(second["report"]),json(reports["cop:b"]))
      verifyEq(budget.nativeReads,3);verifyEq(budget.state.unprepared.val,0)
      states.each |state| {state.close};outputs[0].close
      verifyEq(json(second["report"]),json(reports["cop:b"]),"later warning/source arrays own their copy")
    }
    finally {sources.each |source| {source.close};states.each |state| {state.close};outputs.each |output| {output.close};planning.close;model.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
  Void testTwentyConfigurationsAndHundredPrimaryPointsKeepOwnedOutputWithinBudget()
  {
    a:=DateTime.fromIso("2026-01-01T00:00:00Z");b:=a+2hr
    rs:=[Str:Obj?][["id":"cn","kind":"category","unit":"MWh"],["id":"cd","kind":"category","unit":"kWh"],["id":"s","kind":"space","nativeSourceKind":"site"],["id":"gn","kind":"space","parentId":"s"],["id":"gd","kind":"space","parentId":"s"]]
    points:=Str:Dict[:]
    (0..<50).each |i|
    {
      ["n","d"].each |side|
      {
        id:=side+i;p:="p"+id
        rs.add(["id":id,"kind":"meter","categoryId":side=="n" ? "cn" : "cd","pointId":p,"spaceId":side=="n" ? "gn" : "gd","areaSource":"space","areaSpaceId":"s"])
        points[p]=Etc.makeDict(["id":Ref(p),"his":Marker.val,"hisMode":"consumption","hisCollectInterval":Number.makeDuration(1hr),"unit":side=="n" ? "MWh" : "kWh","tz":"UTC"])
      }
    }
    (0..<20).each |i| {rs.add(["id":"cop"+i,"kind":"cop","numeratorId":"gn","denominatorId":"gd"])}
    q:=Str:Obj?["kind":"profile","metric":"energy","dimension":"space","nodeIds":["s"],"categoryIds":["cd"],"_cockpitCategoryId":"cd","period":"day","from":a.toIso,"to":b.toIso,"asOf":b.toIso,"tz":"UTC"]
    prepared:=EnerCubixCockpitEfficiency.prepare(q,rs,"cubeTest",["cd","cn"]);items:=EnerCubixMath.maps(prepared["items"])
    verifyEq(items.size,20);verify(items.all |item| {item["reason"]==null})
    read:=|Dict point,Span span,|HisItem| sink|
    {(0..2).each |i| {at:=a+1hr*i;if(at>=span.start && at<span.end) {index:=point.id.id[2..-1].toInt+1;amount:=point.id.id.startsWith("pn") ? 0.001f*index*i : index.toFloat*(i+1);sink(HisItem(at,Number(amount)))}}}
    histories:=EnerCubixCockpitStream.prepare(q,rs,points,[:],read,EnerCubixStreamBudget())
    reports:=Str:Obj?[:];modules:=Str:Obj?[:];EnerCubixCockpitEfficiency.attach(prepared,histories,["id":"boundary"],reports,modules)
    budget:=EnerCubixStreamBudget();model:=EnerCubixPreparedOwner(budget.state);planning:=EnerCubixPreparedOwner(budget.state);peer:=EnerCubixPreparedOwner(budget.state)
    catalog:=EnerCubixCockpitCatalog(rs.toImmutable,TimeZone.utc,model,[:],true)
    states:=EnerCubixPreparedOwner[,];outputs:=EnerCubixPreparedOwner[,];actors:=EnerCubixCopConsumer[,];sources:=EnerCubixCockpitStream[,]
    try
    {
      items.each |item| {state:=EnerCubixPreparedOwner(budget.state);output:=EnerCubixPreparedOwner(budget.state);states.add(state);outputs.add(output);actors.add(EnerCubixCopConsumer(q.toImmutable,item.toImmutable,catalog,state,output))}
      ctx:=EnerCubixContext.shared(catalog,"space",false,planning)
      points.keys.sort.each |id| {sources.add(EnerCubixCockpitStream.openCursor(points[id],null,a,b,q,rs,budget,read,ctx))}
      (0..<2).each |i| {end:=a+1hr*(i+1);sources.each |source| {source.advance(end)};EnerCubixCockpitStream.withFrames(sources,budget.state) |h,frame| {actors.each |actor| {actor.addFrame(h,frame)}}}
      sources.each |source| {source.close}
      Str[] prefix:=Str[,]
      actors.each |actor,i|
      {
        data:=actor.finish(prefix);report:=(Map)data["report"];prefix=(Str[])report["warnings"]
        verifyEq(json(report),json(reports["cop:"+((Map)items[i]["config"])["id"]]))
        period:=(EnerCubixPeriodConsumer)EnerCubixCopConsumer#.field("period").get(actor)
        seen:=Obj[,];cells:=count(data,seen)+count(period.periods,seen)
        ["value","known","baseValue","baseKnown"].each |mode| {cells+=count(period.total(mode),seen)}
        verify(outputs[i].entries>=cells,"COP output containers, operand values and period rows are admitted: $cells / ${outputs[i].entries}")
      }
      verifyEq(budget.nativeReads,100);verifyEq(budget.state.unprepared.val,0);verify(budget.state.peak.val<=200000)
      states.each |state| {state.close};planning.close
      peer.hold(budget.state.remaining);peerEntries:=peer.entries
      outputs.each |output| {output.close};verifyEq(peer.entries,peerEntries)
    }
    finally {sources.each |source| {source.close};states.each |state| {state.close};outputs.each |output| {output.close};planning.close;model.close;peer.close}
    verifyEq(budget.state.temporary.val,0);verifyEq(budget.residentRaw,0)
  }
  private Int count(Obj? value,Obj[] seen)
  {
    if(value isnot Map && value isnot List && value isnot EnerCubixValue) return 0
    if(seen.any |root| {root===value}) return 0
    seen.add(value)
    if(value is EnerCubixValue) return 4+count(((EnerCubixValue)value).sources,seen)
    cells:=1+(value is Map ? ((Map)value).size : ((List)value).size)
    if(value is Map) ((Map)value).each |child| {cells+=count(child,seen)}
    else ((List)value).each |child| {cells+=count(child,seen)}
    return cells
  }
  private Obj? json(Obj? value) {JsonInStream(JsonOutStream.writeJsonToStr(value).in).readJson}
}

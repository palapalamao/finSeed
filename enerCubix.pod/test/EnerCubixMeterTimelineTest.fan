using haystack
using folio
using util

class EnerCubixMeterTimelineTest : Test
{
  Void testPointOnlyCleaningDiffDoesNotBecomeConfiguration()
  {
    withDb |db|
    {
      add(db,"total",null)
      point:=db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"equipRef":Ref("total")]),Ref("total-p"))).newRec
      at:=DateTime.fromIso("2026-10-25T10:00:00Z")
      EnerCubixMeterTimeline.initialize(db,at)
      changes:=[Diff(point,Etc.makeDict(["hisFunc":"enerCubixCleanHis","hisTotalized":Marker.val]))]
      verify(EnerCubixMeterTimeline.capture(db,changes,at+1min).isEmpty)
      changes.add(Diff(db.readById(Ref("total")),Etc.makeDict(["enerCubixCleaningEnabled":Marker.val])))
      extra:=EnerCubixMeterTimeline.capture(db,changes,at+1min)
      verifyEq(extra.size,2)
      changes.addAll(extra); db.commitAll(changes)
      verifyEq(EnerCubixMeterTimeline.recordsAt(db,at+2min).find |r| {r["id"] == "total"}["cleaningEnabled"],true)
    }
  }
  Void testCutoverIsUnknownBeforeActivationAndChangesAreEffective()
  {
    withDb |db|
    {
      add(db,"total",null); add(db,"a","total")
      at:=DateTime.fromIso("2026-10-25T10:00:00Z")
      EnerCubixMeterTimeline.initialize(db,at)
      segment:=EnerCubixMeterTimeline.segments(db,EnerCubixMeterTimeline.current(db),at-1hr,at+1hr)
      verifyEq(segment.size,2); verifyEq(segment[0]["known"],false); verifyEq(segment[1]["known"],true)
      old:=db.readById(Ref("a")); change:=Diff(old,Etc.makeDict(["enerCubixMeterParentRef":Remove.val]))
      diffs:=[change]; diffs.addAll(EnerCubixMeterTimeline.capture(db,diffs,at+30min)); db.commitAll(diffs)
      segment=EnerCubixMeterTimeline.segments(db,EnerCubixMeterTimeline.current(db),at,at+1hr)
      verifyEq(segment.size,2)
      verifyEq(EnerCubixMath.maps(segment[0]["records"]).find |r| {r["id"] == "a"}["meterParentId"],"total")
      verifyNull(EnerCubixMath.maps(segment[1]["records"]).find |r| {r["id"] == "a"}["meterParentId"])
      verifyEq(segment[0]["to"],(at+30min).toIso)
    }
  }

  Void testAddingAndRemovingDoesNotRewriteThePast()
  {
    withDb |db|
    {
      add(db,"total",null)
      at:=DateTime.fromIso("2026-10-25T10:00:00Z"); EnerCubixMeterTimeline.initialize(db,at)
      change:=Diff.makeAdd(Etc.makeDict(tags("late","total")),Ref("late"))
      diffs:=[change]; diffs.addAll(EnerCubixMeterTimeline.capture(db,diffs,at+1hr)); db.commitAll(diffs)
      verifyFalse(EnerCubixMeterTimeline.recordsAt(db,at+30min).any |r| {r["id"] == "late"})
      verify(EnerCubixMeterTimeline.recordsAt(db,at+90min).any |r| {r["id"] == "late"})
      old:=db.readById(Ref("late")); removal:=Diff(old,null,Diff.remove)
      diffs=[removal]; diffs.addAll(EnerCubixMeterTimeline.capture(db,diffs,at+2hr)); db.commitAll(diffs)
      verify(EnerCubixMeterTimeline.recordsAt(db,at+90min).any |r| {r["id"] == "late"})
      verifyFalse(EnerCubixMeterTimeline.recordsAt(db,at+3hr).any |r| {r["id"] == "late"})
    }
  }

  private Str:Obj? tags(Str id, Str? parent)
  {
    tags:=Str:Obj?["equip":Marker.val,"enerCubix":Marker.val,"enerCubixKind":"meter","dis":id,"enerCubixAlias":id,"enerCubixPointRef":Ref(id+"-p"),"enerCubixCategoryRef":Ref("cat")]
    if (parent != null) tags["enerCubixMeterParentRef"]=Ref(parent)
    return tags
  }
  private Void add(Folio db, Str id, Str? parent) {db.commit(Diff.makeAdd(Etc.makeDict(tags(id,parent)),Ref(id)))}
  private Void withDb(|Folio| work)
  {
    dir:=Env.cur.tempDir+`enerCubix-timeline-test-${Uuid()}/`; dir.create
    db:=(Folio)Type.find("hxFolio::HxFolio").method("open").call(FolioConfig {name="timelineTest";it.dir=dir;log=Log.get("timelineTest")})
    try {work(db)} finally {db.close; dir.delete}
  }
}

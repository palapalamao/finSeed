using haystack
using folio
using util

class FinEnergyMeterTimelineTest : Test
{
  Void testPointOnlyCleaningDiffDoesNotBecomeConfiguration()
  {
    withDb |db|
    {
      add(db,"total",null)
      point:=db.commit(Diff.makeAdd(Etc.makeDict(["point":Marker.val,"his":Marker.val,"equipRef":Ref("total")]),Ref("total-p"))).newRec
      at:=DateTime.fromIso("2026-10-25T10:00:00Z")
      FinEnergyMeterTimeline.initialize(db,at)
      changes:=[Diff(point,Etc.makeDict(["hisFunc":"finEnergyCleanHis","hisTotalized":Marker.val]))]
      verify(FinEnergyMeterTimeline.capture(db,changes,at+1min).isEmpty)
      changes.add(Diff(db.readById(Ref("total")),Etc.makeDict(["finEnergyCleaningEnabled":Marker.val])))
      extra:=FinEnergyMeterTimeline.capture(db,changes,at+1min)
      verifyEq(extra.size,2)
      changes.addAll(extra); db.commitAll(changes)
      verifyEq(FinEnergyMeterTimeline.recordsAt(db,at+2min).find |r| {r["id"] == "total"}["cleaningEnabled"],true)
    }
  }
  Void testCutoverIsUnknownBeforeActivationAndChangesAreEffective()
  {
    withDb |db|
    {
      add(db,"total",null); add(db,"a","total")
      at:=DateTime.fromIso("2026-10-25T10:00:00Z")
      FinEnergyMeterTimeline.initialize(db,at)
      segment:=FinEnergyMeterTimeline.segments(db,FinEnergyMeterTimeline.current(db),at-1hr,at+1hr)
      verifyEq(segment.size,2); verifyEq(segment[0]["known"],false); verifyEq(segment[1]["known"],true)
      old:=db.readById(Ref("a")); change:=Diff(old,Etc.makeDict(["finEnergyMeterParentRef":Remove.val]))
      diffs:=[change]; diffs.addAll(FinEnergyMeterTimeline.capture(db,diffs,at+30min)); db.commitAll(diffs)
      segment=FinEnergyMeterTimeline.segments(db,FinEnergyMeterTimeline.current(db),at,at+1hr)
      verifyEq(segment.size,2)
      verifyEq(FinEnergyMath.maps(segment[0]["records"]).find |r| {r["id"] == "a"}["meterParentId"],"total")
      verifyNull(FinEnergyMath.maps(segment[1]["records"]).find |r| {r["id"] == "a"}["meterParentId"])
      verifyEq(segment[0]["to"],(at+30min).toIso)
    }
  }

  Void testAddingAndRemovingDoesNotRewriteThePast()
  {
    withDb |db|
    {
      add(db,"total",null)
      at:=DateTime.fromIso("2026-10-25T10:00:00Z"); FinEnergyMeterTimeline.initialize(db,at)
      change:=Diff.makeAdd(Etc.makeDict(tags("late","total")),Ref("late"))
      diffs:=[change]; diffs.addAll(FinEnergyMeterTimeline.capture(db,diffs,at+1hr)); db.commitAll(diffs)
      verifyFalse(FinEnergyMeterTimeline.recordsAt(db,at+30min).any |r| {r["id"] == "late"})
      verify(FinEnergyMeterTimeline.recordsAt(db,at+90min).any |r| {r["id"] == "late"})
      old:=db.readById(Ref("late")); removal:=Diff(old,null,Diff.remove)
      diffs=[removal]; diffs.addAll(FinEnergyMeterTimeline.capture(db,diffs,at+2hr)); db.commitAll(diffs)
      verify(FinEnergyMeterTimeline.recordsAt(db,at+90min).any |r| {r["id"] == "late"})
      verifyFalse(FinEnergyMeterTimeline.recordsAt(db,at+3hr).any |r| {r["id"] == "late"})
    }
  }

  private Str:Obj? tags(Str id, Str? parent)
  {
    tags:=Str:Obj?["equip":Marker.val,"finEnergy":Marker.val,"finEnergyKind":"meter","dis":id,"finEnergyAlias":id,"finEnergyPointRef":Ref(id+"-p"),"finEnergyCategoryRef":Ref("cat")]
    if (parent != null) tags["finEnergyMeterParentRef"]=Ref(parent)
    return tags
  }
  private Void add(Folio db, Str id, Str? parent) {db.commit(Diff.makeAdd(Etc.makeDict(tags(id,parent)),Ref(id)))}
  private Void withDb(|Folio| work)
  {
    dir:=Env.cur.tempDir+`finEnergy-timeline-test-${Uuid()}/`; dir.create
    db:=(Folio)Type.find("hxFolio::HxFolio").method("open").call(FolioConfig {name="timelineTest";it.dir=dir;log=Log.get("timelineTest")})
    try {work(db)} finally {db.close; dir.delete}
  }
}

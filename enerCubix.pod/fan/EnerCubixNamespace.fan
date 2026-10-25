using haystack
using folio
using skyarcd
using hx
using alarmExt
using util

** Explicit administrator-only namespace upgrade. Record IDs and history stay intact.
class EnerCubixNamespace
{
  static Dict changes(Dict original, Str from, Str to)
  {
    out:=Str:Obj?[:]
    original.each |v,name|
    {
      target:=name.startsWith(from) ? to+name[from.size..-1] : name
      value:=rewrite(v,from,to)
      if (name == from+"Config" && v is Str)
        value=JsonOutStream.writeJsonToStr(rewrite(JsonInStream(v.toStr.in).readJson,from,to))
      if (name == "jobExpr" && v is Str)
        value=Regex("\\b"+from+"(?=[A-Z])").matcher(v.toStr).replaceAll(to)
      if (target != name)
      {
        if (original.has(target) && original[target] != value) throw ArgErr("Namespace target collision: "+target)
        out[name]=Remove.val; out[target]=value
      }
      else if (value != v) out[name]=value
    }
    if (original.has(from+"TaskLock")) out["dis"]="EnerCubix shared calculation lock"
    if (original["jobExpr"] == from+"Scheduled()") out["dis"]="EnerCubix hourly calculation and alarms"
    return Etc.makeDict(out)
  }

  private static Obj? rewrite(Obj? value, Str from, Str to)
  {
    if (value is Dict)
    {
      d:=(Dict)value
      edits:=changes(d,from,to)
      return edits.isEmpty ? d : merge(d,edits)
    }
    if (value is Map)
    {
      m:=(Map)value
      record:=m.containsKey(from) || m.containsKey(from+"Kind")
      result:=Str:Obj?[:]
      m.each |v,k|
      {
        name:=k.toStr
        target:=record && name.startsWith(from) ? to+name[from.size..-1] : name
        converted:=rewrite(v,from,to)
        if (result.containsKey(target) && result[target] != converted) throw ArgErr("Namespace snapshot collision: "+target)
        result[target]=converted
      }
      return result
    }
    if (value is List) return ((List)value).map |v->Obj?| { rewrite(v,from,to) }
    return value
  }

  private static Dict merge(Dict original, Dict edits)
  {
    out:=Etc.dictToMap(original)
    edits.each |v,k| { if (v == Remove.val) out.remove(k); else out[k]=v }
    return Etc.makeDict(out)
  }

  static Alarm? alarmChange(Dict original, Str from, Str to)
  {
    edits:=changes(original,from,to)
    return edits.isEmpty ? null : Alarm.wrap(merge(original,edits))
  }

  ** Preview before apply; the revision protects against changes after inspection.
  static Dict run(Str from, Str to, Bool apply, Str? expected)
  {
    cx:=Context.cur
    if (!cx.user.isAdmin) throw ArgErr("Administrator required")
    if (from == to || !Regex<|[a-z][A-Za-z0-9]*|>.matches(from) || !Regex<|[a-z][A-Za-z0-9]*|>.matches(to)) throw ArgErr("Invalid namespace")
    records:=cx.db.readAllList(Filter.has("id")).dup.sort |a,b->Int| { a.id.toStr <=> b.id.toStr }
    originals:=Dict[,]; diffs:=Diff[,]
    records.each |r|
    {
      edits:=changes(r,from,to)
      if (edits.isEmpty) return
      originals.add(r); diffs.add(Diff(r,edits))
    }
    alarmOriginals:=Dict[,]; alarmUpdated:=Alarm[,]
    AlarmFuncs.alarms().each |alarm|
    {
      updated:=alarmChange(alarm,from,to)
      if (updated == null) return
      alarmOriginals.add(alarm)
      alarmUpdated.add(updated)
    }
    before:=ZincWriter.gridToStr(Etc.makeDictsGrid(null,originals))
    alarmBefore:=ZincWriter.gridToStr(Etc.makeDictsGrid(null,alarmOriginals))
    revision:=(before+alarmBefore).toBuf.toDigest("SHA-256").toHex
    report:=Str:Obj?["project":cx.proj.name,"records":Number(diffs.size),"alarms":Number(alarmUpdated.size),"revision":revision,"applied":false]
    if (!apply) return Etc.makeDict(report)
    if (expected != revision) throw ArgErr("Namespace preview changed; inspect again")
    folder:=cx.proj.ioDir+`namespace-${Uuid()}/`
    folder.create
    (folder+`records.zinc`).out.print(before).close
    (folder+`alarms.zinc`).out.print(alarmBefore).close
    report["backup"]=folder.osPath
    // Both stores are backed up before the first mutation. Cross-store operations
    // are deliberately reported separately rather than claimed to be atomic.
    (folder+`progress.json`).out.print(JsonOutStream.writeJsonToStr(report)).close
    if (!diffs.isEmpty) cx.db.commitAll(diffs)
    report["recordsApplied"]=Number(diffs.size)
    (folder+`progress.json`).out.print(JsonOutStream.writeJsonToStr(report)).close
    if (!alarmUpdated.isEmpty)
    {
      AlarmLib alarmLib:=HxContext.curHx.rt.lib("alarm")
      alarmLib.db.createOrUpdate(alarmUpdated,false).get(30sec)
    }
    report["applied"]=true
    (folder+`progress.json`).out.print(JsonOutStream.writeJsonToStr(report)).close
    return Etc.makeDict(report)
  }
}

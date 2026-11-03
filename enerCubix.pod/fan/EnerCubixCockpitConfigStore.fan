using haystack
using folio
using util

** Owned configuration only. The manifest and the existing project-wide revision
** serialize validation plus config/audit changes in one native Folio transaction.
internal class EnerCubixCockpitConfigStore
{
  new make(Folio db,Str project,Ref projectRef,Str actor,Bool manage,
    |Dict->Bool| readable := |Dict r->Bool| {true},|Dict->Bool| writable := |Dict r->Bool| {true})
  {this.db=db;this.project=project;this.projectRef=projectRef;this.actor=actor;this.manage=manage;this.readable=readable;this.writable=writable}
  private EnerCubixPreparedOwner? captureOwner
  private Folio db
  private Str project
  private Ref projectRef
  private Str actor
  private Bool manage
  private |Dict->Bool| readable
  private |Dict->Bool| writable
  private static const Ref manifestId := Ref("enerCubix-cockpit-owned-config")
  private static const Ref revisionId := Ref("enerCubix-config-revision")
  private static const Str[] prohibited := ["point","his","equip","site","floor","enerCubixKind","enerCubixCockpitAudit","enerCubixCockpitManifest"]
  private static const Str[] common := ["id","mod","name","scopeKind","scopeRef","categoryRef","enabled"]
  private static const Str[] budgetFields := ["month","currency","amount","distribution","dailyAmounts"]
  private static const Str[] ruleFields := ["ruleType","calendarRef","threshold","thresholdUnit","currency"]
  private static const Str[] refs := ["scopeRef","categoryRef","calendarRef"]
  private static const Str[] persisted := ["scopeKind","scopeRef","categoryRef","enabled","month","currency","amount","distribution","dailyAmounts","ruleType","calendarRef","threshold","thresholdUnit","version","createdAt","updatedAt","effectiveAt","actor"]

  Str:Obj? list(Str type)
  {readRecords(type,false)}
  ** Server-only context for proving an invalid configuration unrelated. Native
  ** references in this context must never be returned by the public list DTO.
  Str:Obj? capture(Str type,EnerCubixPreparedOwner? owner := null)
  {
    captureOwner=owner
    try {return readRecords(type,true)}
    finally {captureOwner=null}
  }
  private Str:Obj? readRecords(Str type,Bool privateAttribution)
  {
    captureOwner?.hold(8)
    marker(type)
    manifest:=db.readById(manifestId,false)
    if(manifest == null) return ["records":[Str:Obj?][,],"complete":true,"canWrite":manage]
    requireManifest(manifest,false)
    complete:=true;out:=[Str:Obj?][,];attributions:=Str:Obj?[:]
    owned(manifest).each |ref|
    {
      r:=db.readById(ref,false)
      if(r == null || !r.has(marker(type))) return
      if(!readable(r)) {complete=false;return}
      try
      {
        requireOwned(r,type,manifest)
        dto:=dto(r,type)
        captureOwner?.hold(2+dto.size)
        try {v:=dto.dup;references(v,type);validateValue(v,type)}
        catch(ArgErr e) {if(privateAttribution) attributions[r.id.id]=attributionOf(r);dto=invalidDto(r,type,"OWNED_REFERENCE_INVALID")}
        catch(EnerCubixHttpErr e)
        {
          if([401,409,422,429,504].contains(e.status)) throw e
          if(e.status == 403) {complete=false;return}
          if(privateAttribution) attributions[r.id.id]=attributionOf(r)
          dto=invalidDto(r,type,"OWNED_REFERENCE_INVALID")
        }
        captureOwner?.hold(2);out.add(dto)
      }
      catch(ArgErr e) {complete=false}
      catch(EnerCubixHttpErr e) {if([401,409,422,429,504].contains(e.status)) throw e;complete=false}
    }
    result:=Str:Obj?["records":out,"complete":complete,"canWrite":manage]
    if(privateAttribution) result["attribution"]=attributions
    return result
  }

  Str:Obj? save(Str type,Str:Obj? input)
  {mutation:=planSave(type,input);apply(mutation);return dto(record(mutation.target),type)}
  Str:Obj? remove(Str type,Str id,Obj? mod)
  {
    requireWrite
    manifest:=db.readById(manifestId,false) ?: throw EnerCubixHttpErr(404,"NOT_FOUND","cockpitConfigNotFound")
    requireManifest(manifest,true);before:=record(ref(id));requireOwned(before,type,manifest);authorize(before,true);EnerCubixRepo.checkMod(before,mod)
    revision:=revisionBefore
    changes:=[Diff(before,null,Diff.remove)]
    changes.add(audit(type,before.id,"delete",before,Etc.emptyDict))
    appendGuards(changes,manifest,revision,owned(manifest))
    apply(EnerCubixOwnedMutation(before.id,changes))
    return ["deleted":before.id.id]
  }

  EnerCubixOwnedMutation planSave(Str type,Str:Obj? input)
  {
    requireWrite;allowed:=common.dup.addAll(type == "budget" ? budgetFields : ruleFields)
    if(input.keys.any |key| {!allowed.contains(key)}) throw ArgErr("cockpitConfigFields")
    ["id","mod","scopeRef","categoryRef","calendarRef"].each |key| {if(input[key] != null && input[key] isnot Str) throw ArgErr("cockpitConfigFields")}
    marker(type)
    // Both optimistic guards are captured before reading candidate configuration.
    revision:=revisionBefore;manifest:=db.readById(manifestId,false)
    if(manifest != null) requireManifest(manifest,true)
    previous:=input["id"] == null ? null : record(ref(input["id"].toStr))
    if(previous != null) {requireOwned(previous,type,manifest);authorize(previous,true);EnerCubixRepo.checkMod(previous,input["mod"])}
    value:=input.dup;value["name"]=(value["name"] as Str ?: "").trim
    if(value["name"].toStr.isEmpty || value["name"].toStr.size > 160 || value["enabled"] isnot Bool) throw ArgErr("cockpitConfigFields")
    references(value,type)
    validateValue(value,type)
    ids:=manifest == null ? Ref[,] : owned(manifest)
    ids.each |id|
    {
      r:=db.readById(id,false);if(r == null || !r.has(marker(type)) || r.id == previous?.id) return
      authorize(r,false);requireOwned(r,type,manifest)
      other:=dto(r,type)
      if(uniqueKey(other,type) == uniqueKey(value,type)) throw EnerCubixHttpErr(409,"CONFLICT","cockpitConfigDuplicate")
    }
    target:=previous?.id ?: qualify(Ref.gen)
    now:=DateTime.now
    tags:=Str:Obj?[marker(type):Marker.val,"enerCubixOwnedSchema":Number(1),"dis":value["name"],"version":Number(previous == null ? 1 : ((Number)previous["version"]).toInt+1),"createdAt":previous?.get("createdAt") ?: now,"updatedAt":now,"effectiveAt":now,"actor":actor]
    persisted.findAll |key| {value.containsKey(key)}.each |key|
    {
      v:=value[key]
      if(v == null) return
      if(key == "amount" || key == "threshold") v=Number(EnerCubixBudgetMath.number(v))
      if(key == "dailyAmounts") v=((List)v).map |n->Number| {Number(EnerCubixBudgetMath.number(n))}
      tags[key]=v
    }
    if(previous != null) persisted.each |key| {if(previous.has(key) && !tags.containsKey(key)) tags[key]=Remove.val}
    after:=Etc.makeDict(tags.findAll |v,k| {v isnot Remove}.set("id",target))
    changes:=[previous == null ? Diff.makeAdd(Etc.makeDict(tags),target.toRel(db.idPrefix)) : Diff(previous,Etc.makeDict(tags))]
    changes.add(audit(type,target,previous == null ? "create" : "update",previous ?: Etc.emptyDict,after))
    if(!ids.contains(target)) ids.add(target)
    appendGuards(changes,manifest,revision,ids)
    return EnerCubixOwnedMutation(target,changes)
  }
  private Void validateValue(Str:Obj? value,Str type)
  {
    if(value["enabled"] isnot Bool || (value["name"] as Str ?: "").trim.isEmpty) throw ArgErr("cockpitConfigFields")
    if(type == "budget") EnerCubixBudgetMath.validate(value)
    else
    {
      if(value["ruleType"] != "nonWorkingHighUsage" && value["ruleType"] != "budgetVariance") throw ArgErr("cockpitRuleType")
      EnerCubixBudgetMath.number(value["threshold"])
      if(value["ruleType"] == "nonWorkingHighUsage")
      {
        if(value["currency"] != null) throw ArgErr("cockpitRuleUnit")
        if(value["calendarRef"] == null) throw ArgErr("cockpitRuleCalendar")
        category:=record((Ref)value["categoryRef"]);data:=category["enerCubixConfig"] as Str
        unit:=category["unit"] as Str
        if(unit == null && data != null) unit=((Map)(captureOwner==null ? JsonInStream(data.in).readJson : EnerCubixOwnedJson.parse(data,captureOwner)))["unit"] as Str
        if((unit ?: "").trim.isEmpty || (value["thresholdUnit"] as Str ?: "").trim.isEmpty || EnerCubixMath.unitFactor(value["thresholdUnit"].toStr,unit) == null) throw ArgErr("cockpitRuleUnit")
      }
      else if(value["thresholdUnit"] != "%" || value["currency"] == null) throw ArgErr("cockpitRuleUnit")
    }
    if(value["currency"] != null && (value["currency"] isnot Str || !Regex<|[A-Z]{3}|>.matches(value["currency"].toStr))) throw ArgErr("cockpitConfigCurrency")
    if(type == "budget" && value["currency"] == null) throw ArgErr("cockpitConfigCurrency")
  }
  Void apply(EnerCubixOwnedMutation mutation)
  {
    requireWrite;EnerCubixHistorySafety.metadata(db,mutation.changes)
    try {db.commitAll(mutation.changes)}
    catch(Err e) {if(["ConcurrentChangeErr","DuplicateRecErr"].contains(e.typeof.name) || (e is CommitErr && e.msg.startsWith("Rec already exists:"))) throw EnerCubixHttpErr(409,"CONFLICT","cockpitConfigConflict");throw e}
  }
  Str:Obj? history(Str id)
  {
    target:=ref(id);manifest:=db.readById(manifestId,false)
    if(manifest == null || !owned(manifest).contains(target)) throw EnerCubixHttpErr(404,"NOT_FOUND","cockpitConfigNotFound")
    requireManifest(manifest,false)
    current:=db.readById(target,false)
    if(current != null) authorize(current,false)
    rows:=db.readAllList(Filter.has("enerCubixCockpitAudit")).findAll |r| {r["targetRef"] == target && readable(r)}
    rows.each |r| {["before","after"].each |key| {snapshot:=r[key] as Dict;if(snapshot != null && snapshot.has("scopeRef")) references((Str:Obj?)nativeJson(snapshot),r["configType"].toStr)}}
    return ["targetId":target.id,"records":rows.sort |a,b| {((Number)a["version"]).toInt <=> ((Number)b["version"]).toInt}.map |r->[Str:Obj?]| {["id":r.id.id,"version":nativeJson(r["version"]),"action":r["action"],"actor":r["actor"],"at":EnerCubixRepo.iso(r["at"]),"before":nativeJson(r["before"]),"after":nativeJson(r["after"])]}]
  }
  Bool referencesId(Str id)
  {
    target:=ref(id)
    manifest:=db.readById(manifestId,false);if(manifest == null) return false
    requireManifest(manifest,false)
    return owned(manifest).any |key|
    {
      r:=db.readById(key,false);if(r == null) return false
      authorize(r,false)
      return refs.any |field| {r[field] == target}
    }
  }

  private Void references(Str:Obj? value,Str type)
  {
    if(value["scopeKind"] != "project" && value["scopeKind"] != "space") throw ArgErr("cockpitConfigScope")
    scope:=ref(value["scopeRef"]?.toStr ?: "",value["scopeKind"] == "project")
    if(value["scopeKind"] == "project") {if(scope != projectRef) throw ArgErr("cockpitConfigProject")}
    else {r:=record(scope);authorize(r,false);if(!r.has("site") && !r.has("floor")) throw ArgErr("cockpitConfigScope")}
    value["scopeRef"]=scope
    ["categoryRef":"category","calendarRef":"calendar"].each |kind,field|
    {
      if(value[field] == null && field == "calendarRef") return
      target:=ref(value[field]?.toStr ?: "");r:=record(target);authorize(r,false)
      if(r["enerCubixKind"] != kind || !r.has("enerCubix")) throw ArgErr("cockpitConfigReference")
      value[field]=target
    }
  }
  private Dict? revisionBefore()
  {
    r:=db.readById(revisionId,false)
    if(r != null) {authorize(r,true);if(!r.has("enerCubixRevision") || prohibited.any |key| {r.has(key)}) throw EnerCubixHttpErr(409,"CONFLICT","cockpitConfigManifest")}
    return r
  }
  private Void appendGuards(Diff[] changes,Dict? manifest,Dict? revision,Ref[] ids)
  {
    m:=Etc.makeDict(["enerCubixCockpitManifest":Marker.val,"ownedRefs":ids,"version":Number(manifest == null ? 1 : ((Number)manifest["version"]).toInt+1)])
    changes.add(manifest == null ? Diff.makeAdd(m,manifestId) : Diff(manifest,m))
    r:=Etc.makeDict(["enerCubixRevision":Number(DateTime.nowTicks),"enerCubixUpdatedBy":actor])
    changes.add(revision == null ? Diff.makeAdd(r,revisionId) : Diff(revision,r))
  }
  private Diff audit(Str type,Ref target,Str action,Dict before,Dict after)
  {Diff.makeAdd(Etc.makeDict(["enerCubixCockpitAudit":Marker.val,"targetRef":target,"configType":type,"version":action == "delete" ? Number(((Number)before["version"]).toInt+1) : after["version"],"action":action,"actor":actor,"at":DateTime.now(null),"before":before,"after":after]))}
  private Void requireWrite() {if(!manage) throw EnerCubixHttpErr(403,"PERMISSION","cockpitConfigWriteForbidden")}
  private Void authorize(Dict r,Bool write) {if(!readable(r) || (write && !writable(r))) throw EnerCubixHttpErr(403,"PERMISSION","cockpitConfigForbidden")}
  private Void requireManifest(Dict r,Bool write)
  {authorize(r,write);if(!r.has("enerCubixCockpitManifest") || r["ownedRefs"] isnot List || r["version"] isnot Number || prohibited.exclude |k| {k == "enerCubixCockpitManifest"}.any |k| {r.has(k)}) throw EnerCubixHttpErr(409,"CONFLICT","cockpitConfigManifest")}
  private Void requireOwned(Dict r,Str type,Dict? manifest)
  {
    if(manifest == null || !owned(manifest).contains(r.id) || !r.has(marker(type)) || r["enerCubixOwnedSchema"] != Number(1) || r["version"] isnot Number || r["createdAt"] isnot DateTime || r.has(marker(type == "budget" ? "rule" : "budget")) || prohibited.any |key| {r.has(key)})
      throw EnerCubixHttpErr(403,"PERMISSION","cockpitConfigNotOwned")
  }
  private Ref[] owned(Dict manifest) {captureOwner?.hold(2*(1+((List)manifest["ownedRefs"]).size));return ((List)manifest["ownedRefs"]).map |v->Ref| {v as Ref ?: throw ArgErr("cockpitConfigManifest")}.dup}
  private Dict record(Ref ref) {db.readById(ref,false) ?: throw EnerCubixHttpErr(404,"NOT_FOUND","cockpitConfigNotFound")}
  private Ref qualify(Ref ref) {ref.id.startsWith(db.idPrefix) ? ref : Ref(db.idPrefix+ref.id)}
  private Ref ref(Str id,Bool projectScope := false)
  {
    if(projectScope && id == projectRef.id) return projectRef
    if(id.isEmpty || id.trim != id || id.any |c| {c.isSpace || c < 32} || (id.contains(":") && !id.startsWith("p:"+project+":r:"))) throw ArgErr("cockpitConfigProject")
    return qualify(Ref(id))
  }
  private static Str marker(Str type)
  {if(type != "budget" && type != "rule") throw ArgErr("cockpitConfigType");return type == "budget" ? "enerCubixBudget" : "enerCubixCockpitRule"}
  private static Str uniqueKey(Str:Obj? r,Str type)
  { ["scopeKind","scopeRef","categoryRef",type == "budget" ? "month" : "ruleType","currency"].map |k->Str| {nativeJson(r[k])?.toStr ?: ""}.join("|") }
  private Str:Obj? dto(Dict r,Str type)
  {
    captureOwner?.hold(6+persisted.size)
    out:=Str:Obj?["id":r.id.id,"mod":EnerCubixRepo.iso(r["mod"]),"name":r.dis,"type":type,"canWrite":manage && writable(r)]
    persisted.each |key| {if(r.has(key)) out[key]=nativeJson(r[key],captureOwner)}
    return out
  }
  private Str:Obj? invalidDto(Dict r,Str type,Str reason)
  {captureOwner?.hold(9);return ["id":r.id.id,"mod":EnerCubixRepo.iso(r["mod"]),"type":type,"name":r.dis,"validation":"invalid","reasonCodes":[reason]]}
  private Str:Obj? attributionOf(Dict r)
  {
    captureOwner?.hold(8)
    out:=Str:Obj?[:];month:=r["month"] as Str
    if(month != null) {try {EnerCubixBudgetMath.monthStart(month);out["month"]=month} catch(ArgErr e) {}}
    category:=attributionRef(r["categoryRef"])
    if(category != null) out["categoryRef"]=category.id
    scope:=attributionRef(r["scopeRef"],true);kind:=r["scopeKind"] as Str
    if(scope != null && (kind == "project" || kind == "space"))
    {
      out["scopeRef"]=scope.id;out["scopeKind"]=kind
      if(kind == "project") out["scopeReadable"]=scope == projectRef
      else {source:=db.readById(scope,false);out["scopeReadable"]=source != null && readable(source) && (source.has("site") || source.has("floor"))}
    }
    return out
  }
  private Ref? attributionRef(Obj? v,Bool projectScope := false)
  {if(v isnot Ref) return null;try {return ref(((Ref)v).id,projectScope)} catch(ArgErr e) {return null}}
  internal static Obj? nativeJson(Obj? v,EnerCubixPreparedOwner? owner := null)
  {
    if(v is Ref) return ((Ref)v).id
    if(v is Number) return ((Number)v).toFloat
    if(v is DateTime) return ((DateTime)v).toIso
    if(v is Dict) {count:=1;((Dict)v).each |value,key| {count++};owner?.hold(count);out:=Str:Obj?[:];((Dict)v).each |value,key| {out[key]=nativeJson(value,owner)};return out}
    if(v is List) {owner?.hold(1+((List)v).size);return ((List)v).map |item->Obj?| {nativeJson(item,owner)}}
    return v is Marker ? true : v
  }
}

internal class EnerCubixOwnedMutation
{
  new make(Ref target,Diff[] changes) {this.target=target;this.changes=changes}
  Ref target
  Diff[] changes
}

** Pure, repeatable preview. The caller owns permissions, revision and persistence.
** Sources are read-only native site rows (id=siteRef) or flattened point maps:
** pointId (or id), siteRef/siteName, floorRef/floorName, equipRef/equipName
** and native submeterOf (Str or Str[]).
const class SeedMigration
{
  static Str:Obj? plan([Str:Obj?][] all, [Str:Obj?][] sources := [Str:Obj?][,])
  {
    return SeedMigrationPlan(all,sources).build
  }
}

internal class SeedMigrationPlan
{
  private [Str:Obj?][] all
  private [Str:Obj?][] sources
  private Str:[Str:Obj?][] sourcesByPoint := [:]
  private Str:[Str:Obj?] work := [:]
  private Str:[Str:Obj?] proposedSpaces := [:]
  private Str[] warnings := [,]
  private Str[] conflictPoints := [,]
  private Str prefix := ""

  new make([Str:Obj?][] records, [Str:Obj?][] nativeSources)
  {
    all=records.dup.sort |a,b| { key(a) <=> key(b) }
    sources=nativeSources.dup.sort |a,b| { sourceSortKey(a) <=> sourceSortKey(b) }
    sources.each |s|
    {
      point:=sourceKey(s)
      if (!sourcesByPoint.containsKey(point)) sourcesByPoint[point]=[Str:Obj?][,]
      sourcesByPoint[point].add(s)
    }
    all.each |r| { work[key(r)]=r.dup }
    qualified:=all.find |r| { key(r).contains(":r:") }
    if (qualified != null) prefix=projectPrefix(key(qualified))
    else
    {
      qualified=sources.find |r| { sourceKey(r).contains(":r:") }
      if (qualified != null) prefix=projectPrefix(sourceKey(qualified))
    }
  }

  Str:Obj? build()
  {
    canonicalize
    assignSites
    nativeTopology
    suggestions:=[Str:Obj?][,]
    legacySuggestions(suggestions)
    floorSuggestions(suggestions)
    edits:=work.vals.findAll |r| { old:=all.find |a| { key(a) == key(r) }; return old == null || old != r }
    edits.sort |a,b| { key(a) <=> key(b) }
    added:=edits.findAll |r| { !all.any |a| { key(a) == key(r) } }
    return ["version":1,"records":edits,"suggestions":suggestions,"warnings":warnings.unique.sort,
      "counts":["added":added.size,"updated":edits.size-added.size,
      "canonicalAliases":edits.findAll |r| { r["canonicalId"] != null }.size,
      "spaces":added.findAll |r| { r["kind"] == "space" }.size,"suggestions":suggestions.size,
      "unboundMeters":meters.findAll |r| { r["canonicalId"] == null && r["spaceId"] == null }.size]]
  }

  private Void canonicalize()
  {
    points:=meters.map |r->Str| { r["pointId"] as Str ?: "" }.findAll |Str p->Bool| { !p.isEmpty }.unique.sort
    points.each |point|
    {
      aliases:=meters.findAll |r| { r["pointId"] == point }
      if (aliases.size < 2) return
      if (aliases.any |r| { r["categoryId"] != aliases.first["categoryId"] || r["expressionId"] != aliases.first["expressionId"] })
      {
        conflictPoints.add(point)
        warn("同一原始点 $point 的能源类型或表达式不一致，未自动建立兼容引用或归属")
        return
      }
      // Keep an already-consistent canonical choice stable after an earlier apply.
      targets:=aliases.map |r->Str| { r["canonicalId"] as Str ?: "" }.findAll |Str v->Bool| { !v.isEmpty }.unique
      chosen:=targets.size == 1 ? aliases.find |r| { key(r) == targets.first && r["canonicalId"] == null } : null
      if (chosen == null)
        chosen=aliases.dup.sort |a,b| { score(a) == score(b) ? key(a) <=> key(b) : score(a) <=> score(b) }.first
      chosen.remove("canonicalId")
      aliases.each |r| { if (key(r) != key(chosen)) r["canonicalId"]=key(chosen) }
    }
  }

  private Void assignSites()
  {
    // An explicit native site row can initialize an otherwise empty workbench.
    sources.findAll |s| { s["pointId"] == null && s["id"] != null && s["id"] == s["siteRef"] }.each |s|
    {
      ref:=s["siteRef"] as Str ?: ""
      if (!ref.isEmpty) space(ref,"site",s["siteName"] as Str ?: ref,null,true)
    }
    meters.each |r|
    {
      if (conflictPoints.contains(r["pointId"] as Str ?: "")) return
      s:=source(r)
      ref:=s?.get("siteRef") as Str ?: ""
      if (ref.isEmpty) return
      site:=space(ref,"site",s?.get("siteName") as Str ?: ref,null,true)
      if (site != null && r["spaceId"] == null) r["spaceId"]=key(site)
    }
  }

  private Void nativeTopology()
  {
    proposed:=Str:Str[:]
    meters.findAll |r| { r["canonicalId"] == null && ["meter","totalMeter"].contains(r["kind"]) }.each |r|
    {
      if (conflictPoints.contains(r["pointId"] as Str ?: "")) return
      s:=source(r); refs:=Str[,]
      v:=s?.get("submeterOf")
      if (v is Str && !((Str)v).isEmpty) refs.add((Str)v)
      else if (v is List) refs=SeedMath.strings(v).unique.sort
      if (refs.isEmpty) return
      candidates:=Str[,]; mappedAll:=true
      refs.each |ref|
      {
        mapped:=meters.findAll |m|
        {
          return m["canonicalId"] == null && ["meter","totalMeter"].contains(m["kind"]) &&
            m["categoryId"] == r["categoryId"] && (m["pointId"] == ref || source(m)?.get("equipRef") == ref)
        }
        if (mapped.size != 1) mappedAll=false
        mapped.each |m| { candidates.add(key(m)) }
      }
      candidates=candidates.unique.sort
      if (!mappedAll || candidates.size != 1 || candidates.first == key(r))
      {
        warn(r["name"].toStr+" 的原生 submeterOf 未唯一映射到同能源的上级主档案，保持未推断")
        return
      }
      if (r["meterParentId"] != null)
      {
        if (r["meterParentId"] != candidates.first) warn(r["name"].toStr+" 的现有上级与原生 submeterOf 不同，保留现有选择")
        return
      }
      proposed[key(r)]=candidates.first
    }
    proposed.keys.sort.each |id|
    {
      if (cycle(id,proposed[id],proposed)) warn(work[id]["name"].toStr+" 的原生 submeterOf 存在循环，未导入此关系")
      else work[id]["meterParentId"]=proposed[id]
    }
  }

  private Void legacySuggestions([Str:Obj?][] suggestions)
  {
    all.findAll |r| { r["kind"] == "group" }.each |group|
    {
      members:=descendants(key(group))
      name:=group["name"] as Str ?: key(group)
      building:=buildingName(name)
      floor:=floorName(name)
      if (members.isEmpty)
      {
        warn("旧分组“$name”没有绑定表计，保持未绑定")
        return
      }
      if (building != null || floor != null)
      {
        kind:=building != null ? "legacyBuilding" : "legacyFloor"
        parent:=commonSite(members)
        node:=space(key(group),kind,building ?: (floor ?: name),parent,false)
        if (node != null)
        {
          changes:=placement(node,members)
          if (!changes.isEmpty) suggestions.add(suggestion("legacySpace",key(group),"核实空间："+(building ?: floor),
            "仅根据旧分组名称提出候选空间；确认后才创建并批量放置表计，旧分组仍保留",changes,members,[key(group)]))
        }
      }
      else
      {
        s:=suggestion("legacyGroup",key(group),"选择“$name”的实际空间",
          "功能或用途分组不能直接视为建筑或楼层；请在空间树中选择实际覆盖位置",[Str:Obj?][,],members,[key(group)])
        s["placementRequired"]=true
        suggestions.add(s)
      }
      // A known legacy import pattern is useful as an explicit batch proposal only.
      if (name.contains("楼水表")) topologySuggestion(group,members,suggestions)
    }
  }

  private Void floorSuggestions([Str:Obj?][] suggestions)
  {
    refs:=meters.map |r->Str| { source(r)?.get("floorRef") as Str ?: "" }.findAll |Str v->Bool| { !v.isEmpty }.unique.sort
    refs.each |ref|
    {
      members:=meters.findAll |r| { r["canonicalId"] == null && source(r)?.get("floorRef") == ref }
      if (members.isEmpty) return
      s:=source(members.first)
      node:=space(ref,"floor",s?.get("floorName") as Str ?: ref,commonSite(members),false)
      if (node == null) return
      changes:=placement(node,members)
      if (!changes.isEmpty) suggestions.add(suggestion("nativeFloor",ref,"核实原生楼层："+node["name"],
        "原生 floorRef 可能是功能分组，需确认真实空间含义后再创建空间并放置表计",changes,members,[ref]))
    }
  }

  private Void topologySuggestion([Str:Obj?] group, [Str:Obj?][] members, [Str:Obj?][] suggestions)
  {
    masters:=members.findAll |r| { r["kind"] == "totalMeter" && score(r) == 0 }
    if (masters.size != 1) return
    master:=masters.first
    proposed:=Str:Str[:]
    members.each |r|
    {
      if (key(r) != key(master) && ["meter","totalMeter"].contains(r["kind"]) &&
          r["categoryId"] == master["categoryId"] && r["meterParentId"] == null && !conflictPoints.contains(r["pointId"] as Str ?: ""))
        proposed[key(r)]=key(master)
    }
    changes:=[Str:Obj?][,]
    proposed.keys.sort.each |id|
    {
      if (cycle(id,key(master),proposed)) return
      rec:=work[id].dup; rec["meterParentId"]=key(master); changes.add(rec)
    }
    if (changes.isEmpty) return
    s:=suggestion("meterTopology",key(group),"确认“"+group["name"]+"”的 ${changes.size} 块分表上级",
      "旧水表分组及设备包装层仅形成候选批量关系；总表采用同源点的计量主档案，必须人工确认",changes,members,[key(group)])
    s["parentId"]=key(master)
    suggestions.add(s)
  }

  ** Optional proposals are separate from automatic work and never leak into records.
  private [Str:Obj?]? space(Str sourceId, Str kind, Str name, Str? parent, Bool automatic)
  {
    // Preserve any previously persisted migration identity when ID encoding changes.
    matching:=work.vals.findAll |r| { r["kind"] == "space" && r["migrationSourceId"] == sourceId && r["migrationSourceKind"] == kind }.sort |a,b| { key(a) <=> key(b) }
    if (!matching.isEmpty) return matching.first
    // FIN 5.3 Folio accepts local add IDs up to 60 characters. The repository
    // localizes this qualified preview Ref at Diff.makeAdd; this suffix is 54.
    digest:=(kind+"\n"+sourceId).toBuf.toDigest("SHA-256").toHex[0..<40]
    id:=prefix+"finseed-space-"+digest
    existing:=work[id]
    if (existing != null)
    {
      if (existing["kind"] == "space" && existing["migrationSourceId"] == sourceId && existing["migrationSourceKind"] == kind) return existing
      warn("迁移空间标识 $id 已被其他记录使用，未覆盖")
      return null
    }
    if (proposedSpaces.containsKey(id)) return proposedSpaces[id]
    title:=name.trim.isEmpty ? sourceId : name.trim
    if (title.size > 145) title=title[0..<145]
    candidate:=title; suffix:=1
    while (work.vals.dup.addAll(proposedSpaces.vals).any |r| { r["kind"] == "space" && r["parentId"] == parent && r["name"] == candidate })
      candidate=title+" ("+(++suffix)+")"
    rec:=Str:Obj?["id":id,"kind":"space","name":candidate,"migrationSourceId":sourceId,"migrationSourceKind":kind,"migrationVersion":1]
    if (parent != null) rec["parentId"]=parent
    if (automatic) work[id]=rec
    else proposedSpaces[id]=rec
    return rec
  }

  private [Str:Obj?][] placement([Str:Obj?] node, [Str:Obj?][] members)
  {
    changes:=[Str:Obj?][,]
    members.each |r|
    {
      if (r["spaceId"] == key(node) || conflictPoints.contains(r["pointId"] as Str ?: "")) return
      current:=work[r["spaceId"] as Str ?: ""]
      if (current != null && current["migrationSourceKind"] != "site") return
      rec:=r.dup; rec["spaceId"]=key(node); changes.add(rec)
    }
    if (changes.isEmpty) return changes
    if (work[key(node)] == null) changes.insert(0,node)
    return changes
  }

  private [Str:Obj?] suggestion(Str type, Str sourceId, Str title, Str reason,
    [Str:Obj?][] changes, [Str:Obj?][] members, Str[] sourceIds)
  {
    patches:=changes.findAll |r| { work[key(r)] != null }.map |r->[Str:Obj?]|
    {
      before:=work[key(r)]; patch:=Str:Obj?["id":key(r)]
      r.each |v,k| { if (before[k] != v) patch[k]=v }
      return patch
    }
    return ["id":"finseed-"+type+"-"+safe(sourceId),"type":type,"title":title,"reason":reason,
      "requiresConfirmation":true,"records":changes,"patches":patches,"recordIds":members.map |r->Str| { key(r) }.unique.sort,
      "sourceIds":sourceIds,"count":changes.findAll |r| { r["kind"] != "space" }.size]
  }

  private [Str:Obj?][] descendants(Str id)
  {
    pending:=[id]; seen:=Str[,]; result:=Str[,]
    while (!pending.isEmpty)
    {
      current:=pending.removeAt(0)
      if (seen.contains(current)) continue
      seen.add(current)
      all.findAll |r| { r["parentId"] == current }.each |r|
      {
        if (r["kind"] == "group") pending.add(key(r))
        else if (SeedRelations.meterKinds.contains(r["kind"])) result.add(work[key(r)]["canonicalId"] as Str ?: key(r))
      }
    }
    return result.unique.sort.findAll |k| { work[k] != null && SeedRelations.meterKinds.contains(work[k]["kind"]) }.map |k->[Str:Obj?]| { work[k] }
  }

  private Str? commonSite([Str:Obj?][] members)
  {
    sites:=Str[,]; missing:=false
    members.each |r|
    {
      current:=r["spaceId"] as Str ?: ""; seen:=Str[,]; found:=false
      while (!current.isEmpty && !seen.contains(current))
      {
        seen.add(current); node:=work[current]
        if (node == null) break
        if (node["migrationSourceKind"] == "site") { sites.add(current); found=true; break }
        current=node["parentId"] as Str ?: ""
      }
      if (!found) missing=true
    }
    sites=sites.unique
    return sites.size == 1 && !missing ? sites.first : null
  }

  private [Str:Obj?]? source([Str:Obj?] rec)
  {
    point:=rec["pointId"] as Str ?: ""
    if (point.isEmpty) return null
    matches:=sourcesByPoint[point]
    if (matches == null || matches.isEmpty) return null
    first:=matches.first
    if (matches.any |s| { ["siteRef","floorRef","equipRef","submeterOf"].any |k| { s[k] != first[k] } })
    {
      warn("原始点 $point 的来源元数据相互冲突，未自动推断归属")
      return null
    }
    return first
  }

  private Bool cycle(Str id, Str parent, Str:Str proposed)
  {
    seen:=[id]; current:=parent
    while (!current.isEmpty)
    {
      if (seen.contains(current)) return true
      seen.add(current)
      current=proposed[current] ?: (work[current]?.get("meterParentId") as Str ?: "")
    }
    return false
  }

  private [Str:Obj?][] meters() { work.vals.findAll |r| { SeedRelations.meterKinds.contains(r["kind"]) }.sort |a,b| { key(a) <=> key(b) } }
  private static Int score([Str:Obj?] r) { r["kind"] == "totalMeter" && r["includeInTotals"] != false && r["active"] != false && r["enabled"] != false ? 0 : 1 }
  private static Str key([Str:Obj?] r) { r["id"] as Str ?: "" }
  private static Str sourceKey([Str:Obj?] r) { r["pointId"] as Str ?: (r["id"] as Str ?: "") }
  private static Str sourceSortKey([Str:Obj?] r)
  {
    return ["pointId","id","siteRef","siteName","floorRef","floorName","equipRef","equipName","submeterOf"].map |k->Str| { r[k]?.toStr ?: "" }.join("|")
  }
  private static Str projectPrefix(Str id) { id[0..<((id.index(":r:") ?: -3)+3)] }
  private Void warn(Str message) { if (!warnings.contains(message)) warnings.add(message) }

  ** Escape every non-ASCII-alphanumeric character, including hyphens. This is
  ** injective, deterministic and Ref-safe without a clock, counter or hash.
  private static Str safe(Str value)
  {
    out:=StrBuf()
    value.each |c|
    {
      if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) out.addChar(c)
      else out.add("-").add(c.toHex).add("-")
    }
    return out.toStr
  }

  private static Str? buildingName(Str name)
  {
    pos:=name.index("楼")
    if (pos != null && pos > 0 && name[0..<pos].any |c| { c.isDigit }) return name[0..pos]
    if (name.endsWith("栋") || name.endsWith("楼")) return name
    return null
  }
  private static Str? floorName(Str name)
  {
    upper:=name.upper
    if (upper.endsWith("F") && upper.any |c| { c.isDigit } && upper.all |c| { c.isDigit || c == 'F' || c == 'B' || c == '-' }) return name
    if (name.endsWith("层") && name.any |c| { c.isDigit }) return name
    return null
  }
}

using haystack
using folio
using folio3
using concurrent

** Opens only copied Folio record files. Original archives are never restored,
** and passwords, project services, connectors and raw histories are not opened.
internal const class EnerCubixLegacyBackup
{
  static Str:Obj? read(File archive, Str expectedHash, Str prefix, Str[] ids)
  {
    if (!archive.exists || archive.size > 64*1024*1024) throw ArgErr("legacyTopologyBackupChanged")
    bytes:=archive.readAllBuf
    if (bytes.toDigest("SHA-256").toHex.upper != expectedHash.upper) throw ArgErr("legacyTopologyBackupChanged")
    temp:=Env.cur.tempDir.normalize + `enerCubix-legacy-${Uuid()}/`
    temp.create
    zip:=Zip.read(bytes.in);backupPool:=ActorPool();Folio? db:=null
    try
    {
      root:="/"+archive.basename+"/db/"
      DateTime? captured:=null;copied:=0;File? entry
      while ((entry=zip.readNext) != null)
      {
        name:=entry.uri.pathStr
        if (!name.startsWith("/")) name="/"+name
        if (!name.startsWith(root) || entry.isDir) continue
        rel:=name[root.size..-1]
        if (rel == "backup-meta.props")
        {
          captured=DateTime.fromStr(readLimited(entry.in,4096).in.readProps["ts"] ?: "",false)
          continue
        }
        if (rel != "folio.index" && !Regex<|data000/data-\d+-\d+\.p\d+|>.matches(rel)) continue
        data:=readLimited(entry.in,16*1024*1024-copied);copied+=data.size
        if (copied > 16*1024*1024) throw ArgErr("legacyTopologyBackupLimit")
        target:=(temp+Uri.fromStr(rel)).normalize
        if (!target.osPath.startsWith(temp.osPath)) throw ArgErr("legacyTopologyInvalidBackup")
        target.parent.create;target.out.writeBuf(data).close
      }
      if (captured == null || captured > DateTime.now) throw ArgErr("legacyTopologyInvalidBackup")
      if (!(temp+`folio.index`).exists) throw ArgErr("legacyTopologyInvalidBackup")
      config:=FolioConfig {name="enerCubixRecoveryRead";dir=temp;idPrefix=prefix;pool=backupPool;log=Log.get("enerCubixRecoveryRead");opts=Etc.makeDict(["replica":Marker.val])}
      db=Folio3.open(config)
      records:=[Str:Obj?][,]
      ids.each |id|
      {
        raw:=db.readById(Ref(id),false) ?: throw ArgErr("legacyTopologyMissingSource")
        r:=decode(raw);records.add(r)
        parent:=r["meterParentId"] as Str
        if (parent != null && !records.any |e| {e["id"] == parent}) records.add(decode(db.readById(Ref(parent))))
      }
      owners:=[Str:Obj?][,]
      records.each |r|
      {
        point:=r["pointId"] as Str
        if (point == null || owners.any |o| {o["pointId"] == point}) return
        p:=db.readById(Ref(point),false) ?: throw ArgErr("legacyTopologyMissingSource")
        owners.add(["pointId":point,"equipId":(p["equipRef"] as Ref)?.id,"unit":p["unit"]?.toStr,"his":p.has("his"),"point":p.has("point")])
      }
      return ["file":archive.name,"sha256":expectedHash.upper,"capturedAt":captured.toIso,"records":records,"pointOwners":owners]
    }
    finally
    {
      if (db != null) db.close
      backupPool.stop.join;zip.close
      // Only the UUID directory created above is recursively removed.
      if (temp.normalize.osPath.startsWith(Env.cur.tempDir.normalize.osPath) && temp.name.startsWith("enerCubix-legacy-")) temp.delete
    }
  }

  static Buf readLimited(InStream input,Int limit)
  {
    data:=Buf()
    try
    {
      while (data.size <= limit)
        if (input.readBuf(data,(limit-data.size+1).min(8192)) == null) return data.flip
      throw ArgErr("legacyTopologyBackupLimit")
    }
    finally {input.close}
  }

  static Str:Obj? decode(Dict raw)
  {
    tags:=Etc.dictToMap(raw)
    if (raw.has("seedKind") && !raw.has("enerCubixKind"))
    {
      normalized:=Str:Obj?[:]
      tags.each |v,k| {normalized[k == "seed" ? "enerCubix" : (k.startsWith("seed") ? "enerCubix"+k[4..-1] : k)]=v}
      tags=normalized
    }
    decoded:=EnerCubixRepo.decode(Etc.makeDict(tags))
    if (tags["enerCubixUpdatedAt"] != null) decoded["updatedAt"]=EnerCubixRepo.iso(tags["enerCubixUpdatedAt"])
    return decoded
  }
}

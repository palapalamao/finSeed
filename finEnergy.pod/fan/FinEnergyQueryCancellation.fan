using concurrent

** An active HTTP query can be cancelled by its own project/user session.
internal const class FinEnergyQueryCancellation
{
  private static const AtomicRef active := AtomicRef(Str:Obj?[:].toImmutable)
  private const Str key
  private const AtomicBool cancelled := AtomicBool(false)

  private new make(Str key) {this.key=key}

  static FinEnergyQueryCancellation? open(Str project,Str user,Str? id)
  {
    if(id==null) return null
    key:=scopeKey(project,user,id)
    query:=FinEnergyQueryCancellation(key)
    while(true)
    {
      before:=(Str:Obj?)active.val
      if(before.containsKey(key)) throw FinEnergyHttpErr(409,"QUERY_IN_PROGRESS","queryInProgress")
      after:=before.dup.set(key,query).toImmutable
      if(active.compareAndSet(before,after)) return query
    }
  }

  static Bool cancel(Str project,Str user,Str id)
  {
    query:=((Str:Obj?)active.val)[scopeKey(project,user,id)] as FinEnergyQueryCancellation
    if(query==null) return false
    query.cancelled.val=true
    return true
  }

  Void check()
  {
    if(cancelled.val) throw FinEnergyHttpErr(409,"QUERY_CANCELLED","queryCancelled")
  }

  Void close()
  {
    while(true)
    {
      before:=(Str:Obj?)active.val
      if(before[key]!==this) return
      after:=before.dup
      after.remove(key)
      if(active.compareAndSet(before,after.toImmutable)) return
    }
  }

  private static Str scopeKey(Str project,Str user,Str id)
  {
    if(!Regex<|[0-9a-f]{32}|>.matches(id)) throw ArgErr("queryRequestId")
    return "${project.size}:$project|${user.size}:$user|$id"
  }
}

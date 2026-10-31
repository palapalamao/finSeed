using concurrent

** A bounded native request admission gate; no queued work or background actors.
internal const class EnerCubixCockpitGate
{
  private static const AtomicRef active := AtomicRef(Str:Obj?[:].toImmutable)
  static Void enter(Str project, Str user)
  {
    while (true)
    {
      before:=(Str:Obj?)active.val
      users:=(Str[]?)before[project] ?: Str[,]
      if (users.contains(user) || users.size >= 2) throw EnerCubixHttpErr(429,"COCKPIT_BUSY","cockpitBusy")
      after:=before.dup.set(project,users.dup.add(user)).toImmutable
      if (active.compareAndSet(before,after)) return
    }
  }
  static Void leave(Str project, Str user)
  {
    while (true)
    {
      before:=(Str:Obj?)active.val
      users:=((Str[]?)before[project] ?: Str[,]).dup
      users.remove(user)
      after:=before.dup
      if (users.isEmpty) after.remove(project)
      else after[project]=users
      if (active.compareAndSet(before,after.toImmutable)) return
    }
  }
}

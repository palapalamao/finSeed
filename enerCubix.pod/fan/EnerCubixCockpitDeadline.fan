using concurrent

** One request-local monotonic deadline, including native preparation and projections.
** Atomic counters allow the same bounded state to survive immutable history capture.
internal const class EnerCubixCockpitDeadline
{
  new make(Duration timeout := 30sec, |->Int| clock := |->Int| {Duration.nowTicks})
  {this.timeout=timeout;this.clock=clock;started=clock()}
  const Duration timeout
  private const |->Int| clock
  private const Int started
  Void check() {if(clock()-started > timeout.ticks) throw EnerCubixHttpErr(504,"QUERY_TIMEOUT","cockpitQueryTimeout")}
}

internal const class EnerCubixPreparedBudget
{
  new make(EnerCubixCockpitDeadline deadline) {this.deadline=deadline}
  const EnerCubixCockpitDeadline deadline
  const AtomicInt prepared := AtomicInt()
  const AtomicInt temporary := AtomicInt()
  const AtomicInt peak := AtomicInt()
  const AtomicInt peakTemporary := AtomicInt()
  const AtomicInt lookups := AtomicInt()
  const AtomicInt sparseHits := AtomicInt()
  const AtomicInt unprepared := AtomicInt()
  const AtomicInt contextEmptyHits := AtomicInt()
  Void reserve(Int n := 1) {prepared.add(n);guard}
  Void hold(Int n) {temporary.add(n);peakTemporary.val=peakTemporary.val.max(temporary.val);guard}
  Int remaining() {(200000-prepared.val-temporary.val).max(0)}
  Void releaseTemporary(Int n)
  {
    if(n < 0 || n > temporary.val) throw ArgErr("preparedTemporaryOwnership")
    temporary.add(-n)
  }
  private Void guard()
  {
    total:=prepared.val+temporary.val;peak.val=peak.val.max(total)
    if(total > 200000) throw EnerCubixHttpErr(422,"PREPARED_READ_LIMIT","cockpitPreparedReadLimit")
  }
  Void lookup() {if(lookups.incrementAndGet % 128 == 0) deadline.check}
  Str:Obj? evidence() {["representationVersion":2,"preparedResidentEntries":prepared.val,"peakPreparedAndCacheEntries":peak.val,"peakContextEntries":peakTemporary.val,"lookupCount":lookups.val,"sparseLookupCount":sparseHits.val,"constantNullReuseCount":contextEmptyHits.val,"unpreparedLookupCount":unprepared.val,"preparedEntryLimit":200000]}
}

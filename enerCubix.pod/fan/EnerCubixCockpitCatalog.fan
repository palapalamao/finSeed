** One canonical request projection, shared by the three membership views.
** Its owner outlives every bound calculation/output owner; it owns no histories.
internal class EnerCubixCockpitCatalog
{
  new make([Str:Obj?][] source,TimeZone tz,EnerCubixPreparedOwner owner,Str:Str units := [:],Bool originalContext := false)
  {
    if(!source.isImmutable) throw ArgErr("catalogSourceNotFrozen")
    this.tz=tz;this.owner=owner
    owner.watch |->Void|
    {
      // A failed/partial close still has nonzero entries. Do not release the
      // model because an earlier callback ran while other roots remain alive.
      if(bindings.any |binding| {binding.entries!=0}) throw ArgErr("catalogStillBorrowed")
      views.clear;children.each |rows| {rows.clear};children.clear
      protectedRoots.clear;area?.clear;originalIndex?.clear;originalIndex=null;originalRecords=null;bindings.clear;pointUnits.clear;calendar=null;closed=true
    }
    owner.hold(18)
    owner.hold(1+units.size);pointUnits=units.dup
    projection=EnerCubixDimension.owned("metering",source,false,owner)
    if(originalContext)
    {
      // The ordinary COP context indexes original frozen records, independently
      // from its canonical Dimension. These record maps remain borrowed facts.
      originalRecords=source;owner.hold(1+source.size);originalIndex=Str:[Str:Obj?][:]
      source.each |r| {originalIndex[r["id"].toStr]=r}
    }
    owner.hold(3+2*records.size)
    scratch:=EnerCubixPreparedOwner(owner.budget)
    try {scratch.hold(4+(originalContext ? 3 : 2)*records.size);area=EnerCubixArea(originalContext ? originalIndex.vals : projection.records);index}
    finally {scratch.close}
    originalRecords?.each |r| {protect(r)}
    projection.records.each |r| {protect(r)}
  }
  const TimeZone tz
  EnerCubixPreparedOwner owner {private set}
  private EnerCubixDimension? projection
  private EnerCubixArea? area
  private [Str:Obj?][]? originalRecords
  private [Str:[Str:Obj?]]? originalIndex
  private Str:Str pointUnits := [:]
  private Str:EnerCubixDimension views := [:]
  internal Str:[Str:Obj?][] children := [:]
  internal [Str:Obj?]? calendar
  internal Obj[] protectedRoots := [,]
  private EnerCubixPreparedOwner[] bindings := [,]
  private Bool closed := false

  internal Str:[Str:Obj?] byId() {check;return originalIndex ?: projection.byId}
  internal [Str:Obj?][] records() {check;return originalRecords ?: projection.records}
  internal EnerCubixArea areas() {check;return area}
  internal Str? primaryUnit(Str id) {check;return pointUnits[id]}
  internal Void bind(EnerCubixPreparedOwner borrower)
  {
    check
    if(borrower===owner || borrower.budget!==owner.budget || borrower.entries==0) throw ArgErr("catalogBorrower")
    if(bindings.any |b| {b===borrower}) return
    // Keep the closed owner metadata charged while its reference is retained.
    owner.hold(6);bindings.add(borrower)
  }
  internal EnerCubixDimension view(Str dimension,Bool nativeSpace := false)
  {
    check
    if(!["space","metering","organization"].contains(dimension)) throw ArgErr("Invalid report dimension")
    nativeSpace=dimension=="space" && nativeSpace
    key:=dimension+"|"+nativeSpace
    if(!views.containsKey(key)) {owner.hold(10);views[key]=EnerCubixDimension.projected(dimension,projection,nativeSpace)}
    return views[key]
  }
  private Void index()
  {
    records.each |r|
    {
      parent:=r["parentId"] as Str
      if(parent==null) return
      if(!children.containsKey(parent)) {owner.hold(2);children[parent]=[Str:Obj?][,]}
      owner.hold(1);children[parent].add(r)
    }
    calendars:=records.findAll |r| {r["kind"]=="calendar"}
    defaults:=calendars.findAll |r| {r["isDefault"]==true}
    if(defaults.size==1) calendar=defaults.first
    else if(defaults.isEmpty && calendars.size==1) calendar=calendars.first
  }
  private Void protect(Obj? value)
  {
    if(value isnot Map && value isnot List) return
    if(protectedRoots.any |v| {v===value}) return
    owner.hold(1);protectedRoots.add(value)
    if(value is Map) ((Map)value).each |v| {protect(v)}
    else ((List)value).each |v| {protect(v)}
  }
  private Void check() {if(closed) throw ArgErr("catalogClosed")}
}

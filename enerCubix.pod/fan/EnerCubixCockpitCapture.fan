** Request-local diagnostic samples, never arithmetic input. Groups are declared
** before source reads. Late groups evict tails from overrepresented groups;
** parent reads and their retained interval children both consume the 1000 rows.
internal class EnerCubixCockpitCapture
{
  new make(Str:[Str:Obj?] plan,EnerCubixPreparedOwner owner)
  {
    if(plan.isEmpty || plan.size>1000) throw ArgErr("diagnosticPlan")
    this.owner=owner
    owner.watch |->Void|
    {
      if(bindings.any |b| {b.entries!=0}) throw ArgErr("diagnosticsStillBorrowed")
      groups.each |g| {while(!g.cells.isEmpty) remove(g);clear(g.spec);g.rows.clear}
      heads.each |m| {m.clear};heads.clear;metadataEntries.clear;envelopes.clear;byKind.clear;snapshot.clear;groups.clear;protectedRoots.clear;bindings.clear;closed=true
    }
    owner.hold(24)
    scratch:=EnerCubixPreparedOwner(owner.budget)
    try
    {
      scratch.hold(66+plan.size)
      plan.keys.sort.each |key|
      {
        spec:=plan[key]
        if(key.isEmpty || !["sourceUsage","cleaningEvents","coveragePeriods"].contains(spec["kind"])) throw ArgErr("diagnosticPlan")
        owner.hold(20+entries(spec,scratch,Obj[,]))
        g:=EnerCubixCockpitCaptureGroup((Str:Obj?)copy(spec),groups.size)
        groups[key]=g;protectedRoots.add(g.rows)
      }
    }
    finally {scratch.close}
  }
  private EnerCubixPreparedOwner owner
  private Str:EnerCubixCockpitCaptureGroup groups := [:]
  internal Obj[] protectedRoots := [,]
  private EnerCubixPreparedOwner[] bindings := [,]
  private Map[] heads := [,]
  private [Str:Obj?][] metadataEntries := [,]
  private EnerCubixCockpitCaptureEnvelope[] envelopes := [,]
  private Str:Int byKind := [:]
  private Str:Obj? snapshot := [:]
  private Int kept := 0
  private Bool closed := false
  private Bool frozen := false
  private Err? failure
  Int retainedRows() {check;return kept}
  internal EnerCubixPreparedBudget budget() {owner.budget}
  Void bind(EnerCubixPreparedOwner borrower)
  {
    check
    if(borrower===owner || borrower.budget!==owner.budget || borrower.entries==0) throw ArgErr("diagnosticBorrower")
    if(bindings.any |b| {b===borrower}) return
    owner.hold(6);bindings.add(borrower)
  }
  [Str:Obj?][] rows(Str key) {check;return group(key).rows}
  Str captureId(Str key) {check;return group(key).captureId}
  Str diagnosticId(Str key) {check;return "diagnostic-"+group(key).order}
  Void expect(Str key,Str kind)
  {check;g:=group(key);if(frozen || g.sealed || g.spec["kind"]!=kind) throw ArgErr("diagnosticGroupNotPlanned")}
  Bool canPutSimple(Str key)
  {
    check;g:=group(key)
    if(frozen || g.sealed || g.spec["kind"]=="sourceUsage") throw ArgErr("diagnosticSimpleGroup")
    if(kept<1000) return true
    return groups.any |other| {other!==g && other.weight>g.weight && other.weight-other.cells.last.weight>=g.weight}
  }
  Void skipSimple(Str key)
  {check;g:=group(key);if(frozen || g.sealed || g.spec["kind"]=="sourceUsage") throw ArgErr("diagnosticSimpleGroup");g.total++}
  Void seal(Str key,Bool countUnknown := false)
  {check;if(frozen) throw ArgErr("diagnosticsFrozen");g:=group(key);g.sealed=true;g.unknown=g.unknown || countUnknown}
  Void knownEnvelope(Str key,Str:Obj? target,EnerCubixPreparedOwner output,Int count,Bool emptyOmitted := false,Bool unpreparedOmitted := false)
  {
    check
    g:=group(key)
    if(frozen || target.isImmutable || count!=g.total || g.spec["kind"]!="sourceUsage") throw ArgErr("diagnosticEnvelope")
    bind(output);output.hold(14);owner.hold(8)
    envelopes.add(EnerCubixCockpitCaptureEnvelope(g,target,output,count,emptyOmitted,unpreparedOmitted))
    target["sourceUsage"]=g.rows;target["_capturePending"]=true
    g.unknown=g.unknown || emptyOmitted || unpreparedOmitted
  }

  Bool put(Str key,Str:Obj? row)
  {
    check
    g:=group(key)
    if(frozen || g.sealed) throw ArgErr("diagnosticsFrozen")
    EnerCubixPreparedOwner? scratch;EnerCubixPreparedOwner? allocation
    Bool stored:=false
    try
    {
      scratch=EnerCubixPreparedOwner(owner.budget)
      scratch.hold(64)
      g.total++
      children:=g.spec["kind"]=="sourceUsage" ? (row["intervals"] as List) : null
      childCount:=children?.size ?: 0
      advertised:=EnerCubixMath.num(row["intervalCount"])
      g.childTotal+=advertised==null ? childCount : advertised.toInt.max(childCount)
      g.childAvailable+=childCount
      if(children!=null && row["detailsTruncated"]==true && advertised==null) g.childUnknown=true
      if(children!=null && (row["detailsTruncated"]==true || (advertised!=null && advertised>childCount.toFloat))) g.childUpstream=true
      keep:=childCount.min((1000/groups.size-1).max(0));weight:=1+keep
      while(kept+weight>1000)
      {
        EnerCubixCockpitCaptureGroup? donor
        groups.each |candidate|
        {
          // A parent and its children are one detached graph. Removing its tail
          // must not push a donor below the receiving group's current weight.
          if(candidate!==g && candidate.weight>g.weight && candidate.weight-candidate.cells.last.weight>=g.weight &&
            (donor==null || candidate.weight>donor.weight || (candidate.weight==donor.weight && candidate.order<donor.order))) donor=candidate
        }
        if(donor==null) return false
        remove(donor)
      }
      // Count the selected diagnostic graph before allocating it. Only a known
      // root interval list is trimmed; all remaining maps/lists detach deeply.
      n:=1+row.size;path:=Obj[row]
      row.each |value,field|
      {
        if(field=="intervals" && children!=null)
        {n+=1+keep;for(i:=0;i<keep;i++) n+=entries(children[i],scratch,path)}
        else n+=entries(value,scratch,path)
      }
      allocation=EnerCubixPreparedOwner(owner.budget);allocation.hold(32+n)
      cell:=EnerCubixCockpitCaptureCell(allocation,weight)
      out:=Str:Obj?[:];cell.row=out
      row.each |value,field|
      {
        if(field=="intervals" && children!=null)
        {xs:=Obj?[,];for(i:=0;i<keep;i++) xs.add(copy(children[i]));out[field]=xs}
        else out[field]=copy(value)
      }
      if(children!=null && (keep<childCount || (advertised!=null && advertised>keep.toFloat)))
      {
        out["detailsTruncated"]=true
        if(keep<childCount || out["intervalsCaptureId"] isnot Str) out["intervalsCaptureId"]=Uuid().toStr
      }
      g.cells.add(cell);g.rows.add(out);g.weight+=weight;kept+=weight;stored=true
      return true
    }
    catch(Err e) {failure=e;throw e}
    finally {if(!stored) allocation?.close;scratch?.close}
  }

  Str:Obj? freeze()
  {
    check
    if(frozen) return snapshot
    if(groups.any |g| {!g.sealed}) throw ArgErr("diagnosticsIncomplete")
    try
    {
      // Two metadata entries per source-read group, maps and range maps. No
      // sample graph is cloned by freezing; the pool continues to own them.
      owner.hold(32+60*groups.size)
      envelopes.each |e|
      {
        if(e.output.entries==0 || e.target.isEmpty) throw ArgErr("diagnosticEnvelopeExpired")
        omitted:=e.count>e.group.rows.size || e.emptyOmitted || e.unpreparedOmitted
        e.target["detailsTruncated"]=omitted || e.group.rows.any |r| {r["detailsTruncated"]==true}
        e.target["sourceUsageDiagnosticRef"]="diagnostic-"+e.group.order
        if(omitted) e.target.setAll(["sourceUsageCaptureId":e.group.captureId,"sourceUsageTruncated":true,"sourceUsageRowCount":e.emptyOmitted || e.unpreparedOmitted ? null : e.count,"truncationReason":"cockpitBoundedPreparedEvidence","omittedConfirmedEmpty":e.emptyOmitted,"omittedUnprepared":e.unpreparedOmitted])
        e.target.remove("_capturePending")
      }
      list:=metadataEntries
      groups.vals.sort |a,b| {a.order<=>b.order}.each |g|
      {
        meta:=metadata(g,g.spec["kind"].toStr,g.spec["grain"] as Str ?: "",g.unknown ? null : g.total,g.rows.size,g.rows.size<g.total,g.unknown,range(g.rows))
        list.add(meta)
        if(g.spec["kind"]=="sourceUsage")
        {
          childRows:=g.weight-g.rows.size
          list.add(metadata(g,"sourceIntervals","sourceInterval",g.childUnknown || g.unknown ? null : g.childTotal,childRows,childRows<g.childAvailable,g.childUpstream || g.unknown,range(g.rows,true)))
        }
      }
      snapshot=Str:Obj?["schemaVersion":1,"rowBudget":1000,"returnedCount":kept,"returnedByKind":byKind,"truncated":list.any |m| {m["truncated"]==true},"entries":list]
      protectedRoots.add(snapshot);frozen=true;return snapshot
    }
    catch(Err e) {failure=e;throw e}
  }
  private Str:Obj? metadata(EnerCubixCockpitCaptureGroup g,Str kind,Str grain,Int? total,Int returned,Bool limited,Bool upstream,[Str:Obj?]? range)
  {
    reason:=limited ? (upstream ? "upstreamAndSnapshotLimit" : "snapshotDiagnosticBudget") : (upstream ? "upstreamDiagnosticLimit" : "complete")
    meta:=g.spec.dup.setAll(["id":"diagnostic-"+g.order+(kind=="sourceIntervals" ? "-intervals" : ""),"kind":kind,"grain":grain,"totalCount":total,"returnedCount":returned,"truncated":limited || upstream,"reason":reason,"returnedRange":range])
    heads.add(meta);byKind[kind]=(byKind[kind] ?: 0)+returned;return meta
  }
  private [Str:Obj?]? range([Str:Obj?][] rows,Bool children := false)
  {
    DateTime? from;DateTime? to
    visit:=|Map r|
    {
      left:=r["from"] ?: (r["intervalStart"] ?: r["ts"]);right:=r["to"] ?: (r["intervalEnd"] ?: r["ts"])
      a:=DateTime.fromIso(left as Str ?: "",false);b:=DateTime.fromIso(right as Str ?: "",false)
      if(a!=null && (from==null || a<from)) from=a
      if(b!=null && (to==null || b>to)) to=b
    }
    rows.each |r|
    {
      if(children) {xs:=r["intervals"] as List;xs?.each |child| {if(child is Map) visit(child)}}
      else visit(r)
    }
    if(from==null || to==null) return null
    out:=Str:Obj?["from":from.toIso,"to":to.toIso];heads.add(out);return out
  }
  private EnerCubixCockpitCaptureGroup group(Str key) {groups[key] ?: throw ArgErr("diagnosticGroupNotPlanned")}
  private Void remove(EnerCubixCockpitCaptureGroup g)
  {
    cell:=g.cells.removeAt(g.cells.size-1);g.rows.removeAt(g.rows.size-1)
    kept-=cell.weight;g.weight-=cell.weight;cell.owner.close
  }
  private Void check() {if(failure!=null) throw failure;if(closed) throw ArgErr("diagnosticsClosed");owner.budget.deadline.check}

  private static Int entries(Obj? value,EnerCubixPreparedOwner scratch,Obj[] path)
  {
    if(value isnot Map && value isnot List)
    {if(value!=null && !value.isImmutable) throw ArgErr("diagnosticValue");return 0}
    if(path.any |v| {v===value}) throw ArgErr("diagnosticCycle")
    scratch.hold(1);path.add(value)
    try
    {
      if(value is Map) {n:=1+((Map)value).size;((Map)value).each |v| {n+=entries(v,scratch,path)};return n}
      return ((List)value).reduce(1+((List)value).size) |Int n,v->Int| {n+entries(v,scratch,path)}
    }
    finally {path.removeAt(path.size-1)}
  }
  private static Obj? copy(Obj? value)
  {
    if(value is Map) {out:=Str:Obj?[:];((Map)value).each |v,k| {out[k.toStr]=copy(v)};return out}
    if(value is List) return ((List)value).map |v->Obj?| {copy(v)}
    return value
  }
  internal static Void clear(Obj? value)
  {
    // All containers were deeply copied after cycle validation, so children can
    // be cleared directly before the parent, without allocating cleanup copies.
    if(value is Map) {((Map)value).each |v| {clear(v)};((Map)value).clear}
    else if(value is List) {((List)value).each |v| {clear(v)};((List)value).clear}
  }
}

internal class EnerCubixCockpitCaptureGroup
{
  new make(Str:Obj? spec,Int order) {this.spec=spec;this.order=order}
  Str:Obj? spec
  Int order
  const Str captureId := Uuid().toStr
  [Str:Obj?][] rows := [,]
  EnerCubixCockpitCaptureCell[] cells := [,]
  Int total := 0
  Int childTotal := 0
  Int childAvailable := 0
  Int weight := 0
  Bool unknown := false
  Bool childUnknown := false
  Bool childUpstream := false
  Bool sealed := false
}
internal class EnerCubixCockpitCaptureCell
{
  new make(EnerCubixPreparedOwner owner,Int weight)
  {this.owner=owner;this.weight=weight;owner.watch |->Void| {EnerCubixCockpitCapture.clear(row);row=null}}
  EnerCubixPreparedOwner owner
  Int weight
  [Str:Obj?]? row
}
internal class EnerCubixCockpitCaptureEnvelope
{
  new make(EnerCubixCockpitCaptureGroup group,Str:Obj? target,EnerCubixPreparedOwner output,Int count,Bool emptyOmitted,Bool unpreparedOmitted)
  {this.group=group;this.target=target;this.output=output;this.count=count;this.emptyOmitted=emptyOmitted;this.unpreparedOmitted=unpreparedOmitted}
  EnerCubixCockpitCaptureGroup group
  Str:Obj? target
  EnerCubixPreparedOwner output
  Int count
  Bool emptyOmitted
  Bool unpreparedOmitted
}

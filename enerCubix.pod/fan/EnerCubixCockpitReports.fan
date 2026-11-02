** A distinct, optional prepared-report boundary. No fallback is possible once a
** route is supplied; ordinary reports and the existing KPI fault seam stay intact.
internal class EnerCubixCockpitReports
{
  static Str:Obj? read(Str key,Str:Obj? q,[Str:Obj?][] records,[Str:Obj?][] histories,|Str,Str:Obj?->Str:Obj?|? route := null)
  {route == null ? EnerCubixHistory.report(q,records,histories) : route(key,q)}

  static Str:Obj? metricQuery(Str:Obj? q,Str id,Str? auxiliary)
  {
    if(["cost","co2"].contains(id)) return q.dup.set("metric",id)
    if(id == "auxiliary") return q.dup.set("categoryIds",[auxiliary]).set("_cockpitCategoryId",auxiliary)
    if(id == "area") return q.dup.set("perArea",true)
    throw ArgErr("cockpitMetricPlan")
  }
  static Str:Obj? faceQuery(Str:Obj? q,Str:Obj? boundary,Str key)
  {
    if(key == "face-heatmap") return q.dup.set("period","hour")
    base:=q.dup.setAll(["nodeIds":boundary["meterIds"],"dimension":"metering","metric":"energy","perArea":false])
    base.remove("spaceSource")
    if(key == "face-meter-profile") return base.set("kind","profile")
    if(key == "face-endUse") return base.set("kind","utility")
    if(key == "face-daily") return base.setAll(["kind":"daily","period":"hour"])
    if(key == "face-workingHours" || key == "face-workingDays") return base.setAll(["kind":key[5..-1],"period":"hour"])
    throw ArgErr("cockpitFacePlan")
  }
  static Str:Obj? budgetQuery(Str:Obj? q,Str:Obj? boundary)
  {
    request:=q.dup.setAll(["dimension":"metering","nodeIds":boundary["meterIds"],"metric":"cost","perArea":false])
    if(DateTime.fromIso(request["to"].toStr) > DateTime.fromIso(request["asOf"].toStr)) request["to"]=request["asOf"]
    return request
  }
}

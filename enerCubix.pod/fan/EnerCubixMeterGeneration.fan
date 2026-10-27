using haystack
using folio

** Legacy entrypoints are inert. FIN alone collects each explicit primary point.
internal class EnerCubixMeterGeneration
{
  static Void update(Folio db, DateTime now:=DateTime.now) {}
  internal static Void ensure(Folio db, Str:Obj? record, [Str:Obj?][] records, DateTime now) {}
  static Int recalculate(Folio db, [Str:Obj?][] records, DateTime from, DateTime to, Bool locked:=false, |Int|? onProgress:=null)
  { throw ArgErr("报表只读主能耗点，不再创建或重算派生归档") }
  internal static Void publish(Folio db, Dict main, Dict state, DateTime from, DateTime to, EnerCubixValue value, DateTime now, Bool formula, Bool repair:=false)
  { throw ArgErr("报表只读主能耗点，不再创建或重算派生归档") }
}

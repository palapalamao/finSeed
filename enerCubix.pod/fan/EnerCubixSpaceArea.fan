using haystack

** The sole native-space write: a validated area patch in square metres.
const class EnerCubixSpaceArea
{
  static Bool editable([Str:Obj?] row)
  { row["nativeReadonly"] == true && ["site","floor"].contains(row["nativeSourceKind"]) }

  static Float? squareMetres(Obj? value)
  {
    if (value isnot Number) return null
    number:=(Number)value
    try
    {
      area:=number.unit == null ? number.toFloat : number.unit.convertTo(number.toFloat,Unit.fromStr("m²"))
      return area > 0f && !area.isNaN && area != Float.posInf ? area : null
    }
    catch (Err e) { return null }
  }

  static Dict tags([Str:Obj?] input, Dict nativeRec)
  {
    if (!(nativeRec.has("site") || nativeRec.has("floor")) || input["areaOnly"] != true) throw ArgErr("spaceAreaOnly")
    if (input.keys.any |key| { !["id","kind","mod","areaOnly","area"].contains(key) }) throw ArgErr("spaceAreaOnly")
    if (input["kind"] != null && input["kind"] != "space") throw ArgErr("spaceAreaOnly")
    value:=input["area"]
    if (value == null) return Etc.makeDict(["area":Remove.val])
    if (value isnot Float && value isnot Int) throw ArgErr("invalidServiceArea")
    area:=EnerCubixMath.num(value)
    if (area == null || area <= 0f || area.isNaN || area == Float.posInf) throw ArgErr("invalidServiceArea")
    return Etc.makeDict(["area":Number(area,Unit.fromStr("m²"))])
  }

  internal static Str:Obj? referenceRow(Str id, Dict source, [Str:Obj?]? projected)
  {
    if (!(source.has("site") || source.has("floor"))) throw ArgErr("invalidAreaSpace")
    return ["id":projected?.get("id") ?: id,"kind":"space","name":source.dis,
      "nativeSourceId":source.id.id,"nativeSourceKind":source.has("site") ? "site" : "floor"]
  }
}

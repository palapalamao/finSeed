using haystack

class EnerCubixMeterOriginTest : Test
{
  Void testPriorityAndIndependentHistory()
  {
    point:=dict(["id":Ref("p"),"equipRef":Ref("eq"),"modbusConnRef":Ref("conn"),"modbusCur":"energy","his":Marker.val,"hisFunc":"enerCubixCleanHis","curStatus":"down"])
    meter:=Str:Obj?["pointId":"p","historyPointId":"derived-archive"]
    verifyEq(origin(meter,point)["type"],"physical")
    verifyEq(origin(meter,point)["pointId"],"p")
    verifyEq(origin(meter,point)["protocol"],"modbus")
    meter["autoSum"]=true
    verifyEq(origin(meter,point)["type"],"virtual")
    verifyEq(origin(meter,point)["reason"],"submeterSum")
    meter["autoSum"]=false; meter["expressionId"]="formula"
    verifyEq(origin(meter,point)["reason"],"expression")
  }

  Void testConnectorEvidenceRequired()
  {
    ["modbus","bacnet","haystack"].each |protocol|
    {
      point:=dict(["id":Ref("p"),protocol+"ConnRef":Ref("conn"),protocol+"Cur":"address"])
      connected:=EnerCubixMeterOrigin.classify(["pointId":"p"],point) |Ref ref->Dict?| { dict(["id":ref,protocol+"Conn":Marker.val]) }
      verifyEq(connected["type"],"physical")
      verifyEq(EnerCubixMeterOrigin.classify(["pointId":"p"],point) |Ref ref->Dict?| { null }["type"],"unconfirmed")
      verifyEq(origin(["pointId":"p"],dict(["id":Ref("p"),protocol+"ConnRef":Ref("conn")]))["type"],"unconfirmed")
    }
    verifyEq(origin(["pointId":"p"],dict(["id":Ref("p"),"equipRef":Ref("eq"),"his":Marker.val,"curVal":Number(1)]))["type"],"unconfirmed")
    verifyEq(origin(["pointId":"p"],null)["type"],"unconfirmed")
    verifyEq(origin(["historyPointId":"p"],dict(["id":Ref("p"),"modbusConnRef":Ref("conn"),"modbusCur":"energy"]))["type"],"unconfirmed")
    verifyEq(origin(["pointId":"other"],dict(["id":Ref("p"),"modbusConnRef":Ref("conn"),"modbusCur":"energy"]))["type"],"unconfirmed")
  }

  Void testDoesNotModifyInputs()
  {
    meter:=Str:Obj?["name":"用户总表","autoSum":true,"pointId":"p"]
    before:=meter.dup
    verifyEq(origin(meter,null)["reason"],"submeterSum")
    verifyEq(meter,before)
  }

  Void testCatalogDecorationAndAliases()
  {
    main:=Str:Obj?["id":"m","kind":"totalMeter","name":"用户原名","autoSum":true,"pointId":"p"]
    alias:=Str:Obj?["id":"alias","kind":"totalMeter","name":"别名","canonicalId":"m","pointId":"p"]
    group:=Str:Obj?["id":"g","kind":"space","name":"空间"]
    records:=[main,alias,group]
    before:=records.map |r->[Str:Obj?]| { r.dup }
    out:=EnerCubixMeterOrigin.decorate(records,|Str id->Dict?| { fail("Virtual sources do not require point reads"); return null },|Ref ref->Dict?| { null })
    verifyEq(records,before)
    verifyEq(out[0]["name"],"用户原名")
    verifyEq(((Str:Obj?)out[0]["meterOrigin"])["type"],"virtual")
    verifyEq(((Str:Obj?)out[1]["meterOrigin"])["type"],"virtual")
    verifyFalse(out[2].containsKey("meterOrigin"))
  }

  Void testPresentationCannotPersistAsSourceEvidence()
  {
    input:=Str:Obj?["kind":"totalMeter","name":"原名","meterOrigin":["type":"physical"]]
    clean:=EnerCubixNativeSpace.clean(input)
    verifyFalse(clean.containsKey("meterOrigin"))
    verifyTrue(input.containsKey("meterOrigin"))
  }

  private [Str:Obj?] origin([Str:Obj?] meter, Dict? point)
  { EnerCubixMeterOrigin.classify(meter,point) |Ref ref->Dict?| { dict(["id":ref,"modbusConn":Marker.val]) } }

  private Dict dict([Str:Obj?] tags) { Etc.makeDict(tags) }
}

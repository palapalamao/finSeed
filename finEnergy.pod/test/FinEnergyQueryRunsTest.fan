class FinEnergyQueryRunsTest : Test
{
  Void testCutoffAtSubmission()
  {
    now:=DateTime.fromIso("2026-11-23T07:45:00+08:00")
    input:=Str:Obj?["nodeIds":["one","two"],"period":"day"]
    pinned:=FinEnergyQueryRuns.pinRequest(input,now)
    verifyEq(pinned["asOf"],now.toIso)
    verifyEq(pinned["nodeIds"],["one","two"])
    verifyEq(pinned["period"],"day")
    verifyNull(input["asOf"])
    input["asOf"]="2026-11-22T07:45:00+08:00"
    verifyEq(FinEnergyQueryRuns.pinRequest(input,now)["asOf"],input["asOf"])
    input["asOf"]="2026-11-24T07:45:00+08:00"
    verifyEq(DateTime.fromIso(FinEnergyQueryRuns.pinRequest(input,now)["asOf"]),now)
    input["asOf"]="invalid"
    verifyErr(ArgErr#) {FinEnergyQueryRuns.pinRequest(input,now)}
  }
}

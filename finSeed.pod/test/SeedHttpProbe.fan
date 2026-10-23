using web
using util
using haystack
using skyarcd

** All requests are fixed to the independent registered acceptance instance.
** Reuse the incoming native bearer only in memory; never serialize its headers.
const class SeedHttpProbe : WebMod
{
  private Void guard()
  {
    if (Context.cur.proj.name != "finseed_acceptance" || req.headers["Host"] != "127.0.0.1:38085") throw ArgErr("HTTP acceptance is restricted to the independent loopback project")
    if (req.headers["Authorization"] == null) throw ArgErr("Native bearer request required")
  }

  Map proxy(Str path, Str? payload)
  {
    guard
    route := path.split('?').first
    if (!["catalog","points","tree","migration/preview","migration","records","records/delete","tree/copy","tree/move","tree/toggle","tree/manage","report","tasks","alarms","alarms/ack"].contains(route) || path.size > 4096 || path.contains("#")) throw ArgErr("Acceptance bridge route is not permitted")
    if (payload != null && payload.size > 2097152) throw ArgErr("Acceptance request too large")
    Map? body := payload == null ? null : (Map)JsonInStream(payload.in).readJson
    response := call(path,body)
    return ["status":response["status"],"body":response["body"]]
  }

  Str:Obj? permissions()
  {
    guard
    admin:=Context.cur.user.isAdmin
    catalog:=call("catalog")
    expect(catalog,200)
    data:=(Map)((Map)catalog["body"])["data"]
    user:=(Map)data["user"]
    if (user["canWrite"] != admin) throw Err("Catalog permission mismatch")
    unauth:=call("catalog",null,false)
    nativeLogin := unauth["status"] == 200 && unauth["body"] == null && unauth["htmlAuthChallenge"] == true
    if (![401,403,302,303,307].contains(unauth["status"]) && !nativeLogin) throw Err("Anonymous catalog access returned "+unauth["status"]+" type "+unauth["contentType"]+" JSON "+unauth["body"])
    if (!admin)
    {
      expect(call("records",["record":["kind":"group","name":"must not be created"]]),403)
      expect(call("tree/manage",["action":"previewDelete","items":Obj?[,]]),403)
      expect(call("migration/preview"),403)
      expect(call("migration",["action":"preview"]),403)
      expect(call("tasks",["action":"recalculate"]),403)
      expect(call("alarms/ack",["id":"missing","note":"must not be written"]),403)
    }
    return ["status":"passed","actor":Context.cur.user.username,"canWrite":admin,"anonymousStatus":unauth["status"],"nativeLoginChallenge":nativeLogin,"readOnlyWritesRejected":!admin]
  }

  Str:Obj? run()
  {
    guard
    if (!Context.cur.user.isAdmin) throw ArgErr("Acceptance administrator required")
    expect(call("catalog"),200)
    catalog:=(Map)ok(call("catalog"))
    records:=(List)catalog["records"]
    root:=(Map)records.find |v| { ((Map)v)["name"] == "验收楼宇" }
    category:=(Map)records.find |v| { ((Map)v)["name"] == "验收电力" }
    checks:=Str:Obj?[:]
    ["space","metering","organization"].each |dimension|
    {
      tree:=(Map)ok(call("tree?dimension="+dimension))
      if (tree["dimension"] != dimension || tree["records"] isnot List) throw Err("Three-tree route mismatch")
    }
    migration:=(Map)ok(call("migration/preview"))
    if (migration["revision"] == null || migration["sourceRevision"] == null) throw Err("Migration preview revision missing")
    checks["HTTP three dimensions and migration preview"]=true
    shell:=call("/api/finseed_acceptance/ext/enerCubix/")
    expect(shell,302)
    if (shell["location"] != "/pod/enerCubix/res/web/seed/index.html#/dashboard?project=finseed_acceptance") throw Err("Native application entry redirect mismatch")
    entry:=call("/pod/enerCubix/res/web/seed/index.html")
    expect(entry,200)
    module:=entry["module"] as Str ?: throw Err("Packed SPA module missing")
    if (module.startsWith("./")) module=module[2..-1]
    if (!module.startsWith("modules/") || module.contains("..")) throw Err("Invalid SPA module path")
    moduleResponse:=call("/pod/enerCubix/res/web/seed/"+module)
    expect(moduleResponse,200)
    if (!moduleResponse["contentType"].toStr.contains("javascript")) throw Err("Native SPA module MIME type is not JavaScript")
    attest:=call("/finStackAuth",Str:Obj?[:])
    expect(attest,200)
    if (attest["hasAttest"] != true) throw Err("Native FIN attest handshake unavailable")
    checks["native launcher packed SPA modules and FIN CSRF handshake"]=true
    reportRequest:=Str:Obj?["kind":"profile","nodeIds":[root["id"]],"from":"2026-10-19T00:00:00+08:00","to":"2026-10-20T00:00:00+08:00","period":"day","metric":"energy","perArea":false]
    report:=(Map)ok(call("report",reportRequest))
    series:=(List)report["series"]; points:=(List)((Map)series.first)["points"]
    value:=((Map)points.first)["value"]
    if (value == null || (SeedConfig.number(value)-240f).abs > 0.000001f) throw Err("Real HTTP report value incorrect: $value")
    checks["report JSON and native history"]=value
    costRequest:=reportRequest.dup; costRequest["metric"]="cost"
    cost:=(Map)ok(call("report",costRequest))
    if (((Map)((List)cost["series"]).first)["unit"] != "元") throw Err("Cost currency unit mismatch")
    checks["cost currency unit"]=true
    ps:=(Map)ok(call("points?q=finseed-test&limit=10"))
    if (((List)ps["items"]).size < 3) throw Err("Native point browser failed")
    checks["point search and pagination"]=true
    group:=(Map)ok(call("records",["record":["kind":"group","name":"HTTP空组 "+DateTime.now.toIso]]))
    moved:=(Map)ok(call("tree/move",["id":group["id"],"mod":group["mod"],"parentId":root["id"]]))
    group=(Map)((List)moved["records"]).first
    meter:=(Map)ok(call("records",["record":["kind":"meter","name":"HTTP绑点表 "+DateTime.now.toIso,"parentId":group["id"],"categoryId":category["id"],"area":42f,"maximum":80f,"includeInTotals":false,"actualEfficiency":0.85f,"baselineEfficiency":0.9f,"location":"验收位置","description":"属性往返验收"]]))
    if (SeedConfig.number(meter["area"]) != 42f || SeedConfig.number(meter["maximum"]) != 80f || SeedConfig.number(meter["actualEfficiency"]) != 0.85f || SeedConfig.number(meter["baselineEfficiency"]) != 0.9f || meter["includeInTotals"] != false || meter["location"] != "验收位置" || meter["description"] != "属性往返验收") throw Err("Meter business attributes did not persist")
    pointObj:=((List)ps["items"]).find |Obj item->Bool| { ((Map)item)["id"].toStr.endsWith("finseed-test-tariff-source") }
    point:=(pointObj as Map) ?: throw Err("Unbound acceptance source missing")
    if (!Context.cur.db.readById(Ref.fromStr(point["id"].toStr)).has("seedAcceptanceSource")) throw Err("Acceptance source ownership mismatch")
    meter["pointId"]=point["id"]
    meter=(Map)ok(call("records",["record":meter]))
    meter.remove("pointId")
    meter=(Map)ok(call("records",["record":meter]))
    meter["kind"]="totalMeter"
    meter=(Map)ok(call("records",["record":meter]))
    stale:=meter.dup; stale["mod"]="obsolete"
    expect(call("records",["record":stale]),409)
    expect(call("records/delete",["id":group["id"],"mod":group["mod"]]),400)
    ok(call("records/delete",["id":meter["id"],"mod":meter["mod"]]))
    ok(call("records/delete",["id":group["id"],"mod":group["mod"]]))
    checks["HTTP CRUD move bind unbind role switch and stale mod"]=true
    template:=(Map)ok(call("records",["record":["kind":"template","name":"HTTP相对时间模板 "+DateTime.now.toIso,"request":reportRequest,"preset":"thisMonth"]]))
    template["preset"]="lastMonth"
    template=(Map)ok(call("records",["record":template]))
    clone:=template.dup; clone.remove("id"); clone.remove("mod"); clone["name"]=template["name"].toStr+" 另存"
    clone=(Map)ok(call("records",["record":clone]))
    ok(call("records/delete",["id":template["id"],"mod":template["mod"]]))
    ok(call("records/delete",["id":clone["id"],"mod":clone["mod"]]))
    checks["HTTP template save update saveas delete"]=true
    alarms:=(List)ok(call("alarms"))
    alarm:=(Map)(alarms.find |v| { ((Map)v)["state"] == "open" } ?: alarms.first)
    ack:=(Map)ok(call("alarms/ack",["id":alarm["id"],"mod":alarm["mod"],"note":"HTTP验收确认"] ))
    if (ack["ackBy"] != Context.cur.user.username) throw Err("HTTP alarm identity mismatch")
    checks["HTTP alarm confirmation"]=true
    ["setCalculationEnabled","setAlarmEnabled"].each |action|
    {
      ok(call("tasks",["action":action,"enabled":true]))
      ok(call("tasks",["action":action,"enabled":false]))
    }
    checks["independent native scheduler switches"]=true
    checks["native identity permissions"]=permissions
    return ["status":"passed","project":Context.cur.proj.name,"checks":checks,"reportSnapshot":report]
  }

  private Map call(Str path, Map? body := null, Bool authenticate := true)
  {
    client:=WebClient()
    client.followRedirects=false
    relative := path.startsWith("/") ? path : "/api/finseed_acceptance/ext/enerCubix/v1/"+path
    client.reqUri=("http://127.0.0.1:38085"+relative).toUri
    if (authenticate) client.reqHeaders["Authorization"]=req.headers["Authorization"]
    client.reqHeaders["Accept"]="application/json"
    try
    {
      if (body == null) client.writeReq
      else
      {
        json:=JsonOutStream.writeJsonToStr(body)
        client.reqMethod="POST"
        client.reqHeaders["Content-Type"]="application/json; charset=utf-8"
        client.reqHeaders["Content-Length"]=json.toBuf.size.toStr
        client.writeReq
        client.reqOut.print(json).close
      }
      client.readRes
      status:=client.resCode
      Obj? parsed:=null
      contentType:=client.resHeaders.get("Content-Type","")
      authChallenge:=false
      Str? module:=null
      if (contentType.contains("json")) parsed=JsonInStream(client.resIn).readJson
      else if (contentType.contains("html"))
      {
        html:=client.resStr
        lower:=html.lower
        authChallenge=lower.contains("login") || lower.contains("password") || lower.contains("auth")
        matcher:=Regex<|<script[^>]*src="([^"]+)"|>.matcher(html)
        if (matcher.find) module=matcher.group(1)
      }
      return ["status":status,"body":parsed,"contentType":contentType,"htmlAuthChallenge":authChallenge,"module":module,"location":client.resHeaders["Location"],"hasAttest":client.resHeaders["fin-stack-auth"] != null]
    }
    finally { client.close }
  }

  private static Void expect(Map response, Int status)
  {
    if (response["status"] != status) throw Err("HTTP expected $status got "+response["status"]+": "+response["body"])
  }

  private static Obj? ok(Map response)
  {
    expect(response,200)
    body:=(Map)response["body"]
    if (body["ok"] != true) throw Err("HTTP business operation failed")
    return body["data"]
  }
}

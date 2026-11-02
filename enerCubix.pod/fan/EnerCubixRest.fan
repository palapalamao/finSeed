using web
using util
using skyarcd

const class EnerCubixRest : WebMod
{
  override Void onService()
  {
    try
    {
      repo := EnerCubixRepo(Context.cur)
      repo.mustRead
      path := req.uri.path
      i := path.findIndex |p| { p == "v1" }
      route := i == null || i+1 >= path.size ? "" : path[i+1..-1].join("/")
      readOnly := ["session","catalog","points","alarms","messages/changes","comparison-scopes","tree","migration/preview","cockpit/assets","cockpit/assets/image","cockpit/budgets","cockpit/rule-profiles","cockpit/config-audit"].contains(route)
      if (req.method != (readOnly ? "GET" : "POST")) throw EnerCubixHttpErr(405,"METHOD","请求方法不支持")
      body := Str:Obj?[:]
      if (req.method == "POST")
      {
        if (!readPost(route)) repo.mustWrite
        if (!req.headers.get("Content-Type","").lower.startsWith("application/json")) throw ArgErr("请求必须使用 application/json")
        raw := readBody(req.in,bodyLimit(route),route == "cockpit/assets/upload")
        parsed := JsonInStream(raw.in).readJson
        if (parsed isnot Map) throw ArgErr("请求必须为 JSON 对象")
        body = (Str:Obj?)parsed
      }
      Obj? data
      switch (route)
      {
        case "cockpit/budgets": data=repo.cockpitBudgets
        case "cockpit/budgets/save": data=repo.saveCockpitBudget(body)
        case "cockpit/budgets/delete": data=repo.deleteCockpitBudget(body)
        case "cockpit/rule-profiles": data=repo.cockpitRuleProfiles
        case "cockpit/rule-profiles/save": data=repo.saveCockpitRuleProfile(body)
        case "cockpit/rule-profiles/delete": data=repo.deleteCockpitRuleProfile(body)
        case "cockpit/config-audit": data=repo.cockpitConfigAudit(req.uri.query["targetId"] ?: "")
        case "cockpit/assets": data=EnerCubixCockpitAssets(repo).list
        case "cockpit/assets/upload": data=EnerCubixCockpitAssets(repo).upload(body)
        case "cockpit/assets/save": data=EnerCubixCockpitAssets(repo).save(body)
        case "cockpit/assets/select": data=EnerCubixCockpitAssets(repo).select(body)
        case "cockpit/assets/delete": data=EnerCubixCockpitAssets(repo).remove(body)
        case "cockpit/assets/image":
          image:=EnerCubixCockpitAssets(repo).image(req.uri.query["id"] ?: "",req.uri.query["hash"] ?: "")
          sendImage(image); return
        case "session": data=["locale":hx::HxCoreFuncs.context.get("locale"),"username":Context.cur.user.username]
        case "catalog": data=repo.catalog
        case "tree": data=repo.treeView(req.uri.query["dimension"] ?: "space")
        case "comparison-scopes": data=repo.comparisonScopes(req.uri.query["nodeIds"] ?: "")
        case "migration/preview": data=repo.migration(["action":"preview"])
        case "migration": data=repo.migration(body)
        case "points": data=repo.points(req.uri.query["q"] ?: "",Int.fromStr(req.uri.query["offset"] ?: "0"),Int.fromStr(req.uri.query["limit"] ?: "200"))
        case "records": data=repo.save(body["record"] as Map ?: throw ArgErr("缺少记录"))
        case "records/delete": data=repo.remove(str(body,"id"),body["mod"])
        case "tree/manage": data=repo.manage(body)
        case "tree/copy": case "tree/move": case "tree/toggle": data=repo.tree(route.split('/').last,str(body,"id"),body["parentId"] as Str,body["mod"])
        case "report": data=repo.report(body)
        case "cockpit": data=repo.cockpit(body)
        case "cleaning/preview": data=EnerCubixCleaningRepo(repo).preview(body)
        case "tasks": data=EnerCubixJobs(repo).run(body)
        case "alarms": data=repo.alarms
        case "messages/changes": data=repo.changeMessages(Int.fromStr(req.uri.query["offset"] ?: "0"),Int.fromStr(req.uri.query["limit"] ?: "30"))
        case "alarms/ack": data=repo.acknowledge(str(body,"id"),body["mod"],body["note"] as Str ?: "")
        default: throw EnerCubixHttpErr(404,"NOT_FOUND","接口不存在")
      }
      if (route == "cockpit" && JsonOutStream.writeJsonToStr(["ok":true,"data":data]).toBuf.size > 8388608) throw EnerCubixHttpErr(413,"RESPONSE_LIMIT","cockpitResponseLimit")
      send(200,["ok":true,"data":data])
    }
    catch (EnerCubixHttpErr e)
    {
      error:=Str:Obj?["code":e.code,"msg":e.msg]
      if (e.status == 429) {error["retryAfterSeconds"]=2;res.headers["Retry-After"]="2"}
      send(e.status,["ok":false,"error":error])
    }
    catch (ArgErr e) { send(400,["ok":false,"error":["code":"INVALID","msg":e.msg]]) }
    catch (ParseErr e) { send(400,["ok":false,"error":["code":"INVALID","msg":"请求格式无效"]]) }
    catch (Err e)
    {
      Log.get("enerCubix").err("EnerCubix request failed",e)
      send(500,["ok":false,"error":["code":"INTERNAL","msg":"处理失败，请查看 FIN 日志"]])
    }
  }

  private Void sendImage(Str:Obj? image)
  {
    bytes:=(Buf)image["bytes"]
    res.statusCode=200
    res.headers["Content-Type"]=image["mime"].toStr
    res.headers["Content-Length"]=bytes.size.toStr
    res.headers["Cache-Control"]="no-store"
    res.headers["X-Content-Type-Options"]="nosniff"
    res.headers["Content-Security-Policy"]="default-src 'none'; sandbox"
    res.headers["Cross-Origin-Resource-Policy"]="same-origin"
    res.out.writeBuf(bytes); res.out.flush; res.done
  }

  internal static Int bodyLimit(Str route) {route == "cockpit/assets/upload" ? 3145728 : 2097152}

  private Void send(Int status, [Str:Obj?] body)
  {
    res.statusCode=status
    res.headers["Content-Type"]="application/json; charset=utf-8"
    res.headers["Cache-Control"]="no-store"
    JsonOutStream(res.out).writeJson(body)
    res.out.flush
    res.done
  }

  private static Str str([Str:Obj?] map, Str key)
  {
    val := map[key] as Str
    if (val == null || val.isEmpty) throw ArgErr("缺少参数 $key")
    return val
  }

  internal static Str readBody(InStream input, Int limit := 2097152, Bool utf8ByteBound := false)
  {
    out := StrBuf()
    byteCount:=0
    while (true)
    {
      c := input.readChar
      if (c == null) break
      if(c < 128)byteCount++
      else if(c < 2048)byteCount+=2
      else if(c < 65536)byteCount+=3
      else byteCount+=4
      if (out.size >= limit || (utf8ByteBound && byteCount > limit)) throw EnerCubixHttpErr(413,"TOO_LARGE","请求内容过大")
      out.addChar(c)
    }
    return out.toStr
  }

  ** Authentication and FIN CSRF still run through the native /api project route.
  internal static Bool readPost(Str route) { ["report","cleaning/preview","cockpit"].contains(route) }
}

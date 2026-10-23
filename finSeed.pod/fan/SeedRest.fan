using web
using util
using skyarcd

const class SeedRest : WebMod
{
  override Void onService()
  {
    try
    {
      repo := SeedRepo(Context.cur)
      repo.mustRead
      path := req.uri.path
      i := path.findIndex |p| { p == "v1" }
      route := i == null || i+1 >= path.size ? "" : path[i+1..-1].join("/")
      readOnly := ["catalog","points","alarms","tree","migration/preview"].contains(route)
      if (req.method != (readOnly ? "GET" : "POST")) throw SeedHttpErr(405,"METHOD","请求方法不支持")
      body := Str:Obj?[:]
      if (req.method == "POST")
      {
        if (route != "report") repo.mustWrite
        if (!req.headers.get("Content-Type","").lower.startsWith("application/json")) throw ArgErr("请求必须使用 application/json")
        raw := readBody(req.in)
        parsed := JsonInStream(raw.in).readJson
        if (parsed isnot Map) throw ArgErr("请求必须为 JSON 对象")
        body = (Str:Obj?)parsed
      }
      Obj? data
      switch (route)
      {
        case "catalog": data=repo.catalog
        case "tree": data=repo.treeView(req.uri.query["dimension"] ?: "space")
        case "migration/preview": data=repo.migration(["action":"preview"])
        case "migration": data=repo.migration(body)
        case "points": data=repo.points(req.uri.query["q"] ?: "",Int.fromStr(req.uri.query["offset"] ?: "0"),Int.fromStr(req.uri.query["limit"] ?: "200"))
        case "records": data=repo.save(body["record"] as Map ?: throw ArgErr("缺少记录"))
        case "records/delete": data=repo.remove(str(body,"id"),body["mod"])
        case "tree/manage": data=repo.manage(body)
        case "tree/copy": case "tree/move": case "tree/toggle": data=repo.tree(route.split('/').last,str(body,"id"),body["parentId"] as Str,body["mod"])
        case "report": data=repo.report(body)
        case "tasks": data=SeedJobs(repo).run(body)
        case "alarms": data=repo.records.findAll |r| { r["kind"] == "alarm" }
        case "alarms/ack": data=repo.acknowledge(str(body,"id"),body["mod"],body["note"] as Str ?: "")
        default: throw SeedHttpErr(404,"NOT_FOUND","接口不存在")
      }
      send(200,["ok":true,"data":data])
    }
    catch (SeedHttpErr e) { send(e.status,["ok":false,"error":["code":e.code,"msg":e.msg]]) }
    catch (ArgErr e) { send(400,["ok":false,"error":["code":"INVALID","msg":e.msg]]) }
    catch (ParseErr e) { send(400,["ok":false,"error":["code":"INVALID","msg":"请求格式无效"]]) }
    catch (Err e)
    {
      Log.get("enerCubix").err("EnerCubix request failed",e)
      send(500,["ok":false,"error":["code":"INTERNAL","msg":"处理失败，请查看 FIN 日志"]])
    }
  }

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

  internal static Str readBody(InStream input, Int limit := 2097152)
  {
    out := StrBuf()
    while (true)
    {
      c := input.readChar
      if (c == null) break
      if (out.size >= limit) throw SeedHttpErr(413,"TOO_LARGE","请求内容过大")
      out.addChar(c)
    }
    return out.toStr
  }
}

"""Loopback UI acceptance bridge; every FIN operation uses the official audited tool facade."""
import argparse
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import sys
from urllib.parse import parse_qsl, urlsplit

parser = argparse.ArgumentParser()
parser.add_argument("--workspace", default="D:/FINExpert-Export/fin-expert2.1/FINExpert/finprofile")
parser.add_argument("--origin", action="append", default=[])
args = parser.parse_args()
origins = set(args.origin or ["http://127.0.0.1:4178"])
if any(urlsplit(o).hostname not in {"127.0.0.1", "localhost"} or urlsplit(o).scheme != "http" for o in origins):
    raise SystemExit("Only explicit local HTTP UI origins are allowed.")
sys.path.insert(0, str(Path(args.workspace) / "src"))
from fin_expert_agent.runtime import ExpertRuntime
from fin_expert_agent.tools import ToolRegistry
runtime = ExpertRuntime(root=Path(args.workspace))
tools = ToolRegistry(runtime)
audit_file = Path(__file__).resolve().parents[1] / "out/native-browser-audit.jsonl"
routes = {"catalog", "points", "records", "records/delete", "tree/copy", "tree/move", "report", "tasks", "alarms", "alarms/ack"}
users = {"finseed-acceptance-local": "finseed_test_admin", "finseed-acceptance-reader": "finseed_test_reader"}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def send_json(self, status, body):
        content = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        if self.headers.get("Origin") in origins:
            self.send_header("Access-Control-Allow-Origin", self.headers["Origin"])
        self.end_headers()
        self.wfile.write(content)

    def do_OPTIONS(self):
        if self.path != "/proxy" or self.headers.get("Origin") not in origins:
            return self.send_json(403, {"ok": False, "error": {"code": "bridge_origin", "msg": "UI origin rejected"}})
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", self.headers["Origin"])
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self):
        try:
            self.connection.settimeout(65)
            if self.path != "/proxy" or (self.headers.get("Origin") and self.headers["Origin"] not in origins):
                raise ValueError("bridge_origin_or_endpoint")
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= 1_048_576 or not self.headers.get("Content-Type", "").startswith("application/json"):
                raise ValueError("bridge_request_size_or_type")
            request = json.loads(self.rfile.read(size))
            path, connection_id = request["path"], request.get("connection_id", "finseed-acceptance-local")
            uri = urlsplit(path)
            query = parse_qsl(uri.query, max_num_fields=5)
            if uri.scheme or uri.netloc or uri.fragment or uri.path not in routes or (uri.query and uri.path != "points") or any(k not in {"q", "offset", "limit"} for k, _ in query):
                raise ValueError("bridge_route")
            if len(path) > 4096 or connection_id not in users or (request.get("body") is not None and not isinstance(request["body"], dict)):
                raise ValueError("bridge_request")
            connection = runtime.live_connections.get(connection_id)
            if str(connection.base_url).rstrip("/") != "http://127.0.0.1:38085" or connection.project != "finseed_acceptance" or connection.username != users[connection_id]:
                raise ValueError("bridge_target")
            payload = "null" if request.get("body") is None else json.dumps(json.dumps(request["body"], ensure_ascii=False))
            expression = "seedAcceptanceRequest(" + json.dumps(path) + "," + payload + ")"
            result = tools.live_execute_axon({"connection_id": connection_id, "expression": expression, "actor": "finseed-native-browser", "max_rows": 5, "max_bytes": 2_000_000, "timeout_seconds": 60}).model_dump(mode="json")
            data = result.get("data") or {}
            audit_file.parent.mkdir(parents=True, exist_ok=True)
            with audit_file.open("a", encoding="utf-8") as log:
                log.write(json.dumps({"at": datetime.now(timezone.utc).isoformat(), "route": uri.path, "connection_id": connection_id, "audit_id": data.get("audit_id"), "status": data.get("status", "failed")}) + "\n")
            if not result["ok"] or data.get("status") != "succeeded":
                return self.send_json(502, {"ok": False, "error": {"code": data.get("status", "bridge_failed"), "msg": "Audited FIN request failed; audit " + str(data.get("audit_id"))}})
            response = json.loads(data["data"]["data"]["rows"][0]["result"])
            if not isinstance(response["status"], int) or not 200 <= response["status"] <= 599:
                raise ValueError("bridge_response")
            self.send_json(200, {"status": response["status"], "body": response["body"], "audit_id": data.get("audit_id"), "trace_id": result.get("trace_id")})
        except (ValueError, KeyError, TypeError, IndexError):
            self.send_json(400, {"ok": False, "error": {"code": "bridge_invalid_request_or_response", "msg": "Bridge request or native response is invalid"}})
        except Exception:
            self.send_json(502, {"ok": False, "error": {"code": "bridge_failed", "msg": "Audited FIN bridge failed"}})


if __name__ == "__main__":
    print("Native FIN UI bridge listening only on 127.0.0.1:4179", flush=True)
    HTTPServer(("127.0.0.1", 4179), Handler).serve_forever()

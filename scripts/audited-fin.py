"""Run one isolated acceptance request through FIN Expert's MCP tool facade."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from fin_expert_agent.runtime import ExpertRuntime
from fin_expert_agent.tools import ToolRegistry


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    request = json.loads(args.request.read_text(encoding="utf-8-sig"))
    operation = request.pop("operation")
    runtime = ExpertRuntime(root=args.workspace)
    tools = ToolRegistry(runtime)
    connection_id = request.pop("connection_id", "finseed-acceptance-local")
    users = {"finseed-acceptance-local": "finseed_test_admin",
             "finseed-acceptance-reader": "finseed_test_reader"}
    if connection_id not in users:
        raise SystemExit("Only isolated acceptance connections are permitted.")
    connection = runtime.live_connections.get(connection_id)
    if (
        str(connection.base_url).rstrip("/") != "http://127.0.0.1:38085"
        or connection.project != "finseed_acceptance"
        or connection.username != users[connection_id]
    ):
        raise SystemExit("Refusing a target outside the isolated acceptance project.")
    request["connection_id"] = connection_id
    request.setdefault("actor", "finseed-isolated-acceptance")
    if operation == "test":
        result = tools.live_test_connection(connection_id, request["actor"])
    elif operation == "read":
        result = tools.live_read(request)
    elif operation == "axon":
        result = tools.live_execute_axon(request)
    else:
        raise SystemExit("Supported operations: test, read, axon.")
    response = result.model_dump(mode="json")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(response, ensure_ascii=False, indent=2), encoding="utf-8")
    data = response.get("data") or {}
    print(json.dumps({"ok": response["ok"], "status": data.get("status"),
                      "audit_id": data.get("audit_id"), "report": str(args.output)}))
    # Never retry failed or outcome_unknown mutations. Reconcile through a new read.
    if not response["ok"] or data.get("status") != "succeeded":
        raise SystemExit(1)


if __name__ == "__main__":
    main()

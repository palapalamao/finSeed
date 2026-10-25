"""Create the isolated native FIN operator through audited FIN Expert tools.

Passwords are generated locally and are never printed or passed as CLI arguments.
Run once; reconcile any failed/unknown operation before considering a new attempt.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import secrets

from fin_expert_agent.runtime import ExpertRuntime
from fin_expert_agent.tools import ToolRegistry


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--credentials", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    if args.credentials.exists():
        raise SystemExit("Reader credentials already exist; reconcile the recorded native state before retrying.")
    runtime = ExpertRuntime(root=args.workspace)
    tools = ToolRegistry(runtime)
    connection = runtime.live_connections.get("enerCubix-acceptance-local")
    if str(connection.base_url).rstrip("/") != "http://127.0.0.1:38085" or connection.project != "enerCubix_acceptance" or connection.username != "enerCubix_test_admin":
        raise SystemExit("Refusing a target outside the isolated acceptance project.")
    credentials = {"url": "http://127.0.0.1:38085", "username": "enerCubix_test_reader",
                   "password": secrets.token_urlsafe(32), "project": "enerCubix_acceptance"}
    args.credentials.parent.mkdir(parents=True, exist_ok=True)
    args.credentials.write_text(json.dumps(credentials, indent=2), encoding="utf-8")
    evidence = {"username": credentials["username"], "role": "op", "project": "enerCubix_acceptance", "audits": []}
    expressions = [
        '''do
userCommit(diff(null, {id:@enerCubix_test_reader, user, username:"enerCubix_test_reader", dis:"EnerCubix acceptance reader", userRole:"op", tz:"Shanghai", projAccessFilter:"name==\\\"enerCubix_acceptance\\\"", pointOverrideAccess:""}, {add}))
"native-reader-created"
end''',
        'do\nuserSetPassword("enerCubix_test_reader", ' + json.dumps(credentials["password"]) + ')\n"native-reader-password-set"\nend',
    ]
    for expression in expressions:
        result = tools.live_execute_axon({"connection_id": "enerCubix-acceptance-local", "expression": expression,
                                          "actor": "enerCubix-isolated-reader-bootstrap", "max_rows": 5, "max_bytes": 100000}).model_dump(mode="json")
        data = result.get("data") or {}
        evidence["audits"].append({"audit_id": data.get("audit_id"), "status": data.get("status")})
        args.evidence.write_text(json.dumps(evidence, indent=2), encoding="utf-8")
        if not result["ok"] or data.get("status") != "succeeded":
            raise SystemExit("Native reader operation did not succeed. Stop and reconcile the saved audit id.")
    print(json.dumps({"status": "created", "username": credentials["username"], "role": "op", "evidence": str(args.evidence)}))


if __name__ == "__main__":
    main()

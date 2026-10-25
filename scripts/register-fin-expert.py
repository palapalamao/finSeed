"""Use FIN Expert's official CLI with a local hidden-input source.

Only connection registration is performed. No HTTP request is sent here.
"""
from __future__ import annotations

import argparse
import contextlib
import io
import json
from pathlib import Path
import sys
import warnings


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--credentials", type=Path, required=True)
    parser.add_argument("--connection-id", default="enerCubix-acceptance-local")
    parser.add_argument("--project", default="enerCubix_acceptance")
    args = parser.parse_args()
    credentials = json.loads(args.credentials.read_text(encoding="utf-8-sig"))
    if credentials["url"].rstrip("/") != "http://127.0.0.1:38085":
        raise SystemExit("Refusing a non-isolated connection URL.")
    if credentials["username"] not in {"enerCubix_test_admin", "enerCubix_test_reader"}:
        raise SystemExit("Refusing a non-test identity.")

    registry_path = args.workspace / "config.json"
    original = json.loads(registry_path.read_text(encoding="utf-8"))
    preserved = {
        item["connection_id"]: item
        for item in original["connections"]
        if item["connection_id"] != args.connection_id
    }
    for item in original["connections"]:
        if item["connection_id"] == args.connection_id and (
            item["project"] != args.project
            or item["base_url"].rstrip("/") != credentials["url"].rstrip("/")
            or item["username"] != credentials["username"]
        ):
            raise SystemExit("Connection id is already used by another target.")

    from fin_expert_agent import cli

    previous_argv, previous_stdin = sys.argv, sys.stdin
    try:
        # getpass intentionally receives the credential through redirected local
        # stdin, never as an argument, environment variable, prompt or log value.
        sys.stdin = io.StringIO(credentials["password"] + "\n")
        sys.argv = [
            "fin-expert", "--workspace", str(args.workspace),
            "live-connection", "set", "--id", args.connection_id,
            "--url", credentials["url"], "--project", args.project,
            "--username", credentials["username"],
            "--display-name", "EnerCubix isolated acceptance", "--auth-policy", "scram",
        ]
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()), warnings.catch_warnings():
            warnings.simplefilter("ignore")
            cli.main()
    finally:
        sys.argv, sys.stdin = previous_argv, previous_stdin

    current = json.loads(registry_path.read_text(encoding="utf-8"))
    remaining = {
        item["connection_id"]: item
        for item in current["connections"]
        if item["connection_id"] != args.connection_id
    }
    if remaining != preserved:
        raise SystemExit("Existing connection integrity check failed.")
    print(json.dumps({
        "status": "registered", "connection_id": args.connection_id,
        "url": credentials["url"], "project": args.project,
        "existing_connections_preserved": True,
    }))


if __name__ == "__main__":
    main()

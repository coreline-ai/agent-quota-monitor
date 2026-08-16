#!/usr/bin/env python3
"""Read Codex rate limits through the official app-server without mutating auth."""
from __future__ import annotations

import argparse
import json
import os
import selectors
import subprocess
import sys
import time
from pathlib import Path


ALLOWED_METHODS = {"initialize", "account/rateLimits/read"}


def send(process: subprocess.Popen[str], request: dict) -> None:
    if request["method"] not in ALLOWED_METHODS:
        raise RuntimeError("probe attempted a prohibited method")
    assert process.stdin is not None
    process.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
    process.stdin.flush()


def receive(process: subprocess.Popen[str], request_id: int, timeout: float) -> dict:
    assert process.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        events = selector.select(max(0.0, deadline - time.monotonic()))
        if not events:
            break
        line = process.stdout.readline()
        if not line:
            break
        value = json.loads(line)
        if value.get("id") == request_id:
            return value
    raise TimeoutError(f"request {request_id} timed out")


def normalized(result: dict) -> dict:
    snapshot = result.get("rateLimits") or {}
    output: dict[str, object] = {
        "contract": "codex-app-server-0.145.0",
        "planType": snapshot.get("planType"),
        "rateLimitReachedType": snapshot.get("rateLimitReachedType"),
    }
    for name in ("primary", "secondary"):
        window = snapshot.get(name)
        if isinstance(window, dict):
            output[name] = {
                key: window.get(key)
                for key in ("usedPercent", "resetsAt", "windowDurationMins")
                if key in window
            }
    credits = snapshot.get("credits")
    if isinstance(credits, dict):
        output["credits"] = {
            key: credits.get(key)
            for key in ("balance", "hasCredits", "unlimited")
            if key in credits
        }
    return output


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--codex", default="codex")
    parser.add_argument("--timeout", type=float, default=12.0)
    args = parser.parse_args()

    process = subprocess.Popen(
        [args.codex, "app-server", "--stdio"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        env={**os.environ, "CODEX_ANALYTICS_ENABLED": "false"},
    )
    try:
        send(process, {
            "id": 1,
            "method": "initialize",
            "params": {
                "clientInfo": {"name": "QuotaBeaconProbe", "title": "QuotaBeacon read-only probe", "version": "0.1.0"},
                "capabilities": {"experimentalApi": True, "optOutNotificationMethods": ["thread/started"]},
            },
        })
        initialized = receive(process, 1, min(3.0, args.timeout))
        if "error" in initialized:
            raise RuntimeError("app-server initialize failed")
        send(process, {"id": 2, "method": "account/rateLimits/read"})
        response = receive(process, 2, args.timeout)
        if "error" in response:
            code = response["error"].get("code", "unknown")
            raise RuntimeError(f"rate limit read failed: {code}")
        print(json.dumps(normalized(response.get("result") or {}), indent=2, sort_keys=True))
        return 0
    finally:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=2)


if __name__ == "__main__":
    sys.exit(main())


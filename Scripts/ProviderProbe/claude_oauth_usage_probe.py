#!/usr/bin/env python3
"""Run one redacted, read-only Claude OAuth usage probe."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from typing import Any


SERVICE = "Claude Code-credentials"
ENDPOINT = "https://api.anthropic.com/api/oauth/usage"


def read_keychain_credentials() -> bytes:
    account = os.environ.get("USER") or os.environ.get("USERNAME") or "user"
    completed = subprocess.run(
        [
            "/usr/bin/security",
            "find-generic-password",
            "-s",
            SERVICE,
            "-a",
            account,
            "-w",
        ],
        check=True,
        capture_output=True,
        timeout=8,
    )
    if not completed.stdout or len(completed.stdout) > 1_048_576:
        raise ValueError("Claude Keychain credential is unavailable")
    return completed.stdout.strip()


def access_token(credentials: bytes) -> str:
    root = json.loads(credentials)
    token = (root.get("claudeAiOauth") or {}).get("accessToken")
    if not isinstance(token, str) or not token.strip():
        raise ValueError("Claude OAuth access token is unavailable")
    return token.strip()


def inspect_usage(body: bytes) -> dict[str, Any]:
    root = json.loads(body)

    def window(name: str) -> dict[str, Any]:
        value = root.get(name)
        if not isinstance(value, dict):
            return {"kind": name, "present": False}
        percent = value.get("utilization", value.get("used_percentage"))
        return {
            "kind": name,
            "present": isinstance(percent, (int, float)) and 0 <= percent <= 100,
            "resetPresent": value.get("resets_at") is not None,
        }

    fable_present = any(
        isinstance(item, dict)
        and item.get("kind") == "weekly_scoped"
        and isinstance(item.get("percent"), (int, float))
        and str((((item.get("scope") or {}).get("model") or {}).get("display_name") or "")).casefold()
        == "fable"
        for item in root.get("limits", [])
        if isinstance(root.get("limits"), list)
    )
    return {
        "windows": [window("five_hour"), window("seven_day")],
        "fableWeeklyPresent": fable_present,
    }


def run_probe(opener: Any = urllib.request.urlopen) -> dict[str, Any]:
    before = read_keychain_credentials()
    request = urllib.request.Request(
        ENDPOINT,
        headers={
            "Authorization": f"Bearer {access_token(before)}",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-code/2.1.0",
            "Accept": "application/json",
        },
        method="GET",
    )
    try:
        with opener(request, timeout=10) as response:
            inspected = inspect_usage(response.read())
            status = response.status
    except urllib.error.HTTPError as error:
        inspected = {"windows": [], "fableWeeklyPresent": False}
        status = error.code
    after = read_keychain_credentials()
    return {
        "provider": "claude",
        "endpoint": ENDPOINT,
        "method": "GET",
        "httpStatus": status,
        **inspected,
        "credentialSource": "macos-keychain",
        "credentialUnchanged": hashlib.sha256(before).digest() == hashlib.sha256(after).digest(),
        "rawPayloadStored": False,
    }


def main() -> int:
    try:
        print(json.dumps(run_probe(), ensure_ascii=False, sort_keys=True))
        return 0
    except Exception as error:
        print(
            json.dumps(
                {
                    "provider": "claude",
                    "status": "failed",
                    "errorType": type(error).__name__,
                    "rawPayloadStored": False,
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )
        return 1


if __name__ == "__main__":
    sys.exit(main())

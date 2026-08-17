#!/usr/bin/env python3
"""Probe Grok's first-party CLI billing backend without exposing private values."""
from __future__ import annotations

import json
import os
import stat
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import safe_validation


ENDPOINT = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
MAX_RESPONSE_BYTES = 1024 * 1024


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req: Any, fp: Any, code: int, msg: str, headers: Any, newurl: str) -> None:
        return None


def select_credential(payload: dict[str, Any]) -> tuple[str, str] | None:
    candidates: list[tuple[int, dict[str, Any]]] = []
    for scope, value in payload.items():
        if not isinstance(value, dict):
            continue
        priority = 0 if scope.startswith("https://auth.x.ai::") else 1
        candidates.append((priority, value))
    for _, value in sorted(candidates, key=lambda item: item[0]):
        token = value.get("key")
        user_id = value.get("user_id")
        if isinstance(token, str) and token and isinstance(user_id, str) and user_id:
            return token, user_id
    return None


def summarize_response(payload: Any) -> dict[str, Any]:
    config = payload.get("config") if isinstance(payload, dict) else None
    config = config if isinstance(config, dict) else {}
    period = config.get("currentPeriod")
    period = period if isinstance(period, dict) else {}
    period_type = period.get("type")
    normalized_period = period_type.upper() if isinstance(period_type, str) else ""
    if "WEEK" in normalized_period:
        period_category = "weekly"
    elif "MONTH" in normalized_period:
        period_category = "monthly"
    elif normalized_period:
        period_category = "unknown"
    else:
        period_category = "absent"
    return {
        "configPresent": bool(config),
        "creditUsagePercentPresent": "creditUsagePercent" in config,
        "currentPeriodPresent": bool(period),
        "periodCategory": period_category,
        "resetPresent": "end" in period or "billingPeriodEnd" in config,
        "prepaidBalancePresent": "prepaidBalance" in config,
        "unifiedBillingEvidencePresent": "isUnifiedBillingUser" in config,
    }


def credential_fingerprint(path: Path) -> dict[str, Any]:
    return safe_validation.fingerprint(safe_validation.FileTarget("grok_auth", path))


def unchanged(before: dict[str, Any], after: dict[str, Any]) -> dict[str, bool]:
    return {
        "sha256": before.get("sha256") == after.get("sha256"),
        "mtime": before.get("mtimeNs") == after.get("mtimeNs"),
        "mode": before.get("mode") == after.get("mode"),
    }


def main() -> int:
    auth_path = Path.home() / ".grok" / "auth.json"
    before = credential_fingerprint(auth_path)
    if before.get("state") != "regular" or before.get("mode") != "0600" or not before.get("ownerCompliant"):
        print(json.dumps({"ok": False, "error": "credential_file_rejected"}, sort_keys=True))
        return 2
    try:
        payload = json.loads(auth_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        print(json.dumps({"ok": False, "error": "credential_document_invalid"}, sort_keys=True))
        return 2
    credential = select_credential(payload if isinstance(payload, dict) else {})
    if credential is None:
        print(json.dumps({"ok": False, "error": "credential_material_missing"}, sort_keys=True))
        return 2
    token, user_id = credential
    request = urllib.request.Request(
        ENDPOINT,
        method="GET",
        headers={
            "Authorization": f"Bearer {token}",
            "X-XAI-Token-Auth": "xai-grok-cli",
            "x-userid": user_id,
            "x-grok-client-version": "1.0.4",
            "Accept": "application/json",
        },
    )
    status: int | None = None
    response_body = b""
    error: str | None = None
    try:
        opener = urllib.request.build_opener(NoRedirect())
        with opener.open(request, timeout=20) as response:
            status = response.status
            response_body = response.read(MAX_RESPONSE_BYTES + 1)
    except urllib.error.HTTPError as caught:
        status = caught.code
        error = "http_error"
    except Exception:
        error = "transport_error"

    after = credential_fingerprint(auth_path)
    evidence: dict[str, Any] = {
        "ok": status is not None and 200 <= status < 300 and error is None,
        "status": status,
        "error": error,
        "credentialUnchanged": unchanged(before, after),
    }
    if len(response_body) > MAX_RESPONSE_BYTES:
        evidence.update({"ok": False, "error": "response_too_large"})
    elif response_body:
        try:
            evidence["contract"] = summarize_response(json.loads(response_body))
        except json.JSONDecodeError:
            evidence.update({"ok": False, "error": "malformed_response"})
    print(json.dumps(evidence, indent=2, sort_keys=True))
    return 0 if evidence["ok"] and all(evidence["credentialUnchanged"].values()) else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Run the installed official GLM usage plugin once and emit redacted evidence."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any


MAX_PROFILE_BYTES = 1_048_576
MAX_OUTPUT_BYTES = 2 * 1_024 * 1_024
ALIAS_PATTERN = re.compile(r"^\s*alias\s+claude-glm=")


class ProbeError(Exception):
    pass


def parse_profile(contents: str) -> dict[str, str]:
    line = next((line for line in contents.splitlines() if ALIAS_PATTERN.match(line)), None)
    if line is None:
        raise ProbeError("profile_missing")
    raw = line.split("=", 1)[1].strip()
    try:
        parts = shlex.split(raw)
        if len(parts) == 1 and any(char.isspace() for char in parts[0]):
            parts = shlex.split(parts[0])
    except ValueError as error:
        raise ProbeError("profile_malformed") from error

    selected: dict[str, str] = {}
    command: str | None = None
    for part in parts:
        if command is not None:
            continue
        if "=" in part and not part.startswith("="):
            key, value = part.split("=", 1)
            if key in {"ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN"}:
                selected[key] = value
        else:
            command = part

    if Path(command or "").name != "claude":
        raise ProbeError("profile_malformed")
    if not selected.get("ANTHROPIC_AUTH_TOKEN"):
        raise ProbeError("credential_missing")
    if not selected.get("ANTHROPIC_BASE_URL", "").startswith("https://api.z.ai/api/anthropic"):
        raise ProbeError("unsupported_base_url")
    return selected


def extract_quota(stdout: bytes) -> dict[str, Any]:
    if len(stdout) > MAX_OUTPUT_BYTES:
        raise ProbeError("output_too_large")
    text = stdout.decode("utf-8", errors="replace")
    if "Platform: ZAI" not in text:
        raise ProbeError("unsupported_platform")
    lines = text.splitlines()
    try:
        marker = next(index for index, line in enumerate(lines) if line.strip() == "Quota limit data:")
    except StopIteration as error:
        raise ProbeError("quota_section_missing") from error
    for line in lines[marker + 1 :]:
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as error:
            raise ProbeError("quota_malformed") from error
        if not isinstance(value, dict):
            raise ProbeError("quota_malformed")
        return value
    raise ProbeError("quota_section_missing")


def redacted_evidence(quota: dict[str, Any], version: str, unchanged: bool) -> dict[str, Any]:
    types: list[str] = []
    percentages_valid = True
    for item in quota.get("limits", []):
        if not isinstance(item, dict):
            continue
        kind = item.get("type")
        if kind == "Token usage(5 Hour)":
            types.append("token_5_hour")
        elif kind == "MCP usage(1 Month)":
            types.append("mcp_monthly")
        else:
            continue
        percent = item.get("percentage")
        percentages_valid = percentages_valid and isinstance(percent, (int, float)) and 0 <= percent <= 100
    return {
        "ok": len(set(types)) == 2 and percentages_valid and unchanged,
        "platform": "ZAI",
        "pluginVersion": version,
        "limitTypes": sorted(set(types)),
        "percentagesValid": percentages_valid,
        "profileUnchanged": unchanged,
    }


def safe_regular_file(path: Path) -> bool:
    return path.is_file() and not path.is_symlink()


def locate_plugin(home: Path) -> tuple[Path, str]:
    root = home / ".claude/plugins/cache/zai-coding-plugins/glm-plan-usage"
    for version_dir in sorted(root.glob("*"), key=lambda value: value.name, reverse=True):
        script = version_dir / "skills/usage-query-skill/scripts/query-usage.mjs"
        manifest = version_dir / ".claude-plugin/plugin.json"
        if not safe_regular_file(script) or not safe_regular_file(manifest):
            continue
        try:
            metadata = json.loads(manifest.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if metadata.get("name") == "glm-plan-usage" and metadata.get("version") == version_dir.name:
            return script, version_dir.name
    raise ProbeError("official_plugin_missing")


def locate_node(home: Path) -> Path:
    candidates = [
        home / ".local/bin/node",
        Path("/opt/homebrew/bin/node"),
        Path("/usr/local/bin/node"),
        Path("/usr/bin/node"),
    ]
    candidates.extend(sorted((home / ".nvm/versions/node").glob("*/bin/node"), reverse=True))
    for candidate in candidates:
        if safe_regular_file(candidate) and os.access(candidate, os.X_OK):
            return candidate
    raise ProbeError("node_missing")


def fingerprint(path: Path) -> tuple[str, int]:
    return hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mtime_ns


def main() -> int:
    home = Path.home()
    profile_path = home / ".zshrc"
    try:
        if not safe_regular_file(profile_path) or profile_path.stat().st_size > MAX_PROFILE_BYTES:
            raise ProbeError("profile_unavailable")
        before = fingerprint(profile_path)
        profile = parse_profile(profile_path.read_text())
        script, version = locate_plugin(home)
        node = locate_node(home)
        completed = subprocess.run(
            [str(node), str(script)],
            env={
                "ANTHROPIC_BASE_URL": profile["ANTHROPIC_BASE_URL"],
                "ANTHROPIC_AUTH_TOKEN": profile["ANTHROPIC_AUTH_TOKEN"],
                "LANG": "en_US.UTF-8",
            },
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=25,
            check=False,
        )
        after = fingerprint(profile_path)
        if completed.returncode != 0:
            combined = (completed.stderr + completed.stdout).lower()
            if b"http 401" in combined or b"http 403" in combined:
                raise ProbeError("authentication_required")
            if b"http 429" in combined:
                raise ProbeError("rate_limited")
            raise ProbeError("official_query_failed")
        evidence = redacted_evidence(extract_quota(completed.stdout), version, before == after)
        print(json.dumps(evidence, sort_keys=True))
        return 0 if evidence["ok"] else 1
    except subprocess.TimeoutExpired:
        print(json.dumps({"ok": False, "reason": "timeout"}, sort_keys=True))
        return 1
    except (OSError, ProbeError) as error:
        reason = error.args[0] if error.args else "probe_failed"
        print(json.dumps({"ok": False, "reason": reason}, sort_keys=True))
        return 1


if __name__ == "__main__":
    sys.exit(main())

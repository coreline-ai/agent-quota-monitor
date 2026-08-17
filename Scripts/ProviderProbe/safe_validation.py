#!/usr/bin/env python3
"""Collect redacted, read-only validation evidence for QuotaBeacon providers.

The tool never prints credential contents, account identifiers, e-mail addresses,
or unredacted home-directory paths. It does not perform model calls, logins,
logouts, token refresh commands, or configuration writes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import time
from datetime import datetime
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPORT_SCHEMA = 1
DEFAULT_BUNDLE_ID = "ai.coreline.quotabeacon"
SAFE_ENUM = re.compile(r"^[A-Za-z0-9_.+-]{1,64}$")
PROVIDER_COMMANDS = {
    "codex": ("codex",),
    "claude": ("claude",),
    "grok": ("grok",),
    "glm": ("glm", "zai"),
}


@dataclass(frozen=True)
class FileTarget:
    label: str
    path: Path
    strict_permissions: bool = True


def home_path(relative: str, *, home: Path | None = None) -> Path:
    return (home or Path.home()) / relative


def default_file_targets(*, home: Path | None = None) -> list[FileTarget]:
    return [
        FileTarget("codex_auth", home_path(".codex/auth.json", home=home)),
        FileTarget("codex_config", home_path(".codex/config.toml", home=home)),
        FileTarget("claude_settings", home_path(".claude/settings.json", home=home)),
        FileTarget("claude_credentials", home_path(".claude/.credentials.json", home=home)),
        FileTarget("claude_plugins", home_path(".claude/plugins/installed_plugins.json", home=home)),
        FileTarget("grok_auth", home_path(".grok/auth.json", home=home)),
        FileTarget("grok_config", home_path(".grok/config.toml", home=home)),
        FileTarget("zai_config", home_path(".zai/config.json", home=home)),
        FileTarget("glm_config", home_path(".glm/config.json", home=home)),
    ]


def redact_path(value: str, *, home: Path | None = None) -> str:
    home_text = str((home or Path.home()).resolve())
    if value == home_text:
        return "$HOME"
    if value.startswith(home_text + os.sep):
        return "$HOME" + value[len(home_text):]
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(64 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def fingerprint(target: FileTarget, *, expected_uid: int | None = None) -> dict[str, Any]:
    expected_uid = os.getuid() if expected_uid is None else expected_uid
    try:
        info = target.path.lstat()
    except FileNotFoundError:
        return {"label": target.label, "state": "missing"}
    except OSError:
        return {"label": target.label, "state": "unreadable_metadata"}

    mode = stat.S_IMODE(info.st_mode)
    common: dict[str, Any] = {
        "label": target.label,
        "mode": f"{mode:04o}",
        "ownerCompliant": info.st_uid == expected_uid,
        "permissionCompliant": (mode & 0o077) == 0 if target.strict_permissions else True,
        "mtimeNs": info.st_mtime_ns,
    }
    if stat.S_ISLNK(info.st_mode):
        return {**common, "state": "symlink_rejected"}
    if not stat.S_ISREG(info.st_mode):
        return {**common, "state": "not_regular"}
    try:
        digest = sha256_file(target.path)
    except OSError:
        return {**common, "state": "unreadable"}
    return {**common, "state": "regular", "sha256": digest}


def run_command(command: list[str], *, timeout: float = 4.0) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def safe_version(executable: str) -> dict[str, Any]:
    path = shutil.which(executable)
    if path is None:
        return {"installed": False}
    result = run_command([path, "--version"])
    if result is None:
        return {"installed": True, "path": redact_path(path), "versionState": "timeout_or_launch_failed"}
    lines = [line.strip() for line in (result.stdout + "\n" + result.stderr).splitlines() if line.strip()]
    dotted_version = re.compile(r"\b\d+(?:\.\d+){1,3}\b")
    candidates = [line for line in lines if dotted_version.search(line)]
    version = candidates[0] if candidates else "unavailable"
    version = redact_path(version)
    if len(version) > 160:
        version = version[:160]
    return {
        "installed": True,
        "path": redact_path(path),
        "version": version,
        "exitCode": result.returncode,
    }


def inventory() -> dict[str, Any]:
    output: dict[str, Any] = {}
    for provider, candidates in PROVIDER_COMMANDS.items():
        detected = [safe_version(command) | {"command": command} for command in candidates]
        output[provider] = {
            "detected": any(item["installed"] for item in detected),
            "candidates": detected,
        }
    return output


def load_json_object(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def _epoch_seconds(value: Any) -> float | None:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        numeric = float(value)
        return numeric / 1000 if numeric > 10_000_000_000 else numeric
    if isinstance(value, str):
        try:
            numeric = float(value)
        except ValueError:
            try:
                return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
            except ValueError:
                return None
        return numeric / 1000 if numeric > 10_000_000_000 else numeric
    return None


def credential_document_summary(path: Path) -> dict[str, Any]:
    payload = load_json_object(path)
    if payload is None:
        return {"documentReadable": False, "hasCredentialMaterial": False, "expirationEvidence": "unknown"}

    has_material = False
    expirations: list[float] = []

    def walk(value: Any) -> None:
        nonlocal has_material
        if isinstance(value, dict):
            for key, child in value.items():
                normalized = re.sub(r"[^a-z]", "", key.lower())
                if any(marker in normalized for marker in ("token", "credential")) and bool(child):
                    has_material = True
                if normalized in {"expiresat", "expiration", "expires", "expiry", "expirytime"}:
                    epoch = _epoch_seconds(child)
                    if epoch is not None:
                        expirations.append(epoch)
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(payload)
    now = time.time()
    if any(epoch > now for epoch in expirations):
        expiration_evidence = "future_present"
    elif expirations:
        expiration_evidence = "expired_only"
    else:
        expiration_evidence = "unknown"
    return {
        "documentReadable": True,
        "hasCredentialMaterial": has_material,
        "expirationEvidence": expiration_evidence,
    }


def claude_settings_summary(path: Path | None = None) -> dict[str, Any]:
    path = path or home_path(".claude/settings.json")
    settings = load_json_object(path)
    if settings is None:
        return {"settingsReadable": False}

    status_line = settings.get("statusLine")
    env_value = settings.get("env")
    env = env_value if isinstance(env_value, dict) else {}
    endpoint = env.get("ANTHROPIC_BASE_URL")
    endpoint_text = endpoint if isinstance(endpoint, str) else ""
    glm_endpoint = "api.z.ai" in endpoint_text or "bigmodel.cn" in endpoint_text
    credential_keys = ("ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY")
    model_keys = (
        "ANTHROPIC_DEFAULT_OPUS_MODEL",
        "ANTHROPIC_DEFAULT_SONNET_MODEL",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL",
    )
    status_type = status_line.get("type") if isinstance(status_line, dict) else None
    return {
        "settingsReadable": True,
        "statusLineConfigured": isinstance(status_line, dict),
        "statusLineType": status_type if isinstance(status_type, str) and SAFE_ENUM.fullmatch(status_type) else None,
        "glmEndpointConfigured": glm_endpoint,
        "glmCredentialConfigured": any(key in env and bool(env.get(key)) for key in credential_keys),
        "glmModelMappingCount": sum(1 for key in model_keys if key in env and bool(env.get(key))),
    }


def claude_auth_summary(executable: str | None) -> dict[str, Any]:
    if executable is None:
        return {"state": "cli_missing"}
    result = run_command([executable, "auth", "status", "--json"])
    if result is None:
        return {"state": "timeout_or_launch_failed"}
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError:
        return {"state": "malformed", "exitCode": result.returncode}
    if not isinstance(value, dict):
        return {"state": "malformed", "exitCode": result.returncode}

    logged_in = value.get("loggedIn")
    auth_method = value.get("authMethod")
    provider = value.get("apiProvider")
    return {
        "state": "ok" if result.returncode == 0 else "command_failed",
        "loggedIn": logged_in if isinstance(logged_in, bool) else None,
        "authMethod": auth_method if isinstance(auth_method, str) and SAFE_ENUM.fullmatch(auth_method) else None,
        "apiProvider": provider if isinstance(provider, str) and SAFE_ENUM.fullmatch(provider) else None,
        "exitCode": result.returncode,
    }


def claude_plugin_summary(executable: str | None) -> dict[str, Any]:
    if executable is None:
        return {"state": "cli_missing", "glmPlanUsageInstalled": False}
    result = run_command([executable, "plugin", "list", "--json"], timeout=6.0)
    if result is None:
        return {"state": "timeout_or_launch_failed", "glmPlanUsageInstalled": False}
    # Only a boolean derived from the official plugin identifier is retained.
    installed = "glm-plan-usage" in result.stdout.lower()
    try:
        json.loads(result.stdout)
        state = "ok" if result.returncode == 0 else "command_failed"
    except json.JSONDecodeError:
        state = "malformed"
    return {"state": state, "glmPlanUsageInstalled": installed, "exitCode": result.returncode}


def command_names(help_text: str) -> list[str]:
    names: list[str] = []
    in_commands = False
    for line in help_text.splitlines():
        if line.strip() == "Commands:":
            in_commands = True
            continue
        if in_commands and line and not line[0].isspace():
            break
        if in_commands:
            match = re.match(r"^\s{2}([a-zA-Z][a-zA-Z0-9_-]*)\s+", line)
            if match:
                names.append(match.group(1))
    return names


def file_contains_marker(path: Path, marker: bytes) -> bool:
    overlap = max(0, len(marker) - 1)
    tail = b""
    try:
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                value = tail + block
                if marker in value:
                    return True
                tail = value[-overlap:] if overlap else b""
    except OSError:
        return False
    return False


def grok_capability_summary(executable: str | None) -> dict[str, Any]:
    if executable is None:
        return {
            "state": "cli_missing",
            "quotaCommandDocumented": False,
            "agentStdioDocumented": False,
            "billingExtensionEmbedded": False,
        }
    top = run_command([executable, "--help"])
    agent = run_command([executable, "agent", "--help"])
    if top is None:
        return {
            "state": "timeout_or_launch_failed",
            "quotaCommandDocumented": False,
            "agentStdioDocumented": False,
            "billingExtensionEmbedded": file_contains_marker(Path(executable), b"x.ai/billing"),
        }
    names = command_names(top.stdout + "\n" + top.stderr)
    agent_names = command_names(agent.stdout + "\n" + agent.stderr) if agent else []
    quota_names = {"usage", "quota", "limits", "billing"}
    billing_embedded = file_contains_marker(Path(executable), b"x.ai/billing")
    return {
        "state": "ok" if top.returncode == 0 else "command_failed",
        "quotaCommandDocumented": any(name in quota_names for name in names),
        "agentStdioDocumented": "stdio" in agent_names,
        "billingExtensionEmbedded": billing_embedded,
        "quotaContract": "first_party_cli_backend_observed" if billing_embedded else "unavailable",
        "loginCommandDocumented": "login" in names,
        "authEvidence": "credential_file_only",
        "exitCode": top.returncode,
    }


def export_preferences(bundle_id: str = DEFAULT_BUNDLE_ID) -> dict[str, Any] | None:
    result = run_command(["defaults", "export", bundle_id, "-"], timeout=3.0)
    if result is None or result.returncode != 0:
        return None
    try:
        value = plistlib.loads(result.stdout.encode("utf-8"))
    except (plistlib.InvalidFileException, ValueError):
        return None
    return value if isinstance(value, dict) else None


def claude_connection_summary(bundle_id: str = DEFAULT_BUNDLE_ID) -> dict[str, Any]:
    preferences = export_preferences(bundle_id)
    if preferences is None:
        return {
            "preferencesPresent": False,
            "enabled": False,
            "contract": "keychain_oauth_usage_observed",
        }
    direct_preference_present = "claude.readOnlyEnabled" in preferences
    enabled = (
        preferences.get("claude.readOnlyEnabled") is True
        if direct_preference_present
        else preferences.get("claude.snapshotEnabled") is True
    )
    return {
        "preferencesPresent": True,
        "enabled": enabled,
        "contract": "keychain_oauth_usage_observed",
        "automaticCredentialDiscovery": True,
        "separatePathRequired": False,
        "legacyPreferenceMigrated": not direct_preference_present and "claude.snapshotEnabled" in preferences,
    }


def public_report(*, include_fingerprints: bool = True) -> dict[str, Any]:
    cli = inventory()
    claude_path = shutil.which("claude")
    grok_path = shutil.which("grok")
    report: dict[str, Any] = {
        "schemaVersion": REPORT_SCHEMA,
        "generatedAt": int(time.time()),
        "inventory": cli,
        "claude": {
            "auth": claude_auth_summary(claude_path),
            "settings": claude_settings_summary(),
            "plugins": claude_plugin_summary(claude_path),
            "connection": claude_connection_summary(),
        },
        "grok": {
            **grok_capability_summary(grok_path),
            "credential": credential_document_summary(home_path(".grok/auth.json")),
        },
        "glm": {
            "standaloneDetected": cli["glm"]["detected"],
            "supportedBridge": "claude_glm_plan_usage_plugin",
        },
    }
    if include_fingerprints:
        report["fingerprints"] = [fingerprint(target) for target in default_file_targets()]
    return report


def compare_fingerprints(before: list[dict[str, Any]], after: list[dict[str, Any]]) -> list[dict[str, Any]]:
    before_by_label = {item.get("label"): item for item in before}
    changes: list[dict[str, Any]] = []
    for current in after:
        label = current.get("label")
        previous = before_by_label.get(label)
        changes.append({
            "label": label,
            "stateBefore": previous.get("state") if previous else None,
            "stateAfter": current.get("state"),
            "sha256Changed": (
                previous.get("sha256") != current.get("sha256")
                if previous and previous.get("state") == current.get("state") == "regular"
                else previous != current
            ),
            "mtimeChanged": previous.get("mtimeNs") != current.get("mtimeNs") if previous else True,
            "modeChanged": previous.get("mode") != current.get("mode") if previous else True,
        })
    return changes


def write_private_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.chmod(path, 0o600)


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def redacted_for_stdout(report: dict[str, Any]) -> dict[str, Any]:
    value = json.loads(json.dumps(report))
    for item in value.get("fingerprints", []):
        item.pop("sha256", None)
        item.pop("mtimeNs", None)
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect_parser = subparsers.add_parser("inspect", help="Print a redacted local validation report")
    inspect_parser.add_argument("--output", type=Path)

    baseline_parser = subparsers.add_parser("baseline", help="Write a private fingerprint baseline")
    baseline_parser.add_argument("--output", type=Path, required=True)

    compare_parser = subparsers.add_parser("compare", help="Compare current fingerprints with a baseline")
    compare_parser.add_argument("--baseline", type=Path, required=True)
    compare_parser.add_argument("--output", type=Path)

    args = parser.parse_args()
    if args.command == "inspect":
        report = public_report()
        if args.output:
            write_private_json(args.output, report)
        print(json.dumps(redacted_for_stdout(report), indent=2, sort_keys=True))
        return 0
    if args.command == "baseline":
        value = {
            "schemaVersion": REPORT_SCHEMA,
            "createdAt": int(time.time()),
            "fingerprints": [fingerprint(target) for target in default_file_targets()],
        }
        write_private_json(args.output, value)
        print(json.dumps({"baselineWritten": True, "fileCount": len(value["fingerprints"])}))
        return 0

    baseline = read_json(args.baseline)
    current = [fingerprint(target) for target in default_file_targets()]
    comparison = {
        "schemaVersion": REPORT_SCHEMA,
        "comparedAt": int(time.time()),
        "changes": compare_fingerprints(baseline.get("fingerprints", []), current),
    }
    if args.output:
        write_private_json(args.output, comparison)
    print(json.dumps(comparison, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())

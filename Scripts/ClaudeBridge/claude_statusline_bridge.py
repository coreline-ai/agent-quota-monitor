#!/usr/bin/env python3
"""Persist only Claude rate-limit fields, then run the user's original status line."""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


MAX_INPUT_BYTES = 2 * 1024 * 1024
SUPPORT_ROOT = Path(
    os.environ.get(
        "QUOTABEACON_CLAUDE_BRIDGE_ROOT",
        Path.home() / "Library/Application Support/QuotaBeacon",
    )
)
CONFIG_PATH = SUPPORT_ROOT / "claude-bridge-config.json"
SNAPSHOT_PATH = SUPPORT_ROOT / "claude-status.json"


def finite_number(value: Any) -> float | int | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return value if math.isfinite(float(value)) else None


def sanitized_snapshot(payload: Any) -> dict[str, Any] | None:
    if not isinstance(payload, dict):
        return None
    source = payload.get("rate_limits")
    if not isinstance(source, dict):
        return None

    windows: dict[str, dict[str, float | int]] = {}
    for name in ("five_hour", "seven_day"):
        raw_window = source.get(name)
        if not isinstance(raw_window, dict):
            continue
        output: dict[str, float | int] = {}
        percent = finite_number(raw_window.get("used_percentage"))
        if percent is not None and 0 <= float(percent) <= 100:
            output["used_percentage"] = percent
        reset = finite_number(raw_window.get("resets_at"))
        if reset is not None and float(reset) > 0:
            output["resets_at"] = reset
        if output:
            windows[name] = output
    return {"rate_limits": windows} if windows else None


def atomic_json_write(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def original_command() -> str | None:
    try:
        config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None
    value = config.get("originalStatusLine") if isinstance(config, dict) else None
    command = value.get("command") if isinstance(value, dict) else None
    return command if isinstance(command, str) and command.strip() else None


def main() -> int:
    raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
    if len(raw) <= MAX_INPUT_BYTES:
        try:
            snapshot = sanitized_snapshot(json.loads(raw))
            if snapshot is not None:
                atomic_json_write(SNAPSHOT_PATH, snapshot)
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
            pass

    command = original_command()
    if command is None:
        return 0
    try:
        completed = subprocess.run(
            command,
            shell=True,
            executable="/bin/zsh",
            input=raw,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError:
        return 1
    sys.stdout.buffer.write(completed.stdout)
    sys.stderr.buffer.write(completed.stderr)
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())

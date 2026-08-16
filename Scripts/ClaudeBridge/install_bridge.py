#!/usr/bin/env python3
"""Install the opt-in QuotaBeacon Claude status-line bridge."""

from __future__ import annotations

import json
import os
import shutil
import stat
import tempfile
from pathlib import Path
from typing import Any


HOME = Path.home()
CLAUDE_ROOT = HOME / ".claude"
SETTINGS_PATH = CLAUDE_ROOT / "settings.json"
BRIDGE_PATH = CLAUDE_ROOT / "quotabeacon-statusline-bridge.py"
SUPPORT_ROOT = HOME / "Library/Application Support/QuotaBeacon"
CONFIG_PATH = SUPPORT_ROOT / "claude-bridge-config.json"
SNAPSHOT_PATH = SUPPORT_ROOT / "claude-status.json"


def read_object(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def atomic_json_write(path: Path, payload: dict[str, Any], mode: int) -> None:
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        os.chmod(path, mode)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def main() -> int:
    settings = read_object(SETTINGS_PATH)
    status_line = settings.get("statusLine")
    if not isinstance(status_line, dict) or status_line.get("type") != "command":
        raise ValueError("Claude statusLine.type must already be command")

    SUPPORT_ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(SUPPORT_ROOT, 0o700)
    CLAUDE_ROOT.mkdir(parents=True, exist_ok=True)

    bridge_source = Path(__file__).with_name("claude_statusline_bridge.py")
    shutil.copyfile(bridge_source, BRIDGE_PATH)
    os.chmod(BRIDGE_PATH, 0o700)

    current_command = status_line.get("command")
    if current_command == str(BRIDGE_PATH) and CONFIG_PATH.exists():
        original_status_line = read_object(CONFIG_PATH).get("originalStatusLine")
    else:
        original_status_line = status_line
    if not isinstance(original_status_line, dict):
        raise ValueError("Original Claude status line is unavailable")
    original_command = original_status_line.get("command")
    if not isinstance(original_command, str) or not original_command.strip():
        raise ValueError("Original Claude status-line command is unavailable")

    atomic_json_write(
        CONFIG_PATH,
        {
            "schemaVersion": 1,
            "originalStatusLine": original_status_line,
            "snapshotPath": str(SNAPSHOT_PATH),
        },
        0o600,
    )

    updated_status_line = dict(status_line)
    updated_status_line["type"] = "command"
    updated_status_line["command"] = str(BRIDGE_PATH)
    settings["statusLine"] = updated_status_line
    settings_mode = stat.S_IMODE(SETTINGS_PATH.stat().st_mode)
    atomic_json_write(SETTINGS_PATH, settings, settings_mode)

    print(json.dumps({
        "ok": True,
        "bridgeInstalled": True,
        "originalStatusLinePreserved": True,
        "snapshotPath": str(SNAPSHOT_PATH),
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

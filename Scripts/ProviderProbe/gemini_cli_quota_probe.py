#!/usr/bin/env python3
"""Inspect or run Antigravity CLI's read-only /usage command with redacted output."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any


MAX_OUTPUT_BYTES = 512 * 1024
MAX_SETTINGS_BYTES = 1024 * 1024
EXPECT_SCRIPT = r'''
set timeout 22
log_user 1
set env(TERM) "xterm-256color"
set env(NO_COLOR) "1"
proc stop_child {} {
  catch {send "\003"}
  after 150
  catch {send "\003"}
  after 150
  catch {exec /bin/kill -TERM [exp_pid]}
  after 250
  catch {exec /bin/kill -KILL [exp_pid]}
  catch {close}
  catch {wait}
}
spawn -noecho $env(QUOTABEACON_AGY_EXECUTABLE)
stty rows 48 columns 120 < $spawn_out(slave,name)
expect {
  -re {\x1b\[\?2026\$p} { send -- "\033\[?2026;2\$y"; exp_continue -continue_timer }
  -re {\x1b\[\?2027\$p} { send -- "\033\[?2027;2\$y"; exp_continue -continue_timer }
  -re {\x1b\[\?u} { send -- "\033\[?0u"; exp_continue -continue_timer }
  -re {Antigravity CLI [0-9]+[.][0-9]+[.][0-9]+} {}
  -re {Do you trust the contents} { stop_child; exit 44 }
  timeout { stop_child; exit 45 }
  eof { exit 46 }
}
send -- "/usage\r"
set timeout 12
expect {
  -re {\x1b\[\?2026\$p} { send -- "\033\[?2026;2\$y"; exp_continue -continue_timer }
  -re {\x1b\[\?2027\$p} { send -- "\033\[?2027;2\$y"; exp_continue -continue_timer }
  -re {\x1b\[\?u} { send -- "\033\[?0u"; exp_continue -continue_timer }
  -re {Five Hour Limit Remaining} { after 1300 }
  -re {Do you trust the contents} { stop_child; exit 44 }
  timeout {}
  eof { exit 46 }
}
stop_child
exit 0
'''


class ProbeError(Exception):
    pass


def safe_regular_file(path: Path, *, executable: bool = False, maximum_bytes: int) -> bool:
    try:
        info = path.lstat()
    except OSError:
        return False
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        return False
    if info.st_size > maximum_bytes or info.st_uid not in {0, os.getuid()}:
        return False
    return not executable or os.access(path, os.X_OK)


def locate_executable(home: Path, requested: Path | None = None) -> Path:
    candidates = [requested] if requested else [
        home / ".local/bin/agy",
        Path("/opt/homebrew/bin/agy"),
        Path("/usr/local/bin/agy"),
    ]
    for candidate in candidates:
        if candidate and safe_regular_file(candidate, executable=True, maximum_bytes=512 * 1024 * 1024):
            return candidate
    raise ProbeError("official_cli_missing")


def locate_workspace(home: Path) -> tuple[Path, Path]:
    settings = home / ".gemini/antigravity-cli/settings.json"
    if not safe_regular_file(settings, maximum_bytes=MAX_SETTINGS_BYTES):
        raise ProbeError("settings_unavailable")
    try:
        root = json.loads(settings.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ProbeError("settings_invalid") from error
    trusted = root.get("trustedWorkspaces") if isinstance(root, dict) else None
    for value in trusted if isinstance(trusted, list) else []:
        if isinstance(value, str) and value.startswith("/") and Path(value).is_dir():
            return Path(value), settings
    raise ProbeError("trusted_workspace_missing")


def sanitize_tui(data: bytes) -> str:
    text = data.decode("utf-8", errors="replace")
    text = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", "", text)
    text = re.sub(r"\x1bP.*?\x1b\\", "", text, flags=re.DOTALL)
    text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
    return "".join(character for character in text.replace("\r", "\n") if character in "\n\t" or ord(character) >= 32)


def summarize_tui(data: bytes) -> dict[str, Any]:
    if len(data) > MAX_OUTPUT_BYTES:
        raise ProbeError("output_too_large")
    text = sanitize_tui(data)
    starts = list(re.finditer(r"GEMINI MODELS", text, flags=re.IGNORECASE))
    if not starts:
        raise ProbeError("gemini_group_missing")
    group = text[starts[-1].end() :]
    end = re.search(r"CLAUDE AND GPT MODELS", group, flags=re.IGNORECASE)
    if end:
        group = group[: end.start()]

    def bucket(label: str) -> dict[str, bool]:
        match = re.search(re.escape(label), group, flags=re.IGNORECASE)
        if not match:
            return {"present": False, "percentageValid": False, "resetEvidencePresent": False}
        suffix = group[match.end() :]
        next_label = re.search(r"(?:Weekly|Five Hour) Limit Remaining", suffix, flags=re.IGNORECASE)
        section = suffix[: next_label.start()] if next_label else suffix
        percentage = re.search(r"(?<![0-9.+-])([0-9]{1,3}(?:[.][0-9]+)?)\s*%", section)
        valid = bool(percentage and 0 <= float(percentage.group(1)) <= 100)
        return {
            "present": True,
            "percentageValid": valid,
            "resetEvidencePresent": bool(
                re.search(r"Refreshes\s+in\s+(?:[0-9]+\s*[dhm]\s*)+", section, flags=re.IGNORECASE)
                or re.search(r"Quota available", section, flags=re.IGNORECASE)
            ),
        }

    weekly = bucket("Weekly Limit Remaining")
    five_hour = bucket("Five Hour Limit Remaining")
    return {
        "geminiGroupPresent": True,
        "weekly": weekly,
        "fiveHour": five_hour,
        "valuesValid": weekly["percentageValid"] and five_hour["percentageValid"],
        "otherModelGroupExcluded": "CLAUDE AND GPT MODELS" not in group.upper(),
    }


def fingerprint(path: Path) -> tuple[str, int, int]:
    info = path.stat()
    return hashlib.sha256(path.read_bytes()).hexdigest(), info.st_mtime_ns, stat.S_IMODE(info.st_mode)


def safe_environment(home: Path, executable: Path) -> dict[str, str]:
    return {
        "HOME": str(home),
        "USER": os.environ.get("USER", "user"),
        "LOGNAME": os.environ.get("LOGNAME", os.environ.get("USER", "user")),
        "SHELL": os.environ.get("SHELL", "/bin/zsh"),
        "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
        "LANG": "en_US.UTF-8",
        "LC_ALL": "en_US.UTF-8",
        "TERM": "xterm-256color",
        "NO_COLOR": "1",
        "AGY_CLI_DISABLE_AUTO_UPDATE": "1",
        "AGY_CLI_HIDE_ACCOUNT_INFO": "1",
        "QUOTABEACON_AGY_EXECUTABLE": str(executable),
    }


def cli_version(executable: Path, environment: dict[str, str]) -> str:
    try:
        result = subprocess.run(
            [str(executable), "--version"],
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "unavailable"
    match = re.search(rb"\b[0-9]+(?:[.][0-9]+){1,3}\b", result.stdout + result.stderr)
    return match.group().decode("ascii") if match else "unavailable"


def inspect(home: Path, requested: Path | None = None) -> dict[str, Any]:
    executable = locate_executable(home, requested)
    _, settings = locate_workspace(home)
    environment = safe_environment(home, executable)
    return {
        "provider": "gemini",
        "transport": "official-antigravity-cli-usage",
        "installed": True,
        "trustedWorkspacePresent": True,
        "cliVersion": cli_version(executable, environment),
        "settingsReadOnly": safe_regular_file(settings, maximum_bytes=MAX_SETTINGS_BYTES),
        "credentialFilesRead": False,
        "rawOutputStored": False,
    }


def run_live(home: Path, requested: Path | None = None) -> dict[str, Any]:
    executable = locate_executable(home, requested)
    workspace, settings = locate_workspace(home)
    before = fingerprint(settings)
    environment = safe_environment(home, executable)
    try:
        completed = subprocess.run(
            ["/usr/bin/expect", "-c", EXPECT_SCRIPT],
            cwd=workspace,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=45,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise ProbeError("timeout") from error
    output = completed.stdout + completed.stderr
    if len(output) > MAX_OUTPUT_BYTES:
        raise ProbeError("output_too_large")
    if completed.returncode in {45, 47}:
        raise ProbeError("timeout")
    if completed.returncode == 44:
        raise ProbeError("trusted_workspace_required")
    if completed.returncode != 0:
        raise ProbeError("cli_failed")
    contract = summarize_tui(output)
    after = fingerprint(settings)
    return {
        **inspect(home, requested),
        "ok": contract["valuesValid"] and before == after,
        "commandSent": "/usage",
        "modelPromptSent": False,
        "settingsUnchanged": before == after,
        "accountDataReturned": False,
        "contract": contract,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--inspect", action="store_true", help="locate only; do not start agy")
    mode.add_argument("--live", action="store_true", help="run official agy /usage once")
    parser.add_argument("--executable", type=Path)
    args = parser.parse_args()
    try:
        result = run_live(Path.home(), args.executable) if args.live else inspect(Path.home(), args.executable)
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0 if result.get("ok", True) else 1
    except ProbeError as error:
        print(json.dumps({
            "provider": "gemini",
            "ok": False,
            "error": str(error),
            "credentialFilesRead": False,
            "rawOutputStored": False,
        }, sort_keys=True))
        return 1


if __name__ == "__main__":
    sys.exit(main())

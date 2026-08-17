#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "AIQuotaMonitorTests" / "Fixtures"
SENSITIVE_KEY = re.compile(r"(?i)(token|secret|api.?key|cookie|email|account.?id|workspace.?id|session.?id)")
SENSITIVE_VALUE = re.compile(
    r"(?i)(bearer\s+[a-z0-9._-]{12,}|sk-[a-z0-9_-]{12,}|[\w.+-]+@[\w.-]+\.[a-z]{2,}|/Users/[^/\s]+)"
)


def fixture_files() -> list[Path]:
    return sorted(path for path in FIXTURES.rglob("*") if path.is_file())


def inspect(path: Path) -> list[str]:
    errors: list[str] = []
    text = path.read_text(encoding="utf-8", errors="replace")
    if SENSITIVE_VALUE.search(text):
        errors.append("sensitive value pattern")
    if "malformed" not in path.stem and path.suffix.lower() == ".json":
        try:
            value = json.loads(text)
        except json.JSONDecodeError as error:
            errors.append(f"invalid JSON: {error.msg}")
        else:
            def walk(node: object, prefix: str = "$") -> None:
                if isinstance(node, dict):
                    for key, child in node.items():
                        if SENSITIVE_KEY.fullmatch(key):
                            errors.append(f"sensitive key: {prefix}.{key}")
                        walk(child, f"{prefix}.{key}")
                elif isinstance(node, list):
                    for index, child in enumerate(node):
                        walk(child, f"{prefix}[{index}]")
            walk(value)
    elif "malformed" not in path.stem and path.suffix.lower() == ".txt":
        if path.parent.name == "Gemini" and "GEMINI MODELS" not in text:
            errors.append("missing Gemini contract marker")
    elif "malformed" not in path.stem:
        errors.append(f"unsupported fixture format: {path.suffix or '<none>'}")
    return errors


def scan() -> int:
    failures = 0
    for path in fixture_files():
        errors = inspect(path)
        if errors:
            failures += 1
            print(f"FAIL {path.relative_to(ROOT)}: {', '.join(errors)}")
    if failures:
        return 1
    print(f"Fixture guard passed: {len(fixture_files())} files")
    return 0


def manifest() -> int:
    for path in fixture_files():
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        print(f"{digest}  {path.relative_to(ROOT)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("scan", "manifest"))
    args = parser.parse_args()
    return scan() if args.command == "scan" else manifest()


if __name__ == "__main__":
    sys.exit(main())

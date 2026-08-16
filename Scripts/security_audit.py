#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TARGETS = [ROOT / "AIQuotaMonitor", ROOT / "AIQuotaMonitorTests" / "Fixtures"]
TEXT_SUFFIXES = {".swift", ".json", ".strings", ".xcconfig"}
PATTERNS = {
    "private-key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "provider-secret": re.compile(r"(?i)\b(?:sk|xai|glm)-[A-Za-z0-9_-]{16,}\b"),
    "bearer-value": re.compile(r"(?i)bearer\s+[A-Za-z0-9._~+/=-]{16,}"),
    "email": re.compile(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}"),
    "home-path": re.compile(r"/(?:Users|home)/[^/\s\"']+"),
}


def main() -> int:
    findings: list[str] = []
    for root in TARGETS:
        for path in root.rglob("*"):
            if not path.is_file() or path.suffix not in TEXT_SUFFIXES:
                continue
            if "Assets.xcassets" in path.parts:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            for name, pattern in PATTERNS.items():
                for match in pattern.finditer(text):
                    # Test-only literal strings validate the redactor itself.
                    if path.name in {"BoundaryTests.swift", "PresentationTests.swift", "Redactor.swift"}:
                        continue
                    findings.append(f"{path.relative_to(ROOT)}:{name}:{match.start()}")
    if findings:
        print("Security audit failed:")
        print("\n".join(findings))
        return 1
    print("Security audit passed: no credential/PII literals detected in shipping sources or fixtures.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

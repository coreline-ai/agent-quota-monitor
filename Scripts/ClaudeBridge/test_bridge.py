#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


BRIDGE = Path(__file__).with_name("claude_statusline_bridge.py")


class ClaudeBridgeTests(unittest.TestCase):
    def test_snapshot_is_minimal_atomic_and_original_receives_input(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = root / "original.py"
            original.write_text(
                "#!/usr/bin/env python3\nimport sys\nsys.stdout.buffer.write(sys.stdin.buffer.read())\n",
                encoding="utf-8",
            )
            original.chmod(0o700)
            (root / "claude-bridge-config.json").write_text(json.dumps({
                "originalStatusLine": {"type": "command", "command": str(original)},
            }), encoding="utf-8")
            payload = {
                "session_id": "must-not-persist",
                "rate_limits": {
                    "five_hour": {"used_percentage": 23.5, "resets_at": 1_800_000_000},
                    "seven_day": {"used_percentage": 41.2, "resets_at": 1_800_100_000},
                },
            }
            raw = json.dumps(payload).encode()
            result = subprocess.run(
                [str(BRIDGE)],
                input=raw,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "QUOTABEACON_CLAUDE_BRIDGE_ROOT": str(root)},
                check=True,
            )
            self.assertEqual(result.stdout, raw)
            snapshot_path = root / "claude-status.json"
            snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
            self.assertEqual(snapshot, {"rate_limits": payload["rate_limits"]})
            self.assertNotIn("session_id", snapshot)
            self.assertEqual(stat.S_IMODE(snapshot_path.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()

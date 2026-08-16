from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path
from unittest.mock import patch


MODULE_PATH = Path(__file__).with_name("claude_oauth_usage_probe.py")
SPEC = importlib.util.spec_from_file_location("claude_oauth_usage_probe", MODULE_PATH)
assert SPEC and SPEC.loader
subject = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(subject)


class Response:
    status = 200

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self) -> bytes:
        return json.dumps(
            {
                "five_hour": {"utilization": 12, "resets_at": "2026-08-16T00:00:00Z"},
                "seven_day": {"utilization": 34},
                "limits": [
                    {
                        "kind": "weekly_scoped",
                        "percent": 56,
                        "scope": {"model": {"display_name": "Fable"}},
                    }
                ],
            }
        ).encode()


class ClaudeOAuthUsageProbeTests(unittest.TestCase):
    def test_probe_outputs_only_redacted_contract_evidence(self) -> None:
        credential = json.dumps(
            {"claudeAiOauth": {"accessToken": "private-value", "refreshToken": "ignored"}}
        ).encode()

        captured = {}

        def opener(request, timeout):
            captured["request"] = request
            captured["timeout"] = timeout
            return Response()

        with patch.object(subject, "read_keychain_credentials", side_effect=[credential, credential]):
            result = subject.run_probe(opener=opener)

        self.assertEqual(result["httpStatus"], 200)
        self.assertEqual(result["method"], "GET")
        self.assertTrue(result["credentialUnchanged"])
        self.assertTrue(result["fableWeeklyPresent"])
        self.assertFalse(result["rawPayloadStored"])
        self.assertNotIn("private-value", json.dumps(result))
        self.assertNotIn("refresh", json.dumps(result).lower())
        self.assertEqual(captured["request"].get_method(), "GET")
        self.assertEqual(captured["timeout"], 10)

    def test_access_token_rejects_missing_value(self) -> None:
        with self.assertRaises(ValueError):
            subject.access_token(b'{"claudeAiOauth":{}}')


if __name__ == "__main__":
    unittest.main()

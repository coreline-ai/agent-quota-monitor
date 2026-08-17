#!/usr/bin/env python3
from __future__ import annotations

import json
import unittest

import grok_billing_probe as subject


class GrokBillingProbeTests(unittest.TestCase):
    def test_select_credential_prefers_oidc_without_returning_metadata(self) -> None:
        result = subject.select_credential({
            "https://accounts.x.ai/sign-in": {"key": "fallback", "user_id": "fallback-user"},
            "https://auth.x.ai::tests": {
                "key": "preferred-value",
                "user_id": "preferred-user",
                "refresh_token": "must-not-be-returned",
            },
        })
        self.assertEqual(result, ("preferred-value", "preferred-user"))
        self.assertNotIn("must-not-be-returned", json.dumps(result))

    def test_response_summary_contains_presence_only(self) -> None:
        result = subject.summarize_response({
            "config": {
                "creditUsagePercent": 42.5,
                "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY", "end": "private-reset"},
                "prepaidBalance": {"val": 1234},
                "isUnifiedBillingUser": True,
            },
        })
        encoded = json.dumps(result)
        self.assertTrue(result["creditUsagePercentPresent"])
        self.assertTrue(result["resetPresent"])
        self.assertEqual(result["periodCategory"], "weekly")
        self.assertNotIn("42.5", encoded)
        self.assertNotIn("private-reset", encoded)
        self.assertNotIn("1234", encoded)

        unknown = subject.summarize_response({
            "config": {"currentPeriod": {"type": "FIVE_HOUR"}},
        })
        self.assertEqual(unknown["periodCategory"], "unknown")

    def test_unchanged_compares_only_integrity_fields(self) -> None:
        before = {"sha256": "a", "mtimeNs": 1, "mode": "0600"}
        after = {"sha256": "a", "mtimeNs": 1, "mode": "0600"}
        self.assertEqual(subject.unchanged(before, after), {"sha256": True, "mtime": True, "mode": True})

    def test_redirect_handler_never_follows_location(self) -> None:
        handler = subject.NoRedirect()
        self.assertIsNone(handler.redirect_request(None, None, 302, "redirect", {}, "https://example.invalid"))


if __name__ == "__main__":
    unittest.main()

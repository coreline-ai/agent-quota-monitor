#!/usr/bin/env python3
from __future__ import annotations

import json
import unittest

from glm_plugin_usage_probe import ProbeError, extract_quota, parse_profile, redacted_evidence


class GLMPluginUsageProbeTests(unittest.TestCase):
    def test_profile_parser_selects_only_required_keys(self) -> None:
        profile = parse_profile(
            "alias claude-glm='ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic "
            "ANTHROPIC_AUTH_TOKEN=synthetic API_TIMEOUT_MS=10 EXTRA=ignored claude --flag'"
        )
        self.assertEqual(
            profile,
            {
                "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
                "ANTHROPIC_AUTH_TOKEN": "synthetic",
            },
        )

    def test_profile_parser_rejects_missing_or_wrong_command(self) -> None:
        with self.assertRaises(ProbeError):
            parse_profile("alias claude-glm='ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic claude'")
        with self.assertRaises(ProbeError):
            parse_profile(
                "alias claude-glm='ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic "
                "ANTHROPIC_AUTH_TOKEN=synthetic curl'"
            )

    def test_extractor_ignores_model_and_tool_sections(self) -> None:
        stdout = b"""Platform: ZAI
Model usage data:
{"models":[{"usage":99}]}
Tool usage data:
{"tools":[{"usage":88}]}
Quota limit data:
{"limits":[{"type":"Token usage(5 Hour)","percentage":1},{"type":"MCP usage(1 Month)","percentage":0}]}
"""
        quota = extract_quota(stdout)
        encoded = json.dumps(quota)
        self.assertNotIn("models", encoded)
        self.assertNotIn("tools", encoded)
        evidence = redacted_evidence(quota, "0.0.1", True)
        self.assertTrue(evidence["ok"])
        self.assertNotIn("percentage", evidence)

    def test_evidence_rejects_invalid_percentage(self) -> None:
        quota = {
            "limits": [
                {"type": "Token usage(5 Hour)", "percentage": 101},
                {"type": "MCP usage(1 Month)", "percentage": 0},
            ]
        }
        self.assertFalse(redacted_evidence(quota, "0.0.1", True)["ok"])


if __name__ == "__main__":
    unittest.main()

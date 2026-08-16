#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import safe_validation as subject


class SafeValidationTests(unittest.TestCase):
    def test_fingerprint_regular_file_does_not_expose_path_or_content(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "auth.json"
            path.write_text('{"token":"private-value"}', encoding="utf-8")
            path.chmod(0o600)
            result = subject.fingerprint(subject.FileTarget("auth", path))

        self.assertEqual(result["state"], "regular")
        self.assertEqual(result["mode"], "0600")
        self.assertTrue(result["permissionCompliant"])
        self.assertNotIn("path", result)
        self.assertNotIn("private-value", json.dumps(result))

    def test_fingerprint_rejects_symlink_without_following_it(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "secret"
            target.write_text("do-not-read", encoding="utf-8")
            link = root / "auth.json"
            link.symlink_to(target)
            result = subject.fingerprint(subject.FileTarget("auth", link))

        self.assertEqual(result["state"], "symlink_rejected")
        self.assertNotIn("sha256", result)

    def test_fingerprint_flags_group_or_world_access(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.json"
            path.write_text("{}", encoding="utf-8")
            path.chmod(0o644)
            result = subject.fingerprint(subject.FileTarget("settings", path))

        self.assertFalse(result["permissionCompliant"])

    def test_redact_path_replaces_home_prefix(self) -> None:
        home = Path("/Users/example")
        self.assertEqual(
            subject.redact_path("/Users/example/.local/bin/tool", home=home),
            "$HOME/.local/bin/tool",
        )

    def test_claude_settings_summary_only_emits_safe_booleans(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.json"
            path.write_text(json.dumps({
                "statusLine": {"type": "command", "command": "echo hidden"},
                "env": {
                    "ANTHROPIC_BASE_URL": "https://api.z.ai/api/anthropic",
                    "ANTHROPIC_AUTH_TOKEN": "secret-token",
                    "ANTHROPIC_DEFAULT_OPUS_MODEL": "GLM-5.1",
                },
            }), encoding="utf-8")
            result = subject.claude_settings_summary(path)

        encoded = json.dumps(result)
        self.assertTrue(result["statusLineConfigured"])
        self.assertTrue(result["glmEndpointConfigured"])
        self.assertTrue(result["glmCredentialConfigured"])
        self.assertEqual(result["glmModelMappingCount"], 1)
        self.assertNotIn("secret-token", encoded)
        self.assertNotIn("echo hidden", encoded)

    def test_credential_document_summary_does_not_emit_token(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "auth.json"
            path.write_text(json.dumps({
                "access_token": "private-token",
                "expires_at": subject.time.time() + 3600,
            }), encoding="utf-8")
            result = subject.credential_document_summary(path)

        self.assertTrue(result["documentReadable"])
        self.assertTrue(result["hasCredentialMaterial"])
        self.assertEqual(result["expirationEvidence"], "future_present")
        self.assertNotIn("private-token", json.dumps(result))

    def test_command_names_ignores_usage_heading(self) -> None:
        text = "Usage: grok [COMMAND]\n\nCommands:\n  login   Sign in\n  doctor  Diagnose\n\nOptions:\n"
        self.assertEqual(subject.command_names(text), ["login", "doctor"])

    def test_file_contains_marker_across_chunk_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "grok"
            path.write_bytes(b"a" * (1024 * 1024 - 3) + b"x.ai/billing")
            self.assertTrue(subject.file_contains_marker(path, b"x.ai/billing"))
            self.assertFalse(subject.file_contains_marker(path, b"private/method"))

    @mock.patch("safe_validation.file_contains_marker", return_value=True)
    @mock.patch("safe_validation.run_command")
    def test_grok_capability_checks_nested_agent_stdio(self, run_command: mock.Mock, _marker: mock.Mock) -> None:
        run_command.side_effect = [
            subject.subprocess.CompletedProcess(
                ["grok", "--help"], 0,
                stdout="Commands:\n  login   Sign in\n  agent   Run agent\n", stderr="",
            ),
            subject.subprocess.CompletedProcess(
                ["grok", "agent", "--help"], 0,
                stdout="Commands:\n  stdio   Run over stdio\n", stderr="",
            ),
        ]
        result = subject.grok_capability_summary("/tmp/grok")
        self.assertFalse(result["quotaCommandDocumented"])
        self.assertTrue(result["agentStdioDocumented"])
        self.assertTrue(result["billingExtensionEmbedded"])
        self.assertEqual(result["quotaContract"], "first_party_cli_backend_observed")

    @mock.patch("safe_validation.file_contains_marker", return_value=False)
    @mock.patch("safe_validation.run_command")
    def test_grok_capability_does_not_invent_contract_without_billing_marker(
        self, run_command: mock.Mock, _marker: mock.Mock
    ) -> None:
        run_command.side_effect = [
            subject.subprocess.CompletedProcess(
                ["grok", "--help"], 0, stdout="Commands:\n  agent   Run agent\n", stderr=""
            ),
            subject.subprocess.CompletedProcess(
                ["grok", "agent", "--help"], 0, stdout="Commands:\n  stdio   Run over stdio\n", stderr=""
            ),
        ]
        result = subject.grok_capability_summary("/tmp/grok")
        self.assertTrue(result["agentStdioDocumented"])
        self.assertFalse(result["billingExtensionEmbedded"])
        self.assertEqual(result["quotaContract"], "unavailable")

    @mock.patch("safe_validation.shutil.which", return_value="/tmp/codex")
    @mock.patch("safe_validation.run_command")
    def test_safe_version_ignores_numeric_warning(self, run_command: mock.Mock, _which: mock.Mock) -> None:
        run_command.return_value = subject.subprocess.CompletedProcess(
            ["/tmp/codex", "--version"],
            0,
            stdout="codex-cli 0.145.0\n",
            stderr="WARNING: operation not permitted (os error 1)\n",
        )
        result = subject.safe_version("codex")
        self.assertEqual(result["version"], "codex-cli 0.145.0")

    @mock.patch("safe_validation.shutil.which", return_value=None)
    def test_safe_version_handles_missing_cli(self, _which: mock.Mock) -> None:
        self.assertEqual(subject.safe_version("missing"), {"installed": False})

    @mock.patch("safe_validation.subprocess.run", side_effect=subject.subprocess.TimeoutExpired(["tool"], 1))
    def test_run_command_converts_timeout_to_safe_state(self, _run: mock.Mock) -> None:
        self.assertIsNone(subject.run_command(["tool"], timeout=1))

    def test_compare_fingerprints_reports_stable_state(self) -> None:
        before = [{"label": "auth", "state": "regular", "sha256": "a", "mtimeNs": 1, "mode": "0600"}]
        after = [{"label": "auth", "state": "regular", "sha256": "a", "mtimeNs": 1, "mode": "0600"}]
        result = subject.compare_fingerprints(before, after)
        self.assertEqual(result, [{
            "label": "auth",
            "stateBefore": "regular",
            "stateAfter": "regular",
            "sha256Changed": False,
            "mtimeChanged": False,
            "modeChanged": False,
        }])

    def test_write_private_json_forces_0600(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "report.json"
            subject.write_private_json(path, {"ok": True})
            mode = stat.S_IMODE(path.stat().st_mode)
        self.assertEqual(mode, 0o600)


if __name__ == "__main__":
    unittest.main()

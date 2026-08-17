from __future__ import annotations

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("gemini_cli_quota_probe.py")
SPEC = importlib.util.spec_from_file_location("gemini_cli_quota_probe", MODULE_PATH)
assert SPEC and SPEC.loader
subject = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(subject)


class GeminiCLIQuotaProbeTests(unittest.TestCase):
    def test_summary_reads_only_gemini_group_and_emits_no_values(self) -> None:
        raw = b"""\x1b[31mGEMINI MODELS\x1b[0m
Weekly Limit Remaining
64%
Refreshes in 2d 3h
Five Hour Limit Remaining
90%
Refreshes in 4h 59m
CLAUDE AND GPT MODELS
Weekly Limit Remaining
1%
"""
        result = subject.summarize_tui(raw)
        self.assertTrue(result["valuesValid"])
        self.assertTrue(result["weekly"]["resetEvidencePresent"])
        self.assertTrue(result["fiveHour"]["resetEvidencePresent"])
        self.assertTrue(result["otherModelGroupExcluded"])
        encoded = json.dumps(result)
        self.assertNotIn("64", encoded)
        self.assertNotIn("90", encoded)

    def test_summary_rejects_missing_or_invalid_contract(self) -> None:
        with self.assertRaises(subject.ProbeError):
            subject.summarize_tui(b"CLAUDE AND GPT MODELS\n50%")
        invalid = b"GEMINI MODELS\nWeekly Limit Remaining\n101%\nFive Hour Limit Remaining\nno value"
        result = subject.summarize_tui(invalid)
        self.assertFalse(result["valuesValid"])
        negative = b"GEMINI MODELS\nWeekly Limit Remaining\n-1%\nFive Hour Limit Remaining\n100%"
        self.assertFalse(subject.summarize_tui(negative)["valuesValid"])

    def test_locator_rejects_symlink_and_requires_trusted_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            executable = home / ".local/bin/agy"
            settings = home / ".gemini/antigravity-cli/settings.json"
            workspace = root / "workspace"
            executable.parent.mkdir(parents=True)
            settings.parent.mkdir(parents=True)
            workspace.mkdir()
            executable.write_text("#!/bin/sh\n")
            executable.chmod(0o700)
            settings.write_text(json.dumps({"trustedWorkspaces": [str(workspace)]}))
            self.assertEqual(subject.locate_executable(home), executable)
            self.assertEqual(subject.locate_workspace(home)[0], workspace)

            link = executable.with_name("agy-link")
            link.symlink_to(executable)
            with self.assertRaises(subject.ProbeError):
                subject.locate_executable(home, link)

            settings.write_text(json.dumps({"trustedWorkspaces": []}))
            with self.assertRaises(subject.ProbeError):
                subject.locate_workspace(home)

    def test_safe_environment_disables_update_and_requests_account_hiding(self) -> None:
        environment = subject.safe_environment(Path("/tmp/home"), Path("/tmp/agy"))
        self.assertEqual(environment["AGY_CLI_DISABLE_AUTO_UPDATE"], "1")
        self.assertEqual(environment["AGY_CLI_HIDE_ACCOUNT_INFO"], "1")
        self.assertNotIn("TOKEN", " ".join(environment))
        self.assertNotIn("KEY", " ".join(environment))

    def test_expect_sets_spawned_child_slave_size_before_waiting_for_tui(self) -> None:
        self.assertIn(
            "stty rows 48 columns 120 < $spawn_out(slave,name)",
            subject.EXPECT_SCRIPT,
        )

    def test_terminal_query_responses_preserve_the_bounded_expect_timer(self) -> None:
        self.assertEqual(subject.EXPECT_SCRIPT.count("exp_continue -continue_timer"), 6)
        self.assertNotIn("; exp_continue }", subject.EXPECT_SCRIPT)
        self.assertIn("kill -KILL", subject.EXPECT_SCRIPT)


if __name__ == "__main__":
    unittest.main()

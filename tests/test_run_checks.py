import json
import subprocess
import sys
import unittest
from pathlib import Path

from scripts.run_checks import build_check_plan, normalize_profiles


ROOT = Path(__file__).resolve().parents[1]


class RunChecksTests(unittest.TestCase):
    def test_normalize_profiles_expands_all_without_live(self) -> None:
        self.assertEqual(normalize_profiles(["all"]), ["fast", "gui", "release", "rc"])
        self.assertEqual(normalize_profiles(["all", "live"]), ["fast", "gui", "release", "rc", "live"])

    def test_fast_plan_contains_unit_and_offline_startup_checks(self) -> None:
        plan = build_check_plan(
            ROOT,
            ["fast"],
            python_executable="python",
            powershell_executable="powershell",
        )

        self.assertEqual([check["name"] for check in plan], ["unit-tests", "startup-diagnostics-offline"])
        self.assertEqual(plan[0]["command"][:4], ["python", "-m", "unittest", "discover"])
        self.assertIn("--skip-live-probes", plan[1]["command"])

    def test_all_plan_excludes_live_checks(self) -> None:
        plan = build_check_plan(
            ROOT,
            ["all"],
            python_executable="python",
            powershell_executable="powershell",
        )
        names = [check["name"] for check in plan]

        self.assertIn("gui-button-smoke-offline", names)
        self.assertIn("gui-batch-smoke-offline", names)
        self.assertIn("gui-batch-run-smoke-offline", names)
        self.assertIn("launcher-plan", names)
        self.assertIn("release-install-smoke", names)
        self.assertIn("release-candidate-walkthrough", names)
        self.assertNotIn("startup-diagnostics-live", names)
        self.assertNotIn("gui-button-smoke-live", names)
        self.assertNotIn("gui-async-run-smoke-live", names)

    def test_rc_plan_runs_release_candidate_walkthrough(self) -> None:
        plan = build_check_plan(
            ROOT,
            ["rc"],
            python_executable="python",
            powershell_executable="powershell",
        )

        self.assertEqual([check["name"] for check in plan], ["release-candidate-walkthrough"])
        self.assertIn("scripts/release_candidate_walkthrough.py", plan[0]["command"])
        self.assertIn("--compact", plan[0]["command"])

    def test_live_plan_uses_non_skipped_probe_commands_when_powershell_exists(self) -> None:
        plan = build_check_plan(
            ROOT,
            ["live"],
            python_executable="python",
            powershell_executable="powershell",
        )

        self.assertEqual(
            [check["name"] for check in plan],
            ["startup-diagnostics-live", "gui-button-smoke-live", "gui-async-run-smoke-live"],
        )
        self.assertIn("-Diagnostics", plan[0]["command"])
        self.assertIn("-ButtonSmokeTest", plan[1]["command"])
        self.assertIn("-AsyncRunSmokeTest", plan[2]["command"])
        self.assertIsNone(plan[0]["skip_reason"])

    def test_list_cli_reports_plan_without_running_checks(self) -> None:
        completed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts" / "run_checks.py"),
                "--profile",
                "release",
                "--list",
                "--compact",
            ],
            cwd=ROOT,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
        payload = json.loads(completed.stdout.decode("utf-8"))
        self.assertEqual(payload["mode"], "run_checks")
        self.assertEqual(payload["profiles"], ["release"])
        self.assertTrue(payload["valid"])
        self.assertEqual(payload["summary"]["planned"], 3)
        self.assertEqual([check["status"] for check in payload["checks"]], ["planned", "planned", "planned"])


if __name__ == "__main__":
    unittest.main()

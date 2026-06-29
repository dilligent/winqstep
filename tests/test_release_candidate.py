import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ReleaseCandidateWalkthroughTests(unittest.TestCase):
    def test_handoff_doc_is_linked_from_readme(self) -> None:
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        handoff = (ROOT / "docs" / "release-candidate-handoff.md").read_text(encoding="utf-8")

        self.assertIn("docs/release-candidate-handoff.md", readme)
        self.assertIn("## Required Handoff Commands", handoff)
        self.assertIn("python .\\scripts\\run_checks.py --profile all --compact", handoff)
        self.assertIn("## Known Limitations", handoff)

    def test_cli_runs_offline_walkthrough(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "release_candidate_walkthrough.py"),
                    "--workspace",
                    tmp_dir,
                    "--compact",
                ],
                cwd=ROOT,
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
            payload = json.loads(completed.stdout.decode("utf-8"))
            self.assertEqual(payload["mode"], "release_candidate_walkthrough")
            self.assertTrue(payload["valid"], payload["errors"])
            self.assertFalse(payload["include_live"])
            self.assertTrue(payload["workspace_retained"])
            self.assertEqual(payload["summary"]["failed"], 0)

            steps = {step["name"]: step for step in payload["steps"]}
            self.assertEqual(steps["workflow-prepare-energy-force"]["summary"]["run_type"], "ENERGY_FORCE")
            self.assertEqual(steps["workflow-prepare-energy-force"]["summary"]["cp2k_output_status"], "not_available")
            self.assertIn("rc_energy_force", steps["workspace-history"]["summary"]["projects"])
            self.assertIn("quickstep_energy_force", steps["workspace-history"]["summary"]["projects"])
            self.assertTrue(steps["release-plan"]["summary"]["valid"])

            workflow_input = Path(tmp_dir) / "workflow-energy-force" / "rc_energy_force.inp"
            rendered = workflow_input.read_text(encoding="utf-8")
            self.assertIn("RUN_TYPE ENERGY_FORCE", rendered)
            self.assertIn("&FORCES ON", rendered)


if __name__ == "__main__":
    unittest.main()

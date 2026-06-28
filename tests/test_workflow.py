import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from winqstep.runner import load_json_file
from winqstep.structures import import_structure
from winqstep.workflow import WorkflowError, build_quickstep_data, run_quickstep_workflow


ROOT = Path(__file__).resolve().parents[1]
STRUCTURES = ROOT / "tests" / "fixtures" / "structures"


class WorkflowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = load_json_file(ROOT / "examples" / "winqstep.config.json")
        self.template = load_json_file(ROOT / "examples" / "templates" / "energy_pbe.json")

    def test_builds_quickstep_data_from_xyz_and_template(self) -> None:
        imported = import_structure(STRUCTURES / "water.xyz")

        quickstep_data = build_quickstep_data(self.template, imported, project_name="water_from_xyz")

        self.assertEqual(quickstep_data["project_name"], "water_from_xyz")
        self.assertEqual(quickstep_data["structure"]["cell"]["periodic"], "XYZ")
        self.assertEqual(quickstep_data["structure"]["atoms"][0]["xyz"], [5.0, 5.0, 4.707])
        self.assertEqual(
            [kind["element"] for kind in quickstep_data["structure"]["kinds"]],
            ["H", "O"],
        )

    def test_prepare_only_writes_workflow_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            metadata = run_quickstep_workflow(
                config=self.config,
                template_data=self.template,
                structure_path=STRUCTURES / "water.xyz",
                windows_job_dir=tmp_dir,
                project_name="workflow_prepare",
                execute=False,
            )

            self.assertEqual(metadata["status"], "prepared")
            self.assertEqual(metadata["workflow"]["atom_count"], 3)
            self.assertEqual(metadata["workflow"]["elements"], ["H", "O"])
            saved = json.loads(Path(metadata["files"]["metadata"]["path"]).read_text(encoding="utf-8"))
            self.assertEqual(saved["workflow"]["structure_source"]["format"], "xyz")

    def test_missing_kind_reports_template_error(self) -> None:
        imported = import_structure(STRUCTURES / "water.xyz")
        template = dict(self.template)
        template["kinds"] = [kind for kind in self.template["kinds"] if kind["element"] != "O"]

        with self.assertRaisesRegex(WorkflowError, "template missing KIND definitions for: O"):
            build_quickstep_data(template, imported)

    def test_cli_prepare_only_outputs_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "run_workflow.py"),
                    "--config",
                    str(ROOT / "examples" / "winqstep.config.json"),
                    "--template",
                    str(ROOT / "examples" / "templates" / "energy_pbe.json"),
                    "--structure",
                    str(STRUCTURES / "water.xyz"),
                    "--job-dir",
                    tmp_dir,
                    "--project-name",
                    "workflow_cli",
                    "--prepare-only",
                    "--compact",
                ],
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
            metadata = json.loads(completed.stdout.decode("utf-8"))
            self.assertEqual(metadata["status"], "prepared")
            self.assertEqual(metadata["workflow"]["atom_count"], 3)


if __name__ == "__main__":
    unittest.main()

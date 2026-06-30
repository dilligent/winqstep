import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from winqstep.runner import load_json_file
from winqstep.structures import import_structure
from winqstep.workflow import WorkflowError, build_quickstep_data, run_quickstep_workflow


ROOT = Path(__file__).resolve().parents[1]
STRUCTURES = ROOT / "tests" / "fixtures" / "structures"


class WorkflowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = load_json_file(ROOT / "examples" / "winqstep.config.example.json")
        self.template = load_json_file(ROOT / "examples" / "templates" / "energy_pbe.example.json")

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

    def test_builds_quickstep_data_from_periodic_poscar_without_fallback_cell(self) -> None:
        imported = import_structure(STRUCTURES / "POSCAR")

        quickstep_data = build_quickstep_data(self.template, imported, project_name="si_periodic")

        self.assertEqual(quickstep_data["structure"]["cell"]["periodic"], "XYZ")
        self.assertEqual(quickstep_data["structure"]["cell"]["a"], [5.43, 0.0, 0.0])
        self.assertEqual(quickstep_data["structure"]["atoms"][0]["xyz"], [0.0, 0.0, 0.0])
        self.assertEqual(
            [kind["element"] for kind in quickstep_data["structure"]["kinds"]],
            ["Si"],
        )

    def test_builds_energy_force_workflow_data(self) -> None:
        imported = import_structure(STRUCTURES / "water.xyz")
        template = load_json_file(ROOT / "examples" / "templates" / "energy_force_pbe.json")

        quickstep_data = build_quickstep_data(template, imported, project_name="water_force")

        self.assertEqual(quickstep_data["project_name"], "water_force")
        self.assertEqual(quickstep_data["run_type"], "ENERGY_FORCE")
        self.assertNotIn("geo_opt", quickstep_data)

    def test_builds_workflow_data_with_print_level(self) -> None:
        imported = import_structure(STRUCTURES / "water.xyz")
        template = dict(self.template)
        template["print_level"] = "LOW"

        quickstep_data = build_quickstep_data(template, imported, project_name="water_low_print")

        self.assertEqual(quickstep_data["print_level"], "LOW")

    def test_builds_workflow_data_with_poisson_solver(self) -> None:
        imported = import_structure(STRUCTURES / "water.xyz")
        template = json.loads(json.dumps(self.template))
        template["dft"]["poisson_solver"] = "WAVELET"

        quickstep_data = build_quickstep_data(template, imported, project_name="water_wavelet")

        self.assertEqual(quickstep_data["dft"]["poisson_solver"], "WAVELET")

    def test_builds_cell_opt_workflow_data(self) -> None:
        imported = import_structure(STRUCTURES / "POSCAR")
        template = load_json_file(ROOT / "examples" / "templates" / "energy_pbe.example.json")
        template["run_type"] = "CELL_OPT"
        template["cell_opt"] = {
            "optimizer": "BFGS",
            "max_iter": 20,
            "type": "DIRECT_CELL_OPT",
            "pressure_tolerance": "100",
            "keep_angles": True,
            "keep_symmetry": False,
        }

        quickstep_data = build_quickstep_data(template, imported, project_name="si_cell_opt")

        self.assertEqual(quickstep_data["run_type"], "CELL_OPT")
        self.assertEqual(quickstep_data["cell_opt"]["type"], "DIRECT_CELL_OPT")
        self.assertTrue(quickstep_data["cell_opt"]["keep_angles"])
        self.assertNotIn("geo_opt", quickstep_data)

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
            self.assertEqual(metadata["cp2k_output"]["status"], "not_available")
            saved = json.loads(Path(metadata["files"]["metadata"]["path"]).read_text(encoding="utf-8"))
            self.assertEqual(saved["workflow"]["structure_source"]["format"], "xyz")
            self.assertEqual(saved["cp2k_output"]["status"], "not_available")

    def test_successful_workflow_preserves_output_summary(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:

            def fake_executor(argv: list[str]) -> SimpleNamespace:
                job_dir = Path(tmp_dir)
                (job_dir / "workflow_run.out").write_text(
                    "The number of warnings for this run is : 0\n"
                    "PROGRAM ENDED AT                 2026-06-29 03:24:28.023\n",
                    encoding="utf-8",
                )
                (job_dir / "workflow_run.stdout.log").write_text("", encoding="utf-8")
                (job_dir / "workflow_run.stderr.log").write_text("", encoding="utf-8")
                return SimpleNamespace(returncode=0, stdout=b"", stderr=b"")

            metadata = run_quickstep_workflow(
                config=self.config,
                template_data=self.template,
                structure_path=STRUCTURES / "water.xyz",
                windows_job_dir=tmp_dir,
                project_name="workflow_run",
                executor=fake_executor,
            )

            self.assertEqual(metadata["status"], "succeeded")
            self.assertEqual(metadata["cp2k_output"]["status"], "completed")
            self.assertEqual(metadata["cp2k_output"]["warning_count"], 0)
            saved = json.loads(Path(metadata["files"]["metadata"]["path"]).read_text(encoding="utf-8"))
            self.assertEqual(saved["workflow"]["atom_count"], 3)
            self.assertEqual(saved["cp2k_output"]["status"], "completed")

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
                    str(ROOT / "examples" / "winqstep.config.example.json"),
                    "--template",
                    str(ROOT / "examples" / "templates" / "energy_pbe.example.json"),
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

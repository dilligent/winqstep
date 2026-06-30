import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from winqstep.preflight import validate_existing_input_preflight, validate_workflow_preflight
from winqstep.runner import load_json_file


ROOT = Path(__file__).resolve().parents[1]
STRUCTURE = ROOT / "tests" / "fixtures" / "structures" / "water.xyz"
TEMPLATE = ROOT / "examples" / "templates" / "energy_pbe.example.json"
CONFIG = ROOT / "examples" / "winqstep.config.example.json"


class PreflightTests(unittest.TestCase):
    def test_workflow_preflight_reports_missing_kind_before_render(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            template = load_json_file(TEMPLATE)
            template["kinds"] = [kind for kind in template["kinds"] if kind["element"] != "O"]
            template_path = Path(tmp_dir) / "missing-o.json"
            template_path.write_text(json.dumps(template), encoding="utf-8")

            payload = validate_workflow_preflight(
                template_path=template_path,
                structure_path=STRUCTURE,
                cache_path=None,
            )

            self.assertFalse(payload["valid"])
            self.assertIn("template missing KIND definitions for: O", "\n".join(payload["errors"]))
            self.assertEqual(payload["structure"]["elements"], ["H", "O"])

    def test_workflow_preflight_warns_for_unknown_cached_kind_label(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            cache_path = Path(tmp_dir) / "cp2k-cache.json"
            cache_path.write_text(
                json.dumps(
                    {
                        "files": [{"name": "BASIS_MOLOPT"}, {"name": "GTH_POTENTIALS"}],
                        "labels_by_element": {
                            "H": {"basis_sets": ["DZVP-MOLOPT-SR-GTH"], "potentials": ["GTH-PBE-q1"]},
                            "O": {"basis_sets": ["OTHER-BASIS"], "potentials": ["GTH-PBE-q6"]},
                        },
                        "counts": {"files": 2, "elements": 2},
                    }
                ),
                encoding="utf-8",
            )

            payload = validate_workflow_preflight(
                template_path=TEMPLATE,
                structure_path=STRUCTURE,
                cache_path=cache_path,
            )

            self.assertTrue(payload["valid"], payload["errors"])
            self.assertIn("KIND O basis set is not present", "\n".join(payload["warnings"]))

    def test_existing_input_preflight_warns_for_missing_cached_data_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            input_path = Path(tmp_dir) / "job.inp"
            input_path.write_text(
                "BASIS_SET_FILE_NAME MISSING_BASIS\n"
                "POTENTIAL_FILE_NAME GTH_POTENTIALS\n"
                "PARAMETER_FILE_NAME dftd3.dat\n",
                encoding="utf-8",
            )
            cache_path = Path(tmp_dir) / "cache.json"
            cache_path.write_text(
                json.dumps({"files": [{"name": "GTH_POTENTIALS"}], "counts": {"files": 1}}),
                encoding="utf-8",
            )

            payload = validate_existing_input_preflight(input_path=input_path, cache_path=cache_path)

            self.assertTrue(payload["valid"], payload["errors"])
            self.assertIn("MISSING_BASIS", "\n".join(payload["warnings"]))
            self.assertIn("dftd3.dat", "\n".join(payload["warnings"]))

    def test_workflow_preflight_warns_for_missing_dispersion_parameter_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            template = load_json_file(TEMPLATE)
            template["dft"]["dispersion_enabled"] = True
            template["dft"]["dispersion_parameter_file_name"] = "dftd3.dat"
            template_path = Path(tmp_dir) / "d3.json"
            template_path.write_text(json.dumps(template), encoding="utf-8")
            cache_path = Path(tmp_dir) / "cache.json"
            cache_path.write_text(
                json.dumps(
                    {
                        "files": [{"name": "BASIS_MOLOPT"}, {"name": "GTH_POTENTIALS"}],
                        "labels_by_element": {
                            "H": {"basis_sets": ["DZVP-MOLOPT-SR-GTH"], "potentials": ["GTH-PBE-q1"]},
                            "O": {"basis_sets": ["DZVP-MOLOPT-SR-GTH"], "potentials": ["GTH-PBE-q6"]},
                        },
                        "counts": {"files": 2, "elements": 2},
                    }
                ),
                encoding="utf-8",
            )

            payload = validate_workflow_preflight(
                template_path=template_path,
                structure_path=STRUCTURE,
                cache_path=cache_path,
            )

            self.assertTrue(payload["valid"], payload["errors"])
            self.assertIn("dispersion parameter file", "\n".join(payload["warnings"]))

    def test_cli_outputs_json_and_nonzero_for_invalid_workflow(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            template = load_json_file(TEMPLATE)
            template["kinds"] = [kind for kind in template["kinds"] if kind["element"] != "O"]
            template_path = Path(tmp_dir) / "missing-o.json"
            template_path.write_text(json.dumps(template), encoding="utf-8")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "validate_job_inputs.py"),
                    "--mode",
                    "workflow",
                    "--config",
                    str(CONFIG),
                    "--template",
                    str(template_path),
                    "--structure",
                    str(STRUCTURE),
                    "--no-cache",
                    "--compact",
                ],
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 1, completed.stderr.decode("utf-8", errors="replace"))
            payload = json.loads(completed.stdout.decode("utf-8"))
            self.assertFalse(payload["valid"])


if __name__ == "__main__":
    unittest.main()

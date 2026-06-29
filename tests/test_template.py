import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from winqstep.runner import load_json_file
from winqstep.template import load_template, merge_template_fields, save_template, validate_template


ROOT = Path(__file__).resolve().parents[1]
ENERGY_TEMPLATE = ROOT / "examples" / "templates" / "energy_pbe.json"


class TemplateTests(unittest.TestCase):
    def test_load_template_normalizes_existing_example(self) -> None:
        template = load_template(ENERGY_TEMPLATE)

        self.assertEqual(template["run_type"], "ENERGY")
        self.assertEqual(template["dft"]["charge"], 0)
        self.assertEqual(template["dft"]["eps_scf"], "1.0E-6")
        self.assertEqual(template["kinds"][0]["element"], "H")

    def test_merge_fields_updates_dft_and_kinds_text(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(
            template,
            {
                "run_type": "GEO_OPT",
                "cutoff": "500",
                "max_scf": "80",
                "optimizer": "cg",
                "geo_opt_max_iter": "120",
                "kinds_text": "H DZVP-MOLOPT-SR-GTH GTH-PBE-q1\nO TZVP-MOLOPT-GTH GTH-PBE-q6",
            },
        )
        validation = validate_template(merged)

        self.assertTrue(validation["valid"], validation["errors"])
        normalized = validation["template"]
        self.assertEqual(normalized["run_type"], "GEO_OPT")
        self.assertEqual(normalized["dft"]["cutoff"], 500)
        self.assertEqual(normalized["geo_opt"]["optimizer"], "CG")
        self.assertEqual(normalized["geo_opt"]["max_iter"], 120)
        self.assertEqual(normalized["kinds"][1]["basis_set"], "TZVP-MOLOPT-GTH")

    def test_merge_fields_updates_fallback_cell_transform(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(
            template,
            {
                "fallback_cell_periodic": "xy",
                "fallback_cell_a": "12 0 0",
                "fallback_cell_b": "0 11 0",
                "fallback_cell_c": "0 0 14",
                "center_atoms": "false",
            },
        )
        validation = validate_template(merged)

        self.assertTrue(validation["valid"], validation["errors"])
        transform = validation["template"]["structure_transform"]
        self.assertEqual(transform["fallback_cell"]["periodic"], "XY")
        self.assertEqual(transform["fallback_cell"]["a"], [12.0, 0.0, 0.0])
        self.assertEqual(transform["fallback_cell"]["b"], [0.0, 11.0, 0.0])
        self.assertEqual(transform["fallback_cell"]["c"], [0.0, 0.0, 14.0])
        self.assertFalse(transform["center_atoms"])

    def test_blank_geo_fields_do_not_break_energy_template(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(template, {"optimizer": "", "geo_opt_max_iter": ""})
        validation = validate_template(merged)

        self.assertTrue(validation["valid"], validation["errors"])
        self.assertNotIn("geo_opt", validation["template"])

    def test_validate_accepts_energy_force_template(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(template, {"run_type": "energy_force"})
        validation = validate_template(merged)

        self.assertTrue(validation["valid"], validation["errors"])
        self.assertEqual(validation["template"]["run_type"], "ENERGY_FORCE")
        self.assertNotIn("geo_opt", validation["template"])

    def test_validate_rejects_duplicate_kinds(self) -> None:
        template = load_json_file(ENERGY_TEMPLATE)
        template["kinds"].append({"element": "H", "basis_set": "DZVP", "potential": "GTH-PBE-q1"})

        validation = validate_template(template)

        self.assertFalse(validation["valid"])
        self.assertIn("duplicate KIND entry for element H", validation["errors"])

    def test_validate_rejects_incomplete_kind_entry(self) -> None:
        template = load_json_file(ENERGY_TEMPLATE)
        template["kinds"] = [{"element": "H", "basis_set": "", "potential": "GTH-PBE-q1"}]

        validation = validate_template(template)

        self.assertFalse(validation["valid"])
        self.assertIn("kinds[0].basis_set must be a non-empty string", validation["errors"])

    def test_validate_rejects_empty_dft_file_names(self) -> None:
        template = load_json_file(ENERGY_TEMPLATE)
        template["dft"]["basis_set_file_name"] = ""

        validation = validate_template(template)

        self.assertFalse(validation["valid"])
        self.assertIn("dft.basis_set_file_name must be a non-empty string", validation["errors"])

    def test_save_template_writes_stable_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            template_path = Path(tmp_dir) / "template.json"

            saved = save_template(template_path, load_template(ENERGY_TEMPLATE))

            self.assertEqual(list(saved), ["project_name", "run_type", "dft", "structure_transform", "kinds"])
            self.assertEqual(list(saved["dft"]), [
                "basis_set_file_name",
                "potential_file_name",
                "xc_functional",
                "charge",
                "multiplicity",
                "cutoff",
                "rel_cutoff",
                "eps_scf",
                "max_scf",
            ])
            self.assertFalse(template_path.read_bytes().startswith(b"\xef\xbb\xbf"))

    def test_cli_writes_template_from_fields_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            template_path = Path(tmp_dir) / "template.json"
            template_path.write_text(ENERGY_TEMPLATE.read_text(encoding="utf-8"), encoding="utf-8")
            fields = {
                "project_name": "edited_template",
                "run_type": "GEO_OPT",
                "cutoff": "550",
                "geo_opt_max_iter": "150",
                "kinds_text": "H DZVP-MOLOPT-SR-GTH GTH-PBE-q1\nO DZVP-MOLOPT-SR-GTH GTH-PBE-q6",
            }

            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "manage_template.py"),
                    "--template",
                    str(template_path),
                    "--write",
                    "--fields-json",
                    json.dumps(fields),
                    "--compact",
                ],
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
            payload = json.loads(completed.stdout.decode("utf-8"))
            self.assertTrue(payload["written"])
            self.assertTrue(payload["validation"]["valid"])
            saved = load_template(template_path)
            self.assertEqual(saved["project_name"], "edited_template")
            self.assertEqual(saved["run_type"], "GEO_OPT")
            self.assertEqual(saved["dft"]["cutoff"], 550)


if __name__ == "__main__":
    unittest.main()

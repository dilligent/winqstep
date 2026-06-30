import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from winqstep.runner import load_json_file
from winqstep.template import load_template, merge_template_fields, save_template, validate_template


ROOT = Path(__file__).resolve().parents[1]
ENERGY_TEMPLATE = ROOT / "examples" / "templates" / "energy_pbe.example.json"
CELL_OPT_TEMPLATE = ROOT / "examples" / "templates" / "cell_opt_pbe.json"


class TemplateTests(unittest.TestCase):
    def test_load_template_normalizes_existing_example(self) -> None:
        template = load_template(ENERGY_TEMPLATE)

        self.assertEqual(template["run_type"], "ENERGY")
        self.assertEqual(template["dft"]["charge"], 0)
        self.assertEqual(template["dft"]["poisson_solver"], "")
        self.assertEqual(template["dft"]["wfn_restart_file_name"], "")
        self.assertFalse(template["dft"]["print_mulliken"])
        self.assertFalse(template["dft"]["print_lowdin"])
        self.assertEqual(template["dft"]["scf_guess"], "")
        self.assertEqual(template["dft"]["eps_scf"], "1.0E-6")
        self.assertEqual(template["kinds"][0]["element"], "H")

    def test_load_template_normalizes_cell_opt_example(self) -> None:
        template = load_template(CELL_OPT_TEMPLATE)

        self.assertEqual(template["run_type"], "CELL_OPT")
        self.assertEqual(template["cell_opt"]["type"], "DIRECT_CELL_OPT")
        self.assertEqual(template["cell_opt"]["max_iter"], 20)
        self.assertEqual(template["dft"]["kpoints_scheme"], "MONKHORST-PACK")

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

    def test_merge_fields_updates_print_level(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(template, {"print_level": "high"})
        validation = validate_template(merged)

        self.assertTrue(validation["valid"], validation["errors"])
        self.assertEqual(validation["template"]["print_level"], "HIGH")

        cleared = merge_template_fields(validation["template"], {"print_level": ""})
        cleared_validation = validate_template(cleared)
        self.assertTrue(cleared_validation["valid"], cleared_validation["errors"])
        self.assertNotIn("print_level", cleared_validation["template"])

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

    def test_merge_fields_updates_scf_controls(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(
            template,
            {
                "scf_method": "diagonalization",
                "added_mos": "8",
                "uks_enabled": True,
                "outer_scf_enabled": True,
                "outer_scf_eps_scf": "1.0E-7",
                "outer_scf_max_scf": "30",
                "diagonalization_algorithm": "davidson",
                "mixing_enabled": True,
                "mixing_method": "pulay_mixing",
                "mixing_alpha": "0.25",
                "mixing_beta": "1.0",
                "smearing_enabled": True,
                "smearing_method": "fermi_dirac",
                "electronic_temperature": "500",
            },
        )
        validation = validate_template(merged)

        self.assertTrue(validation["valid"], validation["errors"])
        dft = validation["template"]["dft"]
        self.assertEqual(dft["scf_method"], "DIAGONALIZATION")
        self.assertEqual(dft["added_mos"], 8)
        self.assertTrue(dft["uks_enabled"])
        self.assertTrue(dft["outer_scf_enabled"])
        self.assertEqual(dft["outer_scf_eps_scf"], "1.0E-7")
        self.assertEqual(dft["outer_scf_max_scf"], 30)
        self.assertEqual(dft["diagonalization_algorithm"], "DAVIDSON")
        self.assertTrue(dft["mixing_enabled"])
        self.assertEqual(dft["mixing_method"], "PULAY_MIXING")
        self.assertTrue(dft["smearing_enabled"])
        self.assertEqual(dft["electronic_temperature"], "500")

    def test_merge_fields_updates_xc_and_dispersion_controls(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(
            template,
            {
                "xc_pbe_parametrization": "pbesol",
                "dispersion_enabled": True,
                "dispersion_type": "dftd3",
                "dispersion_parameter_file_name": "dftd3.dat",
                "dispersion_reference_functional": "pbe",
            },
        )
        validation = validate_template(merged)

        self.assertTrue(validation["valid"], validation["errors"])
        dft = validation["template"]["dft"]
        self.assertEqual(dft["xc_pbe_parametrization"], "PBESOL")
        self.assertTrue(dft["dispersion_enabled"])
        self.assertEqual(dft["dispersion_type"], "DFTD3")
        self.assertEqual(dft["dispersion_parameter_file_name"], "dftd3.dat")
        self.assertEqual(dft["dispersion_reference_functional"], "PBE")

    def test_merge_fields_updates_kpoints_controls(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(
            template,
            {
                "kpoints_scheme": "monkhorst-pack",
                "kpoints_grid": "2 2 1",
                "kpoints_full_grid": True,
                "kpoints_symmetry": "yes",
                "kpoints_wavefunctions": "real",
            },
        )
        validation = validate_template(merged)

        self.assertTrue(validation["valid"], validation["errors"])
        dft = validation["template"]["dft"]
        self.assertEqual(dft["kpoints_scheme"], "MONKHORST-PACK")
        self.assertEqual(dft["kpoints_grid"], [2, 2, 1])
        self.assertTrue(dft["kpoints_full_grid"])
        self.assertTrue(dft["kpoints_symmetry"])
        self.assertEqual(dft["kpoints_wavefunctions"], "REAL")

    def test_merge_fields_updates_poisson_solver(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(template, {"poisson_solver": "wavelet"})
        validation = validate_template(merged)

        self.assertTrue(validation["valid"], validation["errors"])
        self.assertEqual(validation["template"]["dft"]["poisson_solver"], "WAVELET")

        cleared = merge_template_fields(validation["template"], {"poisson_solver": ""})
        cleared_validation = validate_template(cleared)
        self.assertTrue(cleared_validation["valid"], cleared_validation["errors"])
        self.assertEqual(cleared_validation["template"]["dft"]["poisson_solver"], "")

    def test_merge_fields_updates_restart_controls(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(
            template,
            {
                "wfn_restart_file_name": "previous-RESTART.wfn",
                "scf_guess": "history_restart",
            },
        )
        validation = validate_template(merged)

        self.assertTrue(validation["valid"], validation["errors"])
        dft = validation["template"]["dft"]
        self.assertEqual(dft["wfn_restart_file_name"], "previous-RESTART.wfn")
        self.assertEqual(dft["scf_guess"], "HISTORY_RESTART")

        cleared = merge_template_fields(validation["template"], {"wfn_restart_file_name": "", "scf_guess": ""})
        cleared_validation = validate_template(cleared)
        self.assertTrue(cleared_validation["valid"], cleared_validation["errors"])
        self.assertEqual(cleared_validation["template"]["dft"]["wfn_restart_file_name"], "")
        self.assertEqual(cleared_validation["template"]["dft"]["scf_guess"], "")

    def test_merge_fields_updates_dft_print_controls(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(template, {"print_mulliken": "yes", "print_lowdin": True})
        validation = validate_template(merged)

        self.assertTrue(validation["valid"], validation["errors"])
        dft = validation["template"]["dft"]
        self.assertTrue(dft["print_mulliken"])
        self.assertTrue(dft["print_lowdin"])

    def test_merge_fields_updates_cell_opt_controls(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(
            template,
            {
                "run_type": "cell_opt",
                "cell_opt_type": "direct_cell_opt",
                "cell_opt_optimizer": "lbfgs",
                "cell_opt_max_iter": "50",
                "cell_opt_pressure_tolerance": "75",
                "cell_opt_keep_angles": True,
                "cell_opt_keep_symmetry": "yes",
            },
        )
        validation = validate_template(merged)

        self.assertTrue(validation["valid"], validation["errors"])
        normalized = validation["template"]
        self.assertEqual(normalized["run_type"], "CELL_OPT")
        self.assertNotIn("geo_opt", normalized)
        self.assertEqual(
            list(normalized["cell_opt"]),
            ["optimizer", "max_iter", "type", "pressure_tolerance", "keep_angles", "keep_symmetry"],
        )
        self.assertEqual(normalized["cell_opt"]["optimizer"], "LBFGS")
        self.assertEqual(normalized["cell_opt"]["max_iter"], 50)
        self.assertEqual(normalized["cell_opt"]["type"], "DIRECT_CELL_OPT")
        self.assertEqual(normalized["cell_opt"]["pressure_tolerance"], "75")
        self.assertTrue(normalized["cell_opt"]["keep_angles"])
        self.assertTrue(normalized["cell_opt"]["keep_symmetry"])

    def test_validate_rejects_smearing_without_added_mos(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(
            template,
            {
                "scf_method": "DIAGONALIZATION",
                "added_mos": "0",
                "smearing_enabled": True,
            },
        )
        validation = validate_template(merged)

        self.assertFalse(validation["valid"])
        self.assertIn("dft.smearing_enabled requires dft.added_mos", "\n".join(validation["errors"]))

    def test_validate_rejects_outer_scf_threshold_looser_than_inner_scf(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(
            template,
            {
                "eps_scf": "1.0E-6",
                "outer_scf_enabled": True,
                "outer_scf_eps_scf": "1.0E-5",
            },
        )
        validation = validate_template(merged)

        self.assertFalse(validation["valid"])
        self.assertIn("dft.outer_scf_eps_scf", "\n".join(validation["errors"]))

    def test_validate_rejects_open_shell_multiplicity_without_uks(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(template, {"multiplicity": "2", "uks_enabled": False})
        validation = validate_template(merged)

        self.assertFalse(validation["valid"])
        self.assertIn("dft.uks_enabled", "\n".join(validation["errors"]))

    def test_validate_rejects_pbe_parametrization_with_non_pbe_functional(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(template, {"xc_functional": "BLYP", "xc_pbe_parametrization": "PBESOL"})
        validation = validate_template(merged)

        self.assertFalse(validation["valid"])
        self.assertIn("dft.xc_pbe_parametrization", "\n".join(validation["errors"]))

    def test_validate_rejects_kpoints_options_without_scheme(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(template, {"kpoints_full_grid": True})
        validation = validate_template(merged)

        self.assertFalse(validation["valid"])
        self.assertIn("KPOINTS options require dft.kpoints_scheme", "\n".join(validation["errors"]))

    def test_validate_rejects_unknown_poisson_solver(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(template, {"poisson_solver": "not_a_solver"})
        validation = validate_template(merged)

        self.assertFalse(validation["valid"])
        self.assertIn("dft.poisson_solver has an unsupported value", validation["errors"])

    def test_validate_rejects_wfn_restart_file_without_restart_guess(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(template, {"wfn_restart_file_name": "previous-RESTART.wfn"})
        validation = validate_template(merged)

        self.assertFalse(validation["valid"])
        self.assertIn("dft.wfn_restart_file_name requires dft.scf_guess", "\n".join(validation["errors"]))

    def test_validate_rejects_unknown_scf_guess(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(template, {"scf_guess": "from_memory"})
        validation = validate_template(merged)

        self.assertFalse(validation["valid"])
        self.assertIn("dft.scf_guess has an unsupported value", validation["errors"])

    def test_validate_rejects_noninteger_kpoints_grid(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(
            template,
            {
                "kpoints_scheme": "MONKHORST-PACK",
                "kpoints_grid": [2, 2.5, 2],
            },
        )
        validation = validate_template(merged)

        self.assertFalse(validation["valid"])
        self.assertIn("dft.kpoints_grid must contain integer values", validation["errors"])

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

    def test_validate_accepts_cell_opt_template(self) -> None:
        template = load_template(ENERGY_TEMPLATE)
        merged = merge_template_fields(template, {"run_type": "CELL_OPT"})
        validation = validate_template(merged)

        self.assertTrue(validation["valid"], validation["errors"])
        self.assertEqual(validation["template"]["run_type"], "CELL_OPT")
        self.assertIn("cell_opt", validation["template"])
        self.assertIn("CELL_OPT template did not define cell_opt; defaults were added.", validation["warnings"])

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
                "xc_pbe_parametrization",
                "dispersion_enabled",
                "dispersion_type",
                "dispersion_parameter_file_name",
                "dispersion_reference_functional",
                "charge",
                "multiplicity",
                "uks_enabled",
                "cutoff",
                "rel_cutoff",
                "poisson_solver",
                "wfn_restart_file_name",
                "print_mulliken",
                "print_lowdin",
                "scf_guess",
                "eps_scf",
                "max_scf",
                "outer_scf_enabled",
                "outer_scf_eps_scf",
                "outer_scf_max_scf",
                "scf_method",
                "added_mos",
                "ot_minimizer",
                "ot_preconditioner",
                "diagonalization_algorithm",
                "mixing_enabled",
                "mixing_method",
                "mixing_alpha",
                "mixing_beta",
                "smearing_enabled",
                "smearing_method",
                "electronic_temperature",
                "kpoints_scheme",
                "kpoints_grid",
                "kpoints_full_grid",
                "kpoints_symmetry",
                "kpoints_wavefunctions",
            ])
            self.assertFalse(template_path.read_bytes().startswith(b"\xef\xbb\xbf"))

    def test_save_template_writes_print_level_after_run_type(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            template_path = Path(tmp_dir) / "template.json"
            template = merge_template_fields(load_template(ENERGY_TEMPLATE), {"print_level": "debug"})

            saved = save_template(template_path, template)

            self.assertEqual(list(saved)[:3], ["project_name", "run_type", "print_level"])
            self.assertEqual(saved["print_level"], "DEBUG")

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

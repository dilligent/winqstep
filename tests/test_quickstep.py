import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from winqstep.quickstep import (
    QuickStepInputError,
    quickstep_input_from_dict,
    render_quickstep_input,
)


ROOT = Path(__file__).resolve().parents[1]


class QuickStepTests(unittest.TestCase):
    def test_renders_energy_snapshot(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        expected = (ROOT / "tests" / "fixtures" / "quickstep_energy.inp").read_text(encoding="utf-8")

        self.assertEqual(render_quickstep_input(quickstep_input_from_dict(data)), expected)

    def test_renders_geo_opt_snapshot(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_geo_opt.json").read_text(encoding="utf-8"))
        expected = (ROOT / "tests" / "fixtures" / "quickstep_geo_opt.inp").read_text(encoding="utf-8")

        self.assertEqual(render_quickstep_input(quickstep_input_from_dict(data)), expected)

    def test_renders_energy_force_snapshot(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy_force.json").read_text(encoding="utf-8"))
        expected = (ROOT / "tests" / "fixtures" / "quickstep_energy_force.inp").read_text(encoding="utf-8")

        self.assertEqual(render_quickstep_input(quickstep_input_from_dict(data)), expected)

    def test_renders_energy_force_without_geo_opt_section(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy_force.json").read_text(encoding="utf-8"))
        rendered = render_quickstep_input(quickstep_input_from_dict(data))
        self.assertIn("  RUN_TYPE ENERGY_FORCE\n", rendered)
        self.assertIn("    &FORCES ON\n", rendered)
        self.assertIn("    &POISSON\n      PERIODIC XYZ\n    &END POISSON\n", rendered)
        self.assertNotIn("&GEO_OPT", rendered)
        self.assertNotIn("&MOTION", rendered)

    def test_rejects_non_quickstep_run_type(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["run_type"] = "MD"

        with self.assertRaises(QuickStepInputError):
            quickstep_input_from_dict(data)

    def test_rejects_missing_kind(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["structure"]["kinds"] = data["structure"]["kinds"][:1]

        with self.assertRaises(QuickStepInputError):
            quickstep_input_from_dict(data)

    def test_rejects_zero_vector_for_periodic_cell(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["structure"]["cell"]["a"] = [0.0, 0.0, 0.0]

        with self.assertRaisesRegex(QuickStepInputError, "periodic cell vectors"):
            quickstep_input_from_dict(data)

    def test_renders_ot_scf_section(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"]["scf_method"] = "ot"
        data["dft"]["ot_minimizer"] = "diis"
        data["dft"]["ot_preconditioner"] = "full_kinetic"

        rendered = render_quickstep_input(quickstep_input_from_dict(data))

        self.assertIn("      &OT\n        MINIMIZER DIIS\n        PRECONDITIONER FULL_KINETIC\n      &END OT\n", rendered)
        self.assertNotIn("&DIAGONALIZATION", rendered)

    def test_renders_diagonalization_mixing_and_smearing(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"].update(
            {
                "scf_method": "diagonalization",
                "added_mos": 4,
                "diagonalization_algorithm": "standard",
                "mixing_enabled": True,
                "mixing_method": "broyden_mixing",
                "mixing_alpha": "0.3",
                "mixing_beta": "1.5",
                "smearing_enabled": True,
                "smearing_method": "fermi_dirac",
                "electronic_temperature": "500",
            }
        )

        rendered = render_quickstep_input(quickstep_input_from_dict(data))

        self.assertIn("      ADDED_MOS 4\n", rendered)
        self.assertIn("      &DIAGONALIZATION\n        ALGORITHM STANDARD\n      &END DIAGONALIZATION\n", rendered)
        self.assertIn("      &MIXING\n        METHOD BROYDEN_MIXING\n        ALPHA 0.3\n        BETA 1.5\n      &END MIXING\n", rendered)
        self.assertIn(
            "      &SMEAR ON\n        METHOD FERMI_DIRAC\n        TELEC [K] 500\n      &END SMEAR\n",
            rendered,
        )

    def test_renders_monkhorst_pack_kpoints_section(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"].update(
            {
                "kpoints_scheme": "monkhorst-pack",
                "kpoints_grid": "2 2 1",
                "kpoints_full_grid": True,
                "kpoints_symmetry": True,
                "kpoints_wavefunctions": "real",
            }
        )

        rendered = render_quickstep_input(quickstep_input_from_dict(data))

        self.assertIn(
            "    &KPOINTS\n"
            "      SCHEME MONKHORST-PACK 2 2 1\n"
            "      FULL_GRID T\n"
            "      SYMMETRY T\n"
            "      WAVEFUNCTIONS REAL\n"
            "    &END KPOINTS\n",
            rendered,
        )

    def test_renders_gamma_kpoints_without_grid(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"]["kpoints_scheme"] = "gamma"

        rendered = render_quickstep_input(quickstep_input_from_dict(data))

        self.assertIn("    &KPOINTS\n      SCHEME GAMMA\n    &END KPOINTS\n", rendered)
        self.assertNotIn("SCHEME GAMMA 1 1 1", rendered)

    def test_rejects_kpoints_for_nonperiodic_cell(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["structure"]["cell"]["periodic"] = "NONE"
        data["dft"]["kpoints_scheme"] = "MONKHORST-PACK"
        data["dft"]["kpoints_grid"] = [2, 2, 2]

        with self.assertRaisesRegex(QuickStepInputError, "KPOINTS require"):
            quickstep_input_from_dict(data)

    def test_rejects_mixing_without_diagonalization(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"]["mixing_enabled"] = True

        with self.assertRaisesRegex(QuickStepInputError, "mixing requires"):
            quickstep_input_from_dict(data)

    def test_cli_writes_output_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            output_path = Path(tmp_dir) / "water.inp"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "render_quickstep_input.py"),
                    "--input-json",
                    str(ROOT / "examples" / "quickstep_energy.json"),
                    "--output",
                    str(output_path),
                ],
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
            self.assertTrue(output_path.read_text(encoding="utf-8").startswith("# Generated by WinQStep"))


if __name__ == "__main__":
    unittest.main()

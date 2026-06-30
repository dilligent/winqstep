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

    def test_renders_cell_opt_snapshot(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_cell_opt.json").read_text(encoding="utf-8"))
        expected = (ROOT / "tests" / "fixtures" / "quickstep_cell_opt.inp").read_text(encoding="utf-8")

        self.assertEqual(render_quickstep_input(quickstep_input_from_dict(data)), expected)

    def test_renders_fixed_atom_constraints_for_geo_opt(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_geo_opt.json").read_text(encoding="utf-8"))
        data["motion"] = {
            "fixed_atoms": [1, 3],
            "fixed_atom_components": "xy",
        }

        rendered = render_quickstep_input(quickstep_input_from_dict(data))

        self.assertIn(
            "&MOTION\n"
            "  &CONSTRAINT\n"
            "    &FIXED_ATOMS\n"
            "      LIST 1 3\n"
            "      COMPONENTS_TO_FIX XY\n"
            "    &END FIXED_ATOMS\n"
            "  &END CONSTRAINT\n"
            "  &GEO_OPT\n",
            rendered,
        )

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

    def test_renders_global_print_level_when_set(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["print_level"] = "low"

        rendered = render_quickstep_input(quickstep_input_from_dict(data))

        self.assertIn("  PRINT_LEVEL LOW\n", rendered)

    def test_renders_uks_when_enabled(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"].update({"uks_enabled": True, "multiplicity": 2})

        rendered = render_quickstep_input(quickstep_input_from_dict(data))

        self.assertIn("    MULTIPLICITY 2\n    UKS T\n", rendered)

    def test_renders_pbesol_parametrization(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"]["xc_pbe_parametrization"] = "pbesol"

        rendered = render_quickstep_input(quickstep_input_from_dict(data))

        self.assertIn(
            "    &XC\n"
            "      &XC_FUNCTIONAL PBE\n"
            "        PARAMETRIZATION PBESOL\n"
            "      &END XC_FUNCTIONAL\n"
            "    &END XC\n",
            rendered,
        )

    def test_renders_dftd3_dispersion_when_enabled(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"].update(
            {
                "dispersion_enabled": True,
                "dispersion_type": "DFTD3",
                "dispersion_parameter_file_name": "dftd3.dat",
                "dispersion_reference_functional": "PBE",
            }
        )

        rendered = render_quickstep_input(quickstep_input_from_dict(data))

        self.assertIn(
            "      &VDW_POTENTIAL\n"
            "        POTENTIAL_TYPE PAIR_POTENTIAL\n"
            "        &PAIR_POTENTIAL\n"
            "          TYPE DFTD3\n"
            "          PARAMETER_FILE_NAME dftd3.dat\n"
            "          REFERENCE_FUNCTIONAL PBE\n"
            "        &END PAIR_POTENTIAL\n"
            "      &END VDW_POTENTIAL\n",
            rendered,
        )

    def test_renders_explicit_poisson_solver_when_set(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"]["poisson_solver"] = "periodic"

        rendered = render_quickstep_input(quickstep_input_from_dict(data))

        self.assertIn(
            "    &POISSON\n"
            "      PERIODIC XYZ\n"
            "      POISSON_SOLVER PERIODIC\n"
            "    &END POISSON\n",
            rendered,
        )

    def test_blank_poisson_solver_preserves_existing_poisson_output(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"]["poisson_solver"] = ""

        rendered = render_quickstep_input(quickstep_input_from_dict(data))

        self.assertIn("    &POISSON\n      PERIODIC XYZ\n    &END POISSON\n", rendered)
        self.assertNotIn("POISSON_SOLVER", rendered)

    def test_renders_wavefunction_restart_controls(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"].update(
            {
                "wfn_restart_file_name": "previous-RESTART.wfn",
                "scf_guess": "restart",
            }
        )

        rendered = render_quickstep_input(quickstep_input_from_dict(data))

        self.assertIn("    WFN_RESTART_FILE_NAME previous-RESTART.wfn\n", rendered)
        self.assertIn(
            "    &SCF\n"
            "      SCF_GUESS RESTART\n"
            "      EPS_SCF 1.0E-6\n",
            rendered,
        )

    def test_blank_restart_controls_preserve_existing_scf_output(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"].update({"wfn_restart_file_name": "", "scf_guess": ""})

        rendered = render_quickstep_input(quickstep_input_from_dict(data))

        self.assertIn("    &SCF\n      EPS_SCF 1.0E-6\n      MAX_SCF 50\n    &END SCF\n", rendered)
        self.assertNotIn("WFN_RESTART_FILE_NAME", rendered)
        self.assertNotIn("SCF_GUESS", rendered)

    def test_renders_dft_print_population_sections_when_enabled(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"].update(
            {
                "print_mulliken": True,
                "print_lowdin": True,
                "print_pdos": True,
                "print_e_density_cube": True,
                "print_v_hartree_cube": True,
            }
        )

        rendered = render_quickstep_input(quickstep_input_from_dict(data))

        self.assertIn(
            "    &PRINT\n"
            "      &MULLIKEN ON\n"
            "      &END MULLIKEN\n"
            "      &LOWDIN ON\n"
            "      &END LOWDIN\n"
            "      &PDOS ON\n"
            "      &END PDOS\n"
            "      &E_DENSITY_CUBE ON\n"
            "      &END E_DENSITY_CUBE\n"
            "      &V_HARTREE_CUBE ON\n"
            "      &END V_HARTREE_CUBE\n"
            "    &END PRINT\n",
            rendered,
        )

    def test_rejects_non_quickstep_run_type(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["run_type"] = "MD"

        with self.assertRaises(QuickStepInputError):
            quickstep_input_from_dict(data)

    def test_rejects_unknown_print_level(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["print_level"] = "verbose"

        with self.assertRaisesRegex(QuickStepInputError, "print_level"):
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

    def test_renders_outer_scf_section_when_enabled(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"].update(
            {
                "outer_scf_enabled": True,
                "outer_scf_eps_scf": "1.0E-7",
                "outer_scf_max_scf": 20,
            }
        )

        rendered = render_quickstep_input(quickstep_input_from_dict(data))

        self.assertIn(
            "      &OUTER_SCF\n"
            "        EPS_SCF 1.0E-7\n"
            "        MAX_SCF 20\n"
            "      &END OUTER_SCF\n",
            rendered,
        )

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

    def test_rejects_cell_opt_for_nonperiodic_cell(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_cell_opt.json").read_text(encoding="utf-8"))
        data["structure"]["cell"]["periodic"] = "NONE"
        data["dft"]["kpoints_scheme"] = "NONE"

        with self.assertRaisesRegex(QuickStepInputError, "CELL_OPT requires"):
            quickstep_input_from_dict(data)

    def test_rejects_fixed_atoms_for_energy_run(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["motion"] = {"fixed_atoms": "1 2", "fixed_atom_components": "XYZ"}

        with self.assertRaisesRegex(QuickStepInputError, "fixed_atoms requires"):
            quickstep_input_from_dict(data)

    def test_rejects_fixed_atom_index_outside_structure(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_geo_opt.json").read_text(encoding="utf-8"))
        data["motion"] = {"fixed_atoms": [4], "fixed_atom_components": "XYZ"}

        with self.assertRaisesRegex(QuickStepInputError, "outside the structure atom count"):
            quickstep_input_from_dict(data)

    def test_rejects_duplicate_fixed_atom_indices(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_geo_opt.json").read_text(encoding="utf-8"))
        data["motion"] = {"fixed_atoms": [1, 1], "fixed_atom_components": "XYZ"}

        with self.assertRaisesRegex(QuickStepInputError, "duplicate"):
            quickstep_input_from_dict(data)

    def test_rejects_unknown_fixed_atom_components(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_geo_opt.json").read_text(encoding="utf-8"))
        data["motion"] = {"fixed_atoms": [1], "fixed_atom_components": "AB"}

        with self.assertRaisesRegex(QuickStepInputError, "fixed_atom_components"):
            quickstep_input_from_dict(data)

    def test_rejects_poisson_solver_for_unsupported_periodicity(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["structure"]["cell"]["periodic"] = "XY"
        data["dft"]["poisson_solver"] = "PERIODIC"

        with self.assertRaisesRegex(QuickStepInputError, "poisson_solver PERIODIC"):
            quickstep_input_from_dict(data)

    def test_rejects_unknown_scf_guess(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"]["scf_guess"] = "from_memory"

        with self.assertRaisesRegex(QuickStepInputError, "scf_guess"):
            quickstep_input_from_dict(data)

    def test_rejects_wfn_restart_file_without_restart_guess(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"].update({"wfn_restart_file_name": "previous-RESTART.wfn", "scf_guess": "atomic"})

        with self.assertRaisesRegex(QuickStepInputError, "wfn_restart_file_name"):
            quickstep_input_from_dict(data)

    def test_rejects_mixing_without_diagonalization(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"]["mixing_enabled"] = True

        with self.assertRaisesRegex(QuickStepInputError, "mixing requires"):
            quickstep_input_from_dict(data)

    def test_rejects_outer_scf_threshold_looser_than_inner_scf(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"].update(
            {
                "eps_scf": "1.0E-6",
                "outer_scf_enabled": True,
                "outer_scf_eps_scf": "1.0E-5",
            }
        )

        with self.assertRaisesRegex(QuickStepInputError, "outer_scf_eps_scf"):
            quickstep_input_from_dict(data)

    def test_rejects_open_shell_multiplicity_without_uks(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"]["multiplicity"] = 2

        with self.assertRaisesRegex(QuickStepInputError, "uks_enabled"):
            quickstep_input_from_dict(data)

    def test_rejects_pbe_parametrization_for_non_pbe_shortcut(self) -> None:
        data = json.loads((ROOT / "examples" / "quickstep_energy.json").read_text(encoding="utf-8"))
        data["dft"].update({"xc_functional": "BLYP", "xc_pbe_parametrization": "PBESOL"})

        with self.assertRaisesRegex(QuickStepInputError, "xc_pbe_parametrization"):
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

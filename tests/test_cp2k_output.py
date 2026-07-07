import tempfile
import unittest
from pathlib import Path

from winqstep.cp2k_output import parse_cp2k_output_file, parse_cp2k_output_text


ROOT = Path(__file__).resolve().parents[1]


class Cp2kOutputTests(unittest.TestCase):
    def test_parses_successful_output_summary(self) -> None:
        summary = parse_cp2k_output_file(ROOT / "tests" / "fixtures" / "cp2k_success.out")

        self.assertTrue(summary["available"])
        self.assertEqual(summary["status"], "completed")
        self.assertEqual(summary["warning_count"], 0)
        self.assertTrue(summary["program_ended"])
        self.assertEqual(summary["ended_at"], "2026-06-29 03:24:28.023")
        self.assertEqual(summary["stopped_in"], "/mnt/d/Library/winqstep/outputs/job")
        self.assertIsNone(summary["total_energy_hartree"])
        self.assertIsNone(summary["forces"])
        self.assertIsNone(summary["walltime_seconds"])
        self.assertIsNone(summary["scf"])
        self.assertIsNone(summary["cell"])

    def test_parses_energy_force_summary(self) -> None:
        summary = parse_cp2k_output_file(ROOT / "tests" / "fixtures" / "cp2k_energy_force.out")

        self.assertTrue(summary["available"])
        self.assertEqual(summary["status"], "completed")
        self.assertEqual(summary["warning_count"], 0)
        self.assertAlmostEqual(summary["total_energy_hartree"], -17.219350325303314)
        self.assertEqual(summary["stopped_in"], "/mnt/d/Library/winqstep/outputs/energy-force-live-smoke")
        forces = summary["forces"]
        self.assertEqual(forces["unit"], "hartree/bohr")
        self.assertEqual(len(forces["atoms"]), 3)
        self.assertEqual(forces["atoms"][0]["atom"], 1)
        self.assertAlmostEqual(forces["atoms"][0]["z"], -1.35588799e-2)
        self.assertAlmostEqual(forces["atoms"][1]["norm"], 1.25910344e-2)
        self.assertAlmostEqual(forces["sum"]["z"], 1.48299452e-3)
        self.assertAlmostEqual(forces["total_atomic_force"], 1.48299452e-3)
        self.assertAlmostEqual(summary["walltime_seconds"], 7.086)

        scf = summary["scf"]
        self.assertTrue(scf["converged"])
        self.assertEqual(scf["step_count"], 11)
        self.assertEqual(scf["final_step"], 11)
        self.assertAlmostEqual(scf["final_time_seconds"], 0.3)
        self.assertAlmostEqual(scf["final_convergence"], 0.00000021)
        self.assertAlmostEqual(scf["final_total_energy_hartree"], -17.2193503253)
        self.assertAlmostEqual(scf["final_energy_change_hartree"], -2.68e-12)

        cell = summary["cell"]
        self.assertEqual(cell["unit"], "angstrom")
        self.assertAlmostEqual(cell["volume_angstrom3"], 1000.0)
        self.assertEqual(cell["a"], [10.0, 0.0, 0.0])
        self.assertEqual(cell["b"], [0.0, 10.0, 0.0])
        self.assertEqual(cell["c"], [0.0, 0.0, 10.0])
        self.assertAlmostEqual(cell["lengths"]["a"], 10.0)
        self.assertAlmostEqual(cell["angles_degrees"]["gamma"], 90.0)
        self.assertTrue(cell["orthorhombic"])
        self.assertEqual(cell["periodicity"], "XYZ")

    def test_parses_not_converged_scf_summary(self) -> None:
        summary = parse_cp2k_output_text(
            " SCF WAVEFUNCTION OPTIMIZATION\n"
            "\n"
            "  Step     Update method      Time    Convergence         Total energy    Change\n"
            "  ------------------------------------------------------------------------------\n"
            "    50 DIIS/Diag.  0.67E-03    0.1     0.09309638        -7.6597766131 -1.87E-04\n"
            "\n"
            "  Leaving inner SCF loop after reaching    50 steps.\n"
            "  \\___/     SCF run NOT converged. To continue the calculation regardless,\n"
        )

        scf = summary["scf"]
        self.assertFalse(scf["converged"])
        self.assertEqual(scf["step_count"], 50)
        self.assertEqual(scf["final_step"], 50)
        self.assertAlmostEqual(scf["final_convergence"], 0.09309638)
        self.assertAlmostEqual(scf["final_total_energy_hartree"], -7.6597766131)

    def test_incomplete_output_keeps_available_status(self) -> None:
        summary = parse_cp2k_output_text("SCF did not converge\n")

        self.assertTrue(summary["available"])
        self.assertEqual(summary["status"], "incomplete")
        self.assertIsNone(summary["warning_count"])
        self.assertFalse(summary["program_ended"])
        self.assertIsNone(summary["forces"])
        self.assertIsNone(summary["scf"])

    def test_missing_output_is_not_available(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            summary = parse_cp2k_output_file(Path(tmp_dir) / "missing.out")

        self.assertFalse(summary["available"])
        self.assertEqual(summary["status"], "not_available")
        self.assertIsNone(summary["warning_count"])
        self.assertIsNone(summary["walltime_seconds"])
        self.assertIsNone(summary["scf"])
        self.assertIsNone(summary["cell"])


if __name__ == "__main__":
    unittest.main()

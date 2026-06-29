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

    def test_incomplete_output_keeps_available_status(self) -> None:
        summary = parse_cp2k_output_text("SCF did not converge\n")

        self.assertTrue(summary["available"])
        self.assertEqual(summary["status"], "incomplete")
        self.assertIsNone(summary["warning_count"])
        self.assertFalse(summary["program_ended"])
        self.assertIsNone(summary["forces"])

    def test_missing_output_is_not_available(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            summary = parse_cp2k_output_file(Path(tmp_dir) / "missing.out")

        self.assertFalse(summary["available"])
        self.assertEqual(summary["status"], "not_available")
        self.assertIsNone(summary["warning_count"])


if __name__ == "__main__":
    unittest.main()

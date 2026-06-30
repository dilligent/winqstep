import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from winqstep.runner import _decode_process_text, load_json_file, run_quickstep_job, safe_job_stem


ROOT = Path(__file__).resolve().parents[1]


class RunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = load_json_file(ROOT / "examples" / "winqstep.config.example.json")
        self.quickstep = load_json_file(ROOT / "examples" / "quickstep_energy.json")

    def test_safe_job_stem_removes_path_separators(self) -> None:
        self.assertEqual(safe_job_stem("water / energy"), "water_energy")

    def test_decode_process_text_handles_utf16_wsl_output(self) -> None:
        self.assertEqual(_decode_process_text("wsl: test".encode("utf-16-le")), "wsl: test")

    def test_prepare_only_writes_input_and_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            metadata = run_quickstep_job(
                config=self.config,
                quickstep_data=self.quickstep,
                windows_job_dir=tmp_dir,
                execute=False,
            )

            self.assertEqual(metadata["status"], "prepared")
            self.assertTrue(Path(metadata["files"]["input"]["path"]).exists())
            self.assertTrue(Path(metadata["dry_run"]["windows"]["metadata_path"]).exists())
            self.assertFalse(Path(metadata["files"]["output"]["path"]).exists())
            self.assertEqual(metadata["cp2k_output"]["status"], "not_available")
            self.assertEqual(
                metadata["files"]["metadata"]["size"],
                Path(metadata["files"]["metadata"]["path"]).stat().st_size,
            )

    def test_prepare_only_accepts_relative_job_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            original_cwd = Path.cwd()
            try:
                os.chdir(tmp_dir)
                metadata = run_quickstep_job(
                    config=self.config,
                    quickstep_data=self.quickstep,
                    windows_job_dir="relative-job",
                    execute=False,
                )
            finally:
                os.chdir(original_cwd)

            self.assertTrue(Path(tmp_dir, "relative-job", "water_energy.inp").exists())
            self.assertIn("/relative-job/water_energy.inp", metadata["dry_run"]["wsl"]["input_path"])

    def test_successful_executor_updates_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            job_dir = Path(tmp_dir)
            (job_dir / "water_energy.out").write_text("stale output", encoding="utf-8")

            def fake_executor(argv: list[str]) -> SimpleNamespace:
                self.assertEqual(argv[0], "wsl.exe")
                self.assertFalse((job_dir / "water_energy.out").exists())
                (job_dir / "water_energy.out").write_text(
                    "The number of warnings for this run is : 0\n"
                    "PROGRAM ENDED AT                 2026-06-29 03:24:28.023\n",
                    encoding="utf-8",
                )
                (job_dir / "water_energy.stdout.log").write_text("", encoding="utf-8")
                (job_dir / "water_energy.stderr.log").write_text("", encoding="utf-8")
                return SimpleNamespace(returncode=0, stdout=b"", stderr=b"")

            metadata = run_quickstep_job(
                config=self.config,
                quickstep_data=self.quickstep,
                windows_job_dir=tmp_dir,
                executor=fake_executor,
            )

            self.assertEqual(metadata["status"], "succeeded")
            self.assertEqual(metadata["returncode"], 0)
            self.assertEqual(metadata["cp2k_output"]["status"], "completed")
            self.assertEqual(metadata["cp2k_output"]["warning_count"], 0)
            self.assertTrue(metadata["files"]["output"]["exists"])
            saved = json.loads(Path(metadata["dry_run"]["windows"]["metadata_path"]).read_text(encoding="utf-8"))
            self.assertEqual(saved["status"], "succeeded")
            self.assertEqual(saved["cp2k_output"]["status"], "completed")
            self.assertEqual(
                saved["files"]["metadata"]["size"],
                Path(metadata["files"]["metadata"]["path"]).stat().st_size,
            )

    def test_generated_artifacts_exclude_preexisting_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            job_dir = Path(tmp_dir)
            (job_dir / "old-k1-1.pdos").write_text("old", encoding="utf-8")
            (job_dir / "old-ELECTRON_DENSITY.cube").write_text("old", encoding="utf-8")

            def fake_executor(argv: list[str]) -> SimpleNamespace:
                (job_dir / "water_energy.out").write_text(
                    "The number of warnings for this run is : 0\n"
                    "PROGRAM ENDED AT                 2026-06-29 03:24:28.023\n",
                    encoding="utf-8",
                )
                (job_dir / "water_energy.stdout.log").write_text("", encoding="utf-8")
                (job_dir / "water_energy.stderr.log").write_text("", encoding="utf-8")
                (job_dir / "water_energy-k1-1.pdos").write_text("new", encoding="utf-8")
                (job_dir / "water_energy-ELECTRON_DENSITY.cube").write_text("new", encoding="utf-8")
                (job_dir / "water_energy-v_hartree.cube").write_text("new", encoding="utf-8")
                return SimpleNamespace(returncode=0, stdout=b"", stderr=b"")

            metadata = run_quickstep_job(
                config=self.config,
                quickstep_data=self.quickstep,
                windows_job_dir=tmp_dir,
                executor=fake_executor,
            )

            self.assertEqual(
                [item["name"] for item in metadata["files"]["generated"]],
                [
                    "water_energy-ELECTRON_DENSITY.cube",
                    "water_energy-k1-1.pdos",
                    "water_energy-v_hartree.cube",
                ],
            )
            self.assertEqual(
                [item["type"] for item in metadata["files"]["generated"]],
                ["electron_density_cube", "pdos", "hartree_potential_cube"],
            )

    def test_energy_force_executor_updates_force_summary(self) -> None:
        quickstep = load_json_file(ROOT / "examples" / "quickstep_energy_force.json")
        with tempfile.TemporaryDirectory() as tmp_dir:
            job_dir = Path(tmp_dir)

            def fake_executor(argv: list[str]) -> SimpleNamespace:
                (job_dir / "water_energy_force.out").write_text(
                    (ROOT / "tests" / "fixtures" / "cp2k_energy_force.out").read_text(encoding="utf-8"),
                    encoding="utf-8",
                )
                (job_dir / "water_energy_force.stdout.log").write_text("", encoding="utf-8")
                (job_dir / "water_energy_force.stderr.log").write_text("", encoding="utf-8")
                return SimpleNamespace(returncode=0, stdout=b"", stderr=b"")

            metadata = run_quickstep_job(
                config=self.config,
                quickstep_data=quickstep,
                windows_job_dir=tmp_dir,
                executor=fake_executor,
            )

            self.assertEqual(metadata["status"], "succeeded")
            self.assertEqual(metadata["quickstep"]["run_type"], "ENERGY_FORCE")
            self.assertAlmostEqual(metadata["cp2k_output"]["total_energy_hartree"], -17.219350325303314)
            self.assertAlmostEqual(metadata["cp2k_output"]["forces"]["total_atomic_force"], 1.48299452e-3)

    def test_failed_executor_records_wrapper_stderr(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:

            def fake_executor(argv: list[str]) -> SimpleNamespace:
                return SimpleNamespace(returncode=42, stdout=b"", stderr=b"wrapper failure")

            metadata = run_quickstep_job(
                config=self.config,
                quickstep_data=self.quickstep,
                windows_job_dir=tmp_dir,
                executor=fake_executor,
            )

            self.assertEqual(metadata["status"], "failed")
            self.assertEqual(metadata["returncode"], 42)
            self.assertEqual(metadata["wrapper"]["stderr"], "wrapper failure")


if __name__ == "__main__":
    unittest.main()

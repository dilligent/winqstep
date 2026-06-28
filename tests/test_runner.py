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
        self.config = load_json_file(ROOT / "examples" / "winqstep.config.json")
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
                (job_dir / "water_energy.out").write_text("PROGRAM ENDED\n", encoding="utf-8")
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
            self.assertTrue(metadata["files"]["output"]["exists"])
            saved = json.loads(Path(metadata["dry_run"]["windows"]["metadata_path"]).read_text(encoding="utf-8"))
            self.assertEqual(saved["status"], "succeeded")
            self.assertEqual(
                saved["files"]["metadata"]["size"],
                Path(metadata["files"]["metadata"]["path"]).stat().st_size,
            )

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

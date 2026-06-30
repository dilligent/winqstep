import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from winqstep.runner import RunnerError, load_json_file, mark_job_cancelled, run_existing_input_job


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_INPUT = ROOT / "tests" / "fixtures" / "quickstep_energy.inp"


class ExistingInputRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = load_json_file(ROOT / "examples" / "winqstep.config.example.json")

    def test_prepare_only_uses_existing_input_without_rewriting_it(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            input_path = Path(tmp_dir) / "existing.inp"
            original = FIXTURE_INPUT.read_text(encoding="utf-8")
            input_path.write_text(original, encoding="utf-8")
            job_dir = Path(tmp_dir) / "job"

            metadata = run_existing_input_job(
                config=self.config,
                windows_input_path=input_path,
                windows_job_dir=job_dir,
                execute=False,
            )

            self.assertEqual(metadata["status"], "prepared")
            self.assertEqual(metadata["job"]["mode"], "existing_input")
            self.assertEqual(input_path.read_text(encoding="utf-8"), original)
            self.assertEqual(Path(metadata["files"]["input"]["path"]), input_path.resolve())
            self.assertTrue(Path(metadata["files"]["metadata"]["path"]).exists())
            self.assertFalse(Path(metadata["files"]["output"]["path"]).exists())
            self.assertEqual(metadata["cp2k_output"]["status"], "not_available")
            self.assertEqual(
                metadata["files"]["metadata"]["size"],
                Path(metadata["files"]["metadata"]["path"]).stat().st_size,
            )

    def test_successful_executor_updates_metadata_and_preserves_input(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            input_path = Path(tmp_dir) / "water.inp"
            original = FIXTURE_INPUT.read_text(encoding="utf-8")
            input_path.write_text(original, encoding="utf-8")
            job_dir = Path(tmp_dir) / "job"
            job_dir.mkdir()
            (job_dir / "water.out").write_text("stale output", encoding="utf-8")

            def fake_executor(argv: list[str]) -> SimpleNamespace:
                self.assertEqual(argv[0], "wsl.exe")
                self.assertFalse((job_dir / "water.out").exists())
                self.assertEqual(input_path.read_text(encoding="utf-8"), original)
                (job_dir / "water.out").write_text(
                    "The number of warnings for this run is : 0\n"
                    "PROGRAM ENDED AT                 2026-06-29 03:24:28.023\n",
                    encoding="utf-8",
                )
                (job_dir / "water.stdout.log").write_text("", encoding="utf-8")
                (job_dir / "water.stderr.log").write_text("", encoding="utf-8")
                return SimpleNamespace(returncode=0, stdout=b"", stderr=b"")

            metadata = run_existing_input_job(
                config=self.config,
                windows_input_path=input_path,
                windows_job_dir=job_dir,
                executor=fake_executor,
            )

            self.assertEqual(metadata["status"], "succeeded")
            self.assertEqual(metadata["returncode"], 0)
            self.assertEqual(metadata["cp2k_output"]["status"], "completed")
            self.assertEqual(metadata["cp2k_output"]["warning_count"], 0)
            self.assertEqual(input_path.read_text(encoding="utf-8"), original)
            saved = json.loads(Path(metadata["files"]["metadata"]["path"]).read_text(encoding="utf-8"))
            self.assertEqual(saved["status"], "succeeded")
            self.assertEqual(saved["cp2k_output"]["status"], "completed")
            self.assertEqual(
                saved["files"]["metadata"]["size"],
                Path(metadata["files"]["metadata"]["path"]).stat().st_size,
            )

    def test_missing_input_file_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            with self.assertRaisesRegex(RunnerError, "input file does not exist"):
                run_existing_input_job(
                    config=self.config,
                    windows_input_path=Path(tmp_dir) / "missing.inp",
                    windows_job_dir=Path(tmp_dir) / "job",
                    execute=False,
                )

    def test_mark_cancelled_updates_existing_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            input_path = Path(tmp_dir) / "existing.inp"
            input_path.write_text(FIXTURE_INPUT.read_text(encoding="utf-8"), encoding="utf-8")
            job_dir = Path(tmp_dir) / "job"
            metadata = run_existing_input_job(
                config=self.config,
                windows_input_path=input_path,
                windows_job_dir=job_dir,
                execute=False,
            )
            (job_dir / "existing.out").write_text("partial output\n", encoding="utf-8")

            cancelled = mark_job_cancelled(
                metadata["files"]["metadata"]["path"],
                returncode=-1,
                wrapper_stdout="partial json",
                wrapper_stderr="cancelled by user",
            )

            self.assertEqual(cancelled["status"], "cancelled")
            self.assertEqual(cancelled["returncode"], -1)
            self.assertEqual(cancelled["wrapper"]["stderr"], "cancelled by user")
            self.assertTrue(cancelled["files"]["output"]["exists"])
            saved = json.loads(Path(metadata["files"]["metadata"]["path"]).read_text(encoding="utf-8"))
            self.assertEqual(saved["status"], "cancelled")
            self.assertEqual(saved["wrapper"]["stdout"], "partial json")

    def test_cancelled_cli_outputs_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            input_path = Path(tmp_dir) / "existing.inp"
            input_path.write_text(FIXTURE_INPUT.read_text(encoding="utf-8"), encoding="utf-8")
            job_dir = Path(tmp_dir) / "job"
            metadata = run_existing_input_job(
                config=self.config,
                windows_input_path=input_path,
                windows_job_dir=job_dir,
                execute=False,
            )
            stderr_path = Path(tmp_dir) / "wrapper.stderr.log"
            stderr_path.write_text("cancel requested", encoding="utf-8")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "mark_job_cancelled.py"),
                    "--metadata",
                    metadata["files"]["metadata"]["path"],
                    "--returncode",
                    "-1",
                    "--stderr-file",
                    str(stderr_path),
                    "--compact",
                ],
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
            payload = json.loads(completed.stdout.decode("utf-8"))
            self.assertEqual(payload["status"], "cancelled")
            self.assertEqual(payload["wrapper"]["stderr"], "cancel requested")

    def test_cli_prepare_only_outputs_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            input_path = Path(tmp_dir) / "existing.inp"
            input_path.write_text(FIXTURE_INPUT.read_text(encoding="utf-8"), encoding="utf-8")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "run_existing_input.py"),
                    "--config",
                    str(ROOT / "examples" / "winqstep.config.example.json"),
                    "--input",
                    str(input_path),
                    "--job-dir",
                    str(Path(tmp_dir) / "job"),
                    "--prepare-only",
                    "--compact",
                ],
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
            metadata = json.loads(completed.stdout.decode("utf-8"))
            self.assertEqual(metadata["status"], "prepared")
            self.assertEqual(metadata["job"]["mode"], "existing_input")


if __name__ == "__main__":
    unittest.main()

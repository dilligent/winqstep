import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from winqstep.runner import RunnerError, load_json_file, run_existing_input_job


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_INPUT = ROOT / "tests" / "fixtures" / "quickstep_energy.inp"


class ExistingInputRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = load_json_file(ROOT / "examples" / "winqstep.config.json")

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
                (job_dir / "water.out").write_text("PROGRAM ENDED\n", encoding="utf-8")
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
            self.assertEqual(input_path.read_text(encoding="utf-8"), original)
            saved = json.loads(Path(metadata["files"]["metadata"]["path"]).read_text(encoding="utf-8"))
            self.assertEqual(saved["status"], "succeeded")
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

    def test_cli_prepare_only_outputs_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            input_path = Path(tmp_dir) / "existing.inp"
            input_path.write_text(FIXTURE_INPUT.read_text(encoding="utf-8"), encoding="utf-8")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "run_existing_input.py"),
                    "--config",
                    str(ROOT / "examples" / "winqstep.config.json"),
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

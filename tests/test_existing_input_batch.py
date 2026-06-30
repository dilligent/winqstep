import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from winqstep.batch import (
    BATCH_SUMMARY_NAME,
    load_existing_input_batch_summary,
    resolve_existing_input_batch_inputs,
    run_existing_input_batch,
    update_existing_input_batch_item,
)
from winqstep.history import list_job_history
from winqstep.runner import load_json_file


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_INPUT = ROOT / "tests" / "fixtures" / "quickstep_energy.inp"


class ExistingInputBatchTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = load_json_file(ROOT / "examples" / "winqstep.config.example.json")

    def _write_input(self, path: Path) -> Path:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(FIXTURE_INPUT.read_text(encoding="utf-8"), encoding="utf-8")
        return path

    def test_prepare_only_writes_batch_summary_and_item_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            input_a = self._write_input(root / "inputs" / "a.inp")
            input_b = self._write_input(root / "inputs" / "b.inp")
            batch_dir = root / "batch"

            summary = run_existing_input_batch(
                config=self.config,
                input_paths=[input_a, input_b],
                windows_job_dir=batch_dir,
                execute=False,
            )

            self.assertEqual(summary["mode"], "existing_input_batch")
            self.assertEqual(summary["status"], "prepared")
            self.assertEqual(summary["input_count"], 2)
            self.assertEqual(summary["item_count"], 2)
            self.assertEqual(summary["prepared_count"], 2)
            self.assertEqual(summary["completed_count"], 0)
            self.assertTrue(Path(summary["summary_path"]).is_file())
            self.assertTrue(Path(summary["items"][0]["metadata_path"]).is_file())
            self.assertTrue(Path(summary["items"][1]["metadata_path"]).is_file())
            self.assertEqual(Path(summary["items"][0]["job_dir"]), batch_dir / "a")
            self.assertEqual(Path(summary["items"][1]["job_dir"]), batch_dir / "b")

            history = list_job_history(batch_dir)
            self.assertEqual(len(history["jobs"]), 2)
            self.assertEqual(len(history["errors"]), 0)

    def test_duplicate_input_stems_get_unique_job_dirs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            input_a = self._write_input(root / "left" / "water.inp")
            input_b = self._write_input(root / "right" / "water.inp")

            summary = run_existing_input_batch(
                config=self.config,
                input_paths=[input_a, input_b],
                windows_job_dir=root / "batch",
                execute=False,
            )

            job_dirs = [Path(item["job_dir"]).name for item in summary["items"]]
            self.assertEqual(job_dirs[0], "water")
            self.assertTrue(job_dirs[1].startswith("water-"))
            self.assertNotEqual(job_dirs[0], job_dirs[1])

    def test_execute_continues_after_failed_item_by_default(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            input_a = self._write_input(root / "inputs" / "a.inp")
            input_b = self._write_input(root / "inputs" / "b.inp")
            calls = []

            def fake_executor(argv: list[str]) -> SimpleNamespace:
                calls.append(argv)
                return SimpleNamespace(returncode=0 if len(calls) == 1 else 7, stdout=b"", stderr=b"failed")

            summary = run_existing_input_batch(
                config=self.config,
                input_paths=[input_a, input_b],
                windows_job_dir=root / "batch",
                executor=fake_executor,
            )

            self.assertEqual(len(calls), 2)
            self.assertEqual(summary["status"], "completed_with_errors")
            self.assertEqual([item["status"] for item in summary["items"]], ["succeeded", "failed"])
            self.assertEqual(summary["items"][1]["returncode"], 7)
            self.assertEqual(summary["completed_count"], 2)

    def test_stop_on_failure_skips_remaining_items(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            input_a = self._write_input(root / "inputs" / "a.inp")
            input_b = self._write_input(root / "inputs" / "b.inp")

            def fake_executor(argv: list[str]) -> SimpleNamespace:
                return SimpleNamespace(returncode=5, stdout=b"", stderr=b"failed")

            summary = run_existing_input_batch(
                config=self.config,
                input_paths=[input_a, input_b],
                windows_job_dir=root / "batch",
                stop_on_failure=True,
                executor=fake_executor,
            )

            self.assertEqual(summary["status"], "stopped_on_failure")
            self.assertTrue(summary["stopped_on_failure"])
            self.assertEqual(summary["input_count"], 2)
            self.assertEqual(summary["item_count"], 2)
            self.assertEqual(summary["items"][0]["status"], "failed")
            self.assertEqual(summary["items"][1]["status"], "queued")

    def test_resume_continues_pending_items_after_interruption(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            inputs = [
                self._write_input(root / "inputs" / "a.inp"),
                self._write_input(root / "inputs" / "b.inp"),
                self._write_input(root / "inputs" / "c.inp"),
            ]
            calls = []

            def interrupting_executor(argv: list[str]) -> SimpleNamespace:
                calls.append(argv)
                if len(calls) == 2:
                    raise KeyboardInterrupt()
                return SimpleNamespace(returncode=0, stdout=b"", stderr=b"")

            with self.assertRaises(KeyboardInterrupt):
                run_existing_input_batch(
                    config=self.config,
                    input_paths=inputs,
                    windows_job_dir=root / "batch",
                    executor=interrupting_executor,
                )

            interrupted = load_existing_input_batch_summary(root / "batch" / BATCH_SUMMARY_NAME)
            self.assertEqual([item["status"] for item in interrupted["items"]], ["succeeded", "running", "queued"])

            resumed_calls = []

            def success_executor(argv: list[str]) -> SimpleNamespace:
                resumed_calls.append(argv)
                return SimpleNamespace(returncode=0, stdout=b"", stderr=b"")

            summary = run_existing_input_batch(
                config=self.config,
                input_paths=[],
                windows_job_dir=root / "batch",
                resume=True,
                executor=success_executor,
            )

            self.assertEqual(len(resumed_calls), 2)
            self.assertEqual(summary["status"], "succeeded")
            self.assertEqual([item["status"] for item in summary["items"]], ["succeeded", "succeeded", "succeeded"])
            self.assertEqual(summary["resume_count"], 1)

    def test_queue_item_actions_update_batch_summary(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            input_a = self._write_input(root / "inputs" / "a.inp")
            input_b = self._write_input(root / "inputs" / "b.inp")
            summary = run_existing_input_batch(
                config=self.config,
                input_paths=[input_a, input_b],
                windows_job_dir=root / "batch",
                execute=False,
            )
            summary_path = Path(summary["summary_path"])

            skipped = update_existing_input_batch_item(summary_path, index=2, action="skip")
            self.assertEqual(skipped["items"][1]["status"], "skipped")
            self.assertEqual(skipped["skipped_count"], 1)

            queued = update_existing_input_batch_item(summary_path, index=2, action="rerun")
            self.assertEqual(queued["items"][1]["status"], "queued")
            self.assertEqual(queued["status"], "pending")

            cancelled = update_existing_input_batch_item(summary_path, index=1, action="cancel")
            self.assertEqual(cancelled["items"][0]["status"], "cancelled")
            self.assertEqual(cancelled["cancelled_count"], 1)

    def test_cancel_running_item_requests_cancellation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            input_a = self._write_input(root / "inputs" / "a.inp")
            summary = run_existing_input_batch(
                config=self.config,
                input_paths=[input_a],
                windows_job_dir=root / "batch",
                execute=False,
            )
            summary_path = Path(summary["summary_path"])
            summary["items"][0]["status"] = "running"
            summary_path.write_text(json.dumps(summary), encoding="utf-8")

            updated = update_existing_input_batch_item(summary_path, index=1, action="cancel")

            self.assertEqual(updated["items"][0]["status"], "cancel_requested")
            self.assertEqual(updated["status"], "running")

    def test_resolves_input_dir_and_input_list_paths(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            input_a = self._write_input(root / "inputs" / "a.inp")
            input_b = self._write_input(root / "inputs" / "b.inp")
            ignored = root / "inputs" / "ignored.txt"
            ignored.write_text("&GLOBAL\n&END GLOBAL\n", encoding="utf-8")
            list_path = root / "inputs" / "list.txt"
            list_path.write_text("# comment\nb.inp\n", encoding="utf-8")

            inputs = resolve_existing_input_batch_inputs(
                input_paths=[input_a],
                input_dirs=[root / "inputs"],
                input_list_paths=[list_path],
            )

            self.assertEqual(inputs, [input_a.resolve(), input_b.resolve()])

    def test_cli_prepare_only_accepts_input_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            input_dir = root / "inputs"
            self._write_input(input_dir / "a.inp")
            self._write_input(input_dir / "b.inp")

            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "run_existing_input_batch.py"),
                    "--config",
                    str(ROOT / "examples" / "winqstep.config.example.json"),
                    "--input-dir",
                    str(input_dir),
                    "--job-dir",
                    str(root / "batch"),
                    "--prepare-only",
                    "--compact",
                ],
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
            summary = json.loads(completed.stdout.decode("utf-8"))
            self.assertEqual(summary["status"], "prepared")
            self.assertEqual(summary["input_count"], 2)
            self.assertEqual(summary["prepared_count"], 2)

    def test_cli_manage_batch_item_can_skip_item(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            input_a = self._write_input(root / "inputs" / "a.inp")
            input_b = self._write_input(root / "inputs" / "b.inp")
            summary = run_existing_input_batch(
                config=self.config,
                input_paths=[input_a, input_b],
                windows_job_dir=root / "batch",
                execute=False,
            )

            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "manage_existing_input_batch.py"),
                    "--summary",
                    summary["summary_path"],
                    "--index",
                    "2",
                    "--action",
                    "skip",
                    "--compact",
                ],
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
            updated = json.loads(completed.stdout.decode("utf-8"))
            self.assertEqual(updated["items"][1]["status"], "skipped")
            self.assertEqual(updated["skipped_count"], 1)


if __name__ == "__main__":
    unittest.main()

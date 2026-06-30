import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from winqstep.history import HistoryError, list_job_history


ROOT = Path(__file__).resolve().parents[1]


class JobHistoryTests(unittest.TestCase):
    def test_lists_metadata_newest_first(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            workspace = Path(tmp_dir)
            older_dir = workspace / "older"
            newer_dir = workspace / "newer"
            older_dir.mkdir()
            newer_dir.mkdir()
            _write_metadata(
                older_dir / "old.winqstep.json",
                status="prepared",
                created_at="2026-06-29T01:00:00Z",
                completed_at=None,
                project_name="old_job",
                output_summary={"status": "not_available", "warning_count": None, "program_ended": False},
            )
            _write_metadata(
                newer_dir / "new.winqstep.json",
                status="succeeded",
                created_at="2026-06-29T01:05:00Z",
                completed_at="2026-06-29T01:06:00Z",
                project_name="new_job",
                output_summary={"status": "completed", "warning_count": 0, "program_ended": True},
            )

            history = list_job_history(workspace)

            self.assertEqual(len(history["jobs"]), 2)
            self.assertEqual(history["jobs"][0]["project_name"], "new_job")
            self.assertEqual(history["jobs"][0]["status"], "succeeded")
            self.assertEqual(history["jobs"][0]["output_status"], "completed")
            self.assertEqual(history["jobs"][0]["warning_count"], 0)
            self.assertEqual(history["jobs"][1]["project_name"], "old_job")

    def test_uses_existing_input_mode_and_input_stem(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            workspace = Path(tmp_dir)
            metadata_path = workspace / "water.winqstep.json"
            metadata_path.write_text(
                json.dumps(
                    {
                        "status": "succeeded",
                        "created_at": "2026-06-29T01:00:00Z",
                        "completed_at": "2026-06-29T01:01:00Z",
                        "returncode": 0,
                        "job": {"mode": "existing_input", "input_stem": "water"},
                        "files": {
                            "input": {"path": str(workspace / "water.inp")},
                            "output": {"path": str(workspace / "water.out")},
                            "generated": [
                                {
                                    "path": str(workspace / "water-k1-1.pdos"),
                                    "name": "water-k1-1.pdos",
                                    "type": "pdos",
                                    "size": 4,
                                },
                                {
                                    "path": str(workspace / "water-ELECTRON_DENSITY.cube"),
                                    "name": "water-ELECTRON_DENSITY.cube",
                                    "type": "electron_density_cube",
                                    "size": 4,
                                }
                            ],
                        },
                        "cp2k_output": {
                            "status": "completed",
                            "warning_count": 1,
                            "program_ended": True,
                            "total_energy_hartree": -17.219350325303314,
                            "forces": {
                                "unit": "hartree/bohr",
                                "atoms": [
                                    {"atom": 1, "x": 0.0, "y": 0.0, "z": -0.0135588799, "norm": 0.0135588799}
                                ],
                                "sum": {"x": 0.0, "y": 0.0, "z": 0.00148299452},
                                "total_atomic_force": 0.00148299452,
                            },
                        },
                    }
                ),
                encoding="utf-8",
            )

            job = list_job_history(workspace)["jobs"][0]

            self.assertEqual(job["mode"], "existing_input")
            self.assertEqual(job["project_name"], "water")
            self.assertEqual(job["warning_count"], 1)
            self.assertAlmostEqual(job["total_energy_hartree"], -17.219350325303314)
            self.assertAlmostEqual(job["total_atomic_force"], 0.00148299452)
            self.assertEqual(job["force_unit"], "hartree/bohr")
            self.assertEqual(job["generated_artifact_count"], 2)
            self.assertEqual(job["generated_artifacts"][0]["type"], "pdos")
            self.assertEqual(job["generated_artifacts"][1]["type"], "electron_density_cube")

    def test_bad_metadata_is_reported_without_stopping_scan(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            workspace = Path(tmp_dir)
            _write_metadata(
                workspace / "good.winqstep.json",
                status="prepared",
                created_at="2026-06-29T01:00:00Z",
                completed_at=None,
                project_name="good",
                output_summary={"status": "not_available", "warning_count": None, "program_ended": False},
            )
            (workspace / "bad.winqstep.json").write_text("{", encoding="utf-8")

            history = list_job_history(workspace)

            self.assertEqual(len(history["jobs"]), 1)
            self.assertEqual(len(history["errors"]), 1)
            self.assertIn("bad.winqstep.json", history["errors"][0]["metadata_path"])

    def test_parses_output_when_summary_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            workspace = Path(tmp_dir)
            output_path = workspace / "legacy.out"
            output_path.write_text(
                "The number of warnings for this run is : 2\n"
                "PROGRAM ENDED AT                 2026-06-29 03:24:28.023\n",
                encoding="utf-8",
            )
            (workspace / "legacy.winqstep.json").write_text(
                json.dumps(
                    {
                        "status": "succeeded",
                        "created_at": "2026-06-29T01:00:00Z",
                        "completed_at": "2026-06-29T01:01:00Z",
                        "returncode": 0,
                        "quickstep": {"project_name": "legacy", "run_type": "ENERGY"},
                        "files": {
                            "input": {"path": str(workspace / "legacy.inp")},
                            "output": {"path": str(output_path)},
                        },
                    }
                ),
                encoding="utf-8",
            )

            job = list_job_history(workspace)["jobs"][0]

            self.assertEqual(job["output_status"], "completed")
            self.assertEqual(job["warning_count"], 2)
            self.assertTrue(job["program_ended"])

    def test_non_recursive_scan_ignores_nested_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            workspace = Path(tmp_dir)
            nested = workspace / "nested"
            nested.mkdir()
            _write_metadata(
                nested / "nested.winqstep.json",
                status="prepared",
                created_at="2026-06-29T01:00:00Z",
                completed_at=None,
                project_name="nested",
                output_summary={"status": "not_available", "warning_count": None, "program_ended": False},
            )

            self.assertEqual(list_job_history(workspace, recursive=False)["jobs"], [])

    def test_missing_workspace_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            with self.assertRaisesRegex(HistoryError, "workspace does not exist"):
                list_job_history(Path(tmp_dir) / "missing")

    def test_cli_outputs_compact_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            workspace = Path(tmp_dir)
            _write_metadata(
                workspace / "job.winqstep.json",
                status="prepared",
                created_at="2026-06-29T01:00:00Z",
                completed_at=None,
                project_name="cli_job",
                output_summary={"status": "not_available", "warning_count": None, "program_ended": False},
            )

            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "list_job_history.py"),
                    "--workspace",
                    str(workspace),
                    "--compact",
                ],
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
            history = json.loads(completed.stdout.decode("utf-8"))
            self.assertEqual(history["jobs"][0]["project_name"], "cli_job")


def _write_metadata(
    path: Path,
    *,
    status: str,
    created_at: str,
    completed_at: str | None,
    project_name: str,
    output_summary: dict[str, object],
) -> None:
    stem = path.stem.removesuffix(".winqstep")
    path.write_text(
        json.dumps(
            {
                "status": status,
                "created_at": created_at,
                "completed_at": completed_at,
                "returncode": 0 if status == "succeeded" else None,
                "quickstep": {"project_name": project_name, "run_type": "ENERGY"},
                "files": {
                    "input": {"path": str(path.parent / f"{stem}.inp")},
                    "output": {"path": str(path.parent / f"{stem}.out")},
                    "stdout": {"path": str(path.parent / f"{stem}.stdout.log")},
                    "stderr": {"path": str(path.parent / f"{stem}.stderr.log")},
                },
                "cp2k_output": output_summary,
            }
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    unittest.main()

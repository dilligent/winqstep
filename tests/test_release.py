import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

from scripts.build_release import build_release_plan, should_exclude


ROOT = Path(__file__).resolve().parents[1]


class ReleaseBuildTests(unittest.TestCase):
    def test_release_exclusion_rules_cover_generated_and_local_files(self) -> None:
        self.assertTrue(should_exclude(Path("outputs/job/example.out")))
        self.assertTrue(should_exclude(Path("dist/winqstep.zip")))
        self.assertTrue(should_exclude(Path("build/temp.txt")))
        self.assertTrue(should_exclude(Path("cp2k-2025.2/src/main.F")))
        self.assertTrue(should_exclude(Path("codex-thread.json")))
        self.assertTrue(should_exclude(Path("examples/winqstep.config.json")))
        self.assertTrue(should_exclude(Path("examples/templates/energy_pbe.json")))
        self.assertTrue(should_exclude(Path("examples/templates/custom.local.json")))
        self.assertTrue(should_exclude(Path("winqstep/__pycache__/config.cpython-313.pyc")))
        self.assertFalse(should_exclude(Path("examples/winqstep.config.example.json")))
        self.assertFalse(should_exclude(Path("examples/templates/energy_pbe.example.json")))
        self.assertFalse(should_exclude(Path("scripts/start_gui.ps1")))
        self.assertFalse(should_exclude(Path("resources/i18n/zh-CN.json")))

    def test_release_plan_includes_runtime_files(self) -> None:
        plan = build_release_plan(ROOT)

        self.assertTrue(plan["valid"], plan["missing"])
        self.assertIn(".gitignore", plan["files"])
        self.assertIn("WinQStep.ps1", plan["files"])
        self.assertIn("WinQStep.cmd", plan["files"])
        self.assertIn("launcher/WinQStep.Launcher.cs", plan["files"])
        self.assertIn("scripts/build_launcher.py", plan["files"])
        self.assertIn("scripts/build_release.py", plan["files"])
        self.assertIn("scripts/smoke_release_install.py", plan["files"])
        self.assertIn("scripts/run_checks.py", plan["files"])
        self.assertIn("scripts/release_candidate_walkthrough.py", plan["files"])
        self.assertIn("scripts/start_gui.ps1", plan["files"])
        self.assertIn("scripts/gui/WinQStep.xaml", plan["files"])
        self.assertIn("resources/i18n/en-US.json", plan["files"])
        self.assertIn("resources/i18n/zh-CN.json", plan["files"])
        self.assertIn("examples/winqstep.config.example.json", plan["files"])
        self.assertIn("examples/templates/energy_pbe.example.json", plan["files"])
        self.assertNotIn("examples/winqstep.config.json", plan["files"])
        self.assertNotIn("examples/templates/energy_pbe.json", plan["files"])
        self.assertIn("docs/release-candidate-handoff.md", plan["files"])
        self.assertIn("docs/release-notes.md", plan["files"])
        self.assertIn("THIRD_PARTY_NOTICES.md", plan["files"])
        self.assertNotIn("outputs/gui-smoke/gui_smoke.inp", plan["files"])

    def test_release_builder_dry_run_cli_returns_json(self) -> None:
        completed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts" / "build_release.py"),
                "--dry-run",
                "--compact",
            ],
            cwd=ROOT,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
        payload = json.loads(completed.stdout.decode("utf-8"))
        self.assertEqual(payload["mode"], "release_plan")
        self.assertTrue(payload["valid"], payload["missing"])
        self.assertTrue(payload["archive_path"].endswith(".zip"))

    def test_release_builder_writes_zip_and_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "build_release.py"),
                    "--output-dir",
                    tmp_dir,
                    "--compact",
                ],
                cwd=ROOT,
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
            payload = json.loads(completed.stdout.decode("utf-8"))
            archive_path = Path(payload["archive_path"])
            manifest_path = Path(payload["manifest_path"])
            self.assertTrue(archive_path.is_file())
            self.assertTrue(manifest_path.is_file())
            self.assertEqual(len(payload["archive_sha256"]), 64)

            with zipfile.ZipFile(archive_path) as archive:
                names = archive.namelist()

            root = payload["archive_root"]
            self.assertIn(f"{root}/.gitignore", names)
            self.assertIn(f"{root}/WinQStep.ps1", names)
            self.assertIn(f"{root}/launcher/WinQStep.Launcher.cs", names)
            self.assertIn(f"{root}/scripts/build_launcher.py", names)
            self.assertIn(f"{root}/scripts/smoke_release_install.py", names)
            self.assertIn(f"{root}/scripts/run_checks.py", names)
            self.assertIn(f"{root}/scripts/release_candidate_walkthrough.py", names)
            self.assertIn(f"{root}/scripts/start_gui.ps1", names)
            self.assertIn(f"{root}/examples/winqstep.config.example.json", names)
            self.assertIn(f"{root}/examples/templates/energy_pbe.example.json", names)
            self.assertNotIn(f"{root}/examples/winqstep.config.json", names)
            self.assertNotIn(f"{root}/examples/templates/energy_pbe.json", names)
            self.assertIn(f"{root}/docs/release-candidate-handoff.md", names)
            self.assertIn(f"{root}/docs/release-notes.md", names)
            self.assertIn(f"{root}/RELEASE-MANIFEST.json", names)
            self.assertFalse(any("/outputs/" in name for name in names))
            self.assertFalse(any("/dist/" in name for name in names))
            self.assertFalse(any("/.git/" in name for name in names))

    def test_release_install_smoke_cli_builds_and_unpacks_archive(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "smoke_release_install.py"),
                    "--output-dir",
                    str(Path(tmp_dir) / "dist"),
                    "--compact",
                ],
                cwd=ROOT,
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
            payload = json.loads(completed.stdout.decode("utf-8"))
            self.assertEqual(payload["mode"], "release_install_smoke")
            self.assertTrue(payload["valid"], payload["errors"])
            self.assertTrue(Path(payload["archive_path"]).is_file())
            self.assertEqual(payload["archive"]["archive_root"], payload["build"]["archive_root"])
            self.assertGreater(payload["archive"]["file_count"], 0)
            if not payload["diagnostics"]["skipped"]:
                self.assertTrue(payload["diagnostics"]["valid"], payload["diagnostics"]["error"])


if __name__ == "__main__":
    unittest.main()

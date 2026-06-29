import json
import shutil
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class StartupDiagnosticsTests(unittest.TestCase):
    def test_python_startup_diagnostics_skip_live_probes(self) -> None:
        completed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts" / "check_startup.py"),
                "--skip-live-probes",
                "--compact",
            ],
            cwd=ROOT,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
        payload = json.loads(completed.stdout.decode("utf-8"))
        self.assertTrue(payload["valid"], payload["errors"])
        self.assertTrue(payload["checks"]["live_probes"]["skipped"])
        required = {item["path"]: item["exists"] for item in payload["checks"]["required_files"]}
        self.assertTrue(required["WinQStep.cmd"])
        self.assertTrue(required["WinQStep.ps1"])
        self.assertTrue(required["scripts/start_gui.ps1"])
        self.assertTrue(required["scripts/check_startup.py"])
        self.assertTrue(required["scripts/gui/WinQStep.GuiHost.ps1"])
        self.assertTrue(required["scripts/gui/WinQStep.xaml"])
        exclusions = {item["pattern"]: item["present"] for item in payload["checks"]["release_exclusions"]}
        self.assertTrue(exclusions["/outputs/"])
        self.assertTrue(exclusions["*.winqstep-cache.json"])
        self.assertTrue(exclusions["/cp2k-*/"])

    def test_launchers_forward_diagnostics_to_gui_script(self) -> None:
        ps1_text = (ROOT / "WinQStep.ps1").read_text(encoding="utf-8")
        cmd_text = (ROOT / "WinQStep.cmd").read_text(encoding="utf-8")

        self.assertIn("scripts\\start_gui.ps1", ps1_text)
        self.assertIn("-ExecutionPolicy", ps1_text)
        self.assertIn("-Diagnostics", ps1_text)
        self.assertIn("-SkipLiveProbes", ps1_text)
        self.assertIn("WinQStep.ps1", cmd_text)
        self.assertIn("ExecutionPolicy Bypass", cmd_text)

    @unittest.skipUnless(shutil.which("powershell") or shutil.which("pwsh"), "PowerShell is not available")
    def test_start_gui_diagnostics_skip_live_probes(self) -> None:
        powershell = shutil.which("powershell") or shutil.which("pwsh")
        completed = subprocess.run(
            [
                powershell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(ROOT / "scripts" / "start_gui.ps1"),
                "-Diagnostics",
                "-SkipLiveProbes",
            ],
            cwd=ROOT,
            capture_output=True,
            check=False,
        )

        stderr = completed.stderr.decode("utf-8", errors="replace")
        stdout = completed.stdout.decode("utf-8-sig", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr)
        payload = json.loads(stdout)
        self.assertEqual(payload["mode"], "startup_diagnostics")
        self.assertTrue(payload["checks"]["live_probes"]["skipped"])


if __name__ == "__main__":
    unittest.main()

import json
import platform
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class GuiPrototypeTests(unittest.TestCase):
    @unittest.skipUnless(platform.system() == "Windows", "WPF prototype is Windows-only")
    def test_wpf_smoke_test_loads_window(self) -> None:
        powershell = shutil.which("powershell") or shutil.which("pwsh")
        if not powershell:
            self.skipTest("PowerShell is not available")

        completed = subprocess.run(
            [
                powershell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(ROOT / "scripts" / "start_gui.ps1"),
                "-SmokeTest",
            ],
            capture_output=True,
            check=False,
        )

        stderr = completed.stderr.decode("utf-8", errors="replace")
        stdout = completed.stdout.decode("utf-8-sig", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr)
        report = json.loads(stdout)
        self.assertTrue(report["wpf_available"])
        self.assertTrue(report["xaml_loaded"])
        self.assertEqual(report["title"], "WinQStep")
        self.assertEqual(report["preview_exit_code"], 0)
        self.assertTrue(report["preview_input_exists"])


if __name__ == "__main__":
    unittest.main()

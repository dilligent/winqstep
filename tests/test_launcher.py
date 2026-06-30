import json
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class WindowsExeLauncherTests(unittest.TestCase):
    def test_launcher_source_is_thin_powershell_wrapper(self) -> None:
        text = (ROOT / "launcher" / "WinQStep.Launcher.cs").read_text(encoding="utf-8")

        self.assertIn("WinQStep.ps1", text)
        self.assertIn("powershell.exe", text)
        self.assertIn("CreateNoWindow", text)
        self.assertIn("MessageBox.Show", text)
        self.assertIn("QuoteArgument", text)
        self.assertNotIn("python.exe", text)

    def test_build_launcher_dry_run_returns_json(self) -> None:
        completed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts" / "build_launcher.py"),
                "--dry-run",
                "--compact",
            ],
            cwd=ROOT,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
        payload = json.loads(completed.stdout.decode("utf-8"))
        self.assertEqual(payload["mode"], "launcher_plan")
        self.assertTrue(payload["valid"], payload["errors"])
        self.assertTrue(payload["source"].endswith("WinQStep.Launcher.cs"))
        self.assertTrue(payload["output_path"].endswith("WinQStep.exe"))
        self.assertIn("/target:winexe", payload["command"])
        self.assertIn("/reference:System.Windows.Forms.dll", payload["command"])


if __name__ == "__main__":
    unittest.main()

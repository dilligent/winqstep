import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from winqstep.config import load_config, save_config, validate_config


ROOT = Path(__file__).resolve().parents[1]


class ConfigTests(unittest.TestCase):
    def test_save_config_uses_stable_order_and_utf8(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            config_path = Path(tmp_dir) / "winqstep.config.json"

            saved = save_config(
                config_path,
                {
                    "timeout": "20",
                    "wsl_shell_prelude": "conda deactivate >/dev/null 2>&1 || true",
                    "default_windows_workspace": "D:\\Library\\自制品\\winqstep\\outputs",
                    "cp2k_data_dir": "/home/teng/cp2k/data",
                    "mpirun_command": "",
                    "cp2k_command": "/home/teng/cp2k/exe/local/cp2k.ssmp",
                    "distro": "Ubuntu",
                    "ui_language": "zh-CN",
                },
            )

            raw = config_path.read_bytes()
            self.assertFalse(raw.startswith(b"\xef\xbb\xbf"))
            self.assertIn("自制品", config_path.read_text(encoding="utf-8"))
            self.assertEqual(list(saved), [
                "distro",
                "cp2k_command",
                "mpirun_command",
                "cp2k_data_dir",
                "default_windows_workspace",
                "wsl_shell_prelude",
                "ui_language",
                "timeout",
            ])
            self.assertEqual(load_config(config_path)["timeout"], 20)
            self.assertEqual(load_config(config_path)["ui_language"], "zh-CN")

    def test_validate_requires_execution_fields_when_requested(self) -> None:
        validation = validate_config({"distro": "Ubuntu"}, require_execution=True)

        self.assertFalse(validation["valid"])
        self.assertIn("cp2k_command is required", "\n".join(validation["errors"]))
        self.assertIn("cp2k_data_dir is required", "\n".join(validation["errors"]))

    def test_validate_rejects_windows_cp2k_paths(self) -> None:
        validation = validate_config(
            {
                "distro": "Ubuntu",
                "cp2k_command": "D:\\cp2k\\cp2k.ssmp",
                "cp2k_data_dir": "D:\\cp2k\\data",
            },
            require_execution=True,
        )

        self.assertFalse(validation["valid"])
        self.assertIn("not a Windows path", "\n".join(validation["errors"]))

    def test_validate_rejects_unknown_ui_language(self) -> None:
        validation = validate_config({"ui_language": "fr-FR"})

        self.assertFalse(validation["valid"])
        self.assertIn("ui_language must be one of", "\n".join(validation["errors"]))

    def test_cli_writes_config_from_fields_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            config_path = Path(tmp_dir) / "winqstep.config.json"
            fields = {
                "distro": "Ubuntu",
                "cp2k_command": "/home/teng/cp2k/exe/local/cp2k.ssmp",
                "mpirun_command": "",
                "cp2k_data_dir": "/home/teng/cp2k/data",
                "default_windows_workspace": "D:\\Library\\自制品\\winqstep\\outputs",
                "wsl_shell_prelude": "conda deactivate >/dev/null 2>&1 || true",
                "ui_language": "en-US",
                "timeout": "20",
            }

            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "manage_config.py"),
                    "--config",
                    str(config_path),
                    "--write",
                    "--require-execution",
                    "--fields-json",
                    json.dumps(fields, ensure_ascii=False),
                    "--compact",
                ],
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
            payload = json.loads(completed.stdout.decode("utf-8"))
            self.assertTrue(payload["written"])
            self.assertTrue(payload["validation"]["valid"])
            self.assertEqual(load_config(config_path)["default_windows_workspace"], fields["default_windows_workspace"])
            self.assertEqual(load_config(config_path)["ui_language"], "en-US")

    def test_cli_reports_validation_errors_as_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            config_path = Path(tmp_dir) / "winqstep.config.json"

            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "manage_config.py"),
                    "--config",
                    str(config_path),
                    "--write",
                    "--require-execution",
                    "--fields-json",
                    json.dumps({"distro": "Ubuntu"}),
                    "--compact",
                ],
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 1)
            payload = json.loads(completed.stdout.decode("utf-8"))
            self.assertFalse(payload["validation"]["valid"])


if __name__ == "__main__":
    unittest.main()

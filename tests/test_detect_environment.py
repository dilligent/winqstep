import argparse
import json
import tempfile
import unittest
from pathlib import Path

from scripts.detect_environment import (
    apply_config,
    decode_output,
    first_line,
    load_config,
    parse_wsl_list,
)


class DetectEnvironmentTests(unittest.TestCase):
    def test_parse_wsl_list_with_default_marker(self) -> None:
        output = "  NAME      STATE           VERSION\n* Ubuntu    Stopped         2\n"

        self.assertEqual(
            parse_wsl_list(output),
            [
                {
                    "name": "Ubuntu",
                    "state": "Stopped",
                    "version": "2",
                    "default": True,
                }
            ],
        )

    def test_parse_wsl_list_with_utf16_output(self) -> None:
        output = "  NAME      STATE           VERSION\r\n* Ubuntu    Running         2\r\n"
        decoded = decode_output(output.encode("utf-16-le"))

        self.assertEqual(parse_wsl_list(decoded)[0]["name"], "Ubuntu")
        self.assertTrue(parse_wsl_list(decoded)[0]["default"])

    def test_first_line_skips_empty_lines(self) -> None:
        self.assertEqual(first_line("\n\n/usr/bin/cp2k.psmp\n"), "/usr/bin/cp2k.psmp")

    def test_load_config_reads_supported_keys(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            config_path = Path(tmp_dir) / "winqstep.config.json"
            config_path.write_text(
                json.dumps(
                    {
                        "distro": "Ubuntu",
                        "cp2k_command": "cp2k.ssmp",
                        "cp2k_data_dir": "/opt/cp2k/data",
                        "default_windows_workspace": "D:\\Jobs",
                    }
                ),
                encoding="utf-8",
            )

            self.assertEqual(load_config(str(config_path))["cp2k_command"], "cp2k.ssmp")

    def test_load_config_rejects_unknown_keys(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            config_path = Path(tmp_dir) / "winqstep.config.json"
            config_path.write_text(json.dumps({"unexpected": True}), encoding="utf-8")

            with self.assertRaises(ValueError):
                load_config(str(config_path))

    def test_apply_config_preserves_cli_overrides(self) -> None:
        args = argparse.Namespace(
            config="example.json",
            distro=None,
            cp2k_command="custom-cp2k",
            mpirun_command=None,
            cp2k_data_dir=None,
            default_windows_workspace=None,
            timeout=None,
        )
        merged = apply_config(
            args,
            {
                "distro": "Ubuntu",
                "cp2k_command": "cp2k.ssmp",
                "cp2k_data_dir": "/opt/cp2k/data",
                "timeout": 7,
            },
        )

        self.assertEqual(merged.distro, "Ubuntu")
        self.assertEqual(merged.cp2k_command, "custom-cp2k")
        self.assertEqual(merged.cp2k_data_dir, "/opt/cp2k/data")
        self.assertEqual(merged.timeout, 7)


if __name__ == "__main__":
    unittest.main()

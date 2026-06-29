import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from winqstep.cp2k_data import (
    Cp2kDataError,
    build_wsl_data_dump_command,
    inspect_cp2k_data_texts,
    inspect_windows_cp2k_data_dir,
    inspect_wsl_cp2k_data_dir,
    parse_wsl_data_dump,
)


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DATA = ROOT / "tests" / "fixtures" / "cp2k_data"


class Cp2kDataTests(unittest.TestCase):
    def test_inspects_windows_fixture_data_dir(self) -> None:
        inspection = inspect_windows_cp2k_data_dir(FIXTURE_DATA)

        self.assertEqual(inspection["counts"]["files"], 2)
        self.assertIn("DZVP-MOLOPT-SR-GTH", inspection["basis_sets_by_element"]["H"])
        self.assertIn("TZVP-MOLOPT-GTH", inspection["basis_sets_by_element"]["O"])
        self.assertEqual(inspection["potentials_by_element"]["Si"], ["GTH-PBE-q4"])

    def test_writes_cache_when_requested(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            cache_path = Path(tmp_dir) / "cp2k-data-cache.json"

            inspect_windows_cp2k_data_dir(FIXTURE_DATA, cache_path=cache_path)

            cached = json.loads(cache_path.read_text(encoding="utf-8"))
            self.assertEqual(cached["counts"]["elements"], 3)

    def test_builds_read_only_wsl_dump_command(self) -> None:
        command = build_wsl_data_dump_command(
            cp2k_data_dir="/home/teng/cp2k/data",
            wsl_shell_prelude="conda deactivate >/dev/null 2>&1 || true",
            limit_files=7,
        )

        self.assertIn("conda deactivate", command)
        self.assertIn("test -d /home/teng/cp2k/data", command)
        self.assertIn("find /home/teng/cp2k/data -maxdepth 1 -type f", command)
        self.assertIn("__WINQSTEP_CP2K_DATA_FILE__", command)
        self.assertIn("-exec cat {} \\;", command)
        self.assertNotIn("rm ", command)

    def test_parses_wsl_dump(self) -> None:
        dump = (
            "__WINQSTEP_CP2K_DATA_FILE__BASIS_MOLOPT\n"
            "H DZVP-MOLOPT-SR-GTH\n"
            "__WINQSTEP_CP2K_DATA_END__BASIS_MOLOPT\n"
        )

        self.assertEqual(parse_wsl_data_dump(dump), [{"name": "BASIS_MOLOPT", "text": "H DZVP-MOLOPT-SR-GTH"}])

    def test_potential_parser_ignores_internal_channel_lines(self) -> None:
        inspection = inspect_cp2k_data_texts(
            [
                {
                    "name": "GTH_POTENTIALS",
                    "text": "S GTH-PBE-q6\nS nelec 6\nP ul\nD 0.25\n",
                }
            ]
        )

        self.assertEqual(inspection["potentials_by_element"], {"S": ["GTH-PBE-q6"]})

    def test_wsl_inspection_uses_executor(self) -> None:
        def fake_executor(argv: list[str]) -> SimpleNamespace:
            self.assertEqual(argv[:3], ["wsl.exe", "-d", "Ubuntu"])
            stdout = (
                "__WINQSTEP_CP2K_DATA_FILE__GTH_POTENTIALS\n"
                "O GTH-PBE-q6\n"
                "__WINQSTEP_CP2K_DATA_END__GTH_POTENTIALS\n"
            )
            return SimpleNamespace(returncode=0, stdout=stdout.encode("utf-8"), stderr=b"")

        inspection = inspect_wsl_cp2k_data_dir(
            distro="Ubuntu",
            cp2k_data_dir="/home/teng/cp2k/data",
            executor=fake_executor,
        )

        self.assertEqual(inspection["potentials_by_element"]["O"], ["GTH-PBE-q6"])

    def test_wsl_inspection_decodes_utf16_output(self) -> None:
        def fake_executor(argv: list[str]) -> SimpleNamespace:
            stdout = (
                "__WINQSTEP_CP2K_DATA_FILE__BASIS_MOLOPT\n"
                "H DZVP-MOLOPT-SR-GTH\n"
                "__WINQSTEP_CP2K_DATA_END__BASIS_MOLOPT\n"
            )
            return SimpleNamespace(returncode=0, stdout=stdout.encode("utf-16-le"), stderr=b"")

        inspection = inspect_wsl_cp2k_data_dir(
            distro="Ubuntu",
            cp2k_data_dir="/home/teng/cp2k/data",
            executor=fake_executor,
        )

        self.assertEqual(inspection["basis_sets_by_element"]["H"], ["DZVP-MOLOPT-SR-GTH"])

    def test_wsl_inspection_reports_timeout(self) -> None:
        def fake_executor(argv: list[str]) -> SimpleNamespace:
            raise subprocess.TimeoutExpired(argv, 3)

        with self.assertRaisesRegex(Cp2kDataError, "timed out"):
            inspect_wsl_cp2k_data_dir(
                distro="Ubuntu",
                cp2k_data_dir="/home/teng/cp2k/data",
                timeout=3,
                executor=fake_executor,
            )

    def test_cli_inspects_windows_data_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            cache_path = Path(tmp_dir) / "cache.json"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "inspect_cp2k_data.py"),
                    "--windows-data-dir",
                    str(FIXTURE_DATA),
                    "--cache",
                    str(cache_path),
                    "--compact",
                ],
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
            payload = json.loads(completed.stdout.decode("utf-8"))
            self.assertEqual(payload["counts"]["elements"], 3)
            self.assertTrue(cache_path.exists())


if __name__ == "__main__":
    unittest.main()

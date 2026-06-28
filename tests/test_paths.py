import unittest

from winqstep.paths import PathConversionError, shell_quote, windows_path_to_wsl


class PathTests(unittest.TestCase):
    def test_windows_path_to_wsl_converts_drive_path(self) -> None:
        self.assertEqual(
            windows_path_to_wsl(r"D:\Library\自制品\winqstep\job.inp"),
            "/mnt/d/Library/自制品/winqstep/job.inp",
        )

    def test_windows_path_to_wsl_accepts_forward_slashes(self) -> None:
        self.assertEqual(
            windows_path_to_wsl("C:/Users/Teng/My Jobs/input.inp"),
            "/mnt/c/Users/Teng/My Jobs/input.inp",
        )

    def test_windows_path_to_wsl_rejects_relative_paths(self) -> None:
        with self.assertRaises(PathConversionError):
            windows_path_to_wsl(r"jobs\input.inp")

    def test_shell_quote_handles_spaces(self) -> None:
        self.assertEqual(shell_quote("/mnt/d/My Jobs/input.inp"), "'/mnt/d/My Jobs/input.inp'")


if __name__ == "__main__":
    unittest.main()

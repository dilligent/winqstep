import unittest

from winqstep.jobs import build_cp2k_job_dry_run


class JobDryRunTests(unittest.TestCase):
    def test_builds_direct_cp2k_wsl_command(self) -> None:
        dry_run = build_cp2k_job_dry_run(
            distro="Ubuntu",
            cp2k_command="/home/teng/cp2k/exe/local/cp2k.ssmp",
            windows_input_path=r"D:\Library\自制品\winqstep\jobs\water.inp",
            cp2k_data_dir="/home/teng/cp2k/data",
            wsl_shell_prelude="conda deactivate >/dev/null 2>&1 || true",
        )

        self.assertEqual(dry_run["wsl"]["input_path"], "/mnt/d/Library/自制品/winqstep/jobs/water.inp")
        self.assertEqual(dry_run["command"]["argv"][:5], ["wsl.exe", "-d", "Ubuntu", "--", "bash"])
        shell = dry_run["wsl"]["shell_command"]
        self.assertIn("conda deactivate", shell)
        self.assertIn("cd '/mnt/d/Library/自制品/winqstep/jobs'", shell)
        self.assertIn("export CP2K_DATA_DIR=/home/teng/cp2k/data", shell)
        self.assertIn("/home/teng/cp2k/exe/local/cp2k.ssmp -i", shell)
        self.assertIn("-o water.out > water.stdout.log 2> water.stderr.log", shell)

    def test_builds_mpi_command_when_requested(self) -> None:
        dry_run = build_cp2k_job_dry_run(
            distro="Ubuntu",
            cp2k_command="/opt/cp2k/bin/cp2k.psmp",
            windows_input_path=r"D:\My Jobs\calc.inp",
            mpirun_command="/usr/bin/mpirun",
            mpi_ranks=4,
        )

        shell = dry_run["wsl"]["shell_command"]
        self.assertIn("cd '/mnt/d/My Jobs'", shell)
        self.assertIn("/usr/bin/mpirun -np 4 /opt/cp2k/bin/cp2k.psmp", shell)

    def test_rejects_invalid_mpi_ranks(self) -> None:
        with self.assertRaises(ValueError):
            build_cp2k_job_dry_run(
                distro="Ubuntu",
                cp2k_command="cp2k.ssmp",
                windows_input_path=r"D:\Jobs\calc.inp",
                mpi_ranks=0,
            )


if __name__ == "__main__":
    unittest.main()

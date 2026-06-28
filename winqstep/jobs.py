"""CP2K job dry-run command construction."""

from __future__ import annotations

from pathlib import PureWindowsPath
from typing import Any

from .paths import shell_quote, windows_path_to_wsl


def _nonempty(value: str | None) -> str | None:
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None


def _default_job_dir(windows_input_path: str) -> str:
    path = PureWindowsPath(windows_input_path)
    parent = str(path.parent)
    if not parent or parent == ".":
        raise ValueError("windows_input_path must include a parent directory")
    return parent


def build_cp2k_shell_command(
    *,
    cp2k_command: str,
    wsl_input_path: str,
    wsl_job_dir: str,
    input_stem: str,
    cp2k_data_dir: str | None = None,
    wsl_shell_prelude: str | None = None,
    mpirun_command: str | None = None,
    mpi_ranks: int | None = None,
) -> str:
    """Build the WSL-side shell command for a CP2K job."""
    output_filename = input_stem + ".out"
    stdout_filename = input_stem + ".stdout.log"
    stderr_filename = input_stem + ".stderr.log"

    lines: list[str] = []
    prelude = _nonempty(wsl_shell_prelude)
    if prelude:
        lines.append(prelude)
    lines.extend(["set -e", f"cd {shell_quote(wsl_job_dir)}"])

    data_dir = _nonempty(cp2k_data_dir)
    if data_dir:
        lines.append(f"export CP2K_DATA_DIR={shell_quote(data_dir)}")

    cp2k_args = [
        shell_quote(cp2k_command),
        "-i",
        shell_quote(wsl_input_path),
        "-o",
        shell_quote(output_filename),
    ]

    launcher = _nonempty(mpirun_command)
    if launcher and mpi_ranks:
        cp2k_args = [shell_quote(launcher), "-np", str(mpi_ranks), *cp2k_args]
    elif launcher:
        cp2k_args = [shell_quote(launcher), *cp2k_args]

    lines.append(
        " ".join(cp2k_args)
        + f" > {shell_quote(stdout_filename)} 2> {shell_quote(stderr_filename)}"
    )
    return "\n".join(lines)


def build_wsl_argv(distro: str | None, shell_command: str) -> list[str]:
    args = ["wsl.exe"]
    if _nonempty(distro):
        args.extend(["-d", str(distro)])
    args.extend(["--", "bash", "-lc", shell_command])
    return args


def build_cp2k_job_dry_run(
    *,
    distro: str | None,
    cp2k_command: str,
    windows_input_path: str,
    windows_job_dir: str | None = None,
    cp2k_data_dir: str | None = None,
    wsl_shell_prelude: str | None = None,
    mpirun_command: str | None = None,
    mpi_ranks: int | None = None,
) -> dict[str, Any]:
    """Return metadata for a CP2K job without starting CP2K."""
    input_path = PureWindowsPath(windows_input_path)
    if not input_path.name:
        raise ValueError("windows_input_path must name an input file")
    if mpi_ranks is not None and mpi_ranks < 1:
        raise ValueError("mpi_ranks must be at least 1")

    job_dir = windows_job_dir or _default_job_dir(windows_input_path)
    wsl_input_path = windows_path_to_wsl(windows_input_path)
    wsl_job_dir = windows_path_to_wsl(job_dir)
    input_stem = input_path.stem

    shell_command = build_cp2k_shell_command(
        cp2k_command=cp2k_command,
        wsl_input_path=wsl_input_path,
        wsl_job_dir=wsl_job_dir,
        input_stem=input_stem,
        cp2k_data_dir=cp2k_data_dir,
        wsl_shell_prelude=wsl_shell_prelude,
        mpirun_command=mpirun_command,
        mpi_ranks=mpi_ranks,
    )

    return {
        "windows": {
            "input_path": str(input_path),
            "job_dir": str(PureWindowsPath(job_dir)),
            "output_path": str(PureWindowsPath(job_dir) / (input_stem + ".out")),
            "stdout_path": str(PureWindowsPath(job_dir) / (input_stem + ".stdout.log")),
            "stderr_path": str(PureWindowsPath(job_dir) / (input_stem + ".stderr.log")),
            "metadata_path": str(PureWindowsPath(job_dir) / (input_stem + ".winqstep.json")),
        },
        "wsl": {
            "distro": distro,
            "input_path": wsl_input_path,
            "job_dir": wsl_job_dir,
            "cp2k_command": cp2k_command,
            "cp2k_data_dir": cp2k_data_dir,
            "shell_command": shell_command,
        },
        "command": {
            "argv": build_wsl_argv(distro, shell_command),
        },
    }

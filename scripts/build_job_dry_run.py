#!/usr/bin/env python3
"""Build a dry-run WSL command for a future CP2K job."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from winqstep.config import load_config
from winqstep.jobs import build_cp2k_job_dry_run


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Build a CP2K job dry-run command.")
    parser.add_argument("--config", required=True, help="Path to a WinQStep JSON config file.")
    parser.add_argument("--input", required=True, help="Windows path to the CP2K input file.")
    parser.add_argument("--job-dir", help="Windows job folder. Defaults to the input parent.")
    parser.add_argument("--mpi-ranks", type=int, help="MPI ranks for an MPI-launched job.")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    try:
        config = load_config(args.config)
        dry_run = build_cp2k_job_dry_run(
            distro=config.get("distro"),
            cp2k_command=str(config["cp2k_command"]),
            windows_input_path=args.input,
            windows_job_dir=args.job_dir,
            cp2k_data_dir=config.get("cp2k_data_dir"),
            wsl_shell_prelude=config.get("wsl_shell_prelude"),
            mpirun_command=config.get("mpirun_command"),
            mpi_ranks=args.mpi_ranks,
        )
    except (KeyError, OSError, TypeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    indent = None if args.compact else 2
    print(json.dumps(dry_run, indent=indent, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Run an existing CP2K input file through WSL/CP2K."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from winqstep.runner import RunnerError, load_json_file, run_existing_input_job


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Run an existing CP2K input file.")
    parser.add_argument("--config", required=True, help="Path to a WinQStep config JSON file.")
    parser.add_argument("--input", required=True, help="Windows path to an existing CP2K input file.")
    parser.add_argument("--job-dir", help="Windows job folder. Defaults to the input file folder.")
    parser.add_argument("--mpi-ranks", type=int, help="MPI ranks for an MPI-launched job.")
    parser.add_argument("--prepare-only", action="store_true", help="Write metadata without running CP2K.")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    try:
        metadata = run_existing_input_job(
            config=load_json_file(args.config),
            windows_input_path=args.input,
            windows_job_dir=args.job_dir,
            mpi_ranks=args.mpi_ranks,
            execute=not args.prepare_only,
        )
    except (OSError, RunnerError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    indent = None if args.compact else 2
    print(json.dumps(metadata, ensure_ascii=False, indent=indent))
    return 0 if metadata["status"] in {"prepared", "succeeded"} else 1


if __name__ == "__main__":
    raise SystemExit(main())

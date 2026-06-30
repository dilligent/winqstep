#!/usr/bin/env python3
"""Run multiple existing CP2K input files serially."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from winqstep.batch import resolve_existing_input_batch_inputs, run_existing_input_batch
from winqstep.runner import RunnerError, load_json_file


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Run existing CP2K input files as a serial batch.")
    parser.add_argument("--config", required=True, help="Path to a WinQStep config JSON file.")
    parser.add_argument("--input", action="append", default=[], help="Windows path to an existing CP2K input file.")
    parser.add_argument("--input-dir", action="append", default=[], help="Directory to scan for CP2K input files.")
    parser.add_argument("--input-list", action="append", default=[], help="UTF-8 text file with one input path per line.")
    parser.add_argument("--glob", default="*.inp", help="Glob used with --input-dir. Defaults to *.inp.")
    parser.add_argument("--job-dir", required=True, help="Batch job folder.")
    parser.add_argument(
        "--job-layout",
        choices=("subdirs", "input-dirs"),
        default="subdirs",
        help="Use per-input subdirectories under --job-dir, or each input's own folder.",
    )
    parser.add_argument("--mpi-ranks", type=int, help="MPI ranks for MPI-launched jobs.")
    parser.add_argument("--prepare-only", action="store_true", help="Write metadata without running CP2K.")
    parser.add_argument("--resume", action="store_true", help="Resume pending items from an existing batch summary.")
    parser.add_argument("--stop-on-failure", action="store_true", help="Stop after the first failed item.")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    try:
        inputs = []
        if not args.resume:
            inputs = resolve_existing_input_batch_inputs(
                input_paths=args.input,
                input_dirs=args.input_dir,
                input_list_paths=args.input_list,
                glob_pattern=args.glob,
            )
        summary = run_existing_input_batch(
            config=load_json_file(args.config),
            input_paths=inputs,
            windows_job_dir=args.job_dir,
            mpi_ranks=args.mpi_ranks,
            execute=not args.prepare_only,
            stop_on_failure=args.stop_on_failure,
            job_layout=args.job_layout,
            resume=args.resume,
        )
    except (OSError, RunnerError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    indent = None if args.compact else 2
    print(json.dumps(summary, ensure_ascii=False, indent=indent))
    return 0 if summary["status"] in {"prepared", "succeeded", "completed_with_skips"} else 1


if __name__ == "__main__":
    raise SystemExit(main())

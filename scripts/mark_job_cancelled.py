#!/usr/bin/env python3
"""Mark a WinQStep job metadata file as cancelled."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from winqstep.runner import RunnerError, mark_job_cancelled


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Mark a WinQStep job as cancelled.")
    parser.add_argument("--metadata", required=True, help="Path to a .winqstep.json metadata file.")
    parser.add_argument("--returncode", type=int, help="Wrapper process return code.")
    parser.add_argument("--stdout-file", help="Path to the GUI wrapper stdout file.")
    parser.add_argument("--stderr-file", help="Path to the GUI wrapper stderr file.")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    try:
        metadata = mark_job_cancelled(
            args.metadata,
            returncode=args.returncode,
            wrapper_stdout=_read_optional_text(args.stdout_file),
            wrapper_stderr=_read_optional_text(args.stderr_file),
        )
    except (OSError, RunnerError, ValueError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    indent = None if args.compact else 2
    print(json.dumps(metadata, ensure_ascii=False, indent=indent))
    return 0


def _read_optional_text(path: str | None) -> str:
    if not path:
        return ""
    file_path = Path(path)
    if not file_path.is_file():
        return ""
    return file_path.read_text(encoding="utf-8", errors="replace").strip()


if __name__ == "__main__":
    raise SystemExit(main())

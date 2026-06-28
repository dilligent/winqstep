#!/usr/bin/env python3
"""List WinQStep job metadata files in a workspace."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from winqstep.history import HistoryError, list_job_history


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="List WinQStep job history metadata.")
    parser.add_argument("--workspace", required=True, help="Workspace folder to scan.")
    parser.add_argument("--no-recursive", action="store_true", help="Only scan the workspace folder itself.")
    parser.add_argument("--limit", type=int, help="Maximum number of jobs to emit.")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    try:
        history = list_job_history(
            args.workspace,
            recursive=not args.no_recursive,
            limit=args.limit,
        )
    except (OSError, HistoryError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    indent = None if args.compact else 2
    print(json.dumps(history, ensure_ascii=False, indent=indent))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

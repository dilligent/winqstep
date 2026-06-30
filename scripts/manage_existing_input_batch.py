#!/usr/bin/env python3
"""Manage one item in an existing-input batch queue."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from winqstep.batch import update_existing_input_batch_item
from winqstep.runner import RunnerError


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Manage a WinQStep existing-input batch item.")
    parser.add_argument("--summary", required=True, help="Path to batch.winqstep-batch.json.")
    parser.add_argument("--index", required=True, type=int, help="1-based batch item index.")
    parser.add_argument("--action", required=True, choices=("skip", "rerun", "cancel"))
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    try:
        summary = update_existing_input_batch_item(
            args.summary,
            index=args.index,
            action=args.action,
        )
    except (OSError, RunnerError, ValueError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    indent = None if args.compact else 2
    print(json.dumps(summary, ensure_ascii=False, indent=indent))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

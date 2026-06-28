#!/usr/bin/env python3
"""Render a conservative CP2K QuickStep input from JSON."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from winqstep.quickstep import QuickStepInputError, quickstep_input_from_dict, render_quickstep_input


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Render a CP2K QuickStep input file.")
    parser.add_argument("--input-json", required=True, help="Path to a QuickStep model JSON file.")
    parser.add_argument("--output", help="Optional output .inp path. Defaults to stdout.")
    args = parser.parse_args()

    try:
        with Path(args.input_json).open("r", encoding="utf-8") as handle:
            data = json.load(handle)
        model = quickstep_input_from_dict(data)
        rendered = render_quickstep_input(model)
        if args.output:
            Path(args.output).write_text(rendered, encoding="utf-8")
        else:
            print(rendered, end="")
    except (OSError, json.JSONDecodeError, QuickStepInputError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

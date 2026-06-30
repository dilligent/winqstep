#!/usr/bin/env python3
"""Import a structure file into WinQStep's normalized JSON shape."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from winqstep.structure_preview import build_structure_preview
from winqstep.structures import StructureImportError, dumps_structure, import_structure


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Import CIF, POSCAR, or XYZ as structure JSON.")
    parser.add_argument("--input", required=True, help="Path to a structure file.")
    parser.add_argument("--format", help="Optional explicit format: cif, poscar, or xyz.")
    parser.add_argument("--include-preview", action="store_true", help="Include a display-only 3D preview model.")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    try:
        imported = import_structure(args.input, args.format)
    except (OSError, StructureImportError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.include_preview:
        payload = {
            "mode": "structure_import",
            "structure": imported,
            "preview": build_structure_preview(imported),
        }
        print(dumps_structure(payload, compact=args.compact))
    else:
        print(dumps_structure(imported, compact=args.compact))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

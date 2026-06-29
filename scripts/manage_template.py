#!/usr/bin/env python3
"""Load, validate, and save WinQStep QuickStep workflow templates."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from winqstep.template import (
    TemplateError,
    kinds_to_text,
    load_template,
    merge_template_fields,
    save_template,
    validate_template,
)


FIELD_ARGS = {
    "project_name": "project_name",
    "run_type": "run_type",
    "basis_set_file_name": "basis_set_file_name",
    "potential_file_name": "potential_file_name",
    "xc_functional": "xc_functional",
    "charge": "charge",
    "multiplicity": "multiplicity",
    "cutoff": "cutoff",
    "rel_cutoff": "rel_cutoff",
    "eps_scf": "eps_scf",
    "max_scf": "max_scf",
    "scf_method": "scf_method",
    "added_mos": "added_mos",
    "ot_minimizer": "ot_minimizer",
    "ot_preconditioner": "ot_preconditioner",
    "diagonalization_algorithm": "diagonalization_algorithm",
    "mixing_enabled": "mixing_enabled",
    "mixing_method": "mixing_method",
    "mixing_alpha": "mixing_alpha",
    "mixing_beta": "mixing_beta",
    "smearing_enabled": "smearing_enabled",
    "smearing_method": "smearing_method",
    "electronic_temperature": "electronic_temperature",
    "optimizer": "optimizer",
    "geo_opt_max_iter": "geo_opt_max_iter",
    "fallback_cell_periodic": "fallback_cell_periodic",
    "fallback_cell_a": "fallback_cell_a",
    "fallback_cell_b": "fallback_cell_b",
    "fallback_cell_c": "fallback_cell_c",
    "center_atoms": "center_atoms",
}


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Manage a WinQStep QuickStep workflow template.")
    parser.add_argument("--template", required=True, help="Path to a workflow template JSON file.")
    parser.add_argument("--write", action="store_true", help="Write merged fields back to the template file.")
    parser.add_argument("--fields-json", help="JSON object with editable template fields to merge.")
    parser.add_argument("--project-name")
    parser.add_argument("--run-type")
    parser.add_argument("--basis-set-file-name")
    parser.add_argument("--potential-file-name")
    parser.add_argument("--xc-functional")
    parser.add_argument("--charge")
    parser.add_argument("--multiplicity")
    parser.add_argument("--cutoff")
    parser.add_argument("--rel-cutoff")
    parser.add_argument("--eps-scf")
    parser.add_argument("--max-scf")
    parser.add_argument("--scf-method")
    parser.add_argument("--added-mos")
    parser.add_argument("--ot-minimizer")
    parser.add_argument("--ot-preconditioner")
    parser.add_argument("--diagonalization-algorithm")
    parser.add_argument("--mixing-enabled")
    parser.add_argument("--mixing-method")
    parser.add_argument("--mixing-alpha")
    parser.add_argument("--mixing-beta")
    parser.add_argument("--smearing-enabled")
    parser.add_argument("--smearing-method")
    parser.add_argument("--electronic-temperature")
    parser.add_argument("--optimizer")
    parser.add_argument("--geo-opt-max-iter")
    parser.add_argument("--fallback-cell-periodic")
    parser.add_argument("--fallback-cell-a")
    parser.add_argument("--fallback-cell-b")
    parser.add_argument("--fallback-cell-c")
    parser.add_argument("--center-atoms")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    template_path = Path(args.template)
    try:
        template = load_template(template_path) if template_path.exists() else {}
        if not template_path.exists() and not args.write:
            raise TemplateError(f"template file does not exist: {template_path}")
        template = merge_template_fields(template, _field_updates(args))
        validation = validate_template(template)
        written = False
        if args.write:
            if not validation["valid"]:
                return _emit(args, template_path, validation, written=False, exit_code=1)
            template = save_template(template_path, validation["template"])
            validation = validate_template(template)
            written = True
    except (OSError, TemplateError, json.JSONDecodeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    return _emit(args, template_path, validation, written=written, exit_code=0 if validation["valid"] else 1)


def _field_updates(args: argparse.Namespace) -> dict[str, object]:
    updates: dict[str, object] = {}
    if args.fields_json:
        fields = json.loads(args.fields_json)
        if not isinstance(fields, dict):
            raise TemplateError("--fields-json must contain a JSON object")
        updates.update(fields)

    for arg_name, key in FIELD_ARGS.items():
        value = getattr(args, arg_name)
        if value is not None:
            updates[key] = value
    return updates


def _emit(
    args: argparse.Namespace,
    template_path: Path,
    validation: dict[str, object],
    *,
    written: bool,
    exit_code: int,
) -> int:
    template = validation["template"]
    kinds_text = ""
    if isinstance(template, dict) and isinstance(template.get("kinds"), list):
        kinds_text = kinds_to_text(template["kinds"])
    payload = {
        "template_path": str(template_path.resolve()),
        "written": written,
        "template": template,
        "kinds_text": kinds_text,
        "validation": {
            "valid": validation["valid"],
            "errors": validation["errors"],
            "warnings": validation["warnings"],
        },
    }
    indent = None if args.compact else 2
    print(json.dumps(payload, ensure_ascii=False, indent=indent))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())

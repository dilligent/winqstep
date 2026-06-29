#!/usr/bin/env python3
"""Load, validate, and save WinQStep config files."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from winqstep.config import ConfigError, load_config, save_config, validate_config


FIELD_ARGS = {
    "distro": "distro",
    "cp2k_command": "cp2k_command",
    "mpirun_command": "mpirun_command",
    "cp2k_data_dir": "cp2k_data_dir",
    "default_windows_workspace": "default_windows_workspace",
    "wsl_shell_prelude": "wsl_shell_prelude",
    "ui_language": "ui_language",
    "timeout": "timeout",
}


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Manage a WinQStep JSON config file.")
    parser.add_argument("--config", required=True, help="Path to a WinQStep config JSON file.")
    parser.add_argument("--write", action="store_true", help="Write merged fields back to the config file.")
    parser.add_argument("--require-execution", action="store_true", help="Require CP2K execution fields.")
    parser.add_argument("--fields-json", help="JSON object with config fields to merge.")
    parser.add_argument("--distro")
    parser.add_argument("--cp2k-command")
    parser.add_argument("--mpirun-command")
    parser.add_argument("--cp2k-data-dir")
    parser.add_argument("--default-windows-workspace")
    parser.add_argument("--wsl-shell-prelude")
    parser.add_argument("--ui-language")
    parser.add_argument("--timeout")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    config_path = Path(args.config)
    try:
        config = load_config(config_path) if config_path.exists() else {}
        if not config_path.exists() and not args.write:
            raise ConfigError(f"config file does not exist: {config_path}")
        config.update(_field_updates(args))
        validation = validate_config(config, require_execution=args.require_execution)
        written = False
        if args.write:
            if not validation["valid"]:
                return _emit(args, config_path, validation, written=False, exit_code=1)
            config = save_config(config_path, validation["config"])
            validation = validate_config(config, require_execution=args.require_execution)
            written = True
    except (OSError, ConfigError, json.JSONDecodeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    return _emit(args, config_path, validation, written=written, exit_code=0 if validation["valid"] else 1)


def _field_updates(args: argparse.Namespace) -> dict[str, object]:
    updates: dict[str, object] = {}
    if args.fields_json:
        fields = json.loads(args.fields_json)
        if not isinstance(fields, dict):
            raise ConfigError("--fields-json must contain a JSON object")
        updates.update(fields)

    for arg_name, key in FIELD_ARGS.items():
        value = getattr(args, arg_name)
        if value is not None:
            updates[key] = value
    return updates


def _emit(
    args: argparse.Namespace,
    config_path: Path,
    validation: dict[str, object],
    *,
    written: bool,
    exit_code: int,
) -> int:
    payload = {
        "config_path": str(config_path.resolve()),
        "written": written,
        "config": validation["config"],
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

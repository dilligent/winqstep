#!/usr/bin/env python3
"""Inspect CP2K data files for basis and potential labels."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from winqstep.config import ConfigError, config_value, load_config
from winqstep.cp2k_data import Cp2kDataError, inspect_windows_cp2k_data_dir, inspect_wsl_cp2k_data_dir


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Inspect CP2K data files.")
    parser.add_argument("--config", help="Path to a WinQStep config JSON file.")
    parser.add_argument("--windows-data-dir", help="Inspect a local Windows data directory instead of WSL.")
    parser.add_argument("--cp2k-data-dir", help="Override configured WSL CP2K data directory.")
    parser.add_argument("--distro", help="Override configured WSL distro.")
    parser.add_argument("--wsl-shell-prelude", help="Override configured WSL shell prelude.")
    parser.add_argument("--timeout", type=int, help="Override configured timeout.")
    parser.add_argument("--cache", help="Windows path to write inspection cache JSON.")
    parser.add_argument("--no-cache", action="store_true", help="Do not write the default cache.")
    parser.add_argument("--limit-files", type=int, default=50, help="Maximum local Windows data files to inspect.")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    try:
        config = load_config(args.config) if args.config else {}
        cache_path = _cache_path(args, config)
        if args.windows_data_dir:
            inspection = inspect_windows_cp2k_data_dir(
                args.windows_data_dir,
                cache_path=cache_path,
                limit_files=args.limit_files,
            )
        else:
            inspection = inspect_wsl_cp2k_data_dir(
                distro=args.distro or config_value(config, "distro"),
                cp2k_data_dir=args.cp2k_data_dir or config_value(config, "cp2k_data_dir"),
                wsl_shell_prelude=args.wsl_shell_prelude or config_value(config, "wsl_shell_prelude"),
                timeout=args.timeout or int(config_value(config, "timeout", 20)),
                cache_path=cache_path,
                limit_files=args.limit_files,
            )
        if cache_path:
            inspection["cache_path"] = str(Path(cache_path).resolve())
    except (OSError, ConfigError, Cp2kDataError, ValueError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    indent = None if args.compact else 2
    print(json.dumps(inspection, ensure_ascii=False, indent=indent))
    return 0


def _cache_path(args: argparse.Namespace, config: dict[str, object]) -> str | None:
    if args.no_cache:
        return None
    if args.cache:
        return args.cache
    workspace = config_value(config, "default_windows_workspace")
    if workspace:
        return str(Path(str(workspace)) / "cp2k-data.winqstep-cache.json")
    return None


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Preflight-validate GUI job inputs before rendering or running CP2K."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from winqstep.config import ConfigError, load_config
from winqstep.preflight import (
    PreflightError,
    default_cache_path,
    validate_existing_input_preflight,
    validate_workflow_preflight,
)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Validate WinQStep job inputs before CP2K starts.")
    parser.add_argument("--mode", choices=("workflow", "existing_input"), required=True)
    parser.add_argument("--config", help="Path to a WinQStep config JSON file.")
    parser.add_argument("--template", help="Workflow template JSON path.")
    parser.add_argument("--structure", help="Workflow structure path.")
    parser.add_argument("--project-name", help="Optional workflow project name override.")
    parser.add_argument("--input", help="Existing CP2K input path.")
    parser.add_argument("--cache", help="CP2K data inspection cache JSON path.")
    parser.add_argument("--no-cache", action="store_true", help="Skip CP2K data cache checks.")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    try:
        config = load_config(args.config) if args.config else {}
        cache_path = None if args.no_cache else args.cache or default_cache_path(config)
        if args.mode == "workflow":
            if not args.template or not args.structure:
                raise PreflightError("--template and --structure are required for workflow mode")
            payload = validate_workflow_preflight(
                template_path=args.template,
                structure_path=args.structure,
                project_name=args.project_name,
                cache_path=cache_path,
                warn_missing_cache=not args.no_cache,
            )
        else:
            if not args.input:
                raise PreflightError("--input is required for existing_input mode")
            payload = validate_existing_input_preflight(
                input_path=args.input,
                cache_path=cache_path,
                warn_missing_cache=not args.no_cache,
            )
    except (OSError, ConfigError, PreflightError, ValueError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    indent = None if args.compact else 2
    print(json.dumps(payload, ensure_ascii=False, indent=indent))
    return 0 if payload["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

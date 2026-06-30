#!/usr/bin/env python3
"""Build the thin Windows EXE launcher for WinQStep."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


def find_csharp_compiler() -> str | None:
    windows_dir = os.environ.get("WINDIR")
    candidates: list[Path] = []
    if windows_dir:
        windows_path = Path(windows_dir)
        candidates.extend(
            [
                windows_path / "Microsoft.NET" / "Framework64" / "v4.0.30319" / "csc.exe",
                windows_path / "Microsoft.NET" / "Framework" / "v4.0.30319" / "csc.exe",
            ]
        )

    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)

    return shutil.which("csc.exe")


def build_launcher_plan(repo_root: Path, output_path: Path | None = None) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    source_path = repo_root / "launcher" / "WinQStep.Launcher.cs"
    resolved_output = (output_path or (repo_root / "WinQStep.exe")).resolve()
    compiler = find_csharp_compiler()
    command = [
        compiler or "csc.exe",
        "/nologo",
        "/target:winexe",
        "/optimize+",
        "/platform:anycpu",
        "/reference:System.Windows.Forms.dll",
        f"/out:{resolved_output}",
        str(source_path),
    ]

    errors: list[str] = []
    warnings: list[str] = []
    if not source_path.is_file():
        errors.append(f"launcher source was not found: {source_path}")
    if compiler is None:
        warnings.append("C# compiler csc.exe was not found; install or enable .NET Framework build tools.")

    return {
        "mode": "launcher_plan",
        "valid": not errors,
        "repo_root": str(repo_root),
        "compiler": compiler,
        "compiler_available": compiler is not None,
        "source": str(source_path),
        "source_exists": source_path.is_file(),
        "output_path": str(resolved_output),
        "output_exists": resolved_output.is_file(),
        "command": command,
        "errors": errors,
        "warnings": warnings,
    }


def build_launcher(plan: dict[str, Any]) -> dict[str, Any]:
    errors = list(plan["errors"])
    warnings = list(plan["warnings"])
    if plan["compiler"] is None:
        errors.append("cannot build WinQStep.exe without csc.exe")
    if errors:
        return {
            **plan,
            "mode": "launcher_build",
            "valid": False,
            "built": False,
            "returncode": None,
            "stdout": "",
            "stderr": "",
            "errors": errors,
            "warnings": warnings,
        }

    output_path = Path(plan["output_path"])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    completed = subprocess.run(
        plan["command"],
        cwd=plan["repo_root"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )

    output_exists = output_path.is_file()
    if completed.returncode != 0:
        errors.append("csc.exe failed to build WinQStep.exe")
    elif not output_exists:
        errors.append(f"csc.exe finished without creating {output_path}")

    return {
        **plan,
        "mode": "launcher_build",
        "valid": not errors,
        "built": completed.returncode == 0 and output_exists,
        "returncode": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
        "output_exists": output_exists,
        "errors": errors,
        "warnings": warnings,
    }


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Build the thin WinQStep.exe launcher.")
    parser.add_argument("--repo-root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--output", help="Output path for WinQStep.exe. Defaults to the repository root.")
    parser.add_argument("--dry-run", action="store_true", help="Report the compiler command without building.")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_path = Path(args.output).resolve() if args.output else None
    plan = build_launcher_plan(repo_root, output_path)
    report = plan if args.dry_run else build_launcher(plan)

    indent = None if args.compact else 2
    print(json.dumps(report, ensure_ascii=False, indent=indent))
    return 0 if report["valid"] else 2


if __name__ == "__main__":
    raise SystemExit(main())

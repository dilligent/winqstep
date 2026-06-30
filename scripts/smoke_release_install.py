#!/usr/bin/env python3
"""Smoke-test a WinQStep release archive after unpacking it."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.build_release import build_release_archive, build_release_plan


REQUIRED_UNPACKED_FILES = (
    ".gitignore",
    "README.md",
    "LICENSE",
    "THIRD_PARTY_NOTICES.md",
    "pyproject.toml",
    "WinQStep.ps1",
    "WinQStep.cmd",
    "launcher/WinQStep.Launcher.cs",
    "docs/release-candidate-handoff.md",
    "docs/release-notes.md",
    "docs/release.md",
    "docs/startup.md",
    "scripts/build_launcher.py",
    "scripts/build_release.py",
    "scripts/check_startup.py",
    "scripts/smoke_release_install.py",
    "scripts/run_checks.py",
    "scripts/release_candidate_walkthrough.py",
    "scripts/start_gui.ps1",
    "scripts/gui/WinQStep.GuiHost.ps1",
    "scripts/gui/WinQStep.xaml",
    "resources/i18n/en-US.json",
    "resources/i18n/zh-CN.json",
    "examples/winqstep.config.json",
    "examples/templates/energy_pbe.json",
    "tests/fixtures/quickstep_energy.inp",
)

FORBIDDEN_UNPACKED_PATHS = (
    ".git",
    ".venv",
    "build",
    "dist",
    "outputs",
    "codex-thread.json",
)


def smoke_release_install(
    repo_root: Path,
    archive_path: Path | None = None,
    output_dir: Path | None = None,
    skip_diagnostics: bool = False,
    timeout: int = 30,
    keep_temp: bool = False,
) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    temp_context: tempfile.TemporaryDirectory[str] | None = None
    if keep_temp:
        temp_root = Path(tempfile.mkdtemp(prefix="winqstep-release-smoke-")).resolve()
    else:
        temp_context = tempfile.TemporaryDirectory(prefix="winqstep-release-smoke-")
        temp_root = Path(temp_context.name).resolve()

    try:
        build_report = None
        if archive_path is None:
            release_output_dir = (output_dir or (temp_root / "dist")).resolve()
            plan = build_release_plan(repo_root, release_output_dir)
            build_report = build_release_archive(plan, repo_root)
            archive_path = Path(build_report["archive_path"]).resolve()
        else:
            archive_path = archive_path.resolve()

        errors: list[str] = []
        warnings: list[str] = []
        extract_dir = temp_root / "extract"
        extract_dir.mkdir(parents=True, exist_ok=True)

        archive_report = _inspect_archive(archive_path, errors)
        archive_root = archive_report.get("archive_root")
        extracted_root = None
        if archive_root:
            _safe_extract_zip(archive_path, extract_dir, errors)
            extracted_root = extract_dir / str(archive_root)
            _check_unpacked_tree(extracted_root, errors)

        diagnostics = _run_unpacked_diagnostics(extracted_root, skip_diagnostics, timeout, warnings)
        if diagnostics.get("valid") is False:
            errors.append("unpacked startup diagnostics failed")

        return {
            "mode": "release_install_smoke",
            "valid": not errors,
            "errors": errors,
            "warnings": warnings,
            "repo_root": str(repo_root),
            "archive_path": str(archive_path),
            "temp_root": str(temp_root) if keep_temp else None,
            "build": build_report,
            "archive": archive_report,
            "unpacked_root": str(extracted_root) if extracted_root else None,
            "diagnostics": diagnostics,
        }
    finally:
        if temp_context is not None:
            temp_context.cleanup()


def _inspect_archive(archive_path: Path, errors: list[str]) -> dict[str, Any]:
    if not archive_path.is_file():
        errors.append(f"release archive was not found: {archive_path}")
        return {
            "exists": False,
            "archive_root": None,
            "file_count": 0,
            "size": 0,
        }

    with zipfile.ZipFile(archive_path) as archive:
        names = [name for name in archive.namelist() if name and not name.endswith("/")]

    roots = sorted({PurePosixPath(name).parts[0] for name in names if PurePosixPath(name).parts})
    archive_root = roots[0] if len(roots) == 1 else None
    if archive_root is None:
        errors.append(f"release archive should contain one top-level folder, found: {roots}")

    return {
        "exists": True,
        "archive_root": archive_root,
        "file_count": len(names),
        "size": archive_path.stat().st_size,
    }


def _safe_extract_zip(archive_path: Path, extract_dir: Path, errors: list[str]) -> None:
    base = extract_dir.resolve()
    with zipfile.ZipFile(archive_path) as archive:
        for info in archive.infolist():
            member = PurePosixPath(info.filename)
            if not info.filename or member.is_absolute() or ".." in member.parts:
                errors.append(f"unsafe archive member path: {info.filename}")
                continue

            target = (extract_dir / Path(*member.parts)).resolve()
            if not target.is_relative_to(base):
                errors.append(f"archive member escapes extraction directory: {info.filename}")
                continue

            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue

            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info) as source, target.open("wb") as destination:
                shutil.copyfileobj(source, destination)


def _check_unpacked_tree(unpacked_root: Path, errors: list[str]) -> None:
    if not unpacked_root.is_dir():
        errors.append(f"unpacked release root was not found: {unpacked_root}")
        return

    for relative in REQUIRED_UNPACKED_FILES:
        if not (unpacked_root / relative).is_file():
            errors.append(f"unpacked release is missing required file: {relative}")

    for relative in FORBIDDEN_UNPACKED_PATHS:
        if (unpacked_root / relative).exists():
            errors.append(f"unpacked release contains excluded path: {relative}")


def _run_unpacked_diagnostics(
    unpacked_root: Path | None,
    skip_diagnostics: bool,
    timeout: int,
    warnings: list[str],
) -> dict[str, Any]:
    if unpacked_root is None:
        return {
            "skipped": True,
            "valid": None,
            "reason": "archive did not unpack to a release root",
        }
    if skip_diagnostics:
        return {
            "skipped": True,
            "valid": None,
            "reason": "disabled by --skip-diagnostics",
        }

    powershell = shutil.which("powershell") or shutil.which("pwsh")
    if not powershell:
        warnings.append("PowerShell was not found; skipped unpacked launcher diagnostics.")
        return {
            "skipped": True,
            "valid": None,
            "reason": "PowerShell was not found on PATH",
        }

    command = [
        powershell,
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(unpacked_root / "WinQStep.ps1"),
        "-Diagnostics",
        "-SkipLiveProbes",
    ]
    try:
        completed = subprocess.run(
            command,
            cwd=unpacked_root,
            capture_output=True,
            text=True,
            encoding="utf-8-sig",
            errors="replace",
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {
            "skipped": False,
            "valid": False,
            "command": command,
            "returncode": None,
            "error": str(exc),
            "report": None,
        }

    report = None
    error = None
    stdout = completed.stdout.strip()
    if stdout:
        try:
            report = json.loads(stdout)
        except json.JSONDecodeError as exc:
            error = f"diagnostics did not return JSON: {exc}"
    elif completed.stderr.strip():
        error = completed.stderr.strip()

    valid = completed.returncode == 0 and error is None
    if isinstance(report, dict):
        valid = valid and bool(report.get("valid"))

    return {
        "skipped": False,
        "valid": valid,
        "command": command,
        "returncode": completed.returncode,
        "error": error,
        "report": report,
    }


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Unpack and smoke-test a WinQStep release zip.")
    parser.add_argument("--repo-root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--archive", help="Existing release zip to test. Defaults to building one in a temp dir.")
    parser.add_argument("--output-dir", help="Directory for a newly built release zip.")
    parser.add_argument("--skip-diagnostics", action="store_true", help="Only inspect archive contents.")
    parser.add_argument("--timeout", type=int, default=30, help="Seconds to wait for unpacked diagnostics.")
    parser.add_argument("--keep-temp", action="store_true", help="Keep the temporary extraction directory.")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    report = smoke_release_install(
        repo_root=Path(args.repo_root),
        archive_path=Path(args.archive) if args.archive else None,
        output_dir=Path(args.output_dir) if args.output_dir else None,
        skip_diagnostics=args.skip_diagnostics,
        timeout=args.timeout,
        keep_temp=args.keep_temp,
    )
    indent = None if args.compact else 2
    print(json.dumps(report, ensure_ascii=False, indent=indent))
    return 0 if report["valid"] else 2


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Check WinQStep startup prerequisites and release hygiene."""

from __future__ import annotations

import argparse
import json
import platform
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from winqstep.config import ConfigError, load_config, validate_config


REQUIRED_FILES = (
    "WinQStep.cmd",
    "WinQStep.ps1",
    "launcher/WinQStep.Launcher.cs",
    "scripts/build_launcher.py",
    "scripts/check_startup.py",
    "scripts/build_release.py",
    "scripts/smoke_release_install.py",
    "scripts/run_checks.py",
    "scripts/release_candidate_walkthrough.py",
    "scripts/start_gui.ps1",
    "scripts/gui/WinQStep.GuiHost.ps1",
    "scripts/gui/WinQStep.xaml",
    "resources/i18n/en-US.json",
    "resources/i18n/zh-CN.json",
    "scripts/detect_environment.py",
    "scripts/import_structure.py",
    "scripts/run_workflow.py",
    "scripts/run_existing_input.py",
    "scripts/list_job_history.py",
    "scripts/manage_config.py",
    "scripts/manage_template.py",
    "scripts/inspect_cp2k_data.py",
    "scripts/validate_job_inputs.py",
    "scripts/mark_job_cancelled.py",
    "examples/winqstep.config.example.json",
    "examples/templates/energy_pbe.example.json",
    "tests/fixtures/structures/water.xyz",
    "tests/fixtures/quickstep_energy.inp",
)

RELEASE_EXCLUSION_PATTERNS = (
    "codex-thread.json",
    "/outputs/",
    "/WinQStep.exe",
    "/build/",
    "/dist/",
    "/cp2k-*/",
    "/examples/winqstep.config.json",
    "/examples/templates/energy_pbe.json",
    "/examples/templates/*.local.json",
    "*.winqstep-cache.json",
    "__pycache__/",
    "*.py[cod]",
    ".venv/",
    ".env",
)


def check_required_files(repo_root: Path, errors: list[str]) -> list[dict[str, Any]]:
    rows = []
    for relative_path in REQUIRED_FILES:
        path = repo_root / relative_path
        exists = path.exists()
        rows.append({"path": relative_path, "exists": exists})
        if not exists:
            errors.append(f"missing required file: {relative_path}")
    return rows


def check_release_exclusions(repo_root: Path, warnings: list[str]) -> list[dict[str, Any]]:
    gitignore_path = repo_root / ".gitignore"
    text = ""
    if gitignore_path.is_file():
        text = gitignore_path.read_text(encoding="utf-8", errors="replace")
    else:
        warnings.append(".gitignore was not found; generated artifacts may be committed accidentally.")

    rows = []
    for pattern in RELEASE_EXCLUSION_PATTERNS:
        present = pattern in text
        rows.append({"pattern": pattern, "present": present})
        if not present:
            warnings.append(f"release exclusion is not listed in .gitignore: {pattern}")
    return rows


def check_python(errors: list[str]) -> dict[str, Any]:
    version = sys.version_info
    ok = version >= (3, 11)
    if not ok:
        errors.append("Python 3.11 or newer is required.")
    return {
        "executable": sys.executable,
        "version": platform.python_version(),
        "ok": ok,
    }


def check_powershell(warnings: list[str]) -> dict[str, Any]:
    windows_powershell = shutil.which("powershell")
    pwsh = shutil.which("pwsh")
    path = windows_powershell or pwsh
    if not path:
        warnings.append("Windows PowerShell was not found on PATH; the GUI launcher cannot start.")
    elif not windows_powershell:
        warnings.append("Windows PowerShell 5.1 was not found; the GUI launcher expects powershell.exe, not only pwsh.")
    return {
        "executable": path,
        "available": bool(path),
        "windows_powershell": windows_powershell,
        "pwsh": pwsh,
    }


def check_wpf_desktop(errors: list[str]) -> dict[str, Any]:
    powershell = shutil.which("powershell")
    assemblies = ("PresentationFramework", "PresentationCore", "WindowsBase", "System.Windows.Forms")
    if not powershell:
        return {
            "ok": None,
            "skipped": True,
            "reason": "Windows PowerShell was not found on PATH",
            "assemblies": list(assemblies),
        }

    command_text = (
        "$ErrorActionPreference='Stop'; "
        + "; ".join(f"Add-Type -AssemblyName {assembly}" for assembly in assemblies)
        + "; Write-Output 'ok'"
    )
    command = [
        powershell,
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        command_text,
    ]
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=20,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        errors.append(f"WPF/.NET desktop assembly check could not run: {exc}")
        return {
            "ok": False,
            "skipped": False,
            "command": command,
            "returncode": None,
            "stdout": "",
            "stderr": "",
            "error": str(exc),
            "assemblies": list(assemblies),
        }

    ok = completed.returncode == 0
    if not ok:
        errors.append(
            "WPF/.NET desktop assemblies are not available; install or enable the "
            ".NET desktop runtime / .NET Framework WPF support and run WinQStep "
            "with Windows PowerShell 5.1."
        )
    return {
        "ok": ok,
        "skipped": False,
        "command": command,
        "returncode": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
        "error": None,
        "assemblies": list(assemblies),
    }


def check_config(config_path: Path, errors: list[str], warnings: list[str]) -> dict[str, Any]:
    try:
        config = load_config(config_path)
    except (OSError, ConfigError, ValueError, json.JSONDecodeError) as exc:
        errors.append(f"config could not be loaded: {exc}")
        return {
            "path": str(config_path),
            "valid": False,
            "errors": [str(exc)],
            "warnings": [],
            "config": {},
        }

    validation = validate_config(config, require_execution=True)
    errors.extend(f"config: {error}" for error in validation["errors"])
    warnings.extend(f"config: {warning}" for warning in validation["warnings"])
    return {
        "path": str(config_path),
        **validation,
    }


def run_live_probe(repo_root: Path, config_path: Path, timeout: int) -> dict[str, Any]:
    command = [
        sys.executable,
        str(repo_root / "scripts" / "detect_environment.py"),
        "--config",
        str(config_path),
        "--timeout",
        str(timeout),
        "--compact",
    ]
    try:
        completed = subprocess.run(
            command,
            cwd=repo_root,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout * 4,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {
            "skipped": False,
            "ok": False,
            "command": command,
            "returncode": None,
            "error": str(exc),
            "report": None,
        }

    report = None
    error = None
    if completed.stdout.strip():
        try:
            report = json.loads(completed.stdout)
        except json.JSONDecodeError as exc:
            error = f"detect_environment.py did not return JSON: {exc}"
    elif completed.stderr.strip():
        error = completed.stderr.strip()

    return {
        "skipped": False,
        "ok": completed.returncode == 0,
        "command": command,
        "returncode": completed.returncode,
        "error": error,
        "report": report,
    }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    repo_root = Path(args.repo_root).resolve()
    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = repo_root / config_path

    errors: list[str] = []
    warnings: list[str] = []
    checks: dict[str, Any] = {
        "host": {
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
        },
        "python": check_python(errors),
        "powershell": check_powershell(warnings),
        "wpf_desktop": check_wpf_desktop(errors),
        "required_files": check_required_files(repo_root, errors),
        "config": check_config(config_path, errors, warnings),
        "release_exclusions": check_release_exclusions(repo_root, warnings),
    }

    if args.skip_live_probes:
        checks["live_probes"] = {
            "skipped": True,
            "ok": None,
            "reason": "disabled by --skip-live-probes",
        }
    else:
        live_probe = run_live_probe(repo_root, config_path, args.timeout)
        checks["live_probes"] = live_probe
        if live_probe["error"]:
            errors.append(f"live probe failed: {live_probe['error']}")
        elif not live_probe["ok"]:
            report = live_probe.get("report")
            if isinstance(report, dict) and report.get("warnings"):
                warnings.extend(f"live probe: {warning}" for warning in report["warnings"])
            else:
                errors.append("live probe failed; run scripts/detect_environment.py for details")

    return {
        "mode": "startup_diagnostics",
        "repo_root": str(repo_root),
        "valid": not errors,
        "errors": errors,
        "warnings": warnings,
        "checks": checks,
    }


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Check WinQStep startup prerequisites.")
    parser.add_argument("--repo-root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--config", default="examples/winqstep.config.example.json")
    parser.add_argument("--timeout", type=int, default=20)
    parser.add_argument("--skip-live-probes", action="store_true")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    report = build_report(args)
    indent = None if args.compact else 2
    print(json.dumps(report, ensure_ascii=False, indent=indent))
    return 0 if report["valid"] else 2


if __name__ == "__main__":
    raise SystemExit(main())

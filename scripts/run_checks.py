#!/usr/bin/env python3
"""Run WinQStep's standard local verification profiles."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


PROFILE_ALIASES = {
    "all": ("fast", "gui", "release", "rc"),
}


def normalize_profiles(profiles: list[str] | None) -> list[str]:
    requested = profiles or ["fast"]
    normalized: list[str] = []
    for profile in requested:
        for expanded in PROFILE_ALIASES.get(profile, (profile,)):
            if expanded not in normalized:
                normalized.append(expanded)
    return normalized


def build_check_plan(
    repo_root: Path,
    profiles: list[str] | None = None,
    *,
    python_executable: str | None = None,
    powershell_executable: str | None = None,
) -> list[dict[str, Any]]:
    repo_root = repo_root.resolve()
    python = python_executable or sys.executable
    powershell = powershell_executable if powershell_executable is not None else find_powershell()
    normalized_profiles = normalize_profiles(profiles)

    checks: list[dict[str, Any]] = []
    for profile in normalized_profiles:
        if profile == "fast":
            checks.extend(
                [
                    python_check(
                        "unit-tests",
                        profile,
                        python,
                        ["-m", "unittest", "discover", "-s", "tests"],
                        timeout=180,
                    ),
                    python_check(
                        "startup-diagnostics-offline",
                        profile,
                        python,
                        ["scripts/check_startup.py", "--skip-live-probes", "--compact"],
                        timeout=60,
                    ),
                ]
            )
        elif profile == "gui":
            checks.extend(
                [
                    powershell_check(
                        "gui-smoke-zh-cn",
                        profile,
                        powershell,
                        ["-SmokeTest", "-Language", "zh-CN"],
                        timeout=120,
                    ),
                    powershell_check(
                        "gui-button-smoke-offline",
                        profile,
                        powershell,
                        ["-ButtonSmokeTest", "-SkipLiveProbes", "-Language", "zh-CN"],
                        timeout=120,
                    ),
                    powershell_check(
                        "gui-lifecycle-smoke",
                        profile,
                        powershell,
                        ["-LifecycleSmokeTest"],
                        timeout=120,
                    ),
                    powershell_check(
                        "gui-python-invoke-smoke",
                        profile,
                        powershell,
                        ["-PythonInvokeSmokeTest"],
                        timeout=60,
                    ),
                ]
            )
        elif profile == "release":
            checks.extend(
                [
                    python_check(
                        "launcher-plan",
                        profile,
                        python,
                        ["scripts/build_launcher.py", "--dry-run", "--compact"],
                        timeout=60,
                    ),
                    python_check(
                        "release-plan",
                        profile,
                        python,
                        ["scripts/build_release.py", "--dry-run", "--compact"],
                        timeout=60,
                    ),
                    python_check(
                        "release-install-smoke",
                        profile,
                        python,
                        ["scripts/smoke_release_install.py", "--compact"],
                        timeout=180,
                    ),
                ]
            )
        elif profile == "rc":
            checks.extend(
                [
                    python_check(
                        "release-candidate-walkthrough",
                        profile,
                        python,
                        ["scripts/release_candidate_walkthrough.py", "--compact"],
                        timeout=240,
                    ),
                ]
            )
        elif profile == "live":
            checks.extend(
                [
                    powershell_check(
                        "startup-diagnostics-live",
                        profile,
                        powershell,
                        ["-Diagnostics"],
                        timeout=240,
                    ),
                    powershell_check(
                        "gui-button-smoke-live",
                        profile,
                        powershell,
                        ["-ButtonSmokeTest", "-Language", "zh-CN"],
                        timeout=240,
                    ),
                    powershell_check(
                        "gui-async-run-smoke-live",
                        profile,
                        powershell,
                        ["-AsyncRunSmokeTest", "-Language", "zh-CN"],
                        timeout=300,
                    ),
                ]
            )
        else:
            raise ValueError(f"unknown profile: {profile}")

    deduped: list[dict[str, Any]] = []
    seen = set()
    for check in checks:
        if check["name"] in seen:
            continue
        seen.add(check["name"])
        check["repo_root"] = str(repo_root)
        deduped.append(check)
    return deduped


def python_check(name: str, profile: str, python: str, args: list[str], *, timeout: int) -> dict[str, Any]:
    return {
        "name": name,
        "profile": profile,
        "command": [python, *args],
        "timeout": timeout,
        "skip_reason": None,
    }


def powershell_check(
    name: str,
    profile: str,
    powershell: str | None,
    args: list[str],
    *,
    timeout: int,
) -> dict[str, Any]:
    executable = powershell or "powershell"
    return {
        "name": name,
        "profile": profile,
        "command": [
            executable,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            "scripts/start_gui.ps1",
            *args,
        ],
        "timeout": timeout,
        "skip_reason": None if powershell else "PowerShell was not found on PATH",
    }


def find_powershell() -> str | None:
    return shutil.which("powershell") or shutil.which("pwsh")


def run_plan(
    repo_root: Path,
    plan: list[dict[str, Any]],
    *,
    profiles: list[str] | None = None,
    list_only: bool = False,
    timeout_override: int | None = None,
) -> dict[str, Any]:
    checks = []
    for check in plan:
        if list_only:
            checks.append({**check, "status": "planned"})
        else:
            checks.append(run_one_check(repo_root, check, timeout_override=timeout_override))

    summary = summarize_checks(checks, list_only=list_only)
    return {
        "mode": "run_checks",
        "repo_root": str(repo_root.resolve()),
        "profiles": normalize_profiles(profiles),
        "valid": summary["failed"] == 0,
        "summary": summary,
        "checks": checks,
    }


def run_one_check(repo_root: Path, check: dict[str, Any], *, timeout_override: int | None = None) -> dict[str, Any]:
    if check.get("skip_reason"):
        return {
            **check,
            "status": "skipped",
            "returncode": None,
            "duration_seconds": 0.0,
            "stdout_tail": "",
            "stderr_tail": "",
            "error": check["skip_reason"],
        }

    timeout = timeout_override or int(check["timeout"])
    started = time.perf_counter()
    try:
        completed = subprocess.run(
            check["command"],
            cwd=repo_root,
            capture_output=True,
            text=True,
            encoding="utf-8-sig",
            errors="replace",
            timeout=timeout,
            check=False,
        )
        duration = round(time.perf_counter() - started, 3)
        return {
            **check,
            "status": "passed" if completed.returncode == 0 else "failed",
            "returncode": completed.returncode,
            "duration_seconds": duration,
            "stdout_tail": tail_text(completed.stdout),
            "stderr_tail": tail_text(completed.stderr),
            "error": None,
        }
    except subprocess.TimeoutExpired as exc:
        duration = round(time.perf_counter() - started, 3)
        return {
            **check,
            "status": "failed",
            "returncode": None,
            "duration_seconds": duration,
            "stdout_tail": tail_text(to_text(exc.stdout)),
            "stderr_tail": tail_text(to_text(exc.stderr)),
            "error": f"timed out after {timeout} seconds",
        }
    except OSError as exc:
        duration = round(time.perf_counter() - started, 3)
        return {
            **check,
            "status": "failed",
            "returncode": None,
            "duration_seconds": duration,
            "stdout_tail": "",
            "stderr_tail": "",
            "error": str(exc),
        }


def summarize_checks(checks: list[dict[str, Any]], *, list_only: bool) -> dict[str, int]:
    if list_only:
        return {
            "total": len(checks),
            "planned": len(checks),
            "passed": 0,
            "failed": 0,
            "skipped": 0,
        }
    return {
        "total": len(checks),
        "planned": 0,
        "passed": sum(1 for check in checks if check["status"] == "passed"),
        "failed": sum(1 for check in checks if check["status"] == "failed"),
        "skipped": sum(1 for check in checks if check["status"] == "skipped"),
    }


def tail_text(text: str, max_chars: int = 4000) -> str:
    if len(text) <= max_chars:
        return text
    return text[-max_chars:]


def to_text(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    repo_root = Path(args.repo_root).resolve()
    profiles = normalize_profiles(args.profile)
    plan = build_check_plan(repo_root, profiles)
    return run_plan(repo_root, plan, profiles=profiles, list_only=args.list, timeout_override=args.timeout)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Run standard WinQStep verification profiles.")
    parser.add_argument("--repo-root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument(
        "--profile",
        action="append",
        choices=("fast", "gui", "release", "rc", "live", "all"),
        help="Verification profile to run. Repeat to combine profiles. Defaults to fast.",
    )
    parser.add_argument("--list", action="store_true", help="List the selected checks without running them.")
    parser.add_argument("--timeout", type=int, help="Override the per-check timeout in seconds.")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    report = build_report(args)
    indent = None if args.compact else 2
    print(json.dumps(report, ensure_ascii=False, indent=indent))
    return 0 if report["valid"] else 2


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Run a release-candidate walkthrough of the main WinQStep user paths."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Run the WinQStep release-candidate workflow walkthrough.")
    parser.add_argument("--repo-root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--workspace", help="Workspace for prepared walkthrough jobs. Defaults to a temporary folder.")
    parser.add_argument("--keep-workspace", action="store_true", help="Keep the temporary workspace for inspection.")
    parser.add_argument("--include-live", action="store_true", help="Run a real CP2K ENERGY_FORCE workflow.")
    parser.add_argument("--include-release-smoke", action="store_true", help="Run unpacked release install smoke too.")
    parser.add_argument("--timeout", type=int, default=180, help="Per-step timeout in seconds.")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    temp_context: tempfile.TemporaryDirectory[str] | None = None
    if args.workspace:
        workspace = Path(args.workspace).resolve()
        workspace.mkdir(parents=True, exist_ok=True)
    elif args.keep_workspace:
        workspace = Path(tempfile.mkdtemp(prefix="winqstep-rc-walkthrough-")).resolve()
    else:
        temp_context = tempfile.TemporaryDirectory(prefix="winqstep-rc-walkthrough-")
        workspace = Path(temp_context.name).resolve()

    try:
        report = run_walkthrough(
            repo_root=repo_root,
            workspace=workspace,
            include_live=args.include_live,
            include_release_smoke=args.include_release_smoke,
            timeout=args.timeout,
            workspace_retained=args.keep_workspace or bool(args.workspace),
        )
    finally:
        if temp_context is not None:
            temp_context.cleanup()

    indent = None if args.compact else 2
    print(json.dumps(report, ensure_ascii=False, indent=indent))
    return 0 if report["valid"] else 2


def run_walkthrough(
    *,
    repo_root: Path,
    workspace: Path,
    include_live: bool = False,
    include_release_smoke: bool = False,
    timeout: int = 180,
    workspace_retained: bool = True,
) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    workspace = workspace.resolve()
    workspace.mkdir(parents=True, exist_ok=True)

    config = repo_root / "examples" / "winqstep.config.json"
    energy_force_template = repo_root / "examples" / "templates" / "energy_force_pbe.json"
    structure = repo_root / "tests" / "fixtures" / "structures" / "water.xyz"
    existing_input = repo_root / "tests" / "fixtures" / "quickstep_energy_force.inp"
    workflow_dir = workspace / "workflow-energy-force"
    existing_dir = workspace / "existing-input"
    live_dir = workspace / "live-energy-force"

    steps: list[dict[str, Any]] = []
    errors: list[str] = []
    warnings: list[str] = []

    startup = _run_json_step(
        "startup-diagnostics-offline",
        [sys.executable, "scripts/check_startup.py", "--skip-live-probes", "--compact"],
        repo_root,
        timeout,
        errors,
    )
    steps.append(_step_summary(startup, _startup_summary))
    _require(_payload_value(startup, "valid") is True, errors, "offline startup diagnostics must be valid")

    config_step = _run_json_step(
        "config-validation",
        [sys.executable, "scripts/manage_config.py", "--config", str(config), "--require-execution", "--compact"],
        repo_root,
        timeout,
        errors,
    )
    steps.append(_step_summary(config_step, _config_summary))
    _require(_payload_value(config_step, "validation", "valid") is True, errors, "sample config must validate")

    template_step = _run_json_step(
        "energy-force-template-validation",
        [sys.executable, "scripts/manage_template.py", "--template", str(energy_force_template), "--compact"],
        repo_root,
        timeout,
        errors,
    )
    steps.append(_step_summary(template_step, _template_summary))
    _require(
        _payload_value(template_step, "validation", "valid") is True,
        errors,
        "ENERGY_FORCE template must validate",
    )
    _require(
        _payload_value(template_step, "template", "run_type") == "ENERGY_FORCE",
        errors,
        "release-candidate walkthrough must exercise ENERGY_FORCE",
    )

    workflow_preflight = _run_json_step(
        "workflow-preflight",
        [
            sys.executable,
            "scripts/validate_job_inputs.py",
            "--mode",
            "workflow",
            "--config",
            str(config),
            "--template",
            str(energy_force_template),
            "--structure",
            str(structure),
            "--project-name",
            "rc_energy_force",
            "--no-cache",
            "--compact",
        ],
        repo_root,
        timeout,
        errors,
    )
    steps.append(_step_summary(workflow_preflight, _preflight_summary))
    _require(_payload_value(workflow_preflight, "valid") is True, errors, "workflow preflight must be valid")

    workflow_prepare = _run_json_step(
        "workflow-prepare-energy-force",
        [
            sys.executable,
            "scripts/run_workflow.py",
            "--config",
            str(config),
            "--template",
            str(energy_force_template),
            "--structure",
            str(structure),
            "--job-dir",
            str(workflow_dir),
            "--project-name",
            "rc_energy_force",
            "--prepare-only",
            "--compact",
        ],
        repo_root,
        timeout,
        errors,
    )
    steps.append(_step_summary(workflow_prepare, _job_summary))
    _require(_payload_value(workflow_prepare, "status") == "prepared", errors, "workflow prepare must succeed")
    _require(
        _payload_value(workflow_prepare, "quickstep", "run_type") == "ENERGY_FORCE",
        errors,
        "workflow prepare must produce ENERGY_FORCE metadata",
    )
    workflow_input_path = _payload_value(workflow_prepare, "files", "input", "path")
    _require(_input_contains(workflow_input_path, "RUN_TYPE ENERGY_FORCE"), errors, "workflow input must use ENERGY_FORCE")
    _require(_input_contains(workflow_input_path, "&FORCES ON"), errors, "workflow input must request force printing")

    existing_preflight = _run_json_step(
        "existing-input-preflight",
        [
            sys.executable,
            "scripts/validate_job_inputs.py",
            "--mode",
            "existing_input",
            "--config",
            str(config),
            "--input",
            str(existing_input),
            "--no-cache",
            "--compact",
        ],
        repo_root,
        timeout,
        errors,
    )
    steps.append(_step_summary(existing_preflight, _preflight_summary))
    _require(_payload_value(existing_preflight, "valid") is True, errors, "existing-input preflight must be valid")

    existing_prepare = _run_json_step(
        "existing-input-prepare",
        [
            sys.executable,
            "scripts/run_existing_input.py",
            "--config",
            str(config),
            "--input",
            str(existing_input),
            "--job-dir",
            str(existing_dir),
            "--prepare-only",
            "--compact",
        ],
        repo_root,
        timeout,
        errors,
    )
    steps.append(_step_summary(existing_prepare, _job_summary))
    _require(_payload_value(existing_prepare, "status") == "prepared", errors, "existing input prepare must succeed")
    _require(
        Path(str(_payload_value(existing_prepare, "files", "input", "path"))).resolve() == existing_input.resolve(),
        errors,
        "existing-input prepare must preserve the original input path",
    )

    history = _run_json_step(
        "workspace-history",
        [sys.executable, "scripts/list_job_history.py", "--workspace", str(workspace), "--compact"],
        repo_root,
        timeout,
        errors,
    )
    steps.append(_step_summary(history, _history_summary))
    jobs = _payload_value(history, "jobs") or []
    _require(isinstance(jobs, list) and len(jobs) >= 2, errors, "walkthrough workspace history must include both jobs")
    projects = {str(job.get("project_name")) for job in jobs if isinstance(job, dict)}
    _require("rc_energy_force" in projects, errors, "history must include the workflow job")
    _require("quickstep_energy_force" in projects, errors, "history must include the existing-input job")

    release_plan = _run_json_step(
        "release-plan",
        [sys.executable, "scripts/build_release.py", "--dry-run", "--compact"],
        repo_root,
        timeout,
        errors,
    )
    steps.append(_step_summary(release_plan, _release_plan_summary))
    _require(_payload_value(release_plan, "valid") is True, errors, "release dry-run plan must be valid")
    release_files = _payload_value(release_plan, "files") or []
    _require(
        "scripts/release_candidate_walkthrough.py" in release_files,
        errors,
        "release plan must include the RC walkthrough script",
    )

    if include_release_smoke:
        release_smoke = _run_json_step(
            "release-install-smoke",
            [sys.executable, "scripts/smoke_release_install.py", "--compact"],
            repo_root,
            timeout,
            errors,
        )
        steps.append(_step_summary(release_smoke, _release_smoke_summary))
        _require(_payload_value(release_smoke, "valid") is True, errors, "release install smoke must be valid")

    if include_live:
        live_step = _run_json_step(
            "live-energy-force-workflow",
            [
                sys.executable,
                "scripts/run_workflow.py",
                "--config",
                str(config),
                "--template",
                str(energy_force_template),
                "--structure",
                str(structure),
                "--job-dir",
                str(live_dir),
                "--project-name",
                "rc_live_energy_force",
                "--compact",
            ],
            repo_root,
            timeout,
            errors,
        )
        steps.append(_step_summary(live_step, _live_job_summary))
        _require(_payload_value(live_step, "status") == "succeeded", errors, "live ENERGY_FORCE workflow must succeed")
        _require(
            _payload_value(live_step, "cp2k_output", "total_energy_hartree") is not None,
            errors,
            "live ENERGY_FORCE workflow must parse total energy",
        )
        _require(
            _payload_value(live_step, "cp2k_output", "forces", "total_atomic_force") is not None,
            errors,
            "live ENERGY_FORCE workflow must parse total atomic force",
        )

    return {
        "mode": "release_candidate_walkthrough",
        "repo_root": str(repo_root),
        "workspace": str(workspace) if workspace_retained else None,
        "workspace_retained": workspace_retained,
        "include_live": include_live,
        "include_release_smoke": include_release_smoke,
        "valid": not errors,
        "errors": errors,
        "warnings": warnings,
        "summary": {
            "total": len(steps),
            "passed": sum(1 for step in steps if step["status"] == "passed"),
            "failed": sum(1 for step in steps if step["status"] == "failed"),
        },
        "steps": steps,
    }


def _run_json_step(
    name: str,
    command: list[str],
    repo_root: Path,
    timeout: int,
    errors: list[str],
) -> dict[str, Any]:
    try:
        completed = subprocess.run(
            command,
            cwd=repo_root,
            capture_output=True,
            text=True,
            encoding="utf-8-sig",
            errors="replace",
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        errors.append(f"{name} timed out after {timeout} seconds")
        return {
            "name": name,
            "command": command,
            "returncode": None,
            "status": "failed",
            "payload": None,
            "stdout_tail": _tail(_to_text(exc.stdout)),
            "stderr_tail": _tail(_to_text(exc.stderr)),
            "error": f"timed out after {timeout} seconds",
        }
    except OSError as exc:
        errors.append(f"{name} could not start: {exc}")
        return {
            "name": name,
            "command": command,
            "returncode": None,
            "status": "failed",
            "payload": None,
            "stdout_tail": "",
            "stderr_tail": "",
            "error": str(exc),
        }

    payload = None
    error = None
    stdout = completed.stdout.strip()
    if stdout:
        try:
            payload = json.loads(stdout)
        except json.JSONDecodeError as exc:
            error = f"did not return JSON: {exc}"
            errors.append(f"{name} {error}")
    elif completed.returncode == 0:
        error = "returned no JSON"
        errors.append(f"{name} {error}")

    if completed.returncode != 0:
        message = completed.stderr.strip() or error or f"exit code {completed.returncode}"
        errors.append(f"{name} failed: {message}")

    return {
        "name": name,
        "command": command,
        "returncode": completed.returncode,
        "status": "passed" if completed.returncode == 0 and error is None else "failed",
        "payload": payload,
        "stdout_tail": _tail(completed.stdout) if completed.returncode != 0 or error else "",
        "stderr_tail": _tail(completed.stderr) if completed.returncode != 0 or error else "",
        "error": error,
    }


def _step_summary(step: dict[str, Any], summarizer: Any) -> dict[str, Any]:
    payload = step.get("payload")
    summary = summarizer(payload) if isinstance(payload, dict) else {}
    return {
        "name": step["name"],
        "command": step["command"],
        "status": step["status"],
        "returncode": step["returncode"],
        "summary": summary,
        "stdout_tail": step["stdout_tail"],
        "stderr_tail": step["stderr_tail"],
        "error": step["error"],
    }


def _payload_value(step: dict[str, Any], *keys: str) -> Any:
    current = step.get("payload")
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def _require(condition: bool, errors: list[str], message: str) -> None:
    if not condition:
        errors.append(message)


def _input_contains(path: Any, needle: str) -> bool:
    if path is None:
        return False
    candidate = Path(str(path))
    if not candidate.is_file():
        return False
    return needle in candidate.read_text(encoding="utf-8", errors="replace")


def _startup_summary(payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "valid": payload.get("valid"),
        "errors": len(payload.get("errors") or []),
        "warnings": len(payload.get("warnings") or []),
    }


def _config_summary(payload: dict[str, Any]) -> dict[str, Any]:
    validation = payload.get("validation") or {}
    config = payload.get("config") or {}
    return {
        "valid": validation.get("valid"),
        "distro": config.get("distro"),
        "cp2k_command": config.get("cp2k_command"),
        "cp2k_data_dir": config.get("cp2k_data_dir"),
    }


def _template_summary(payload: dict[str, Any]) -> dict[str, Any]:
    validation = payload.get("validation") or {}
    template = payload.get("template") or {}
    return {
        "valid": validation.get("valid"),
        "project_name": template.get("project_name"),
        "run_type": template.get("run_type"),
    }


def _preflight_summary(payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "mode": payload.get("mode"),
        "valid": payload.get("valid"),
        "errors": len(payload.get("errors") or []),
        "warnings": len(payload.get("warnings") or []),
    }


def _job_summary(payload: dict[str, Any]) -> dict[str, Any]:
    files = payload.get("files") or {}
    quickstep = payload.get("quickstep") or {}
    job = payload.get("job") or {}
    output = payload.get("cp2k_output") or {}
    input_file = files.get("input") or {}
    metadata_file = files.get("metadata") or {}
    return {
        "status": payload.get("status"),
        "returncode": payload.get("returncode"),
        "mode": job.get("mode") or "workflow",
        "project_name": quickstep.get("project_name") or job.get("input_stem"),
        "run_type": quickstep.get("run_type"),
        "input_exists": input_file.get("exists"),
        "metadata_exists": metadata_file.get("exists"),
        "cp2k_output_status": output.get("status"),
    }


def _history_summary(payload: dict[str, Any]) -> dict[str, Any]:
    jobs = payload.get("jobs") or []
    return {
        "job_count": len(jobs),
        "projects": [job.get("project_name") for job in jobs if isinstance(job, dict)],
        "errors": len(payload.get("errors") or []),
    }


def _release_plan_summary(payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "valid": payload.get("valid"),
        "version": payload.get("version"),
        "file_count": payload.get("file_count"),
        "archive_path": payload.get("archive_path"),
    }


def _release_smoke_summary(payload: dict[str, Any]) -> dict[str, Any]:
    archive = payload.get("archive") or {}
    diagnostics = payload.get("diagnostics") or {}
    return {
        "valid": payload.get("valid"),
        "archive_root": archive.get("archive_root"),
        "file_count": archive.get("file_count"),
        "diagnostics_valid": diagnostics.get("valid"),
    }


def _live_job_summary(payload: dict[str, Any]) -> dict[str, Any]:
    summary = _job_summary(payload)
    cp2k_output = payload.get("cp2k_output") or {}
    forces = cp2k_output.get("forces") or {}
    summary.update(
        {
            "total_energy_hartree": cp2k_output.get("total_energy_hartree"),
            "total_atomic_force": forces.get("total_atomic_force"),
            "force_unit": forces.get("unit"),
        }
    )
    return summary


def _tail(text: str, max_chars: int = 2000) -> str:
    if len(text) <= max_chars:
        return text
    return text[-max_chars:]


def _to_text(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


if __name__ == "__main__":
    raise SystemExit(main())

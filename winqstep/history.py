"""Job metadata discovery for WinQStep workspaces."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .cp2k_output import parse_cp2k_output_file, unavailable_output_summary


class HistoryError(ValueError):
    """Raised when a job history scan cannot be started."""


def list_job_history(
    workspace: str | Path,
    *,
    recursive: bool = True,
    limit: int | None = None,
) -> dict[str, Any]:
    """Scan a workspace for WinQStep metadata files."""
    workspace_path = Path(workspace).resolve()
    if not workspace_path.exists():
        raise HistoryError(f"workspace does not exist: {workspace_path}")
    if not workspace_path.is_dir():
        raise HistoryError(f"workspace is not a directory: {workspace_path}")

    jobs: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []
    metadata_paths = (
        workspace_path.rglob("*.winqstep.json")
        if recursive
        else workspace_path.glob("*.winqstep.json")
    )
    for metadata_path in sorted(metadata_paths):
        if not metadata_path.is_file():
            continue
        try:
            jobs.append(_history_item(metadata_path))
        except (OSError, json.JSONDecodeError, TypeError, ValueError) as exc:
            errors.append({"metadata_path": str(metadata_path), "error": str(exc)})

    jobs.sort(key=_job_sort_key, reverse=True)
    if limit is not None:
        jobs = jobs[: max(0, limit)]

    return {
        "workspace": str(workspace_path),
        "recursive": recursive,
        "jobs": jobs,
        "errors": errors,
    }


def _history_item(metadata_path: Path) -> dict[str, Any]:
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if not isinstance(metadata, dict):
        raise ValueError("metadata root must be an object")

    metadata_mtime = _utc_timestamp(metadata_path.stat().st_mtime)
    input_path = _metadata_path(metadata, "input")
    output_path = _metadata_path(metadata, "output")
    stdout_path = _metadata_path(metadata, "stdout")
    stderr_path = _metadata_path(metadata, "stderr")
    cp2k_output = _cp2k_output_summary(metadata, output_path)
    forces = _as_dict(cp2k_output.get("forces"))
    generated_artifacts = _generated_artifacts(metadata)

    return {
        "metadata_path": str(metadata_path),
        "metadata_mtime": metadata_mtime,
        "status": _optional_text(metadata.get("status"), "unknown"),
        "created_at": _optional_text(metadata.get("created_at")),
        "completed_at": _optional_text(metadata.get("completed_at")),
        "returncode": metadata.get("returncode"),
        "mode": _job_mode(metadata),
        "project_name": _project_name(metadata, input_path),
        "run_type": _run_type(metadata),
        "input_path": input_path,
        "output_path": output_path,
        "stdout_path": stdout_path,
        "stderr_path": stderr_path,
        "output_status": cp2k_output.get("status"),
        "warning_count": cp2k_output.get("warning_count"),
        "program_ended": cp2k_output.get("program_ended"),
        "total_energy_hartree": cp2k_output.get("total_energy_hartree"),
        "total_atomic_force": forces.get("total_atomic_force"),
        "force_unit": _optional_text(forces.get("unit")),
        "walltime_seconds": cp2k_output.get("walltime_seconds"),
        "scf": cp2k_output.get("scf"),
        "cell": cp2k_output.get("cell"),
        "generated_artifacts": generated_artifacts,
        "generated_artifact_count": len(generated_artifacts),
    }


def _metadata_path(metadata: dict[str, Any], key: str) -> str | None:
    files = _as_dict(metadata.get("files"))
    file_entry = _as_dict(files.get(key))
    path = _optional_text(file_entry.get("path"))
    if path:
        return path

    dry_windows = _as_dict(_as_dict(metadata.get("dry_run")).get("windows"))
    return _optional_text(dry_windows.get(f"{key}_path"))


def _generated_artifacts(metadata: dict[str, Any]) -> list[dict[str, Any]]:
    files = _as_dict(metadata.get("files"))
    generated = files.get("generated")
    if not isinstance(generated, list):
        return []
    artifacts: list[dict[str, Any]] = []
    for item in generated:
        data = _as_dict(item)
        path = _optional_text(data.get("path"))
        if not path:
            continue
        artifacts.append(
            {
                "path": path,
                "name": _optional_text(data.get("name")) or Path(path).name,
                "type": _optional_text(data.get("type")) or "generated",
                "size": data.get("size"),
            }
        )
    return artifacts


def _cp2k_output_summary(metadata: dict[str, Any], output_path: str | None) -> dict[str, Any]:
    summary = metadata.get("cp2k_output")
    if isinstance(summary, dict):
        return summary
    if output_path:
        return parse_cp2k_output_file(output_path)
    return unavailable_output_summary()


def _job_mode(metadata: dict[str, Any]) -> str:
    job = _as_dict(metadata.get("job"))
    mode = _optional_text(job.get("mode"))
    if mode:
        return mode
    if isinstance(metadata.get("workflow"), dict):
        return "workflow"
    if isinstance(metadata.get("quickstep"), dict):
        return "quickstep"
    return "unknown"


def _project_name(metadata: dict[str, Any], input_path: str | None) -> str | None:
    quickstep = _as_dict(metadata.get("quickstep"))
    project_name = _optional_text(quickstep.get("project_name"))
    if project_name:
        return project_name

    workflow_template = _as_dict(_as_dict(metadata.get("workflow")).get("template"))
    project_name = _optional_text(workflow_template.get("project_name"))
    if project_name:
        return project_name

    job = _as_dict(metadata.get("job"))
    input_stem = _optional_text(job.get("input_stem"))
    if input_stem:
        return input_stem

    if input_path:
        return Path(input_path).stem
    return None


def _run_type(metadata: dict[str, Any]) -> str | None:
    quickstep = _as_dict(metadata.get("quickstep"))
    run_type = _optional_text(quickstep.get("run_type"))
    if run_type:
        return run_type

    workflow_template = _as_dict(_as_dict(metadata.get("workflow")).get("template"))
    return _optional_text(workflow_template.get("run_type"))


def _job_sort_key(job: dict[str, Any]) -> str:
    return str(
        job.get("completed_at")
        or job.get("created_at")
        or job.get("metadata_mtime")
        or ""
    )


def _utc_timestamp(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp, timezone.utc).isoformat().replace("+00:00", "Z")


def _as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _optional_text(value: Any, default: str | None = None) -> str | None:
    if value is None:
        return default
    text = str(value).strip()
    return text or default

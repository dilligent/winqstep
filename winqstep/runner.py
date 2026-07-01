"""End-to-end QuickStep job preparation and execution."""

from __future__ import annotations

import json
import locale
import re
import subprocess
import time
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .cp2k_output import parse_cp2k_output_file
from .jobs import build_cp2k_job_dry_run
from .quickstep import quickstep_input_from_dict, render_quickstep_input


GENERATED_ARTIFACT_SUFFIXES = (".pdos", ".pdos_raw", ".cube", ".bs", ".band", ".bands")


class RunnerError(ValueError):
    """Raised when a WinQStep job cannot be prepared or run."""


Executor = Callable[[list[str]], Any]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def safe_job_stem(project_name: str) -> str:
    stem = re.sub(r"[^A-Za-z0-9_.-]+", "_", project_name.strip())
    return stem.strip("._") or "winqstep_job"


def default_executor(argv: list[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(argv, capture_output=True, check=False)


def load_json_file(path: str | Path) -> dict[str, Any]:
    with Path(path).open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise RunnerError("JSON file must contain an object")
    return data


def run_quickstep_job(
    *,
    config: dict[str, Any],
    quickstep_data: dict[str, Any],
    windows_job_dir: str | Path,
    input_name: str | None = None,
    mpi_ranks: int | None = None,
    execute: bool = True,
    executor: Executor | None = None,
) -> dict[str, Any]:
    """Render a QuickStep input, optionally run CP2K, and write metadata."""
    model = quickstep_input_from_dict(quickstep_data)
    rendered = render_quickstep_input(model)

    job_dir = Path(windows_job_dir).resolve()
    job_dir.mkdir(parents=True, exist_ok=True)

    filename = input_name or (safe_job_stem(model.project_name) + ".inp")
    if Path(filename).name != filename:
        raise RunnerError("input_name must be a file name, not a path")
    input_path = job_dir / filename
    input_path.write_text(rendered, encoding="utf-8")

    try:
        cp2k_command = str(config["cp2k_command"])
    except KeyError as exc:
        raise RunnerError("config missing cp2k_command") from exc

    dry_run = build_cp2k_job_dry_run(
        distro=_optional_str(config.get("distro")),
        cp2k_command=cp2k_command,
        windows_input_path=str(input_path),
        windows_job_dir=str(job_dir),
        cp2k_data_dir=_optional_str(config.get("cp2k_data_dir")),
        wsl_shell_prelude=_optional_str(config.get("wsl_shell_prelude")),
        mpirun_command=_optional_str(config.get("mpirun_command")),
        mpi_ranks=mpi_ranks,
    )
    if execute:
        _remove_previous_run_outputs(dry_run)
    dry_run["windows"]["generated_artifact_existing_paths"] = _current_generated_artifact_paths(dry_run)
    dry_run["windows"]["generated_artifact_scan_start"] = time.time()

    metadata_path = Path(dry_run["windows"]["metadata_path"])
    metadata: dict[str, Any] = {
        "status": "prepared",
        "created_at": utc_now(),
        "completed_at": None,
        "returncode": None,
        "quickstep": {
            "project_name": model.project_name,
            "run_type": model.run_type,
        },
        "dry_run": dry_run,
        "files": _job_files(dry_run),
        "wrapper": {
            "stdout": "",
            "stderr": "",
        },
    }
    _write_metadata_with_current_files(metadata_path, metadata, dry_run)

    if not execute:
        return metadata

    actual_executor = executor or default_executor
    completed = actual_executor(dry_run["command"]["argv"])
    returncode = int(getattr(completed, "returncode", 1))
    metadata["status"] = "succeeded" if returncode == 0 else "failed"
    metadata["completed_at"] = utc_now()
    metadata["returncode"] = returncode
    metadata["wrapper"] = {
        "stdout": _decode_process_text(getattr(completed, "stdout", "")),
        "stderr": _decode_process_text(getattr(completed, "stderr", "")),
    }
    _write_metadata_with_current_files(metadata_path, metadata, dry_run)
    return metadata


def run_existing_input_job(
    *,
    config: dict[str, Any],
    windows_input_path: str | Path,
    windows_job_dir: str | Path | None = None,
    mpi_ranks: int | None = None,
    execute: bool = True,
    executor: Executor | None = None,
) -> dict[str, Any]:
    """Run an existing CP2K input file without rewriting or copying it."""
    input_path = Path(windows_input_path).resolve()
    if not input_path.is_file():
        raise RunnerError(f"input file does not exist: {input_path}")

    job_dir = (
        Path(windows_job_dir).resolve()
        if windows_job_dir is not None
        else input_path.parent
    )
    job_dir.mkdir(parents=True, exist_ok=True)

    try:
        cp2k_command = str(config["cp2k_command"])
    except KeyError as exc:
        raise RunnerError("config missing cp2k_command") from exc

    dry_run = build_cp2k_job_dry_run(
        distro=_optional_str(config.get("distro")),
        cp2k_command=cp2k_command,
        windows_input_path=str(input_path),
        windows_job_dir=str(job_dir),
        cp2k_data_dir=_optional_str(config.get("cp2k_data_dir")),
        wsl_shell_prelude=_optional_str(config.get("wsl_shell_prelude")),
        mpirun_command=_optional_str(config.get("mpirun_command")),
        mpi_ranks=mpi_ranks,
    )
    if execute:
        _remove_previous_run_outputs(dry_run)
    dry_run["windows"]["generated_artifact_existing_paths"] = _current_generated_artifact_paths(dry_run)
    dry_run["windows"]["generated_artifact_scan_start"] = time.time()

    metadata_path = Path(dry_run["windows"]["metadata_path"])
    metadata: dict[str, Any] = {
        "status": "prepared",
        "created_at": utc_now(),
        "completed_at": None,
        "returncode": None,
        "job": {
            "mode": "existing_input",
            "input_stem": input_path.stem,
        },
        "dry_run": dry_run,
        "files": _job_files(dry_run),
        "wrapper": {
            "stdout": "",
            "stderr": "",
        },
    }
    _write_metadata_with_current_files(metadata_path, metadata, dry_run)

    if not execute:
        return metadata

    actual_executor = executor or default_executor
    completed = actual_executor(dry_run["command"]["argv"])
    returncode = int(getattr(completed, "returncode", 1))
    metadata["status"] = "succeeded" if returncode == 0 else "failed"
    metadata["completed_at"] = utc_now()
    metadata["returncode"] = returncode
    metadata["wrapper"] = {
        "stdout": _decode_process_text(getattr(completed, "stdout", "")),
        "stderr": _decode_process_text(getattr(completed, "stderr", "")),
    }
    _write_metadata_with_current_files(metadata_path, metadata, dry_run)
    return metadata


def mark_job_cancelled(
    metadata_path: str | Path,
    *,
    returncode: int | None = None,
    wrapper_stdout: str = "",
    wrapper_stderr: str = "",
) -> dict[str, Any]:
    """Mark an existing job metadata file as cancelled by the GUI."""
    path = Path(metadata_path).resolve()
    metadata = load_json_file(path)
    metadata["status"] = "cancelled"
    metadata["completed_at"] = utc_now()
    metadata["returncode"] = returncode
    metadata["wrapper"] = {
        "stdout": wrapper_stdout,
        "stderr": wrapper_stderr,
    }

    dry_run = metadata.get("dry_run")
    if isinstance(dry_run, dict) and isinstance(dry_run.get("windows"), dict):
        _write_metadata_with_current_files(path, metadata, dry_run)
    else:
        _write_metadata(path, metadata)
    return metadata


def _optional_str(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _job_files(dry_run: dict[str, Any]) -> dict[str, Any]:
    windows = dry_run["windows"]
    return {
        "input": _file_info(windows["input_path"]),
        "output": _file_info(windows["output_path"]),
        "stdout": _file_info(windows["stdout_path"]),
        "stderr": _file_info(windows["stderr_path"]),
        "metadata": _file_info(windows["metadata_path"]),
        "generated": _generated_artifacts(dry_run),
    }


def _remove_previous_run_outputs(dry_run: dict[str, Any]) -> None:
    windows = dry_run["windows"]
    for key in ("output_path", "stdout_path", "stderr_path"):
        Path(windows[key]).unlink(missing_ok=True)


def _current_generated_artifact_paths(dry_run: dict[str, Any]) -> list[str]:
    windows = dry_run["windows"]
    job_dir = Path(windows["job_dir"])
    if not job_dir.is_dir():
        return []
    return [
        str(path.resolve())
        for path in sorted(job_dir.iterdir(), key=lambda item: item.name.lower())
        if path.is_file() and _generated_artifact_type(path) is not None
    ]


def _file_info(path: str) -> dict[str, Any]:
    file_path = Path(path)
    exists = file_path.exists()
    return {
        "path": str(file_path),
        "exists": exists,
        "size": file_path.stat().st_size if exists else None,
    }


def _generated_artifacts(dry_run: dict[str, Any]) -> list[dict[str, Any]]:
    windows = dry_run["windows"]
    job_dir = Path(windows["job_dir"])
    if not job_dir.is_dir():
        return []
    known_paths = {
        Path(windows[key]).resolve()
        for key in ("input_path", "output_path", "stdout_path", "stderr_path", "metadata_path")
    }
    scan_start = _float_or_none(windows.get("generated_artifact_scan_start"))
    existing_generated_paths = {
        str(Path(path).resolve())
        for path in windows.get("generated_artifact_existing_paths", [])
        if path
    }
    artifacts: list[dict[str, Any]] = []
    for path in sorted(job_dir.iterdir(), key=lambda item: item.name.lower()):
        resolved_path = path.resolve()
        if not path.is_file() or resolved_path in known_paths:
            continue
        if str(resolved_path) in existing_generated_paths:
            continue
        artifact_type = _generated_artifact_type(path)
        if artifact_type is None:
            continue
        if scan_start is not None and path.stat().st_mtime < (scan_start - 1.0):
            continue
        info = _file_info(str(path))
        info["name"] = path.name
        info["type"] = artifact_type
        artifacts.append(info)
    return artifacts


def _generated_artifact_type(path: Path) -> str | None:
    name = path.name.lower()
    if name.endswith(".pdos_raw"):
        return "pdos_raw"
    if name.endswith(".pdos"):
        return "pdos"
    if name.endswith(".cube"):
        if "electron_density" in name:
            return "electron_density_cube"
        if "spin_density" in name:
            return "spin_density_cube"
        if "v_hartree" in name:
            return "hartree_potential_cube"
        return "cube"
    if name.endswith((".bs", ".band", ".bands")):
        return "band_structure"
    if any(name.endswith(suffix) for suffix in GENERATED_ARTIFACT_SUFFIXES):
        return "generated"
    return None


def _float_or_none(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _write_metadata(path: Path, metadata: dict[str, Any]) -> None:
    path.write_text(_metadata_text(metadata), encoding="utf-8", newline="\n")


def _write_metadata_with_current_files(
    path: Path, metadata: dict[str, Any], dry_run: dict[str, Any]
) -> None:
    metadata["files"] = _job_files(dry_run)
    metadata["cp2k_output"] = parse_cp2k_output_file(dry_run["windows"]["output_path"])
    metadata_file = metadata["files"]["metadata"]
    for _ in range(10):
        text = _metadata_text(metadata)
        size = len(text.encode("utf-8"))
        if metadata_file.get("exists") is True and metadata_file.get("size") == size:
            path.write_text(text, encoding="utf-8", newline="\n")
            return
        metadata_file["exists"] = True
        metadata_file["size"] = size
    path.write_text(_metadata_text(metadata), encoding="utf-8", newline="\n")


def _metadata_text(metadata: dict[str, Any]) -> str:
    return json.dumps(metadata, ensure_ascii=False, indent=2) + "\n"


def _decode_process_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        decoded = _decode_process_bytes(value)
    else:
        decoded = str(value)
    return decoded.replace("\x00", "").strip()


def _decode_process_bytes(value: bytes) -> str:
    candidates: list[str] = []
    if value.startswith((b"\xff\xfe", b"\xfe\xff")) or value.count(b"\x00") > len(value) // 8:
        candidates.extend(["utf-16", "utf-16-le"])
    candidates.extend(["utf-8-sig", locale.getpreferredencoding(False), "gbk"])

    for encoding in candidates:
        try:
            return value.decode(encoding)
        except UnicodeDecodeError:
            continue
    return value.decode("utf-8", errors="replace")

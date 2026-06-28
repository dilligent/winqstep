"""End-to-end QuickStep job preparation and execution."""

from __future__ import annotations

import json
import locale
import re
import subprocess
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .jobs import build_cp2k_job_dry_run
from .quickstep import quickstep_input_from_dict, render_quickstep_input


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
    _write_metadata(metadata_path, metadata)
    metadata["files"] = _job_files(dry_run)
    _write_metadata(metadata_path, metadata)

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
    metadata["files"] = _job_files(dry_run)
    _write_metadata(metadata_path, metadata)
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
    }


def _remove_previous_run_outputs(dry_run: dict[str, Any]) -> None:
    windows = dry_run["windows"]
    for key in ("output_path", "stdout_path", "stderr_path"):
        Path(windows[key]).unlink(missing_ok=True)


def _file_info(path: str) -> dict[str, Any]:
    file_path = Path(path)
    exists = file_path.exists()
    return {
        "path": str(file_path),
        "exists": exists,
        "size": file_path.stat().st_size if exists else None,
    }


def _write_metadata(path: Path, metadata: dict[str, Any]) -> None:
    path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


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

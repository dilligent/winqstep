"""Batch execution helpers for existing CP2K input files."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Iterable

from .runner import Executor, RunnerError, run_existing_input_job, safe_job_stem, utc_now


BATCH_SUMMARY_NAME = "batch.winqstep-batch.json"
JOB_LAYOUTS = {"subdirs", "input-dirs"}


def resolve_existing_input_batch_inputs(
    *,
    input_paths: Iterable[str | Path] = (),
    input_dirs: Iterable[str | Path] = (),
    input_list_paths: Iterable[str | Path] = (),
    glob_pattern: str = "*.inp",
) -> list[Path]:
    """Resolve explicit, listed, and directory-globbed CP2K input paths."""
    resolved: list[Path] = []

    for input_path in input_paths:
        resolved.append(Path(input_path).resolve())

    for list_path in input_list_paths:
        resolved.extend(_read_input_list(list_path))

    for input_dir in input_dirs:
        directory = Path(input_dir).resolve()
        if not directory.is_dir():
            raise RunnerError(f"input directory does not exist: {directory}")
        resolved.extend(
            path.resolve()
            for path in sorted(directory.glob(glob_pattern), key=lambda item: item.name.lower())
            if path.is_file()
        )

    deduped: list[Path] = []
    seen: set[str] = set()
    for path in resolved:
        key = str(path).casefold()
        if key in seen:
            continue
        seen.add(key)
        deduped.append(path)

    if not deduped:
        raise RunnerError("no existing input files were selected")
    return deduped


def run_existing_input_batch(
    *,
    config: dict[str, Any],
    input_paths: Iterable[str | Path],
    windows_job_dir: str | Path,
    mpi_ranks: int | None = None,
    execute: bool = True,
    stop_on_failure: bool = False,
    job_layout: str = "subdirs",
    executor: Executor | None = None,
) -> dict[str, Any]:
    """Run existing CP2K input files serially and write a batch summary."""
    if job_layout not in JOB_LAYOUTS:
        raise RunnerError("job_layout must be subdirs or input-dirs")

    inputs = [Path(path).resolve() for path in input_paths]
    if not inputs:
        raise RunnerError("no existing input files were selected")

    batch_dir = Path(windows_job_dir).resolve()
    batch_dir.mkdir(parents=True, exist_ok=True)
    summary_path = batch_dir / BATCH_SUMMARY_NAME
    created_at = utc_now()
    summary: dict[str, Any] = {
        "mode": "existing_input_batch",
        "status": "running",
        "created_at": created_at,
        "completed_at": None,
        "execute": execute,
        "prepare_only": not execute,
        "stop_on_failure": stop_on_failure,
        "stopped_on_failure": False,
        "job_layout": job_layout,
        "input_count": len(inputs),
        "item_count": 0,
        "prepared_count": 0,
        "succeeded_count": 0,
        "failed_count": 0,
        "error_count": 0,
        "job_dir": str(batch_dir),
        "summary_path": str(summary_path),
        "items": [],
    }
    _write_batch_summary(summary_path, summary)

    used_job_names: set[str] = set()
    for index, input_path in enumerate(inputs, start=1):
        item_job_dir = _job_dir_for_input(
            input_path=input_path,
            batch_dir=batch_dir,
            used_job_names=used_job_names,
            job_layout=job_layout,
        )
        try:
            metadata = run_existing_input_job(
                config=config,
                windows_input_path=input_path,
                windows_job_dir=item_job_dir,
                mpi_ranks=mpi_ranks,
                execute=execute,
                executor=executor,
            )
            item = _item_from_metadata(index, input_path, item_job_dir, metadata)
        except (OSError, RunnerError, ValueError) as exc:
            item = {
                "index": index,
                "input_path": str(input_path),
                "job_dir": str(item_job_dir) if item_job_dir is not None else str(input_path.parent),
                "status": "error",
                "returncode": None,
                "metadata_path": None,
                "output_path": None,
                "stdout_path": None,
                "stderr_path": None,
                "generated_artifact_count": 0,
                "error": str(exc),
            }
        summary["items"].append(item)
        _update_batch_counts(summary)
        if stop_on_failure and item["status"] not in {"prepared", "succeeded"}:
            summary["stopped_on_failure"] = True
            break
        _write_batch_summary(summary_path, summary)

    summary["completed_at"] = utc_now()
    summary["status"] = _batch_status(summary)
    _update_batch_counts(summary)
    _write_batch_summary(summary_path, summary)
    return summary


def _read_input_list(input_list_path: str | Path) -> list[Path]:
    path = Path(input_list_path).resolve()
    if not path.is_file():
        raise RunnerError(f"input list file does not exist: {path}")
    inputs: list[Path] = []
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        input_path = Path(line)
        if not input_path.is_absolute():
            input_path = path.parent / input_path
        inputs.append(input_path.resolve())
    return inputs


def _job_dir_for_input(
    *,
    input_path: Path,
    batch_dir: Path,
    used_job_names: set[str],
    job_layout: str,
) -> Path | None:
    if job_layout == "input-dirs":
        return None

    base_name = safe_job_stem(input_path.stem)
    candidate = base_name
    if candidate.casefold() in used_job_names:
        digest = hashlib.sha1(str(input_path).encode("utf-8")).hexdigest()[:8]
        candidate = f"{base_name}-{digest}"
        ordinal = 2
        while candidate.casefold() in used_job_names:
            candidate = f"{base_name}-{digest}-{ordinal}"
            ordinal += 1
    used_job_names.add(candidate.casefold())
    return batch_dir / candidate


def _item_from_metadata(
    index: int,
    input_path: Path,
    job_dir: Path | None,
    metadata: dict[str, Any],
) -> dict[str, Any]:
    files = metadata.get("files") if isinstance(metadata.get("files"), dict) else {}
    generated = files.get("generated") if isinstance(files.get("generated"), list) else []
    resolved_job_dir = job_dir
    if resolved_job_dir is None:
        dry_windows = metadata.get("dry_run", {}).get("windows", {})
        job_dir_text = dry_windows.get("job_dir") if isinstance(dry_windows, dict) else None
        resolved_job_dir = Path(job_dir_text) if job_dir_text else input_path.parent
    return {
        "index": index,
        "input_path": str(input_path),
        "job_dir": str(resolved_job_dir),
        "status": metadata.get("status"),
        "returncode": metadata.get("returncode"),
        "metadata_path": _file_path(files, "metadata"),
        "output_path": _file_path(files, "output"),
        "stdout_path": _file_path(files, "stdout"),
        "stderr_path": _file_path(files, "stderr"),
        "generated_artifact_count": len(generated),
        "error": None,
    }


def _file_path(files: dict[str, Any], key: str) -> str | None:
    entry = files.get(key)
    if not isinstance(entry, dict):
        return None
    path = entry.get("path")
    return str(path) if path else None


def _update_batch_counts(summary: dict[str, Any]) -> None:
    items = summary["items"]
    summary["item_count"] = len(items)
    summary["prepared_count"] = sum(1 for item in items if item["status"] == "prepared")
    summary["succeeded_count"] = sum(1 for item in items if item["status"] == "succeeded")
    summary["failed_count"] = sum(1 for item in items if item["status"] == "failed")
    summary["error_count"] = sum(1 for item in items if item["status"] == "error")


def _batch_status(summary: dict[str, Any]) -> str:
    if summary.get("stopped_on_failure"):
        return "stopped_on_failure"
    items = summary["items"]
    if any(item["status"] in {"failed", "error"} for item in items):
        return "completed_with_errors"
    if summary["execute"]:
        return "succeeded"
    return "prepared"


def _write_batch_summary(path: Path, summary: dict[str, Any]) -> None:
    path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

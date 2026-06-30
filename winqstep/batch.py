"""Batch execution helpers for existing CP2K input files."""

from __future__ import annotations

import hashlib
import json
import subprocess
import time
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Iterable

from .runner import (
    Executor,
    RunnerError,
    mark_job_cancelled,
    run_existing_input_job,
    safe_job_stem,
    utc_now,
)


BATCH_SUMMARY_NAME = "batch.winqstep-batch.json"
JOB_LAYOUTS = {"subdirs", "input-dirs"}
TERMINAL_STATUSES = {"succeeded", "failed", "error", "skipped", "cancelled"}
RUNNABLE_RESUME_STATUSES = {"queued", "prepared", "running", "cancel_requested"}
MUTABLE_IDLE_STATUSES = {"queued", "prepared", "succeeded", "failed", "error", "skipped", "cancelled"}


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
    resume: bool = False,
    executor: Executor | None = None,
) -> dict[str, Any]:
    """Run existing CP2K input files serially and write a batch summary."""
    if job_layout not in JOB_LAYOUTS:
        raise RunnerError("job_layout must be subdirs or input-dirs")

    batch_dir = Path(windows_job_dir).resolve()
    batch_dir.mkdir(parents=True, exist_ok=True)
    summary_path = batch_dir / BATCH_SUMMARY_NAME

    if resume:
        summary = load_existing_input_batch_summary(summary_path)
        _prepare_summary_for_resume(summary, execute=execute, stop_on_failure=stop_on_failure)
        items = summary["items"]
    else:
        inputs = [Path(path).resolve() for path in input_paths]
        if not inputs:
            raise RunnerError("no existing input files were selected")
        summary = _new_batch_summary(
            inputs=inputs,
            batch_dir=batch_dir,
            summary_path=summary_path,
            execute=execute,
            stop_on_failure=stop_on_failure,
            job_layout=job_layout,
        )
        items = summary["items"]

    _write_batch_summary(summary_path, summary)

    planned_indexes = [int(item["index"]) for item in items]
    for item_index in planned_indexes:
        summary = load_existing_input_batch_summary(summary_path)
        item = _find_item(summary, item_index)
        if not _should_process_item(item, execute=execute, resume=resume):
            _update_batch_counts(summary)
            _write_batch_summary(summary_path, summary)
            continue

        input_path = Path(str(item["input_path"])).resolve()
        item_job_dir = _job_dir_arg_for_item(summary, item)
        _mark_item_started(item, execute=execute)
        _update_batch_counts(summary)
        _write_batch_summary(summary_path, summary)

        cancelled_state = {"cancelled": False}
        actual_executor = executor
        if execute and executor is None:
            actual_executor = _cancellable_executor(summary_path, int(item["index"]), cancelled_state)

        try:
            metadata = run_existing_input_job(
                config=config,
                windows_input_path=input_path,
                windows_job_dir=item_job_dir,
                mpi_ranks=mpi_ranks,
                execute=execute,
                executor=actual_executor,
            )
            if cancelled_state["cancelled"]:
                metadata_path = _file_path(metadata.get("files", {}), "metadata")
                if metadata_path:
                    metadata = mark_job_cancelled(metadata_path, returncode=metadata.get("returncode"))
                metadata["status"] = "cancelled"
            _replace_summary_item(
                summary,
                _item_from_metadata(item, input_path, item_job_dir, metadata),
            )
        except (OSError, RunnerError, ValueError) as exc:
            _replace_summary_item(summary, _error_item(item, input_path, item_job_dir, str(exc)))
        _update_batch_counts(summary)
        current_item = _find_item(summary, item_index)
        if stop_on_failure and current_item["status"] in {"failed", "error"}:
            summary["stopped_on_failure"] = True
            _write_batch_summary(summary_path, summary)
            break
        _write_batch_summary(summary_path, summary)

    summary = load_existing_input_batch_summary(summary_path)
    summary["completed_at"] = utc_now()
    summary["status"] = _batch_status(summary)
    _update_batch_counts(summary)
    _write_batch_summary(summary_path, summary)
    return summary


def load_existing_input_batch_summary(summary_path: str | Path) -> dict[str, Any]:
    """Load and normalize an existing batch summary."""
    path = Path(summary_path).resolve()
    if not path.is_file():
        raise RunnerError(f"batch summary does not exist: {path}")
    with path.open("r", encoding="utf-8") as handle:
        summary = json.load(handle)
    if not isinstance(summary, dict) or summary.get("mode") != "existing_input_batch":
        raise RunnerError("batch summary is not an existing-input batch")
    _normalize_batch_summary(summary, path)
    return summary


def update_existing_input_batch_item(
    summary_path: str | Path,
    *,
    index: int,
    action: str,
) -> dict[str, Any]:
    """Apply a queue action to one item in an existing batch summary."""
    path = Path(summary_path).resolve()
    summary = load_existing_input_batch_summary(path)
    item = _find_item(summary, index)
    if action == "skip":
        _skip_item(item)
    elif action == "rerun":
        _queue_item_for_rerun(item)
        summary["execute"] = True
        summary["prepare_only"] = False
        summary["completed_at"] = None
        summary["stopped_on_failure"] = False
    elif action == "cancel":
        _cancel_item(item)
    else:
        raise RunnerError("action must be skip, rerun, or cancel")

    _update_batch_counts(summary)
    summary["status"] = _batch_status(summary)
    _write_batch_summary(path, summary)
    return summary


def _new_batch_summary(
    *,
    inputs: list[Path],
    batch_dir: Path,
    summary_path: Path,
    execute: bool,
    stop_on_failure: bool,
    job_layout: str,
) -> dict[str, Any]:
    used_job_names: set[str] = set()
    items = []
    for index, input_path in enumerate(inputs, start=1):
        item_job_dir = _job_dir_for_input(
            input_path=input_path,
            batch_dir=batch_dir,
            used_job_names=used_job_names,
            job_layout=job_layout,
        )
        items.append(_new_queue_item(index, input_path, item_job_dir))

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
        "item_count": len(items),
        "completed_count": 0,
        "queued_count": len(items),
        "running_count": 0,
        "prepared_count": 0,
        "skipped_count": 0,
        "cancelled_count": 0,
        "succeeded_count": 0,
        "failed_count": 0,
        "error_count": 0,
        "job_dir": str(batch_dir),
        "summary_path": str(summary_path),
        "items": items,
    }
    _update_batch_counts(summary)
    return summary


def _prepare_summary_for_resume(
    summary: dict[str, Any],
    *,
    execute: bool,
    stop_on_failure: bool,
) -> None:
    summary["status"] = "running"
    summary["execute"] = execute
    summary["prepare_only"] = not execute
    summary["stop_on_failure"] = stop_on_failure
    summary["stopped_on_failure"] = False
    summary["completed_at"] = None
    summary["resumed_at"] = utc_now()
    summary["resume_count"] = int(summary.get("resume_count") or 0) + 1
    for item in summary["items"]:
        if item.get("status") == "running":
            item["status"] = "queued"
            item["started_at"] = None
            item["completed_at"] = None
            item["error"] = None
        elif item.get("status") == "cancel_requested":
            item["status"] = "cancelled"
            item["completed_at"] = utc_now()
            item["error"] = "Cancelled by user."
    _update_batch_counts(summary)


def _new_queue_item(index: int, input_path: Path, job_dir: Path | None) -> dict[str, Any]:
    return {
        "index": index,
        "input_path": str(input_path),
        "job_dir": str(job_dir) if job_dir is not None else str(input_path.parent),
        "status": "queued",
        "attempt": 0,
        "started_at": None,
        "completed_at": None,
        "returncode": None,
        "metadata_path": None,
        "output_path": None,
        "stdout_path": None,
        "stderr_path": None,
        "generated_artifact_count": 0,
        "error": None,
    }


def _read_input_list(input_list_path: str | Path) -> list[Path]:
    path = Path(input_list_path).resolve()
    if not path.is_file():
        raise RunnerError(f"input list file does not exist: {path}")
    inputs: list[Path] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
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


def _job_dir_arg_for_item(summary: dict[str, Any], item: dict[str, Any]) -> Path | None:
    if summary.get("job_layout") == "input-dirs":
        return None
    return Path(str(item["job_dir"])).resolve()


def _should_process_item(item: dict[str, Any], *, execute: bool, resume: bool) -> bool:
    status = str(item.get("status") or "")
    if not execute:
        return status == "queued"
    if resume:
        return status in RUNNABLE_RESUME_STATUSES
    return status == "queued"


def _mark_item_started(item: dict[str, Any], *, execute: bool) -> None:
    item["status"] = "running" if execute else "prepared"
    item["started_at"] = utc_now()
    item["completed_at"] = None
    item["error"] = None
    if execute:
        item["attempt"] = int(item.get("attempt") or 0) + 1


def _item_from_metadata(
    original_item: dict[str, Any],
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
    item = dict(original_item)
    item.update({
        "index": int(original_item["index"]),
        "input_path": str(input_path),
        "job_dir": str(resolved_job_dir),
        "status": metadata.get("status"),
        "started_at": original_item.get("started_at"),
        "completed_at": metadata.get("completed_at") or utc_now(),
        "returncode": metadata.get("returncode"),
        "metadata_path": _file_path(files, "metadata"),
        "output_path": _file_path(files, "output"),
        "stdout_path": _file_path(files, "stdout"),
        "stderr_path": _file_path(files, "stderr"),
        "generated_artifact_count": len(generated),
        "error": None,
    })
    return item


def _error_item(
    original_item: dict[str, Any],
    input_path: Path,
    job_dir: Path | None,
    error: str,
) -> dict[str, Any]:
    item = dict(original_item)
    item.update({
        "input_path": str(input_path),
        "job_dir": str(job_dir) if job_dir is not None else str(input_path.parent),
        "status": "error",
        "completed_at": utc_now(),
        "returncode": None,
        "metadata_path": item.get("metadata_path"),
        "output_path": item.get("output_path"),
        "stdout_path": item.get("stdout_path"),
        "stderr_path": item.get("stderr_path"),
        "generated_artifact_count": int(item.get("generated_artifact_count") or 0),
        "error": error,
    })
    return item


def _file_path(files: dict[str, Any], key: str) -> str | None:
    entry = files.get(key)
    if not isinstance(entry, dict):
        return None
    path = entry.get("path")
    return str(path) if path else None


def _find_item(summary: dict[str, Any], index: int) -> dict[str, Any]:
    for item in summary["items"]:
        if int(item.get("index") or 0) == index:
            return item
    raise RunnerError(f"batch item was not found: {index}")


def _replace_summary_item(summary: dict[str, Any], replacement: dict[str, Any]) -> None:
    replacement_index = int(replacement["index"])
    for position, item in enumerate(summary["items"]):
        if int(item.get("index") or 0) == replacement_index:
            summary["items"][position] = replacement
            return
    raise RunnerError(f"batch item was not found: {replacement_index}")


def _skip_item(item: dict[str, Any]) -> None:
    status = str(item.get("status") or "")
    if status in {"running", "cancel_requested"}:
        raise RunnerError("running batch items cannot be skipped; cancel the item instead")
    item["status"] = "skipped"
    item["completed_at"] = utc_now()
    item["returncode"] = None
    item["error"] = "Skipped by user."


def _queue_item_for_rerun(item: dict[str, Any]) -> None:
    status = str(item.get("status") or "")
    if status in {"running", "cancel_requested"}:
        raise RunnerError("running batch items cannot be queued for rerun")
    if status not in MUTABLE_IDLE_STATUSES:
        raise RunnerError(f"batch item cannot be queued for rerun from status: {status}")
    item["status"] = "queued"
    item["started_at"] = None
    item["completed_at"] = None
    item["returncode"] = None
    item["metadata_path"] = None
    item["output_path"] = None
    item["stdout_path"] = None
    item["stderr_path"] = None
    item["generated_artifact_count"] = 0
    item["error"] = None


def _cancel_item(item: dict[str, Any]) -> None:
    status = str(item.get("status") or "")
    if status == "running":
        item["status"] = "cancel_requested"
        item["error"] = "Cancellation requested by user."
        return
    if status == "cancel_requested":
        return
    if status not in MUTABLE_IDLE_STATUSES:
        raise RunnerError(f"batch item cannot be cancelled from status: {status}")
    item["status"] = "cancelled"
    item["completed_at"] = utc_now()
    item["returncode"] = None
    item["error"] = "Cancelled by user."


def _normalize_batch_summary(summary: dict[str, Any], path: Path) -> None:
    items = summary.get("items")
    if not isinstance(items, list):
        raise RunnerError("batch summary items must be a list")
    normalized_items = []
    for fallback_index, item in enumerate(items, start=1):
        if not isinstance(item, dict):
            raise RunnerError("batch summary item must be an object")
        input_path = item.get("input_path")
        if not input_path:
            raise RunnerError("batch summary item is missing input_path")
        normalized = _new_queue_item(
            int(item.get("index") or fallback_index),
            Path(str(input_path)).resolve(),
            Path(str(item.get("job_dir") or Path(str(input_path)).parent)).resolve(),
        )
        normalized.update(item)
        normalized["index"] = int(normalized["index"])
        normalized["status"] = str(normalized.get("status") or "queued")
        normalized_items.append(normalized)
    summary["items"] = normalized_items
    summary["summary_path"] = str(path)
    summary["job_dir"] = str(path.parent)
    summary.setdefault("job_layout", "subdirs")
    summary.setdefault("execute", not bool(summary.get("prepare_only")))
    summary.setdefault("prepare_only", not bool(summary.get("execute")))
    summary.setdefault("stop_on_failure", False)
    summary.setdefault("stopped_on_failure", False)
    summary["input_count"] = int(summary.get("input_count") or len(normalized_items))
    _update_batch_counts(summary)


def _item_cancel_requested(summary_path: Path, index: int) -> bool:
    try:
        summary = load_existing_input_batch_summary(summary_path)
        item = _find_item(summary, index)
    except (OSError, RunnerError, ValueError, json.JSONDecodeError):
        return False
    return str(item.get("status") or "") == "cancel_requested"


def _cancellable_executor(
    summary_path: Path,
    index: int,
    cancelled_state: dict[str, bool],
) -> Executor:
    def execute(argv: list[str]) -> SimpleNamespace:
        process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        while process.poll() is None:
            if _item_cancel_requested(summary_path, index):
                cancelled_state["cancelled"] = True
                process.terminate()
                try:
                    stdout, stderr = process.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    stdout, stderr = process.communicate()
                stderr = (stderr or b"") + b"\nWinQStep batch item cancellation requested.\n"
                return SimpleNamespace(returncode=process.returncode, stdout=stdout, stderr=stderr)
            time.sleep(0.5)
        stdout, stderr = process.communicate()
        return SimpleNamespace(returncode=process.returncode, stdout=stdout, stderr=stderr)

    return execute


def _update_batch_counts(summary: dict[str, Any]) -> None:
    items = summary["items"]
    summary["item_count"] = len(items)
    summary["queued_count"] = sum(1 for item in items if item["status"] == "queued")
    summary["running_count"] = sum(1 for item in items if item["status"] in {"running", "cancel_requested"})
    summary["prepared_count"] = sum(1 for item in items if item["status"] == "prepared")
    summary["skipped_count"] = sum(1 for item in items if item["status"] == "skipped")
    summary["cancelled_count"] = sum(1 for item in items if item["status"] == "cancelled")
    summary["succeeded_count"] = sum(1 for item in items if item["status"] == "succeeded")
    summary["failed_count"] = sum(1 for item in items if item["status"] == "failed")
    summary["error_count"] = sum(1 for item in items if item["status"] == "error")
    summary["completed_count"] = sum(1 for item in items if item["status"] in TERMINAL_STATUSES)


def _batch_status(summary: dict[str, Any]) -> str:
    items = summary["items"]
    if any(item["status"] in {"running", "cancel_requested"} for item in items):
        return "running"
    if summary.get("stopped_on_failure"):
        return "stopped_on_failure"
    if summary["execute"] and any(item["status"] in {"queued", "prepared"} for item in items):
        return "pending"
    if any(item["status"] in {"failed", "error"} for item in items):
        return "completed_with_errors"
    if summary["execute"]:
        if any(item["status"] in {"skipped", "cancelled"} for item in items):
            return "completed_with_skips"
        return "succeeded"
    return "prepared"


def _write_batch_summary(path: Path, summary: dict[str, Any]) -> None:
    path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

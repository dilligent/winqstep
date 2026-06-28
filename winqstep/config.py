"""WinQStep configuration loading, validation, and saving."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


CONFIG_KEY_ORDER = (
    "distro",
    "cp2k_command",
    "mpirun_command",
    "cp2k_data_dir",
    "default_windows_workspace",
    "wsl_shell_prelude",
    "timeout",
)
CONFIG_KEYS = set(CONFIG_KEY_ORDER)
WINDOWS_DRIVE_RE = re.compile(r"^[A-Za-z]:[\\/]")


class ConfigError(ValueError):
    """Raised when a WinQStep config cannot be loaded or saved."""


def load_config(path: str | Path | None) -> dict[str, Any]:
    """Load and normalize a WinQStep JSON config file."""
    if not path:
        return {}

    config_path = Path(path)
    with config_path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    return normalize_config(data)


def save_config(path: str | Path, data: dict[str, Any]) -> dict[str, Any]:
    """Validate and save a config file with stable key order and UTF-8 text."""
    config = normalize_config(data)
    Path(path).write_text(
        json.dumps(config, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return config


def normalize_config(data: dict[str, Any]) -> dict[str, Any]:
    """Return a config object ordered by the public schema."""
    validation = validate_config(data)
    if not validation["valid"]:
        raise ConfigError("; ".join(validation["errors"]))
    normalized = validation["config"]
    return {
        key: normalized[key]
        for key in CONFIG_KEY_ORDER
        if key in normalized and normalized[key] is not None
    }


def validate_config(
    data: dict[str, Any],
    *,
    require_execution: bool = False,
) -> dict[str, Any]:
    """Validate config shape and return normalized fields plus diagnostics."""
    errors: list[str] = []
    warnings: list[str] = []
    normalized: dict[str, Any] = {}

    if not isinstance(data, dict):
        return {
            "valid": False,
            "errors": ["config file must contain a JSON object"],
            "warnings": [],
            "config": {},
        }

    unknown_keys = sorted(set(data) - CONFIG_KEYS)
    if unknown_keys:
        errors.append("unknown config key(s): " + ", ".join(unknown_keys))

    for key in CONFIG_KEY_ORDER:
        if key not in data:
            continue
        value = data[key]
        if key == "timeout":
            normalized_timeout = _normalize_timeout(value, errors)
            if normalized_timeout is not None:
                normalized[key] = normalized_timeout
            continue
        normalized[key] = _normalize_string(key, value, errors)

    _validate_cp2k_paths(normalized, errors, require_execution=require_execution)
    if not normalized.get("distro"):
        warnings.append("No WSL distro is configured; WinQStep will rely on the WSL default.")
    if not normalized.get("mpirun_command"):
        warnings.append("No MPI launcher is configured; jobs will run CP2K directly.")
    if not normalized.get("default_windows_workspace"):
        warnings.append("No default Windows workspace is configured.")

    return {
        "valid": not errors,
        "errors": errors,
        "warnings": warnings,
        "config": {
            key: normalized[key]
            for key in CONFIG_KEY_ORDER
            if key in normalized and normalized[key] is not None
        },
    }


def config_value(config: dict[str, Any], key: str, default: Any = None) -> Any:
    """Return config value while treating an empty string as missing."""
    value = config.get(key, default)
    if value == "":
        return default
    return value


def _normalize_string(key: str, value: Any, errors: list[str]) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        errors.append(f"{key} must be a string")
        return ""
    return value.strip()


def _normalize_timeout(value: Any, errors: list[str]) -> int | None:
    if value is None or value == "":
        return None
    if isinstance(value, bool):
        errors.append("timeout must be a positive integer")
        return None
    try:
        timeout = int(value)
    except (TypeError, ValueError):
        errors.append("timeout must be a positive integer")
        return None
    if timeout <= 0:
        errors.append("timeout must be a positive integer")
        return None
    return timeout


def _validate_cp2k_paths(
    config: dict[str, Any],
    errors: list[str],
    *,
    require_execution: bool,
) -> None:
    cp2k_command = str(config.get("cp2k_command") or "")
    cp2k_data_dir = str(config.get("cp2k_data_dir") or "")
    if require_execution and not cp2k_command:
        errors.append("cp2k_command is required before previewing or running a job")
    if require_execution and not cp2k_data_dir:
        errors.append("cp2k_data_dir is required before previewing or running a job")

    for key in ("cp2k_command", "mpirun_command", "cp2k_data_dir"):
        value = str(config.get(key) or "")
        if WINDOWS_DRIVE_RE.match(value) or "\\" in value:
            errors.append(f"{key} must be a WSL command or POSIX path, not a Windows path")

    if cp2k_data_dir and not cp2k_data_dir.startswith("/"):
        errors.append("cp2k_data_dir must be an absolute WSL path")

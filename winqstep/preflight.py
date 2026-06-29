"""Preflight validation for GUI workflow and existing-input jobs."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from .structures import StructureImportError, import_structure
from .template import TemplateError, load_template
from .workflow import WorkflowError, build_quickstep_data


class PreflightError(ValueError):
    """Raised when preflight validation cannot be started."""


DATA_FILE_RE = {
    "basis": re.compile(r"^\s*BASIS_SET_FILE_NAME\s+(\S+)", re.IGNORECASE | re.MULTILINE),
    "potential": re.compile(r"^\s*POTENTIAL_FILE_NAME\s+(\S+)", re.IGNORECASE | re.MULTILINE),
}


def validate_workflow_preflight(
    *,
    template_path: str | Path,
    structure_path: str | Path,
    project_name: str | None = None,
    cache_path: str | Path | None = None,
    warn_missing_cache: bool = True,
) -> dict[str, Any]:
    """Validate a workflow template and structure before writing job files."""
    errors: list[str] = []
    warnings: list[str] = []
    template: dict[str, Any] = {}
    imported: dict[str, Any] = {}
    quickstep_data: dict[str, Any] | None = None

    try:
        template = load_template(template_path)
    except (OSError, TemplateError, json.JSONDecodeError, ValueError) as exc:
        errors.append(f"template: {exc}")

    try:
        imported = import_structure(structure_path)
    except (OSError, StructureImportError, ValueError) as exc:
        errors.append(f"structure: {exc}")

    if template and imported:
        try:
            quickstep_data = build_quickstep_data(template, imported, project_name=project_name)
        except WorkflowError as exc:
            errors.append(str(exc))

    cache = _load_data_cache(cache_path, warnings, warn_missing_cache=warn_missing_cache)
    if template:
        _validate_template_data_files(template, cache, warnings)
    if quickstep_data is not None:
        _validate_kind_labels(quickstep_data["structure"]["kinds"], cache, warnings)

    return {
        "mode": "workflow",
        "valid": not errors,
        "errors": errors,
        "warnings": warnings,
        "template": {
            "path": str(Path(template_path).resolve()),
            "kind_elements": _template_elements(template),
        },
        "structure": _structure_summary(structure_path, imported),
        "data_cache": _cache_summary(cache_path, cache),
    }


def validate_existing_input_preflight(
    *,
    input_path: str | Path,
    cache_path: str | Path | None = None,
    warn_missing_cache: bool = True,
) -> dict[str, Any]:
    """Validate an existing input path and warn about obvious data-file issues."""
    errors: list[str] = []
    warnings: list[str] = []
    path = Path(input_path).resolve()
    references = {"basis_set_file_names": [], "potential_file_names": []}

    if not path.is_file():
        errors.append(f"input file does not exist: {path}")
    else:
        text = path.read_text(encoding="utf-8", errors="replace")
        references = _input_data_file_references(text)

    cache = _load_data_cache(cache_path, warnings, warn_missing_cache=warn_missing_cache)
    _validate_referenced_data_files(references, cache, warnings)

    return {
        "mode": "existing_input",
        "valid": not errors,
        "errors": errors,
        "warnings": warnings,
        "input": {
            "path": str(path),
        },
        "references": references,
        "data_cache": _cache_summary(cache_path, cache),
    }


def default_cache_path(config: dict[str, Any]) -> str | None:
    """Return the configured job-independent CP2K data cache path."""
    workspace = str(config.get("default_windows_workspace") or "").strip()
    if not workspace:
        return None
    return str(Path(workspace) / "cp2k-data.winqstep-cache.json")


def _load_data_cache(cache_path: str | Path | None, warnings: list[str], *, warn_missing_cache: bool) -> dict[str, Any] | None:
    if cache_path is None or not str(cache_path).strip():
        if warn_missing_cache:
            warnings.append("CP2K data cache is not configured; run Inspect Data to validate basis/potential labels.")
        return None
    path = Path(cache_path).resolve()
    if not path.is_file():
        warnings.append(f"CP2K data cache not found: {path}; run Inspect Data to validate basis/potential labels.")
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        warnings.append(f"CP2K data cache could not be read: {exc}")
        return None
    if not isinstance(data, dict):
        warnings.append("CP2K data cache root must be an object.")
        return None
    return data


def _cache_summary(cache_path: str | Path | None, cache: dict[str, Any] | None) -> dict[str, Any]:
    path = str(Path(cache_path).resolve()) if cache_path else ""
    counts = cache.get("counts", {}) if isinstance(cache, dict) else {}
    return {
        "path": path,
        "available": cache is not None,
        "counts": counts,
    }


def _template_elements(template: dict[str, Any]) -> list[str]:
    kinds = template.get("kinds") if isinstance(template, dict) else []
    if not isinstance(kinds, list):
        return []
    return sorted({str(kind.get("element", "")).strip() for kind in kinds if isinstance(kind, dict) and kind.get("element")})


def _structure_summary(structure_path: str | Path, imported: dict[str, Any]) -> dict[str, Any]:
    atoms = []
    if isinstance(imported, dict):
        if isinstance(imported.get("atoms"), list):
            atoms = imported["atoms"]
        else:
            structure = imported.get("structure")
            if isinstance(structure, dict) and isinstance(structure.get("atoms"), list):
                atoms = structure["atoms"]
    elements = sorted({str(atom.get("element", "")).strip() for atom in atoms if isinstance(atom, dict) and atom.get("element")})
    return {
        "path": str(Path(structure_path).resolve()),
        "atom_count": len(atoms),
        "elements": elements,
    }


def _data_file_names(cache: dict[str, Any] | None) -> set[str]:
    if not cache:
        return set()
    files = cache.get("files")
    if not isinstance(files, list):
        return set()
    names = set()
    for item in files:
        if isinstance(item, dict) and item.get("name"):
            names.add(str(item["name"]))
    return names


def _validate_template_data_files(template: dict[str, Any], cache: dict[str, Any] | None, warnings: list[str]) -> None:
    if cache is None:
        return
    file_names = _data_file_names(cache)
    dft = template.get("dft") if isinstance(template.get("dft"), dict) else {}
    for key, label in (
        ("basis_set_file_name", "basis set file"),
        ("potential_file_name", "potential file"),
    ):
        name = str(dft.get(key) or "").strip()
        if name and file_names and name not in file_names:
            warnings.append(f"Template {label} is not present in CP2K data cache: {name}")


def _validate_kind_labels(kinds: list[dict[str, Any]], cache: dict[str, Any] | None, warnings: list[str]) -> None:
    if cache is None:
        return
    labels_by_element = cache.get("labels_by_element")
    if not isinstance(labels_by_element, dict):
        warnings.append("CP2K data cache does not include labels_by_element.")
        return
    for kind in kinds:
        element = str(kind.get("element") or "").strip()
        labels = labels_by_element.get(element)
        if not isinstance(labels, dict):
            warnings.append(f"CP2K data cache has no labels for element {element}.")
            continue
        basis_labels = _string_set(labels.get("basis_sets"))
        potential_labels = _string_set(labels.get("potentials"))
        basis = str(kind.get("basis_set") or "").strip()
        potential = str(kind.get("potential") or "").strip()
        if basis_labels and basis not in basis_labels:
            warnings.append(f"KIND {element} basis set is not present in CP2K data cache: {basis}")
        if potential_labels and potential not in potential_labels:
            warnings.append(f"KIND {element} potential is not present in CP2K data cache: {potential}")


def _string_set(value: Any) -> set[str]:
    if not isinstance(value, list):
        return set()
    return {str(item) for item in value}


def _input_data_file_references(text: str) -> dict[str, list[str]]:
    return {
        "basis_set_file_names": sorted(set(DATA_FILE_RE["basis"].findall(text))),
        "potential_file_names": sorted(set(DATA_FILE_RE["potential"].findall(text))),
    }


def _validate_referenced_data_files(
    references: dict[str, list[str]],
    cache: dict[str, Any] | None,
    warnings: list[str],
) -> None:
    if cache is None:
        return
    file_names = _data_file_names(cache)
    for key, label in (
        ("basis_set_file_names", "basis set file"),
        ("potential_file_names", "potential file"),
    ):
        for name in references.get(key, []):
            if file_names and name not in file_names:
                warnings.append(f"Existing input references {label} not present in CP2K data cache: {name}")

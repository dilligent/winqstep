"""Workflow helpers that combine structures, templates, and CP2K execution."""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any

from .quickstep import QuickStepInputError, quickstep_input_from_dict
from .runner import Executor, RunnerError, run_quickstep_job
from .structures import StructureImportError, import_structure


class WorkflowError(ValueError):
    """Raised when a structure-to-QuickStep workflow cannot be built."""


def build_quickstep_data(
    template_data: dict[str, Any],
    structure_data: dict[str, Any],
    *,
    project_name: str | None = None,
) -> dict[str, Any]:
    """Combine a calculation template and imported structure into QuickStep JSON."""
    template = _object(template_data, "template")
    structure = _object(structure_data, "structure")
    atoms = _atoms(structure.get("atoms"))
    transform = _object(template.get("structure_transform", {}), "structure_transform")
    structure_cell = _object(structure.get("cell"), "structure.cell")
    uses_fallback_cell = _uses_fallback_cell(structure_cell, transform)
    cell = _resolved_cell(structure_cell, transform)
    should_center_atoms = bool(transform.get("center_atoms", False)) and uses_fallback_cell
    transformed_atoms = _center_atoms(atoms, cell) if should_center_atoms else atoms
    kinds = _select_kinds(_kind_library(template), transformed_atoms)

    run_type = _optional_string(template, "run_type", "ENERGY").upper()
    resolved_project_name = project_name or _optional_string(
        template,
        "project_name",
        f"{_structure_stem(structure)}_{run_type.lower()}",
    )
    quickstep_data: dict[str, Any] = {
        "project_name": resolved_project_name,
        "run_type": run_type,
        "dft": copy.deepcopy(_object(template.get("dft", {}), "dft")),
        "structure": {
            "cell": cell,
            "atoms": transformed_atoms,
            "kinds": kinds,
        },
    }
    if "geo_opt" in template:
        quickstep_data["geo_opt"] = copy.deepcopy(_object(template.get("geo_opt"), "geo_opt"))

    try:
        quickstep_input_from_dict(quickstep_data)
    except QuickStepInputError as exc:
        raise WorkflowError(str(exc)) from exc
    return quickstep_data


def run_quickstep_workflow(
    *,
    config: dict[str, Any],
    template_data: dict[str, Any],
    structure_path: str | Path,
    windows_job_dir: str | Path,
    structure_format: str | None = None,
    project_name: str | None = None,
    input_name: str | None = None,
    mpi_ranks: int | None = None,
    execute: bool = True,
    executor: Executor | None = None,
) -> dict[str, Any]:
    """Import a structure, render QuickStep input, optionally run CP2K, and record metadata."""
    try:
        imported = import_structure(structure_path, structure_format)
        quickstep_data = build_quickstep_data(template_data, imported, project_name=project_name)
        metadata = run_quickstep_job(
            config=config,
            quickstep_data=quickstep_data,
            windows_job_dir=windows_job_dir,
            input_name=input_name,
            mpi_ranks=mpi_ranks,
            execute=execute,
            executor=executor,
        )
    except (StructureImportError, QuickStepInputError, RunnerError, OSError) as exc:
        raise WorkflowError(str(exc)) from exc

    metadata["workflow"] = _workflow_metadata(template_data, imported, quickstep_data)
    _rewrite_metadata(metadata)
    return metadata


def _object(value: Any, key: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise WorkflowError(f"{key} must be an object")
    return value


def _optional_string(data: dict[str, Any], key: str, default: str) -> str:
    value = data.get(key, default)
    if not isinstance(value, str) or not value.strip():
        raise WorkflowError(f"{key} must be a non-empty string")
    return value.strip()


def _atoms(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list) or not value:
        raise WorkflowError("structure.atoms must be a non-empty list")
    atoms: list[dict[str, Any]] = []
    for atom in value:
        parsed = _object(atom, "structure atom")
        atoms.append(
            {
                "element": _optional_string(parsed, "element", ""),
                "xyz": _vector(parsed.get("xyz"), "atom.xyz"),
            }
        )
    return atoms


def _kind_library(template: dict[str, Any]) -> list[dict[str, Any]]:
    raw = template.get("kinds")
    if raw is None:
        raw = _object(template.get("structure", {}), "template.structure").get("kinds")
    if not isinstance(raw, list) or not raw:
        raise WorkflowError("template must define a non-empty kinds list")

    kinds: list[dict[str, Any]] = []
    for kind in raw:
        parsed = _object(kind, "kind")
        kinds.append(
            {
                "element": _normalize_element(_optional_string(parsed, "element", "")),
                "basis_set": _optional_string(parsed, "basis_set", ""),
                "potential": _optional_string(parsed, "potential", ""),
            }
        )
    return kinds


def _select_kinds(kind_library: list[dict[str, Any]], atoms: list[dict[str, Any]]) -> list[dict[str, Any]]:
    needed = {_normalize_element(atom["element"]) for atom in atoms}
    by_element = {_normalize_element(kind["element"]): kind for kind in kind_library}
    missing = sorted(needed - set(by_element))
    if missing:
        raise WorkflowError("template missing KIND definitions for: " + ", ".join(missing))
    return [copy.deepcopy(by_element[element]) for element in sorted(needed)]


def _resolved_cell(structure_cell: dict[str, Any], transform: dict[str, Any]) -> dict[str, Any]:
    fallback = transform.get("fallback_cell")
    if _needs_fallback_cell(structure_cell):
        if fallback is None:
            return _cell_dict(structure_cell)
        return _cell_dict(_object(fallback, "structure_transform.fallback_cell"))
    return _cell_dict(structure_cell)


def _uses_fallback_cell(structure_cell: dict[str, Any], transform: dict[str, Any]) -> bool:
    return _needs_fallback_cell(structure_cell) and transform.get("fallback_cell") is not None


def _needs_fallback_cell(cell: dict[str, Any]) -> bool:
    periodic = str(cell.get("periodic", "NONE")).strip().upper()
    return periodic == "NONE" or all(_vector_norm(_vector(cell.get(axis), f"cell.{axis}")) == 0 for axis in ("a", "b", "c"))


def _cell_dict(cell: dict[str, Any]) -> dict[str, Any]:
    return {
        "periodic": _optional_string(cell, "periodic", "XYZ").upper(),
        "a": _vector(cell.get("a"), "cell.a"),
        "b": _vector(cell.get("b"), "cell.b"),
        "c": _vector(cell.get("c"), "cell.c"),
    }


def _center_atoms(atoms: list[dict[str, Any]], cell: dict[str, Any]) -> list[dict[str, Any]]:
    coordinates = [atom["xyz"] for atom in atoms]
    minimum = [min(vector[index] for vector in coordinates) for index in range(3)]
    maximum = [max(vector[index] for vector in coordinates) for index in range(3)]
    current_center = [(minimum[index] + maximum[index]) / 2.0 for index in range(3)]
    target_center = [
        (cell["a"][index] + cell["b"][index] + cell["c"][index]) / 2.0
        for index in range(3)
    ]
    shift = [target_center[index] - current_center[index] for index in range(3)]
    return [
        {
            "element": atom["element"],
            "xyz": [round(atom["xyz"][index] + shift[index], 10) for index in range(3)],
        }
        for atom in atoms
    ]


def _workflow_metadata(
    template_data: dict[str, Any],
    structure_data: dict[str, Any],
    quickstep_data: dict[str, Any],
) -> dict[str, Any]:
    atoms = quickstep_data["structure"]["atoms"]
    return {
        "template": {
            "project_name": template_data.get("project_name"),
            "run_type": template_data.get("run_type", "ENERGY"),
        },
        "structure_source": structure_data.get("source", {}),
        "atom_count": len(atoms),
        "elements": sorted({_normalize_element(atom["element"]) for atom in atoms}),
        "cell": quickstep_data["structure"]["cell"],
    }


def _rewrite_metadata(metadata: dict[str, Any]) -> None:
    path = Path(metadata["dry_run"]["windows"]["metadata_path"])
    metadata_file = metadata.get("files", {}).get("metadata")
    for _ in range(3):
        path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if not isinstance(metadata_file, dict):
            return
        previous_size = metadata_file.get("size")
        metadata_file["exists"] = True
        metadata_file["size"] = path.stat().st_size
        if metadata_file["size"] == previous_size:
            return


def _structure_stem(structure: dict[str, Any]) -> str:
    source = structure.get("source")
    if isinstance(source, dict):
        path = source.get("path")
        if isinstance(path, str) and path.strip():
            return Path(path).stem
    return "quickstep"


def _vector(value: Any, key: str) -> list[float]:
    if not isinstance(value, list | tuple) or len(value) != 3:
        raise WorkflowError(f"{key} must be a 3-vector")
    try:
        return [float(value[0]), float(value[1]), float(value[2])]
    except (TypeError, ValueError) as exc:
        raise WorkflowError(f"{key} must contain numeric values") from exc


def _vector_norm(vector: list[float]) -> float:
    return sum(value * value for value in vector) ** 0.5


def _normalize_element(value: str) -> str:
    stripped = value.strip()
    if not stripped:
        raise WorkflowError("element must be a non-empty string")
    return stripped[0].upper() + stripped[1:].lower()

"""Build display-only preview models for imported structures."""

from __future__ import annotations

import math
from typing import Any, Iterable


DEFAULT_MAX_DISPLAY_ATOMS = 2000
DEFAULT_ELEMENT_STYLE = {"color": "#B0B0B0", "radius": 0.7}
ELEMENT_STYLES: dict[str, dict[str, float | str]] = {
    "H": {"color": "#FFFFFF", "radius": 0.31},
    "C": {"color": "#909090", "radius": 0.76},
    "N": {"color": "#3050F8", "radius": 0.71},
    "O": {"color": "#FF0D0D", "radius": 0.66},
    "F": {"color": "#90E050", "radius": 0.57},
    "Na": {"color": "#AB5CF2", "radius": 1.66},
    "Mg": {"color": "#8AFF00", "radius": 1.41},
    "Al": {"color": "#BFA6A6", "radius": 1.21},
    "Si": {"color": "#F0C8A0", "radius": 1.11},
    "P": {"color": "#FF8000", "radius": 1.07},
    "S": {"color": "#FFFF30", "radius": 1.05},
    "Cl": {"color": "#1FF01F", "radius": 1.02},
    "K": {"color": "#8F40D4", "radius": 2.03},
    "Ca": {"color": "#3DFF00", "radius": 1.76},
    "Fe": {"color": "#E06633", "radius": 1.24},
}


class StructurePreviewError(ValueError):
    """Raised when imported structure data cannot produce a preview model."""


def build_structure_preview(
    structure: dict[str, Any],
    *,
    max_atoms: int = DEFAULT_MAX_DISPLAY_ATOMS,
) -> dict[str, Any]:
    """Return a deterministic, JSON-serializable structure preview model."""
    if max_atoms < 1:
        raise StructurePreviewError("max_atoms must be at least 1")

    atoms = _as_sequence(structure.get("atoms"))
    cell = structure.get("cell") if isinstance(structure.get("cell"), dict) else {}
    periodic = _string_value(cell.get("periodic"), "NONE").upper()
    warnings: list[str] = []

    display_atoms = atoms[:max_atoms]
    if len(atoms) > max_atoms:
        warnings.append(f"Only the first {max_atoms} of {len(atoms)} atoms are included in preview geometry.")

    preview_atoms = [_preview_atom(index, atom) for index, atom in enumerate(display_atoms, start=1)]
    cell_model = _build_cell_model(cell, periodic, warnings)
    points = [atom["xyz"] for atom in preview_atoms]
    if cell_model["available"]:
        points.extend(cell_model["corners"])

    center, bounding_radius = _bounds(points, preview_atoms)
    if not preview_atoms:
        warnings.append("Structure preview contains no atoms.")

    return {
        "mode": "structure_preview",
        "source": structure.get("source") if isinstance(structure.get("source"), dict) else {},
        "atom_count": len(atoms),
        "displayed_atom_count": len(preview_atoms),
        "periodic": periodic,
        "center": center,
        "bounding_radius": bounding_radius,
        "atoms": preview_atoms,
        "cell": {
            "available": cell_model["available"],
            "periodic": periodic,
            "vectors": cell_model["vectors"],
            "origin": [0.0, 0.0, 0.0],
            "edges": cell_model["edges"],
        },
        "warnings": warnings,
    }


def _preview_atom(index: int, atom: Any) -> dict[str, Any]:
    if not isinstance(atom, dict):
        raise StructurePreviewError(f"atoms[{index - 1}] must be an object")
    element = _normalize_element(atom.get("element"))
    style = ELEMENT_STYLES.get(element, DEFAULT_ELEMENT_STYLE)
    return {
        "index": index,
        "element": element,
        "xyz": _vector(atom.get("xyz"), f"atoms[{index - 1}].xyz"),
        "color": str(style["color"]),
        "radius": _round(float(style["radius"])),
    }


def _build_cell_model(cell: dict[str, Any], periodic: str, warnings: list[str]) -> dict[str, Any]:
    vectors = {
        "a": _optional_vector(cell.get("a")),
        "b": _optional_vector(cell.get("b")),
        "c": _optional_vector(cell.get("c")),
    }
    has_cell = all(_norm(vectors[key]) > 1.0e-8 for key in ("a", "b", "c"))
    if periodic == "NONE" or not has_cell:
        if periodic == "NONE":
            warnings.append("No periodic cell frame is available for this structure.")
        else:
            warnings.append("Periodic structure has incomplete cell vectors; cell frame was omitted.")
        return {
            "available": False,
            "vectors": vectors,
            "corners": [],
            "edges": [],
        }

    corners = _cell_corners(vectors["a"], vectors["b"], vectors["c"])
    edges = [
        _edge(corners[0], corners[1]),
        _edge(corners[0], corners[2]),
        _edge(corners[0], corners[4]),
        _edge(corners[1], corners[3]),
        _edge(corners[1], corners[5]),
        _edge(corners[2], corners[3]),
        _edge(corners[2], corners[6]),
        _edge(corners[4], corners[5]),
        _edge(corners[4], corners[6]),
        _edge(corners[3], corners[7]),
        _edge(corners[5], corners[7]),
        _edge(corners[6], corners[7]),
    ]
    return {
        "available": True,
        "vectors": vectors,
        "corners": corners,
        "edges": edges,
    }


def _cell_corners(a: list[float], b: list[float], c: list[float]) -> list[list[float]]:
    origin = [0.0, 0.0, 0.0]
    return [
        origin,
        a,
        b,
        _add(a, b),
        c,
        _add(a, c),
        _add(b, c),
        _add(_add(a, b), c),
    ]


def _edge(start: list[float], end: list[float]) -> dict[str, list[float]]:
    return {"start": start, "end": end}


def _bounds(points: list[list[float]], atoms: list[dict[str, Any]]) -> tuple[list[float], float]:
    if not points:
        return [0.0, 0.0, 0.0], 1.0

    mins = [min(point[index] for point in points) for index in range(3)]
    maxes = [max(point[index] for point in points) for index in range(3)]
    center = [_round((mins[index] + maxes[index]) / 2.0) for index in range(3)]
    radius = 0.0
    for point in points:
        radius = max(radius, _distance(point, center))
    for atom in atoms:
        radius = max(radius, _distance(atom["xyz"], center) + float(atom["radius"]))
    return center, _round(max(radius, 1.0))


def _normalize_element(value: Any) -> str:
    element = _string_value(value, "X")
    if len(element) == 1:
        return element.upper()
    return element[0].upper() + element[1:].lower()


def _string_value(value: Any, fallback: str) -> str:
    if value is None:
        return fallback
    text = str(value).strip()
    return text or fallback


def _as_sequence(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, tuple):
        return list(value)
    raise StructurePreviewError("atoms must be a list")


def _vector(value: Any, key: str) -> list[float]:
    if not isinstance(value, Iterable) or isinstance(value, (str, bytes)):
        raise StructurePreviewError(f"{key} must contain three numeric values")
    items = list(value)
    if len(items) != 3:
        raise StructurePreviewError(f"{key} must contain three numeric values")
    try:
        return [_round(float(item)) for item in items]
    except (TypeError, ValueError) as exc:
        raise StructurePreviewError(f"{key} must contain three numeric values") from exc


def _optional_vector(value: Any) -> list[float]:
    try:
        return _vector(value, "cell vector")
    except StructurePreviewError:
        return [0.0, 0.0, 0.0]


def _add(left: list[float], right: list[float]) -> list[float]:
    return [_round(left[index] + right[index]) for index in range(3)]


def _norm(vector: list[float]) -> float:
    return math.sqrt(sum(value * value for value in vector))


def _distance(left: list[float], right: list[float]) -> float:
    return math.sqrt(sum((left[index] - right[index]) ** 2 for index in range(3)))


def _round(value: float) -> float:
    return round(value, 10)

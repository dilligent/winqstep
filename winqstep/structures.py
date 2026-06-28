"""Structure import helpers for CIF, POSCAR, and XYZ files."""

from __future__ import annotations

import json
import math
import shlex
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


class StructureImportError(ValueError):
    """Raised when a structure file cannot be imported."""


@dataclass(frozen=True)
class ImportedAtom:
    element: str
    xyz: tuple[float, float, float]


@dataclass(frozen=True)
class ImportedStructure:
    atoms: tuple[ImportedAtom, ...]
    cell: tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float]]
    pbc: tuple[bool, bool, bool]
    source_format: str
    reader: str


def import_structure(path: str | Path, file_format: str | None = None) -> dict[str, Any]:
    """Import a structure file and return WinQStep's normalized JSON shape."""
    source_path = Path(path)
    resolved_format = normalize_format(file_format or infer_format(source_path))

    try:
        imported = import_with_ase(source_path, resolved_format)
    except StructureImportError:
        imported = import_with_builtin_reader(source_path, resolved_format)

    return structure_to_dict(imported, source_path)


def normalize_format(file_format: str) -> str:
    value = file_format.lower().strip()
    if value in {"vasp", "poscar", "contcar"}:
        return "poscar"
    if value in {"xyz", "extxyz"}:
        return "xyz"
    if value == "cif":
        return "cif"
    raise StructureImportError(f"unsupported structure format: {file_format}")


def infer_format(path: Path) -> str:
    name = path.name.lower()
    suffix = path.suffix.lower()
    if name in {"poscar", "contcar"}:
        return "poscar"
    if suffix == ".vasp":
        return "poscar"
    if suffix == ".xyz":
        return "xyz"
    if suffix == ".cif":
        return "cif"
    raise StructureImportError(f"cannot infer structure format from {path}")


def import_with_ase(path: Path, file_format: str) -> ImportedStructure:
    try:
        from ase.io import read  # type: ignore[import-not-found]
    except ImportError as exc:
        raise StructureImportError("ASE is not installed") from exc

    try:
        atoms = read(str(path), format="vasp" if file_format == "poscar" else file_format)
    except Exception as exc:  # pragma: no cover - exercised when ASE is installed.
        raise StructureImportError(f"ASE failed to read {path}: {exc}") from exc

    imported_atoms = tuple(
        ImportedAtom(element=symbol, xyz=tuple(float(value) for value in position))
        for symbol, position in zip(atoms.get_chemical_symbols(), atoms.get_positions(), strict=True)
    )
    cell_matrix = atoms.get_cell().array
    cell = tuple(tuple(float(value) for value in vector) for vector in cell_matrix)
    pbc = tuple(bool(value) for value in atoms.get_pbc())
    return ImportedStructure(
        atoms=imported_atoms,
        cell=cell,  # type: ignore[arg-type]
        pbc=pbc,  # type: ignore[arg-type]
        source_format=file_format,
        reader="ase",
    )


def import_with_builtin_reader(path: Path, file_format: str) -> ImportedStructure:
    if file_format == "xyz":
        return read_xyz(path)
    if file_format == "poscar":
        return read_poscar(path)
    if file_format == "cif":
        return read_cif(path)
    raise StructureImportError(f"no built-in reader for {file_format}")


def read_xyz(path: Path) -> ImportedStructure:
    lines = path.read_text(encoding="utf-8").splitlines()
    if len(lines) < 2:
        raise StructureImportError("XYZ file is too short")
    try:
        atom_count = int(lines[0].strip())
    except ValueError as exc:
        raise StructureImportError("XYZ atom count must be an integer") from exc
    atom_lines = lines[2 : 2 + atom_count]
    if len(atom_lines) != atom_count:
        raise StructureImportError("XYZ atom count does not match coordinate lines")

    atoms = []
    for line in atom_lines:
        parts = line.split()
        if len(parts) < 4:
            raise StructureImportError("XYZ atom line must contain element and xyz")
        atoms.append(ImportedAtom(parts[0], _vector(parts[1:4], "xyz atom")))

    return ImportedStructure(
        atoms=tuple(atoms),
        cell=_zero_cell(),
        pbc=(False, False, False),
        source_format="xyz",
        reader="builtin",
    )


def read_poscar(path: Path) -> ImportedStructure:
    lines = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(lines) < 8:
        raise StructureImportError("POSCAR file is too short")
    try:
        scale = float(lines[1])
    except ValueError as exc:
        raise StructureImportError("POSCAR scale must be numeric") from exc
    lattice = tuple(_scale_vector(_vector(lines[index].split(), f"POSCAR lattice {index}"), scale) for index in range(2, 5))

    symbols_or_counts = lines[5].split()
    if all(part.isdigit() for part in symbols_or_counts):
        raise StructureImportError("POSCAR without element symbols is not supported")

    symbols = symbols_or_counts
    counts_line = lines[6].split()
    if len(symbols) != len(counts_line):
        raise StructureImportError("POSCAR element and count lines have different lengths")
    try:
        counts = [int(value) for value in counts_line]
    except ValueError as exc:
        raise StructureImportError("POSCAR counts must be integers") from exc

    coord_index = 7
    if lines[coord_index].lower().startswith("s"):
        coord_index += 1
    coord_mode = lines[coord_index].lower()
    coord_index += 1
    total_atoms = sum(counts)
    coord_lines = lines[coord_index : coord_index + total_atoms]
    if len(coord_lines) != total_atoms:
        raise StructureImportError("POSCAR coordinate count does not match element counts")

    atoms = []
    line_index = 0
    for symbol, count in zip(symbols, counts, strict=True):
        for _ in range(count):
            vector = _vector(coord_lines[line_index].split()[:3], "POSCAR coordinate")
            xyz = _fractional_to_cartesian(vector, lattice) if coord_mode.startswith("d") else _scale_vector(vector, scale)
            atoms.append(ImportedAtom(symbol, xyz))
            line_index += 1

    return ImportedStructure(
        atoms=tuple(atoms),
        cell=lattice,  # type: ignore[arg-type]
        pbc=(True, True, True),
        source_format="poscar",
        reader="builtin",
    )


def read_cif(path: Path) -> ImportedStructure:
    lines = path.read_text(encoding="utf-8").splitlines()
    fields: dict[str, str] = {}
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("_cell_"):
            parts = shlex.split(stripped)
            if len(parts) >= 2:
                fields[parts[0].lower()] = parts[1]

    try:
        a = float(fields["_cell_length_a"])
        b = float(fields["_cell_length_b"])
        c = float(fields["_cell_length_c"])
        alpha = float(fields.get("_cell_angle_alpha", "90"))
        beta = float(fields.get("_cell_angle_beta", "90"))
        gamma = float(fields.get("_cell_angle_gamma", "90"))
    except (KeyError, ValueError) as exc:
        raise StructureImportError("CIF cell lengths and angles are required") from exc

    lattice = cell_from_lengths_angles(a, b, c, alpha, beta, gamma)
    atoms = read_cif_atom_loop(lines, lattice)
    return ImportedStructure(
        atoms=tuple(atoms),
        cell=lattice,
        pbc=(True, True, True),
        source_format="cif",
        reader="builtin",
    )


def read_cif_atom_loop(
    lines: list[str],
    lattice: tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float]],
) -> list[ImportedAtom]:
    index = 0
    while index < len(lines):
        if lines[index].strip().lower() != "loop_":
            index += 1
            continue
        index += 1
        headers = []
        while index < len(lines) and lines[index].strip().startswith("_"):
            headers.append(lines[index].strip().lower())
            index += 1
        if "_atom_site_fract_x" not in headers:
            continue
        try:
            symbol_idx = headers.index("_atom_site_type_symbol")
        except ValueError:
            symbol_idx = headers.index("_atom_site_label")
        x_idx = headers.index("_atom_site_fract_x")
        y_idx = headers.index("_atom_site_fract_y")
        z_idx = headers.index("_atom_site_fract_z")

        atoms = []
        while index < len(lines):
            stripped = lines[index].strip()
            if not stripped or stripped.startswith("_") or stripped.lower() == "loop_":
                break
            parts = shlex.split(stripped)
            if len(parts) >= len(headers):
                symbol = _clean_cif_symbol(parts[symbol_idx])
                frac = _vector([parts[x_idx], parts[y_idx], parts[z_idx]], "CIF fractional coordinate")
                atoms.append(ImportedAtom(symbol, _fractional_to_cartesian(frac, lattice)))
            index += 1
        if atoms:
            return atoms
    raise StructureImportError("CIF atom site loop with fractional coordinates was not found")


def structure_to_dict(structure: ImportedStructure, source_path: Path) -> dict[str, Any]:
    return {
        "source": {
            "path": str(source_path),
            "format": structure.source_format,
            "reader": structure.reader,
        },
        "cell": {
            "a": _list_vector(structure.cell[0]),
            "b": _list_vector(structure.cell[1]),
            "c": _list_vector(structure.cell[2]),
            "pbc": list(structure.pbc),
            "periodic": periodic_label(structure.pbc),
        },
        "atoms": [
            {
                "element": atom.element,
                "xyz": _list_vector(atom.xyz),
            }
            for atom in structure.atoms
        ],
    }


def periodic_label(pbc: tuple[bool, bool, bool]) -> str:
    labels = ["X", "Y", "Z"]
    periodic = "".join(label for label, enabled in zip(labels, pbc, strict=True) if enabled)
    return periodic or "NONE"


def cell_from_lengths_angles(
    a: float, b: float, c: float, alpha: float, beta: float, gamma: float
) -> tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float]]:
    alpha_r = math.radians(alpha)
    beta_r = math.radians(beta)
    gamma_r = math.radians(gamma)
    vector_a = (a, 0.0, 0.0)
    vector_b = (b * math.cos(gamma_r), b * math.sin(gamma_r), 0.0)
    c_x = c * math.cos(beta_r)
    c_y = c * (math.cos(alpha_r) - math.cos(beta_r) * math.cos(gamma_r)) / math.sin(gamma_r)
    c_z_squared = c * c - c_x * c_x - c_y * c_y
    c_z = math.sqrt(max(c_z_squared, 0.0))
    return (vector_a, vector_b, (c_x, c_y, c_z))


def _fractional_to_cartesian(
    frac: tuple[float, float, float],
    lattice: tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float]],
) -> tuple[float, float, float]:
    return (
        frac[0] * lattice[0][0] + frac[1] * lattice[1][0] + frac[2] * lattice[2][0],
        frac[0] * lattice[0][1] + frac[1] * lattice[1][1] + frac[2] * lattice[2][1],
        frac[0] * lattice[0][2] + frac[1] * lattice[1][2] + frac[2] * lattice[2][2],
    )


def _clean_cif_symbol(value: str) -> str:
    symbol = "".join(character for character in value if character.isalpha())
    if not symbol:
        raise StructureImportError("CIF atom symbol is empty")
    return symbol[0].upper() + symbol[1:].lower()


def _scale_vector(vector: tuple[float, float, float], scale: float) -> tuple[float, float, float]:
    return (vector[0] * scale, vector[1] * scale, vector[2] * scale)


def _vector(values: Iterable[str], key: str) -> tuple[float, float, float]:
    parts = list(values)
    if len(parts) != 3:
        raise StructureImportError(f"{key} must contain three values")
    try:
        return (float(parts[0]), float(parts[1]), float(parts[2]))
    except ValueError as exc:
        raise StructureImportError(f"{key} must contain numeric values") from exc


def _list_vector(vector: tuple[float, float, float]) -> list[float]:
    return [round(value, 10) for value in vector]


def _zero_cell() -> tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float]]:
    return ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0))


def dumps_structure(structure: dict[str, Any], compact: bool = False) -> str:
    return json.dumps(structure, ensure_ascii=False, indent=None if compact else 2)

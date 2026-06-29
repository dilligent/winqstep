"""Deterministic CP2K QuickStep input generation."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterable, Literal


RunType = Literal["ENERGY", "ENERGY_FORCE", "GEO_OPT"]
RUN_TYPES = {"ENERGY", "ENERGY_FORCE", "GEO_OPT"}


class QuickStepInputError(ValueError):
    """Raised when a QuickStep input model is invalid."""


@dataclass(frozen=True)
class Atom:
    element: str
    xyz: tuple[float, float, float]


@dataclass(frozen=True)
class Cell:
    a: tuple[float, float, float]
    b: tuple[float, float, float]
    c: tuple[float, float, float]
    periodic: str = "XYZ"


@dataclass(frozen=True)
class Kind:
    element: str
    basis_set: str
    potential: str


@dataclass(frozen=True)
class DftSettings:
    basis_set_file_name: str = "BASIS_MOLOPT"
    potential_file_name: str = "GTH_POTENTIALS"
    xc_functional: str = "PBE"
    charge: int = 0
    multiplicity: int = 1
    cutoff: int = 400
    rel_cutoff: int = 40
    eps_scf: str = "1.0E-6"
    max_scf: int = 50


@dataclass(frozen=True)
class GeoOptSettings:
    optimizer: str = "BFGS"
    max_iter: int = 200


@dataclass(frozen=True)
class QuickStepInput:
    project_name: str
    run_type: RunType
    cell: Cell
    atoms: tuple[Atom, ...]
    kinds: tuple[Kind, ...]
    dft: DftSettings = DftSettings()
    geo_opt: GeoOptSettings = GeoOptSettings()


def _required_string(data: dict[str, Any], key: str) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value.strip():
        raise QuickStepInputError(f"{key} must be a non-empty string")
    return value.strip()


def _optional_string(data: dict[str, Any], key: str, default: str) -> str:
    value = data.get(key, default)
    if not isinstance(value, str) or not value.strip():
        raise QuickStepInputError(f"{key} must be a non-empty string")
    return value.strip()


def _int_value(data: dict[str, Any], key: str, default: int) -> int:
    value = data.get(key, default)
    if not isinstance(value, int):
        raise QuickStepInputError(f"{key} must be an integer")
    return value


def _vector(value: Any, key: str) -> tuple[float, float, float]:
    if not isinstance(value, list | tuple) or len(value) != 3:
        raise QuickStepInputError(f"{key} must be a 3-vector")
    try:
        return (float(value[0]), float(value[1]), float(value[2]))
    except (TypeError, ValueError) as exc:
        raise QuickStepInputError(f"{key} must contain numeric values") from exc


def _parse_atom(data: dict[str, Any]) -> Atom:
    return Atom(element=_required_string(data, "element"), xyz=_vector(data.get("xyz"), "atom.xyz"))


def _parse_cell(data: dict[str, Any]) -> Cell:
    return Cell(
        a=_vector(data.get("a"), "cell.a"),
        b=_vector(data.get("b"), "cell.b"),
        c=_vector(data.get("c"), "cell.c"),
        periodic=_optional_string(data, "periodic", "XYZ").upper(),
    )


def _parse_kind(data: dict[str, Any]) -> Kind:
    return Kind(
        element=_required_string(data, "element"),
        basis_set=_required_string(data, "basis_set"),
        potential=_required_string(data, "potential"),
    )


def _parse_dft(data: dict[str, Any]) -> DftSettings:
    return DftSettings(
        basis_set_file_name=_optional_string(data, "basis_set_file_name", "BASIS_MOLOPT"),
        potential_file_name=_optional_string(data, "potential_file_name", "GTH_POTENTIALS"),
        xc_functional=_optional_string(data, "xc_functional", "PBE").upper(),
        charge=_int_value(data, "charge", 0),
        multiplicity=_int_value(data, "multiplicity", 1),
        cutoff=_int_value(data, "cutoff", 400),
        rel_cutoff=_int_value(data, "rel_cutoff", 40),
        eps_scf=_optional_string(data, "eps_scf", "1.0E-6"),
        max_scf=_int_value(data, "max_scf", 50),
    )


def _parse_geo_opt(data: dict[str, Any]) -> GeoOptSettings:
    return GeoOptSettings(
        optimizer=_optional_string(data, "optimizer", "BFGS").upper(),
        max_iter=_int_value(data, "max_iter", 200),
    )


def quickstep_input_from_dict(data: dict[str, Any]) -> QuickStepInput:
    run_type = _required_string(data, "run_type").upper()
    if run_type not in RUN_TYPES:
        raise QuickStepInputError("run_type must be ENERGY, ENERGY_FORCE, or GEO_OPT")

    structure = data.get("structure")
    if not isinstance(structure, dict):
        raise QuickStepInputError("structure must be an object")

    atoms_raw = structure.get("atoms")
    if not isinstance(atoms_raw, list) or not atoms_raw:
        raise QuickStepInputError("structure.atoms must be a non-empty list")
    atoms = tuple(_parse_atom(atom) for atom in atoms_raw)

    kinds_raw = structure.get("kinds")
    if not isinstance(kinds_raw, list) or not kinds_raw:
        raise QuickStepInputError("structure.kinds must be a non-empty list")
    kinds = tuple(_parse_kind(kind) for kind in kinds_raw)

    model = QuickStepInput(
        project_name=_required_string(data, "project_name"),
        run_type=run_type,  # type: ignore[arg-type]
        cell=_parse_cell(_object(structure.get("cell"), "structure.cell")),
        atoms=atoms,
        kinds=kinds,
        dft=_parse_dft(_object(data.get("dft", {}), "dft")),
        geo_opt=_parse_geo_opt(_object(data.get("geo_opt", {}), "geo_opt")),
    )
    validate_quickstep_input(model)
    return model


def _object(value: Any, key: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise QuickStepInputError(f"{key} must be an object")
    return value


def validate_quickstep_input(model: QuickStepInput) -> None:
    kind_elements = {kind.element for kind in model.kinds}
    atom_elements = {atom.element for atom in model.atoms}
    missing_kinds = sorted(atom_elements - kind_elements)
    if missing_kinds:
        raise QuickStepInputError("missing KIND definitions for: " + ", ".join(missing_kinds))

    if model.cell.periodic not in {"NONE", "X", "Y", "Z", "XY", "XZ", "YZ", "XYZ"}:
        raise QuickStepInputError("cell.periodic has an unsupported value")
    if model.dft.cutoff <= 0 or model.dft.rel_cutoff <= 0:
        raise QuickStepInputError("cutoff and rel_cutoff must be positive")
    if model.dft.max_scf <= 0:
        raise QuickStepInputError("max_scf must be positive")
    if model.geo_opt.max_iter <= 0:
        raise QuickStepInputError("geo_opt.max_iter must be positive")


def render_quickstep_input(model: QuickStepInput) -> str:
    validate_quickstep_input(model)
    lines: list[str] = [
        "# Generated by WinQStep. You can edit this CP2K input manually.",
        "&GLOBAL",
        f"  PROJECT_NAME {model.project_name}",
        f"  RUN_TYPE {model.run_type}",
        "&END GLOBAL",
        "",
        "&FORCE_EVAL",
        "  METHOD QS",
        "  &DFT",
        f"    BASIS_SET_FILE_NAME {model.dft.basis_set_file_name}",
        f"    POTENTIAL_FILE_NAME {model.dft.potential_file_name}",
        f"    CHARGE {model.dft.charge}",
        f"    MULTIPLICITY {model.dft.multiplicity}",
        "    &MGRID",
        f"      CUTOFF {model.dft.cutoff}",
        f"      REL_CUTOFF {model.dft.rel_cutoff}",
        "    &END MGRID",
        "    &SCF",
        f"      EPS_SCF {model.dft.eps_scf}",
        f"      MAX_SCF {model.dft.max_scf}",
        "    &END SCF",
        "    &XC",
        f"      &XC_FUNCTIONAL {model.dft.xc_functional}",
        "      &END XC_FUNCTIONAL",
        "    &END XC",
        "  &END DFT",
        "  &SUBSYS",
        "    &CELL",
        f"      PERIODIC {model.cell.periodic}",
        f"      A {_format_vector(model.cell.a)}",
        f"      B {_format_vector(model.cell.b)}",
        f"      C {_format_vector(model.cell.c)}",
        "    &END CELL",
        "    &COORD",
        *_render_atoms(model.atoms),
        "    &END COORD",
        *_render_kinds(model.kinds),
        "  &END SUBSYS",
        "&END FORCE_EVAL",
    ]

    if model.run_type == "GEO_OPT":
        lines.extend(
            [
                "",
                "&MOTION",
                "  &GEO_OPT",
                f"    OPTIMIZER {model.geo_opt.optimizer}",
                f"    MAX_ITER {model.geo_opt.max_iter}",
                "  &END GEO_OPT",
                "&END MOTION",
            ]
        )

    return "\n".join(lines) + "\n"


def _format_vector(vector: tuple[float, float, float]) -> str:
    return " ".join(f"{value:.10g}" for value in vector)


def _render_atoms(atoms: Iterable[Atom]) -> list[str]:
    return [f"      {atom.element} {_format_vector(atom.xyz)}" for atom in atoms]


def _render_kinds(kinds: Iterable[Kind]) -> list[str]:
    lines: list[str] = []
    for kind in sorted(kinds, key=lambda item: item.element):
        lines.extend(
            [
                f"    &KIND {kind.element}",
                f"      BASIS_SET {kind.basis_set}",
                f"      POTENTIAL {kind.potential}",
                "    &END KIND",
            ]
        )
    return lines

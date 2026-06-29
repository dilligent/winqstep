"""Deterministic CP2K QuickStep input generation."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterable, Literal


RunType = Literal["ENERGY", "ENERGY_FORCE", "GEO_OPT"]
RUN_TYPES = {"ENERGY", "ENERGY_FORCE", "GEO_OPT"}
PERIODIC_VALUES = {"NONE", "X", "Y", "Z", "XY", "XZ", "YZ", "XYZ"}
SCF_METHODS = {"DEFAULT", "OT", "DIAGONALIZATION"}
OT_MINIMIZERS = {"SD", "CG", "DIIS", "BROYDEN"}
OT_PRECONDITIONERS = {
    "FULL_ALL",
    "FULL_KINETIC",
    "FULL_SINGLE",
    "FULL_SINGLE_INVERSE",
    "FULL_S_INVERSE",
    "NONE",
}
DIAGONALIZATION_ALGORITHMS = {"STANDARD", "DAVIDSON", "LANCZOS", "FILTER_MATRIX"}
MIXING_METHODS = {
    "DIRECT_P_MIXING",
    "BROYDEN_MIXING",
    "PULAY_MIXING",
    "KERKER_MIXING",
    "MULTISECANT_MIXING",
    "NEW_PULAY_MIXING",
}
SMEARING_METHODS = {"FERMI_DIRAC", "ENERGY_WINDOW", "GAUSSIAN", "METHFESSEL_PAXTON", "MARZARI_VANDERBILT"}


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
    scf_method: str = "DEFAULT"
    added_mos: int = 0
    ot_minimizer: str = "CG"
    ot_preconditioner: str = "FULL_KINETIC"
    diagonalization_algorithm: str = "STANDARD"
    mixing_enabled: bool = False
    mixing_method: str = "BROYDEN_MIXING"
    mixing_alpha: str = "0.4"
    mixing_beta: str = "1.5"
    smearing_enabled: bool = False
    smearing_method: str = "FERMI_DIRAC"
    electronic_temperature: str = "300"


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


def _bool_value(data: dict[str, Any], key: str, default: bool) -> bool:
    value = data.get(key, default)
    if not isinstance(value, bool):
        raise QuickStepInputError(f"{key} must be a boolean")
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
        scf_method=_optional_string(data, "scf_method", "DEFAULT").upper(),
        added_mos=_int_value(data, "added_mos", 0),
        ot_minimizer=_optional_string(data, "ot_minimizer", "CG").upper(),
        ot_preconditioner=_optional_string(data, "ot_preconditioner", "FULL_KINETIC").upper(),
        diagonalization_algorithm=_optional_string(data, "diagonalization_algorithm", "STANDARD").upper(),
        mixing_enabled=_bool_value(data, "mixing_enabled", False),
        mixing_method=_optional_string(data, "mixing_method", "BROYDEN_MIXING").upper(),
        mixing_alpha=_optional_string(data, "mixing_alpha", "0.4"),
        mixing_beta=_optional_string(data, "mixing_beta", "1.5"),
        smearing_enabled=_bool_value(data, "smearing_enabled", False),
        smearing_method=_optional_string(data, "smearing_method", "FERMI_DIRAC").upper(),
        electronic_temperature=_optional_string(data, "electronic_temperature", "300"),
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

    if model.cell.periodic not in PERIODIC_VALUES:
        raise QuickStepInputError("cell.periodic has an unsupported value")
    if model.cell.periodic != "NONE" and any(
        _vector_norm(vector) == 0.0 for vector in (model.cell.a, model.cell.b, model.cell.c)
    ):
        raise QuickStepInputError("periodic cell vectors must be non-zero")
    if model.dft.cutoff <= 0 or model.dft.rel_cutoff <= 0:
        raise QuickStepInputError("cutoff and rel_cutoff must be positive")
    if model.dft.max_scf <= 0:
        raise QuickStepInputError("max_scf must be positive")
    if model.dft.scf_method not in SCF_METHODS:
        raise QuickStepInputError("dft.scf_method has an unsupported value")
    if model.dft.added_mos < -1:
        raise QuickStepInputError("dft.added_mos must be -1 or greater")
    if model.dft.ot_minimizer not in OT_MINIMIZERS:
        raise QuickStepInputError("dft.ot_minimizer has an unsupported value")
    if model.dft.ot_preconditioner not in OT_PRECONDITIONERS:
        raise QuickStepInputError("dft.ot_preconditioner has an unsupported value")
    if model.dft.diagonalization_algorithm not in DIAGONALIZATION_ALGORITHMS:
        raise QuickStepInputError("dft.diagonalization_algorithm has an unsupported value")
    if model.dft.mixing_method not in MIXING_METHODS:
        raise QuickStepInputError("dft.mixing_method has an unsupported value")
    if model.dft.smearing_method not in SMEARING_METHODS:
        raise QuickStepInputError("dft.smearing_method has an unsupported value")
    if model.dft.mixing_enabled and model.dft.scf_method != "DIAGONALIZATION":
        raise QuickStepInputError("SCF mixing requires dft.scf_method DIAGONALIZATION")
    if model.dft.smearing_enabled and model.dft.scf_method != "DIAGONALIZATION":
        raise QuickStepInputError("SCF smearing requires dft.scf_method DIAGONALIZATION")
    if model.dft.smearing_enabled and model.dft.added_mos == 0:
        raise QuickStepInputError("SCF smearing requires dft.added_mos to add unoccupied orbitals")
    _positive_float(model.dft.mixing_alpha, "dft.mixing_alpha")
    _positive_float(model.dft.mixing_beta, "dft.mixing_beta")
    _positive_float(model.dft.electronic_temperature, "dft.electronic_temperature")
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
        *_render_force_eval_print(model),
        "  &DFT",
        f"    BASIS_SET_FILE_NAME {model.dft.basis_set_file_name}",
        f"    POTENTIAL_FILE_NAME {model.dft.potential_file_name}",
        f"    CHARGE {model.dft.charge}",
        f"    MULTIPLICITY {model.dft.multiplicity}",
        "    &MGRID",
        f"      CUTOFF {model.dft.cutoff}",
        f"      REL_CUTOFF {model.dft.rel_cutoff}",
        "    &END MGRID",
        "    &POISSON",
        f"      PERIODIC {model.cell.periodic}",
        "    &END POISSON",
        "    &SCF",
        f"      EPS_SCF {model.dft.eps_scf}",
        f"      MAX_SCF {model.dft.max_scf}",
        *_render_scf_extras(model.dft),
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


def _render_force_eval_print(model: QuickStepInput) -> list[str]:
    if model.run_type != "ENERGY_FORCE":
        return []
    return [
        "  &PRINT",
        "    &FORCES ON",
        "    &END FORCES",
        "  &END PRINT",
    ]


def _render_scf_extras(dft: DftSettings) -> list[str]:
    lines: list[str] = []
    if dft.added_mos != 0:
        lines.append(f"      ADDED_MOS {dft.added_mos}")
    if dft.scf_method == "OT":
        lines.extend(
            [
                "      &OT",
                f"        MINIMIZER {dft.ot_minimizer}",
                f"        PRECONDITIONER {dft.ot_preconditioner}",
                "      &END OT",
            ]
        )
    if dft.scf_method == "DIAGONALIZATION":
        lines.extend(
            [
                "      &DIAGONALIZATION",
                f"        ALGORITHM {dft.diagonalization_algorithm}",
                "      &END DIAGONALIZATION",
            ]
        )
        if dft.mixing_enabled:
            lines.extend(
                [
                    "      &MIXING",
                    f"        METHOD {dft.mixing_method}",
                    f"        ALPHA {dft.mixing_alpha}",
                    f"        BETA {dft.mixing_beta}",
                    "      &END MIXING",
                ]
            )
        if dft.smearing_enabled:
            lines.extend(
                [
                    "      &SMEAR ON",
                    f"        METHOD {dft.smearing_method}",
                    f"        TELEC [K] {dft.electronic_temperature}",
                    "      &END SMEAR",
                ]
            )
    return lines


def _format_vector(vector: tuple[float, float, float]) -> str:
    return " ".join(f"{value:.10g}" for value in vector)


def _vector_norm(vector: tuple[float, float, float]) -> float:
    return sum(value * value for value in vector) ** 0.5


def _positive_float(value: str, key: str) -> float:
    try:
        parsed = float(value.replace("D", "E"))
    except ValueError as exc:
        raise QuickStepInputError(f"{key} must be a positive numeric value") from exc
    if parsed <= 0:
        raise QuickStepInputError(f"{key} must be positive")
    return parsed


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

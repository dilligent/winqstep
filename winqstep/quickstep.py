"""Deterministic CP2K QuickStep input generation."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterable, Literal


RunType = Literal["ENERGY", "ENERGY_FORCE", "GEO_OPT", "CELL_OPT"]
RUN_TYPES = {"ENERGY", "ENERGY_FORCE", "GEO_OPT", "CELL_OPT"}
PRINT_LEVELS = {"SILENT", "LOW", "MEDIUM", "HIGH", "DEBUG"}
PERIODIC_VALUES = {"NONE", "X", "Y", "Z", "XY", "XZ", "YZ", "XYZ"}
POISSON_SOLVERS = {"ANALYTIC", "IMPLICIT", "MT", "MULTIPOLE", "PERIODIC", "WAVELET"}
BAND_KPOINT_UNITS = {"B_VECTOR", "CART_ANGSTROM", "CART_BOHR"}
SCF_METHODS = {"DEFAULT", "OT", "DIAGONALIZATION"}
SCF_GUESSES = {
    "ATOMIC",
    "CORE",
    "HISTORY_RESTART",
    "MOPAC",
    "NONE",
    "RANDOM",
    "RESTART",
    "SPARSE",
}
KPOINTS_SCHEMES = {"NONE", "GAMMA", "MONKHORST-PACK"}
KPOINTS_WAVEFUNCTIONS = {"COMPLEX", "REAL"}
MOTION_OPTIMIZERS = {"BFGS", "LBFGS", "CG"}
FIXED_ATOM_COMPONENTS = {"X", "Y", "Z", "XY", "XZ", "YZ", "XYZ"}
CELL_OPT_TYPES = {"DIRECT_CELL_OPT"}
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
PBE_PARAMETRIZATIONS = {"ORIG", "REVPBE", "RPBE", "PBESOL"}
DISPERSION_TYPES = {"DFTD3", "DFTD3(BJ)"}


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
    xc_pbe_parametrization: str = "ORIG"
    dispersion_enabled: bool = False
    dispersion_type: str = "DFTD3(BJ)"
    dispersion_parameter_file_name: str = "dftd3.dat"
    dispersion_reference_functional: str = "PBE"
    charge: int = 0
    multiplicity: int = 1
    uks_enabled: bool = False
    cutoff: int = 400
    rel_cutoff: int = 40
    poisson_solver: str | None = None
    wfn_restart_file_name: str | None = None
    print_mulliken: bool = False
    print_lowdin: bool = False
    print_pdos: bool = False
    print_e_density_cube: bool = False
    print_v_hartree_cube: bool = False
    print_band_structure: bool = False
    band_file_name: str = "band_structure.bs"
    band_added_mos: int = 0
    band_npoints: int = 20
    band_kpoint_units: str = "B_VECTOR"
    band_special_points: tuple[str, ...] = (
        "GAMMA 0.0 0.0 0.0",
        "X 0.5 0.0 0.0",
        "GAMMA 0.0 0.0 0.0",
    )
    scf_guess: str | None = None
    eps_scf: str = "1.0E-6"
    max_scf: int = 50
    outer_scf_enabled: bool = False
    outer_scf_eps_scf: str = "1.0E-6"
    outer_scf_max_scf: int = 20
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
    kpoints_scheme: str = "NONE"
    kpoints_grid: tuple[int, int, int] = (1, 1, 1)
    kpoints_full_grid: bool = False
    kpoints_symmetry: bool = False
    kpoints_wavefunctions: str = "COMPLEX"


@dataclass(frozen=True)
class GeoOptSettings:
    optimizer: str = "BFGS"
    max_iter: int = 200


@dataclass(frozen=True)
class CellOptSettings:
    optimizer: str = "BFGS"
    max_iter: int = 200
    type: str = "DIRECT_CELL_OPT"
    pressure_tolerance: str = "100"
    keep_angles: bool = False
    keep_symmetry: bool = False


@dataclass(frozen=True)
class MotionSettings:
    fixed_atoms: tuple[int, ...] = ()
    fixed_atom_components: str = "XYZ"


@dataclass(frozen=True)
class QuickStepInput:
    project_name: str
    run_type: RunType
    cell: Cell
    atoms: tuple[Atom, ...]
    kinds: tuple[Kind, ...]
    print_level: str | None = None
    dft: DftSettings = DftSettings()
    geo_opt: GeoOptSettings = GeoOptSettings()
    cell_opt: CellOptSettings = CellOptSettings()
    motion: MotionSettings = MotionSettings()


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


def _optional_choice(data: dict[str, Any], key: str) -> str | None:
    value = data.get(key)
    if value is None:
        return None
    if not isinstance(value, str):
        raise QuickStepInputError(f"{key} must be a string")
    stripped = value.strip()
    if not stripped:
        return None
    return stripped.upper()


def _optional_free_string(data: dict[str, Any], key: str) -> str | None:
    value = data.get(key)
    if value is None:
        return None
    if not isinstance(value, str):
        raise QuickStepInputError(f"{key} must be a string")
    stripped = value.strip()
    if not stripped:
        return None
    return stripped


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


def _int_triplet(value: Any, key: str) -> tuple[int, int, int]:
    if isinstance(value, str):
        value = [part for part in value.replace(",", " ").split() if part]
    if not isinstance(value, list | tuple) or len(value) != 3:
        raise QuickStepInputError(f"{key} must be a 3-integer vector")
    parsed_values: list[int] = []
    for item in value:
        if isinstance(item, bool) or not isinstance(item, int | str):
            raise QuickStepInputError(f"{key} must contain integer values")
        try:
            parsed_values.append(int(item))
        except ValueError as exc:
            raise QuickStepInputError(f"{key} must contain integer values") from exc
    parsed = (parsed_values[0], parsed_values[1], parsed_values[2])
    return parsed


def _int_list(value: Any, key: str) -> tuple[int, ...]:
    if value is None:
        return ()
    if isinstance(value, str):
        value = [part for part in value.replace(",", " ").split() if part]
    if not isinstance(value, list | tuple):
        raise QuickStepInputError(f"{key} must be an integer list")
    parsed_values: list[int] = []
    for item in value:
        if isinstance(item, bool) or not isinstance(item, int | str):
            raise QuickStepInputError(f"{key} must contain integer values")
        try:
            parsed_values.append(int(item))
        except ValueError as exc:
            raise QuickStepInputError(f"{key} must contain integer values") from exc
    return tuple(parsed_values)


def _string_list(value: Any, key: str, default: tuple[str, ...]) -> tuple[str, ...]:
    if value is None:
        return default
    if isinstance(value, str):
        value = [part for part in value.replace(";", "\n").splitlines() if part.strip()]
    if not isinstance(value, list | tuple):
        raise QuickStepInputError(f"{key} must be a string list")
    parsed: list[str] = []
    for item in value:
        if not isinstance(item, str):
            raise QuickStepInputError(f"{key} must contain string values")
        stripped = item.strip()
        if stripped:
            parsed.append(stripped)
    return tuple(parsed)


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
        xc_pbe_parametrization=_optional_string(data, "xc_pbe_parametrization", "ORIG").upper(),
        dispersion_enabled=_bool_value(data, "dispersion_enabled", False),
        dispersion_type=_optional_string(data, "dispersion_type", "DFTD3(BJ)").upper(),
        dispersion_parameter_file_name=_optional_string(data, "dispersion_parameter_file_name", "dftd3.dat"),
        dispersion_reference_functional=_optional_string(data, "dispersion_reference_functional", "PBE").upper(),
        charge=_int_value(data, "charge", 0),
        multiplicity=_int_value(data, "multiplicity", 1),
        uks_enabled=_bool_value(data, "uks_enabled", False),
        cutoff=_int_value(data, "cutoff", 400),
        rel_cutoff=_int_value(data, "rel_cutoff", 40),
        poisson_solver=_optional_choice(data, "poisson_solver"),
        wfn_restart_file_name=_optional_free_string(data, "wfn_restart_file_name"),
        print_mulliken=_bool_value(data, "print_mulliken", False),
        print_lowdin=_bool_value(data, "print_lowdin", False),
        print_pdos=_bool_value(data, "print_pdos", False),
        print_e_density_cube=_bool_value(data, "print_e_density_cube", False),
        print_v_hartree_cube=_bool_value(data, "print_v_hartree_cube", False),
        print_band_structure=_bool_value(data, "print_band_structure", False),
        band_file_name=_optional_string(data, "band_file_name", "band_structure.bs"),
        band_added_mos=_int_value(data, "band_added_mos", 0),
        band_npoints=_int_value(data, "band_npoints", 20),
        band_kpoint_units=_optional_string(data, "band_kpoint_units", "B_VECTOR").upper(),
        band_special_points=_string_list(
            data.get("band_special_points"),
            "dft.band_special_points",
            DftSettings().band_special_points,
        ),
        scf_guess=_optional_choice(data, "scf_guess"),
        eps_scf=_optional_string(data, "eps_scf", "1.0E-6"),
        max_scf=_int_value(data, "max_scf", 50),
        outer_scf_enabled=_bool_value(data, "outer_scf_enabled", False),
        outer_scf_eps_scf=_optional_string(data, "outer_scf_eps_scf", "1.0E-6"),
        outer_scf_max_scf=_int_value(data, "outer_scf_max_scf", 20),
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
        kpoints_scheme=_optional_string(data, "kpoints_scheme", "NONE").upper(),
        kpoints_grid=_int_triplet(data.get("kpoints_grid", (1, 1, 1)), "dft.kpoints_grid"),
        kpoints_full_grid=_bool_value(data, "kpoints_full_grid", False),
        kpoints_symmetry=_bool_value(data, "kpoints_symmetry", False),
        kpoints_wavefunctions=_optional_string(data, "kpoints_wavefunctions", "COMPLEX").upper(),
    )


def _parse_geo_opt(data: dict[str, Any]) -> GeoOptSettings:
    return GeoOptSettings(
        optimizer=_optional_string(data, "optimizer", "BFGS").upper(),
        max_iter=_int_value(data, "max_iter", 200),
    )


def _parse_cell_opt(data: dict[str, Any]) -> CellOptSettings:
    return CellOptSettings(
        optimizer=_optional_string(data, "optimizer", "BFGS").upper(),
        max_iter=_int_value(data, "max_iter", 200),
        type=_optional_string(data, "type", "DIRECT_CELL_OPT").upper(),
        pressure_tolerance=_optional_string(data, "pressure_tolerance", "100"),
        keep_angles=_bool_value(data, "keep_angles", False),
        keep_symmetry=_bool_value(data, "keep_symmetry", False),
    )


def _parse_motion(data: dict[str, Any]) -> MotionSettings:
    return MotionSettings(
        fixed_atoms=_int_list(data.get("fixed_atoms"), "motion.fixed_atoms"),
        fixed_atom_components=_optional_string(data, "fixed_atom_components", "XYZ").upper(),
    )


def quickstep_input_from_dict(data: dict[str, Any]) -> QuickStepInput:
    run_type = _required_string(data, "run_type").upper()
    if run_type not in RUN_TYPES:
        raise QuickStepInputError("run_type must be ENERGY, ENERGY_FORCE, GEO_OPT, or CELL_OPT")

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
        print_level=_optional_choice(data, "print_level"),
        dft=_parse_dft(_object(data.get("dft", {}), "dft")),
        geo_opt=_parse_geo_opt(_object(data.get("geo_opt", {}), "geo_opt")),
        cell_opt=_parse_cell_opt(_object(data.get("cell_opt", {}), "cell_opt")),
        motion=_parse_motion(_object(data.get("motion", {}), "motion")),
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

    if model.print_level is not None and model.print_level not in PRINT_LEVELS:
        raise QuickStepInputError("print_level has an unsupported value")
    if model.cell.periodic not in PERIODIC_VALUES:
        raise QuickStepInputError("cell.periodic has an unsupported value")
    if model.dft.poisson_solver is not None and model.dft.poisson_solver not in POISSON_SOLVERS:
        raise QuickStepInputError("dft.poisson_solver has an unsupported value")
    _validate_poisson_solver_periodicity(model.dft.poisson_solver, model.cell.periodic)
    if model.dft.band_kpoint_units not in BAND_KPOINT_UNITS:
        raise QuickStepInputError("dft.band_kpoint_units has an unsupported value")
    if model.dft.band_added_mos < 0:
        raise QuickStepInputError("dft.band_added_mos must be zero or greater")
    if model.dft.band_npoints <= 0:
        raise QuickStepInputError("dft.band_npoints must be positive")
    if model.dft.print_band_structure:
        if model.cell.periodic == "NONE":
            raise QuickStepInputError("DFT band structure output requires a periodic cell")
        if not model.dft.band_file_name.strip():
            raise QuickStepInputError("dft.band_file_name must be a non-empty string")
        if "\n" in model.dft.band_file_name or "\r" in model.dft.band_file_name:
            raise QuickStepInputError("dft.band_file_name must be a single-line string")
        if len(model.dft.band_special_points) < 2:
            raise QuickStepInputError("dft.band_special_points must contain at least two points")
        for point in model.dft.band_special_points:
            _validate_band_special_point(point)
    if model.dft.scf_guess is not None and model.dft.scf_guess not in SCF_GUESSES:
        raise QuickStepInputError("dft.scf_guess has an unsupported value")
    if model.dft.wfn_restart_file_name is not None and model.dft.scf_guess not in {"RESTART", "HISTORY_RESTART"}:
        raise QuickStepInputError("dft.wfn_restart_file_name requires dft.scf_guess RESTART or HISTORY_RESTART")
    if model.cell.periodic != "NONE" and any(
        _vector_norm(vector) == 0.0 for vector in (model.cell.a, model.cell.b, model.cell.c)
    ):
        raise QuickStepInputError("periodic cell vectors must be non-zero")
    if model.dft.cutoff <= 0 or model.dft.rel_cutoff <= 0:
        raise QuickStepInputError("cutoff and rel_cutoff must be positive")
    if model.dft.xc_pbe_parametrization not in PBE_PARAMETRIZATIONS:
        raise QuickStepInputError("dft.xc_pbe_parametrization has an unsupported value")
    if model.dft.xc_pbe_parametrization != "ORIG" and model.dft.xc_functional != "PBE":
        raise QuickStepInputError("dft.xc_pbe_parametrization requires dft.xc_functional PBE")
    if model.dft.dispersion_type not in DISPERSION_TYPES:
        raise QuickStepInputError("dft.dispersion_type has an unsupported value")
    if model.dft.dispersion_enabled and not model.dft.dispersion_parameter_file_name.strip():
        raise QuickStepInputError("dft.dispersion_parameter_file_name must be a non-empty string")
    if model.dft.dispersion_enabled and not model.dft.dispersion_reference_functional.strip():
        raise QuickStepInputError("dft.dispersion_reference_functional must be a non-empty string")
    if model.dft.multiplicity <= 0:
        raise QuickStepInputError("dft.multiplicity must be positive")
    if model.dft.multiplicity > 1 and not model.dft.uks_enabled:
        raise QuickStepInputError("dft.multiplicity greater than 1 requires dft.uks_enabled")
    if model.dft.max_scf <= 0:
        raise QuickStepInputError("max_scf must be positive")
    if model.dft.outer_scf_max_scf <= 0:
        raise QuickStepInputError("dft.outer_scf_max_scf must be positive")
    eps_scf = _positive_float(model.dft.eps_scf, "dft.eps_scf")
    outer_scf_eps_scf = _positive_float(model.dft.outer_scf_eps_scf, "dft.outer_scf_eps_scf")
    if model.dft.outer_scf_enabled and outer_scf_eps_scf > eps_scf:
        raise QuickStepInputError("dft.outer_scf_eps_scf must be less than or equal to dft.eps_scf")
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
    if model.dft.kpoints_scheme not in KPOINTS_SCHEMES:
        raise QuickStepInputError("dft.kpoints_scheme has an unsupported value")
    if model.dft.kpoints_wavefunctions not in KPOINTS_WAVEFUNCTIONS:
        raise QuickStepInputError("dft.kpoints_wavefunctions has an unsupported value")
    if any(value <= 0 for value in model.dft.kpoints_grid):
        raise QuickStepInputError("dft.kpoints_grid values must be positive")
    if model.dft.mixing_enabled and model.dft.scf_method != "DIAGONALIZATION":
        raise QuickStepInputError("SCF mixing requires dft.scf_method DIAGONALIZATION")
    if model.dft.smearing_enabled and model.dft.scf_method != "DIAGONALIZATION":
        raise QuickStepInputError("SCF smearing requires dft.scf_method DIAGONALIZATION")
    if model.dft.smearing_enabled and model.dft.added_mos == 0:
        raise QuickStepInputError("SCF smearing requires dft.added_mos to add unoccupied orbitals")
    _positive_float(model.dft.mixing_alpha, "dft.mixing_alpha")
    _positive_float(model.dft.mixing_beta, "dft.mixing_beta")
    _positive_float(model.dft.electronic_temperature, "dft.electronic_temperature")
    if model.dft.kpoints_scheme != "NONE" and model.cell.periodic == "NONE":
        raise QuickStepInputError("KPOINTS require a periodic cell")
    if model.dft.kpoints_scheme == "NONE" and (
        model.dft.kpoints_full_grid or model.dft.kpoints_symmetry or model.dft.kpoints_wavefunctions != "COMPLEX"
    ):
        raise QuickStepInputError("KPOINTS options require dft.kpoints_scheme other than NONE")
    if model.geo_opt.optimizer not in MOTION_OPTIMIZERS:
        raise QuickStepInputError("geo_opt.optimizer has an unsupported value")
    if model.geo_opt.max_iter <= 0:
        raise QuickStepInputError("geo_opt.max_iter must be positive")
    if model.cell_opt.optimizer not in MOTION_OPTIMIZERS:
        raise QuickStepInputError("cell_opt.optimizer has an unsupported value")
    if model.cell_opt.max_iter <= 0:
        raise QuickStepInputError("cell_opt.max_iter must be positive")
    if model.cell_opt.type not in CELL_OPT_TYPES:
        raise QuickStepInputError("cell_opt.type has an unsupported value")
    _positive_float(model.cell_opt.pressure_tolerance, "cell_opt.pressure_tolerance")
    if model.run_type == "CELL_OPT" and model.cell.periodic == "NONE":
        raise QuickStepInputError("CELL_OPT requires a periodic cell")
    if model.motion.fixed_atom_components not in FIXED_ATOM_COMPONENTS:
        raise QuickStepInputError("motion.fixed_atom_components has an unsupported value")
    if model.motion.fixed_atoms:
        if model.run_type not in {"GEO_OPT", "CELL_OPT"}:
            raise QuickStepInputError("motion.fixed_atoms requires run_type GEO_OPT or CELL_OPT")
        if any(index <= 0 for index in model.motion.fixed_atoms):
            raise QuickStepInputError("motion.fixed_atoms must contain positive 1-based atom indices")
        if len(set(model.motion.fixed_atoms)) != len(model.motion.fixed_atoms):
            raise QuickStepInputError("motion.fixed_atoms must not contain duplicate indices")
        atom_count = len(model.atoms)
        out_of_range = [index for index in model.motion.fixed_atoms if index > atom_count]
        if out_of_range:
            raise QuickStepInputError(
                "motion.fixed_atoms contains atom indices outside the structure atom count: "
                + ", ".join(str(index) for index in out_of_range)
            )


def render_quickstep_input(model: QuickStepInput) -> str:
    validate_quickstep_input(model)
    lines: list[str] = [
        "# Generated by WinQStep. You can edit this CP2K input manually.",
        "&GLOBAL",
        f"  PROJECT_NAME {model.project_name}",
        f"  RUN_TYPE {model.run_type}",
        *_render_global_print_level(model),
        "&END GLOBAL",
        "",
        "&FORCE_EVAL",
        "  METHOD QS",
        *_render_force_eval_keywords(model),
        *_render_force_eval_print(model),
        "  &DFT",
        f"    BASIS_SET_FILE_NAME {model.dft.basis_set_file_name}",
        f"    POTENTIAL_FILE_NAME {model.dft.potential_file_name}",
        f"    CHARGE {model.dft.charge}",
        f"    MULTIPLICITY {model.dft.multiplicity}",
        *_render_spin_keywords(model.dft),
        *_render_wfn_restart_file_name(model.dft),
        "    &MGRID",
        f"      CUTOFF {model.dft.cutoff}",
        f"      REL_CUTOFF {model.dft.rel_cutoff}",
        "    &END MGRID",
        "    &POISSON",
        f"      PERIODIC {model.cell.periodic}",
        *_render_poisson_solver(model.dft),
        "    &END POISSON",
        *_render_kpoints(model),
        "    &SCF",
        *_render_scf_guess(model.dft),
        f"      EPS_SCF {model.dft.eps_scf}",
        f"      MAX_SCF {model.dft.max_scf}",
        *_render_scf_extras(model.dft),
        "    &END SCF",
        *_render_xc(model.dft),
        *_render_dft_print(model.dft),
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

    motion_lines = _render_motion(model)
    if motion_lines:
        lines.extend(["", *motion_lines])

    return "\n".join(lines) + "\n"


def _render_global_print_level(model: QuickStepInput) -> list[str]:
    if model.print_level is None:
        return []
    return [f"  PRINT_LEVEL {model.print_level}"]


def _render_force_eval_print(model: QuickStepInput) -> list[str]:
    if model.run_type != "ENERGY_FORCE":
        return []
    return [
        "  &PRINT",
        "    &FORCES ON",
        "    &END FORCES",
        "  &END PRINT",
    ]


def _render_force_eval_keywords(model: QuickStepInput) -> list[str]:
    if model.run_type != "CELL_OPT":
        return []
    return ["  STRESS_TENSOR ANALYTICAL"]


def _render_spin_keywords(dft: DftSettings) -> list[str]:
    if not dft.uks_enabled:
        return []
    return ["    UKS T"]


def _render_poisson_solver(dft: DftSettings) -> list[str]:
    if dft.poisson_solver is None:
        return []
    return [f"      POISSON_SOLVER {dft.poisson_solver}"]


def _render_wfn_restart_file_name(dft: DftSettings) -> list[str]:
    if dft.wfn_restart_file_name is None:
        return []
    return [f"    WFN_RESTART_FILE_NAME {dft.wfn_restart_file_name}"]


def _render_scf_guess(dft: DftSettings) -> list[str]:
    if dft.scf_guess is None:
        return []
    return [f"      SCF_GUESS {dft.scf_guess}"]


def _render_dft_print(dft: DftSettings) -> list[str]:
    lines: list[str] = []
    if dft.print_mulliken:
        lines.extend(
            [
                "      &MULLIKEN ON",
                "      &END MULLIKEN",
            ]
        )
    if dft.print_lowdin:
        lines.extend(
            [
                "      &LOWDIN ON",
                "      &END LOWDIN",
            ]
        )
    if dft.print_pdos:
        lines.extend(
            [
                "      &PDOS ON",
                "      &END PDOS",
            ]
        )
    if dft.print_e_density_cube:
        lines.extend(
            [
                "      &E_DENSITY_CUBE ON",
                "      &END E_DENSITY_CUBE",
            ]
        )
    if dft.print_v_hartree_cube:
        lines.extend(
            [
                "      &V_HARTREE_CUBE ON",
                "      &END V_HARTREE_CUBE",
            ]
        )
    if dft.print_band_structure:
        lines.extend(
            [
                "      &BAND_STRUCTURE ON",
                f"        FILE_NAME {dft.band_file_name}",
            ]
        )
        if dft.band_added_mos:
            lines.append(f"        ADDED_MOS {dft.band_added_mos}")
        lines.extend(
            [
                "        &KPOINT_SET",
                f"          UNITS {dft.band_kpoint_units}",
                f"          NPOINTS {dft.band_npoints}",
                *[f"          SPECIAL_POINT {point}" for point in dft.band_special_points],
                "        &END KPOINT_SET",
                "      &END BAND_STRUCTURE",
            ]
        )
    if not lines:
        return []
    return ["    &PRINT", *lines, "    &END PRINT"]


def _render_xc(dft: DftSettings) -> list[str]:
    lines = [
        "    &XC",
        f"      &XC_FUNCTIONAL {dft.xc_functional}",
    ]
    if dft.xc_functional == "PBE" and dft.xc_pbe_parametrization != "ORIG":
        lines.append(f"        PARAMETRIZATION {dft.xc_pbe_parametrization}")
    lines.append("      &END XC_FUNCTIONAL")
    if dft.dispersion_enabled:
        lines.extend(
            [
                "      &VDW_POTENTIAL",
                "        POTENTIAL_TYPE PAIR_POTENTIAL",
                "        &PAIR_POTENTIAL",
                f"          TYPE {dft.dispersion_type}",
                f"          PARAMETER_FILE_NAME {dft.dispersion_parameter_file_name}",
                f"          REFERENCE_FUNCTIONAL {dft.dispersion_reference_functional}",
                "        &END PAIR_POTENTIAL",
                "      &END VDW_POTENTIAL",
            ]
        )
    lines.append("    &END XC")
    return lines


def _render_motion(model: QuickStepInput) -> list[str]:
    if model.run_type not in {"GEO_OPT", "CELL_OPT"}:
        return []
    lines = [
        "&MOTION",
        *_render_motion_constraint(model.motion),
    ]
    if model.run_type == "GEO_OPT":
        lines.extend(
            [
                "  &GEO_OPT",
                f"    OPTIMIZER {model.geo_opt.optimizer}",
                f"    MAX_ITER {model.geo_opt.max_iter}",
                "  &END GEO_OPT",
            ]
        )
        lines.append("&END MOTION")
        return lines
    if model.run_type == "CELL_OPT":
        lines.extend(
            [
                "  &CELL_OPT",
                f"    OPTIMIZER {model.cell_opt.optimizer}",
                f"    MAX_ITER {model.cell_opt.max_iter}",
                f"    TYPE {model.cell_opt.type}",
                f"    PRESSURE_TOLERANCE [bar] {model.cell_opt.pressure_tolerance}",
            ]
        )
        if model.cell_opt.keep_angles:
            lines.append("    KEEP_ANGLES T")
        if model.cell_opt.keep_symmetry:
            lines.append("    KEEP_SYMMETRY T")
        lines.extend(["  &END CELL_OPT", "&END MOTION"])
        return lines
    return []


def _render_motion_constraint(motion: MotionSettings) -> list[str]:
    if not motion.fixed_atoms:
        return []
    return [
        "  &CONSTRAINT",
        "    &FIXED_ATOMS",
        f"      LIST {_format_int_list(motion.fixed_atoms)}",
        f"      COMPONENTS_TO_FIX {motion.fixed_atom_components}",
        "    &END FIXED_ATOMS",
        "  &END CONSTRAINT",
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
    if dft.outer_scf_enabled:
        lines.extend(
            [
                "      &OUTER_SCF",
                f"        EPS_SCF {dft.outer_scf_eps_scf}",
                f"        MAX_SCF {dft.outer_scf_max_scf}",
                "      &END OUTER_SCF",
            ]
        )
    return lines


def _render_kpoints(model: QuickStepInput) -> list[str]:
    dft = model.dft
    if dft.kpoints_scheme == "NONE":
        return []

    lines = ["    &KPOINTS"]
    if dft.kpoints_scheme == "MONKHORST-PACK":
        lines.append(f"      SCHEME MONKHORST-PACK {_format_int_triplet(dft.kpoints_grid)}")
    else:
        lines.append("      SCHEME GAMMA")
    if dft.kpoints_full_grid:
        lines.append("      FULL_GRID T")
    if dft.kpoints_symmetry:
        lines.append("      SYMMETRY T")
    if dft.kpoints_wavefunctions != "COMPLEX":
        lines.append(f"      WAVEFUNCTIONS {dft.kpoints_wavefunctions}")
    lines.append("    &END KPOINTS")
    return lines


def _format_vector(vector: tuple[float, float, float]) -> str:
    return " ".join(f"{value:.10g}" for value in vector)


def _format_int_triplet(vector: tuple[int, int, int]) -> str:
    return " ".join(str(value) for value in vector)


def _format_int_list(values: Iterable[int]) -> str:
    return " ".join(str(value) for value in values)


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


def _validate_band_special_point(point: str) -> None:
    parts = point.split()
    if len(parts) != 4:
        raise QuickStepInputError("dft.band_special_points entries must have: label kx ky kz")
    if not parts[0].strip():
        raise QuickStepInputError("dft.band_special_points labels must be non-empty")
    try:
        float(parts[1].replace("D", "E"))
        float(parts[2].replace("D", "E"))
        float(parts[3].replace("D", "E"))
    except ValueError as exc:
        raise QuickStepInputError("dft.band_special_points coordinates must be numeric") from exc


def _validate_poisson_solver_periodicity(poisson_solver: str | None, periodic: str) -> None:
    if poisson_solver is None:
        return
    supported_periodicities = {
        "PERIODIC": {"XYZ"},
        "MULTIPOLE": {"NONE"},
        "MT": {"NONE", "XY", "XZ", "YZ"},
        "ANALYTIC": {"NONE", "X", "Y", "Z", "XY", "XZ", "YZ"},
        "WAVELET": {"NONE", "XY", "XZ", "YZ", "XYZ"},
        "IMPLICIT": PERIODIC_VALUES,
    }[poisson_solver]
    if periodic not in supported_periodicities:
        raise QuickStepInputError(f"dft.poisson_solver {poisson_solver} is unsupported for PERIODIC {periodic}")


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

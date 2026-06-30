"""QuickStep workflow template loading, validation, and saving."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from .quickstep import (
    CELL_OPT_TYPES,
    DIAGONALIZATION_ALGORITHMS,
    KPOINTS_SCHEMES,
    KPOINTS_WAVEFUNCTIONS,
    MIXING_METHODS,
    MOTION_OPTIMIZERS,
    OT_MINIMIZERS,
    OT_PRECONDITIONERS,
    PERIODIC_VALUES,
    PRINT_LEVELS,
    RUN_TYPES,
    SCF_METHODS,
    SMEARING_METHODS,
    CellOptSettings,
    DftSettings,
    GeoOptSettings,
)


TEMPLATE_KEY_ORDER = (
    "project_name",
    "run_type",
    "print_level",
    "dft",
    "geo_opt",
    "cell_opt",
    "structure_transform",
    "kinds",
)
DFT_KEY_ORDER = (
    "basis_set_file_name",
    "potential_file_name",
    "xc_functional",
    "charge",
    "multiplicity",
    "cutoff",
    "rel_cutoff",
    "eps_scf",
    "max_scf",
    "scf_method",
    "added_mos",
    "ot_minimizer",
    "ot_preconditioner",
    "diagonalization_algorithm",
    "mixing_enabled",
    "mixing_method",
    "mixing_alpha",
    "mixing_beta",
    "smearing_enabled",
    "smearing_method",
    "electronic_temperature",
    "kpoints_scheme",
    "kpoints_grid",
    "kpoints_full_grid",
    "kpoints_symmetry",
    "kpoints_wavefunctions",
)
GEO_OPT_KEY_ORDER = ("optimizer", "max_iter")
CELL_OPT_KEY_ORDER = (
    "optimizer",
    "max_iter",
    "type",
    "pressure_tolerance",
    "keep_angles",
    "keep_symmetry",
)
FALLBACK_CELL_FIELD_KEYS = (
    "fallback_cell_periodic",
    "fallback_cell_a",
    "fallback_cell_b",
    "fallback_cell_c",
)
ELEMENT_RE = re.compile(r"^[A-Z][a-z]?$")


class TemplateError(ValueError):
    """Raised when a QuickStep workflow template is invalid."""


def load_template(path: str | Path) -> dict[str, Any]:
    """Load and normalize a workflow template JSON file."""
    template_path = Path(path)
    with template_path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    return normalize_template(data)


def save_template(path: str | Path, data: dict[str, Any]) -> dict[str, Any]:
    """Validate and save a workflow template with stable UTF-8 JSON."""
    template = normalize_template(data)
    Path(path).write_text(
        json.dumps(template, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return template


def normalize_template(data: dict[str, Any]) -> dict[str, Any]:
    """Return a normalized workflow template object."""
    validation = validate_template(data)
    if not validation["valid"]:
        raise TemplateError("; ".join(validation["errors"]))
    return validation["template"]


def validate_template(data: dict[str, Any]) -> dict[str, Any]:
    """Validate a workflow template and return diagnostics plus normalized data."""
    errors: list[str] = []
    warnings: list[str] = []
    if not isinstance(data, dict):
        return {
            "valid": False,
            "errors": ["template file must contain a JSON object"],
            "warnings": [],
            "template": {},
        }

    project_name = _required_string(data.get("project_name"), "project_name", errors)
    run_type = _string_value(data.get("run_type", "ENERGY"), "run_type", errors).upper()
    if run_type and run_type not in RUN_TYPES:
        errors.append("run_type must be ENERGY, ENERGY_FORCE, GEO_OPT, or CELL_OPT")
    print_level = _optional_choice_value(data.get("print_level"), "print_level", PRINT_LEVELS, errors)

    dft = _normalize_dft(_object_value(data.get("dft", {}), "dft", errors), errors)
    geo_opt = _normalize_geo_opt(_object_value(data.get("geo_opt", {}), "geo_opt", errors), errors)
    cell_opt = _normalize_cell_opt(_object_value(data.get("cell_opt", {}), "cell_opt", errors), errors)
    structure_transform = _normalize_structure_transform(data.get("structure_transform", {}), errors, warnings)
    kinds = _normalize_kinds(data.get("kinds"), errors)

    if run_type == "GEO_OPT" and not data.get("geo_opt"):
        warnings.append("GEO_OPT template did not define geo_opt; defaults were added.")
    if run_type == "CELL_OPT" and not data.get("cell_opt"):
        warnings.append("CELL_OPT template did not define cell_opt; defaults were added.")
    if not kinds:
        warnings.append("Template has no usable KIND entries.")

    template: dict[str, Any] = {
        "project_name": project_name,
        "run_type": run_type,
        "dft": dft,
    }
    if print_level:
        template["print_level"] = print_level
    if run_type == "GEO_OPT":
        template["geo_opt"] = geo_opt
    if run_type == "CELL_OPT":
        template["cell_opt"] = cell_opt
    if structure_transform:
        template["structure_transform"] = structure_transform
    template["kinds"] = kinds

    return {
        "valid": not errors,
        "errors": errors,
        "warnings": warnings,
        "template": {
            key: template[key]
            for key in TEMPLATE_KEY_ORDER
            if key in template
        },
    }


def merge_template_fields(template: dict[str, Any], fields: dict[str, Any]) -> dict[str, Any]:
    """Merge flat editable fields into the nested workflow template shape."""
    merged = json.loads(json.dumps(template))
    dft = _ensure_object(merged, "dft")
    geo_opt = _ensure_object(merged, "geo_opt")
    cell_opt = _ensure_object(merged, "cell_opt")

    for key in ("project_name", "run_type"):
        if key in fields:
            merged[key] = fields[key]
    if _field_has_value(fields, "print_level"):
        merged["print_level"] = fields["print_level"]
    elif "print_level" in fields:
        merged.pop("print_level", None)
    for key in DFT_KEY_ORDER:
        if key in fields:
            dft[key] = fields[key]
    if _field_has_value(fields, "optimizer"):
        geo_opt["optimizer"] = fields["optimizer"]
    if _field_has_value(fields, "geo_opt_max_iter"):
        geo_opt["max_iter"] = fields["geo_opt_max_iter"]
    if _field_has_value(fields, "max_iter"):
        geo_opt["max_iter"] = fields["max_iter"]
    if _field_has_value(fields, "cell_opt_optimizer"):
        cell_opt["optimizer"] = fields["cell_opt_optimizer"]
    if _field_has_value(fields, "cell_opt_max_iter"):
        cell_opt["max_iter"] = fields["cell_opt_max_iter"]
    if _field_has_value(fields, "cell_opt_type"):
        cell_opt["type"] = fields["cell_opt_type"]
    if _field_has_value(fields, "cell_opt_pressure_tolerance"):
        cell_opt["pressure_tolerance"] = fields["cell_opt_pressure_tolerance"]
    if "cell_opt_keep_angles" in fields:
        cell_opt["keep_angles"] = _bool_value(fields["cell_opt_keep_angles"])
    if "cell_opt_keep_symmetry" in fields:
        cell_opt["keep_symmetry"] = _bool_value(fields["cell_opt_keep_symmetry"])
    if "center_atoms" in fields:
        transform = _ensure_object(merged, "structure_transform")
        transform["center_atoms"] = _bool_value(fields["center_atoms"])
    if _should_merge_fallback_cell(merged, fields):
        transform = _ensure_object(merged, "structure_transform")
        fallback_cell = _ensure_object(transform, "fallback_cell")
        if "fallback_cell_periodic" in fields:
            fallback_cell["periodic"] = fields["fallback_cell_periodic"]
        if "fallback_cell_a" in fields:
            fallback_cell["a"] = fields["fallback_cell_a"]
        if "fallback_cell_b" in fields:
            fallback_cell["b"] = fields["fallback_cell_b"]
        if "fallback_cell_c" in fields:
            fallback_cell["c"] = fields["fallback_cell_c"]
    if "kinds_text" in fields:
        merged["kinds"] = parse_kinds_text(str(fields["kinds_text"]))
    if "kinds_json" in fields:
        kinds_json = fields["kinds_json"]
        if isinstance(kinds_json, str):
            kinds_json = json.loads(kinds_json)
        merged["kinds"] = kinds_json

    return merged


def kinds_to_text(kinds: list[dict[str, Any]]) -> str:
    """Return KIND entries as editable tab-separated text."""
    lines = []
    for kind in kinds:
        lines.append(
            "\t".join(
                [
                    str(kind.get("element", "")),
                    str(kind.get("basis_set", "")),
                    str(kind.get("potential", "")),
                ]
            )
        )
    return "\n".join(lines)


def parse_kinds_text(text: str) -> list[dict[str, str]]:
    """Parse editable KIND text: element, basis set, potential per line."""
    kinds: list[dict[str, str]] = []
    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 3:
            raise TemplateError(f"kinds_text line {line_number} must have: element basis_set potential")
        kinds.append({"element": parts[0], "basis_set": parts[1], "potential": parts[2]})
    return kinds


def _normalize_dft(data: dict[str, Any], errors: list[str]) -> dict[str, Any]:
    defaults = DftSettings()
    dft = {
        "basis_set_file_name": _required_string(
            data.get("basis_set_file_name", defaults.basis_set_file_name),
            "dft.basis_set_file_name",
            errors,
        ),
        "potential_file_name": _required_string(
            data.get("potential_file_name", defaults.potential_file_name),
            "dft.potential_file_name",
            errors,
        ),
        "xc_functional": _required_string(
            data.get("xc_functional", defaults.xc_functional),
            "dft.xc_functional",
            errors,
        ).upper(),
        "charge": _int_value(data.get("charge", defaults.charge), "dft.charge", errors),
        "multiplicity": _positive_int_value(
            data.get("multiplicity", defaults.multiplicity),
            "dft.multiplicity",
            errors,
        ),
        "cutoff": _positive_int_value(data.get("cutoff", defaults.cutoff), "dft.cutoff", errors),
        "rel_cutoff": _positive_int_value(
            data.get("rel_cutoff", defaults.rel_cutoff),
            "dft.rel_cutoff",
            errors,
        ),
        "eps_scf": _eps_value(data.get("eps_scf", defaults.eps_scf), errors),
        "max_scf": _positive_int_value(data.get("max_scf", defaults.max_scf), "dft.max_scf", errors),
        "scf_method": _choice_value(
            data.get("scf_method", defaults.scf_method),
            "dft.scf_method",
            SCF_METHODS,
            errors,
        ),
        "added_mos": _int_min_value(data.get("added_mos", defaults.added_mos), "dft.added_mos", -1, errors),
        "ot_minimizer": _choice_value(
            data.get("ot_minimizer", defaults.ot_minimizer),
            "dft.ot_minimizer",
            OT_MINIMIZERS,
            errors,
        ),
        "ot_preconditioner": _choice_value(
            data.get("ot_preconditioner", defaults.ot_preconditioner),
            "dft.ot_preconditioner",
            OT_PRECONDITIONERS,
            errors,
        ),
        "diagonalization_algorithm": _choice_value(
            data.get("diagonalization_algorithm", defaults.diagonalization_algorithm),
            "dft.diagonalization_algorithm",
            DIAGONALIZATION_ALGORITHMS,
            errors,
        ),
        "mixing_enabled": _bool_value(data.get("mixing_enabled", defaults.mixing_enabled)),
        "mixing_method": _choice_value(
            data.get("mixing_method", defaults.mixing_method),
            "dft.mixing_method",
            MIXING_METHODS,
            errors,
        ),
        "mixing_alpha": _positive_float_string(data.get("mixing_alpha", defaults.mixing_alpha), "dft.mixing_alpha", errors),
        "mixing_beta": _positive_float_string(data.get("mixing_beta", defaults.mixing_beta), "dft.mixing_beta", errors),
        "smearing_enabled": _bool_value(data.get("smearing_enabled", defaults.smearing_enabled)),
        "smearing_method": _choice_value(
            data.get("smearing_method", defaults.smearing_method),
            "dft.smearing_method",
            SMEARING_METHODS,
            errors,
        ),
        "electronic_temperature": _positive_float_string(
            data.get("electronic_temperature", defaults.electronic_temperature),
            "dft.electronic_temperature",
            errors,
        ),
        "kpoints_scheme": _choice_value(
            data.get("kpoints_scheme", defaults.kpoints_scheme),
            "dft.kpoints_scheme",
            KPOINTS_SCHEMES,
            errors,
        ),
        "kpoints_grid": _positive_int_triplet_value(
            data.get("kpoints_grid", defaults.kpoints_grid),
            "dft.kpoints_grid",
            errors,
        ),
        "kpoints_full_grid": _bool_value(data.get("kpoints_full_grid", defaults.kpoints_full_grid)),
        "kpoints_symmetry": _bool_value(data.get("kpoints_symmetry", defaults.kpoints_symmetry)),
        "kpoints_wavefunctions": _choice_value(
            data.get("kpoints_wavefunctions", defaults.kpoints_wavefunctions),
            "dft.kpoints_wavefunctions",
            KPOINTS_WAVEFUNCTIONS,
            errors,
        ),
    }
    if dft["mixing_enabled"] and dft["scf_method"] != "DIAGONALIZATION":
        errors.append("dft.mixing_enabled requires dft.scf_method DIAGONALIZATION")
    if dft["smearing_enabled"] and dft["scf_method"] != "DIAGONALIZATION":
        errors.append("dft.smearing_enabled requires dft.scf_method DIAGONALIZATION")
    if dft["smearing_enabled"] and dft["added_mos"] == 0:
        errors.append("dft.smearing_enabled requires dft.added_mos to add unoccupied orbitals")
    if dft["kpoints_scheme"] == "NONE" and (
        dft["kpoints_full_grid"] or dft["kpoints_symmetry"] or dft["kpoints_wavefunctions"] != "COMPLEX"
    ):
        errors.append("KPOINTS options require dft.kpoints_scheme other than NONE")
    return {key: dft[key] for key in DFT_KEY_ORDER}


def _normalize_geo_opt(data: dict[str, Any], errors: list[str]) -> dict[str, Any]:
    defaults = GeoOptSettings()
    geo_opt = {
        "optimizer": _choice_value(
            data.get("optimizer", defaults.optimizer),
            "geo_opt.optimizer",
            MOTION_OPTIMIZERS,
            errors,
        ),
        "max_iter": _positive_int_value(data.get("max_iter", defaults.max_iter), "geo_opt.max_iter", errors),
    }
    return {key: geo_opt[key] for key in GEO_OPT_KEY_ORDER}


def _normalize_cell_opt(data: dict[str, Any], errors: list[str]) -> dict[str, Any]:
    defaults = CellOptSettings()
    cell_opt = {
        "optimizer": _choice_value(
            data.get("optimizer", defaults.optimizer),
            "cell_opt.optimizer",
            MOTION_OPTIMIZERS,
            errors,
        ),
        "max_iter": _positive_int_value(
            data.get("max_iter", defaults.max_iter),
            "cell_opt.max_iter",
            errors,
        ),
        "type": _choice_value(
            data.get("type", defaults.type),
            "cell_opt.type",
            CELL_OPT_TYPES,
            errors,
        ),
        "pressure_tolerance": _positive_float_string(
            data.get("pressure_tolerance", defaults.pressure_tolerance),
            "cell_opt.pressure_tolerance",
            errors,
        ),
        "keep_angles": _bool_value(data.get("keep_angles", defaults.keep_angles)),
        "keep_symmetry": _bool_value(data.get("keep_symmetry", defaults.keep_symmetry)),
    }
    return {key: cell_opt[key] for key in CELL_OPT_KEY_ORDER}


def _normalize_structure_transform(value: Any, errors: list[str], warnings: list[str]) -> dict[str, Any]:
    data = _object_value(value, "structure_transform", errors)
    if not data:
        return {}

    transform: dict[str, Any] = {}
    if "fallback_cell" in data:
        cell = _object_value(data.get("fallback_cell"), "structure_transform.fallback_cell", errors)
        periodic = _string_value(cell.get("periodic", "XYZ"), "structure_transform.fallback_cell.periodic", errors).upper()
        if periodic not in PERIODIC_VALUES:
            errors.append("structure_transform.fallback_cell.periodic has an unsupported value")
        a = _vector_value(cell.get("a"), "structure_transform.fallback_cell.a", errors)
        b = _vector_value(cell.get("b"), "structure_transform.fallback_cell.b", errors)
        c = _vector_value(cell.get("c"), "structure_transform.fallback_cell.c", errors)
        if periodic != "NONE" and any(_vector_norm(vector) == 0.0 for vector in (a, b, c)):
            warnings.append("Periodic fallback cell has zero-length vectors; CP2K will need a usable CELL.")
        transform["fallback_cell"] = {
            "periodic": periodic,
            "a": a,
            "b": b,
            "c": c,
        }
    if "center_atoms" in data:
        center_atoms = _bool_value(data.get("center_atoms"))
        if center_atoms or "fallback_cell" in transform:
            transform["center_atoms"] = center_atoms
    return transform


def _normalize_kinds(value: Any, errors: list[str]) -> list[dict[str, str]]:
    if not isinstance(value, list) or not value:
        errors.append("kinds must be a non-empty list")
        return []

    kinds: list[dict[str, str]] = []
    seen: set[str] = set()
    for index, item in enumerate(value):
        data = _object_value(item, f"kinds[{index}]", errors)
        element = _normalize_element(_required_string(data.get("element"), f"kinds[{index}].element", errors), errors)
        basis_set = _required_string(data.get("basis_set"), f"kinds[{index}].basis_set", errors)
        potential = _required_string(data.get("potential"), f"kinds[{index}].potential", errors)
        if element in seen:
            errors.append(f"duplicate KIND entry for element {element}")
        seen.add(element)
        kinds.append({"element": element, "basis_set": basis_set, "potential": potential})
    return kinds


def _object_value(value: Any, key: str, errors: list[str]) -> dict[str, Any]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        errors.append(f"{key} must be an object")
        return {}
    return value


def _ensure_object(data: dict[str, Any], key: str) -> dict[str, Any]:
    value = data.get(key)
    if not isinstance(value, dict):
        value = {}
        data[key] = value
    return value


def _should_merge_fallback_cell(template: dict[str, Any], fields: dict[str, Any]) -> bool:
    if not any(key in fields for key in FALLBACK_CELL_FIELD_KEYS):
        return False
    if any(_field_has_value(fields, key) for key in FALLBACK_CELL_FIELD_KEYS):
        return True
    transform = template.get("structure_transform")
    return isinstance(transform, dict) and isinstance(transform.get("fallback_cell"), dict)


def _field_has_value(fields: dict[str, Any], key: str) -> bool:
    if key not in fields:
        return False
    value = fields[key]
    return not (value is None or (isinstance(value, str) and not value.strip()))


def _required_string(value: Any, key: str, errors: list[str]) -> str:
    text = _string_value(value, key, errors)
    if not text:
        errors.append(f"{key} must be a non-empty string")
    return text


def _string_value(value: Any, key: str, errors: list[str]) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        errors.append(f"{key} must be a string")
        return ""
    return value.strip()


def _int_value(value: Any, key: str, errors: list[str]) -> int:
    if isinstance(value, bool):
        errors.append(f"{key} must be an integer")
        return 0
    try:
        return int(value)
    except (TypeError, ValueError):
        errors.append(f"{key} must be an integer")
        return 0


def _positive_int_value(value: Any, key: str, errors: list[str]) -> int:
    parsed = _int_value(value, key, errors)
    if parsed <= 0:
        errors.append(f"{key} must be positive")
    return parsed


def _positive_int_triplet_value(value: Any, key: str, errors: list[str]) -> list[int]:
    if isinstance(value, str):
        value = [part for part in value.replace(",", " ").split() if part]
    if not isinstance(value, list | tuple) or len(value) != 3:
        errors.append(f"{key} must be a 3-integer vector")
        return [1, 1, 1]

    parsed: list[int] = []
    for item in value:
        if isinstance(item, bool) or not isinstance(item, int | str):
            errors.append(f"{key} must contain integer values")
            return [1, 1, 1]
        try:
            parsed.append(int(item))
        except ValueError:
            errors.append(f"{key} must contain integer values")
            return [1, 1, 1]
    if any(item <= 0 for item in parsed):
        errors.append(f"{key} values must be positive")
    return parsed


def _int_min_value(value: Any, key: str, minimum: int, errors: list[str]) -> int:
    parsed = _int_value(value, key, errors)
    if parsed < minimum:
        errors.append(f"{key} must be {minimum} or greater")
    return parsed


def _choice_value(value: Any, key: str, choices: set[str], errors: list[str]) -> str:
    text = _required_string(value, key, errors).upper()
    if text and text not in choices:
        errors.append(f"{key} has an unsupported value")
    return text


def _optional_choice_value(value: Any, key: str, choices: set[str], errors: list[str]) -> str:
    text = _string_value(value, key, errors).upper()
    if text and text not in choices:
        errors.append(f"{key} has an unsupported value")
    return text


def _eps_value(value: Any, errors: list[str]) -> str:
    text = _string_value(value, "dft.eps_scf", errors).upper()
    try:
        parsed = float(text.replace("D", "E"))
    except ValueError:
        errors.append("dft.eps_scf must be a positive numeric value")
        return text
    if parsed <= 0:
        errors.append("dft.eps_scf must be positive")
    return text


def _positive_float_string(value: Any, key: str, errors: list[str]) -> str:
    text = _string_value(value, key, errors).upper()
    try:
        parsed = float(text.replace("D", "E"))
    except ValueError:
        errors.append(f"{key} must be a positive numeric value")
        return text
    if parsed <= 0:
        errors.append(f"{key} must be positive")
    return text


def _vector_value(value: Any, key: str, errors: list[str]) -> list[float]:
    if isinstance(value, str):
        value = [part for part in re.split(r"[\s,]+", value.strip()) if part]
    if not isinstance(value, list | tuple) or len(value) != 3:
        errors.append(f"{key} must be a 3-vector")
        return [0.0, 0.0, 0.0]
    try:
        return [float(value[0]), float(value[1]), float(value[2])]
    except (TypeError, ValueError):
        errors.append(f"{key} must contain numeric values")
        return [0.0, 0.0, 0.0]


def _vector_norm(vector: list[float]) -> float:
    return sum(value * value for value in vector) ** 0.5


def _normalize_element(value: str, errors: list[str]) -> str:
    stripped = value.strip()
    if not stripped:
        return ""
    normalized = stripped[0].upper() + stripped[1:].lower()
    if not ELEMENT_RE.match(normalized):
        errors.append(f"unsupported element label: {value}")
    return normalized


def _bool_value(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return bool(value)

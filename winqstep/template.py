"""QuickStep workflow template loading, validation, and saving."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from .quickstep import DftSettings, GeoOptSettings, RUN_TYPES


PERIODIC_VALUES = {"NONE", "X", "Y", "Z", "XY", "XZ", "YZ", "XYZ"}
TEMPLATE_KEY_ORDER = (
    "project_name",
    "run_type",
    "dft",
    "geo_opt",
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
)
GEO_OPT_KEY_ORDER = ("optimizer", "max_iter")
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
        errors.append("run_type must be ENERGY, ENERGY_FORCE, or GEO_OPT")

    dft = _normalize_dft(_object_value(data.get("dft", {}), "dft", errors), errors)
    geo_opt = _normalize_geo_opt(_object_value(data.get("geo_opt", {}), "geo_opt", errors), errors)
    structure_transform = _normalize_structure_transform(data.get("structure_transform", {}), errors)
    kinds = _normalize_kinds(data.get("kinds"), errors)

    if run_type == "GEO_OPT" and not data.get("geo_opt"):
        warnings.append("GEO_OPT template did not define geo_opt; defaults were added.")
    if not kinds:
        warnings.append("Template has no usable KIND entries.")

    template: dict[str, Any] = {
        "project_name": project_name,
        "run_type": run_type,
        "dft": dft,
    }
    if run_type == "GEO_OPT":
        template["geo_opt"] = geo_opt
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

    for key in ("project_name", "run_type"):
        if key in fields:
            merged[key] = fields[key]
    for key in DFT_KEY_ORDER:
        if key in fields:
            dft[key] = fields[key]
    if _field_has_value(fields, "optimizer"):
        geo_opt["optimizer"] = fields["optimizer"]
    if _field_has_value(fields, "geo_opt_max_iter"):
        geo_opt["max_iter"] = fields["geo_opt_max_iter"]
    if _field_has_value(fields, "max_iter"):
        geo_opt["max_iter"] = fields["max_iter"]
    if "center_atoms" in fields:
        transform = _ensure_object(merged, "structure_transform")
        transform["center_atoms"] = _bool_value(fields["center_atoms"])
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
    }
    return {key: dft[key] for key in DFT_KEY_ORDER}


def _normalize_geo_opt(data: dict[str, Any], errors: list[str]) -> dict[str, Any]:
    defaults = GeoOptSettings()
    geo_opt = {
        "optimizer": _required_string(
            data.get("optimizer", defaults.optimizer),
            "geo_opt.optimizer",
            errors,
        ).upper(),
        "max_iter": _positive_int_value(data.get("max_iter", defaults.max_iter), "geo_opt.max_iter", errors),
    }
    return {key: geo_opt[key] for key in GEO_OPT_KEY_ORDER}


def _normalize_structure_transform(value: Any, errors: list[str]) -> dict[str, Any]:
    data = _object_value(value, "structure_transform", errors)
    if not data:
        return {}

    transform: dict[str, Any] = {}
    if "fallback_cell" in data:
        cell = _object_value(data.get("fallback_cell"), "structure_transform.fallback_cell", errors)
        periodic = _string_value(cell.get("periodic", "XYZ"), "structure_transform.fallback_cell.periodic", errors).upper()
        if periodic not in PERIODIC_VALUES:
            errors.append("structure_transform.fallback_cell.periodic has an unsupported value")
        transform["fallback_cell"] = {
            "periodic": periodic,
            "a": _vector_value(cell.get("a"), "structure_transform.fallback_cell.a", errors),
            "b": _vector_value(cell.get("b"), "structure_transform.fallback_cell.b", errors),
            "c": _vector_value(cell.get("c"), "structure_transform.fallback_cell.c", errors),
        }
    if "center_atoms" in data:
        transform["center_atoms"] = _bool_value(data.get("center_atoms"))
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


def _vector_value(value: Any, key: str, errors: list[str]) -> list[float]:
    if not isinstance(value, list | tuple) or len(value) != 3:
        errors.append(f"{key} must be a 3-vector")
        return [0.0, 0.0, 0.0]
    try:
        return [float(value[0]), float(value[1]), float(value[2])]
    except (TypeError, ValueError):
        errors.append(f"{key} must contain numeric values")
        return [0.0, 0.0, 0.0]


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

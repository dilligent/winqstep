"""Small CP2K output summary parser."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any


WARNING_COUNT_RE = re.compile(r"The number of warnings for this run is\s*:\s*(\d+)", re.IGNORECASE)
PROGRAM_ENDED_RE = re.compile(r"\bPROGRAM ENDED AT\s+(.+?)\s*$", re.IGNORECASE)
PROGRAM_STOPPED_RE = re.compile(r"\bPROGRAM STOPPED IN\s+(.+?)\s*$", re.IGNORECASE)
FLOAT_RE = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[EeDd][-+]?\d+)?"
TOTAL_ENERGY_RE = re.compile(
    rf"ENERGY\|\s+Total FORCE_EVAL .* energy \[hartree\]\s+({FLOAT_RE})",
    re.IGNORECASE,
)
FORCES_HEADER_RE = re.compile(r"FORCES\|\s+Atomic forces \[(.+?)\]", re.IGNORECASE)
FORCE_ATOM_RE = re.compile(
    rf"FORCES\|\s+(\d+)\s+({FLOAT_RE})\s+({FLOAT_RE})\s+({FLOAT_RE})\s+({FLOAT_RE})",
    re.IGNORECASE,
)
FORCE_SUM_RE = re.compile(
    rf"FORCES\|\s+Sum\s+({FLOAT_RE})\s+({FLOAT_RE})\s+({FLOAT_RE})",
    re.IGNORECASE,
)
FORCE_TOTAL_RE = re.compile(rf"FORCES\|\s+Total atomic force\s+({FLOAT_RE})", re.IGNORECASE)
TIMING_CP2K_RE = re.compile(
    rf"^\s*CP2K\s+\d+\s+{FLOAT_RE}\s+{FLOAT_RE}\s+{FLOAT_RE}\s+{FLOAT_RE}\s+({FLOAT_RE})\s*$",
    re.IGNORECASE,
)
SCF_HEADER_RE = re.compile(r"^\s*SCF WAVEFUNCTION OPTIMIZATION\s*$", re.IGNORECASE)
SCF_STEP_RE = re.compile(
    rf"^\s*(\d+)\s+.+?\s+({FLOAT_RE})\s+({FLOAT_RE})\s+({FLOAT_RE})\s+({FLOAT_RE})\s*$",
    re.IGNORECASE,
)
SCF_CONVERGED_RE = re.compile(r"\bSCF run converged in\s+(\d+)\s+steps\b", re.IGNORECASE)
SCF_LEAVING_RE = re.compile(r"\bLeaving inner SCF loop after reaching\s+(\d+)\s+steps\b", re.IGNORECASE)
SCF_NOT_CONVERGED_RE = re.compile(r"\bSCF run NOT converged\b", re.IGNORECASE)
CELL_PREFIX_RE = re.compile(r"^\s*CELL\|")
CELL_VOLUME_RE = re.compile(rf"^\s*CELL\|\s+Volume\s+\[angstrom\^3\]:\s+({FLOAT_RE})", re.IGNORECASE)
CELL_VECTOR_RE = re.compile(
    rf"^\s*CELL\|\s+Vector\s+([abc])\s+\[(.+?)\]:\s+"
    rf"({FLOAT_RE})\s+({FLOAT_RE})\s+({FLOAT_RE})\s+\|\1\|\s*=\s*({FLOAT_RE})",
    re.IGNORECASE,
)
CELL_ANGLE_RE = re.compile(
    rf"^\s*CELL\|\s+Angle\s+\([^)]+\),\s+(alpha|beta|gamma)\s+\[degree\]:\s+({FLOAT_RE})",
    re.IGNORECASE,
)
CELL_ORTHO_RE = re.compile(r"^\s*CELL\|\s+Numerically orthorhombic:\s+(\S+)", re.IGNORECASE)
CELL_PERIODICITY_RE = re.compile(r"^\s*CELL\|\s+Periodicity\s+(\S+)", re.IGNORECASE)


def unavailable_output_summary(path: str | Path | None = None, error: str | None = None) -> dict[str, Any]:
    """Return the summary shape used when no CP2K output can be parsed."""
    summary: dict[str, Any] = {
        "path": str(path) if path is not None else None,
        "available": False,
        "status": "not_available",
        "warning_count": None,
        "program_ended": False,
        "ended_at": None,
        "stopped_in": None,
        "total_energy_hartree": None,
        "forces": None,
        "walltime_seconds": None,
        "scf": None,
        "cell": None,
    }
    if error:
        summary["error"] = error
    return summary


def parse_cp2k_output_file(path: str | Path) -> dict[str, Any]:
    """Parse a CP2K `.out` file if it exists."""
    output_path = Path(path)
    if not output_path.is_file():
        return unavailable_output_summary(output_path)

    try:
        text = output_path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        return unavailable_output_summary(output_path, str(exc))
    return parse_cp2k_output_text(text, path=output_path)


def parse_cp2k_output_text(text: str, path: str | Path | None = None) -> dict[str, Any]:
    """Extract a compact status summary from CP2K output text."""
    warning_counts = [int(match.group(1)) for match in WARNING_COUNT_RE.finditer(text)]
    ended_at = _last_match_group(PROGRAM_ENDED_RE, text)
    stopped_in = _last_program_stopped_in(text)
    program_ended = ended_at is not None
    total_energy = _last_float_match_group(TOTAL_ENERGY_RE, text)

    return {
        "path": str(path) if path is not None else None,
        "available": True,
        "status": "completed" if program_ended else "incomplete",
        "warning_count": warning_counts[-1] if warning_counts else None,
        "program_ended": program_ended,
        "ended_at": ended_at,
        "stopped_in": stopped_in,
        "total_energy_hartree": total_energy,
        "forces": _last_forces_block(text),
        "walltime_seconds": _last_float_match_group(TIMING_CP2K_RE, text),
        "scf": _last_scf_block(text),
        "cell": _last_cell_block(text),
    }


def _last_match_group(pattern: re.Pattern[str], text: str) -> str | None:
    value = None
    for line in text.splitlines():
        match = pattern.search(line)
        if match:
            value = match.group(1).strip()
    return value


def _last_float_match_group(pattern: re.Pattern[str], text: str) -> float | None:
    value = None
    for line in text.splitlines():
        match = pattern.search(line)
        if match:
            value = _float_value(match.group(1))
    return value


def _last_program_stopped_in(text: str) -> str | None:
    lines = text.splitlines()
    value = None
    for index, line in enumerate(lines):
        match = PROGRAM_STOPPED_RE.search(line)
        if not match:
            continue
        parts = [match.group(1).strip()]
        next_index = index + 1
        while next_index < len(lines):
            continuation = lines[next_index]
            stripped = continuation.strip()
            indentation = len(continuation) - len(continuation.lstrip())
            if indentation < 20 or not stripped or stripped.startswith("-") or "PROGRAM " in stripped:
                break
            parts.append(stripped)
            next_index += 1
        value = "".join(parts)
    return value


def _last_forces_block(text: str) -> dict[str, Any] | None:
    current: dict[str, Any] | None = None
    last: dict[str, Any] | None = None
    for line in text.splitlines():
        header = FORCES_HEADER_RE.search(line)
        if header:
            current = {
                "unit": header.group(1).strip(),
                "atoms": [],
                "sum": None,
                "total_atomic_force": None,
            }
            continue
        if current is None:
            continue

        atom = FORCE_ATOM_RE.search(line)
        if atom:
            current["atoms"].append(
                {
                    "atom": int(atom.group(1)),
                    "x": _float_value(atom.group(2)),
                    "y": _float_value(atom.group(3)),
                    "z": _float_value(atom.group(4)),
                    "norm": _float_value(atom.group(5)),
                }
            )
            continue

        force_sum = FORCE_SUM_RE.search(line)
        if force_sum:
            current["sum"] = {
                "x": _float_value(force_sum.group(1)),
                "y": _float_value(force_sum.group(2)),
                "z": _float_value(force_sum.group(3)),
            }
            continue

        total = FORCE_TOTAL_RE.search(line)
        if total:
            current["total_atomic_force"] = _float_value(total.group(1))
            last = current
            continue

        if line.startswith(" FORCES|") or not current["atoms"]:
            continue
        if current["atoms"]:
            last = current
            current = None
    return last


def _last_scf_block(text: str) -> dict[str, Any] | None:
    current: dict[str, Any] | None = None
    last: dict[str, Any] | None = None
    for line in text.splitlines():
        if SCF_HEADER_RE.match(line):
            if current is not None:
                last = _finalize_scf_summary(current)
            current = _empty_scf_summary()
            continue
        if current is None:
            continue

        step = SCF_STEP_RE.match(line)
        if step:
            current["final_step"] = int(step.group(1))
            current["final_time_seconds"] = _float_value(step.group(2))
            current["final_convergence"] = _float_value(step.group(3))
            current["final_total_energy_hartree"] = _float_value(step.group(4))
            current["final_energy_change_hartree"] = _float_value(step.group(5))
            continue

        leaving = SCF_LEAVING_RE.search(line)
        if leaving:
            current["converged"] = False
            current["step_count"] = int(leaving.group(1))
            last = _finalize_scf_summary(current)
            continue

        if SCF_NOT_CONVERGED_RE.search(line):
            current["converged"] = False
            last = _finalize_scf_summary(current)
            continue

        converged = SCF_CONVERGED_RE.search(line)
        if converged:
            current["converged"] = True
            current["step_count"] = int(converged.group(1))
            last = _finalize_scf_summary(current)
            current = None

    if current is not None:
        last = _finalize_scf_summary(current)
    return last


def _empty_scf_summary() -> dict[str, Any]:
    return {
        "converged": None,
        "step_count": None,
        "final_step": None,
        "final_time_seconds": None,
        "final_convergence": None,
        "final_total_energy_hartree": None,
        "final_energy_change_hartree": None,
    }


def _finalize_scf_summary(summary: dict[str, Any]) -> dict[str, Any]:
    if summary["step_count"] is None and summary["final_step"] is not None:
        summary["step_count"] = summary["final_step"]
    return summary


def _last_cell_block(text: str) -> dict[str, Any] | None:
    current: dict[str, Any] | None = None
    last: dict[str, Any] | None = None
    for line in text.splitlines():
        volume = CELL_VOLUME_RE.match(line)
        if volume:
            current = _empty_cell_summary()
            current["volume_angstrom3"] = _float_value(volume.group(1))
            last = current
            continue

        if not CELL_PREFIX_RE.match(line):
            if current is not None:
                last = current
                current = None
            continue

        if current is None:
            current = _empty_cell_summary()

        vector = CELL_VECTOR_RE.match(line)
        if vector:
            axis = vector.group(1).lower()
            current[axis] = [
                _float_value(vector.group(3)),
                _float_value(vector.group(4)),
                _float_value(vector.group(5)),
            ]
            current["lengths"][axis] = _float_value(vector.group(6))
            last = current
            continue

        angle = CELL_ANGLE_RE.match(line)
        if angle:
            current["angles_degrees"][angle.group(1).lower()] = _float_value(angle.group(2))
            last = current
            continue

        ortho = CELL_ORTHO_RE.match(line)
        if ortho:
            current["orthorhombic"] = _optional_bool(ortho.group(1))
            last = current
            continue

        periodicity = CELL_PERIODICITY_RE.match(line)
        if periodicity:
            current["periodicity"] = periodicity.group(1).strip()
            last = current
            continue

    return last


def _empty_cell_summary() -> dict[str, Any]:
    return {
        "unit": "angstrom",
        "volume_angstrom3": None,
        "a": None,
        "b": None,
        "c": None,
        "lengths": {"a": None, "b": None, "c": None},
        "angles_degrees": {"alpha": None, "beta": None, "gamma": None},
        "orthorhombic": None,
        "periodicity": None,
    }


def _optional_bool(text: str) -> bool | None:
    normalized = text.strip().lower()
    if normalized in {"yes", "true", "1", "on"}:
        return True
    if normalized in {"no", "false", "0", "off"}:
        return False
    return None


def _float_value(text: str) -> float:
    return float(text.replace("D", "E").replace("d", "e"))

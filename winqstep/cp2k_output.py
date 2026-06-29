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


def _float_value(text: str) -> float:
    return float(text.replace("D", "E").replace("d", "e"))

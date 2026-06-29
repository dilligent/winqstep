"""Inspect CP2K data files for basis set and potential labels."""

from __future__ import annotations

import json
import locale
import re
import subprocess
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .jobs import build_wsl_argv
from .paths import shell_quote


DATA_FILE_START = "__WINQSTEP_CP2K_DATA_FILE__"
DATA_FILE_END = "__WINQSTEP_CP2K_DATA_END__"
ELEMENT_RE = re.compile(r"^[A-Z][a-z]?$")
LABEL_NUMERIC_RE = re.compile(r"^[+-]?\d")
ELEMENTS = {
    "H", "He", "Li", "Be", "B", "C", "N", "O", "F", "Ne",
    "Na", "Mg", "Al", "Si", "P", "S", "Cl", "Ar",
    "K", "Ca", "Sc", "Ti", "V", "Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn",
    "Ga", "Ge", "As", "Se", "Br", "Kr",
    "Rb", "Sr", "Y", "Zr", "Nb", "Mo", "Tc", "Ru", "Rh", "Pd", "Ag", "Cd",
    "In", "Sn", "Sb", "Te", "I", "Xe",
    "Cs", "Ba", "La", "Ce", "Pr", "Nd", "Pm", "Sm", "Eu", "Gd", "Tb", "Dy",
    "Ho", "Er", "Tm", "Yb", "Lu",
    "Hf", "Ta", "W", "Re", "Os", "Ir", "Pt", "Au", "Hg",
    "Tl", "Pb", "Bi", "Po", "At", "Rn",
    "Fr", "Ra", "Ac", "Th", "Pa", "U", "Np", "Pu", "Am", "Cm", "Bk", "Cf",
    "Es", "Fm", "Md", "No", "Lr",
    "Rf", "Db", "Sg", "Bh", "Hs", "Mt", "Ds", "Rg", "Cn", "Nh", "Fl", "Mc",
    "Lv", "Ts", "Og",
}
POTENTIAL_METADATA_LABELS = {"s", "p", "d", "f", "g", "nelec", "ul"}


class Cp2kDataError(ValueError):
    """Raised when CP2K data files cannot be inspected."""


Executor = Callable[[list[str]], Any]


def inspect_windows_cp2k_data_dir(
    data_dir: str | Path,
    *,
    cache_path: str | Path | None = None,
    limit_files: int = 50,
) -> dict[str, Any]:
    """Inspect CP2K data files from a local Windows directory."""
    root = Path(data_dir).resolve()
    if not root.is_dir():
        raise Cp2kDataError(f"CP2K data directory does not exist: {root}")

    files: list[dict[str, str]] = []
    for path in sorted(root.iterdir()):
        if not path.is_file() or not _is_cp2k_data_file(path.name):
            continue
        files.append({"name": path.name, "path": str(path), "text": path.read_text(encoding="utf-8", errors="replace")})
        if len(files) >= limit_files:
            break

    inspection = inspect_cp2k_data_texts(files, source={"mode": "windows", "data_dir": str(root)})
    _maybe_write_cache(inspection, cache_path)
    return inspection


def inspect_wsl_cp2k_data_dir(
    *,
    distro: str | None,
    cp2k_data_dir: str | None,
    wsl_shell_prelude: str | None = None,
    timeout: int = 20,
    cache_path: str | Path | None = None,
    limit_files: int = 50,
    executor: Executor | None = None,
) -> dict[str, Any]:
    """Inspect CP2K data files from a configured WSL CP2K data directory."""
    data_dir = str(cp2k_data_dir or "").strip()
    if not data_dir:
        raise Cp2kDataError("cp2k_data_dir is required for WSL data inspection")
    if not data_dir.startswith("/"):
        raise Cp2kDataError("cp2k_data_dir must be an absolute WSL path")

    shell_command = build_wsl_data_dump_command(
        cp2k_data_dir=data_dir,
        wsl_shell_prelude=wsl_shell_prelude,
        limit_files=limit_files,
    )
    argv = build_wsl_argv(distro, shell_command)
    try:
        completed = executor(argv) if executor else default_executor(argv, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise Cp2kDataError(f"WSL data inspection timed out after {exc.timeout} seconds") from exc
    returncode = int(getattr(completed, "returncode", 1))
    stdout = _decode_process_text(getattr(completed, "stdout", ""))
    stderr = _decode_process_text(getattr(completed, "stderr", ""))
    if returncode != 0:
        raise Cp2kDataError(stderr or stdout or f"WSL data inspection failed with return code {returncode}")

    files = parse_wsl_data_dump(stdout)
    inspection = inspect_cp2k_data_texts(
        files,
        source={
            "mode": "wsl",
            "distro": distro,
            "cp2k_data_dir": data_dir,
            "command": argv,
        },
    )
    _maybe_write_cache(inspection, cache_path)
    return inspection


def build_wsl_data_dump_command(
    *,
    cp2k_data_dir: str,
    wsl_shell_prelude: str | None = None,
    limit_files: int = 50,
) -> str:
    """Build a read-only WSL shell command that dumps selected CP2K data files."""
    # Avoid shell variables here: wsl.exe + bash -lc handling differs across Windows hosts.
    lines: list[str] = []
    if wsl_shell_prelude and wsl_shell_prelude.strip():
        lines.append(wsl_shell_prelude.strip())
    quoted_dir = shell_quote(cp2k_data_dir)
    lines.extend(
        [
            "set -e",
            f"test -d {quoted_dir}",
            (
                f"find {quoted_dir} -maxdepth 1 -type f "
                "\\( -name '*BASIS*' -o -name '*POTENTIAL*' \\) "
                f"-printf '{DATA_FILE_START}%f\\n' "
                "-exec cat {} \\; "
                f"-printf '\\n{DATA_FILE_END}%f\\n'"
            ),
        ]
    )
    return "\n".join(lines)


def inspect_cp2k_data_texts(
    files: list[dict[str, str]],
    *,
    source: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Extract basis and potential labels from CP2K data file texts."""
    basis_by_element: dict[str, set[str]] = {}
    potentials_by_element: dict[str, set[str]] = {}
    file_summaries: list[dict[str, Any]] = []

    for file_info in files:
        name = file_info["name"]
        text = file_info.get("text", "")
        file_type = _file_type(name)
        if file_type == "basis":
            labels = _parse_basis_labels(text)
            _merge_labels(basis_by_element, labels)
        elif file_type == "potential":
            labels = _parse_potential_labels(text)
            _merge_labels(potentials_by_element, labels)
        else:
            continue
        file_summaries.append(
            {
                "name": name,
                "type": file_type,
                "line_count": len(text.splitlines()),
            }
        )

    elements = sorted(set(basis_by_element) | set(potentials_by_element))
    labels_by_element = {
        element: {
            "basis_sets": sorted(basis_by_element.get(element, set())),
            "potentials": sorted(potentials_by_element.get(element, set())),
        }
        for element in elements
    }

    return {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "source": source or {},
        "files": file_summaries,
        "basis_sets_by_element": {
            element: sorted(labels)
            for element, labels in sorted(basis_by_element.items())
        },
        "potentials_by_element": {
            element: sorted(labels)
            for element, labels in sorted(potentials_by_element.items())
        },
        "labels_by_element": labels_by_element,
        "counts": {
            "files": len(file_summaries),
            "elements": len(elements),
            "basis_sets": sum(len(labels) for labels in basis_by_element.values()),
            "potentials": sum(len(labels) for labels in potentials_by_element.values()),
        },
    }


def parse_wsl_data_dump(text: str) -> list[dict[str, str]]:
    """Parse the delimiter-based dump produced by `build_wsl_data_dump_command`."""
    files: list[dict[str, str]] = []
    current_name: str | None = None
    current_lines: list[str] = []
    for line in text.splitlines():
        if line.startswith(DATA_FILE_START):
            current_name = line[len(DATA_FILE_START) :].strip()
            current_lines = []
            continue
        if line.startswith(DATA_FILE_END):
            end_name = line[len(DATA_FILE_END) :].strip()
            if current_name and end_name == current_name:
                files.append({"name": current_name, "text": "\n".join(current_lines)})
            current_name = None
            current_lines = []
            continue
        if current_name is not None:
            current_lines.append(line)
    return files


def default_executor(argv: list[str], *, timeout: int) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(argv, capture_output=True, check=False, timeout=timeout)


def _parse_basis_labels(text: str) -> dict[str, set[str]]:
    labels: dict[str, set[str]] = {}
    for line in _candidate_lines(text):
        parts = line.split()
        if len(parts) < 2:
            continue
        element = _normalize_element(parts[0])
        if not element:
            continue
        for label in parts[1:]:
            if LABEL_NUMERIC_RE.match(label):
                break
            if not _is_basis_label(label):
                continue
            labels.setdefault(element, set()).add(label)
    return labels


def _parse_potential_labels(text: str) -> dict[str, set[str]]:
    labels: dict[str, set[str]] = {}
    for line in _candidate_lines(text):
        parts = line.split()
        if len(parts) < 2:
            continue
        element = _normalize_element(parts[0])
        if not element or not _is_potential_label(parts[1]):
            continue
        labels.setdefault(element, set()).add(parts[1])
    return labels


def _candidate_lines(text: str) -> list[str]:
    lines = []
    for raw_line in text.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if line:
            lines.append(line)
    return lines


def _normalize_element(value: str) -> str | None:
    stripped = value.strip()
    if not stripped:
        return None
    element = stripped[0].upper() + stripped[1:].lower()
    return element if ELEMENT_RE.match(element) and element in ELEMENTS else None


def _is_basis_label(value: str) -> bool:
    return not value.startswith("(")


def _is_potential_label(value: str) -> bool:
    label = value.strip()
    if not label or LABEL_NUMERIC_RE.match(label):
        return False
    if label.lower() in POTENTIAL_METADATA_LABELS:
        return False
    upper_label = label.upper()
    return (
        "-" in label
        or upper_label.startswith("GTH")
        or upper_label.startswith("ECP")
        or upper_label in {"ALL", "ALLELECTRON"}
    )


def _merge_labels(target: dict[str, set[str]], source: dict[str, set[str]]) -> None:
    for element, labels in source.items():
        target.setdefault(element, set()).update(labels)


def _file_type(name: str) -> str | None:
    upper_name = name.upper()
    if "POTENTIAL" in upper_name:
        return "potential"
    if "BASIS" in upper_name:
        return "basis"
    return None


def _is_cp2k_data_file(name: str) -> bool:
    return _file_type(name) is not None


def _maybe_write_cache(inspection: dict[str, Any], cache_path: str | Path | None) -> None:
    if cache_path is None:
        return
    path = Path(cache_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(inspection, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def _decode_process_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, bytes):
        candidates: list[str] = []
        if value.startswith((b"\xff\xfe", b"\xfe\xff")) or value.count(b"\x00") > len(value) // 8:
            candidates.extend(["utf-16", "utf-16-le"])
        candidates.extend(["utf-8-sig", locale.getpreferredencoding(False), "gbk"])
        for encoding in candidates:
            try:
                return value.decode(encoding).replace("\x00", "").replace("\ufeff", "")
            except UnicodeDecodeError:
                continue
        return value.decode("utf-8", errors="replace").replace("\x00", "").replace("\ufeff", "")
    return str(value)

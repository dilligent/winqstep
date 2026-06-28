#!/usr/bin/env python3
"""Collect Windows/WSL2/CP2K environment facts for WinQStep."""

from __future__ import annotations

import argparse
import json
import locale
import platform
import shlex
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from winqstep.config import CONFIG_KEYS, config_value, load_config


def decode_output(value: bytes | None) -> str:
    if not value:
        return ""

    candidates: list[str] = []
    if value.startswith((b"\xff\xfe", b"\xfe\xff")) or value.count(b"\x00") > len(value) // 8:
        candidates.extend(["utf-16", "utf-16-le"])
    candidates.extend(["utf-8-sig", locale.getpreferredencoding(False), "gbk"])

    for encoding in candidates:
        try:
            return value.decode(encoding)
        except UnicodeDecodeError:
            continue
    return value.decode("utf-8", errors="replace")


def normalize_text(value: str) -> str:
    """Normalize common Windows/WSL subprocess output quirks."""
    return value.replace("\x00", "").replace("\ufeff", "").strip()


def run_command(args: list[str], timeout: int) -> dict[str, Any]:
    result: dict[str, Any] = {
        "command": args,
        "ok": False,
        "returncode": None,
        "stdout": "",
        "stderr": "",
        "error": None,
    }

    try:
        completed = subprocess.run(
            args,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError as exc:
        result["error"] = f"command not found: {exc.filename}"
        return result
    except subprocess.TimeoutExpired as exc:
        result["error"] = f"timed out after {timeout} seconds"
        result["stdout"] = normalize_text(decode_output(exc.stdout))
        result["stderr"] = normalize_text(decode_output(exc.stderr))
        return result

    result["ok"] = completed.returncode == 0
    result["returncode"] = completed.returncode
    result["stdout"] = normalize_text(decode_output(completed.stdout))
    result["stderr"] = normalize_text(decode_output(completed.stderr))
    return result


def parse_wsl_list(output: str) -> list[dict[str, Any]]:
    distros: list[dict[str, Any]] = []
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line or line.upper().startswith("NAME"):
            continue

        is_default = line.startswith("*")
        if is_default:
            line = line[1:].strip()

        parts = line.split()
        if len(parts) < 3:
            continue

        distros.append(
            {
                "name": " ".join(parts[:-2]),
                "state": parts[-2],
                "version": parts[-1],
                "default": is_default,
            }
        )
    return distros


def build_wsl_shell_command(command: str, prelude: str | None = None) -> str:
    if not prelude:
        return command
    return prelude.rstrip() + "\n" + command


def wsl_bash_command(
    distro: str | None, command: str, prelude: str | None = None
) -> list[str]:
    args = ["wsl.exe"]
    if distro:
        args.extend(["-d", distro])
    args.extend(["--", "bash", "-lc", build_wsl_shell_command(command, prelude)])
    return args


def run_wsl(
    distro: str | None, command: str, timeout: int, prelude: str | None = None
) -> dict[str, Any]:
    return run_command(wsl_bash_command(distro, command, prelude), timeout)


def first_line(text: str) -> str:
    for line in text.splitlines():
        if line.strip():
            return line.strip()
    return ""


def apply_config(args: argparse.Namespace, config: dict[str, Any]) -> argparse.Namespace:
    merged = argparse.Namespace(**vars(args))
    for key in CONFIG_KEYS:
        if not hasattr(merged, key):
            continue
        current = getattr(merged, key)
        if current is None:
            setattr(merged, key, config_value(config, key))

    if merged.timeout is None:
        merged.timeout = 20

    return merged


def probe_wsl(args: argparse.Namespace) -> dict[str, Any]:
    warnings: list[str] = []
    wsl_path = shutil.which("wsl.exe") or shutil.which("wsl")

    report: dict[str, Any] = {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "config": {
            "path": args.config,
        },
        "host": {
            "system": platform.system(),
            "release": platform.release(),
            "version": platform.version(),
            "machine": platform.machine(),
        },
        "wsl": {
            "executable": wsl_path,
            "available": bool(wsl_path),
            "distros": [],
            "selected_distro": args.distro,
            "shell_prelude": args.wsl_shell_prelude,
        },
        "cp2k": {
            "command": args.cp2k_command,
            "version_output": "",
            "data_dir": args.cp2k_data_dir,
            "data_files": [],
        },
        "mpi": {
            "command": args.mpirun_command,
        },
        "workspace": {
            "default_windows_workspace": args.default_windows_workspace,
        },
        "commands": {},
        "warnings": warnings,
    }

    if platform.system() != "Windows":
        warnings.append("This probe is intended to run from Windows.")

    if not wsl_path:
        warnings.append("wsl.exe was not found on PATH.")
        return report

    list_result = run_command(["wsl.exe", "--list", "--verbose"], args.timeout)
    report["commands"]["wsl_list"] = list_result
    if list_result["ok"]:
        distros = parse_wsl_list(list_result["stdout"])
        report["wsl"]["distros"] = distros
        if not args.distro:
            default = next((d for d in distros if d["default"]), None)
            if default:
                report["wsl"]["selected_distro"] = default["name"]
    else:
        warnings.append("Unable to list WSL distros.")
        return report

    selected_distro = report["wsl"]["selected_distro"]
    if not selected_distro:
        warnings.append("No WSL distro selected or detected.")
        return report

    cp2k_command = args.cp2k_command
    if not cp2k_command:
        find_cp2k = run_wsl(
            selected_distro,
            "command -v cp2k.ssmp || command -v cp2k.psmp || command -v cp2k || true",
            args.timeout,
            args.wsl_shell_prelude,
        )
        report["commands"]["find_cp2k"] = find_cp2k
        if find_cp2k["ok"]:
            cp2k_command = first_line(find_cp2k["stdout"])
            report["cp2k"]["command"] = cp2k_command
        else:
            warnings.append("Unable to search for a CP2K command in the selected WSL distro.")

    if not cp2k_command:
        if "find_cp2k" not in report["commands"] or report["commands"]["find_cp2k"]["ok"]:
            warnings.append("No CP2K command was found in the selected WSL distro.")
    else:
        quoted_cp2k = shlex.quote(cp2k_command)
        version = run_wsl(
            selected_distro,
            f"{quoted_cp2k} --version 2>&1",
            args.timeout,
            args.wsl_shell_prelude,
        )
        report["commands"]["cp2k_version"] = version
        report["cp2k"]["version_output"] = version["stdout"] or version["stderr"]
        if not version["ok"]:
            warnings.append("CP2K command is configured or detected, but version probing failed.")

    mpirun_command = args.mpirun_command
    if not mpirun_command:
        find_mpi = run_wsl(
            selected_distro,
            "command -v mpirun || command -v mpiexec || true",
            args.timeout,
            args.wsl_shell_prelude,
        )
        report["commands"]["find_mpi"] = find_mpi
        if find_mpi["ok"]:
            mpirun_command = first_line(find_mpi["stdout"])
            report["mpi"]["command"] = mpirun_command
        else:
            warnings.append("Unable to search for an MPI command in the selected WSL distro.")

    if args.cp2k_data_dir:
        quoted_data_dir = shlex.quote(args.cp2k_data_dir)
        data_dir_check = run_wsl(
            selected_distro,
            f"test -d {quoted_data_dir} && printf '%s' {quoted_data_dir}",
            args.timeout,
            args.wsl_shell_prelude,
        )
        report["commands"]["cp2k_data_dir_check"] = data_dir_check
        if not data_dir_check["ok"]:
            warnings.append("Configured CP2K data directory is not accessible in WSL.")
            return report
        data_dir_value = args.cp2k_data_dir
    else:
        data_dir = run_wsl(
            selected_distro,
            "printf '%s' \"${CP2K_DATA_DIR:-}\"",
            args.timeout,
            args.wsl_shell_prelude,
        )
        report["commands"]["cp2k_data_dir"] = data_dir
        report["cp2k"]["data_dir"] = data_dir["stdout"]
        if not data_dir["ok"]:
            warnings.append("Unable to read CP2K_DATA_DIR from the selected WSL distro.")
            return report
        data_dir_value = data_dir["stdout"]

    if not data_dir_value:
        warnings.append("CP2K_DATA_DIR is not set in the selected WSL distro.")
        return report

    report["cp2k"]["data_dir"] = data_dir_value
    quoted_data_dir = shlex.quote(data_dir_value)
    data_files = run_wsl(
        selected_distro,
        "test -d "
        + quoted_data_dir
        + " && find "
        + quoted_data_dir
        + " -maxdepth 1 -type f \\( -name '*BASIS*' -o -name '*POTENTIAL*' \\) "
        + "-printf '%f\\n' | sort | head -100",
        args.timeout,
        args.wsl_shell_prelude,
    )
    report["commands"]["cp2k_data_files"] = data_files
    if data_files["ok"]:
        report["cp2k"]["data_files"] = [
            line for line in data_files["stdout"].splitlines() if line.strip()
        ]
    else:
        warnings.append("Unable to inspect CP2K_DATA_DIR.")

    if not report["cp2k"]["data_files"]:
        warnings.append("No basis or potential files were found in CP2K_DATA_DIR.")

    return report


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(
        description="Collect WSL2 and CP2K environment facts for WinQStep."
    )
    parser.add_argument("--config", help="Path to a WinQStep JSON config file.")
    parser.add_argument("--distro", help="WSL distro name. Defaults to the WSL default.")
    parser.add_argument(
        "--cp2k-command",
        help="CP2K command inside WSL, for example cp2k.ssmp or /usr/bin/cp2k.ssmp.",
    )
    parser.add_argument(
        "--mpirun-command",
        help="MPI launcher command inside WSL, for example mpirun.",
    )
    parser.add_argument(
        "--cp2k-data-dir",
        help="CP2K data directory inside WSL. Defaults to the CP2K_DATA_DIR environment variable.",
    )
    parser.add_argument(
        "--default-windows-workspace",
        help="Default Windows folder for WinQStep jobs.",
    )
    parser.add_argument(
        "--wsl-shell-prelude",
        help="Shell code to run before each WSL command, such as safe conda cleanup.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=None,
        help="Timeout in seconds for each subprocess call.",
    )
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()
    try:
        config = load_config(args.config)
        args = apply_config(args, config)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    report = probe_wsl(args)
    indent = None if args.compact else 2
    print(json.dumps(report, indent=indent, ensure_ascii=False))
    return 0 if not report["warnings"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

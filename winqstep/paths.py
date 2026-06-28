"""Path conversion helpers for Windows and WSL."""

from __future__ import annotations

import re
import shlex


DRIVE_PATH_PATTERN = re.compile(r"^([a-zA-Z]):[\\/](.*)$")


class PathConversionError(ValueError):
    """Raised when a path cannot be converted safely."""


def windows_path_to_wsl(path: str) -> str:
    """Convert an absolute Windows drive path to a WSL `/mnt/<drive>` path."""
    value = path.strip()
    match = DRIVE_PATH_PATTERN.match(value)
    if not match:
        raise PathConversionError(f"expected an absolute Windows drive path: {path!r}")

    drive = match.group(1).lower()
    rest = match.group(2)
    parts = [part for part in re.split(r"[\\/]+", rest) if part]
    if not parts:
        return f"/mnt/{drive}"
    return "/mnt/" + drive + "/" + "/".join(parts)


def shell_quote(value: str) -> str:
    """Quote a value for a WSL-side POSIX shell command."""
    return shlex.quote(value)

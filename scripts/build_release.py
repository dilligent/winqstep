#!/usr/bin/env python3
"""Build a local WinQStep source release archive."""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import sys
import tomllib
import zipfile
from pathlib import Path
from typing import Any


RELEASE_ROOT_FILES = (
    ".gitignore",
    "README.md",
    "LICENSE",
    "THIRD_PARTY_NOTICES.md",
    "pyproject.toml",
    "WinQStep.ps1",
    "WinQStep.cmd",
)
OPTIONAL_RELEASE_ROOT_FILES = (
    "WinQStep.exe",
)
RELEASE_DIRS = (
    "launcher",
    "winqstep",
    "scripts",
    "resources",
    "examples",
    "docs",
    "tests",
)
EXCLUDED_TOP_LEVEL_DIRS = {
    "build",
    "dist",
    "outputs",
}
EXCLUDED_DIR_NAMES = {
    ".agents",
    ".codex",
    ".git",
    ".pytest_cache",
    ".venv",
    "__pycache__",
}
EXCLUDED_FILE_NAMES = {
    ".env",
    "codex-thread.json",
}
EXCLUDED_PATTERNS = (
    "*.py[cod]",
    "*.winqstep-cache.json",
)
FIXED_ZIP_TIMESTAMP = (2026, 1, 1, 0, 0, 0)


def read_project_version(repo_root: Path) -> str:
    with (repo_root / "pyproject.toml").open("rb") as handle:
        data = tomllib.load(handle)
    return str(data["project"]["version"])


def should_exclude(relative_path: Path) -> bool:
    parts = relative_path.parts
    if not parts:
        return False

    if parts[0] in EXCLUDED_TOP_LEVEL_DIRS:
        return True
    if parts[0].startswith("cp2k-"):
        return True
    if any(part in EXCLUDED_DIR_NAMES for part in parts):
        return True
    if relative_path.name in EXCLUDED_FILE_NAMES:
        return True

    posix_path = relative_path.as_posix()
    return any(
        fnmatch.fnmatch(relative_path.name, pattern) or fnmatch.fnmatch(posix_path, pattern)
        for pattern in EXCLUDED_PATTERNS
    )


def iter_release_files(repo_root: Path) -> list[Path]:
    files: list[Path] = []

    for relative in RELEASE_ROOT_FILES:
        path = repo_root / relative
        if path.is_file() and not should_exclude(Path(relative)):
            files.append(Path(relative))

    for relative in OPTIONAL_RELEASE_ROOT_FILES:
        path = repo_root / relative
        if path.is_file() and not should_exclude(Path(relative)):
            files.append(Path(relative))

    for relative_dir in RELEASE_DIRS:
        directory = repo_root / relative_dir
        if not directory.is_dir():
            continue
        for path in directory.rglob("*"):
            if not path.is_file():
                continue
            relative = path.relative_to(repo_root)
            if not should_exclude(relative):
                files.append(relative)

    return sorted(set(files), key=lambda path: path.as_posix())


def find_missing_required_files(repo_root: Path) -> list[str]:
    missing = [relative for relative in RELEASE_ROOT_FILES if not (repo_root / relative).is_file()]
    missing.extend(relative for relative in RELEASE_DIRS if not (repo_root / relative).is_dir())
    return sorted(missing)


def build_release_plan(repo_root: Path, output_dir: Path | None = None) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    version = read_project_version(repo_root)
    archive_name = f"winqstep-{version}.zip"
    resolved_output_dir = (output_dir or (repo_root / "dist")).resolve()
    files = iter_release_files(repo_root)
    missing = find_missing_required_files(repo_root)
    archive_path = resolved_output_dir / archive_name
    manifest_path = resolved_output_dir / f"winqstep-{version}.manifest.json"

    return {
        "mode": "release_plan",
        "valid": not missing,
        "version": version,
        "archive_root": f"winqstep-{version}",
        "archive_path": str(archive_path),
        "manifest_path": str(manifest_path),
        "file_count": len(files),
        "files": [path.as_posix() for path in files],
        "missing": missing,
        "excluded": {
            "top_level_dirs": sorted(EXCLUDED_TOP_LEVEL_DIRS),
            "dir_names": sorted(EXCLUDED_DIR_NAMES),
            "file_names": sorted(EXCLUDED_FILE_NAMES),
            "patterns": list(EXCLUDED_PATTERNS),
            "cp2k_snapshots": "top-level cp2k-* directories",
        },
        "optional_root_files": list(OPTIONAL_RELEASE_ROOT_FILES),
    }


def build_release_archive(plan: dict[str, Any], repo_root: Path) -> dict[str, Any]:
    if not plan["valid"]:
        raise ValueError("release plan is invalid: " + "; ".join(plan["missing"]))

    repo_root = repo_root.resolve()
    archive_path = Path(plan["archive_path"])
    manifest_path = Path(plan["manifest_path"])
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    archive_root = str(plan["archive_root"])
    files = [Path(relative) for relative in plan["files"]]

    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for relative in files:
            _write_file_to_archive(
                archive,
                repo_root / relative,
                f"{archive_root}/{relative.as_posix()}",
            )

        manifest = {
            "version": plan["version"],
            "archive_root": archive_root,
            "file_count": len(files),
            "files": plan["files"],
        }
        _write_text_to_archive(
            archive,
            f"{archive_root}/RELEASE-MANIFEST.json",
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        )

    digest = _sha256_file(archive_path)
    report = {
        **plan,
        "mode": "release_build",
        "archive_sha256": digest,
        "archive_size": archive_path.stat().st_size,
    }
    manifest_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    return report


def _write_file_to_archive(archive: zipfile.ZipFile, source: Path, archive_name: str) -> None:
    info = zipfile.ZipInfo(archive_name, FIXED_ZIP_TIMESTAMP)
    info.external_attr = (0o644 & 0xFFFF) << 16
    archive.writestr(info, source.read_bytes(), compress_type=zipfile.ZIP_DEFLATED)


def _write_text_to_archive(archive: zipfile.ZipFile, archive_name: str, text: str) -> None:
    info = zipfile.ZipInfo(archive_name, FIXED_ZIP_TIMESTAMP)
    info.external_attr = (0o644 & 0xFFFF) << 16
    archive.writestr(info, text.encode("utf-8"), compress_type=zipfile.ZIP_DEFLATED)


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Build a WinQStep source release zip.")
    parser.add_argument("--repo-root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--output-dir", help="Directory for the release zip and manifest.")
    parser.add_argument("--dry-run", action="store_true", help="Plan the release without writing files.")
    parser.add_argument("--compact", action="store_true", help="Emit compact JSON.")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_dir = Path(args.output_dir).resolve() if args.output_dir else None
    plan = build_release_plan(repo_root, output_dir)
    report = plan if args.dry_run else build_release_archive(plan, repo_root)

    indent = None if args.compact else 2
    print(json.dumps(report, ensure_ascii=False, indent=indent))
    return 0 if report["valid"] else 2


if __name__ == "__main__":
    raise SystemExit(main())

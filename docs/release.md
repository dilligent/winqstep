# Release Packaging

Round 22 adds a local source-release builder for the Windows prototype. It is a
zip packaging step, not a PyPI or installer release.

## Build

Run from the repository root:

```powershell
python .\scripts\build_release.py
```

The command writes:

- `dist/winqstep-<version>.zip`
- `dist/winqstep-<version>.manifest.json`

Use `--dry-run` to inspect the file list without writing artifacts:

```powershell
python .\scripts\build_release.py --dry-run
```

## Contents

The release zip includes the Windows launchers, Python package, scripts,
resources, examples, tests, and documentation needed to run and verify the
prototype from an unpacked folder.

The zip intentionally excludes local/generated artifacts:

- `outputs/`
- `build/`
- `dist/`
- `cp2k-*` source or data snapshots
- `codex-thread.json`
- `*.winqstep-cache.json`
- virtual environments, Python bytecode, and local dotenv files

CP2K binaries, CP2K source snapshots, and CP2K data files remain external
dependencies and are never copied into the release archive.

## Verify

After unpacking the zip on Windows, run:

```powershell
.\WinQStep.ps1 -Diagnostics -SkipLiveProbes
```

Then run the full diagnostics when WSL2 and CP2K are available:

```powershell
.\WinQStep.ps1 -Diagnostics
```

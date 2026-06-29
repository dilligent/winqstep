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

The release builder writes deterministic zip entries and a manifest containing
the archive size, SHA-256, archive root, and included file list.

## Contents

The release zip includes the Windows launchers, Python package, scripts,
resources, examples, tests, and documentation needed to run and verify the
prototype from an unpacked folder.

The sample config uses a relative `outputs` workspace so an unpacked release
writes local job artifacts under that release folder by default. Users can save
an absolute workspace path from the GUI `Config` tab when they want outputs in a
separate project directory.

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

To test the release artifact exactly as a user would receive it, run:

```powershell
python .\scripts\smoke_release_install.py
```

The same release checks are available through the consolidated runner:

```powershell
python .\scripts\run_checks.py --profile release
```

By default this builds a release zip in a temporary directory, extracts it,
checks for required files and excluded paths, and runs:

```powershell
.\WinQStep.ps1 -Diagnostics -SkipLiveProbes
```

from the unpacked folder. To test an existing archive:

```powershell
python .\scripts\smoke_release_install.py --archive .\dist\winqstep-<version>.zip
```

After unpacking the zip on Windows, run:

```powershell
.\WinQStep.ps1 -Diagnostics -SkipLiveProbes
```

Then run the full diagnostics when WSL2 and CP2K are available:

```powershell
.\WinQStep.ps1 -Diagnostics
```

Before handing off a release candidate from a development checkout, run:

```powershell
python .\scripts\run_checks.py --profile all
```

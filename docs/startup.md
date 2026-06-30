# Startup and Diagnostics

Round 18 adds lightweight Windows launchers and a startup diagnostics command.
Round 56 adds an optional thin `WinQStep.exe` launcher for double-click startup.
This is still a developer/local prototype flow, not a formal packaged release.

## Start the GUI

From the repository root:

```powershell
.\WinQStep.ps1
```

If the optional EXE launcher has been built or included in a release zip,
double-click `WinQStep.exe` or run:

```powershell
.\WinQStep.exe
```

From `cmd.exe` or by double-clicking in File Explorer:

```cmd
WinQStep.cmd
```

All launchers run `scripts/start_gui.ps1` with `-ExecutionPolicy Bypass` for
that process only. They do not change the machine-wide PowerShell execution
policy.

Build or refresh the optional `WinQStep.exe` launcher with:

```powershell
python .\scripts\build_launcher.py
```

`WinQStep.exe` is a small .NET Framework executable that locates the sibling
`WinQStep.ps1`, starts Windows PowerShell without opening a separate console
window, and shows a message box if the launcher cannot find required startup
files. It does not bundle Python, PowerShell, WSL, CP2K, or CP2K data files.

Force a GUI language when needed:

```powershell
.\WinQStep.ps1 -Language en-US
.\WinQStep.ps1 -Language zh-CN
```

Without `-Language`, the GUI uses `ui_language` from the config when set, then
falls back to Windows UI culture.

## Startup Diagnostics

Run diagnostics without opening the GUI:

```powershell
.\WinQStep.ps1 -Diagnostics
```

For deterministic checks that do not probe WSL or CP2K:

```powershell
.\WinQStep.ps1 -Diagnostics -SkipLiveProbes
```

The diagnostics path calls `scripts/check_startup.py` and returns JSON covering:

- required repository scripts, launchers, examples, and fixtures;
- Python version, Windows PowerShell availability, and WPF/.NET desktop
  assembly loading;
- active config validation with execution fields required;
- release hygiene checks for generated outputs and local caches;
- optional live WSL/CP2K probing through `scripts/detect_environment.py`.

For routine development checks, use the consolidated runner:

```powershell
python .\scripts\run_checks.py --profile fast
```

See `docs/testing.md` for GUI, release, and live profiles.

## Prerequisites

- Windows with Windows PowerShell 5.1 and WPF desktop assemblies. If the GUI
  reports missing .NET/WPF components, install or enable the .NET desktop
  runtime / .NET Framework WPF support and launch with `powershell.exe`, not
  `pwsh`.
- Python 3.11 or newer on `PATH`.
- Python dependency `ase` installed for structure import.
- WSL2 with the configured distro available.
- A CP2K QuickStep executable inside WSL, such as `cp2k.ssmp`.
- A matching CP2K data directory configured as a WSL path.
- Optional: an MPI launcher such as `mpirun` when running MPI-enabled CP2K.
- Optional for rebuilding `WinQStep.exe`: .NET Framework C# compiler `csc.exe`,
  usually available from Windows .NET Framework build tools.

The sample local config uses direct `cp2k.ssmp` execution and a shell prelude
that deactivates conda before each WSL-side command.

## Release Packaging

Build a local source-release zip with:

```powershell
python .\scripts\build_launcher.py
python .\scripts\build_release.py
```

Use `--dry-run` to inspect the planned archive without writing `dist/`
artifacts. To verify the zip from a clean temporary extraction:

```powershell
python .\scripts\smoke_release_install.py
```

See `docs/release.md` for the full packaging checklist.

## Release Hygiene

The following are local/generated artifacts and should not be committed:

- `outputs/`
- `build/`
- `dist/`
- `*.winqstep-cache.json`
- `WinQStep.exe` in the source checkout; rebuild it locally when needed, or
  include it in a prepared release zip by running `build_launcher.py` before
  `build_release.py`
- `cp2k-*` source or data snapshots
- `codex-thread.json`
- virtual environments and Python bytecode caches

CP2K binaries, source snapshots, and data files remain external dependencies.

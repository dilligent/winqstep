# Startup and Diagnostics

Round 18 adds lightweight Windows launchers and a startup diagnostics command.
This is still a developer/local prototype flow, not a formal packaged release.

## Start the GUI

From the repository root:

```powershell
.\WinQStep.ps1
```

From `cmd.exe` or by double-clicking in File Explorer:

```cmd
WinQStep.cmd
```

Both launchers run `scripts/start_gui.ps1` with `-ExecutionPolicy Bypass` for
that process only. They do not change the machine-wide PowerShell execution
policy.

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
- Python version and PowerShell availability;
- active config validation with execution fields required;
- release hygiene checks for generated outputs and local caches;
- optional live WSL/CP2K probing through `scripts/detect_environment.py`.

## Prerequisites

- Windows with Windows PowerShell 5.1 and WPF desktop assemblies.
- Python 3.11 or newer on `PATH`.
- Python dependency `ase` installed for structure import.
- WSL2 with the configured distro available.
- A CP2K QuickStep executable inside WSL, such as `cp2k.ssmp`.
- A matching CP2K data directory configured as a WSL path.
- Optional: an MPI launcher such as `mpirun` when running MPI-enabled CP2K.

The sample local config uses direct `cp2k.ssmp` execution and a shell prelude
that deactivates conda before each WSL-side command.

## Release Hygiene

The following are local/generated artifacts and should not be committed or
included in future release artifacts:

- `outputs/`
- `build/`
- `dist/`
- `*.winqstep-cache.json`
- `cp2k-*` source or data snapshots
- `codex-thread.json`
- virtual environments and Python bytecode caches

CP2K binaries, source snapshots, and data files remain external dependencies.

# Architecture

WinQStep should be built around a small core that can run without the GUI. The
GUI should call this core instead of owning CP2K-specific behavior directly.

## Layers

- Desktop UI: Windows screens, forms, file pickers, job logs, and progress.
- Core model: typed project settings, calculation settings, and validation.
- Environment probe: WSL distro, CP2K command, MPI command, data directory, and
  available data files.
- Structure sidecar: Python-based structure import/export, initially using ASE.
- Input generator: deterministic rendering from typed options to CP2K input.
- WSL runner: command construction, process lifetime, output collection, and
  cancellation.
- Persistence: project folder layout, recent environments, and user presets.

## GUI Host Boundaries

The PowerShell-hosted WPF GUI is split by responsibility:

- `scripts/start_gui.ps1`: process entry point, window construction, event
  wiring, view state, and user workflows.
- `scripts/gui/WinQStep.xaml`: WPF layout and named controls.
- `scripts/gui/WinQStep.GuiHost.ps1`: reusable host helpers for localization
  loading, Python process invocation, startup diagnostics, UTF-8 file/process
  I/O, and CP2K summary formatting.
- `scripts/gui/WinQStep.GuiControls.ps1`: named-control registration and
  localization application maps for WPF controls.

The GUI helper scripts should not own CP2K input semantics. New QuickStep
features should first land in the Python core and CLI commands, then be exposed
by GUI controls that call those same commands.

## Process Boundaries

CP2K remains an external program. WinQStep should communicate with it through
`wsl.exe` and command-line execution, not by linking or embedding CP2K.

Structure parsing lives in a Python sidecar because the scientific Python
ecosystem already has mature readers for CIF, POSCAR, and XYZ. The first sidecar
API is file-in, JSON-out, with explicit errors that the GUI can display. ASE is
the preferred reader, with small built-in fallback readers for simple fixtures
and offline tests.

## Data Flow

1. Probe environment.
2. Import structure into a normalized JSON structure model.
3. Combine structure data with typed calculation settings.
4. Validate the settings against local environment facts.
5. Render `.inp`.
6. Run CP2K in a dedicated WSL working directory.
7. Copy or expose outputs in the Windows project folder.

## Dependency Policy

WinQStep's own code is GPL-3.0-or-later. Third-party dependencies should be
added through package managers and tracked in a third-party notices document
before release. CP2K code, binaries, and data files should not be copied into the
repository or installer.

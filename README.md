# WinQStep

WinQStep is an unofficial Windows companion for running CP2K QuickStep through WSL2.

The project is intentionally narrow: it helps users generate conservative CP2K
QuickStep input files, run an existing WSL2 CP2K installation, and keep Windows
paths, WSL paths, logs, and output files organized.

WinQStep is not affiliated with the CP2K project.

## Current Stage

This repository is in the foundation stage. The immediate work is to define the
product boundary, capture the Windows/WSL2 execution rules, and build a small
environment probe before adding a GUI.

The local execution plan is tracked in `docs/execution-plan.md`.

## First Target

The first usable version should:

- detect the selected WSL2 distro and CP2K command;
- locate `CP2K_DATA_DIR` and common basis/potential files;
- import a simple structure file through a Python sidecar;
- generate a QuickStep `ENERGY` or `GEO_OPT` input from typed options;
- run CP2K through `wsl.exe` and store outputs in a Windows project folder.

## Development

The first utility is a standard-library Python probe:

```powershell
python .\scripts\detect_environment.py --help
```

Run it from Windows so it can call `wsl.exe`.

## License

WinQStep is licensed under `GPL-3.0-or-later`. See `LICENSE`.

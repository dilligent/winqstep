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

For machine-specific settings, use the sample config:

```powershell
python .\scripts\detect_environment.py --config .\examples\winqstep.config.json
```

To preview the WSL command for a future CP2K job without running it:

```powershell
python .\scripts\build_job_dry_run.py --config .\examples\winqstep.config.json --input D:\Library\自制品\winqstep\outputs\water.inp
```

To render a conservative QuickStep input from JSON:

```powershell
python .\scripts\render_quickstep_input.py --input-json .\examples\quickstep_energy.json
```

To import a structure file as normalized JSON:

```powershell
python .\scripts\import_structure.py --input .\tests\fixtures\structures\water.xyz
```

To combine a structure file with a calculation template and run CP2K:

```powershell
python .\scripts\run_workflow.py --config .\examples\winqstep.config.json --template .\examples\templates\energy_pbe.json --structure .\tests\fixtures\structures\water.xyz --job-dir .\outputs\workflow-energy
```

To render and run a minimal QuickStep job through WSL/CP2K:

```powershell
python .\scripts\run_quickstep_job.py --config .\examples\winqstep.config.json --input-json .\examples\quickstep_energy.json --job-dir .\outputs\smoke-energy
```

## License

WinQStep is licensed under `GPL-3.0-or-later`. See `LICENSE`.

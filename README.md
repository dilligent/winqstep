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

To validate or rewrite that config with stable UTF-8 JSON:

```powershell
python .\scripts\manage_config.py --config .\examples\winqstep.config.json --require-execution
```

To validate or rewrite a workflow template:

```powershell
python .\scripts\manage_template.py --template .\examples\templates\energy_pbe.json
```

To inspect configured CP2K basis and potential labels:

```powershell
python .\scripts\inspect_cp2k_data.py --config .\examples\winqstep.config.json
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

To open the Windows GUI prototype:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start_gui.ps1
```

The GUI can run either the structure/template workflow or an existing `.inp`
file through the same command-line core. It can also browse previous job
metadata from the selected job folder, edit the active WinQStep config, and edit
common QuickStep template settings. It can also inspect CP2K data files and
populate basis/potential choices for template KIND entries. CP2K runs start in
the background so the window remains responsive, with a `Stop` action for
best-effort cancellation, status-bar job paths, and a close-window guard while a
job is active. The `Artifacts` tab gives read-only access to the current job's
input, output, metadata, stdout, and stderr files.

To render and run a minimal QuickStep job through WSL/CP2K:

```powershell
python .\scripts\run_quickstep_job.py --config .\examples\winqstep.config.json --input-json .\examples\quickstep_energy.json --job-dir .\outputs\smoke-energy
```

To run an existing CP2K input file without regenerating it:

```powershell
python .\scripts\run_existing_input.py --config .\examples\winqstep.config.json --input D:\path\to\job.inp --job-dir .\outputs\existing-job
```

Completed jobs include a compact `cp2k_output` summary in metadata with warning
count and CP2K program-end status.

To list previous WinQStep jobs from metadata:

```powershell
python .\scripts\list_job_history.py --workspace .\outputs --limit 10
```

## License

WinQStep is licensed under `GPL-3.0-or-later`. See `LICENSE`.

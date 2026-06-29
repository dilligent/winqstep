# WinQStep

WinQStep is an unofficial Windows companion for running CP2K QuickStep through WSL2.

The project is intentionally narrow: it helps users generate conservative CP2K
QuickStep input files, run an existing WSL2 CP2K installation, and keep Windows
paths, WSL paths, logs, and output files organized.

WinQStep is not affiliated with the CP2K project.

## Current Stage

This repository is a local Windows prototype. It has a PowerShell-hosted WPF GUI
over tested Python commands for QuickStep input generation, existing-input runs,
job history, config/template editing, CP2K data inspection, startup diagnostics,
and source-release packaging.

The local execution plan is tracked in `docs/execution-plan.md`.

## Current Target

The current usable path is:

- configure a WSL2 distro, CP2K command, and CP2K data directory;
- generate conservative QuickStep `ENERGY` or `GEO_OPT` inputs from structures
  and templates;
- run either generated inputs or existing `.inp` files through `wsl.exe`;
- keep inputs, outputs, stdout/stderr logs, metadata, and history in a Windows
  workspace folder;
- package and smoke-test a source release that can be unpacked on Windows.

## Quick Start

From an unpacked WinQStep folder on Windows:

```powershell
.\WinQStep.ps1 -Diagnostics -SkipLiveProbes
```

If the local WSL2/CP2K environment is available, run the full probe:

```powershell
.\WinQStep.ps1 -Diagnostics
```

Open the GUI with:

```powershell
.\WinQStep.ps1
```

The sample config in `examples/winqstep.config.json` defaults job output to the
relative `outputs` folder inside the current WinQStep directory. Edit it from
the GUI `Config` tab or with `scripts/manage_config.py` for your own CP2K paths.

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

To preflight-check a workflow template and structure before previewing or
running CP2K:

```powershell
python .\scripts\validate_job_inputs.py --mode workflow --config .\examples\winqstep.config.json --template .\examples\templates\energy_pbe.json --structure .\tests\fixtures\structures\water.xyz
```

To inspect configured CP2K basis and potential labels:

```powershell
python .\scripts\inspect_cp2k_data.py --config .\examples\winqstep.config.json
```

To preview the WSL command for a future CP2K job without running it:

```powershell
python .\scripts\build_job_dry_run.py --config .\examples\winqstep.config.json --input D:\path\to\water.inp
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
.\WinQStep.ps1
```

To run startup diagnostics without opening the GUI:

```powershell
.\WinQStep.ps1 -Diagnostics
```

To force a GUI language:

```powershell
.\WinQStep.ps1 -Language zh-CN
```

For a persistent preference, set `ui_language` from the GUI `Config` tab and
save the config. An empty value follows Windows UI culture.

The GUI can run either the structure/template workflow or an existing `.inp`
file through the same command-line core. It can also browse previous job
metadata from the selected job folder, edit the active WinQStep config, and edit
common QuickStep template settings. It can also inspect CP2K data files and
populate basis/potential choices for template KIND entries. Before `Preview` or
`Run`, it preflight-checks the active workflow or existing input so common
template, structure, and CP2K data-file issues are visible before CP2K starts.
CP2K runs start in the background so the window remains responsive, with a
`Stop` action for best-effort cancellation, status-bar job paths, and a
close-window guard while a job is active. The `Artifacts` tab gives read-only
access to the current job's input, output, metadata, stdout, and stderr files.

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

Launcher, prerequisite, and release-hygiene notes are in
`docs/startup.md`.
GUI localization notes are in `docs/localization.md`.
Release packaging notes are in `docs/release.md`.

To build a local source-release zip:

```powershell
python .\scripts\build_release.py
```

To build, unpack, and smoke-test that release in a temporary directory:

```powershell
python .\scripts\smoke_release_install.py
```

## License

WinQStep is licensed under `GPL-3.0-or-later`. See `LICENSE`.

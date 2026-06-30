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
source-release packaging, and a buildable thin `WinQStep.exe` launcher.

The current distribution is a source-release zip, not a Windows installer or a
single-file application. A prepared zip may include `WinQStep.exe`, but that
file is only a thin launcher for the existing PowerShell/WPF GUI. It does not
bundle Python, PowerShell, WSL, CP2K, CP2K data files, or Python package
dependencies. Users should expect to unpack the zip on a Windows machine that
already has, or can install, the runtime environment below.

The local execution plan is tracked in `docs/execution-plan.md`.

## Current Target

The current usable path is:

- configure a WSL2 distro, CP2K command, and CP2K data directory;
- generate conservative QuickStep `ENERGY`, `ENERGY_FORCE`, `GEO_OPT`, or
  `CELL_OPT`
  inputs from structures and templates, including common XC/PBE and opt-in
  DFT-D3 settings;
- run either generated inputs, single existing `.inp` files, or serial
  existing-input batches through `wsl.exe`;
- keep inputs, outputs, stdout/stderr logs, metadata, and history in a Windows
  workspace folder;
- package and smoke-test a source release that can be unpacked on Windows.
- optionally build a double-click `WinQStep.exe` launcher that starts the same
  GUI without opening a terminal command first.

## Requirements

WinQStep currently expects these components on the user's Windows computer:

- Windows desktop session with Windows PowerShell 5.1 and WPF desktop
  assemblies available. If the GUI reports missing .NET/WPF components, install
  or enable the .NET desktop runtime / .NET Framework WPF support and launch
  with `powershell.exe`, not `pwsh`. The optional `WinQStep.exe` launcher uses
  the same Windows desktop/.NET Framework foundation to start PowerShell and
  show startup errors.
- Python 3.11 or newer available as `python` on `PATH`.
- Python package dependency `ase>=3.23` for structure import. From the unpacked
  WinQStep folder, install it with:

  ```powershell
  python -m pip install ase
  ```

- WSL2 with the configured Linux distro available through `wsl.exe`.
- A CP2K QuickStep executable path or command name inside WSL, for example
  `/home/user/cp2k/exe/local/cp2k.ssmp`.
- A matching CP2K data directory inside WSL, for example `/home/user/cp2k/data`.
- Optional: an MPI launcher executable path or command name such as `mpirun`
  when using an MPI-enabled CP2K build.

The GUI `Config` tab stores the machine-specific WSL distro, CP2K command,
CP2K data directory, optional MPI command, shell prelude, and Windows job
workspace. The sample config uses direct `cp2k.ssmp` execution and a shell
prelude that deactivates conda before each WSL-side command.
`cp2k_command` and `mpirun_command` are treated as single executable tokens;
do not put extra arguments such as `--bind-to none` in those fields.

CP2K binaries, CP2K source trees, CP2K data files, WSL distros, Python, and
virtual environments are external dependencies and are intentionally not copied
into release archives.

## Quick Start

From an unpacked WinQStep folder on Windows:

```powershell
python -m pip install ase
.\WinQStep.ps1 -Diagnostics -SkipLiveProbes
```

If the local WSL2/CP2K environment is available, run the full probe:

```powershell
.\WinQStep.ps1 -Diagnostics
```

Build or refresh the optional double-click launcher:

```powershell
python .\scripts\build_launcher.py
```

Open the GUI by double-clicking `WinQStep.exe`, or from PowerShell with:

```powershell
.\WinQStep.exe
```

If `WinQStep.exe` is not present, open the same GUI with:

```powershell
.\WinQStep.ps1
```

The tracked sample config in `examples/winqstep.config.example.json` defaults
job output to the relative `outputs` folder inside the current WinQStep
directory. The GUI creates an ignored local working copy at
`examples/winqstep.config.json` on first launch; edit that local copy from the
GUI `Config` tab or with `scripts/manage_config.py` for your own CP2K paths.

If startup diagnostics report that `python`, `powershell`, WPF/.NET desktop
assemblies, `wsl.exe`, the CP2K command, or the CP2K data directory cannot be
found, fix the Windows/WSL environment or the `Config` tab values before running
jobs.

## Development

Run the standard local verification profile with:

```powershell
python .\scripts\run_checks.py
```

Use `python .\scripts\run_checks.py --profile all` before release handoff, and
`--profile live` when WSL2 and the configured CP2K installation should be
probed. The `all` profile includes a release-candidate walkthrough of the main
offline user path. See `docs/testing.md` for the full matrix.

The first utility is a standard-library Python probe:

```powershell
python .\scripts\detect_environment.py --help
```

Run it from Windows so it can call `wsl.exe`.

For machine-specific settings, use the sample config:

```powershell
python .\scripts\detect_environment.py --config .\examples\winqstep.config.example.json
```

To validate the tracked sample config with stable UTF-8 JSON:

```powershell
python .\scripts\manage_config.py --config .\examples\winqstep.config.example.json --require-execution
```

To validate the tracked sample workflow template:

```powershell
python .\scripts\manage_template.py --template .\examples\templates\energy_pbe.example.json
```

For editable work, use the ignored local files created by the GUI:
`examples/winqstep.config.json` and `examples/templates/energy_pbe.json`.

To preflight-check a workflow template and structure before previewing or
running CP2K:

```powershell
python .\scripts\validate_job_inputs.py --mode workflow --config .\examples\winqstep.config.example.json --template .\examples\templates\energy_pbe.example.json --structure .\tests\fixtures\structures\water.xyz
```

To inspect configured CP2K basis and potential labels:

```powershell
python .\scripts\inspect_cp2k_data.py --config .\examples\winqstep.config.example.json
```

To preview the WSL command for a future CP2K job without running it:

```powershell
python .\scripts\build_job_dry_run.py --config .\examples\winqstep.config.example.json --input D:\path\to\water.inp
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
python .\scripts\run_workflow.py --config .\examples\winqstep.config.example.json --template .\examples\templates\energy_pbe.example.json --structure .\tests\fixtures\structures\water.xyz --job-dir .\outputs\workflow-energy
```

To open the Windows GUI prototype:

```powershell
python .\scripts\build_launcher.py
.\WinQStep.exe
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
python .\scripts\run_quickstep_job.py --config .\examples\winqstep.config.example.json --input-json .\examples\quickstep_energy.json --job-dir .\outputs\smoke-energy
```

To run an existing CP2K input file without regenerating it:

```powershell
python .\scripts\run_existing_input.py --config .\examples\winqstep.config.example.json --input D:\path\to\job.inp --job-dir .\outputs\existing-job
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
Release notes are in `docs/release-notes.md`.
Release candidate handoff notes are in `docs/release-candidate-handoff.md`.
Testing matrix notes are in `docs/testing.md`.

To build a local source-release zip:

```powershell
python .\scripts\build_release.py
```

To build, unpack, and smoke-test that release in a temporary directory:

```powershell
python .\scripts\smoke_release_install.py
```

To run the release-candidate user-path walkthrough:

```powershell
python .\scripts\release_candidate_walkthrough.py
```

## License

WinQStep is licensed under `GPL-3.0-or-later`. See `LICENSE`.

# Execution Plan

This plan keeps the near-term WinQStep work executable across Codex sessions.
Each round should end with a focused commit.

## Current Baseline

- Repository name: `winqstep`.
- Product name: WinQStep.
- License: `GPL-3.0-or-later`.
- Current code: standard-library Python core commands plus unit tests.
- Current docs: product scope, architecture, WSL execution rules, CP2K input
  model, workflow, GUI prototype, existing-input jobs, output summaries, and
  job history.
- Next active round: Round 11, configuration editor and validation.
- Known local facts:
  - WSL2 is available.
  - Default distro is `Ubuntu`.
  - `mpirun` is available at `/usr/bin/mpirun`.
  - The direct CP2K executable is `/home/teng/cp2k/exe/local/cp2k.ssmp`.
  - The detected CP2K version is 2025.2.
  - The matching CP2K data directory is `/home/teng/cp2k/data`.
  - WSL-side commands should deactivate conda before probing or running CP2K.
  - `cp2k.ssmp` is available in an interactive WSL shell, but not in the
    non-interactive `bash -lc` shell used by WinQStep.
  - `CP2K_DATA_DIR` is not exported in the selected distro.
  - A separate CP2K 2026.1 data snapshot exists at
    `/mnt/d/Library/自制品/winqstep/cp2k-2026.1/data`, but it should not be the
    default for the CP2K 2025.2 executable.

## Round 1: Configuration File Support

Status: implemented.

Goal: make environment detection work from explicit project configuration, not
only from auto-detection.

Tasks:

- Add a repo-local sample config, such as `examples/winqstep.config.json`.
- Teach `scripts/detect_environment.py` to read a config file.
- Support config keys for `distro`, `cp2k_command`, `mpirun_command`,
  `cp2k_data_dir`, a default Windows workspace folder, and a WSL shell prelude.
- Keep CLI arguments as overrides over config values.
- Add tests for config loading and override precedence.
- Prefer `cp2k.ssmp` in the repo-local sample config because that matches the
  current machine's normal CP2K workflow.

Acceptance:

- `python .\scripts\detect_environment.py --config <file>` emits stable JSON.
- The local CP2K data directory can be configured without exporting
  `CP2K_DATA_DIR` in WSL.
- Unit tests pass.

Commit boundary:

- One commit for config format, loader, tests, and docs.

## Round 2: Path Conversion and Job Model

Status: implemented.

Goal: define how Windows files become WSL-side job commands before running CP2K.

Tasks:

- Add a small module for Windows path to WSL path conversion.
- Define a job folder model: input, output, stderr, metadata, and copied files.
- Add a dry-run command builder for `wsl.exe -d <distro> -- bash -lc ...`.
- Quote paths robustly for both Windows subprocess arguments and WSL shell
  commands.
- Add tests for drive paths, paths with spaces, and non-ASCII paths.

Acceptance:

- Given a Windows `.inp` path, the tool can emit a dry-run command and metadata
  without starting CP2K.
- Tests cover `D:\Library\自制品\...` style paths.

Commit boundary:

- One commit for path conversion, job model, dry-run builder, and tests.

## Round 3: QuickStep Input Generator

Status: implemented.

Goal: generate a small, stable CP2K input file from typed data.

Local verification:

- `examples/quickstep_energy.json` rendered to `outputs/water_energy.inp`.
- `/home/teng/cp2k/exe/local/cp2k.ssmp` completed the generated `ENERGY` job
  with zero CP2K warnings on 2026-06-29.

Tasks:

- Add a typed JSON schema or dataclass model for `ENERGY` and `GEO_OPT`.
- Render sections for `GLOBAL`, `FORCE_EVAL`, `DFT`, `SCF`, `SUBSYS`, and
  `MOTION/GEO_OPT`.
- Keep output order stable.
- Add fixtures for minimal periodic structures.
- Add snapshot-style tests for generated `.inp` files.

Acceptance:

- A minimal `ENERGY` and `GEO_OPT` input can be generated from JSON.
- The generated file is readable and manually editable.
- Tests fail on accidental formatting or keyword regressions.

Commit boundary:

- One commit for model, renderer, fixtures, and tests.

## Round 4: Structure Import Sidecar

Status: implemented.

Goal: normalize CIF, POSCAR, and XYZ into one structure JSON shape.

Local verification:

- ASE `3.29.0` is available on the current machine.
- `scripts/import_structure.py` imports XYZ, POSCAR, and CIF fixtures.
- The normalized JSON contains source metadata, cell vectors, PBC flags,
  periodic label, elements, and Cartesian coordinates.

Tasks:

- Add a Python sidecar command for structure import.
- Prefer ASE for first implementation.
- Record the new dependency and license notes before release.
- Add structure fixtures for CIF, POSCAR, and XYZ.
- Return explicit parse errors that the future GUI can display.

Acceptance:

- The sidecar outputs elements, coordinates, cell vectors, and periodic flags.
- Fixtures parse deterministically.

Commit boundary:

- One commit for sidecar, fixtures, dependency notes, and tests.

## Round 5: Local CP2K Smoke Run

Status: implemented.

Goal: run one minimal CP2K job end to end through WSL.

Local verification:

- `scripts/run_quickstep_job.py` runs the configured CP2K command through WSL.
- The runner writes `.inp`, `.out`, stdout/stderr logs, and metadata in the job
  folder.
- `examples/quickstep_energy.json` completed through the runner in
  `outputs/smoke-round5` on 2026-06-29 with return code `0` and zero CP2K
  warnings.

Tasks:

- Use the configured environment and generated input.
- Create a dedicated job folder.
- Run CP2K directly or through MPI.
- Capture stdout, stderr, return code, and output file paths.
- Preserve raw CP2K output for diagnosis.

Acceptance:

- A minimal `ENERGY` job writes `.inp`, `.out`, and metadata.
- Success and failure are distinguishable from return code and output files.

Commit boundary:

- One commit for runner, smoke fixture, docs, and tests that do not require a
  long CP2K run by default.

## Round 5.5: Structure-to-QuickStep Workflow

Status: implemented.

Goal: connect imported structures to calculation templates so the CLI can
generate and run a QuickStep job without hand-writing full QuickStep JSON.

Tasks:

- Add a workflow layer that imports CIF, POSCAR, or XYZ structure files.
- Merge imported structure facts with a calculation template and KIND library.
- Support fallback cells for structure formats such as XYZ that do not carry a
  usable periodic cell.
- Add a CLI that can run the full workflow or prepare input and metadata only.
- Keep the lower-level QuickStep renderer and runner as the execution path.

Acceptance:

- A workflow command can turn `water.xyz` plus a PBE energy template into a
  rendered CP2K input.
- Missing KIND definitions fail before CP2K is launched.
- Metadata records the structure source, selected elements, atom count, and
  resolved cell.

Commit boundary:

- One commit for workflow composition, CLI, templates, docs, and tests.

## Round 6: GUI Prototype

Status: implemented.

Goal: build a thin Windows UI over the already-tested core workflow.

Local verification:

- The current machine has the .NET Desktop runtime but no .NET SDK, so the first
  WPF prototype is hosted by PowerShell instead of a compiled WPF project.
- `scripts/start_gui.ps1 -SmokeTest` loads the WPF window and validates default
  repository paths without showing the UI.

Tasks:

- Pick WPF or WinUI 3 after the command-line core is stable.
- Add screens for environment config, structure import, input preview, and job
  log.
- Call the same core commands used by tests.

Acceptance:

- GUI can run environment detection and show structured results.
- GUI can preview a generated input without duplicating generator logic.

Commit boundary:

- One commit for initial GUI skeleton and integration notes.

## Round 7: Existing-Input Job Execution

Status: implemented.

Goal: run a user-provided CP2K `.inp` file without regenerating it.

Local verification:

- `scripts/run_existing_input.py` can run a known-good CP2K input through the
  same WSL command path used by generated jobs.

Tasks:

- Add a CLI that accepts an existing Windows input path and optional job folder.
- Reuse the current WSL command builder, CP2K data directory handling, and conda
  cleanup prelude.
- Preserve the original input file instead of rendering or copying over it.
- Record stdout, stderr, return code, output file paths, and metadata.

Acceptance:

- A known-good `.inp` can run through the same WSL/CP2K path.
- The command works independently of the QuickStep JSON and workflow template
  layers.

Commit boundary:

- One commit for existing-input execution, tests, docs, and local smoke output.

## Round 8: GUI Existing-Input Integration

Status: implemented.

Goal: expose the existing-input runner in the GUI prototype.

Local verification:

- `scripts/start_gui.ps1 -SmokeTest` validates both workflow prepare-only and
  existing-input prepare-only paths without launching CP2K.

Tasks:

- Add a GUI mode selector for workflow-generated input vs existing `.inp` input.
- Keep both modes routed through the command-line core scripts.
- Show the selected input path, output path, and metadata consistently.

Acceptance:

- The GUI can preview or run an existing `.inp` without requiring a structure
  file or workflow template.

Commit boundary:

- One commit for GUI integration, smoke test updates, and docs.

## Round 9: Output Summary Parsing

Status: implemented.

Goal: extract a compact status summary from CP2K output files.

Local verification:

- Unit tests cover completed, incomplete, and missing CP2K output.
- `scripts/start_gui.ps1 -SmokeTest` confirms GUI metadata includes output
  summary status for both preview modes.

Tasks:

- Parse CP2K warning count, program end marker, and final status from `.out`
  files.
- Add the parsed summary to metadata after generated, workflow, and existing
  input runs.
- Surface the summary in CLI output and the GUI job log.

Acceptance:

- Successful smoke runs report return code, warning count, and output marker
  without requiring users to inspect the full `.out` file.

Commit boundary:

- One commit for parser, tests, docs, and GUI display updates.

## Round 10: Job History Browser

Status: implemented.

Goal: make generated metadata easier to inspect from the GUI.

Local verification:

- `scripts/list_job_history.py` lists `*.winqstep.json` metadata under a
  workspace folder.
- `scripts/start_gui.ps1 -SmokeTest` validates the WPF history grid and history
  scanner without launching CP2K.

Tasks:

- Scan a selected job folder for `*.winqstep.json` metadata files.
- Show recent jobs with status, return code, warning count, and output path.
- Open selected metadata and CP2K output in the existing GUI log/preview panes.

Acceptance:

- The GUI can list previous generated, workflow, and existing-input runs from a
  workspace folder without rerunning CP2K.

Commit boundary:

- One commit for metadata discovery, GUI list view, tests, and docs.

## Round 11: Configuration Editor and Validation

Goal: make the GUI safer for real local configuration edits.

Tasks:

- Show editable config fields for distro, CP2K command, data directory, MPI
  command, and WSL shell prelude.
- Validate required fields before previewing or running jobs.
- Save a config JSON file with UTF-8 output and stable key order.
- Keep CLI config parsing as the source of truth.

Acceptance:

- Users can inspect and save the active GUI configuration without hand-editing
  JSON.
- Invalid or missing CP2K paths are reported before CP2K is launched.

Commit boundary:

- One commit for GUI config editing, validation tests, and docs.

## Working Rules

- Keep each round small enough to review.
- Commit after each completed round.
- Do not commit `codex-thread.json`, CP2K source snapshots, generated outputs, or
  local virtual environments.
- Prefer deterministic tests over manual-only verification.
- Keep CP2K as an external program invoked through WSL.

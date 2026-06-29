# Execution Plan

This plan keeps the near-term WinQStep work executable across Codex sessions.
Each round should end with a focused commit.

## Current Baseline

- Repository name: `winqstep`.
- Product name: WinQStep.
- License: `GPL-3.0-or-later`.
- Current code: standard-library Python core commands plus unit tests.
- Current docs: product scope, architecture, WSL execution rules, CP2K input
  model, workflow, GUI prototype, existing-input jobs, output summaries, job
  history, config editing, template editing, CP2K data inspection, and
  asynchronous GUI job execution, GUI job lifecycle hardening, GUI output
  inspection, job input preflight validation, startup diagnostics, and GUI
  modularization, GUI localization, persisted GUI language preferences, local
  release packaging, release install smoke testing, and user guide polish.
- Next active round: Round 24, release candidate workflow walkthrough.
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

Status: implemented.

Goal: make the GUI safer for real local configuration edits.

Local verification:

- `scripts/manage_config.py` validates and writes config JSON with stable key
  order and UTF-8 text.
- `scripts/start_gui.ps1 -SmokeTest` validates the GUI config tab and Chinese
  workspace path rendering without launching CP2K.

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

## Round 12: QuickStep Template Editor

Status: implemented.

Goal: let users adjust common QuickStep calculation settings without editing
template JSON by hand.

Local verification:

- `scripts/manage_template.py` validates and writes workflow templates with
  stable UTF-8 JSON.
- `scripts/start_gui.ps1 -SmokeTest` validates the GUI template tab without
  launching CP2K.

Tasks:

- Expose run type, charge, multiplicity, cutoff, SCF limits, basis sets, and
  potentials in the GUI.
- Validate template fields before rendering input.
- Keep the existing JSON template format as the source of truth.
- Save edited templates with stable UTF-8 JSON output.

Acceptance:

- A user can open a template, adjust conservative ENERGY/GEO_OPT settings, and
  preview the generated CP2K input without hand-editing JSON.

Commit boundary:

- One commit for template editing, validation tests, and docs.

## Round 13: CP2K Data File Inspection

Status: implemented.

Goal: help users choose basis sets and potentials from the configured CP2K data
directory.

Local verification:

- `scripts/inspect_cp2k_data.py` parses fixture CP2K data files without WSL.
- A local WSL smoke run inspected `/home/teng/cp2k/data` and wrote
  `outputs/cp2k-data-round13.json`.
- `scripts/start_gui.ps1 -SmokeTest` validates the GUI data label grid without
  launching CP2K.

Tasks:

- Inspect `BASIS*` and `*POTENTIAL*` files from the configured WSL CP2K data
  directory.
- Extract available basis and potential labels for common elements.
- Surface selectable values in the template editor.
- Keep inspection read-only and cache results in job-independent metadata.

Acceptance:

- The GUI can populate basis/potential choices from the configured CP2K data
  directory instead of requiring manual label entry.

Commit boundary:

- One commit for data inspection, GUI population, tests, and docs.

## Round 14: Asynchronous GUI Job Execution

Status: implemented.

Goal: keep the GUI responsive while CP2K jobs run.

Local verification:

- `scripts/start_gui.ps1 -SmokeTest` validates the `Stop` control and the WPF
  shell without launching CP2K.
- Unit tests verify the GUI run button is wired to the async job launcher.
- Unit tests verify cancelled jobs are written back to `.winqstep.json`
  metadata with the existing file/output summary shape.

Tasks:

- Run long CP2K commands in a background job or process.
- Stream or refresh stdout/stderr and CP2K output tails while the job is active.
- Add a cancel/stop action that terminates the wrapper process where possible.
- Keep metadata updates compatible with the existing runner output shape.

Acceptance:

- Starting a CP2K job does not block the GUI event loop, and users can inspect
  logs or cancel a running job from the window.

Commit boundary:

- One commit for async execution plumbing, GUI controls, tests, and docs.

## Round 15: GUI Job Lifecycle Hardening

Status: implemented.

Goal: make long-running and interrupted CP2K jobs easier to supervise.

Local verification:

- `scripts/start_gui.ps1 -SmokeTest` validates the background-job status bar
  field and close-safe GUI shell without launching CP2K.
- `scripts/start_gui.ps1 -LifecycleSmokeTest` starts and stops a controlled
  background process through the same process helpers used by `Run` and `Stop`.
- A real WSL CP2K existing-input run completed successfully in
  `outputs\round15-cp2k-real` with `status=succeeded`, `returncode=0`, and
  `warning_count=0`.

Tasks:

- Manually validate async run and stop behavior against a longer WSL CP2K job.
- Add a close-window guard when a background job is still running.
- Add clearer running-job path/PID/status display.
- Decide whether MPI/WSL process-group cancellation needs a stronger helper.

Acceptance:

- Users can see exactly which job is running, avoid accidentally closing the
  window mid-run, and have documented behavior for interrupted WSL jobs.

Commit boundary:

- One commit for lifecycle hardening, tests, and docs.

## Round 16: GUI Output Inspection Hardening

Status: implemented.

Goal: make completed CP2K jobs easier to inspect from the GUI.

Local verification:

- `scripts/start_gui.ps1 -SmokeTest` validates the `Artifacts` tab, summary
  field, and five read-only artifact view buttons without launching CP2K.
- Unit tests verify the run, history, and artifact button wiring in
  `scripts/start_gui.ps1`.

Tasks:

- Add explicit buttons or actions to open the current input, output, metadata,
  stdout, and stderr files.
- Surface CP2K output summary fields in a compact, scan-friendly panel.
- Make history selection restore the same current-job path/status display used
  by active jobs.
- Keep all file-opening actions read-only.

Acceptance:

- After a run or history selection, users can inspect all relevant job artifacts
  without manually browsing the job folder.

Commit boundary:

- One commit for GUI output inspection controls, tests, and docs.

## Round 17: Input/Template Validation Refinement

Status: implemented.

Goal: catch common QuickStep input and template mistakes before CP2K starts.

Local verification:

- `scripts/validate_job_inputs.py` validates workflow and existing-input jobs
  without launching CP2K.
- Unit tests cover missing workflow KIND coverage, cached CP2K label warnings,
  existing-input data-file warnings, and CLI exit codes.
- `scripts/start_gui.ps1 -SmokeTest` validates the GUI preflight wiring without
  launching CP2K.

Tasks:

- Validate that template KIND entries cover all imported structure elements.
- Add GUI feedback for missing basis/potential selections before `Preview` or
  `Run`.
- Surface validation errors in the relevant tab instead of only in `Job Log`.
- Keep existing-input mode permissive, but warn when referenced files are
  obviously missing from the configured CP2K data directory.

Acceptance:

- Common template/input mistakes are visible before job launch and can be fixed
  from the GUI without reading raw Python exceptions.

Commit boundary:

- One commit for validation changes, tests, and docs.

## Round 18: Windows Launcher and Packaging Polish

Status: implemented.

Goal: make WinQStep easier to start and diagnose from a normal Windows desktop
session.

Local verification:

- `WinQStep.ps1` and `WinQStep.cmd` launch `scripts/start_gui.ps1` with a local
  process-scoped execution policy bypass.
- `scripts/check_startup.py --skip-live-probes` reports required files, config
  validity, launch prerequisites, and release exclusions without opening the
  GUI.
- `scripts/start_gui.ps1 -Diagnostics -SkipLiveProbes` returns startup
  diagnostics JSON without loading the WPF window.

Tasks:

- Add a small Windows launcher wrapper around `scripts/start_gui.ps1`.
- Document execution-policy, Python, WSL, and CP2K prerequisites in one place.
- Add a startup diagnostics path that checks required scripts, config, WSL, and
  CP2K command availability before showing the main window.
- Decide which generated caches and local outputs should stay outside release
  artifacts.

Acceptance:

- A user can start the GUI without typing the full PowerShell command and can
  see actionable startup diagnostics when prerequisites are missing.

Commit boundary:

- One commit for launcher, packaging notes, tests, and docs.

## Round 19: GUI Modularization

Status: implemented.

Goal: reduce the maintenance risk in the PowerShell-hosted WPF prototype.

Local verification:

- `scripts/start_gui.ps1` dot-sources `scripts/gui/WinQStep.GuiHost.ps1` for
  host/process/file helpers.
- The WPF layout is loaded from `scripts/gui/WinQStep.xaml` instead of an
  embedded here-string.
- GUI smoke tests verify the split files are present, loadable, and still
  provide the same controls and workflow smoke paths.

Tasks:

- Split reusable PowerShell helpers out of `scripts/start_gui.ps1`.
- Move the XAML layout into a separate resource file while keeping smoke tests
  deterministic.
- Keep GUI actions routed through CLI/core commands rather than duplicating
  CP2K behavior in PowerShell.
- Add tests that verify the split files are loaded and the current smoke paths
  still work.

Acceptance:

- The GUI remains functionally equivalent, but layout, startup, process, and
  artifact/history helper code can be edited independently.

Commit boundary:

- One commit for GUI file split, tests, and docs.

## Round 20: GUI Localization Foundation

Status: implemented.

Goal: prepare the GUI for Chinese and English UI text without localizing CP2K
keywords, metadata schemas, or raw scientific output.

Local verification:

- `resources/i18n/en-US.json` and `resources/i18n/zh-CN.json` provide GUI
  string resources.
- `scripts/start_gui.ps1 -SmokeTest -Language en-US` and `-Language zh-CN`
  verify that the GUI can start from either resource file.
- Startup diagnostics and GUI prerequisite checks include both localization
  resource files.

Tasks:

- Add resource files for at least `en-US` and `zh-CN` GUI strings.
- Add a small PowerShell localization helper for looking up UI text by stable
  keys.
- Allow the selected UI language to default from Windows culture, with a manual
  config override planned or implemented conservatively.
- Replace high-value hard-coded GUI labels, tab headers, status messages, and
  common error captions with resource lookups.
- Keep CP2K input keywords, JSON keys, file names, paths, stdout, stderr, and
  metadata schemas untranslated.

Acceptance:

- The GUI can start in English or simplified Chinese from resource files while
  existing CLI JSON and CP2K-facing behavior remain stable.

Commit boundary:

- One commit for localization resources, lookup helper, focused GUI wiring,
  tests, and docs.

## Round 21: Localization Coverage and Preferences

Status: implemented.

Goal: make localization selection more ergonomic and broaden coverage without
changing CP2K-facing interfaces.

Round 21 implementation note: this round intentionally did not add new
languages. It focused on persisted preference plumbing for the existing `en-US`
and `zh-CN` resources.

Local verification:

- `ui_language` is a validated WinQStep config key with stable save order.
- The GUI `Config` tab exposes a language selector and saves it through
  `scripts/manage_config.py`.
- `-Language` remains a temporary launcher override and wins over config.
- Resource key completeness checks still compare `en-US` and `zh-CN` key-for-key.

Tasks:

- Decide whether `ui_language` belongs in the WinQStep config schema.
- Add a GUI language selector or documented config override if useful.
- Defer broader localization coverage to a later round; do not add new
  languages in this pass.
- Add resource completeness checks that compare supported languages key-for-key.

Acceptance:

- Users can persist or clearly control their preferred GUI language, and missing
  localization keys are caught by deterministic tests.

Commit boundary:

- One commit for preference plumbing, coverage tests, focused GUI wiring, and
  docs.

## Round 22: Release Packaging and Distribution Pass

Status: implemented.

Goal: produce a local release archive that can be unpacked and run on Windows
without carrying generated outputs, local caches, CP2K snapshots, or Codex
thread state.

Local verification:

- `scripts/build_release.py --dry-run` reports the deterministic release file
  list without writing artifacts.
- `scripts/build_release.py` writes `dist/winqstep-<version>.zip` plus a JSON
  manifest with archive size and SHA-256.
- Unit tests validate the release file list, exclusion rules, dry-run JSON, and
  generated zip contents.
- Startup diagnostics now treat the release builder as a required local file.

Tasks:

- Add a pure-Python release zip builder with explicit include and exclude rules.
- Keep CP2K binaries, CP2K source/data snapshots, `outputs/`, `build/`, `dist/`,
  caches, virtual environments, and `codex-thread.json` out of release archives.
- Document build, dry-run, and post-unpack diagnostics commands.
- Add deterministic tests for release planning and artifact contents.

Acceptance:

- A user can build a local source-release zip from the repository root, inspect
  the manifest, and run startup diagnostics after unpacking it.

Commit boundary:

- One commit for release builder, tests, docs, and startup diagnostics updates.

## Interlude: Template Drop-Down Editing

Status: implemented before Round 23.

Goal: make the GUI template editor faster to use by adding selectable choices
for every single-line template field while preserving direct text entry.

Notes:

- The Template tab now uses editable drop-down controls for project name,
  run type, basis file, potential file, XC functional, charge, multiplicity,
  cutoff, relative cutoff, EPS_SCF, MAX_SCF, GEO_OPT optimizer, and GEO_OPT
  max iterations.
- Template KIND entries now render in an editable `Element`, `Basis Set`,
  `Potential` table while still saving through the existing `kinds_text`
  template writer.
- Run type choices stay within the current WinQStep QuickStep model:
  `ENERGY` and `GEO_OPT`.
- GUI smoke tests verify that all single-line template fields are editable
  drop-down controls, core option lists are present, and template KIND rows are
  shown in the table instead of a visible raw text box.

Commit boundary:

- One commit for GUI template drop-down controls, smoke assertions, and docs.

## Round 23: Release Install Smoke and User Guide Polish

Status: implemented.

Goal: verify the release zip as an unpacked artifact and make the first-run path
clearer for users.

Local verification:

- `scripts/smoke_release_install.py` builds a release archive in a temporary
  directory, extracts it, checks required/unwanted paths, and runs
  `WinQStep.ps1 -Diagnostics -SkipLiveProbes` from the unpacked folder.
- The sample config now uses a relative `outputs` workspace so release folders
  are portable after extraction.
- GUI workspace handling resolves relative workspaces from the WinQStep folder,
  keeping release defaults local to the unpacked directory.

Tasks:

- Add an install smoke command for newly built or existing release zips.
- Include `.gitignore` and the smoke script in release artifacts so unpacked
  startup diagnostics can verify release hygiene.
- Keep diagnostics deterministic by defaulting the install smoke to
  `-SkipLiveProbes`.
- Polish README, startup, release, and configuration notes around first run,
  release verification, and portable output folders.

Acceptance:

- A user can build a zip, smoke-test the unpacked artifact, run startup
  diagnostics from the release folder, and understand where outputs will be
  written by default.

Commit boundary:

- One commit for release install smoke, tests, portable config defaults, and
  user-facing docs.

## Round 24: Consolidated Test Runner

Status: implemented.

Goal: make the expected local verification matrix executable instead of relying
on manually remembered commands.

Local verification:

- `scripts/run_checks.py` exposes `fast`, `gui`, `release`, `live`, and `all`
  profiles as JSON-returning commands.
- The default `fast` profile runs unit tests and offline startup diagnostics.
- The `gui` profile runs WPF smoke checks without WSL/CP2K.
- The `release` profile runs release planning and unpacked release smoke.
- The `live` profile is explicit and probes WSL/CP2K through the configured
  local environment.

Tasks:

- Add a consolidated check runner with a list-only mode for inspecting commands.
- Include the runner in startup diagnostics, GUI prerequisite checks, and release
  install smoke required-file lists.
- Document routine, GUI, release, and live verification paths.

Acceptance:

- A developer can run one command for the default local checks and one profile
  command for GUI, release, or live verification.
- Release artifacts include the same check runner used by the development
  checkout.

Commit boundary:

- One commit for check runner, tests, diagnostics/release wiring, and docs.

## Round 25: GUI Tab Order Polish

Status: implemented.

Goal: make the lower tab bar match the user workflow better after trial-user
feedback.

Local verification:

- GUI smoke tests now report the actual WPF tab order.
- Static GUI tests verify the XAML `TabItem` order.

Tasks:

- Move `Input Preview` next to `Template`.
- Keep the tabs separate for now so the Template editor and read-only generated
  input pane do not crowd each other.
- Move diagnostic tabs after the edit/preview path.

Acceptance:

- The tab order is `Config`, `Template`, `Input Preview`, `Structure`,
  `Environment`, `Job Log`, `Artifacts`, `History`.
- Tests fail if the Template and Input Preview tabs stop being adjacent.

Commit boundary:

- One commit for GUI tab order, smoke assertions, and docs.

## Working Rules

- Keep each round small enough to review.
- Commit after each completed round.
- Do not commit `codex-thread.json`, CP2K source snapshots, generated outputs, or
  local virtual environments.
- Prefer deterministic tests over manual-only verification.
- Keep CP2K as an external program invoked through WSL.

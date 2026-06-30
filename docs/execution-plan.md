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
  inspection, structured GUI result summaries, job input preflight validation,
  startup diagnostics, and GUI modularization, GUI localization, persisted GUI
  language preferences, local release packaging, release install smoke testing,
  release-candidate workflow walkthrough, release handoff notes, final release
  artifact build, release install smoke, live CP2K release validation, and user
  guide polish, GUI async run completion hardening, and window-level GUI
  overflow scrolling, QuickStep CELL/PERIODIC template support, QuickStep SCF
  control expansion, QuickStep KPOINTS support, QuickStep CELL_OPT support, and
  CP2K-section grouping in the Template tab, optional QuickStep
  `GLOBAL/PRINT_LEVEL`, immediate GUI language apply, GUI workflow tab
  ordering, full CP2K input-section labels in the Template tab, and UTF-8
  hardening for live GUI job logs, and readable imported-structure display in
  the GUI Structure tab, and readable environment probe display in the GUI
  Environment tab, QuickStep `SCF/&OUTER_SCF` support, QuickStep `DFT/UKS`
  support, a thin double-click `WinQStep.exe` launcher, and QuickStep
  `DFT/&XC` PBE parametrization plus DFT-D3 support.
- Next active round: Round 58, expand QuickStep coverage from the next selected
  CP2K feature area.
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

- The historical tab-order polish made `Template` and `Input Preview`
  adjacent. The current user-tested order is tracked in Round 41.
- Tests fail if the Template and Input Preview tabs stop being adjacent.

Commit boundary:

- One commit for GUI tab order, smoke assertions, and docs.

## Round 26: Editable Preview Run Path

Status: implemented.

Goal: make manual edits in the `Input Preview` pane affect subsequent runs
without silently overwriting user input files.

Local verification:

- `-EditedPreviewSmokeTest` generates a workflow preview, edits the preview
  text, presses `Run`, and stops before starting CP2K after verifying the edited
  input copy and run arguments.
- GUI unit tests cover the edited-preview smoke report.

Tasks:

- Track the last true input preview text and path in GUI state.
- Detect changed preview text when `Run` is pressed.
- Save edited preview text as `*_edited.inp` in the selected job folder.
- Run that saved copy through the existing-input path.
- Keep original generated or user-provided input files unchanged.

Acceptance:

- Manual preview edits are preserved in the input file passed to CP2K.
- Running an edited preview does not modify the original existing input file.
- Tests fail if edited preview text no longer feeds the prepared run arguments.

Commit boundary:

- One commit for editable preview run plumbing, smoke coverage, and docs.

## Round 27: ENERGY_FORCE Run Type

Status: implemented.

Goal: allow QuickStep templates and generated inputs to use CP2K
`RUN_TYPE ENERGY_FORCE`.

Local verification:

- QuickStep unit tests render `ENERGY_FORCE` and verify it does not add
  `&MOTION/&GEO_OPT`.
- Template tests validate lowercase input normalization to `ENERGY_FORCE`.
- GUI tests assert the run type drop-down includes `ENERGY_FORCE`.

Tasks:

- Add `ENERGY_FORCE` to the typed QuickStep model and template validator.
- Add `ENERGY_FORCE` to the GUI run type drop-down.
- Update current docs that list supported run types.

Acceptance:

- `ENERGY_FORCE` templates validate and render `RUN_TYPE ENERGY_FORCE`.
- Unsupported run types such as `MD` remain rejected.
- GUI smoke/static tests fail if the option disappears from the drop-down.

Commit boundary:

- One commit for ENERGY_FORCE model, GUI, tests, and docs.

## Round 28: ENERGY_FORCE End-to-End

Status: implemented.

Goal: make `ENERGY_FORCE` useful beyond input generation by adding examples,
live validation, force printing, and force summary parsing.

Local verification:

- Generated `tests/fixtures/quickstep_energy_force.inp` from
  `examples/quickstep_energy_force.json`.
- Ran local WSL2 CP2K with `examples/templates/energy_force_pbe.json`; CP2K
  completed successfully with `RUN_TYPE ENERGY_FORCE`.
- Verified CP2K accepts `FORCE_EVAL/&PRINT/&FORCES` and emits `FORCES|` rows.
- Unit tests parse total energy, per-atom forces, force sums, and total atomic
  force from a compact ENERGY_FORCE output fixture.

Tasks:

- Add ENERGY_FORCE example JSON and workflow template.
- Render `FORCE_EVAL/&PRINT/&FORCES` for ENERGY_FORCE inputs.
- Parse `ENERGY| Total FORCE_EVAL ... energy [hartree]`.
- Parse `FORCES| Atomic forces [hartree/bohr]` blocks into metadata.
- Include total energy and total atomic force in the GUI CP2K summary line.

Acceptance:

- ENERGY_FORCE inputs run under local CP2K.
- Job metadata includes energy and force summaries when CP2K prints them.
- Existing ENERGY and GEO_OPT behavior remains unchanged.

Commit boundary:

- One commit for ENERGY_FORCE examples, force printing, force parsing, live
  verification docs, and tests.

## Round 29: GUI Result Summary and Export

Status: implemented.

Goal: make parsed CP2K results easier to inspect and export from the GUI,
especially `ENERGY_FORCE` energy/force summaries.

Local verification:

- `scripts/start_gui.ps1 -SmokeTest -Language en-US` validates the new result
  buttons are present and disabled before a job is selected.
- `scripts/start_gui.ps1 -ButtonSmokeTest -SkipLiveProbes -Language en-US`
  loads a synthetic ENERGY_FORCE history item, opens `Results`, saves
  `button_history.results.txt`, and checks the saved force summary.
- Targeted unit tests cover GUI static wiring, localization keys, startup
  resource completeness, and history energy/force fields.

Tasks:

- Add `Results` and `Save Results` controls to the `Artifacts` tab.
- Build a structured result text summary from job metadata.
- Include total energy, total atomic force, and per-atom forces when available.
- Save the result summary as `*.results.txt` next to job metadata.
- Carry total energy and total atomic force through history scan items.

Acceptance:

- Users can inspect parsed scientific results without opening raw metadata.
- ENERGY_FORCE force tables are visible in the GUI result summary.
- Saved result summaries are deterministic UTF-8 text files.

Commit boundary:

- One commit for result summary GUI controls, history fields, tests, and docs.

## Round 30: Release-Candidate Workflow Walkthrough

Status: implemented.

Goal: make the release-candidate user path executable as a deterministic local
check instead of relying on manual notes.

Local verification:

- `scripts/release_candidate_walkthrough.py --compact --keep-workspace` ran the
  offline walkthrough successfully with 9 passed steps.
- Targeted tests cover the new walkthrough CLI, `run_checks --profile rc`,
  startup required files, release file inclusion, and GUI prerequisite checks.

Tasks:

- Add a standalone RC walkthrough script.
- Validate startup, config, and the ENERGY_FORCE template.
- Preflight and prepare an ENERGY_FORCE workflow job.
- Preflight and prepare an existing-input job without rewriting the source
  input.
- Scan the walkthrough workspace history and verify both jobs appear.
- Check the release dry-run plan includes the walkthrough script.
- Add optional `--include-live` for a real CP2K ENERGY_FORCE walkthrough.
- Add `rc` to `run_checks` and include it in `all`.

Acceptance:

- `python .\scripts\release_candidate_walkthrough.py` returns valid JSON and
  exits zero offline.
- `python .\scripts\run_checks.py --profile all` covers the RC walkthrough.
- The release zip includes the walkthrough script.

Commit boundary:

- One commit for RC walkthrough script, check-runner integration, tests, and
  docs.

## Round 31: Release-Candidate Handoff Notes

Status: implemented.

Goal: make release handoff explicit enough that a tester or future session can
verify, package, and start the candidate without reading the whole repository.

Tasks:

- Add a short handoff document with required commands, expected artifacts,
  tester first-run path, and known limitations.
- Link the handoff document from README and release docs.
- Make release install smoke treat the handoff note as a required unpacked file.
- Add tests that verify the handoff note is discoverable and included in the
  release plan/archive.

Acceptance:

- The source-release zip includes `docs/release-candidate-handoff.md`.
- README points readers to the handoff note.
- Tests fail if the handoff note is missing from release contents.

Commit boundary:

- One commit for handoff documentation, release smoke wiring, tests, and plan
  update.

## Round 32: Final Release Artifact Build

Status: implemented.

Goal: produce the `0.1.0` source-release artifact and verify it through the
handoff checklist, including local live CP2K validation.

Local verification:

- `python .\scripts\run_checks.py --profile all --compact`: 9/9 checks passed,
  including 108 unit tests.
- `python .\scripts\release_candidate_walkthrough.py --compact`: 9/9 offline
  steps passed.
- `python .\scripts\build_release.py --compact`: wrote
  `dist/winqstep-0.1.0.zip` and `dist/winqstep-0.1.0.manifest.json`.
- `python .\scripts\smoke_release_install.py --archive .\dist\winqstep-0.1.0.zip --compact`:
  unpacked diagnostics passed.
- `python .\scripts\release_candidate_walkthrough.py --include-live --keep-workspace --compact`:
  10/10 steps passed, including a real `ENERGY_FORCE` run.
- `python .\scripts\run_checks.py --profile live --compact`: 2/2 checks passed.

Artifact:

- Version: `0.1.0`.
- Source files in archive: 99 plus archive `RELEASE-MANIFEST.json`.
- Archive SHA-256: recorded in `dist/winqstep-0.1.0.manifest.json` after each
  build. Do not duplicate the digest here because this document is packaged
  into the source archive.

Tasks:

- Run the required release-candidate handoff commands.
- Build the actual source-release zip and manifest.
- Smoke test the generated archive by unpacking it and running startup
  diagnostics.
- Run optional local live CP2K validation because WSL2 and CP2K are available.
- Record the release baseline for future sessions.

Acceptance:

- `dist/winqstep-0.1.0.zip` and `dist/winqstep-0.1.0.manifest.json` exist.
- The generated archive passes unpacked release smoke testing.
- Live CP2K validation succeeds and parses ENERGY_FORCE energy and force
  summaries.
- Handoff documentation records the verification baseline and points to the
  generated manifest as the authoritative archive hash source.

Commit boundary:

- One commit for Round 32 release baseline documentation.

## Round 33: GUI Async Run Completion Crash Fix

Status: implemented.

Goal: fix the GUI crash reported when clicking `Run` for the default water
workflow: Job log updated while CP2K was running, then the WPF dispatcher raised
an invalid `&` invocation error when the async job completed.

Root cause:

- The async completion closure was created before `SetArtifactsFromMetadata`
  was defined.
- While the job was running, timer refreshes could still tail CP2K output.
- When CP2K exited, the completion path tried to call the not-yet-captured
  artifact helper from inside the closure, which became an invalid call target
  under PowerShell strict mode.

Local verification:

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start_gui.ps1 -AsyncRunSmokeTest -Language zh-CN`:
  passed with a real CP2K `ENERGY` run.
- `python .\scripts\run_checks.py --profile live --compact`: 3/3 checks passed,
  including the new GUI async `Run` smoke.
- `python -m unittest tests.test_gui_prototype tests.test_run_checks`: 13 tests
  passed.
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start_gui.ps1 -ButtonSmokeTest -SkipLiveProbes -Language zh-CN`:
  passed.

Tasks:

- Move async completion/timer closure creation after artifact helpers are
  defined.
- Catch async refresh failures so future refresh errors write to Job log and
  restore controls instead of crashing the WPF app.
- Add `-AsyncRunSmokeTest` to click the GUI `Run` button and wait for a real
  CP2K job to finish.
- Add the async run smoke to the `live` check profile.
- Document the new live smoke coverage.

Acceptance:

- The default GUI water workflow can run to completion from the `Run` button.
- Job log, status, and artifacts update after the async job completes.
- The `live` profile fails if this GUI async completion path regresses.

Commit boundary:

- One commit for the async run crash fix, live smoke coverage, tests, and docs.

## Round 34: Window-Level GUI Overflow Scrolling

Status: implemented.

Goal: keep all GUI content reachable when vertical content exceeds the current
window height, especially after action buttons wrap or form-heavy tabs need more
vertical space.

Tasks:

- Add a root `ScrollViewer` around the main GUI layout with automatic vertical
  scrolling and disabled horizontal scrolling.
- Keep existing text-pane and grid scrollbars available for logs, artifacts,
  previews, and tables.
- Extend smoke reports and static tests to verify the root scroll viewer exists.
- Document the overflow behavior for users.

Acceptance:

- The GUI exposes a right-side vertical scrollbar when the main content is
  taller than the window.
- Users can reach lower controls without maximizing the window.
- Smoke/static tests fail if the root scroll viewer is removed.

Commit boundary:

- One commit for the XAML scroll fix, tests, docs, and plan update.

## Round 35: QuickStep CELL/PERIODIC Support

Status: implemented.

Goal: make periodic cell handling a first-class QuickStep workflow feature
instead of an implicit fallback hidden in template JSON.

Tasks:

- Render `DFT/&POISSON/PERIODIC` from the same resolved periodicity used by
  `SUBSYS/&CELL/PERIODIC`.
- Validate supported periodicity labels and reject periodic cells with
  zero-length vectors before writing CP2K input.
- Expose fallback cell periodicity, A/B/C vectors, and `center_atoms` in the
  Template tab and in `scripts/manage_template.py`.
- Keep fallback centering limited to structures that actually use the fallback
  cell, so POSCAR/CIF periodic structures preserve imported coordinates.
- Add tests for POISSON rendering, fallback cell editing, periodic POSCAR
  workflow data, GUI template controls, and updated input snapshots.

Acceptance:

- Existing ENERGY, ENERGY_FORCE, and GEO_OPT snapshots render with matching
  `POISSON PERIODIC` and `CELL PERIODIC` values.
- XYZ workflows still use the configured fallback cell and can center atoms.
- Periodic POSCAR/CIF workflows keep the imported cell instead of being replaced
  by the fallback cell.
- The GUI can load, edit, save, and smoke-test fallback periodicity and cell
  vectors.

Commit boundary:

- One commit for CELL/PERIODIC model, renderer, template/GUI controls, tests,
  and docs.

## Round 36: QuickStep SCF Control Expansion

Status: implemented.

Goal: expose common QuickStep SCF solver controls without broadening into
spin-polarized DFT, DFT+U, hybrid functional, or MD workflows yet.

Local verification:

- A real local CP2K 2025.2 run completed with `DIAGONALIZATION`,
  `BROYDEN_MIXING`, `SMEAR`, and `TELEC [K]` in
  `outputs/round36-scf-live`, return code `0`, and zero CP2K warnings.

Tasks:

- Add typed DFT fields for `ADDED_MOS`, `OT`, `DIAGONALIZATION`, `MIXING`, and
  `SMEAR`.
- Render `SCF/&OT` for OT minimization, and render `SCF/&DIAGONALIZATION`,
  optional `SCF/&MIXING`, and optional `SCF/&SMEAR` for diagonalization.
- Keep existing templates on a `DEFAULT` SCF method so previous generated input
  snapshots stay unchanged unless the user explicitly enables advanced SCF
  controls.
- Validate method choices, numeric ranges, and incompatible combinations such as
  mixing or smearing without `DIAGONALIZATION`.
- Expose the new fields in `scripts/manage_template.py` and the GUI Template
  tab with editable drop-downs and checkboxes.
- Add tests for renderer output, template normalization, invalid combinations,
  GUI controls, localization keys, and default compatibility.

Acceptance:

- Default ENERGY, ENERGY_FORCE, and GEO_OPT generated inputs remain stable.
- OT templates render only an `&OT` subsection.
- Diagonalization templates can render `ADDED_MOS`, `&DIAGONALIZATION`,
  `&MIXING`, and `&SMEAR`.
- The GUI loads and saves the new SCF controls through the same template JSON
  path used by CLI workflows.

Commit boundary:

- One commit for SCF model, renderer, template/GUI controls, tests, and docs.

## Round 37: QuickStep KPOINTS Support

Status: implemented.

Goal: add a conservative, locally validated KPOINTS path for periodic
QuickStep calculations without exposing the advanced GENERAL or MACDONALD
schemes yet.

Tasks:

- Add typed DFT fields for `KPOINTS/SCHEME`, Monkhorst-Pack grid dimensions,
  `FULL_GRID`, `SYMMETRY`, and `WAVEFUNCTIONS`.
- Render `DFT/&KPOINTS` only when the scheme is not `NONE`, preserving existing
  default ENERGY, ENERGY_FORCE, and GEO_OPT input snapshots.
- Support `GAMMA` and `MONKHORST-PACK` schemes from the CP2K input manual.
- Reject KPOINTS for nonperiodic systems before CP2K is started.
- Expose the new fields in `scripts/manage_template.py` and the GUI Template
  tab with editable drop-downs and checkboxes.
- Add renderer, template, GUI, fast-profile, and local CP2K live validation.

Acceptance:

- Default templates keep `kpoints_scheme` at `NONE` and do not render
  `&KPOINTS`.
- Periodic templates can render `SCHEME GAMMA` or
  `SCHEME MONKHORST-PACK nx ny nz`.
- Optional `FULL_GRID`, `SYMMETRY`, and non-default `WAVEFUNCTIONS` render only
  inside `&KPOINTS`.
- The GUI loads, edits, saves, and smoke-tests KPOINTS fields through the same
  template path used by workflows.

Commit boundary:

- One commit for KPOINTS model, renderer, template/GUI controls, tests, docs,
  and local CP2K validation.

## Round 38: QuickStep CELL_OPT Support

Status: implemented.

Goal: add a conservative direct cell-optimization path for periodic QuickStep
workflows.

Tasks:

- Add `CELL_OPT` as a supported generated run type.
- Add typed `cell_opt` fields for optimizer, max iterations,
  `DIRECT_CELL_OPT`, pressure tolerance, `KEEP_ANGLES`, and `KEEP_SYMMETRY`.
- Render `FORCE_EVAL/STRESS_TENSOR ANALYTICAL` and `MOTION/&CELL_OPT` only for
  `RUN_TYPE CELL_OPT`.
- Reject `CELL_OPT` for nonperiodic systems before CP2K is started.
- Add `examples/quickstep_cell_opt.json` and
  `examples/templates/cell_opt_pbe.json`.
- Expose the new fields in `scripts/manage_template.py` and the GUI Template
  tab with editable drop-downs and checkboxes.
- Add renderer, template, workflow, GUI, fast-profile, and local CP2K live
  validation.

Acceptance:

- Existing ENERGY, ENERGY_FORCE, and GEO_OPT snapshots remain stable.
- CELL_OPT inputs render `RUN_TYPE CELL_OPT` and `MOTION/&CELL_OPT`.
- The first CELL_OPT path uses `TYPE DIRECT_CELL_OPT`; MD-driven cell
  optimization and space-group controls remain out of scope.
- Workflow templates can carry `cell_opt` settings through preview and run.

Commit boundary:

- One commit for CELL_OPT model, renderer, template/GUI controls, examples,
  tests, docs, and local CP2K validation.

## Round 39: Template CP2K Section Grouping

Status: implemented.

Goal: make the Template tab reflect the nested shape of the generated CP2K
input file instead of presenting all controls as flat peers.

Tasks:

- Group Template controls with WPF `GroupBox` sections named after the CP2K
  input paths they render.
- Keep all existing control names stable so loading, saving, validation, and
  smoke tests keep using the same GUI wiring.
- Cover `FORCE_EVAL/DFT`, `FORCE_EVAL/DFT/SCF`,
  `FORCE_EVAL/DFT/SCF/MIXING`, `FORCE_EVAL/DFT/SCF/SMEAR`,
  `MOTION/GEO_OPT`, `MOTION/CELL_OPT`, `FORCE_EVAL/SUBSYS/CELL`,
  `FORCE_EVAL/DFT/KPOINTS`, and `FORCE_EVAL/SUBSYS/KIND`.
- Extend the GUI smoke report and static GUI tests to assert that these section
  groups load.
- Make the config-language smoke assertion follow the current sample config so
  local saved config preferences do not create false GUI failures.

Acceptance:

- Mixing and smearing controls are visibly grouped as their own SCF subsections.
- KPOINTS, CELL_OPT, cell, and KIND controls are visually grouped by the
  matching CP2K input-section path.
- The GUI still loads, edits, saves, and validates the same template fields as
  before.
- GUI smoke tests pass with either an empty sample `ui_language` or a locally
  saved language preference.

Commit boundary:

- One commit for the Template layout grouping, smoke/static tests, and docs.

## Round 40: GLOBAL Print Level and GUI Language Apply

Status: implemented.

Goal: add conservative CP2K `GLOBAL/PRINT_LEVEL` support and make GUI language
selection take effect without restarting or saving first.

Tasks:

- Add optional top-level `print_level` support to the QuickStep input model,
  template validator, workflow merger, and `scripts/manage_template.py`.
- Validate `SILENT`, `LOW`, `MEDIUM`, `HIGH`, and `DEBUG` from the CP2K
  `GLOBAL/PRINT_LEVEL` manual entry.
- Render `GLOBAL/PRINT_LEVEL` only when the field is explicitly set, preserving
  existing generated input snapshots by default.
- Expose `Print Level` in the Template tab's `&GLOBAL` group with an editable
  drop-down.
- Add an `Apply` button next to `UI Language` that refreshes the visible GUI
  labels immediately without writing the config file.
- Extend GUI smoke coverage to verify the language apply path and print-level
  controls.

Acceptance:

- Generated inputs include `PRINT_LEVEL <level>` in `&GLOBAL` when requested.
- Unsupported print levels are rejected before CP2K starts.
- Workflow templates carry `print_level` through preview and run.
- Clicking `Apply` after changing `UI Language` updates the active window's
  localized labels; `Save Config` remains the persistence action.

Commit boundary:

- One commit for print-level model/template/GUI support, language apply wiring,
  tests, and docs.

## Round 41: GUI Workflow Tab and Section Label Polish

Status: implemented.

Goal: align the lower GUI tab order with trial-user feedback and make Template
section headings show the full CP2K input path for each rendered block.

Tasks:

- Reorder the main GUI tabs to `Config`, `Environment`, `Structure`,
  `Template`, `Input Preview`, `Job Log`, `Artifacts`, and `History`.
- Keep `Template` and `Input Preview` adjacent so template editing and manual
  input inspection remain a direct workflow pair.
- Expand Template section headers from partial nested labels such as
  `&SCF / &SMEAR` to full CP2K paths such as
  `&FORCE_EVAL / &DFT / &SCF / &SMEAR`.
- Update static GUI tests, smoke-report assertions, and user-facing docs.

Acceptance:

- Static XAML tests and GUI smoke tests assert the exact current tab order.
- Template section headers load as `&GLOBAL`, `&FORCE_EVAL / &DFT`,
  `&FORCE_EVAL / &DFT / &SCF`,
  `&FORCE_EVAL / &DFT / &SCF / &MIXING`,
  `&FORCE_EVAL / &DFT / &SCF / &SMEAR`, `&MOTION / &GEO_OPT`,
  `&MOTION / &CELL_OPT`, `&FORCE_EVAL / &SUBSYS / &CELL`,
  `&FORCE_EVAL / &DFT / &KPOINTS`, and
  `&FORCE_EVAL / &SUBSYS / &KIND`.

Commit boundary:

- One commit for GUI tab order, Template section labels, tests, and docs.

## Round 42: Live Job Log UTF-8 Hardening

Status: implemented.

Goal: keep CP2K text with non-ASCII characters readable in the GUI Job Log
during live runs, matching the already-correct artifact viewing path.

Tasks:

- Set UTF-8 stdout/stderr decoding on the asynchronous Python worker process
  used by GUI Run.
- Read live log tails with explicit UTF-8 encoding instead of relying on the
  Windows PowerShell default code page.
- Extend lifecycle smoke coverage with non-ASCII stdout/stderr and tail checks.

Acceptance:

- Detect/import/preview paths remain UTF-8.
- Live Job Log tails preserve UTF-8 text from CP2K stdout/stderr files.
- Lifecycle smoke verifies saved worker stdout/stderr and live-tail reads keep
  Chinese text intact.

Commit boundary:

- One commit for GUI host encoding, smoke tests, and docs.

## Round 43: Readable Structure Import Display

Status: implemented.

Goal: keep the normalized structure JSON as the internal interchange format but
show imported structures in a more readable GUI form.

Tasks:

- Parse successful `import_structure.py` output in the GUI Import handler.
- Display source metadata, atom count, element counts, cell vectors,
  periodicity, and cartesian coordinates in the `Structure` tab.
- Keep raw command output visible when structure import fails or returns
  unparsable output.
- Update button smoke coverage to assert the readable import summary.

Acceptance:

- Importing `water.xyz` shows `Imported structure`, `Atoms: 3`,
  `Elements: H=2, O=1`, and a coordinate table in the `Structure` tab.
- Preview/Run continue to validate from the structure file path rather than
  depending on editable Structure-tab text.

Commit boundary:

- One commit for Structure tab display formatting, smoke tests, and docs.

## Round 44: Readable Environment Probe Display

Status: implemented.

Goal: keep `detect_environment.py` JSON useful for automation while making the
GUI `Environment` tab easier to read.

Tasks:

- Parse `detect_environment.py` JSON in the GUI Detect handler even when the
  command exits nonzero because warnings are present.
- Display host, WSL, CP2K, MPI, workspace, warnings, and probe-command status
  as a readable summary in the `Environment` tab.
- Keep the raw detection JSON in `Job Log` for copying and debugging.
- Add a deterministic synthetic smoke test for the Environment display
  formatter.

Acceptance:

- A valid probe payload shows `Environment detection`, selected distro, CP2K
  command, data-file count, warnings, and probe command statuses without
  exposing raw JSON as the primary `Environment` view.
- Existing config validation and execution paths still read from saved config
  fields, not from editable Environment-tab text.

Commit boundary:

- One commit for Environment display formatting, smoke tests, and docs.

## Round 45: Edited Preview Run Confirmation

Status: implemented.

Goal: prevent accidental edits in the editable `Input Preview` pane from being
silently used as the CP2K input when the user presses `Run`.

Tasks:

- Detect manual changes in `Input Preview` as before, but ask for confirmation
  before saving or running the edited text.
- Use a warning dialog with `Yes/No` buttons and `No` as the default result.
- Keep confirmed edited-preview runs on the existing-input path and continue to
  save the edited copy as `*_edited.inp`.
- Localize the confirmation and cancellation text.
- Extend edited-preview smoke coverage to prove the confirmation path is reached
  before the edited input is accepted.

Acceptance:

- Unchanged previews still run without extra confirmation.
- Changed previews require explicit confirmation before CP2K starts.
- Cancelling the prompt leaves the job unstarted and keeps the preview text
  available for review.
- Existing original input files are still not overwritten.

Commit boundary:

- One commit for edited-preview confirmation, tests, resources, and docs.

## Round 46: Structure 3D Preview Planning

Status: planned.

Goal: add a local design plan for a 3D preview of imported structures without
committing to a large implementation all at once.

Plan:

- Keep normalized structure JSON as the importer and workflow boundary.
- Add a dedicated preview data model before touching WPF rendering.
- Prefer native WPF `Viewport3D` for the first implementation to avoid WebView2,
  JavaScript, and extra packaging constraints.
- Preserve the readable Structure text summary and keep the 3D view as display
  only.
- Split implementation into preview-model, static-view, and interaction rounds.

Reference:

- See `docs/structure-3d-preview-plan.md`.

Acceptance:

- The 3D preview work is locally documented with scope boundaries, proposed
  rounds, risks, and open decisions.
- The plan makes clear that generated inputs and CP2K runs must not depend on
  editable viewer state.

Commit boundary:

- One commit for the local 3D preview planning document and execution-plan
  reference.

## Round 47: Structure Preview Data Model

Status: implemented.

Goal: build the first display-only model for imported-structure 3D previews
without touching WPF rendering yet.

Tasks:

- Add `winqstep.structure_preview.build_structure_preview`.
- Convert normalized importer output into atoms with element colors, display
  radii, cartesian coordinates, source metadata, center, and bounding radius.
- Add periodic cell-frame geometry as 12 edges when usable periodic cell vectors
  are present.
- Warn and omit the cell frame for nonperiodic or incomplete-cell structures.
- Cap displayed atoms for large structures while keeping total atom count.
- Cover water XYZ, POSCAR, NaCl CIF, atom-count capping, and invalid limits in
  tests.

Acceptance:

- Nonperiodic XYZ structures render atoms and warn that no periodic cell frame
  is available.
- Periodic POSCAR/CIF structures include 12 cell-frame edges.
- Large structures report both total and displayed atom counts.
- The helper has no dependency on WPF and does not affect Preview or Run.

Commit boundary:

- One commit for the preview model helper, tests, and local plan update.

## Round 48: Static Structure 3D Preview

Status: implemented.

Goal: render imported structures in the GUI using the Round 47 preview model
while keeping the existing readable Structure summary and calculation workflow
unchanged.

Tasks:

- Extend `scripts/import_structure.py` with an optional `--include-preview`
  wrapper payload for GUI use.
- Add a native WPF `Viewport3D` region, preview status text, and `Reset View`
  button to the Structure tab.
- Render preview atoms as colored sphere geometry and cell-frame edges as thin
  cylinder geometry.
- Reset the camera from preview center and bounding radius.
- Clear stale 3D geometry on failed imports and on `Clear`.
- Localize the new Reset View button and preview status text.
- Extend GUI smoke coverage to verify viewport loading, import-time geometry,
  reset-button wiring, and clear-time cleanup.

Acceptance:

- Successful Structure import populates both readable text and static 3D
  geometry.
- Nonperiodic structures still show atoms even without a cell frame.
- Clearing the GUI removes stale structure geometry.
- Preview and Run continue to use the existing structure/input paths rather than
  viewer state.

Commit boundary:

- One commit for static WPF 3D preview rendering, tests, localization, and docs.

## Round 49: Structure 3D Preview Interaction

Status: implemented.

Goal: make the native WPF structure preview inspectable with basic camera/model
interaction while keeping the viewer display-only.

Tasks:

- Track preview yaw, pitch, pan, distance, default distance, and drag state.
- Rotate the model on left-button drag.
- Pan the camera on right-button or middle-button drag.
- Zoom the camera with the mouse wheel.
- Make `Reset View` restore yaw, pitch, pan, and distance.
- Add GUI smoke coverage that verifies rotation changes the model transform,
  pan changes camera X/Y, zoom changes camera distance, and reset restores the
  initial view.

Acceptance:

- Imported structures can be rotated, zoomed, panned, and reset without changing
  the structure model used by Preview or Run.
- Clear still removes stale 3D geometry and disables reset.
- No visual bond inference is added in this round.

Commit boundary:

- One commit for 3D preview interaction plumbing, smoke tests, and docs.

## Round 50: Structure 3D Preview Initial Framing

Status: implemented.

Goal: make the first imported 3D preview and `Reset View` show the full
displayed atom/cell model without requiring manual zoom-out.

Tasks:

- Replace the fixed `bounding_radius * 2.8` camera distance with a field-of-view
  aware bounding-sphere fit.
- Account for the Structure preview viewport aspect ratio, because wide panes
  have a narrower derived vertical viewing angle.
- Keep the viewer display-only; this changes only the camera state.
- Extend GUI smoke coverage so the imported preview's initial distance matches
  the fit calculation and is more conservative than the old fixed multiplier.

Acceptance:

- Importing the default structure initializes the camera far enough to include
  the full preview model.
- `Reset View` restores the same fitted camera distance, pan, and transform.
- Existing rotate, pan, zoom, clear, preview, and run workflows remain
  unchanged.

Commit boundary:

- One commit for initial 3D preview framing, smoke tests, and docs.

## Round 51: 0.2.0 Release Candidate Preparation

Status: implemented.

Goal: prepare the next source-release candidate after the post-`0.1.0`
QuickStep, GUI workflow, structure preview, and documentation updates.

Tasks:

- Bump the project version from `0.1.0` to `0.2.0`.
- Update release handoff commands, artifact names, and candidate scope.
- Add release notes summarizing user-visible changes since `0.1.0`.
- Make release smoke coverage treat release notes as a required handoff file.
- Run offline release verification and build/smoke-test the candidate archive.

Local verification:

- `python -m pytest tests\test_release.py tests\test_release_candidate.py -q`:
  8 tests passed.
- `python .\scripts\build_release.py --dry-run --compact`: valid plan for
  `winqstep-0.2.0`, including 106 source files.
- `python .\scripts\run_checks.py --profile all --compact`: 9/9 checks passed,
  including 141 unit tests, GUI smoke, release smoke, and RC walkthrough.
- `python .\scripts\build_release.py --compact`: wrote
  `dist/winqstep-0.2.0.zip` and `dist/winqstep-0.2.0.manifest.json`.
- `python .\scripts\smoke_release_install.py --archive .\dist\winqstep-0.2.0.zip --compact`:
  valid unpacked diagnostics.

Acceptance:

- `build_release.py --dry-run` plans `winqstep-0.2.0` artifacts and includes
  the release notes.
- Release candidate tests confirm handoff docs track the project version.
- The candidate archive can be built and unpacked through release smoke.
- Final GitHub tag/release creation remains a separate explicit step.

Commit boundary:

- One commit for `0.2.0` release-prep metadata, tests, and docs.

## Round 52: WPF Runtime Startup Diagnostics

Status: implemented.

Goal: make missing .NET/WPF desktop runtime problems visible before users try to
open the GUI.

Context:

- A tester reported that the GUI failed with a missing .NET runtime error.
- Installing the .NET runtime resolved the issue, confirming that the
  PowerShell-hosted WPF GUI depends on desktop WPF assemblies being available.

Tasks:

- Extend startup diagnostics to load `PresentationFramework`,
  `PresentationCore`, `WindowsBase`, and `System.Windows.Forms` through
  `powershell.exe`.
- Report the WPF/.NET desktop assembly check under `checks.wpf_desktop`.
- Document that users should install or enable .NET desktop runtime /
  .NET Framework WPF support and launch with Windows PowerShell 5.1 rather than
  `pwsh`.
- Add startup tests for the new diagnostics field.

Acceptance:

- `check_startup.py --skip-live-probes` fails with a direct WPF/.NET desktop
  message when the assemblies cannot be loaded.
- Existing startup diagnostics still pass on a correctly configured Windows
  desktop.

Commit boundary:

- One commit for WPF runtime diagnostics, tests, and docs.

## Round 53: External Review Baseline Fixes

Status: implemented.

Goal: address actionable issues from an external 0.2 review before adding more
features.

Context:

- A reviewer reported that `run_checks.py --profile fast` failed in a clean
  clone whose path did not contain Chinese characters.
- The same review found that WSL CP2K data inspection accepted `limit_files`
  but did not apply it to the generated `find` command.
- The review also noted that `cp2k_command` and `mpirun_command` are treated as
  single shell tokens, not command strings with extra arguments.

Tasks:

- Make GUI smoke workspace checks verify portable `outputs` resolution instead
  of assuming the repository path contains a Chinese folder name.
- Keep the explicit non-ASCII subprocess/path probes for encoding coverage.
- Apply `limit_files` in the WSL CP2K data dump command before reading files.
- Test the WSL data command's file limit and invalid-limit behavior.
- Clarify command-field semantics in README, configuration docs, and English GUI
  labels.

Acceptance:

- Fast checks no longer depend on the user's clone path containing non-ASCII
  characters.
- WSL data inspection cannot dump an unbounded number of CP2K data files when a
  caller provides `limit_files`.
- Users are told that CP2K and MPI fields are executable paths or command names,
  not argument-bearing command lines.

Commit boundary:

- One commit for external review fixes, tests, and docs.

## Round 54: QuickStep OUTER_SCF Support

Status: implemented.

Goal: add a conservative, optional `FORCE_EVAL/DFT/SCF/OUTER_SCF` block for
QuickStep templates and generated inputs.

Tasks:

- Add typed DFT fields for `outer_scf_enabled`, `outer_scf_eps_scf`, and
  `outer_scf_max_scf`.
- Render `SCF/&OUTER_SCF` only when explicitly enabled, preserving existing
  snapshots by default.
- Validate positive OUTER_SCF values and reject enabled outer thresholds looser
  than the inner `EPS_SCF`.
- Expose OUTER_SCF controls in the Template tab as a CP2K-section group with
  editable drop-downs.
- Wire the new fields through `manage_template.py`, GUI load/save paths, smoke
  reports, docs, and tests.

Acceptance:

- Existing generated ENERGY, ENERGY_FORCE, GEO_OPT, and CELL_OPT snapshots stay
  unchanged unless OUTER_SCF is enabled.
- Enabling OUTER_SCF renders `&OUTER_SCF` with `EPS_SCF` and `MAX_SCF`.
- Template validation and GUI smoke coverage include the OUTER_SCF controls.

Commit boundary:

- One commit for OUTER_SCF model, renderer, template/GUI controls, tests, and
  docs.

## Round 55: QuickStep UKS Spin Polarization

Status: implemented.

Goal: add explicit spin-polarized QuickStep DFT support through the CP2K
`FORCE_EVAL/DFT/UKS` keyword.

Tasks:

- Add a typed `dft.uks_enabled` field to the QuickStep input model and workflow
  template model.
- Render `UKS T` inside `&DFT` only when the field is explicitly enabled,
  preserving existing generated input snapshots by default.
- Reject `multiplicity` values greater than 1 unless UKS is enabled, so
  open-shell templates cannot run as restricted calculations by mistake.
- Expose UKS in the Template tab as a checkbox in the
  `&FORCE_EVAL / &DFT` group.
- Wire the field through `manage_template.py`, GUI load/save paths,
  localization resources, smoke reports, docs, and tests.

Acceptance:

- Existing snapshots remain unchanged when `uks_enabled` is false or omitted.
- Enabling UKS renders `UKS T` near the DFT charge/multiplicity keywords.
- Open-shell multiplicity without UKS fails in both QuickStep model validation
  and template validation.
- GUI smoke coverage includes the UKS checkbox state.

Commit boundary:

- One commit for UKS model, renderer, template/GUI controls, tests, and docs.

## Round 56: Thin Windows EXE Launcher

Status: implemented.

Goal: let normal Windows users start the GUI by double-clicking an `.exe`
without turning WinQStep into a bundled interpreter package.

Tasks:

- Add a small C# WinForms-compatible launcher that locates sibling
  `WinQStep.ps1` and starts Windows PowerShell with the existing startup
  arguments.
- Keep the launcher as a thin wrapper only: no Python, PowerShell, WSL, CP2K,
  CP2K data files, or package dependencies are bundled into it.
- Add `scripts/build_launcher.py` to compile `WinQStep.exe` with the local
  .NET Framework C# compiler when available.
- Keep generated `WinQStep.exe` out of git, but include it in release zips when
  it exists at release-build time.
- Wire the launcher source and build script into startup diagnostics, release
  planning, release smoke checks, tests, and user docs.

Acceptance:

- `python .\scripts\build_launcher.py` creates `WinQStep.exe` in the repository
  root on a machine with `csc.exe`.
- Double-clicking `WinQStep.exe` starts the same PowerShell-hosted WPF GUI as
  `WinQStep.ps1`.
- Source-only checkouts can still use `WinQStep.ps1` and can build the EXE
  locally without committing a binary.

Commit boundary:

- One commit for the thin launcher, builder, release wiring, tests, and docs.

## Round 57: QuickStep XC and DFT-D3 Support

Status: implemented.

Goal: add the most common next layer of QuickStep XC control without taking on
hybrid functional, ADMM, or restart workflow complexity.

Tasks:

- Preserve the existing default `&XC_FUNCTIONAL PBE` rendering and snapshots.
- Add `dft.xc_pbe_parametrization` for explicit PBE variants such as `PBESOL`,
  `REVPBE`, and `RPBE`.
- Add opt-in DFT-D3 settings that render `DFT/&XC/&VDW_POTENTIAL` with
  `PAIR_POTENTIAL`, `TYPE`, `PARAMETER_FILE_NAME`, and `REFERENCE_FUNCTIONAL`.
- Expose the XC controls in a dedicated Template section,
  `&FORCE_EVAL / &DFT / &XC`, using editable drop-down fields and a DFT-D3
  enable checkbox.
- Include D3 parameter files such as `dftd3.dat` in CP2K data inspection caches
  and warn during preflight when enabled D3 references a missing parameter file.
- Wire the fields through `manage_template.py`, GUI load/save paths, smoke
  reports, docs, and tests.

Acceptance:

- Existing generated ENERGY, ENERGY_FORCE, GEO_OPT, and CELL_OPT snapshots stay
  unchanged unless a non-default PBE parametrization or DFT-D3 is enabled.
- PBEsol/revPBE/RPBE render as `PARAMETRIZATION` inside `&XC_FUNCTIONAL PBE`.
- Enabling DFT-D3 renders `&VDW_POTENTIAL` and `&PAIR_POTENTIAL` in the CP2K XC
  hierarchy.
- Template validation rejects PBE parametrization when the selected functional
  is not `PBE`.
- GUI smoke coverage includes the new XC section and DFT-D3 fields.

Commit boundary:

- One commit for XC/DFT-D3 model, renderer, template/GUI controls, data-cache
  support, tests, and docs.

## Working Rules

- Keep each round small enough to review.
- Commit after each completed round.
- Do not commit `codex-thread.json`, CP2K source snapshots, generated outputs, or
  local virtual environments.
- Prefer deterministic tests over manual-only verification.
- Keep CP2K as an external program invoked through WSL.

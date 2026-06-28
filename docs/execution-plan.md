# Execution Plan

This plan keeps the near-term WinQStep work executable across Codex sessions.
Each round should end with a focused commit.

## Current Baseline

- Repository name: `winqstep`.
- Product name: WinQStep.
- License: `GPL-3.0-or-later`.
- Current code: standard-library Python environment probe plus unit tests.
- Current docs: product scope, architecture, WSL execution rules, and CP2K input
  model.
- Next active round: Round 2, path conversion and job model.
- Known local facts:
  - WSL2 is available.
  - Default distro is `Ubuntu`.
  - `mpirun` is available at `/usr/bin/mpirun`.
  - The normal direct CP2K command in WSL2 is `cp2k.ssmp`.
  - CP2K is not currently found on WSL `PATH`.
  - `CP2K_DATA_DIR` is not exported in the selected distro.
  - A local CP2K 2026.1 data snapshot exists at
    `/mnt/d/Library/自制品/winqstep/cp2k-2026.1/data`.

## Round 1: Configuration File Support

Status: implemented.

Goal: make environment detection work from explicit project configuration, not
only from auto-detection.

Tasks:

- Add a repo-local sample config, such as `examples/winqstep.config.json`.
- Teach `scripts/detect_environment.py` to read a config file.
- Support config keys for `distro`, `cp2k_command`, `mpirun_command`,
  `cp2k_data_dir`, and a default Windows workspace folder.
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

Goal: generate a small, stable CP2K input file from typed data.

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

Goal: normalize CIF, POSCAR, and XYZ into one structure JSON shape.

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

Goal: run one minimal CP2K job end to end through WSL.

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

## Round 6: GUI Prototype

Goal: build a thin Windows UI over the already-tested core workflow.

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

## Working Rules

- Keep each round small enough to review.
- Commit after each completed round.
- Do not commit `codex-thread.json`, CP2K source snapshots, generated outputs, or
  local virtual environments.
- Prefer deterministic tests over manual-only verification.
- Keep CP2K as an external program invoked through WSL.

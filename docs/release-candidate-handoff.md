# Release Candidate Handoff

This note is the short handoff checklist for a WinQStep source-release
candidate. It complements `docs/release.md`, which documents the packaging
mechanics in more detail.

## Candidate Scope

Current package version: `0.3.0`.

This is a local Windows prototype, not an installer or PyPI release. The
candidate supports:

- WSL2 CP2K QuickStep execution through `wsl.exe`.
- GUI and CLI workflows for generated `ENERGY`, `ENERGY_FORCE`, `GEO_OPT`, and
  `CELL_OPT`
  inputs.
- Existing CP2K `.inp` execution without regenerating the input.
- Config and template editing, CP2K data inspection, preflight validation, job
  history, artifact inspection, and structured result summary export.
- GUI conveniences added after `0.1.0`: responsive tab order, editable generated
  input confirmation, readable Environment and Structure summaries, native 3D
  structure preview with rotate/zoom/pan/reset, localized UI improvements,
  UTF-8 live job-log tails, a thin double-click `WinQStep.exe` launcher, and
  clearer first-run requirements.
- Existing-input batch workflow support with separate directory, multi-file,
  and input-list selectors, batch preview/result summaries, resume, result
  export, and queue actions.
- Additional QuickStep Template coverage added after `0.2.0`, including
  DFT PRINT Band Structure output and tighter GUI dependency hints for
  periodicity-sensitive KPOINTS, POISSON, CELL_OPT, and Band Structure choices.
- Source-release zip packaging and unpacked release smoke testing.

## Required Handoff Commands

Run from the repository root before handing off a candidate:

```powershell
git status --short
python .\scripts\run_checks.py --profile all --compact
python .\scripts\release_candidate_walkthrough.py --compact
python .\scripts\build_launcher.py --compact
python .\scripts\build_release.py --compact
python .\scripts\smoke_release_install.py --archive .\dist\winqstep-0.3.0.zip --compact
```

Expected minimum result:

- `git status --short` prints no tracked or untracked release-relevant changes.
- `run_checks.py --profile all` reports `valid: true`.
- `release_candidate_walkthrough.py` reports `valid: true` with 9 offline
  steps passed.
- `build_launcher.py` writes `WinQStep.exe`.
- `build_release.py` writes `dist/winqstep-0.3.0.zip` and
  `dist/winqstep-0.3.0.manifest.json`.
- `smoke_release_install.py --archive ...` reports `valid: true`.

When WSL2 and the configured CP2K installation are available, also run:

```powershell
python .\scripts\release_candidate_walkthrough.py --include-live --keep-workspace --compact
python .\scripts\run_checks.py --profile live --compact
```

The live walkthrough must complete a real `ENERGY_FORCE` CP2K run and parse
`total_energy_hartree` plus `forces.total_atomic_force`.

## Files to Hand Off

For a source-release handoff, provide:

- `dist/winqstep-0.3.0.zip`
- `dist/winqstep-0.3.0.manifest.json`
- the SHA-256 value from the manifest or `build_release.py` output
- this handoff note, `docs/release.md`, and `docs/release-notes.md`

Do not hand off `outputs/`, `build/`, local `dist/` work folders other than the
release zip and manifest, CP2K snapshots, virtual environments, caches, or
Codex thread files.

## First-Run Path for Testers

After unpacking the zip on Windows:

```powershell
.\WinQStep.ps1 -Diagnostics -SkipLiveProbes
.\WinQStep.ps1 -Diagnostics
.\WinQStep.exe
```

Use `-Diagnostics -SkipLiveProbes` first to verify Python, PowerShell,
repository files, config shape, and release hygiene without touching WSL. Use
full `-Diagnostics` only when WSL2 and CP2K are expected to be available.
If `WinQStep.exe` is not present in a source-only handoff, run
`python .\scripts\build_launcher.py` or start the GUI with `.\WinQStep.ps1`.

## Known Limitations

- QuickStep only. Other CP2K modules are outside the current scope.
- Supported generated run types are `ENERGY`, `ENERGY_FORCE`, `GEO_OPT`, and
  `CELL_OPT`.
- CP2K binaries, CP2K source trees, and CP2K data files are external
  dependencies and are never bundled.
- The GUI is PowerShell-hosted WPF. It is intended for Windows desktop sessions
  with Windows PowerShell 5.1 and WPF assemblies available.
- Structure import depends on ASE for general CIF/POSCAR/XYZ parsing.
- CP2K cancellation is best effort. The GUI terminates the Python/WSL wrapper
  process tree where possible and marks metadata as cancelled.
- Result parsing is intentionally compact. Raw CP2K output remains the source
  of truth for scientific interpretation.

## Current Verification Baseline

Round 84 prepares the `0.3.0` source-release candidate after the post-`0.2.0`
batch, Band Structure, GUI dependency, and documentation updates:

- `python .\scripts\run_checks.py --profile all --compact`: 13/13 checks
  passed, including 201 unit tests.
- `python .\scripts\release_candidate_walkthrough.py --compact`: 9/9 offline
  steps passed.
- `python .\scripts\build_launcher.py --compact`: wrote `WinQStep.exe`.
- `python .\scripts\build_release.py --compact`: wrote
  `dist/winqstep-0.3.0.zip` and `dist/winqstep-0.3.0.manifest.json`, with 116
  planned source files plus archive `RELEASE-MANIFEST.json`.
- `python .\scripts\smoke_release_install.py --archive .\dist\winqstep-0.3.0.zip --compact`:
  valid unpacked diagnostics.
- `python .\scripts\run_checks.py --profile live --compact`: 3/3 live checks
  passed on the maintainer workstation with WSL2 `Ubuntu` and
  `/home/teng/cp2k/exe/local/cp2k.ssmp`.
- The live validation also covers WSL CP2K data inspection, GUI button smoke,
  and a real GUI async `Run` CP2K `ENERGY` job.
- The authoritative archive SHA-256 is the value in
  `dist/winqstep-0.3.0.manifest.json`; do not duplicate it in packaged docs,
  because this handoff note is itself included in the archive.

Round 57 adds QuickStep XC/PBE parametrization and opt-in DFT-D3 support. The
local checks for this round were:

- `python .\scripts\run_checks.py --profile fast --compact`: 2/2 checks
  passed, including 156 unit tests.
- `python .\scripts\run_checks.py --profile release --compact`: 3/3 checks
  passed. With the optional EXE present, release planning listed 111 files.

Round 56 adds the optional thin EXE launcher. The local launcher/release checks
for this round were:

- `python .\scripts\build_launcher.py --compact`: wrote `WinQStep.exe`.
- `python .\scripts\run_checks.py --profile fast --compact`: 2/2 checks
  passed, including 150 unit tests.
- `python .\scripts\run_checks.py --profile release --compact`: 3/3 checks
  passed. With the optional EXE present, release planning listed 110 files.

Round 51 prepares the `0.2.0` source-release candidate after the post-`0.1.0`
GUI, QuickStep, preview, and documentation updates:

- `python .\scripts\run_checks.py --profile all --compact`: 9/9 checks passed,
  including 141 unit tests.
- `python .\scripts\release_candidate_walkthrough.py --compact`: passed as
  part of the `rc` profile in `run_checks.py --profile all`, with 9 offline
  steps passed.
- `python .\scripts\build_release.py --compact`: wrote
  `dist/winqstep-0.2.0.zip` and `dist/winqstep-0.2.0.manifest.json`, with 106
  planned source files plus archive `RELEASE-MANIFEST.json`.
- `python .\scripts\smoke_release_install.py --archive .\dist\winqstep-0.2.0.zip --compact`:
  valid unpacked diagnostics.
- The authoritative archive SHA-256 is the value in
  `dist/winqstep-0.2.0.manifest.json`; do not duplicate it in packaged docs,
  because this handoff note is itself included in the archive.

The previous `0.1.0` release baseline was:

- `python .\scripts\run_checks.py --profile all --compact`: 9/9 checks passed.
- `python .\scripts\release_candidate_walkthrough.py --compact`: 9/9 steps
  passed.
- `python .\scripts\build_release.py --compact`: valid archive with 99 source
  files plus archive `RELEASE-MANIFEST.json`.
- `python .\scripts\smoke_release_install.py --archive .\dist\winqstep-0.1.0.zip --compact`:
  valid unpacked diagnostics.

The previous `0.1.0` optional live checks also passed on the local WSL2/CP2K
setup:

- `python .\scripts\release_candidate_walkthrough.py --include-live --keep-workspace --compact`:
  10/10 steps, including a real `ENERGY_FORCE` CP2K run.
- Parsed live result included `total_energy_hartree` and
  `forces.total_atomic_force` in `hartree/bohr`.
- `python .\scripts\run_checks.py --profile live --compact`: 2/2 checks.

Rerun the required handoff commands after any code, docs, config, or packaging
change.

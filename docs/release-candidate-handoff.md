# Release Candidate Handoff

This note is the short handoff checklist for a WinQStep source-release
candidate. It complements `docs/release.md`, which documents the packaging
mechanics in more detail.

## Candidate Scope

Current package version: `0.1.0`.

This is a local Windows prototype, not an installer or PyPI release. The
candidate supports:

- WSL2 CP2K QuickStep execution through `wsl.exe`.
- GUI and CLI workflows for generated `ENERGY`, `ENERGY_FORCE`, and `GEO_OPT`
  inputs.
- Existing CP2K `.inp` execution without regenerating the input.
- Config and template editing, CP2K data inspection, preflight validation, job
  history, artifact inspection, and structured result summary export.
- Source-release zip packaging and unpacked release smoke testing.

## Required Handoff Commands

Run from the repository root before handing off a candidate:

```powershell
git status --short
python .\scripts\run_checks.py --profile all --compact
python .\scripts\release_candidate_walkthrough.py --compact
python .\scripts\build_release.py --compact
python .\scripts\smoke_release_install.py --archive .\dist\winqstep-0.1.0.zip --compact
```

Expected minimum result:

- `git status --short` prints no tracked or untracked release-relevant changes.
- `run_checks.py --profile all` reports `valid: true`.
- `release_candidate_walkthrough.py` reports `valid: true` with 9 offline
  steps passed.
- `build_release.py` writes `dist/winqstep-0.1.0.zip` and
  `dist/winqstep-0.1.0.manifest.json`.
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

- `dist/winqstep-0.1.0.zip`
- `dist/winqstep-0.1.0.manifest.json`
- the SHA-256 value from the manifest or `build_release.py` output
- this handoff note and `docs/release.md`

Do not hand off `outputs/`, `build/`, local `dist/` work folders other than the
release zip and manifest, CP2K snapshots, virtual environments, caches, or
Codex thread files.

## First-Run Path for Testers

After unpacking the zip on Windows:

```powershell
.\WinQStep.ps1 -Diagnostics -SkipLiveProbes
.\WinQStep.ps1 -Diagnostics
.\WinQStep.ps1
```

Use `-Diagnostics -SkipLiveProbes` first to verify Python, PowerShell,
repository files, config shape, and release hygiene without touching WSL. Use
full `-Diagnostics` only when WSL2 and CP2K are expected to be available.

## Known Limitations

- QuickStep only. Other CP2K modules are outside the current scope.
- Supported generated run types are `ENERGY`, `ENERGY_FORCE`, and `GEO_OPT`.
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

Round 32 produced and verified the current `0.1.0` source-release candidate:

- `python .\scripts\run_checks.py --profile all --compact`: 9/9 checks.
- `python .\scripts\release_candidate_walkthrough.py --compact`: 9/9 steps.
- `python .\scripts\build_release.py --compact`: valid archive with 99 source
  files plus archive `RELEASE-MANIFEST.json`.
- `python .\scripts\smoke_release_install.py --archive .\dist\winqstep-0.1.0.zip --compact`:
  valid unpacked diagnostics.
- The authoritative archive SHA-256 is the value in
  `dist/winqstep-0.1.0.manifest.json`; do not duplicate it in packaged docs,
  because this handoff note is itself included in the archive.

The optional live checks also passed on the local WSL2/CP2K setup:

- `python .\scripts\release_candidate_walkthrough.py --include-live --keep-workspace --compact`:
  10/10 steps, including a real `ENERGY_FORCE` CP2K run.
- Parsed live result included `total_energy_hartree` and
  `forces.total_atomic_force` in `hartree/bohr`.
- `python .\scripts\run_checks.py --profile live --compact`: 2/2 checks.

Rerun the required handoff commands after any code, docs, config, or packaging
change.

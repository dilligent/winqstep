# Release Notes

## 0.3.0 Candidate

This candidate builds on `0.2.0` with a more complete GUI workflow for existing
inputs, safer QuickStep template dependencies, and additional DFT print output
coverage.

Highlights:

- Added GUI support for existing-input batch workflows, including separate
  directory, multi-file, and input-list entry points; batch preview/result
  summaries; result table export; resume; and queue actions for skip, rerun,
  and cancel.
- Added generated-input support and GUI controls for QuickStep
  `DFT/&PRINT/&BAND_STRUCTURE`, including output-file handling, `KPOINT_SET`
  fields, special k-point editing, and `.bs`/`.band` artifact classification.
- Tightened GUI scientific dependency behavior for periodicity-sensitive
  options. KPOINTS and Band Structure are disabled for visible nonperiodic cell
  settings, explicit `POISSON_SOLVER` choices warn on incompatible periodicity,
  and `CELL_OPT` warns when paired with visible nonperiodic cell settings.
- Improved Template ergonomics after the expanded QuickStep coverage: section
  hints, nested CP2K section grouping, manual link access, and layout fixes for
  Band Structure controls.
- Continued GUI hardening through broader button, batch, lifecycle, stress, and
  localization smoke tests.
- Fixed release-candidate validation issues in live WSL2/CP2K paths: CP2K data
  inspection now preserves WSL-side shell variables correctly, and GUI async
  runs drain wrapper stdout/stderr while the job is running so completed jobs do
  not stall before artifacts update.

Packaging notes:

- CP2K binaries, CP2K source trees, CP2K data files, WSL distros, Python
  runtimes, and virtual environments remain external dependencies.
- The expected source-release artifacts are `dist/winqstep-0.3.0.zip` and
  `dist/winqstep-0.3.0.manifest.json`.
- Follow `docs/release-candidate-handoff.md` for the required verification
  commands before tagging or publishing.

## 0.2.0 Candidate

This candidate updates the original `0.1.0` Windows prototype with broader
QuickStep coverage, a more usable GUI workflow, and clearer release handoff
requirements.

Highlights:

- Added generated-input support and GUI controls for additional QuickStep
  options, including SCF method details, KPOINTS, CELL_OPT, GLOBAL PRINT_LEVEL,
  DFT PRINT file outputs such as PDOS/cube/band-structure files, and fuller
  CP2K section grouping in the Template tab.
- Improved GUI reliability for asynchronous CP2K runs, live UTF-8 job-log tails,
  overflow scrolling, tab order, and language application.
- Added confirmation before running manually edited generated input, preserving
  the edited input as a separate saved file.
- Replaced raw Environment and Structure JSON displays with readable summaries
  while preserving raw diagnostic output in Job Log where appropriate.
- Added a native WPF 3D Structure preview with atom/cell rendering, rotate,
  zoom, pan, reset, and field-of-view-aware initial framing.
- Clarified first-run requirements: this is still a source-release zip, not an
  installer, and it expects external Python, ASE, WSL2, CP2K, and CP2K data.

Packaging notes:

- CP2K binaries, CP2K source trees, CP2K data files, WSL distros, Python
  runtimes, and virtual environments remain external dependencies.
- The expected source-release artifacts are `dist/winqstep-0.2.0.zip` and
  `dist/winqstep-0.2.0.manifest.json`.
- Follow `docs/release-candidate-handoff.md` for the required verification
  commands before tagging or publishing.

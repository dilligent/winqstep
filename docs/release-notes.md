# Release Notes

## 0.2.0 Candidate

This candidate updates the original `0.1.0` Windows prototype with broader
QuickStep coverage, a more usable GUI workflow, and clearer release handoff
requirements.

Highlights:

- Added generated-input support and GUI controls for additional QuickStep
  options, including SCF method details, KPOINTS, CELL_OPT, GLOBAL PRINT_LEVEL,
  and fuller CP2K section grouping in the Template tab.
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

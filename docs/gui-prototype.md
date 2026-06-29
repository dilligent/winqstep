# GUI Prototype

Round 6 added a thin Windows GUI prototype over the command-line core. The UI is
implemented as a PowerShell-hosted WPF window because this machine has the .NET
Desktop runtime but no .NET SDK. That keeps the prototype runnable without
adding a build toolchain.

Round 8 adds a mode selector for the two supported job paths:

- `Workflow`: structure file plus calculation template, routed through
  `scripts/run_workflow.py`
- `Existing input`: user-provided `.inp`, routed through
  `scripts/run_existing_input.py`

Round 10 adds a job history browser over existing metadata files. The `History`
button scans the selected job folder with `scripts/list_job_history.py`, and the
`History` tab lists previous generated, workflow, and existing-input jobs.

Round 11 adds the `Config` tab plus `Load Config` and `Save Config` buttons.
The fields are loaded and saved through `scripts/manage_config.py`, so the GUI
uses the same validation and stable UTF-8 JSON writer as the command line.

Round 12 adds the `Template` tab plus `Load Template` and `Save Template`
buttons. The tab edits the existing workflow template JSON through
`scripts/manage_template.py`.

Round 13 adds the `Inspect Data` button. It scans the configured CP2K data
directory with `scripts/inspect_cp2k_data.py`, caches the extracted labels, and
shows basis/potential choices in the `Template` tab.

Round 17 adds job input preflight validation. Before `Preview` or `Run`, the GUI
calls `scripts/validate_job_inputs.py` to catch missing workflow KIND entries
and obvious CP2K data-file mismatches before CP2K starts.

Round 18 adds `WinQStep.ps1` and `WinQStep.cmd` launchers plus a startup
diagnostics mode that can check repository files, config, release hygiene, and
optional WSL/CP2K availability before opening the main window.

Round 19 splits the PowerShell-hosted GUI into separate files. The main script
still owns event wiring and GUI workflows, but the WPF layout now lives in
`scripts/gui/WinQStep.xaml`, while reusable host/process/file helpers live in
`scripts/gui/WinQStep.GuiHost.ps1`.

Round 20 adds GUI localization resources for `en-US` and `zh-CN`. The GUI
defaults from Windows UI culture, and `-Language` can force a specific language
for local testing or daily use.

Round 21 adds a `UI Language` field to the `Config` tab. Saving the config
persists `ui_language` as `en-US`, `zh-CN`, or an empty system-default value.
The launcher `-Language` option remains a temporary override and does not write
the config.

## Start

```powershell
.\WinQStep.ps1
```

Force a language when needed:

```powershell
.\WinQStep.ps1 -Language zh-CN
```

Persist a language preference from the `Config` tab by choosing `UI Language`
and pressing `Save Config`.

The lower-level command remains available:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start_gui.ps1
```

Run startup diagnostics without showing the GUI:

```powershell
.\WinQStep.ps1 -Diagnostics
```

The window defaults to the repository sample config, the PBE energy template,
the water XYZ fixture, and the QuickStep input fixture. The buttons call the
same scripts used by tests:

- `Detect`: `scripts/detect_environment.py`
- `Import`: `scripts/import_structure.py`
- `Preview`: `scripts/run_workflow.py --prepare-only` or
  `scripts/run_existing_input.py --prepare-only`
- `Run`: starts `scripts/run_workflow.py` or `scripts/run_existing_input.py`
  in a background process
- Preflight before `Preview` or `Run`: `scripts/validate_job_inputs.py`
- `Stop`: requests cancellation for the running background job
- `History`: `scripts/list_job_history.py`
- `Load Config` and `Save Config`: `scripts/manage_config.py`
- `Load Template` and `Save Template`: `scripts/manage_template.py`
- `Inspect Data`: `scripts/inspect_cp2k_data.py`

The top action buttons wrap onto additional rows when the window is too narrow,
so every action remains reachable without maximizing the window.

The main tab order follows the common workflow path: `Config`, `Template`,
`Input Preview`, `Structure`, `Environment`, `Job Log`, `Artifacts`, and
`History`. `Template` and `Input Preview` are adjacent so users can edit template
fields and immediately inspect the generated CP2K input without crossing
diagnostic tabs. They remain separate tabs to keep the editable template grid
and read-only input text pane from competing for vertical space.

The GUI does not parse or generate CP2K input itself. It displays JSON, rendered
input text, job metadata, and CP2K output summaries produced by the core
commands.

The GUI layout is intentionally separate from event wiring. Edit
`scripts/gui/WinQStep.xaml` for controls and layout, and edit
`scripts/start_gui.ps1` for event handlers and view-state behavior.
User-facing GUI strings live in `resources/i18n/`, while CP2K keywords, JSON
keys, metadata, paths, and raw CP2K output remain untranslated.

Double-clicking a row in the history grid loads the selected metadata into the
job log pane and the selected CP2K output file into the input preview pane.

The PowerShell host forces UTF-8 for Python subprocess output so Windows paths
with Chinese characters render correctly in the text panes.

`Detect` saves the current config fields before probing. `Preview` and `Run`
save and validate the current config first, requiring `cp2k_command` and
`cp2k_data_dir` before any job command is prepared or launched.

In workflow mode, `Preview` and `Run` also save and validate the current
template fields before rendering input. They then preflight the saved template
against the selected structure and the latest CP2K data cache. Missing KIND
coverage and basis/potential label warnings are shown in the `Template` and
`Structure` tabs, so they can be fixed without reading Python exceptions.
Existing-input mode skips template handling but still validates that the input
file exists and warns in the preview/log panes when referenced basis or
potential files are obviously missing from the cached CP2K data inspection.

The single-line fields on the `Template` tab are editable drop-down controls:
users can select common values from the list or type a custom value directly.
Template KIND entries are shown in an editable `Element`, `Basis Set`,
`Potential` table. The hidden `KindsText` backing field is kept only so the GUI
can reuse the existing `kinds_text` JSON writer.

`Run` first performs a prepare-only pass to write input and metadata, then starts
the real CP2K job asynchronously. The GUI remains responsive while a timer
refreshes the job log pane with metadata, CP2K output tails, and stdout/stderr
tails. `Stop` terminates the Python/WSL wrapper process tree where possible and
marks the metadata as `cancelled`.

While a background job is active, the status bar shows the wrapper PID, job
folder, and output path. Closing the window is blocked until the job exits or
the user presses `Stop`, which prevents accidentally orphaning a WSL job from
the GUI.

The `Artifacts` tab shows a compact summary for the current or selected job:
job status, return code, CP2K output status, warning count, program-end marker,
and the known input, output, metadata, stdout, and stderr paths. The tab has
read-only `Input`, `Output`, `Metadata`, `Stdout`, and `Stderr` buttons that
load those files into the GUI text pane without modifying or rerunning the job.

Double-clicking a row in the CP2K data label table updates the corresponding
KIND table entry, preferring MOLOPT basis labels and GTH-PBE potentials when
available. The CP2K data label table is collapsed until `Inspect Data` returns
available labels.

## Smoke Test

Use smoke mode to validate the WPF host and default paths without showing the
window:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start_gui.ps1 -SmokeTest
```

The Python unit suite runs the same smoke test on Windows. Smoke mode validates
config loading, template loading, workflow preview, existing-input preview, and
history scanning without launching CP2K. It also verifies that the asynchronous
job controls, status bar, artifact inspection controls, and preflight script
wiring are present.
`-LifecycleSmokeTest` starts and stops a controlled background process through
the same lifecycle helpers used by `Run` and `Stop`. CP2K data inspection is
covered by unit tests with fixture data and by manual/local WSL smoke runs.

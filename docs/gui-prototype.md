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

## Start

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start_gui.ps1
```

The window defaults to the repository sample config, the PBE energy template,
the water XYZ fixture, and the QuickStep input fixture. The buttons call the
same scripts used by tests:

- `Detect`: `scripts/detect_environment.py`
- `Import`: `scripts/import_structure.py`
- `Preview`: `scripts/run_workflow.py --prepare-only` or
  `scripts/run_existing_input.py --prepare-only`
- `Run`: `scripts/run_workflow.py` or `scripts/run_existing_input.py`
- `History`: `scripts/list_job_history.py`
- `Load Config` and `Save Config`: `scripts/manage_config.py`
- `Load Template` and `Save Template`: `scripts/manage_template.py`
- `Inspect Data`: `scripts/inspect_cp2k_data.py`

The GUI does not parse or generate CP2K input itself. It displays JSON, rendered
input text, job metadata, and CP2K output summaries produced by the core
commands.

Double-clicking a row in the history grid loads the selected metadata into the
job log pane and the selected CP2K output file into the input preview pane.

The PowerShell host forces UTF-8 for Python subprocess output so Windows paths
with Chinese characters render correctly in the text panes.

`Detect` saves the current config fields before probing. `Preview` and `Run`
save and validate the current config first, requiring `cp2k_command` and
`cp2k_data_dir` before any job command is prepared or launched.

In workflow mode, `Preview` and `Run` also save and validate the current
template fields before rendering input. Existing-input mode skips template
handling.

Double-clicking a row in the CP2K data label table updates the corresponding
`KindsText` entry, preferring MOLOPT basis labels and GTH-PBE potentials when
available.

## Smoke Test

Use smoke mode to validate the WPF host and default paths without showing the
window:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start_gui.ps1 -SmokeTest
```

The Python unit suite runs the same smoke test on Windows. Smoke mode validates
config loading, template loading, workflow preview, existing-input preview, and
history scanning without launching CP2K. CP2K data inspection is covered by
unit tests with fixture data and by manual/local WSL smoke runs.

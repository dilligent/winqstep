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

The GUI does not parse or generate CP2K input itself. It displays JSON, rendered
input text, and job metadata produced by the core commands.

## Smoke Test

Use smoke mode to validate the WPF host and default paths without showing the
window:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start_gui.ps1 -SmokeTest
```

The Python unit suite runs the same smoke test on Windows. Smoke mode validates
both workflow preview and existing-input preview without launching CP2K.

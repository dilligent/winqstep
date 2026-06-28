# GUI Prototype

Round 6 adds a thin Windows GUI prototype over the command-line core. The UI is
implemented as a PowerShell-hosted WPF window because this machine has the .NET
Desktop runtime but no .NET SDK. That keeps the prototype runnable without
adding a build toolchain.

## Start

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start_gui.ps1
```

The window defaults to the repository sample config, the PBE energy template,
and the water XYZ fixture. The buttons call the same scripts used by tests:

- `Detect`: `scripts/detect_environment.py`
- `Import`: `scripts/import_structure.py`
- `Preview`: `scripts/run_workflow.py --prepare-only`
- `Run`: `scripts/run_workflow.py`

The GUI does not parse or generate CP2K input itself. It displays JSON, rendered
input text, and job metadata produced by the core commands.

## Smoke Test

Use smoke mode to validate the WPF host and default paths without showing the
window:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start_gui.ps1 -SmokeTest
```

The Python unit suite runs the same smoke test on Windows.

# Job History

Round 10 adds metadata discovery for previous WinQStep jobs. The scanner reads
`*.winqstep.json` files from a selected workspace folder and returns a compact
list for the GUI or other tools.

## CLI

```powershell
python .\scripts\list_job_history.py --workspace .\outputs
```

By default the scan is recursive. Use `--no-recursive` to inspect only the
selected folder:

```powershell
python .\scripts\list_job_history.py --workspace .\outputs\smoke-energy --no-recursive
```

Use `--limit` for short lists and `--compact` for machine-readable single-line
JSON:

```powershell
python .\scripts\list_job_history.py --workspace .\outputs --limit 10 --compact
```

Each job item includes:

- metadata path
- status and return code
- job mode: `workflow`, `quickstep`, or `existing_input`
- project/input name and run type when available
- input, output, stdout, and stderr paths
- CP2K output status, warning count, and program-end marker

Invalid metadata files are returned in the top-level `errors` array instead of
stopping the whole scan.

## GUI

The PowerShell WPF prototype has a `History` button and a `History` tab. The
button scans the current `Job Folder` recursively and fills the grid with recent
metadata, newest first.

Double-click a history row to load:

- the selected metadata JSON into `Job Log`
- the selected CP2K `.out` file into `Input Preview`, if present

This does not rerun CP2K or rewrite existing job files.

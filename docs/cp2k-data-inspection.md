# CP2K Data File Inspection

Round 13 adds read-only inspection for CP2K data files. The scanner extracts
basis set and potential labels from files such as `BASIS_MOLOPT` and
`GTH_POTENTIALS` so the template editor can show available choices.

## CLI

Inspect the configured WSL CP2K data directory:

```powershell
python .\scripts\inspect_cp2k_data.py --config .\examples\winqstep.config.json
```

By default, if the config contains `default_windows_workspace`, the command
writes a job-independent cache file named:

```text
cp2k-data.winqstep-cache.json
```

Use an explicit cache path or disable cache writing:

```powershell
python .\scripts\inspect_cp2k_data.py --config .\examples\winqstep.config.json --cache .\outputs\cp2k-data-cache.json
python .\scripts\inspect_cp2k_data.py --config .\examples\winqstep.config.json --no-cache
```

For tests or local snapshots, inspect a Windows folder directly:

```powershell
python .\scripts\inspect_cp2k_data.py --windows-data-dir .\tests\fixtures\cp2k_data --no-cache
```

The output includes:

- inspected files and file types
- basis set labels by element
- potential labels by element
- combined `labels_by_element` rows for GUI display
- counts and cache path

## GUI

The GUI has an `Inspect Data` button in the top action bar. It saves and
validates the current config, scans the configured WSL `cp2k_data_dir`, writes
the cache in the configured workspace, and fills the CP2K data table in the
`Template` tab.

Double-click a row in the CP2K data table to update that element in the
template KIND table. The GUI prefers `MOLOPT` basis labels and `GTH-PBE`
potentials when several labels are available.

The scanner is read-only with respect to the WSL CP2K data directory.

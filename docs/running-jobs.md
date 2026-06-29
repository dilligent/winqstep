# Running Jobs

WinQStep can now render a QuickStep model JSON file, create a job folder, run
CP2K through WSL, and write metadata that records what happened.

## Command

```powershell
python .\scripts\run_quickstep_job.py --config .\examples\winqstep.config.json --input-json .\examples\quickstep_energy.json --job-dir .\outputs\smoke-energy
```

The command writes:

- `<project>.inp`: rendered CP2K input;
- `<project>.out`: CP2K output requested with `-o`;
- `<project>.stdout.log`: stdout from the CP2K command;
- `<project>.stderr.log`: stderr from the CP2K command;
- `<project>.winqstep.json`: WinQStep metadata.

The metadata includes the dry-run command, return code, job status, wrapper
stdout/stderr from `wsl.exe`, file existence/size information, and a compact
`cp2k_output` summary parsed from the `.out` file.

Before launching CP2K, the runner removes stale `.out`, `.stdout.log`, and
`.stderr.log` files for the same input stem so repeated runs do not append or
mix old output into a new result.

## Prepare Only

Use `--prepare-only` to write input and metadata without launching CP2K:

```powershell
python .\scripts\run_quickstep_job.py --config .\examples\winqstep.config.json --input-json .\examples\quickstep_energy.json --job-dir .\outputs\prepared --prepare-only
```

This is useful for UI previews and command inspection.

## Status

- `prepared`: input and metadata were written, but CP2K was not started.
- `succeeded`: CP2K process returned `0`.
- `failed`: CP2K or WSL returned a non-zero exit code.
- `cancelled`: the GUI requested cancellation and marked the metadata after
  stopping the wrapper process tree.

Raw CP2K output is preserved. The runner does not parse scientific results yet.
It only extracts diagnostic run markers such as warning count and whether CP2K
printed `PROGRAM ENDED AT`.

## GUI Artifacts

After a preview, run, or history selection, the GUI `Artifacts` tab lists the
known input, output, metadata, stdout, and stderr files. The artifact buttons
read those files into the GUI without opening them for editing. Missing files
remain disabled, which is expected for prepare-only jobs before CP2K writes
output.

## GUI Lifecycle Smoke

The GUI script has a non-interactive lifecycle smoke mode for the background
process helpers:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start_gui.ps1 -LifecycleSmokeTest
```

It starts a controlled sleeper process through the same helper used by `Run`,
stops it through the same process-tree helper used by `Stop`, and emits JSON
describing whether the process started and stopped.

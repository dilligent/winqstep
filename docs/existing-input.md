# Existing CP2K Input Jobs

WinQStep can run a user-provided CP2K `.inp` file without regenerating or
modifying it. This path is useful when a user already has a working CP2K input
and only wants WinQStep to handle WSL path conversion, `CP2K_DATA_DIR`, logs, and
metadata.

## Command

```powershell
python .\scripts\run_existing_input.py --config .\examples\winqstep.config.json --input D:\path\to\job.inp --job-dir .\outputs\existing-job
```

Use `--prepare-only` to validate paths and write metadata without starting
CP2K:

```powershell
python .\scripts\run_existing_input.py --config .\examples\winqstep.config.json --input D:\path\to\job.inp --job-dir .\outputs\existing-job --prepare-only
```

The command writes output files in the job folder using the input file stem:

- `<input-stem>.out`
- `<input-stem>.stdout.log`
- `<input-stem>.stderr.log`
- `<input-stem>.winqstep.json`

Before a real run, stale output and log files for the same input stem are
removed. The input file is never rewritten or copied over.

# Existing CP2K Input Jobs

WinQStep can run a user-provided CP2K `.inp` file without regenerating or
modifying it. This path is useful when a user already has a working CP2K input
and only wants WinQStep to handle WSL path conversion, `CP2K_DATA_DIR`, logs, and
metadata.

## Command

```powershell
python .\scripts\run_existing_input.py --config .\examples\winqstep.config.example.json --input D:\path\to\job.inp --job-dir .\outputs\existing-job
```

Use `--prepare-only` to validate paths and write metadata without starting
CP2K:

```powershell
python .\scripts\run_existing_input.py --config .\examples\winqstep.config.example.json --input D:\path\to\job.inp --job-dir .\outputs\existing-job --prepare-only
```

The command writes output files in the job folder using the input file stem:

- `<input-stem>.out`
- `<input-stem>.stdout.log`
- `<input-stem>.stderr.log`
- `<input-stem>.winqstep.json`

Before a real run, stale output and log files for the same input stem are
removed. The input file is never rewritten or copied over.

Completed metadata includes a `cp2k_output` summary with warning count and
whether CP2K printed its `PROGRAM ENDED AT` marker.

## Batch Command

Existing-input jobs can also be processed as a serial batch:

```powershell
python .\scripts\run_existing_input_batch.py --config .\examples\winqstep.config.example.json --input-dir D:\path\to\inputs --job-dir .\outputs\batch-existing --prepare-only
```

Inputs can be supplied in three ways, and the command de-duplicates resolved
paths while preserving first-seen order:

- repeat `--input D:\path\to\job.inp` for explicit files;
- use `--input-dir D:\path\to\inputs` with `--glob *.inp` to scan a directory;
- use `--input-list inputs.txt`, a UTF-8 text file with one input path per line
  and `#` comments allowed. Relative paths in the list are resolved from the
  list file's folder.

By default, each input runs in a stable subdirectory under `--job-dir`, using
the input stem as the subdirectory name. If two inputs share the same stem, the
later item gets a short hash suffix so output files do not collide. The command
writes a batch index named `batch.winqstep-batch.json` in `--job-dir`; this file
records item status, return code, metadata path, output path, and error text.
It deliberately does not use the `*.winqstep.json` suffix, so History scans only
the per-item job metadata files.

Use `--prepare-only` to create per-item metadata without launching CP2K. During
real execution the batch is serial by default. A failed item is recorded and the
next item continues unless `--stop-on-failure` is set.

If a batch was interrupted after `batch.winqstep-batch.json` was written, resume
the pending queue items with:

```powershell
python .\scripts\run_existing_input_batch.py --config .\examples\winqstep.config.example.json --job-dir .\outputs\batch-existing --resume
```

Completed, skipped, and cancelled items are not rerun by resume. Stale
`running` items left by an interrupted wrapper are put back in the queue.
Use the management command to adjust a single item:

```powershell
python .\scripts\manage_existing_input_batch.py --summary .\outputs\batch-existing\batch.winqstep-batch.json --index 2 --action skip
python .\scripts\manage_existing_input_batch.py --summary .\outputs\batch-existing\batch.winqstep-batch.json --index 2 --action rerun
python .\scripts\manage_existing_input_batch.py --summary .\outputs\batch-existing\batch.winqstep-batch.json --index 2 --action cancel
```

`rerun` queues the item for the next resume. `cancel` marks an idle item as
cancelled; if the item is currently running, the batch runner records a
cancel-request flag, terminates that CP2K process, marks the item cancelled, and
continues the remaining serial queue.

If an existing CP2K input relies on relative include/data paths from its own
folder, use:

```powershell
python .\scripts\run_existing_input_batch.py --config .\examples\winqstep.config.example.json --input-list .\inputs.txt --job-dir .\outputs\batch-existing --job-layout input-dirs
```

`--job-layout input-dirs` keeps each job's working directory beside its input
file while still writing the batch index to `--job-dir`.

## GUI Batch Mode

The GUI has an `Existing input batch` mode in the top `Mode` selector. In this
mode the batch inputs panel has separate fields for a directory, one or more
explicit `.inp` files, and an input-list file. Each field has its own browse
button, and the panel shows the number of input files that will run. `Preview` runs
`scripts/run_existing_input_batch.py --prepare-only` to write and display
`batch.winqstep-batch.json`.

`Run` first performs the same prepare-only batch check. If that summary is
valid, the GUI starts the real serial batch in the background and updates `Job
Log` from the batch index while it runs. The log includes explicit
`current/total`, completed item count, queued/running item count, and
succeeded/failed/error/skipped/cancelled counts.
`Artifacts` exposes the batch summary as metadata, shows a read-only per-item
result table, and lets `Save Results` export that table as `batch-results.tsv`.
Per-input job metadata remains visible through `History` after users load the
batch job folder.

The `Artifacts` tab also exposes batch queue controls. Select a row in the
batch result table, then use `Skip Item`, `Rerun Item`, or `Cancel Item` to
update that item in `batch.winqstep-batch.json`. Use `Resume Batch` to continue
queued or stale running items after an interruption, or after queueing a rerun.

The `.inp Files` field remains editable after multi-select browsing, so users
can paste or adjust paths manually. Input-list files should be UTF-8 text files
with one input path per line.

Batch execution is intentionally serial. WinQStep does not try to schedule true
parallel CP2K work; users who need parallel numerical execution should configure
CP2K/MPI for each individual input.

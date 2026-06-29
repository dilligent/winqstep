# WSL Execution

WinQStep runs CP2K as an external command in WSL2. The execution layer must be
predictable because path handling and process control are common failure points.

## Environment Detection

The application should detect:

- installed WSL distros and their WSL version;
- the selected distro;
- CP2K command path, such as `cp2k.psmp` or `cp2k`;
- optional MPI command path, such as `mpirun` or `mpiexec`;
- `CP2K_DATA_DIR`;
- basis and potential files visible from `CP2K_DATA_DIR`.

Detection results should be stored as JSON so the GUI and tests can consume the
same data.

## Shell Prelude

Every WSL-side command may run an optional shell prelude before the actual work.
The current local policy is to deactivate conda first:

```bash
conda deactivate >/dev/null 2>&1 || true
```

This keeps CP2K probing and future job execution out of accidental conda
environments while remaining harmless when conda is not installed or not active.

## Path Rules

- Windows project folders are the user's source of truth.
- Paths passed into WSL must be converted to Linux paths before execution.
- Generated inputs should be written to a stable job folder before CP2K starts.
- Output files should be kept with the input that produced them.
- The runner should never depend on the GUI process current directory.
- Absolute Windows drive paths convert to `/mnt/<drive>/...`, preserving path
  segments, spaces, and non-ASCII characters.

## Command Shape

The eventual runner should build commands equivalent to:

```powershell
wsl.exe -d <distro> -- bash -lc "<quoted Linux command>"
```

The Linux command should:

1. run the configured shell prelude;
2. change to the job working directory;
3. set required environment variables;
4. run either CP2K directly or through MPI;
5. write stdout/stderr to files that the GUI can stream or tail.

## Dry-run Jobs

The current command builder emits JSON metadata without starting CP2K:

```powershell
python .\scripts\build_job_dry_run.py --config .\examples\winqstep.config.json --input D:\path\to\water.inp
```

The `--input` value must be an absolute Windows drive path because this helper
exists to preview Windows-to-WSL path conversion.

The dry-run output includes:

- Windows input, output, stdout, stderr, and metadata paths;
- WSL input and job directory paths;
- the WSL-side shell command;
- the Windows `wsl.exe` argument vector.

This keeps path conversion and quoting testable before long-running CP2K jobs
are enabled.

## Running Jobs

`scripts/run_quickstep_job.py` uses the same dry-run model, then executes the
generated `wsl.exe` argument vector. It writes rendered input, CP2K output,
stdout/stderr logs, and metadata in the selected job folder.

The runner treats the process return code as the source of truth for
`succeeded` or `failed`. It preserves raw CP2K output for later inspection
instead of trying to interpret scientific results.

## Cancellation

The GUI starts CP2K through a Python wrapper process and keeps the window
responsive with timer-based log refresh. `Stop` requests cancellation by
terminating the wrapper process tree, including child `wsl.exe` processes where
Windows exposes them. The job metadata is then marked as `cancelled`.

Round 15 keeps this Windows process-tree cancellation as the default because it
is simple, works with the current direct `cp2k.ssmp` path, and preserves
metadata consistently. A stronger WSL-side helper is deferred until MPI and
long-running CP2K cancellation are validated, because launcher behavior can vary
and killing only `wsl.exe` may not be sufficient for every process group.

## Error Handling

The runner should preserve raw CP2K output. GUI messages can summarize common
failures, but users must be able to inspect the original `.out` and stderr text.

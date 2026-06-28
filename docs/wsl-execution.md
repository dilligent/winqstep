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

## Path Rules

- Windows project folders are the user's source of truth.
- Paths passed into WSL must be converted to Linux paths before execution.
- Generated inputs should be written to a stable job folder before CP2K starts.
- Output files should be kept with the input that produced them.
- The runner should never depend on the GUI process current directory.

## Command Shape

The eventual runner should build commands equivalent to:

```powershell
wsl.exe -d <distro> -- bash -lc "<quoted Linux command>"
```

The Linux command should:

1. change to the job working directory;
2. set required environment variables;
3. run either CP2K directly or through MPI;
4. write stdout/stderr to files that the GUI can stream or tail.

## Cancellation

Stopping a job must stop the WSL-side process group, not just the Windows
`wsl.exe` wrapper. This should be treated as a first-class design requirement
before long-running jobs are supported.

## Error Handling

The runner should preserve raw CP2K output. GUI messages can summarize common
failures, but users must be able to inspect the original `.out` and stderr text.

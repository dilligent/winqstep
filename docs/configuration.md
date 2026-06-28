# Configuration

WinQStep environment detection can use a JSON config file. This is important on
machines where CP2K works interactively but is not exported through a global WSL
environment.

## Example

See `examples/winqstep.config.json`.

```json
{
  "distro": "Ubuntu",
  "cp2k_command": "cp2k.ssmp",
  "mpirun_command": "",
  "cp2k_data_dir": "/mnt/d/Library/自制品/winqstep/cp2k-2026.1/data",
  "default_windows_workspace": "D:\\Library\\自制品\\winqstep\\outputs",
  "wsl_shell_prelude": "conda deactivate >/dev/null 2>&1 || true",
  "timeout": 20
}
```

## Usage

```powershell
python .\scripts\detect_environment.py --config .\examples\winqstep.config.json
```

Command-line arguments override config values:

```powershell
python .\scripts\detect_environment.py --config .\examples\winqstep.config.json --cp2k-command /usr/local/bin/cp2k.ssmp
```

## Keys

- `distro`: WSL distro name, such as `Ubuntu`.
- `cp2k_command`: CP2K command inside WSL. For this project machine, the normal
  direct command is `cp2k.ssmp`.
- `mpirun_command`: optional MPI launcher. Use an empty string when direct
  `cp2k.ssmp` execution is preferred.
- `cp2k_data_dir`: CP2K data directory inside WSL.
- `default_windows_workspace`: default Windows folder for future job outputs.
- `wsl_shell_prelude`: shell code to run before each WSL command. The sample
  uses `conda deactivate >/dev/null 2>&1 || true` so conda environments do not
  leak into CP2K probing or future job execution.
- `timeout`: subprocess timeout in seconds.

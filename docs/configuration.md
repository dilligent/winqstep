# Configuration

WinQStep environment detection can use a JSON config file. This is important on
machines where CP2K works interactively but is not exported through a global WSL
environment.

## Example

See `examples/winqstep.config.json`.

```json
{
  "distro": "Ubuntu",
  "cp2k_command": "/home/teng/cp2k/exe/local/cp2k.ssmp",
  "mpirun_command": "",
  "cp2k_data_dir": "/home/teng/cp2k/data",
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

Round 11 adds a config management command used by the GUI:

```powershell
python .\scripts\manage_config.py --config .\examples\winqstep.config.json --require-execution
```

It validates the JSON shape, rejects unknown keys, checks that CP2K execution
fields are present when `--require-execution` is used, and emits normalized JSON
with diagnostics. To rewrite a config with stable key order and UTF-8 text:

```powershell
python .\scripts\manage_config.py --config .\examples\winqstep.config.json --write --fields-json "{\"distro\":\"Ubuntu\",\"cp2k_command\":\"/home/teng/cp2k/exe/local/cp2k.ssmp\",\"mpirun_command\":\"\",\"cp2k_data_dir\":\"/home/teng/cp2k/data\",\"default_windows_workspace\":\"D:\\Library\\自制品\\winqstep\\outputs\",\"wsl_shell_prelude\":\"conda deactivate >/dev/null 2>&1 || true\",\"timeout\":\"20\"}"
```

## Keys

- `distro`: WSL distro name, such as `Ubuntu`.
- `cp2k_command`: CP2K command inside WSL. Use an absolute path when the command
  is only available after interactive shell initialization.
- `mpirun_command`: optional MPI launcher. Use an empty string when direct
  `cp2k.ssmp` execution is preferred.
- `cp2k_data_dir`: CP2K data directory inside WSL.
- `default_windows_workspace`: default Windows folder for future job outputs.
- `wsl_shell_prelude`: shell code to run before each WSL command. The sample
  uses `conda deactivate >/dev/null 2>&1 || true` so conda environments do not
  leak into CP2K probing or future job execution.
- `timeout`: subprocess timeout in seconds.

For execution, `cp2k_command` and `cp2k_data_dir` must be present. CP2K command,
MPI command, and CP2K data directory values are WSL-side values; Windows paths
such as `D:\...` are rejected for those fields.

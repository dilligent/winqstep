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
  "default_windows_workspace": "outputs",
  "wsl_shell_prelude": "conda deactivate >/dev/null 2>&1 || true",
  "ui_language": "",
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

The CLI emits JSON for scripting and diagnostics. In the GUI, the same probe
result is parsed into a readable `Environment` tab summary while the raw JSON is
kept in `Job Log`.

Round 11 adds a config management command used by the GUI:

```powershell
python .\scripts\manage_config.py --config .\examples\winqstep.config.json --require-execution
```

It validates the JSON shape, rejects unknown keys, checks that CP2K execution
fields are present when `--require-execution` is used, and emits normalized JSON
with diagnostics. To rewrite a config with stable key order and UTF-8 text:

```powershell
python .\scripts\manage_config.py --config .\examples\winqstep.config.json --write --fields-json "{\"distro\":\"Ubuntu\",\"cp2k_command\":\"/home/teng/cp2k/exe/local/cp2k.ssmp\",\"mpirun_command\":\"\",\"cp2k_data_dir\":\"/home/teng/cp2k/data\",\"default_windows_workspace\":\"outputs\",\"wsl_shell_prelude\":\"conda deactivate >/dev/null 2>&1 || true\",\"ui_language\":\"\",\"timeout\":\"20\"}"
```

## Keys

- `distro`: WSL distro name, such as `Ubuntu`.
- `cp2k_command`: CP2K executable path or command name inside WSL. Use an
  absolute path when the command is only available after interactive shell
  initialization.
- `mpirun_command`: optional MPI launcher executable path or command name. Use
  an empty string when direct `cp2k.ssmp` execution is preferred.
- `cp2k_data_dir`: CP2K data directory inside WSL.
- `default_windows_workspace`: default Windows folder for future job outputs.
  A relative value such as `outputs` is resolved from the WinQStep folder by the
  GUI and command-line wrappers, which keeps unpacked release folders portable.
- `wsl_shell_prelude`: shell code to run before each WSL command. The sample
  uses `conda deactivate >/dev/null 2>&1 || true` so conda environments do not
  leak into CP2K probing or future job execution.
- `ui_language`: GUI language preference. Use `en-US`, `zh-CN`, or an empty
  string for Windows UI culture.
- `timeout`: subprocess timeout in seconds.

For execution, `cp2k_command` and `cp2k_data_dir` must be present. CP2K command,
MPI command, and CP2K data directory values are WSL-side values; Windows paths
such as `D:\...` are rejected for those fields.
`cp2k_command` and `mpirun_command` are currently treated as single shell
tokens. Do not include extra command-line arguments in these fields, for example
use `mpirun` rather than `mpirun --bind-to none`.

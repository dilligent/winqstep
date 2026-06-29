# Testing Matrix

WinQStep keeps local checks behind one entry point:

```powershell
python .\scripts\run_checks.py
```

The default profile is `fast`. It runs the Python unit suite and offline startup
diagnostics.

## Profiles

Use `--profile` to choose a verification slice. Repeat it to combine slices.

```powershell
python .\scripts\run_checks.py --profile fast
python .\scripts\run_checks.py --profile gui
python .\scripts\run_checks.py --profile release
python .\scripts\run_checks.py --profile rc
python .\scripts\run_checks.py --profile live
python .\scripts\run_checks.py --profile all
```

- `fast`: unit tests plus `check_startup.py --skip-live-probes`.
- `gui`: non-interactive WPF smoke tests, button smoke, lifecycle smoke, and
  Python stderr-separation smoke. These checks do not call WSL or CP2K.
- `release`: release file planning plus unpacked release install smoke.
- `rc`: release-candidate user-path walkthrough. It runs offline startup and
  config/template validation, prepares an `ENERGY_FORCE` workflow job, prepares
  an existing-input job, scans history, and checks the release file plan.
- `live`: startup diagnostics and GUI button smoke with WSL/CP2K probes enabled.
- `all`: expands to `fast`, `gui`, `release`, and `rc`. It does not include
  `live`.

Use `--list` to inspect the selected commands without running them:

```powershell
python .\scripts\run_checks.py --profile all --list
```

The command returns JSON and exits nonzero if any executed check fails.

## Routine Use

Before committing a normal implementation round:

```powershell
python .\scripts\run_checks.py --profile fast
```

After GUI changes:

```powershell
python .\scripts\run_checks.py --profile fast --profile gui
```

Before packaging or handing off a release candidate:

```powershell
python .\scripts\run_checks.py --profile all
```

To run only the release-candidate walkthrough:

```powershell
python .\scripts\release_candidate_walkthrough.py
```

When WSL2 and the configured CP2K installation are available:

```powershell
python .\scripts\run_checks.py --profile live
```

The live profile calls the configured distro, CP2K command, and CP2K data path.
It should stay explicit so offline development and release verification remain
deterministic.

For an explicit live CP2K walkthrough of the same `ENERGY_FORCE` path, run:

```powershell
python .\scripts\release_candidate_walkthrough.py --include-live --keep-workspace
```

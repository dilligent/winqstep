# CP2K Output Summary

WinQStep stores a compact CP2K output summary in job metadata under
`cp2k_output`. The parser is intentionally small and only reads stable text
markers from CP2K `.out` files:

- `The number of warnings for this run is : <n>`
- `PROGRAM ENDED AT ...`
- `PROGRAM STOPPED IN ...`

Example metadata:

```json
{
  "cp2k_output": {
    "path": "D:\\work\\winqstep\\outputs\\job\\water.out",
    "available": true,
    "status": "completed",
    "warning_count": 0,
    "program_ended": true,
    "ended_at": "2026-06-29 03:24:28.023",
    "stopped_in": "/mnt/d/Library/winqstep/outputs/job"
  }
}
```

If the output file is not present, such as after `--prepare-only`, the summary
uses:

```json
{
  "available": false,
  "status": "not_available",
  "warning_count": null,
  "program_ended": false
}
```

If an output file exists but CP2K did not print `PROGRAM ENDED AT`, WinQStep
marks the summary as `incomplete`. The process return code is still recorded
separately in metadata; the output summary is a diagnostic convenience, not a
replacement for the raw `.out` file.

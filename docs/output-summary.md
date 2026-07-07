# CP2K Output Summary

WinQStep stores a compact CP2K output summary in job metadata under
`cp2k_output`. The parser is intentionally small and only reads stable text
markers from CP2K `.out` files:

- `The number of warnings for this run is : <n>`
- `PROGRAM ENDED AT ...`
- `PROGRAM STOPPED IN ...`
- `ENERGY| Total FORCE_EVAL ... energy [hartree]`
- `FORCES| Atomic forces [hartree/bohr]` for `ENERGY_FORCE`
- the final `SCF WAVEFUNCTION OPTIMIZATION` table and convergence marker
- the final `CELL| ...` cell block
- the `CP2K` row in the timing table

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
    "stopped_in": "/mnt/d/Library/winqstep/outputs/job",
    "total_energy_hartree": -17.219350325303314,
    "walltime_seconds": 7.086,
    "scf": {
      "converged": true,
      "step_count": 11,
      "final_step": 11,
      "final_time_seconds": 0.3,
      "final_convergence": 0.00000021,
      "final_total_energy_hartree": -17.2193503253,
      "final_energy_change_hartree": -2.68e-12
    },
    "cell": {
      "unit": "angstrom",
      "volume_angstrom3": 1000.0,
      "a": [10.0, 0.0, 0.0],
      "b": [0.0, 10.0, 0.0],
      "c": [0.0, 0.0, 10.0],
      "lengths": {"a": 10.0, "b": 10.0, "c": 10.0},
      "angles_degrees": {"alpha": 90.0, "beta": 90.0, "gamma": 90.0},
      "orthorhombic": true,
      "periodicity": "XYZ"
    },
    "forces": {
      "unit": "hartree/bohr",
      "atoms": [
        {"atom": 1, "x": -1.36343519e-10, "y": -4.64397561e-12, "z": -0.0135588799, "norm": 0.0135588799}
      ],
      "sum": {"x": -1.371556e-10, "y": -5.18303421e-11, "z": 0.00148299452},
      "total_atomic_force": 0.00148299452
    }
  }
}
```

`total_energy_hartree`, `forces`, `walltime_seconds`, `scf`, and `cell` are
`null` when those sections are absent or cannot be parsed conservatively.

The GUI turns the same metadata into a structured `Results` text view. For an
`ENERGY_FORCE` job, it includes the job status, return code, CP2K status,
warning count, total energy, total atomic force, known artifact paths, and a
per-atom force table. When available, it also reports wall time, SCF
convergence/step counts/final convergence, and final cell periodicity, volume,
and lattice vectors. When file-generating print controls such as PDOS, cube, or
band-structure output produce recognized outputs, the result summary also lists
`files.generated` entries.
`Save Results` writes the text as `*.results.txt` next to the `.winqstep.json`
metadata file. If CP2K did not print a force block, the result summary reports
`forces=not_available`.

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

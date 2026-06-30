# Structure Import

WinQStep imports structure files into a small JSON shape that later stages can
combine with calculation settings. The importer records structure facts only; it
does not guess basis sets, potentials, charge, spin, or scientific settings.

## Dependency

The preferred reader is ASE:

```toml
dependencies = [
  "ase>=3.23",
]
```

On the current machine, ASE `3.29.0` is installed and reports
`LGPL-2.1-or-later`. WinQStep depends on ASE through the package manager and does
not vendor ASE source code.

The importer also includes minimal built-in readers for simple XYZ, POSCAR, and
CIF fixtures. These fallback readers keep tests deterministic and provide clear
errors when ASE is unavailable, but ASE remains the intended production reader.

## Usage

```powershell
python .\scripts\import_structure.py --input .\tests\fixtures\structures\water.xyz
```

The command emits JSON:

```json
{
  "source": {
    "path": "tests\\fixtures\\structures\\water.xyz",
    "format": "xyz",
    "reader": "ase"
  },
  "cell": {
    "a": [0.0, 0.0, 0.0],
    "b": [0.0, 0.0, 0.0],
    "c": [0.0, 0.0, 0.0],
    "pbc": [false, false, false],
    "periodic": "NONE"
  },
  "atoms": [
    {"element": "O", "xyz": [0.0, 0.0, 0.0]}
  ]
}
```

In the GUI, the same normalized importer output is parsed for display and shown
as a readable structure summary: source path, format, reader, atom count,
element counts, cell vectors, periodicity, and a cartesian coordinate table.
The workflow still uses the structure file path and the normalized importer
model internally.

## Supported Inputs

- `.xyz`
- `POSCAR` / `CONTCAR`
- `.cif`

The first importer intentionally avoids chemistry defaults. The QuickStep input
renderer still requires explicit `KIND` definitions because basis and potential
selection should be controlled by typed settings, not inferred silently.

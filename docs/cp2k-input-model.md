# CP2K Input Model

WinQStep should generate CP2K input from a typed model, not from free-form prose.
The model should be deliberately smaller than CP2K itself and should expand only
when each option has a clear mapping and test fixture.

## Source of Truth

The preferred source of CP2K keyword truth is the user's local CP2K version and
its matching input reference. Online manuals can guide development, but generated
input should be validated against the local environment whenever possible.

The current external reference is the CP2K trunk input manual:

```text
https://manual.cp2k.org/trunk/CP2K_INPUT.html
```

When the manual links to source code for details, prefer the local CP2K source
checkout that matches the user's installed CP2K version. WinQStep's generator is
limited to QuickStep; other CP2K methods are out of scope for this model.

## First Supported Area

The first generator should target:

- `&GLOBAL`
- `&FORCE_EVAL`
- `&DFT`
- `DFT/UKS`
- `DFT/WFN_RESTART_FILE_NAME`
- `DFT/&POISSON`
- `DFT/&POISSON/POISSON_SOLVER`
- `DFT/&KPOINTS`
- `DFT/&PRINT`
- `DFT/&PRINT/&MULLIKEN`
- `DFT/&PRINT/&LOWDIN`
- `DFT/&PRINT/&PDOS`
- `DFT/&PRINT/&E_DENSITY_CUBE`
- `DFT/&PRINT/&V_HARTREE_CUBE`
- `DFT/&XC`
- `DFT/&XC/&XC_FUNCTIONAL`
- `DFT/&XC/&VDW_POTENTIAL` with `PAIR_POTENTIAL` DFT-D3
- `&SUBSYS`
- `SUBSYS/&CELL`
- `&SCF`
- `SCF/SCF_GUESS`
- `SCF/&OT`
- `SCF/&DIAGONALIZATION`
- `SCF/&OUTER_SCF`
- `SCF/&MIXING`
- `SCF/&SMEAR`
- `FORCE_EVAL/&PRINT/&FORCES` for `ENERGY_FORCE`
- `&MOTION` for `GEO_OPT` and `CELL_OPT`
- `MOTION/&CONSTRAINT/&FIXED_ATOMS`

The first calculation types should be:

- `ENERGY`
- `ENERGY_FORCE`
- `GEO_OPT`
- `CELL_OPT`

The first chemistry defaults should be conservative:

- QuickStep DFT only;
- periodic systems first;
- PBE/GTH-style defaults;
- common MOLOPT basis selections;
- explicit, editable SCF presets.

## Implemented JSON Shape

The first renderer consumes a JSON model like `examples/quickstep_energy.json`
and renders CP2K input through `scripts/render_quickstep_input.py`.

Top-level fields:

- `project_name`
- `run_type`: `ENERGY`, `ENERGY_FORCE`, `GEO_OPT`, or `CELL_OPT`
- `print_level`: optional `GLOBAL/PRINT_LEVEL`, one of `SILENT`, `LOW`,
  `MEDIUM`, `HIGH`, or `DEBUG`; when omitted or blank, WinQStep leaves CP2K's
  default print level implicit
- `dft`: basis/potential file names, XC functional settings, optional DFT-D3
  dispersion, charge, multiplicity, optional UKS spin polarization, MGRID
  cutoff, optional POISSON solver controls, optional wavefunction restart
  controls, SCF controls, optional KPOINTS controls, and optional DFT print
  controls
- `motion`: optional `MOTION/&CONSTRAINT/&FIXED_ATOMS` controls for geometry
  and cell optimizations
- `geo_opt`: optimizer and max iteration settings for `GEO_OPT`
- `cell_opt`: optimizer, max iteration, type, pressure tolerance, and simple
  cell-shape constraints for `CELL_OPT`
- `structure`: periodic cell, atoms, and per-element `KIND` definitions

For `ENERGY_FORCE`, the renderer adds `FORCE_EVAL/&PRINT/&FORCES` so CP2K
prints an atom-by-atom force table that WinQStep can summarize.

The renderer writes the resolved periodicity to both `SUBSYS/&CELL/PERIODIC`
and `DFT/&POISSON/PERIODIC`. Supported values are `NONE`, `X`, `Y`, `Z`, `XY`,
`XZ`, `YZ`, and `XYZ`. Periodic cells must provide non-zero A, B, and C vectors.
`dft.poisson_solver` is optional; when it is blank or omitted, WinQStep does not
render `POISSON_SOLVER` and leaves CP2K's default implicit. Supported explicit
solver values are `PERIODIC`, `ANALYTIC`, `MT`, `MULTIPOLE`, `WAVELET`, and
`IMPLICIT`. WinQStep rejects explicit solver/periodicity combinations that the
current model does not deliberately support.

DFT print controls are opt-in. `dft.print_mulliken` renders
`DFT/&PRINT/&MULLIKEN ON`, `dft.print_lowdin` renders
`DFT/&PRINT/&LOWDIN ON`, `dft.print_pdos` renders
`DFT/&PRINT/&PDOS ON`, `dft.print_e_density_cube` renders
`DFT/&PRINT/&E_DENSITY_CUBE ON`, and `dft.print_v_hartree_cube` renders
`DFT/&PRINT/&V_HARTREE_CUBE ON`. All default to false so existing generated
inputs do not add population analysis output, PDOS files, or cube files unless
users request them. When these file-generating print controls are enabled, the
runner records generated `.pdos`, `.pdos_raw`, and `.cube` files in metadata
under `files.generated` so the GUI can list them with the other job artifacts.

Wavefunction restart is explicit and opt-in. `dft.wfn_restart_file_name` renders
`DFT/WFN_RESTART_FILE_NAME`, while `dft.scf_guess` renders `SCF/SCF_GUESS`.
Leaving both blank preserves the previous generated input. If a restart file is
named, WinQStep requires `SCF_GUESS RESTART` or `SCF_GUESS HISTORY_RESTART` so
the selected file is not silently ignored. `EXT_RESTART` remains out of scope
for now because it can restore broader simulation state than the current
structure-import workflow models.

Spin polarization is opt-in through `dft.uks_enabled`. When it is true, the
renderer writes `UKS T` in `&DFT`; when false, the keyword is omitted. Templates
with `multiplicity` greater than 1 must enable UKS so open-shell intent is not
silently reduced to a restricted calculation. UKS with multiplicity 1 remains
allowed for broken-symmetry singlet workflows.

XC settings are intentionally conservative. `dft.xc_functional` still defaults
to the CP2K `&XC_FUNCTIONAL PBE` shortcut. `dft.xc_pbe_parametrization` defaults
to `ORIG` and is omitted from generated input unless a non-default PBE
parametrization such as `PBESOL`, `REVPBE`, or `RPBE` is selected. Non-default
PBE parametrizations are rejected unless `dft.xc_functional` is `PBE`, because
they render as `PARAMETRIZATION` inside the PBE `&XC_FUNCTIONAL` section.

DFT-D3 dispersion is opt-in through `dft.dispersion_enabled`. When enabled, the
renderer writes `DFT/&XC/&VDW_POTENTIAL` with `POTENTIAL_TYPE PAIR_POTENTIAL`
and a nested `&PAIR_POTENTIAL` section containing `TYPE`, `PARAMETER_FILE_NAME`,
and `REFERENCE_FUNCTIONAL`. Supported D3 types are `DFTD3` and `DFTD3(BJ)`.
The default parameter file is `dftd3.dat`; preflight can warn when the CP2K data
inspection cache does not list that file.

SCF advanced controls are opt-in. `dft.scf_method` defaults to `DEFAULT`, which
keeps the previous minimal `EPS_SCF`/`MAX_SCF` output. `OT` renders `SCF/&OT`.
`DIAGONALIZATION` renders `SCF/&DIAGONALIZATION` and can also render
`ADDED_MOS`, `SCF/&MIXING`, and `SCF/&SMEAR`. For the local CP2K 2025.2
baseline, smearing uses `TELEC [K]` for electronic temperature. Mixing and
smearing are rejected unless diagonalization is selected; smearing also requires
added unoccupied orbitals through `ADDED_MOS`.

`SCF/&OUTER_SCF` is also opt-in. When `dft.outer_scf_enabled` is true, the
renderer writes `EPS_SCF` and `MAX_SCF` inside `&OUTER_SCF`; when false, the
section is omitted. The outer threshold must be at least as tight as the inner
`dft.eps_scf`, matching the CP2K expectation that outer SCF convergence is not
looser than the inner SCF loop.

KPOINTS controls are opt-in. `dft.kpoints_scheme` defaults to `NONE`, so
existing templates do not render `DFT/&KPOINTS`. The supported schemes are
`GAMMA` and `MONKHORST-PACK`; Monkhorst-Pack templates also set
`dft.kpoints_grid` as three positive integers. The renderer can include
`FULL_GRID`, `SYMMETRY`, and a non-default `WAVEFUNCTIONS` value inside
`&KPOINTS`. KPOINTS are rejected for `PERIODIC NONE` cells.

CELL_OPT controls are opt-in through `run_type CELL_OPT`. The first supported
cell optimization path renders `MOTION/&CELL_OPT` with `TYPE DIRECT_CELL_OPT`,
`OPTIMIZER`, `MAX_ITER`, `PRESSURE_TOLERANCE [bar]`, and optional
`KEEP_ANGLES` or `KEEP_SYMMETRY`. CELL_OPT also renders
`FORCE_EVAL/STRESS_TENSOR ANALYTICAL`, which CP2K requires for cell
optimization. CELL_OPT is rejected for `PERIODIC NONE` cells. MD-driven cell
optimization and space-group constraints remain out of scope for now.

Fixed-atom constraints are opt-in through `motion.fixed_atoms`, a list of
1-based atom indices. When set for `GEO_OPT` or `CELL_OPT`, the renderer writes
`MOTION/&CONSTRAINT/&FIXED_ATOMS` with `LIST` and `COMPONENTS_TO_FIX`.
`motion.fixed_atom_components` defaults to `XYZ` and supports `X`, `Y`, `Z`,
`XY`, `XZ`, `YZ`, and `XYZ`. The current model does not support coordinate
restraints, collective variables, or molecule-name based fixed-atom selection.

Unsupported `run_type` values such as `MD` are rejected for now even if CP2K
supports them. That is intentional: the first generator covers only a small
QuickStep subset with tests.

## Rendering Rules

- Every GUI field maps to one typed model field.
- Every typed model field maps to one known CP2K section or keyword.
- Optional `print_level` renders only as `GLOBAL/PRINT_LEVEL` when explicitly
  set.
- CELL and POISSON periodicity must stay synchronized.
- `POISSON_SOLVER` renders only when explicitly selected.
- `WFN_RESTART_FILE_NAME` and `SCF_GUESS` render only when explicitly selected.
- PBE parametrization renders only when explicitly non-default.
- DFT-D3 renders only when explicitly enabled.
- UKS is generated only when explicitly enabled.
- OUTER_SCF is generated only when explicitly enabled.
- Mixing and smearing are only generated with the diagonalization SCF path.
- KPOINTS are only generated for explicitly selected periodic calculations.
- `DFT/&PRINT` renders only when at least one DFT print subsection is enabled.
- `MOTION/&CONSTRAINT/&FIXED_ATOMS` renders only when fixed atom indices are
  explicitly set, and only for optimization run types.
- The renderer should produce stable output order for readable diffs.
- Unknown advanced text blocks must be marked as user-provided overrides.
- Generated files should include a short header saying they were generated by
  WinQStep and can be edited manually.

## Validation Rules

The generator should validate before writing:

- required structure data exists;
- periodic cell data exists when periodic mode is selected;
- explicit POISSON solver choices are compatible with the resolved periodicity;
- explicit wavefunction restart files use restart-compatible `SCF_GUESS`
  values;
- fixed atom constraints use positive, unique 1-based atom indices that are
  within the resolved structure atom count;
- basis and potential file names are available in `CP2K_DATA_DIR`;
- calculation type is supported by the current generator;
- required CP2K commands were detected.

Validation failures should be specific enough to guide the user to the missing
environment setting or input choice.

# Structure-to-QuickStep Workflow

WinQStep can combine an imported structure file with a calculation template,
render a QuickStep input, and run CP2K through the same WSL runner used by the
lower-level job command.

## Command

```powershell
python .\scripts\run_workflow.py --config .\examples\winqstep.config.example.json --template .\examples\templates\energy_pbe.example.json --structure .\tests\fixtures\structures\water.xyz --job-dir .\outputs\workflow-energy
```

Use `--prepare-only` to generate the input and metadata without starting CP2K:

```powershell
python .\scripts\run_workflow.py --config .\examples\winqstep.config.example.json --template .\examples\templates\energy_pbe.example.json --structure .\tests\fixtures\structures\water.xyz --job-dir .\outputs\workflow-preview --prepare-only
```

Use preflight validation to check the same workflow inputs before rendering or
running:

```powershell
python .\scripts\validate_job_inputs.py --mode workflow --config .\examples\winqstep.config.example.json --template .\examples\templates\energy_pbe.example.json --structure .\tests\fixtures\structures\water.xyz
```

The preflight command reports missing KIND coverage as errors. If a CP2K data
inspection cache is available, it also warns about template basis/potential data
files or KIND labels that are not present in the cache.

## Template Shape

Workflow templates intentionally stay smaller than full QuickStep JSON. They
define calculation settings, optional structure transforms, and a KIND library:

```json
{
  "project_name": "workflow_energy",
  "run_type": "ENERGY",
  "dft": {
    "basis_set_file_name": "BASIS_MOLOPT",
    "potential_file_name": "GTH_POTENTIALS",
    "xc_functional": "PBE",
    "xc_pbe_parametrization": "ORIG",
    "dispersion_enabled": false
  },
  "structure_transform": {
    "fallback_cell": {
      "periodic": "XYZ",
      "a": [10.0, 0.0, 0.0],
      "b": [0.0, 10.0, 0.0],
      "c": [0.0, 0.0, 10.0]
    },
    "center_atoms": true
  },
  "kinds": [
    {"element": "H", "basis_set": "DZVP-MOLOPT-SR-GTH", "potential": "GTH-PBE-q1"},
    {"element": "O", "basis_set": "DZVP-MOLOPT-SR-GTH", "potential": "GTH-PBE-q6"}
  ]
}
```

The fallback cell is used when the structure file has no usable cell, which is
common for XYZ. `center_atoms` translates the imported coordinates into the
middle of the fallback cell only when that fallback cell is actually used.
Periodic POSCAR and CIF imports keep their imported cell and coordinates.

The resolved periodicity is rendered consistently in both `SUBSYS/&CELL` and
`DFT/&POISSON`. Supported periodicity labels are `NONE`, `X`, `Y`, `Z`, `XY`,
`XZ`, `YZ`, and `XYZ`; periodic cells must have non-zero A, B, and C vectors.
Templates can also set `dft.poisson_solver` to render an explicit
`DFT/&POISSON/POISSON_SOLVER` keyword. Leaving the field blank keeps the
historical generated input and leaves CP2K's default implicit. Explicit solver
choices are validated before rendering so unsupported solver/periodicity
combinations do not reach CP2K.

Templates can enable spin-polarized QuickStep DFT with `uks_enabled`, which
renders `UKS T` inside `&DFT`. Multiplicity values greater than 1 require UKS,
so open-shell templates fail before CP2K is started instead of silently running
as restricted calculations.

Templates can opt into wavefunction restart with
`dft.wfn_restart_file_name` and `dft.scf_guess`. The file name renders as
`DFT/WFN_RESTART_FILE_NAME`, and the guess renders as `SCF/SCF_GUESS`.
Leaving both blank keeps generated inputs unchanged. If a restart file is set,
the template must use `RESTART` or `HISTORY_RESTART` as the SCF guess.

Templates can adjust the conservative XC layer with `xc_functional` and, for
PBE, `xc_pbe_parametrization`. `ORIG` keeps the historical `&XC_FUNCTIONAL PBE`
shortcut unchanged; values such as `PBESOL` render a nested `PARAMETRIZATION`
keyword. `dispersion_enabled` turns on DFT-D3 through
`DFT/&XC/&VDW_POTENTIAL/&PAIR_POTENTIAL` with editable type, parameter file,
and reference functional fields.

Templates can optionally enable `DFT/&KPOINTS` for periodic structures.
`kpoints_scheme` defaults to `NONE`; supported rendered schemes are `GAMMA` and
`MONKHORST-PACK`, with `kpoints_grid` providing the three Monkhorst-Pack
subdivision counts. Optional `kpoints_full_grid`, `kpoints_symmetry`, and
`kpoints_wavefunctions` fields map to the corresponding CP2K KPOINTS keywords.
KPOINTS are rejected for `PERIODIC NONE` inputs.

Templates can optionally enable `DFT/&PRINT` output through `print_mulliken`,
`print_lowdin`, `print_pdos`, `print_e_density_cube`,
`print_v_hartree_cube`, and `print_band_structure`. These fields render
`&MULLIKEN ON`, `&LOWDIN ON`, `&PDOS ON`, `&E_DENSITY_CUBE ON`,
`&V_HARTREE_CUBE ON`, and `&BAND_STRUCTURE ON` under `DFT/&PRINT`; leaving all
false omits the section entirely. Band-structure output includes one explicit
`&KPOINT_SET`, so users should edit `band_special_points` for the intended
high-symmetry path. After a run, generated `.pdos`, `.pdos_raw`, `.cube`,
`.bs`, `.band`, and `.bands` files are recorded in job metadata under
`files.generated` and shown in the GUI artifact summary.

Templates can also optionally enable `DFT/&SCF/&OUTER_SCF` with
`outer_scf_enabled`, `outer_scf_eps_scf`, and `outer_scf_max_scf`. The section
is omitted unless enabled, and the outer convergence threshold must be no looser
than the inner `eps_scf`.

Templates can optionally define fixed atom constraints for optimization runs:

```json
"motion": {
  "fixed_atoms": [1, 3],
  "fixed_atom_components": "XYZ"
}
```

The list uses CP2K's 1-based atom indices after structure import and optional
fallback-cell centering. The renderer writes
`MOTION/&CONSTRAINT/&FIXED_ATOMS` with `LIST` and `COMPONENTS_TO_FIX`.
Constraints are rejected for non-optimization run types and for indices outside
the resolved structure atom count.

The workflow selects only KIND entries needed by the imported elements. Missing
KIND definitions fail before CP2K is started. The GUI runs the same preflight
check before `Preview` and `Run` so those errors appear in the `Template` and
`Structure` panes.

## Template Editing

Use `scripts/manage_template.py` to validate or rewrite template files with
stable UTF-8 JSON:

```powershell
python .\scripts\manage_template.py --template .\examples\templates\energy_pbe.example.json
```

The GUI `Template` tab uses the same command. It exposes project name, run type,
DFT settings, XC/PBE/DFT-D3 controls, UKS, POISSON solver controls, SCF solver
and OUTER_SCF controls, wavefunction restart controls, KPOINTS controls, DFT
PRINT controls, fixed atom constraints, GEO_OPT settings, CELL_OPT settings,
fallback cell/periodicity settings, centering, and KIND basis/potential
entries.
Supported QuickStep run types are `ENERGY`,
`ENERGY_FORCE`, `GEO_OPT`, and `CELL_OPT`. Workflow preview and run actions
save and validate the current template before rendering input.

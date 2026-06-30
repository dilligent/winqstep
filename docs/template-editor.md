# QuickStep Template Editor

Round 12 adds a small editor layer for WinQStep workflow templates. The JSON
template format remains the source of truth, but common QuickStep settings can
now be loaded, validated, and saved through a CLI and the GUI.

## CLI

```powershell
python .\scripts\manage_template.py --template .\examples\templates\energy_pbe.json
```

The command emits normalized template JSON, editable `kinds_text`, and
validation diagnostics. To write edited fields back to the template:

```powershell
python .\scripts\manage_template.py --template .\examples\templates\energy_pbe.json --write --fields-json "{\"project_name\":\"workflow_energy\",\"run_type\":\"ENERGY\",\"cutoff\":\"400\",\"max_scf\":\"50\",\"kinds_text\":\"H DZVP-MOLOPT-SR-GTH GTH-PBE-q1`nO DZVP-MOLOPT-SR-GTH GTH-PBE-q6\"}"
```

Editable fields include:

- `project_name`
- `run_type`: `ENERGY`, `ENERGY_FORCE`, `GEO_OPT`, or `CELL_OPT`
- `print_level`: optional `GLOBAL/PRINT_LEVEL`; supported values are
  `SILENT`, `LOW`, `MEDIUM`, `HIGH`, and `DEBUG`
- DFT fields: basis file, potential file, XC functional, optional PBE
  parametrization, optional DFT-D3 dispersion, charge, multiplicity, UKS spin
  polarization, cutoff, relative cutoff, EPS_SCF, MAX_SCF, SCF method,
  optional OUTER_SCF settings, ADDED_MOS, OT settings, diagonalization
  settings, mixing settings, and electronic-temperature smearing settings,
  plus KPOINTS scheme/grid,
  full-grid, symmetry, and wavefunction controls
- GEO_OPT fields: optimizer and max iterations
- CELL_OPT fields: optimizer, max iterations, optimization type, pressure
  tolerance, keep-angles, and keep-symmetry
- Structure transform fields: fallback periodicity, fallback cell A/B/C
  vectors, and whether fallback-cell structures should be centered
- `kinds_text`: one KIND per line as `element basis_set potential`

The writer saves UTF-8 JSON with stable key order.

## GUI

The PowerShell WPF prototype has a `Template` tab plus `Load Template` and
`Save Template` buttons. The tab exposes conservative fields already supported
by the renderer and workflow layer. Related controls are grouped by their CP2K
input-section path, so `&GLOBAL`, `&FORCE_EVAL / &DFT`,
`&FORCE_EVAL / &DFT / &XC`,
`&FORCE_EVAL / &DFT / &SCF`, nested blocks such as
`&FORCE_EVAL / &DFT / &SCF / &OUTER_SCF`,
`&FORCE_EVAL / &DFT / &SCF / &MIXING`,
`&FORCE_EVAL / &DFT / &SCF / &SMEAR`,
`&FORCE_EVAL / &DFT / &KPOINTS`, `&MOTION / &CELL_OPT`,
`&FORCE_EVAL / &SUBSYS / &CELL`, and
`&FORCE_EVAL / &SUBSYS / &KIND` are visible as sections instead of a flat list
of peer fields.

Single-line template fields are editable drop-down controls. Each field offers
common CP2K/WinQStep choices, such as `ENERGY`, `ENERGY_FORCE`, `GEO_OPT`, and
`CELL_OPT` for run type, `SILENT`, `LOW`, `MEDIUM`, `HIGH`, and `DEBUG` for
`GLOBAL/PRINT_LEVEL`, common basis and potential file names, common XC functional
shortcuts, typical SCF/MGRID numeric values, SCF methods such as `DEFAULT`,
`DIAGONALIZATION`, and `OT`, and `BFGS`, `LBFGS`, or `CG` for GEO_OPT and
CELL_OPT optimizers. Fallback cell fields expose the supported CP2K periodicity labels
and common cubic-cell vectors while still accepting direct typed values.
XC controls expose common `XC_FUNCTIONAL` shortcuts, PBE parametrizations
(`ORIG`, `PBESOL`, `REVPBE`, `RPBE`), and opt-in DFT-D3 pair-potential settings.
UKS is exposed as a checkbox in the `&FORCE_EVAL / &DFT` group because it maps
to the top-level `DFT/UKS` keyword.
OUTER_SCF fields expose common outer-loop thresholds and iteration counts while
remaining editable.
KPOINTS fields expose `NONE`, `GAMMA`, and `MONKHORST-PACK`, common
Monkhorst-Pack grids, `FULL_GRID`, `SYMMETRY`, and `WAVEFUNCTIONS` choices.
The controls remain editable, so values not listed in the drop-down can still
be typed directly and saved through the same template writer.
The candidate lists are intentionally conservative and are based on the CP2K
manual pages for `GLOBAL/RUN_TYPE`, `GLOBAL/PRINT_LEVEL`,
`FORCE_EVAL/DFT/BASIS_SET_FILE_NAME`,
`FORCE_EVAL/DFT/POTENTIAL_FILE_NAME`, `FORCE_EVAL/DFT/XC/XC_FUNCTIONAL`,
`FORCE_EVAL/DFT/XC/VDW_POTENTIAL/PAIR_POTENTIAL`, `FORCE_EVAL/DFT/UKS`,
`FORCE_EVAL/DFT/MGRID`, `FORCE_EVAL/DFT/SCF`, and
`MOTION/GEO_OPT`, plus
`FORCE_EVAL/SUBSYS/CELL`, `FORCE_EVAL/DFT/POISSON`,
`FORCE_EVAL/DFT/SCF/OT`, `FORCE_EVAL/DFT/SCF/DIAGONALIZATION`,
`FORCE_EVAL/DFT/SCF/OUTER_SCF`, `FORCE_EVAL/DFT/SCF/MIXING`,
`FORCE_EVAL/DFT/SCF/SMEAR`, and `FORCE_EVAL/DFT/KPOINTS` for periodicity,
SCF solver, and k-point controls, plus `MOTION/CELL_OPT` for direct cell
optimization controls.

KIND entries are shown in an editable `Element`, `Basis Set`, `Potential` table
instead of a raw text box. The GUI still serializes that table through
`kinds_text` internally, so the CLI and JSON template format stay unchanged.

For workflow mode, `Preview` and `Run` save and validate the current template
fields before preparing the CP2K input. Existing-input mode does not use the
template editor.

The template editor validates field shape, numeric ranges, run type, SCF method
choices, duplicate KIND entries, and required basis/potential names. It rejects
open-shell multiplicity values unless UKS is enabled. It rejects
mixing or smearing unless the SCF method is `DIAGONALIZATION`; smearing also
requires `ADDED_MOS` to add unoccupied orbitals. Enabled OUTER_SCF settings
must use a positive max iteration count and an outer `EPS_SCF` no looser than
the inner SCF threshold. KPOINTS options are rejected unless a KPOINTS scheme
is selected, and rendered workflow inputs reject KPOINTS for nonperiodic cells.
CELL_OPT inputs reject nonperiodic cells and currently support the
`DIRECT_CELL_OPT` path. When a CP2K data inspection cache is available, the GUI
preflight step also compares template data-file names and KIND basis/potential
labels against the cached CP2K data labels before `Preview` or `Run`.
When DFT-D3 is enabled, preflight also checks the configured D3 parameter file
name against the cached CP2K data file list.

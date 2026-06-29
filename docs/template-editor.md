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
- `run_type`: `ENERGY`, `ENERGY_FORCE`, or `GEO_OPT`
- DFT fields: basis file, potential file, XC functional, charge,
  multiplicity, cutoff, relative cutoff, EPS_SCF, MAX_SCF, SCF method,
  ADDED_MOS, OT settings, diagonalization settings, mixing settings, and
  electronic-temperature smearing settings
- GEO_OPT fields: optimizer and max iterations
- Structure transform fields: fallback periodicity, fallback cell A/B/C
  vectors, and whether fallback-cell structures should be centered
- `kinds_text`: one KIND per line as `element basis_set potential`

The writer saves UTF-8 JSON with stable key order.

## GUI

The PowerShell WPF prototype has a `Template` tab plus `Load Template` and
`Save Template` buttons. The tab exposes conservative fields already supported
by the renderer and workflow layer.

Single-line template fields are editable drop-down controls. Each field offers
common CP2K/WinQStep choices, such as `ENERGY`, `ENERGY_FORCE`, and `GEO_OPT`
for run type, common basis and potential file names, common XC functional
shortcuts, typical SCF/MGRID numeric values, SCF methods such as `DEFAULT`,
`DIAGONALIZATION`, and `OT`, and `BFGS`, `LBFGS`, or `CG` for GEO_OPT
optimizer. Fallback cell fields expose the supported CP2K periodicity labels
and common cubic-cell vectors while still accepting direct typed values.
The controls remain editable, so values not listed in the drop-down can still
be typed directly and saved through the same template writer.
The candidate lists are intentionally conservative and are based on the CP2K
manual pages for `GLOBAL/RUN_TYPE`, `DFT/BASIS_SET_FILE_NAME`,
`DFT/POTENTIAL_FILE_NAME`, `XC/XC_FUNCTIONAL`, `DFT/MGRID`, `DFT/SCF`, and
`MOTION/GEO_OPT`, plus `SUBSYS/CELL`, `DFT/POISSON`, `SCF/OT`,
`SCF/DIAGONALIZATION`, `SCF/MIXING`, and `SCF/SMEAR` for periodicity and SCF
solver controls.

KIND entries are shown in an editable `Element`, `Basis Set`, `Potential` table
instead of a raw text box. The GUI still serializes that table through
`kinds_text` internally, so the CLI and JSON template format stay unchanged.

For workflow mode, `Preview` and `Run` save and validate the current template
fields before preparing the CP2K input. Existing-input mode does not use the
template editor.

The template editor validates field shape, numeric ranges, run type, SCF method
choices, duplicate KIND entries, and required basis/potential names. It rejects
mixing or smearing unless the SCF method is `DIAGONALIZATION`; smearing also
requires `ADDED_MOS` to add unoccupied orbitals. When a CP2K data inspection
cache is available, the GUI preflight step also compares template data-file
names and KIND basis/potential labels against the cached CP2K data labels before
`Preview` or `Run`.

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
- `run_type`: `ENERGY` or `GEO_OPT`
- DFT fields: basis file, potential file, XC functional, charge,
  multiplicity, cutoff, relative cutoff, EPS_SCF, and MAX_SCF
- GEO_OPT fields: optimizer and max iterations
- `kinds_text`: one KIND per line as `element basis_set potential`

The writer saves UTF-8 JSON with stable key order.

## GUI

The PowerShell WPF prototype has a `Template` tab plus `Load Template` and
`Save Template` buttons. The tab exposes conservative fields already supported
by the renderer and workflow layer.

For workflow mode, `Preview` and `Run` save and validate the current template
fields before preparing the CP2K input. Existing-input mode does not use the
template editor.

The template editor does not inspect CP2K data files yet. It validates field
shape, numeric ranges, run type, duplicate KIND entries, and required
basis/potential names.

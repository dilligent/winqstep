# Structure-to-QuickStep Workflow

WinQStep can combine an imported structure file with a calculation template,
render a QuickStep input, and run CP2K through the same WSL runner used by the
lower-level job command.

## Command

```powershell
python .\scripts\run_workflow.py --config .\examples\winqstep.config.json --template .\examples\templates\energy_pbe.json --structure .\tests\fixtures\structures\water.xyz --job-dir .\outputs\workflow-energy
```

Use `--prepare-only` to generate the input and metadata without starting CP2K:

```powershell
python .\scripts\run_workflow.py --config .\examples\winqstep.config.json --template .\examples\templates\energy_pbe.json --structure .\tests\fixtures\structures\water.xyz --job-dir .\outputs\workflow-preview --prepare-only
```

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
    "xc_functional": "PBE"
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
middle of the selected cell.

The workflow selects only KIND entries needed by the imported elements. Missing
KIND definitions fail before CP2K is started.

## Template Editing

Use `scripts/manage_template.py` to validate or rewrite template files with
stable UTF-8 JSON:

```powershell
python .\scripts\manage_template.py --template .\examples\templates\energy_pbe.json
```

The GUI `Template` tab uses the same command. It exposes project name, run type,
DFT settings, GEO_OPT settings, and KIND basis/potential entries. Workflow
preview and run actions save and validate the current template before rendering
input.

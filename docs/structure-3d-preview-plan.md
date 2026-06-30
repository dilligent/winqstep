# Structure 3D Preview Plan

WinQStep can add a 3D preview for imported structures without changing the
calculation workflow. The existing importer already returns the required
normalized data: element symbols, cartesian coordinates, cell vectors, PBC
flags, source metadata, and reader metadata. The preview should be a display
layer only; Preview and Run should continue to use the selected structure file
path and the existing normalized importer model.

## Recommendation

Start with a native WPF `Viewport3D` preview instead of embedding a browser or
adding a full molecular viewer dependency.

Reasons:

- It fits the current PowerShell/WPF GUI without adding WebView2, JavaScript, or
  extra offline packaging constraints.
- It is enough for the first useful target: atoms, element colors, cell frame,
  rotation, zoom, pan, and reset.
- It keeps the feature testable with the current Windows smoke-test approach.
- It avoids turning WinQStep into a general-purpose structure viewer before the
  QuickStep workflow is mature.

WebView2 plus Three.js remains a possible future path if native WPF rendering
becomes too limiting for large systems or richer interaction.

## Boundaries

The first preview should not affect generated CP2K input, template fields,
fallback-cell behavior, or run validation. It should not infer bonds or
chemistry settings for calculations.

The first preview should not try to implement:

- advanced atom selection and editing;
- bond-length or angle measurement;
- supercell expansion;
- density, orbital, trajectory, or force-vector rendering;
- professional viewer features from tools such as VESTA, VMD, OVITO, or ASE GUI.

## Proposed Rounds

### Round A: Preview Data Model

Status: implemented.

Goal: build a small view model from normalized structure JSON that is stable,
testable, and independent of WPF.

Tasks:

- Add a Python helper that accepts normalized structure data and returns a
  preview model with atoms, element colors, approximate display radii, cell
  frame edges, model center, bounding radius, and warnings.
- Keep the model compact and deterministic so it can be used by CLI tests and
  GUI smoke tests.
- Cap or warn on very large atom counts before GUI rendering.
- Add tests for `water.xyz`, `POSCAR`, and `nacl.cif`.

Acceptance:

- Preview model contains one entry per displayed atom with element, xyz, color,
  and radius.
- Periodic structures include 12 cell-frame edges.
- Nonperiodic XYZ structures still render atoms and report that no cell frame is
  available.
- Large structures can be represented without forcing expensive GUI geometry.

Implementation:

- `winqstep.structure_preview.build_structure_preview` returns a JSON-friendly
  preview model.
- The model includes displayed atoms, element colors, display radii, periodic
  cell edges, center, bounding radius, source metadata, and warnings.
- The helper intentionally does not infer bonds or mutate structure data.
- Tests cover nonperiodic `water.xyz`, periodic `POSCAR`, periodic `nacl.cif`,
  atom-count capping, and invalid display limits.

### Round B: Static WPF 3D Preview

Status: next.

Goal: render imported structures in the `Structure` tab while preserving the
existing readable text summary.

Tasks:

- Change the `Structure` tab layout to include a 3D preview region and the
  existing readable structure summary.
- Render atoms as low-detail spheres with element-colored materials.
- Render periodic cell edges as simple line or thin-cylinder geometry.
- Add a reset-view control.
- Update Import handling so successful imports populate both the text summary
  and the 3D view.
- Add Windows GUI smoke coverage that confirms the preview viewport receives
  atom and cell geometry for fixture structures.

Acceptance:

- Importing `water.xyz` shows atom geometry and keeps the readable text summary.
- Importing `POSCAR` shows atom geometry plus a cell frame.
- Import failures keep the existing error behavior and do not leave stale 3D
  geometry that could mislead the user.

### Round C: Interaction and Polish

Goal: make the preview useful for inspection rather than just a static picture.

Tasks:

- Add mouse drag rotation.
- Add mouse-wheel zoom.
- Add right-button or middle-button pan.
- Add toggles for cell frame and simple inferred bonds if bonds are implemented.
- Add a visible atom-count and periodicity summary near the preview.
- Protect large structures with simplified rendering or an explicit warning.

Acceptance:

- Users can rotate, zoom, pan, and reset the current structure without changing
  the calculation input.
- Interaction remains responsive for small and medium structures.
- Large structures fail gracefully or render in a simplified mode.

## Main Risks

- WPF 3D interaction in PowerShell is verbose, so the implementation should be
  kept small and isolated from the rest of `start_gui.ps1`.
- Rendering one high-detail mesh per atom will not scale. Use low-detail
  geometry, shared materials, and an atom-count threshold.
- Any inferred bonds can be scientifically misleading. Bonds should be optional
  and labeled as visual aids if added.
- GUI tests need to verify model and control state rather than relying on pixel
  screenshots.

## Open Decisions

- Whether the Structure tab should split into `Preview` and `Summary` subpanes
  or use a vertical layout with the 3D preview above the text summary.
- Whether element colors should use a small built-in palette only, or a fuller
  CPK-like color table.
- Whether bond inference belongs in Round C or should be deferred until users
  ask for it.
- What atom-count threshold should switch to simplified rendering.

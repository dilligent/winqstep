import unittest
from pathlib import Path

from winqstep.structure_preview import StructurePreviewError, build_structure_preview
from winqstep.structures import import_structure


ROOT = Path(__file__).resolve().parents[1]
STRUCTURES = ROOT / "tests" / "fixtures" / "structures"


class StructurePreviewTests(unittest.TestCase):
    def test_builds_nonperiodic_xyz_atom_preview_without_cell_frame(self) -> None:
        imported = import_structure(STRUCTURES / "water.xyz")

        preview = build_structure_preview(imported)

        self.assertEqual(preview["mode"], "structure_preview")
        self.assertEqual(preview["atom_count"], 3)
        self.assertEqual(preview["displayed_atom_count"], 3)
        self.assertEqual(preview["periodic"], "NONE")
        self.assertFalse(preview["cell"]["available"])
        self.assertEqual(preview["cell"]["edges"], [])
        self.assertIn("No periodic cell frame is available", "\n".join(preview["warnings"]))
        self.assertEqual(preview["atoms"][0]["element"], "O")
        self.assertEqual(preview["atoms"][0]["color"], "#FF0D0D")
        self.assertEqual(preview["atoms"][1]["element"], "H")
        self.assertEqual(preview["atoms"][1]["color"], "#FFFFFF")
        self.assertGreater(preview["bounding_radius"], 1.0)

    def test_builds_periodic_poscar_preview_with_twelve_cell_edges(self) -> None:
        imported = import_structure(STRUCTURES / "POSCAR")

        preview = build_structure_preview(imported)

        self.assertEqual(preview["periodic"], "XYZ")
        self.assertTrue(preview["cell"]["available"])
        self.assertEqual(preview["cell"]["vectors"]["a"], [5.43, 0.0, 0.0])
        self.assertEqual(len(preview["cell"]["edges"]), 12)
        self.assertEqual(preview["atoms"][0]["element"], "Si")
        self.assertEqual(preview["atoms"][0]["color"], "#F0C8A0")
        self.assertEqual(preview["center"], [2.715, 2.715, 2.715])
        self.assertGreater(preview["bounding_radius"], 4.7)
        self.assertEqual(preview["warnings"], [])

    def test_builds_cif_preview_with_element_styles(self) -> None:
        imported = import_structure(STRUCTURES / "nacl.cif")

        preview = build_structure_preview(imported)

        self.assertEqual(preview["atom_count"], 2)
        self.assertEqual(preview["atoms"][0]["element"], "Na")
        self.assertEqual(preview["atoms"][0]["color"], "#AB5CF2")
        self.assertEqual(preview["atoms"][1]["element"], "Cl")
        self.assertEqual(preview["atoms"][1]["color"], "#1FF01F")
        self.assertTrue(preview["cell"]["available"])
        self.assertEqual(len(preview["cell"]["edges"]), 12)

    def test_caps_large_structure_geometry_and_reports_warning(self) -> None:
        structure = {
            "source": {"path": "synthetic.xyz", "format": "xyz", "reader": "test"},
            "cell": {"a": [0, 0, 0], "b": [0, 0, 0], "c": [0, 0, 0], "periodic": "NONE"},
            "atoms": [
                {"element": "Xx", "xyz": [float(index), 0.0, 0.0]}
                for index in range(5)
            ],
        }

        preview = build_structure_preview(structure, max_atoms=2)

        self.assertEqual(preview["atom_count"], 5)
        self.assertEqual(preview["displayed_atom_count"], 2)
        self.assertEqual([atom["index"] for atom in preview["atoms"]], [1, 2])
        self.assertEqual(preview["atoms"][0]["element"], "Xx")
        self.assertEqual(preview["atoms"][0]["color"], "#B0B0B0")
        self.assertIn("Only the first 2 of 5 atoms", "\n".join(preview["warnings"]))

    def test_rejects_invalid_max_atom_count(self) -> None:
        with self.assertRaisesRegex(StructurePreviewError, "max_atoms"):
            build_structure_preview({"atoms": []}, max_atoms=0)


if __name__ == "__main__":
    unittest.main()

import json
import subprocess
import sys
import unittest
from pathlib import Path

from winqstep.structures import import_with_builtin_reader, import_structure, structure_to_dict


ROOT = Path(__file__).resolve().parents[1]
STRUCTURES = ROOT / "tests" / "fixtures" / "structures"


class StructureImportTests(unittest.TestCase):
    def test_imports_xyz_with_builtin_reader(self) -> None:
        imported = import_structure(STRUCTURES / "water.xyz")

        self.assertEqual(imported["source"]["format"], "xyz")
        self.assertEqual(imported["cell"]["periodic"], "NONE")
        self.assertEqual(imported["atoms"][0]["element"], "O")
        self.assertEqual(imported["atoms"][1]["xyz"], [0.0, 0.757, 0.586])

    def test_imports_poscar_with_direct_coordinates(self) -> None:
        imported = import_structure(STRUCTURES / "POSCAR")

        self.assertEqual(imported["source"]["format"], "poscar")
        self.assertEqual(imported["cell"]["periodic"], "XYZ")
        self.assertEqual(imported["atoms"][1]["element"], "Si")
        self.assertEqual(imported["atoms"][1]["xyz"], [1.3575, 1.3575, 1.3575])

    def test_imports_simple_cif_fractional_coordinates(self) -> None:
        imported = import_structure(STRUCTURES / "nacl.cif")

        self.assertEqual(imported["source"]["format"], "cif")
        self.assertEqual(imported["atoms"][0]["element"], "Na")
        self.assertEqual(imported["atoms"][1]["element"], "Cl")
        self.assertEqual(imported["atoms"][1]["xyz"], [2.82, 2.82, 2.82])

    def test_builtin_reader_fallback_shape(self) -> None:
        structure = import_with_builtin_reader(STRUCTURES / "water.xyz", "xyz")
        imported = structure_to_dict(structure, STRUCTURES / "water.xyz")

        self.assertEqual(imported["source"]["reader"], "builtin")
        self.assertEqual(imported["cell"]["periodic"], "NONE")
        self.assertEqual(len(imported["atoms"]), 3)

    def test_cli_outputs_json(self) -> None:
        completed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts" / "import_structure.py"),
                "--input",
                str(STRUCTURES / "water.xyz"),
                "--compact",
            ],
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
        imported = json.loads(completed.stdout.decode("utf-8"))
        self.assertEqual(imported["atoms"][2]["element"], "H")

    def test_cli_can_include_preview_model(self) -> None:
        completed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts" / "import_structure.py"),
                "--input",
                str(STRUCTURES / "POSCAR"),
                "--include-preview",
                "--compact",
            ],
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr.decode("utf-8", errors="replace"))
        payload = json.loads(completed.stdout.decode("utf-8"))
        self.assertEqual(payload["mode"], "structure_import")
        self.assertEqual(payload["structure"]["source"]["format"], "poscar")
        self.assertEqual(payload["preview"]["mode"], "structure_preview")
        self.assertEqual(payload["preview"]["displayed_atom_count"], 2)
        self.assertEqual(len(payload["preview"]["cell"]["edges"]), 12)


if __name__ == "__main__":
    unittest.main()

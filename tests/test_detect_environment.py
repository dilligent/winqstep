import unittest

from scripts.detect_environment import decode_output, first_line, parse_wsl_list


class DetectEnvironmentTests(unittest.TestCase):
    def test_parse_wsl_list_with_default_marker(self) -> None:
        output = "  NAME      STATE           VERSION\n* Ubuntu    Stopped         2\n"

        self.assertEqual(
            parse_wsl_list(output),
            [
                {
                    "name": "Ubuntu",
                    "state": "Stopped",
                    "version": "2",
                    "default": True,
                }
            ],
        )

    def test_parse_wsl_list_with_utf16_output(self) -> None:
        output = "  NAME      STATE           VERSION\r\n* Ubuntu    Running         2\r\n"
        decoded = decode_output(output.encode("utf-16-le"))

        self.assertEqual(parse_wsl_list(decoded)[0]["name"], "Ubuntu")
        self.assertTrue(parse_wsl_list(decoded)[0]["default"])

    def test_first_line_skips_empty_lines(self) -> None:
        self.assertEqual(first_line("\n\n/usr/bin/cp2k.psmp\n"), "/usr/bin/cp2k.psmp")


if __name__ == "__main__":
    unittest.main()

import json
import platform
import shutil
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class GuiPrototypeTests(unittest.TestCase):
    def test_run_button_is_wired_to_async_job_launcher(self) -> None:
        script_text = (ROOT / "scripts" / "start_gui.ps1").read_text(encoding="utf-8").replace("\r\n", "\n")

        self.assertIn("[System.Windows.Threading.DispatcherTimer]::new()", script_text)
        self.assertIn("Start-WinQStepPythonProcess", script_text)
        self.assertIn("Save-WinQStepProcessOutput", script_text)
        self.assertIn("Stop-WinQStepProcessTree", script_text)
        self.assertIn("JobStatusText", script_text)
        self.assertIn("ArtifactSummaryText", script_text)
        self.assertIn("ArtifactText", script_text)
        self.assertIn("ViewInputButton", script_text)
        self.assertIn("SetArtifactsFromMetadata", script_text)
        self.assertIn("SetArtifactsFromHistoryItem", script_text)
        self.assertIn("ViewArtifact", script_text)
        self.assertIn("$window.Add_Closing({", script_text)
        self.assertIn("Use Stop before closing WinQStep", script_text)
        self.assertIn("job_dir=$($State[\"JobDir\"])", script_text)
        self.assertIn("wrapper_stdout=$($State[\"WrapperStdoutPath\"])", script_text)
        self.assertIn("$LifecycleSmokeTest", script_text)
        self.assertIn('$controls["RunButton"].Add_Click({\n        & $StartAsyncJob', script_text)
        self.assertIn('$controls["CancelJobButton"].Add_Click({\n        & $CancelAsyncJob', script_text)
        self.assertIn('$controls["ViewOutputButton"].Add_Click({\n        & $InvokeGuiAction "Viewing output artifact"', script_text)

    @unittest.skipUnless(platform.system() == "Windows", "WPF prototype is Windows-only")
    def test_wpf_smoke_test_loads_window(self) -> None:
        powershell = shutil.which("powershell") or shutil.which("pwsh")
        if not powershell:
            self.skipTest("PowerShell is not available")

        completed = subprocess.run(
            [
                powershell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(ROOT / "scripts" / "start_gui.ps1"),
                "-SmokeTest",
            ],
            capture_output=True,
            check=False,
        )

        stderr = completed.stderr.decode("utf-8", errors="replace")
        stdout = completed.stdout.decode("utf-8-sig", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr)
        report = json.loads(stdout)
        self.assertTrue(report["wpf_available"])
        self.assertTrue(report["xaml_loaded"])
        self.assertEqual(report["title"], "WinQStep")
        self.assertTrue(report["action_button_panel_wraps"])
        self.assertTrue(report["cancel_button_loaded"])
        self.assertTrue(report["cancel_button_initially_disabled"])
        self.assertTrue(report["job_status_text_loaded"])
        self.assertEqual(report["job_status_text_initial"], "")
        self.assertTrue(report["artifact_summary_loaded"])
        self.assertTrue(report["artifact_text_loaded"])
        self.assertEqual(report["artifact_view_buttons_loaded"], 5)
        self.assertTrue(report["artifact_view_buttons_initially_disabled"])
        self.assertTrue(report["config_tab_loaded"])
        self.assertEqual(report["config_distro"], "Ubuntu")
        self.assertTrue(report["config_cp2k_command"].endswith("cp2k.ssmp"))
        self.assertEqual(report["config_data_dir"], "/home/teng/cp2k/data")
        self.assertTrue(report["config_workspace_encoding_ok"], report["config_workspace_path"])
        self.assertIn("Config valid", report["config_validation_text"])
        self.assertTrue(report["template_tab_loaded"])
        self.assertEqual(report["template_project_name"], "workflow_energy")
        self.assertEqual(report["template_run_type"], "ENERGY")
        self.assertEqual(report["template_cutoff"], "400")
        self.assertTrue(report["template_kinds_has_oxygen"])
        self.assertIn("Template valid", report["template_validation_text"])
        self.assertTrue(report["data_labels_grid_loaded"])
        self.assertTrue(report["history_grid_loaded"])
        self.assertEqual(report["console_output_encoding"].lower(), "utf-8")
        self.assertEqual(report["pythonioencoding"], "utf-8")
        self.assertEqual(report["encoding_probe_exit_code"], 0)
        self.assertTrue(report["encoding_probe_ok"], report["encoding_probe_text"])
        self.assertEqual(report["preview_exit_code"], 0)
        self.assertTrue(report["preview_input_exists"])
        self.assertEqual(report["preview_summary_status"], "not_available")
        self.assertEqual(report["existing_preview_exit_code"], 0)
        self.assertEqual(report["existing_preview_mode"], "existing_input")
        self.assertTrue(report["existing_preview_input_exists"])
        self.assertEqual(report["existing_preview_summary_status"], "not_available")
        self.assertTrue(report["existing_preview_path_encoding_ok"], report["existing_preview_input_path"])
        self.assertEqual(report["history_exit_code"], 0)
        self.assertGreaterEqual(report["history_job_count"], 1)
        self.assertEqual(report["history_first_mode"], "existing_input")
        self.assertEqual(report["history_first_warning_count"], 0)
        self.assertTrue(report["existing_mode_input_enabled"])
        self.assertFalse(report["existing_mode_import_enabled"])

    @unittest.skipUnless(platform.system() == "Windows", "WPF prototype is Windows-only")
    def test_lifecycle_smoke_can_stop_background_process(self) -> None:
        powershell = shutil.which("powershell") or shutil.which("pwsh")
        if not powershell:
            self.skipTest("PowerShell is not available")

        completed = subprocess.run(
            [
                powershell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(ROOT / "scripts" / "start_gui.ps1"),
                "-LifecycleSmokeTest",
            ],
            capture_output=True,
            check=False,
        )

        stderr = completed.stderr.decode("utf-8", errors="replace")
        stdout = completed.stdout.decode("utf-8-sig", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr)
        report = json.loads(stdout)
        self.assertTrue(report["process_started"])
        self.assertTrue(report["process_stopped"])
        self.assertTrue(report["stdout_exists"])
        self.assertTrue(report["stderr_exists"])


if __name__ == "__main__":
    unittest.main()

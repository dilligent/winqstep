import json
import platform
import re
import shutil
import subprocess
import unittest
from pathlib import Path

from winqstep.template import load_template


ROOT = Path(__file__).resolve().parents[1]


class GuiPrototypeTests(unittest.TestCase):
    @staticmethod
    def _example_config_language() -> str:
        payload = json.loads((ROOT / "examples" / "winqstep.config.example.json").read_text(encoding="utf-8"))
        return str(payload.get("ui_language") or "")

    @staticmethod
    def _example_template() -> dict[str, object]:
        return load_template(ROOT / "examples" / "templates" / "energy_pbe.example.json")

    @staticmethod
    def _template_vector_text(value: object) -> str:
        if value is None:
            return ""
        if isinstance(value, str):
            return value
        if isinstance(value, (list, tuple)) and len(value) == 3:
            parts = []
            for item in value:
                try:
                    parts.append(f"{float(item):g}")
                except (TypeError, ValueError):
                    parts.append(str(item))
            return " ".join(parts)
        return str(value)

    @classmethod
    def _example_template_expectations(cls) -> dict[str, object]:
        template = cls._example_template()
        dft = template.get("dft", {})
        motion = template.get("motion", {})
        cell_opt = template.get("cell_opt", {})
        structure_transform = template.get("structure_transform", {})
        fallback_cell = {}
        if isinstance(structure_transform, dict):
            fallback_cell = structure_transform.get("fallback_cell", {})

        if not isinstance(dft, dict):
            dft = {}
        if not isinstance(motion, dict):
            motion = {}
        if not isinstance(cell_opt, dict):
            cell_opt = {}
        if not isinstance(fallback_cell, dict):
            fallback_cell = {}

        return {
            "template_project_name": str(template.get("project_name", "")),
            "template_run_type": str(template.get("run_type", "")),
            "template_print_level": str(template.get("print_level", "")),
            "template_xc_functional": str(dft.get("xc_functional", "")),
            "template_xc_pbe_parametrization": str(dft.get("xc_pbe_parametrization", "")),
            "template_dispersion_enabled": bool(dft.get("dispersion_enabled", False)),
            "template_dispersion_type": str(dft.get("dispersion_type", "")),
            "template_dispersion_parameter_file": str(dft.get("dispersion_parameter_file_name", "")),
            "template_dispersion_reference_functional": str(dft.get("dispersion_reference_functional", "")),
            "template_cutoff": str(dft.get("cutoff", "")),
            "template_poisson_solver": str(dft.get("poisson_solver", "")),
            "template_wfn_restart_file_name": str(dft.get("wfn_restart_file_name", "")),
            "template_uks_enabled": bool(dft.get("uks_enabled", False)),
            "template_scf_method": str(dft.get("scf_method", "")),
            "template_scf_guess": str(dft.get("scf_guess", "")),
            "template_added_mos": str(dft.get("added_mos", "")),
            "template_outer_scf_enabled": bool(dft.get("outer_scf_enabled", False)),
            "template_outer_scf_eps_scf": str(dft.get("outer_scf_eps_scf", "")),
            "template_outer_scf_max_scf": str(dft.get("outer_scf_max_scf", "")),
            "template_mixing_enabled": bool(dft.get("mixing_enabled", False)),
            "template_smearing_enabled": bool(dft.get("smearing_enabled", False)),
            "template_cell_opt_type": str(cell_opt.get("type", "")),
            "template_cell_opt_optimizer": str(cell_opt.get("optimizer", "")),
            "template_cell_opt_max_iter": str(cell_opt.get("max_iter", "")),
            "template_cell_opt_pressure_tolerance": str(cell_opt.get("pressure_tolerance", "")),
            "template_cell_opt_keep_angles": bool(cell_opt.get("keep_angles", False)),
            "template_cell_opt_keep_symmetry": bool(cell_opt.get("keep_symmetry", False)),
            "template_kpoints_scheme": str(dft.get("kpoints_scheme", "")),
            "template_kpoints_grid": cls._template_vector_text(dft.get("kpoints_grid")),
            "template_kpoints_full_grid": bool(dft.get("kpoints_full_grid", False)),
            "template_kpoints_symmetry": bool(dft.get("kpoints_symmetry", False)),
            "template_kpoints_wavefunctions": str(dft.get("kpoints_wavefunctions", "")),
            "template_print_mulliken": bool(dft.get("print_mulliken", False)),
            "template_print_lowdin": bool(dft.get("print_lowdin", False)),
            "template_print_pdos": bool(dft.get("print_pdos", False)),
            "template_fixed_atoms": cls._template_vector_text(motion.get("fixed_atoms")),
            "template_fixed_atom_components": str(motion.get("fixed_atom_components", "XYZ")),
            "template_fallback_periodic": str(fallback_cell.get("periodic", "")),
            "template_fallback_cell_a": cls._template_vector_text(fallback_cell.get("a")),
            "template_center_atoms": bool(
                structure_transform.get("center_atoms", False)
                if isinstance(structure_transform, dict)
                else False
            ),
        }

    @staticmethod
    def _language_option_text(tag: str, ui_language: str) -> str:
        labels = {
            "en-US": {
                "": "System default",
                "en-US": "English (en-US)",
                "zh-CN": "Chinese (zh-CN)",
            },
            "zh-CN": {
                "": "系统默认",
                "en-US": "英语 (en-US)",
                "zh-CN": "中文 (zh-CN)",
            },
        }
        return labels[ui_language].get(tag, tag)

    def test_run_button_is_wired_to_async_job_launcher(self) -> None:
        script_text = (ROOT / "scripts" / "start_gui.ps1").read_text(encoding="utf-8").replace("\r\n", "\n")
        helper_text = (ROOT / "scripts" / "gui" / "WinQStep.GuiHost.ps1").read_text(encoding="utf-8").replace("\r\n", "\n")
        controls_text = (
            ROOT / "scripts" / "gui" / "WinQStep.GuiControls.ps1"
        ).read_text(encoding="utf-8").replace("\r\n", "\n")
        xaml_text = (ROOT / "scripts" / "gui" / "WinQStep.xaml").read_text(encoding="utf-8").replace("\r\n", "\n")
        english_text = (ROOT / "resources" / "i18n" / "en-US.json").read_text(encoding="utf-8")
        chinese_text = (ROOT / "resources" / "i18n" / "zh-CN.json").read_text(encoding="utf-8")

        self.assertIn('gui\\WinQStep.GuiHost.ps1', script_text)
        self.assertIn('gui\\WinQStep.GuiControls.ps1', script_text)
        self.assertIn('scripts\\gui\\WinQStep.xaml', script_text)
        self.assertNotIn('[xml]$xaml = @"', script_text)
        self.assertIn("Initialize-WinQStepLocalization", helper_text)
        self.assertIn("Read-WinQStepConfigLanguage", helper_text)
        self.assertIn("Get-WinQStepText", helper_text)
        self.assertIn("Set-WinQStepContent", helper_text)
        self.assertIn("scripts\\gui\\WinQStep.GuiControls.ps1", helper_text)
        self.assertIn("Get-WinQStepGuiControlNames", controls_text)
        self.assertIn("Set-WinQStepLocalizedControls", controls_text)
        self.assertIn("Get-WinQStepGuiControlNames", script_text)
        self.assertIn("Set-WinQStepLocalizedControls", script_text)
        self.assertIn("UiLanguageBox", xaml_text)
        self.assertIn('x:Name="ApplyLanguageButton"', xaml_text)
        self.assertIn('ScrollViewer x:Name="MainScrollViewer"', xaml_text)
        self.assertIn('VerticalScrollBarVisibility="Auto"', xaml_text)
        self.assertIn('HorizontalScrollBarVisibility="Disabled"', xaml_text)
        self.assertIn('TabControl x:Name="MainTabs"', xaml_text)
        self.assertIn('x:Name="Cp2kInputManualLink"', xaml_text)
        self.assertIn('NavigateUri="https://manual.cp2k.org/trunk/CP2K_INPUT.html"', xaml_text)
        self.assertIn('Cp2kInputManualLink', script_text)
        self.assertIn('Add_RequestNavigate', script_text)
        self.assertIn('x:Key="TemplateSectionGroupBoxStyle"', xaml_text)
        self.assertIn('x:Key="TemplateSectionLevel1GroupBoxStyle"', xaml_text)
        self.assertIn('x:Key="TemplateSectionLevel2GroupBoxStyle"', xaml_text)
        self.assertIn('x:Key="TemplateSectionLevel3GroupBoxStyle"', xaml_text)
        self.assertIn('x:Name="TemplateGlobalGroup" Header="&amp;GLOBAL"', xaml_text)
        self.assertIn('x:Name="TemplateDftGroup" Header="&amp;FORCE__EVAL / &amp;DFT"', xaml_text)
        self.assertIn('x:Name="TemplatePoissonGroup" Header="&amp;FORCE__EVAL / &amp;DFT / &amp;POISSON"', xaml_text)
        self.assertIn('x:Name="TemplateXcGroup" Header="&amp;FORCE__EVAL / &amp;DFT / &amp;XC"', xaml_text)
        self.assertIn('x:Name="TemplateScfGroup" Header="&amp;FORCE__EVAL / &amp;DFT / &amp;SCF"', xaml_text)
        self.assertIn('x:Name="TemplateOuterScfGroup" Header="&amp;FORCE__EVAL / &amp;DFT / &amp;SCF / &amp;OUTER__SCF"', xaml_text)
        self.assertIn('x:Name="TemplateMixingGroup" Header="&amp;FORCE__EVAL / &amp;DFT / &amp;SCF / &amp;MIXING"', xaml_text)
        self.assertIn('x:Name="TemplateSmearingGroup" Header="&amp;FORCE__EVAL / &amp;DFT / &amp;SCF / &amp;SMEAR"', xaml_text)
        self.assertIn('x:Name="TemplateFixedAtomsGroup" Header="&amp;MOTION / &amp;CONSTRAINT / &amp;FIXED__ATOMS"', xaml_text)
        self.assertIn('x:Name="TemplateGeoOptGroup" Header="&amp;MOTION / &amp;GEO__OPT"', xaml_text)
        self.assertIn('x:Name="TemplateCellOptGroup" Header="&amp;MOTION / &amp;CELL__OPT"', xaml_text)
        self.assertIn('x:Name="TemplateCellGroup" Header="&amp;FORCE__EVAL / &amp;SUBSYS / &amp;CELL"', xaml_text)
        self.assertIn('x:Name="TemplateKpointsGroup" Header="&amp;FORCE__EVAL / &amp;DFT / &amp;KPOINTS"', xaml_text)
        self.assertIn('x:Name="TemplateDftPrintGroup" Header="&amp;FORCE__EVAL / &amp;DFT / &amp;PRINT"', xaml_text)
        self.assertIn('x:Name="TemplateKindGroup" Header="&amp;FORCE__EVAL / &amp;SUBSYS / &amp;KIND"', xaml_text)
        self.assertNotIn('Header="&amp;FORCE_EVAL', xaml_text)
        expected_template_group_order = [
            "TemplateGlobalGroup",
            "TemplateDftGroup",
            "TemplatePoissonGroup",
            "TemplateXcGroup",
            "TemplateScfGroup",
            "TemplateOuterScfGroup",
            "TemplateMixingGroup",
            "TemplateSmearingGroup",
            "TemplateKpointsGroup",
            "TemplateDftPrintGroup",
            "TemplateCellGroup",
            "TemplateKindGroup",
            "TemplateFixedAtomsGroup",
            "TemplateGeoOptGroup",
            "TemplateCellOptGroup",
        ]
        template_group_positions = [xaml_text.index(f'x:Name="{name}"') for name in expected_template_group_order]
        self.assertEqual(template_group_positions, sorted(template_group_positions))
        self.assertIn('x:Name="StructurePreviewViewport"', xaml_text)
        self.assertIn('x:Name="StructurePreviewCamera"', xaml_text)
        self.assertIn('x:Name="StructurePreviewVisual"', xaml_text)
        self.assertIn('x:Name="StructureResetViewButton"', xaml_text)
        self.assertIn('x:Name="StructureSelectionText"', xaml_text)
        self.assertIn('x:Name="StructureApplyFixedAtomsButton"', xaml_text)
        self.assertIn('x:Name="StructureClearSelectionButton"', xaml_text)
        self.assertIn('x:Name="StructureLayoutGrid"', xaml_text)
        self.assertIn('x:Name="StructureText" Grid.Column="0" MinHeight="360"', xaml_text)
        self.assertIn('x:Name="StructurePreviewPanel" Grid.Column="2" MinHeight="360"', xaml_text)
        self.assertIn('x:Name="StructurePreviewFrame" Grid.Row="1"', xaml_text)
        self.assertLess(
            xaml_text.index('x:Name="StructureText" Grid.Column="0"'),
            xaml_text.index('x:Name="StructurePreviewPanel" Grid.Column="2"'),
        )
        self.assertEqual(
            re.findall(r'<TabItem x:Name="([^"]+)"', xaml_text),
            [
                "ConfigTab",
                "EnvironmentTab",
                "StructureTab",
                "TemplateTab",
                "InputPreviewTab",
                "JobLogTab",
                "ArtifactsTab",
                "HistoryTab",
            ],
        )
        self.assertIn('x:Name="TemplateRunTypeBox" Grid.Row="0" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="PrintLevelBox" Grid.Row="1" Grid.Column="1" IsEditable="True"', xaml_text)
        self.assertIn('<ComboBoxItem Content="SILENT"/>', xaml_text)
        self.assertIn('<ComboBoxItem Content="DEBUG"/>', xaml_text)
        self.assertIn('<ComboBoxItem Content="ENERGY"/>', xaml_text)
        self.assertIn('<ComboBoxItem Content="ENERGY_FORCE"/>', xaml_text)
        self.assertIn('<ComboBoxItem Content="GEO_OPT"/>', xaml_text)
        self.assertIn('<ComboBoxItem Content="CELL_OPT"/>', xaml_text)
        self.assertIn('x:Name="UksEnabledBox" Grid.Row="3" Grid.Column="0"', xaml_text)
        self.assertIn('x:Name="WfnRestartFileNameBox" Grid.Row="3" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('<ComboBoxItem Content="PROJECT-RESTART.wfn"/>', xaml_text)
        self.assertIn('x:Name="PoissonSolverBox" Grid.Row="0" Grid.Column="1" IsEditable="True"', xaml_text)
        self.assertIn('<ComboBoxItem Content="PERIODIC"/>', xaml_text)
        self.assertIn('<ComboBoxItem Content="WAVELET"/>', xaml_text)
        self.assertIn('<ComboBoxItem Content="IMPLICIT"/>', xaml_text)
        self.assertIn('x:Name="XcPbeParametrizationBox" Grid.Row="0" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('<ComboBoxItem Content="PBESOL"/>', xaml_text)
        self.assertIn('x:Name="DispersionEnabledBox"', xaml_text)
        self.assertIn('x:Name="DispersionTypeBox" Grid.Row="1" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('<ComboBoxItem Content="DFTD3(BJ)"/>', xaml_text)
        self.assertIn('x:Name="DispersionParameterFileBox" Grid.Row="2" Grid.Column="1" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="DispersionReferenceFunctionalBox" Grid.Row="2" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('<ComboBoxItem Content="BFGS"/>', xaml_text)
        self.assertIn('<ComboBoxItem Content="LBFGS"/>', xaml_text)
        self.assertIn('<ComboBoxItem Content="CG"/>', xaml_text)
        self.assertIn('x:Name="CellOptTypeBox" Grid.Row="0" Grid.Column="1" IsEditable="True"', xaml_text)
        self.assertIn('<ComboBoxItem Content="DIRECT_CELL_OPT"/>', xaml_text)
        self.assertIn('x:Name="CellOptOptimizerBox" Grid.Row="1" Grid.Column="1" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="CellOptMaxIterBox" Grid.Row="0" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="CellOptPressureToleranceBox" Grid.Row="1" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="CellOptKeepAnglesBox"', xaml_text)
        self.assertIn('x:Name="CellOptKeepSymmetryBox"', xaml_text)
        self.assertIn('x:Name="ScfMethodBox" Grid.Row="1" Grid.Column="1" IsEditable="True"', xaml_text)
        self.assertIn('<ComboBoxItem Content="DIAGONALIZATION"/>', xaml_text)
        self.assertIn('<ComboBoxItem Content="OT"/>', xaml_text)
        self.assertIn('x:Name="ScfGuessBox" Grid.Row="3" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('<ComboBoxItem Content="RESTART"/>', xaml_text)
        self.assertIn('<ComboBoxItem Content="HISTORY_RESTART"/>', xaml_text)
        self.assertIn('x:Name="AddedMosBox" Grid.Row="1" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="DiagonalizationAlgorithmBox" Grid.Row="2" Grid.Column="1" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="OtMinimizerBox" Grid.Row="2" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="OtPreconditionerBox" Grid.Row="3" Grid.Column="1" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="OuterScfEnabledBox"', xaml_text)
        self.assertIn('x:Name="OuterScfEpsScfBox" Grid.Row="0" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="OuterScfMaxScfBox" Grid.Row="1" Grid.Column="1" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="MixingEnabledBox"', xaml_text)
        self.assertIn('x:Name="SmearingEnabledBox"', xaml_text)
        self.assertIn('x:Name="KpointsSchemeBox" Grid.Row="0" Grid.Column="1" IsEditable="True"', xaml_text)
        self.assertIn('<ComboBoxItem Content="GAMMA"/>', xaml_text)
        self.assertIn('<ComboBoxItem Content="MONKHORST-PACK"/>', xaml_text)
        self.assertIn('x:Name="KpointsGridBox" Grid.Row="0" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="KpointsFullGridBox"', xaml_text)
        self.assertIn('x:Name="KpointsSymmetryBox"', xaml_text)
        self.assertIn('x:Name="KpointsWavefunctionsBox" Grid.Row="1" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('<ComboBoxItem Content="REAL"/>', xaml_text)
        self.assertIn('x:Name="PrintMullikenBox"', xaml_text)
        self.assertIn('x:Name="PrintLowdinBox"', xaml_text)
        self.assertIn('x:Name="FixedAtomsBox" Grid.Row="0" Grid.Column="1" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="FixedAtomComponentsBox" Grid.Row="0" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('<ComboBoxItem Content="YZ"/>', xaml_text)
        self.assertIn('x:Name="FallbackPeriodicBox" Grid.Row="0" Grid.Column="1" IsEditable="True"', xaml_text)
        self.assertIn('<ComboBoxItem Content="NONE"/>', xaml_text)
        self.assertIn('x:Name="FallbackCellABox" Grid.Row="0" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="FallbackCellBBox" Grid.Row="1" Grid.Column="1" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="FallbackCellCBox" Grid.Row="1" Grid.Column="3" IsEditable="True"', xaml_text)
        self.assertIn('x:Name="CenterAtomsBox"', xaml_text)
        self.assertIn('x:Name="KindEntriesGrid"', xaml_text)
        self.assertIn('x:Name="KindsText" Height="170" Visibility="Collapsed"', xaml_text)
        self.assertIn('x:Name="DataLabelsGrid" Height="130" Visibility="Collapsed"', xaml_text)
        self.assertIn('Height="130" Visibility="Collapsed"', xaml_text)
        self.assertIn("ui_language", script_text)
        self.assertIn('"button.preview": "Preview"', english_text)
        self.assertIn('"button.apply": "Apply"', english_text)
        self.assertIn('"label.print_level": "Print Level"', english_text)
        self.assertIn('"label.poisson_solver": "Poisson Solver"', english_text)
        self.assertIn('"label.wfn_restart_file_name": "WFN Restart File"', english_text)
        self.assertIn('"label.scf_guess": "SCF Guess"', english_text)
        self.assertIn('"label.fixed_atoms": "Fixed Atoms"', english_text)
        self.assertIn('"label.fixed_atom_components": "Components"', english_text)
        self.assertIn('"button.apply_fixed_atoms": "Apply Fixed Atoms"', english_text)
        self.assertIn('"button.clear_selection": "Clear Selection"', english_text)
        self.assertIn('"structure.fixed_atoms.none": "Selected fixed atoms: none"', english_text)
        self.assertIn('"structure.fixed_atoms.selected": "Selected fixed atoms: {0}"', english_text)
        self.assertIn('"label.uks_enabled": "UKS"', english_text)
        self.assertIn('"label.dispersion_enabled": "DFT-D3"', english_text)
        self.assertIn('"label.outer_scf_enabled": "Outer SCF"', english_text)
        self.assertIn('"label.print_mulliken": "Mulliken"', english_text)
        self.assertIn('"label.print_lowdin": "Lowdin"', english_text)
        self.assertIn('"label.print_pdos": "PDOS"', english_text)
        self.assertIn('x:Name="PrintPdosBox"', xaml_text)
        self.assertIn("generated_artifacts", script_text)
        self.assertIn('"button.preview": "预览"', chinese_text)
        self.assertIn("[System.Windows.Threading.DispatcherTimer]::new()", script_text)
        self.assertIn("Start-WinQStepPythonProcess", helper_text)
        self.assertIn("Save-WinQStepProcessOutput", helper_text)
        self.assertIn("Stop-WinQStepProcessTree", helper_text)
        self.assertIn("$startInfo.StandardOutputEncoding = $Script:Utf8NoBomEncoding", helper_text)
        self.assertIn("$startInfo.StandardErrorEncoding = $Script:Utf8NoBomEncoding", helper_text)
        self.assertIn("Get-Content -LiteralPath $Path -Encoding UTF8 -Tail", helper_text)
        self.assertIn("energy_hartree", helper_text)
        self.assertIn("total_atomic_force", helper_text)
        self.assertIn("JobStatusText", xaml_text)
        self.assertIn("ArtifactSummaryText", xaml_text)
        self.assertIn("ArtifactText", xaml_text)
        self.assertIn("ViewResultsButton", xaml_text)
        self.assertIn("SaveResultsButton", xaml_text)
        self.assertIn("ViewInputButton", xaml_text)
        self.assertIn("SetArtifactsFromMetadata", script_text)
        self.assertIn("SetArtifactsFromHistoryItem", script_text)
        self.assertIn("BuildResultSummaryFromMetadata", script_text)
        self.assertIn("ViewResultSummary", script_text)
        self.assertIn("SaveResultSummary", script_text)
        self.assertIn("ViewArtifact", script_text)
        self.assertIn('if ($Key -eq "input")', script_text)
        self.assertNotIn('$Key -in @("input", "output")', script_text)
        self.assertIn('"button.results": "Results"', english_text)
        self.assertIn('"button.results": "结果"', chinese_text)
        self.assertIn("scripts\\validate_job_inputs.py", script_text)
        self.assertIn("template_section_groups_loaded", script_text)
        self.assertIn("template_uks_enabled", script_text)
        self.assertIn("template_outer_scf_enabled", script_text)
        self.assertIn("language_apply_switched_to_zh", script_text)
        self.assertIn("scripts\\check_startup.py", helper_text)
        self.assertIn("scripts\\build_release.py", helper_text)
        self.assertIn("scripts\\smoke_release_install.py", helper_text)
        self.assertIn("scripts\\run_checks.py", helper_text)
        self.assertIn("scripts\\release_candidate_walkthrough.py", helper_text)
        self.assertIn("Invoke-WinQStepStartupDiagnostics", helper_text)
        self.assertIn("$Diagnostics", script_text)
        self.assertIn("$SkipLiveProbes", script_text)
        self.assertIn("$EnvironmentDisplaySmokeTest", script_text)
        self.assertIn("ValidateActiveInputs", script_text)
        self.assertIn("FormatEnvironmentProbeDisplay", script_text)
        self.assertIn("Environment detection", script_text)
        self.assertIn("detect_environment.py raw JSON", script_text)
        self.assertIn("FormatStructureImportDisplay", script_text)
        self.assertIn("SetStructurePreview", script_text)
        self.assertIn("ClearStructurePreview", script_text)
        self.assertIn("ApplyStructurePreviewInteraction", script_text)
        self.assertIn("StructurePreviewSmokeApplyInteraction", script_text)
        self.assertIn("StructurePreviewSmokeGetState", script_text)
        self.assertIn("StructurePreviewSmokeToggleAtomSelection", script_text)
        self.assertIn("StructurePreviewSmokeApplyFixedAtoms", script_text)
        self.assertIn("HitTestStructurePreviewAtom", script_text)
        self.assertIn("ToggleStructureAtomSelectionByModelKey", script_text)
        self.assertIn("ApplyStructureSelectionToFixedAtoms", script_text)
        self.assertIn("GetStructurePreviewFitDistance", script_text)
        self.assertIn("GetStructurePreviewViewportSize", script_text)
        self.assertIn("[Math]::Atan([Math]::Tan($halfHorizontalFovRadians) / $aspect)", script_text)
        self.assertIn("$safeRadius / [Math]::Sin($limitingHalfFovRadians)", script_text)
        self.assertIn('StructurePreviewViewport"].Add_MouseDown', script_text)
        self.assertIn('StructurePreviewViewport"].Add_MouseMove', script_text)
        self.assertIn('StructurePreviewViewport"].Add_MouseUp', script_text)
        self.assertIn('StructurePreviewViewport"].Add_MouseWheel', script_text)
        self.assertIn("NewSphereMesh", script_text)
        self.assertIn("NewCylinderMesh", script_text)
        self.assertIn("--include-preview", script_text)
        self.assertIn("Imported structure", script_text)
        self.assertIn("Atoms (cartesian coordinates, Angstrom)", script_text)
        self.assertIn("$SetKindEntriesFromText", script_text)
        self.assertIn("$SyncKindsTextFromGrid", script_text)
        self.assertIn("kinds_text = (& $SyncKindsTextFromGrid)", script_text)
        self.assertIn('$controls["TemplateValidationText"].Text = $text', script_text)
        self.assertIn('$controls["StructureText"].Text = $text', script_text)
        self.assertIn('$controls["PreviewText"].Text = $text', script_text)
        self.assertIn("$window.Add_Closing({", script_text)
        self.assertIn("message.close_blocked", script_text)
        self.assertIn("Use Stop before closing WinQStep", english_text)
        self.assertIn("job_dir=$($State[\"JobDir\"])", script_text)
        self.assertIn("wrapper_stdout=$($State[\"WrapperStdoutPath\"])", script_text)
        self.assertIn("$LifecycleSmokeTest", script_text)
        self.assertIn("$ButtonSmokeTest", script_text)
        self.assertIn("$EditedPreviewSmokeTest", script_text)
        self.assertIn("$AsyncRunSmokeTest", script_text)
        self.assertIn("$PythonInvokeSmokeTest", script_text)
        self.assertIn("Add_DispatcherUnhandledException", script_text)
        self.assertIn("$Script:SuppressGuiMessageBoxes", script_text)
        self.assertIn("SaveEditedInputPreview", script_text)
        self.assertIn("GetEditedInputPreview", script_text)
        self.assertIn("ConfirmEditedInputPreviewRun", script_text)
        self.assertIn("ValidateExistingInputPath", script_text)
        self.assertIn("edited_preview_used", script_text)
        self.assertIn("edited_preview_confirmation_requested", script_text)
        self.assertIn("[System.Windows.MessageBoxButton]::YesNo", script_text)
        self.assertIn("[System.Windows.MessageBoxResult]::No", script_text)
        self.assertIn("message.edited_preview_confirm", english_text)
        self.assertIn("No cancels this run", english_text)
        self.assertIn('"button.reset_view": "Reset View"', english_text)
        self.assertIn("structure.preview.loaded", english_text)
        self.assertIn("stderr_has_native_wrapper", script_text)
        self.assertIn("PreviewWorkflowButton", script_text)
        self.assertIn("PreviewExistingInputButton", script_text)
        self.assertIn("async_run_smoke", script_text)
        self.assertIn("run_completed", script_text)
        self.assertIn("HistoryGridDoubleClick", script_text)
        self.assertIn("[System.Windows.MessageBoxImage]::Error", script_text)
        self.assertIn("[System.Windows.MessageBoxImage]::Warning", script_text)
        self.assertNotIn('"OK", (Get-WinQStepText "message.error_caption")', script_text)
        self.assertNotIn('"OK", (Get-WinQStepText "message.warning_caption")', script_text)
        self.assertIn('$controls["RunButton"].Add_Click({\n        & $StartAsyncJob', script_text)
        self.assertIn('$controls["CancelJobButton"].Add_Click({\n        & $CancelAsyncJob', script_text)
        self.assertIn('$controls["ViewOutputButton"].Add_Click({\n        & $InvokeGuiAction -Status (Get-WinQStepText "status.viewing_output_artifact") -Action', script_text)
        self.assertIn('$controls["ViewResultsButton"].Add_Click({\n        & $InvokeGuiAction -Status (Get-WinQStepText "status.viewing_results_artifact") -Action', script_text)
        self.assertIn('$InvokeGuiAction -Status (Get-WinQStepText "status.detecting_environment") -Action', script_text)
        self.assertIn('$InvokeGuiAction -Status (Get-WinQStepText "status.importing_structure") -Action', script_text)
        self.assertIn('$InvokeGuiAction -Status (Get-WinQStepText "status.loading_job_history") -Action', script_text)

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
                "-Language",
                "en-US",
            ],
            capture_output=True,
            check=False,
        )

        stderr = completed.stderr.decode("utf-8", errors="replace")
        stdout = completed.stdout.decode("utf-8-sig", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr)
        report = json.loads(stdout)
        self.assertTrue(report["wpf_available"])
        self.assertEqual(report["ui_language"], "en-US")
        self.assertEqual(report["preview_button_text"], "Preview")
        self.assertEqual(report["config_tab_header"], "Config")
        self.assertEqual(report["status_text_initial"], "Ready")
        self.assertIn("WinQStep.cmd", report["checked_files"])
        self.assertIn("WinQStep.ps1", report["checked_files"])
        self.assertIn("scripts\\start_gui.ps1", report["checked_files"])
        self.assertIn("scripts\\build_release.py", report["checked_files"])
        self.assertIn("scripts\\smoke_release_install.py", report["checked_files"])
        self.assertIn("scripts\\run_checks.py", report["checked_files"])
        self.assertIn("scripts\\release_candidate_walkthrough.py", report["checked_files"])
        self.assertIn("scripts\\gui\\WinQStep.GuiHost.ps1", report["checked_files"])
        self.assertIn("scripts\\gui\\WinQStep.GuiControls.ps1", report["checked_files"])
        self.assertIn("scripts\\gui\\WinQStep.xaml", report["checked_files"])
        self.assertIn("scripts\\check_startup.py", report["checked_files"])
        self.assertIn("scripts\\validate_job_inputs.py", report["checked_files"])
        self.assertTrue(report["xaml_loaded"])
        self.assertEqual(report["title"], "WinQStep")
        self.assertTrue(report["main_scroll_viewer_loaded"])
        self.assertTrue(report["main_scroll_vertical_auto"])
        self.assertTrue(report["main_scroll_horizontal_disabled"])
        self.assertTrue(report["action_button_panel_wraps"])
        self.assertTrue(report["cancel_button_loaded"])
        self.assertTrue(report["cancel_button_initially_disabled"])
        self.assertTrue(report["job_status_text_loaded"])
        self.assertEqual(report["job_status_text_initial"], "")
        self.assertTrue(report["structure_preview_viewport_loaded"])
        self.assertTrue(report["structure_preview_visual_loaded"])
        self.assertTrue(report["structure_preview_camera_loaded"])
        self.assertEqual(report["structure_preview_status_initial"], "No structure preview loaded.")
        self.assertTrue(report["structure_reset_button_initially_disabled"])
        self.assertEqual(report["structure_selection_text_initial"], "Selected fixed atoms: none")
        self.assertTrue(report["structure_apply_fixed_atoms_initially_disabled"])
        self.assertTrue(report["structure_clear_selection_initially_disabled"])
        self.assertTrue(report["artifact_summary_loaded"])
        self.assertTrue(report["artifact_text_loaded"])
        self.assertEqual(report["artifact_result_buttons_loaded"], 2)
        self.assertTrue(report["artifact_result_buttons_initially_disabled"])
        self.assertEqual(report["artifact_view_buttons_loaded"], 5)
        self.assertTrue(report["artifact_view_buttons_initially_disabled"])
        self.assertTrue(report["config_tab_loaded"])
        self.assertEqual(report["config_distro"], "Ubuntu")
        self.assertTrue(report["config_cp2k_command"].endswith("cp2k.ssmp"))
        self.assertEqual(report["config_data_dir"], "/home/teng/cp2k/data")
        expected_config_language = self._example_config_language()
        self.assertEqual(report["config_ui_language"], expected_config_language)
        self.assertEqual(report["config_ui_language_text"], self._language_option_text(expected_config_language, "en-US"))
        self.assertTrue(report["config_workspace_resolution_ok"], report["config_workspace_resolved_path"])
        self.assertTrue(str(report["config_workspace_expected_path"]).endswith("outputs"))
        self.assertIn("Config valid", report["config_validation_text"])
        self.assertTrue(report["template_tab_loaded"])
        self.assertTrue(report["template_manual_link_loaded"])
        self.assertEqual(report["template_manual_link_uri"], "https://manual.cp2k.org/trunk/CP2K_INPUT.html")
        self.assertEqual(report["template_section_groups_loaded"], 15)
        self.assertEqual(
            report["template_section_group_headers"],
            [
                "&GLOBAL",
                "&FORCE_EVAL / &DFT",
                "&FORCE_EVAL / &DFT / &POISSON",
                "&FORCE_EVAL / &DFT / &XC",
                "&FORCE_EVAL / &DFT / &SCF",
                "&FORCE_EVAL / &DFT / &SCF / &OUTER_SCF",
                "&FORCE_EVAL / &DFT / &SCF / &MIXING",
                "&FORCE_EVAL / &DFT / &SCF / &SMEAR",
                "&FORCE_EVAL / &DFT / &KPOINTS",
                "&FORCE_EVAL / &DFT / &PRINT",
                "&FORCE_EVAL / &SUBSYS / &CELL",
                "&FORCE_EVAL / &SUBSYS / &KIND",
                "&MOTION / &CONSTRAINT / &FIXED_ATOMS",
                "&MOTION / &GEO_OPT",
                "&MOTION / &CELL_OPT",
            ],
        )
        self.assertEqual(report["template_section_group_left_margins"], [0, 18, 36, 36, 36, 54, 54, 54, 36, 36, 36, 36, 54, 18, 18])
        self.assertEqual(report["template_combo_fields_loaded"], 46)
        self.assertEqual(report["template_combo_fields_editable"], 46)
        self.assertEqual(report["template_run_type_options"], ["ENERGY", "ENERGY_FORCE", "GEO_OPT", "CELL_OPT"])
        self.assertEqual(report["template_print_level_options"], ["", "SILENT", "LOW", "MEDIUM", "HIGH", "DEBUG"])
        self.assertEqual(
            report["template_poisson_solver_options"],
            ["", "PERIODIC", "ANALYTIC", "MT", "MULTIPOLE", "WAVELET", "IMPLICIT"],
        )
        self.assertEqual(
            report["template_scf_guess_options"],
            ["", "ATOMIC", "RESTART", "HISTORY_RESTART", "CORE", "RANDOM", "SPARSE", "NONE", "MOPAC"],
        )
        self.assertEqual(report["template_fixed_atom_components_options"], ["XYZ", "X", "Y", "Z", "XY", "XZ", "YZ"])
        self.assertEqual(report["template_optimizer_options"], ["BFGS", "LBFGS", "CG"])
        self.assertEqual(report["template_cell_opt_type_options"], ["DIRECT_CELL_OPT"])
        expected_template = self._example_template_expectations()
        for key, expected_value in expected_template.items():
            self.assertEqual(report[key], expected_value)
        self.assertTrue(report["kind_entries_grid_loaded"])
        self.assertGreaterEqual(report["kind_entries_grid_rows"], 2)
        self.assertTrue(report["kinds_text_hidden"])
        self.assertTrue(report["template_kinds_has_oxygen"])
        self.assertIn("Template valid", report["template_validation_text"])
        self.assertTrue(report["data_labels_grid_loaded"])
        self.assertTrue(report["data_labels_grid_initially_collapsed"])
        self.assertTrue(report["history_grid_loaded"])
        self.assertEqual(
            report["tab_order"],
            [
                "ConfigTab",
                "EnvironmentTab",
                "StructureTab",
                "TemplateTab",
                "InputPreviewTab",
                "JobLogTab",
                "ArtifactsTab",
                "HistoryTab",
            ],
        )
        self.assertTrue(report["template_preview_tabs_adjacent"])
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
    def test_wpf_smoke_can_load_chinese_language(self) -> None:
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
                "-Language",
                "zh-CN",
            ],
            capture_output=True,
            check=False,
        )

        stderr = completed.stderr.decode("utf-8", errors="replace")
        stdout = completed.stdout.decode("utf-8-sig", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr)
        report = json.loads(stdout)
        self.assertEqual(report["ui_language"], "zh-CN")
        self.assertEqual(report["preview_button_text"], "预览")
        self.assertEqual(report["config_tab_header"], "配置")
        self.assertEqual(report["status_text_initial"], "就绪")
        expected_config_language = self._example_config_language()
        self.assertEqual(report["config_ui_language"], expected_config_language)
        self.assertEqual(report["config_ui_language_text"], self._language_option_text(expected_config_language, "zh-CN"))

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
        self.assertTrue(report["stdout_utf8_ok"])
        self.assertTrue(report["stderr_utf8_ok"])
        self.assertTrue(report["tail_utf8_ok"])

    @unittest.skipUnless(platform.system() == "Windows", "WPF prototype is Windows-only")
    def test_button_smoke_can_raise_common_click_handlers(self) -> None:
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
                "-ButtonSmokeTest",
                "-SkipLiveProbes",
            ],
            capture_output=True,
            check=False,
        )

        stderr = completed.stderr.decode("utf-8", errors="replace")
        stdout = completed.stdout.decode("utf-8-sig", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr)
        report = json.loads(stdout)
        self.assertTrue(report["button_live_probes_skipped"])
        self.assertTrue(report["button_message_boxes_suppressed"])
        expected_clicks = [
            "LoadConfigButton",
            "SaveConfigButton",
            "LoadTemplateButton",
            "SaveTemplateButton",
            "ImportButton",
            "StructureResetViewButton",
            "PreviewWorkflowButton",
            "PreviewExistingInputButton",
            "HistoryButton",
            "HistoryGridDoubleClick",
            "ViewResultsButton",
            "SaveResultsButton",
            "ViewInputButton",
            "ViewOutputButton",
            "ViewMetadataButton",
            "ViewStdoutButton",
            "ViewStderrButton",
            "ApplyLanguageButton",
            "ClearButton",
        ]
        for name in expected_clicks:
            self.assertIn(name, report["button_clicks"])
            self.assertTrue(report["button_clicks"][name]["ok"], report["button_clicks"][name]["error"])
        self.assertNotIn("DetectButton", report["button_clicks"])
        self.assertNotIn("InspectDataButton", report["button_clicks"])
        self.assertTrue(report["scratch_config_exists"])
        self.assertTrue(report["scratch_template_exists"])
        self.assertTrue(report["import_text_has_summary"])
        self.assertTrue(report["import_text_has_atom_count"])
        self.assertTrue(report["import_text_has_elements"])
        self.assertTrue(report["import_text_has_coordinate_table"])
        self.assertGreaterEqual(report["structure_preview_geometry_count"], 3)
        self.assertTrue(report["structure_preview_status_has_atoms"])
        self.assertTrue(report["structure_preview_reset_enabled_after_import"])
        self.assertTrue(report["structure_selection_hook_loaded"])
        self.assertIn("1 3", report["structure_selection_text_after_toggle"])
        self.assertTrue(report["structure_apply_selection_enabled"])
        self.assertTrue(report["structure_clear_selection_enabled"])
        self.assertEqual(report["structure_applied_fixed_atoms"], "1 3")
        self.assertEqual(report["fixed_atoms_after_structure_selection"], "1 3")
        self.assertTrue(report["structure_preview_initial_distance_fits_viewport"])
        self.assertTrue(report["structure_preview_interaction_hook_loaded"])
        self.assertTrue(report["structure_preview_rotate_changed_transform"])
        self.assertTrue(report["structure_preview_pan_changed_camera"])
        self.assertTrue(report["structure_preview_zoom_changed_distance"])
        self.assertTrue(report["structure_preview_reset_restored_camera"])
        self.assertTrue(report["structure_preview_reset_restored_transform"])
        self.assertGreaterEqual(report["history_grid_count"], 1)
        self.assertEqual(report["history_selected_project"], "button_history")
        self.assertTrue(report["history_log_has_jobs"])
        self.assertTrue(report["existing_mode_import_disabled"])
        self.assertTrue(report["workflow_preview_has_global"])
        self.assertTrue(report["existing_preview_has_global"])
        self.assertTrue(report["artifact_summary_has_history"])
        self.assertTrue(report["artifact_summary_has_energy"])
        self.assertTrue(report["artifact_results_has_force_table"])
        self.assertTrue(report["result_summary_saved"])
        self.assertTrue(report["result_summary_path_in_summary"])
        self.assertTrue(report["result_summary_file_has_force"])
        self.assertTrue(report["artifact_input_synced_preview"])
        self.assertTrue(report["artifact_output_text_has_program_end"])
        self.assertTrue(report["artifact_output_preserved_input_preview"])
        self.assertTrue(report["artifact_text_has_stderr"])
        self.assertTrue(report["artifact_log_has_stderr"])
        self.assertTrue(report["preview_text_preserved_after_output_artifact"])
        self.assertTrue(report["language_apply_switched_to_zh"])
        self.assertTrue(report["language_apply_changed_preview_text"])
        self.assertTrue(report["clear_emptied_text_fields"])
        self.assertTrue(report["clear_removed_structure_preview_geometry"])
        self.assertTrue(report["clear_disabled_structure_reset"])
        self.assertTrue(report["clear_disabled_artifact_buttons"])
        self.assertTrue(report["clear_removed_history_items"])

    @unittest.skipUnless(platform.system() == "Windows", "WPF prototype is Windows-only")
    def test_edited_preview_smoke_runs_saved_input_copy(self) -> None:
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
                "-EditedPreviewSmokeTest",
            ],
            capture_output=True,
            check=False,
        )

        stderr = completed.stderr.decode("utf-8", errors="replace")
        stdout = completed.stdout.decode("utf-8-sig", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr)
        report = json.loads(stdout)
        self.assertEqual(report["mode"], "edited_preview_smoke")
        self.assertTrue(report["preview_original_has_global"])
        self.assertTrue(report["edited_preview_reported"])
        self.assertTrue(report["edited_preview_used"])
        self.assertTrue(report["edited_preview_confirmation_requested"])
        self.assertTrue(report["edited_preview_confirmation_suppressed"])
        self.assertEqual(report["edited_preview_confirmation_result"], "suppressed_yes")
        self.assertEqual(report["prepared_job_mode"], "existing_input")
        self.assertTrue(report["edited_input_path"].endswith("_edited.inp"))
        self.assertEqual(report["edited_input_path"], report["prepared_input_path"])
        self.assertTrue(report["edited_input_contains_marker"])
        self.assertTrue(report["prepared_input_contains_marker"])
        self.assertTrue(report["edited_input_separate_from_original"])
        self.assertFalse(report["original_input_contains_marker"])
        self.assertIn(report["edited_input_path"], report["run_arguments"])
        run_arguments = report["run_arguments"]
        self.assertIn("--job-dir", run_arguments)
        self.assertEqual(
            Path(report["edited_input_path"]).parent,
            Path(run_arguments[run_arguments.index("--job-dir") + 1]),
        )
        self.assertFalse(Path(report["edited_input_path"]).read_bytes().startswith(b"\xef\xbb\xbf"))

    @unittest.skipUnless(platform.system() == "Windows", "WPF prototype is Windows-only")
    def test_python_invoke_smoke_keeps_stderr_separate(self) -> None:
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
                "-PythonInvokeSmokeTest",
            ],
            capture_output=True,
            check=False,
        )

        stderr = completed.stderr.decode("utf-8", errors="replace")
        stdout = completed.stdout.decode("utf-8-sig", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr)
        report = json.loads(stdout)
        self.assertEqual(report["mode"], "python_invoke_smoke")
        self.assertEqual(report["json_stdout_output"], '{"ok": true}')
        self.assertEqual(report["json_stdout_error"], "plain stderr")
        self.assertIn("Expecting property name enclosed in double quotes", report["bad_fields_error"])
        self.assertFalse(report["stderr_has_native_wrapper"])

    @unittest.skipUnless(platform.system() == "Windows", "WPF prototype is Windows-only")
    def test_environment_display_smoke_formats_probe_json(self) -> None:
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
                "-EnvironmentDisplaySmokeTest",
            ],
            capture_output=True,
            check=False,
        )

        stderr = completed.stderr.decode("utf-8", errors="replace")
        stdout = completed.stdout.decode("utf-8-sig", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr)
        report = json.loads(stdout)
        self.assertEqual(report["mode"], "environment_display_smoke")
        self.assertTrue(report["environment_text_has_summary"])
        self.assertTrue(report["environment_text_has_distro"])
        self.assertTrue(report["environment_text_has_cp2k"])
        self.assertTrue(report["environment_text_has_data_files"])
        self.assertTrue(report["environment_text_has_warning"])
        self.assertTrue(report["environment_text_has_command_status"])
        self.assertTrue(report["environment_text_is_not_raw_json"])


if __name__ == "__main__":
    unittest.main()

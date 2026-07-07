function Get-WinQStepGuiControlNames {
    return @(
        "MainScrollViewer", "MainTabs",
        "WorkflowModeRadio", "ExistingInputModeRadio", "ExistingInputBatchModeRadio", "BatchStopOnFailureBox",
        "JobInputsGroup",
        "ModeLabel", "ConfigPathLabel", "TemplatePathLabel", "StructurePathLabel",
        "ExistingInputPathLabel", "BatchInputDirLabel", "BatchInputFilesLabel", "BatchInputListLabel",
        "JobFolderLabel", "ProjectLabel",
        "RunTargetLabel", "RunTargetText", "BatchInputCountText",
        "ConfigPathBox", "TemplatePathBox", "StructurePathBox", "ExistingInputPathBox",
        "BatchInputsPanel", "BatchInputDirBox", "BatchInputFilesBox", "BatchInputListBox",
        "JobDirBox", "ProjectNameBox",
        "ConfigTab", "TemplateTab", "EnvironmentTab", "StructureTab",
        "InputPreviewTab", "JobLogTab", "ArtifactsTab", "HistoryTab",
        "StructurePreviewStatusText", "StructureSelectionText", "StructurePreviewViewport", "StructurePreviewCamera", "StructurePreviewVisual",
        "TemplateManualText", "Cp2kInputManualLink",
        "TemplateSectionsTabs", "TemplateCoreTab", "TemplateDftTab", "TemplateSubsystemTab", "TemplateMotionTab",
        "DistroLabel", "Cp2kCommandLabel", "Cp2kDataDirLabel", "MpiCommandLabel",
        "WorkspaceLabel", "WslPreludeLabel", "TimeoutLabel", "UiLanguageLabel",
        "DistroBox", "Cp2kCommandBox", "Cp2kDataDirBox", "MpirunCommandBox",
        "DefaultWorkspaceBox", "WslPreludeBox", "TimeoutBox", "UiLanguageBox", "ConfigValidationText",
        "TemplateProjectLabel", "RunTypeLabel", "BasisFileLabel", "PotentialFileLabel",
        "XcFunctionalLabel", "XcPbeParametrizationLabel", "DispersionTypeLabel",
        "DispersionParameterFileLabel", "DispersionReferenceFunctionalLabel",
        "DispersionHintText",
        "EpsScfLabel", "ChargeLabel", "MultiplicityLabel",
        "CutoffLabel", "RelCutoffLabel", "PoissonSolverLabel", "PrintLevelLabel", "MaxScfLabel", "OptimizerLabel", "GeoMaxIterLabel",
        "PoissonHintText",
        "WfnRestartFileNameLabel", "ScfGuessLabel",
        "CellOptTypeLabel", "CellOptOptimizerLabel", "CellOptMaxIterLabel",
        "CellOptPressureToleranceLabel",
        "CellOptHintText",
        "FixedAtomsLabel", "FixedAtomComponentsLabel",
        "ScfMethodLabel", "AddedMosLabel", "DiagonalizationAlgorithmLabel",
        "OtMinimizerLabel", "OtPreconditionerLabel",
        "OuterScfEpsScfLabel", "OuterScfMaxScfLabel",
        "OuterScfHintText",
        "MixingMethodLabel",
        "MixingAlphaLabel", "MixingBetaLabel", "MixingHintText", "SmearingMethodLabel",
        "ElectronicTemperatureLabel", "KpointsSchemeLabel", "KpointsGridLabel",
        "SmearingHintText", "KpointsWavefunctionsLabel", "KpointsHintText", "DftPrintHintText",
        "BandFileNameLabel", "BandAddedMosLabel", "BandNpointsLabel",
        "BandKpointUnitsLabel", "BandSpecialPointsLabel",
        "FallbackPeriodicLabel", "FallbackCellALabel", "FallbackCellBLabel", "FallbackCellCLabel",
        "TemplateProjectBox", "TemplateRunTypeBox", "PrintLevelBox", "BasisSetFileBox", "PotentialFileBox",
        "PoissonSolverBox",
        "WfnRestartFileNameBox",
        "XcFunctionalBox", "XcPbeParametrizationBox", "DispersionTypeBox",
        "DispersionParameterFileBox", "DispersionReferenceFunctionalBox",
        "ChargeBox", "MultiplicityBox", "CutoffBox", "RelCutoffBox",
        "EpsScfBox", "MaxScfBox", "GeoOptimizerBox", "GeoMaxIterBox",
        "CellOptTypeBox", "CellOptOptimizerBox", "CellOptMaxIterBox",
        "CellOptPressureToleranceBox",
        "FixedAtomsBox", "FixedAtomComponentsBox",
        "ScfMethodBox", "AddedMosBox", "DiagonalizationAlgorithmBox",
        "ScfGuessBox",
        "OtMinimizerBox", "OtPreconditionerBox",
        "OuterScfEpsScfBox", "OuterScfMaxScfBox",
        "MixingMethodBox",
        "MixingAlphaBox", "MixingBetaBox", "SmearingMethodBox",
        "ElectronicTemperatureBox", "KpointsSchemeBox", "KpointsGridBox",
        "KpointsWavefunctionsBox", "OuterScfEnabledBox", "MixingEnabledBox", "SmearingEnabledBox",
        "DispersionEnabledBox",
        "PrintMullikenBox", "PrintLowdinBox", "PrintPdosBox",
        "PrintEDensityCubeBox", "PrintVHartreeCubeBox", "PrintBandStructureBox",
        "BandFileNameBox", "BandAddedMosBox", "BandNpointsBox",
        "BandKpointUnitsBox", "BandSpecialPointsBox",
        "UksEnabledBox", "CellOptKeepAnglesBox", "CellOptKeepSymmetryBox",
        "KpointsFullGridBox", "KpointsSymmetryBox",
        "FallbackPeriodicBox", "FallbackCellABox", "FallbackCellBBox", "FallbackCellCBox",
        "CenterAtomsBox", "KindsText",
        "KindEntriesGrid", "DataLabelsGrid", "TemplateValidationText",
        "EnvironmentText", "StructureText", "PreviewText", "LogSearchLabel", "LogSearchBox",
        "LogFindPreviousButton", "LogFindNextButton", "LogSearchStatusText", "LogText",
        "ArtifactSummaryText", "ArtifactSearchLabel", "ArtifactSearchBox",
        "ArtifactFindPreviousButton", "ArtifactFindNextButton", "ArtifactSearchStatusText",
        "ArtifactText", "BatchResultsGrid", "HistoryGrid", "StatusText", "JobStatusText",
        "LoadConfigButton", "SaveConfigButton", "ApplyLanguageButton", "LoadTemplateButton", "SaveTemplateButton",
        "InspectDataButton", "DetectButton", "ImportButton",
        "StructureResetViewButton", "StructureApplyFixedAtomsButton", "StructureClearSelectionButton",
        "PreviewButton", "RunButton", "CancelJobButton", "HistoryButton", "ClearButton",
        "ViewResultsButton", "SaveResultsButton",
        "ViewInputButton", "ViewOutputButton", "ViewMetadataButton", "ViewStdoutButton", "ViewStderrButton",
        "ViewArtifactTailButton", "ViewArtifactFullButton",
        "ResumeBatchButton", "SkipBatchItemButton", "RerunBatchItemButton", "CancelBatchItemButton",
        "BrowseConfigButton", "BrowseTemplateButton", "BrowseStructureButton",
        "BrowseExistingInputButton", "BrowseBatchInputDirButton", "BrowseBatchInputFilesButton",
        "BrowseBatchInputListButton", "BrowseJobDirButton"
    )
}

function Set-WinQStepLocalizedControls {
    param(
        [Parameter(Mandatory = $true)]$Window,
        [Parameter(Mandatory = $true)][hashtable]$Controls
    )

    $Window.Title = Get-WinQStepText "app.title"
    $contentLocalization = @{
    LoadConfigButton = "button.load_config"
    SaveConfigButton = "button.save_config"
    ApplyLanguageButton = "button.apply"
    LoadTemplateButton = "button.load_template"
    SaveTemplateButton = "button.save_template"
    InspectDataButton = "button.inspect_data"
    DetectButton = "button.detect"
    ImportButton = "button.import"
    StructureResetViewButton = "button.reset_view"
    StructureApplyFixedAtomsButton = "button.apply_fixed_atoms"
    StructureClearSelectionButton = "button.clear_selection"
    PreviewButton = "button.preview"
    RunButton = "button.run"
    CancelJobButton = "button.stop"
    HistoryButton = "button.history"
    ClearButton = "button.clear"
    BrowseConfigButton = "button.browse"
    BrowseTemplateButton = "button.browse"
    BrowseStructureButton = "button.browse"
    BrowseExistingInputButton = "button.browse"
    BrowseBatchInputDirButton = "button.browse"
    BrowseBatchInputFilesButton = "button.browse"
    BrowseBatchInputListButton = "button.browse"
    BrowseJobDirButton = "button.browse"
    ViewResultsButton = "button.results"
    SaveResultsButton = "button.save_results"
    ViewInputButton = "button.input"
    ViewOutputButton = "button.output"
    ViewMetadataButton = "button.metadata"
    ViewStdoutButton = "button.stdout"
    ViewStderrButton = "button.stderr"
    ViewArtifactTailButton = "button.tail"
    ViewArtifactFullButton = "button.full_text"
    LogFindPreviousButton = "button.find_previous"
    LogFindNextButton = "button.find_next"
    ArtifactFindPreviousButton = "button.find_previous"
    ArtifactFindNextButton = "button.find_next"
    ResumeBatchButton = "button.resume_batch"
    SkipBatchItemButton = "button.skip_item"
    RerunBatchItemButton = "button.rerun_item"
    CancelBatchItemButton = "button.cancel_item"
    WorkflowModeRadio = "mode.workflow"
    ExistingInputModeRadio = "mode.existing_input"
    ExistingInputBatchModeRadio = "mode.existing_input_batch"
    BatchStopOnFailureBox = "label.batch_stop_on_failure"
    MixingEnabledBox = "label.mixing_enabled"
    SmearingEnabledBox = "label.smearing_enabled"
    UksEnabledBox = "label.uks_enabled"
    DispersionEnabledBox = "label.dispersion_enabled"
    CellOptKeepAnglesBox = "label.cell_opt_keep_angles"
    CellOptKeepSymmetryBox = "label.cell_opt_keep_symmetry"
    OuterScfEnabledBox = "label.outer_scf_enabled"
    KpointsFullGridBox = "label.kpoints_full_grid"
    KpointsSymmetryBox = "label.kpoints_symmetry"
    PrintMullikenBox = "label.print_mulliken"
    PrintLowdinBox = "label.print_lowdin"
    PrintPdosBox = "label.print_pdos"
    PrintEDensityCubeBox = "label.print_e_density_cube"
    PrintVHartreeCubeBox = "label.print_v_hartree_cube"
    PrintBandStructureBox = "label.print_band_structure"
    CenterAtomsBox = "label.center_atoms"
    }
    foreach ($entry in $contentLocalization.GetEnumerator()) {
        Set-WinQStepContent $Controls[$entry.Key] $entry.Value
    }

    $headerLocalization = @{
    JobInputsGroup = "group.job_inputs"
    ConfigTab = "tab.config"
    TemplateTab = "tab.template"
    EnvironmentTab = "tab.environment"
    StructureTab = "tab.structure"
    InputPreviewTab = "tab.input_preview"
    JobLogTab = "tab.job_log"
    ArtifactsTab = "tab.artifacts"
    HistoryTab = "tab.history"
    TemplateCoreTab = "tab.template_core"
    TemplateDftTab = "tab.template_dft"
    TemplateSubsystemTab = "tab.template_subsystem"
    TemplateMotionTab = "tab.template_motion"
    }
    foreach ($entry in $headerLocalization.GetEnumerator()) {
        Set-WinQStepHeader $Controls[$entry.Key] $entry.Value
    }

    $textLocalization = @{
    ModeLabel = "label.mode"
    LogSearchLabel = "label.find"
    ArtifactSearchLabel = "label.find"
    ConfigPathLabel = "label.config"
    TemplatePathLabel = "label.template"
    StructurePathLabel = "label.structure"
    ExistingInputPathLabel = "label.existing_input"
    BatchInputDirLabel = "label.batch_input_dir"
    BatchInputFilesLabel = "label.batch_input_files"
    BatchInputListLabel = "label.batch_input_list"
    JobFolderLabel = "label.job_folder"
    ProjectLabel = "label.project"
    RunTargetLabel = "label.run_target"
    DistroLabel = "label.distro"
    Cp2kCommandLabel = "label.cp2k_command"
    Cp2kDataDirLabel = "label.cp2k_data_dir"
    MpiCommandLabel = "label.mpi_command"
    WorkspaceLabel = "label.workspace"
    WslPreludeLabel = "label.wsl_prelude"
    TimeoutLabel = "label.timeout"
    UiLanguageLabel = "label.ui_language"
    TemplateProjectLabel = "label.project"
    RunTypeLabel = "label.run_type"
    PrintLevelLabel = "label.print_level"
    BasisFileLabel = "label.basis_file"
    PotentialFileLabel = "label.potential_file"
    XcFunctionalLabel = "label.xc_functional"
    XcPbeParametrizationLabel = "label.xc_pbe_parametrization"
    DispersionTypeLabel = "label.dispersion_type"
    DispersionParameterFileLabel = "label.dispersion_parameter_file"
    DispersionReferenceFunctionalLabel = "label.dispersion_reference_functional"
    EpsScfLabel = "label.eps_scf"
    ChargeLabel = "label.charge"
    MultiplicityLabel = "label.multiplicity"
    CutoffLabel = "label.cutoff"
    RelCutoffLabel = "label.rel_cutoff"
    PoissonSolverLabel = "label.poisson_solver"
    WfnRestartFileNameLabel = "label.wfn_restart_file_name"
    MaxScfLabel = "label.max_scf"
    ScfMethodLabel = "label.scf_method"
    ScfGuessLabel = "label.scf_guess"
    AddedMosLabel = "label.added_mos"
    DiagonalizationAlgorithmLabel = "label.diagonalization_algorithm"
    OtMinimizerLabel = "label.ot_minimizer"
    OtPreconditionerLabel = "label.ot_preconditioner"
    OuterScfEpsScfLabel = "label.outer_scf_eps_scf"
    OuterScfMaxScfLabel = "label.outer_scf_max_scf"
    MixingMethodLabel = "label.mixing_method"
    MixingAlphaLabel = "label.mixing_alpha"
    MixingBetaLabel = "label.mixing_beta"
    SmearingMethodLabel = "label.smearing_method"
    ElectronicTemperatureLabel = "label.electronic_temperature"
    KpointsSchemeLabel = "label.kpoints_scheme"
    KpointsGridLabel = "label.kpoints_grid"
    KpointsWavefunctionsLabel = "label.kpoints_wavefunctions"
    BandFileNameLabel = "label.band_file_name"
    BandAddedMosLabel = "label.band_added_mos"
    BandNpointsLabel = "label.band_npoints"
    BandKpointUnitsLabel = "label.band_kpoint_units"
    BandSpecialPointsLabel = "label.band_special_points"
    OptimizerLabel = "label.optimizer"
    GeoMaxIterLabel = "label.geo_max_iter"
    CellOptTypeLabel = "label.cell_opt_type"
    CellOptOptimizerLabel = "label.cell_opt_optimizer"
    CellOptMaxIterLabel = "label.cell_opt_max_iter"
    CellOptPressureToleranceLabel = "label.cell_opt_pressure_tolerance"
    FixedAtomsLabel = "label.fixed_atoms"
    FixedAtomComponentsLabel = "label.fixed_atom_components"
    FallbackPeriodicLabel = "label.fallback_periodic"
    FallbackCellALabel = "label.fallback_cell_a"
    FallbackCellBLabel = "label.fallback_cell_b"
    FallbackCellCLabel = "label.fallback_cell_c"
    StructureSelectionText = "structure.fixed_atoms.none"
    StatusText = "status.ready"
    }
    foreach ($entry in $textLocalization.GetEnumerator()) {
        Set-WinQStepText $Controls[$entry.Key] $entry.Value
    }

    if ($Controls["UiLanguageBox"].Items.Count -ge 3) {
        $Controls["UiLanguageBox"].Items[0].Content = Get-WinQStepText "language.system_default"
        $Controls["UiLanguageBox"].Items[0].Tag = ""
        $Controls["UiLanguageBox"].Items[1].Content = Get-WinQStepText "language.en_us"
        $Controls["UiLanguageBox"].Items[1].Tag = "en-US"
        $Controls["UiLanguageBox"].Items[2].Content = Get-WinQStepText "language.zh_cn"
        $Controls["UiLanguageBox"].Items[2].Tag = "zh-CN"
    }

    if ($Controls["DataLabelsGrid"].Columns.Count -ge 3) {
        $Controls["DataLabelsGrid"].Columns[0].Header = Get-WinQStepText "column.element"
        $Controls["DataLabelsGrid"].Columns[1].Header = Get-WinQStepText "column.basis_sets"
        $Controls["DataLabelsGrid"].Columns[2].Header = Get-WinQStepText "column.potentials"
    }
    if ($Controls["HistoryGrid"].Columns.Count -ge 7) {
        $Controls["HistoryGrid"].Columns[0].Header = Get-WinQStepText "column.completed"
        $Controls["HistoryGrid"].Columns[1].Header = Get-WinQStepText "column.mode"
        $Controls["HistoryGrid"].Columns[2].Header = Get-WinQStepText "column.status"
        $Controls["HistoryGrid"].Columns[3].Header = Get-WinQStepText "column.code"
        $Controls["HistoryGrid"].Columns[4].Header = Get-WinQStepText "column.warnings"
        $Controls["HistoryGrid"].Columns[5].Header = Get-WinQStepText "column.project_input"
        $Controls["HistoryGrid"].Columns[6].Header = Get-WinQStepText "column.output"
    }
    if ($Controls["BatchResultsGrid"].Columns.Count -ge 8) {
        $Controls["BatchResultsGrid"].Columns[0].Header = Get-WinQStepText "column.index"
        $Controls["BatchResultsGrid"].Columns[1].Header = Get-WinQStepText "column.status"
        $Controls["BatchResultsGrid"].Columns[2].Header = Get-WinQStepText "column.attempt"
        $Controls["BatchResultsGrid"].Columns[3].Header = Get-WinQStepText "column.code"
        $Controls["BatchResultsGrid"].Columns[4].Header = Get-WinQStepText "column.input"
        $Controls["BatchResultsGrid"].Columns[5].Header = Get-WinQStepText "column.output"
        $Controls["BatchResultsGrid"].Columns[6].Header = Get-WinQStepText "column.metadata"
        $Controls["BatchResultsGrid"].Columns[7].Header = Get-WinQStepText "column.error"
    }
}

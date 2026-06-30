#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SmokeTest,
    [switch]$LifecycleSmokeTest,
    [switch]$ButtonSmokeTest,
    [switch]$EditedPreviewSmokeTest,
    [switch]$AsyncRunSmokeTest,
    [switch]$PythonInvokeSmokeTest,
    [switch]$Diagnostics,
    [switch]$SkipLiveProbes,
    [string]$Language = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Script:RepoRoot = Split-Path -Parent $PSScriptRoot
$Script:PythonCommand = "python"
$Script:Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($false)
$Script:RequestedLanguage = $Language
$SuppressGuiMessageBoxes = [bool]($ButtonSmokeTest -or $EditedPreviewSmokeTest -or $AsyncRunSmokeTest)
$EditedPreviewSmokeTestEnabled = [bool]$EditedPreviewSmokeTest
$EditedPreviewSmokeState = @{ Report = $null }
$Script:SuppressGuiMessageBoxes = $SuppressGuiMessageBoxes
$Script:EditedPreviewSmokeStartAsyncJob = $null

. (Join-Path $PSScriptRoot "gui\WinQStep.GuiHost.ps1")
function New-WinQStepWindow {
    Add-WinQStepWpfAssemblies
    $defaultConfigPath = Resolve-WinQStepPath "examples\winqstep.config.json"
    $hasLanguageOverride = -not [string]::IsNullOrWhiteSpace($Script:RequestedLanguage)
    $initialLanguage = $Script:RequestedLanguage
    if ([string]::IsNullOrWhiteSpace($initialLanguage)) {
        $initialLanguage = Read-WinQStepConfigLanguage $defaultConfigPath
    }
    $localization = Initialize-WinQStepLocalization $initialLanguage

    $xamlPath = Resolve-WinQStepPath "scripts\gui\WinQStep.xaml"
    [xml]$xaml = [System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8)

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $controls = @{}
    $names = @(
        "MainScrollViewer", "MainTabs",
        "WorkflowModeRadio", "ExistingInputModeRadio",
        "JobInputsGroup",
        "ModeLabel", "ConfigPathLabel", "TemplatePathLabel", "StructurePathLabel",
        "ExistingInputPathLabel", "JobFolderLabel", "ProjectLabel",
        "ConfigPathBox", "TemplatePathBox", "StructurePathBox", "ExistingInputPathBox",
        "JobDirBox", "ProjectNameBox",
        "ConfigTab", "TemplateTab", "EnvironmentTab", "StructureTab",
        "InputPreviewTab", "JobLogTab", "ArtifactsTab", "HistoryTab",
        "DistroLabel", "Cp2kCommandLabel", "Cp2kDataDirLabel", "MpiCommandLabel",
        "WorkspaceLabel", "WslPreludeLabel", "TimeoutLabel", "UiLanguageLabel",
        "DistroBox", "Cp2kCommandBox", "Cp2kDataDirBox", "MpirunCommandBox",
        "DefaultWorkspaceBox", "WslPreludeBox", "TimeoutBox", "UiLanguageBox", "ConfigValidationText",
        "TemplateProjectLabel", "RunTypeLabel", "BasisFileLabel", "PotentialFileLabel",
        "XcFunctionalLabel", "EpsScfLabel", "ChargeLabel", "MultiplicityLabel",
        "CutoffLabel", "RelCutoffLabel", "PrintLevelLabel", "MaxScfLabel", "OptimizerLabel", "GeoMaxIterLabel",
        "CellOptTypeLabel", "CellOptOptimizerLabel", "CellOptMaxIterLabel",
        "CellOptPressureToleranceLabel",
        "ScfMethodLabel", "AddedMosLabel", "DiagonalizationAlgorithmLabel",
        "OtMinimizerLabel", "OtPreconditionerLabel", "MixingMethodLabel",
        "MixingAlphaLabel", "MixingBetaLabel", "SmearingMethodLabel",
        "ElectronicTemperatureLabel", "KpointsSchemeLabel", "KpointsGridLabel",
        "KpointsWavefunctionsLabel",
        "FallbackPeriodicLabel", "FallbackCellALabel", "FallbackCellBLabel", "FallbackCellCLabel",
        "TemplateProjectBox", "TemplateRunTypeBox", "PrintLevelBox", "BasisSetFileBox", "PotentialFileBox",
        "XcFunctionalBox", "ChargeBox", "MultiplicityBox", "CutoffBox", "RelCutoffBox",
        "EpsScfBox", "MaxScfBox", "GeoOptimizerBox", "GeoMaxIterBox",
        "CellOptTypeBox", "CellOptOptimizerBox", "CellOptMaxIterBox",
        "CellOptPressureToleranceBox",
        "ScfMethodBox", "AddedMosBox", "DiagonalizationAlgorithmBox",
        "OtMinimizerBox", "OtPreconditionerBox", "MixingMethodBox",
        "MixingAlphaBox", "MixingBetaBox", "SmearingMethodBox",
        "ElectronicTemperatureBox", "KpointsSchemeBox", "KpointsGridBox",
        "KpointsWavefunctionsBox", "MixingEnabledBox", "SmearingEnabledBox",
        "CellOptKeepAnglesBox", "CellOptKeepSymmetryBox",
        "KpointsFullGridBox", "KpointsSymmetryBox",
        "FallbackPeriodicBox", "FallbackCellABox", "FallbackCellBBox", "FallbackCellCBox",
        "CenterAtomsBox", "KindsText",
        "KindEntriesGrid", "DataLabelsGrid", "TemplateValidationText",
        "EnvironmentText", "StructureText", "PreviewText", "LogText",
        "ArtifactSummaryText", "ArtifactText", "HistoryGrid", "StatusText", "JobStatusText",
        "LoadConfigButton", "SaveConfigButton", "ApplyLanguageButton", "LoadTemplateButton", "SaveTemplateButton",
        "InspectDataButton", "DetectButton", "ImportButton",
        "PreviewButton", "RunButton", "CancelJobButton", "HistoryButton", "ClearButton",
        "ViewResultsButton", "SaveResultsButton",
        "ViewInputButton", "ViewOutputButton", "ViewMetadataButton", "ViewStdoutButton", "ViewStderrButton",
        "BrowseConfigButton", "BrowseTemplateButton", "BrowseStructureButton",
        "BrowseExistingInputButton", "BrowseJobDirButton"
    )
    foreach ($name in $names) {
        $controls[$name] = $window.FindName($name)
    }

    $ApplyLocalizationToControls = {
        $window.Title = Get-WinQStepText "app.title"
        $contentLocalization = @{
        LoadConfigButton = "button.load_config"
        SaveConfigButton = "button.save_config"
        ApplyLanguageButton = "button.apply"
        LoadTemplateButton = "button.load_template"
        SaveTemplateButton = "button.save_template"
        InspectDataButton = "button.inspect_data"
        DetectButton = "button.detect"
        ImportButton = "button.import"
        PreviewButton = "button.preview"
        RunButton = "button.run"
        CancelJobButton = "button.stop"
        HistoryButton = "button.history"
        ClearButton = "button.clear"
        BrowseConfigButton = "button.browse"
        BrowseTemplateButton = "button.browse"
        BrowseStructureButton = "button.browse"
        BrowseExistingInputButton = "button.browse"
        BrowseJobDirButton = "button.browse"
        ViewResultsButton = "button.results"
        SaveResultsButton = "button.save_results"
        ViewInputButton = "button.input"
        ViewOutputButton = "button.output"
        ViewMetadataButton = "button.metadata"
        ViewStdoutButton = "button.stdout"
        ViewStderrButton = "button.stderr"
        WorkflowModeRadio = "mode.workflow"
        ExistingInputModeRadio = "mode.existing_input"
        MixingEnabledBox = "label.mixing_enabled"
        SmearingEnabledBox = "label.smearing_enabled"
        CellOptKeepAnglesBox = "label.cell_opt_keep_angles"
        CellOptKeepSymmetryBox = "label.cell_opt_keep_symmetry"
        KpointsFullGridBox = "label.kpoints_full_grid"
        KpointsSymmetryBox = "label.kpoints_symmetry"
        CenterAtomsBox = "label.center_atoms"
        }
        foreach ($entry in $contentLocalization.GetEnumerator()) {
            Set-WinQStepContent $controls[$entry.Key] $entry.Value
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
        }
        foreach ($entry in $headerLocalization.GetEnumerator()) {
            Set-WinQStepHeader $controls[$entry.Key] $entry.Value
        }

        $textLocalization = @{
        ModeLabel = "label.mode"
        ConfigPathLabel = "label.config"
        TemplatePathLabel = "label.template"
        StructurePathLabel = "label.structure"
        ExistingInputPathLabel = "label.existing_input"
        JobFolderLabel = "label.job_folder"
        ProjectLabel = "label.project"
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
        EpsScfLabel = "label.eps_scf"
        ChargeLabel = "label.charge"
        MultiplicityLabel = "label.multiplicity"
        CutoffLabel = "label.cutoff"
        RelCutoffLabel = "label.rel_cutoff"
        MaxScfLabel = "label.max_scf"
        ScfMethodLabel = "label.scf_method"
        AddedMosLabel = "label.added_mos"
        DiagonalizationAlgorithmLabel = "label.diagonalization_algorithm"
        OtMinimizerLabel = "label.ot_minimizer"
        OtPreconditionerLabel = "label.ot_preconditioner"
        MixingMethodLabel = "label.mixing_method"
        MixingAlphaLabel = "label.mixing_alpha"
        MixingBetaLabel = "label.mixing_beta"
        SmearingMethodLabel = "label.smearing_method"
        ElectronicTemperatureLabel = "label.electronic_temperature"
        KpointsSchemeLabel = "label.kpoints_scheme"
        KpointsGridLabel = "label.kpoints_grid"
        KpointsWavefunctionsLabel = "label.kpoints_wavefunctions"
        OptimizerLabel = "label.optimizer"
        GeoMaxIterLabel = "label.geo_max_iter"
        CellOptTypeLabel = "label.cell_opt_type"
        CellOptOptimizerLabel = "label.cell_opt_optimizer"
        CellOptMaxIterLabel = "label.cell_opt_max_iter"
        CellOptPressureToleranceLabel = "label.cell_opt_pressure_tolerance"
        FallbackPeriodicLabel = "label.fallback_periodic"
        FallbackCellALabel = "label.fallback_cell_a"
        FallbackCellBLabel = "label.fallback_cell_b"
        FallbackCellCLabel = "label.fallback_cell_c"
        StatusText = "status.ready"
        }
        foreach ($entry in $textLocalization.GetEnumerator()) {
            Set-WinQStepText $controls[$entry.Key] $entry.Value
        }

        if ($controls["UiLanguageBox"].Items.Count -ge 3) {
            $controls["UiLanguageBox"].Items[0].Content = Get-WinQStepText "language.system_default"
            $controls["UiLanguageBox"].Items[0].Tag = ""
            $controls["UiLanguageBox"].Items[1].Content = Get-WinQStepText "language.en_us"
            $controls["UiLanguageBox"].Items[1].Tag = "en-US"
            $controls["UiLanguageBox"].Items[2].Content = Get-WinQStepText "language.zh_cn"
            $controls["UiLanguageBox"].Items[2].Tag = "zh-CN"
        }

        if ($controls["DataLabelsGrid"].Columns.Count -ge 3) {
            $controls["DataLabelsGrid"].Columns[0].Header = Get-WinQStepText "column.element"
            $controls["DataLabelsGrid"].Columns[1].Header = Get-WinQStepText "column.basis_sets"
            $controls["DataLabelsGrid"].Columns[2].Header = Get-WinQStepText "column.potentials"
        }
        if ($controls["HistoryGrid"].Columns.Count -ge 7) {
            $controls["HistoryGrid"].Columns[0].Header = Get-WinQStepText "column.completed"
            $controls["HistoryGrid"].Columns[1].Header = Get-WinQStepText "column.mode"
            $controls["HistoryGrid"].Columns[2].Header = Get-WinQStepText "column.status"
            $controls["HistoryGrid"].Columns[3].Header = Get-WinQStepText "column.code"
            $controls["HistoryGrid"].Columns[4].Header = Get-WinQStepText "column.warnings"
            $controls["HistoryGrid"].Columns[5].Header = Get-WinQStepText "column.project_input"
            $controls["HistoryGrid"].Columns[6].Header = Get-WinQStepText "column.output"
        }
    }.GetNewClosure()
    & $ApplyLocalizationToControls

    $controls["ConfigPathBox"].Text = $defaultConfigPath
    $controls["TemplatePathBox"].Text = Resolve-WinQStepPath "examples\templates\energy_pbe.json"
    $controls["StructurePathBox"].Text = Resolve-WinQStepPath "tests\fixtures\structures\water.xyz"
    $controls["ExistingInputPathBox"].Text = Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"
    $controls["JobDirBox"].Text = Resolve-WinQStepPath "outputs\gui-preview"
    $controls["ProjectNameBox"].Text = "gui_preview"
    $controls["CancelJobButton"].IsEnabled = $false

    $artifactButtons = @{
        input = $controls["ViewInputButton"]
        output = $controls["ViewOutputButton"]
        metadata = $controls["ViewMetadataButton"]
        stdout = $controls["ViewStdoutButton"]
        stderr = $controls["ViewStderrButton"]
    }
    $resultButtons = @(
        $controls["ViewResultsButton"],
        $controls["SaveResultsButton"]
    )
    $artifactState = @{ Current = $null }
    $previewState = @{ Current = $null }

    $actionButtons = @(
        $controls["LoadConfigButton"], $controls["SaveConfigButton"],
        $controls["ApplyLanguageButton"],
        $controls["LoadTemplateButton"], $controls["SaveTemplateButton"],
        $controls["InspectDataButton"], $controls["DetectButton"], $controls["ImportButton"],
        $controls["PreviewButton"], $controls["RunButton"],
        $controls["HistoryButton"], $controls["ClearButton"],
        $controls["ViewResultsButton"], $controls["SaveResultsButton"],
        $controls["ViewInputButton"], $controls["ViewOutputButton"], $controls["ViewMetadataButton"],
        $controls["ViewStdoutButton"], $controls["ViewStderrButton"], $controls["BrowseConfigButton"],
        $controls["BrowseTemplateButton"], $controls["BrowseStructureButton"],
        $controls["BrowseExistingInputButton"], $controls["BrowseJobDirButton"]
    )

    $GetUiLanguageSelection = {
        $item = $controls["UiLanguageBox"].SelectedItem
        if ($null -eq $item -or $null -eq $item.Tag) {
            return ""
        }
        return [string]$item.Tag
    }.GetNewClosure()

    $SetUiLanguageSelection = {
        param([string]$Language)
        $target = ""
        if (-not [string]::IsNullOrWhiteSpace($Language)) {
            $target = Resolve-WinQStepLanguage $Language
        }
        foreach ($item in @($controls["UiLanguageBox"].Items)) {
            if ([string]$item.Tag -eq $target) {
                $controls["UiLanguageBox"].SelectedItem = $item
                return
            }
        }
        $controls["UiLanguageBox"].SelectedIndex = 0
    }.GetNewClosure()

    $ApplyConfiguredLanguage = {
        param([string]$Language)
        if ($hasLanguageOverride) {
            return
        }
        $null = Initialize-WinQStepLocalization $Language
        & $ApplyLocalizationToControls
    }.GetNewClosure()

    $ApplySelectedLanguage = {
        $language = & $GetUiLanguageSelection
        $null = Initialize-WinQStepLocalization $language
        & $ApplyLocalizationToControls
        & $SetUiLanguageSelection $language
    }.GetNewClosure()

    $TestIsExistingInputMode = {
        return [bool]$controls["ExistingInputModeRadio"].IsChecked
    }.GetNewClosure()

    $UpdateModeControls = {
        $isExistingInputMode = & $TestIsExistingInputMode
        foreach ($name in @("TemplatePathBox", "BrowseTemplateButton", "StructurePathBox", "BrowseStructureButton", "ProjectNameBox")) {
            $controls[$name].IsEnabled = -not $isExistingInputMode
        }
        foreach ($name in @("ExistingInputPathBox", "BrowseExistingInputButton")) {
            $controls[$name].IsEnabled = $isExistingInputMode
        }
        $controls["ImportButton"].IsEnabled = -not $isExistingInputMode
    }.GetNewClosure()

    $UpdateArtifactControls = {
        $current = $artifactState["Current"]
        foreach ($entry in $artifactButtons.GetEnumerator()) {
            $enabled = $false
            if ($null -ne $current -and $null -ne $current["paths"]) {
                $path = [string]$current["paths"][$entry.Key]
                $enabled = (-not [string]::IsNullOrWhiteSpace($path)) -and [System.IO.File]::Exists($path)
            }
            $entry.Value.IsEnabled = $enabled
        }
        $hasResultText = (
            $null -ne $current -and
            $null -ne $current["result_text"] -and
            -not [string]::IsNullOrWhiteSpace([string]$current["result_text"])
        )
        foreach ($button in $resultButtons) {
            $button.IsEnabled = $hasResultText
        }
    }.GetNewClosure()

    $SetBusy = {
        param([bool]$IsBusy, [string]$Status)
        $controls["StatusText"].Text = $Status
        foreach ($button in $actionButtons) {
            $button.IsEnabled = -not $IsBusy
        }
        $window.Cursor = if ($IsBusy) { [System.Windows.Input.Cursors]::Wait } else { $null }
        if (-not $IsBusy) {
            & $UpdateModeControls
            & $UpdateArtifactControls
        }
        [System.Windows.Forms.Application]::DoEvents()
    }.GetNewClosure()

    $AppendLog = {
        param([string]$Text)
        if ([string]::IsNullOrWhiteSpace($controls["LogText"].Text)) {
            $controls["LogText"].Text = $Text
        }
        else {
            $controls["LogText"].AppendText("`r`n$Text")
        }
        $controls["LogText"].ScrollToEnd()
    }.GetNewClosure()

    $InvokeGuiAction = {
        param(
            [Parameter(Mandatory = $true)][string]$Status,
            [Parameter(Mandatory = $true)][scriptblock]$Action
        )
        & $SetBusy $true $Status
        try {
            & $Action
        }
        catch {
            $message = $_.Exception.Message
            & $AppendLog "ERROR: $message"
            if ($SuppressGuiMessageBoxes) {
                throw
            }
            [System.Windows.MessageBox]::Show(
                $window,
                $message,
                (Get-WinQStepText "message.error_caption"),
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            ) | Out-Null
        }
        finally {
            & $SetBusy $false (Get-WinQStepText "status.ready")
        }
    }.GetNewClosure()

    $SelectFilePath = {
        param([Parameter(Mandatory = $true)]$TextBox, [Parameter(Mandatory = $true)][string]$Filter)
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Filter = $Filter
        if ([System.IO.File]::Exists($TextBox.Text)) {
            $dialog.InitialDirectory = Split-Path -Parent $TextBox.Text
        }
        if ($dialog.ShowDialog($window)) {
            $TextBox.Text = $dialog.FileName
        }
    }.GetNewClosure()

    $SelectFolderPath = {
        param([Parameter(Mandatory = $true)]$TextBox)
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        if ([System.IO.Directory]::Exists($TextBox.Text)) {
            $dialog.SelectedPath = $TextBox.Text
        }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $TextBox.Text = $dialog.SelectedPath
        }
    }.GetNewClosure()

    $GetWorkflowArguments = {
        param([bool]$PrepareOnly)
        $arguments = @(
            "scripts\run_workflow.py",
            "--config", $controls["ConfigPathBox"].Text,
            "--template", $controls["TemplatePathBox"].Text,
            "--structure", $controls["StructurePathBox"].Text,
            "--job-dir", $controls["JobDirBox"].Text,
            "--project-name", $controls["ProjectNameBox"].Text
        )
        if ($PrepareOnly) {
            $arguments += "--prepare-only"
        }
        return $arguments
    }.GetNewClosure()

    $GetExistingInputArgumentsForPath = {
        param(
            [Parameter(Mandatory = $true)][string]$InputPath,
            [bool]$PrepareOnly
        )
        $arguments = @(
            "scripts\run_existing_input.py",
            "--config", $controls["ConfigPathBox"].Text,
            "--input", $InputPath,
            "--job-dir", $controls["JobDirBox"].Text
        )
        if ($PrepareOnly) {
            $arguments += "--prepare-only"
        }
        return $arguments
    }.GetNewClosure()

    $GetExistingInputArguments = {
        param([bool]$PrepareOnly)
        return (& $GetExistingInputArgumentsForPath $controls["ExistingInputPathBox"].Text $PrepareOnly)
    }.GetNewClosure()

    $GetActiveJobArguments = {
        param([bool]$PrepareOnly)
        if (& $TestIsExistingInputMode) {
            return (& $GetExistingInputArguments $PrepareOnly)
        }
        return (& $GetWorkflowArguments $PrepareOnly)
    }.GetNewClosure()

    $GetActiveInputPreviewPath = {
        param([Parameter(Mandatory = $true)]$Metadata)
        return [string]$Metadata.files.input.path
    }.GetNewClosure()

    $ClearInputPreviewState = {
        $previewState["Current"] = $null
    }.GetNewClosure()

    $SetInputPreviewState = {
        param(
            [Parameter(Mandatory = $true)]$Metadata,
            [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
            [Parameter(Mandatory = $true)][string]$SourceMode
        )
        $previewState["Current"] = [ordered]@{
            InputPath = (& $GetActiveInputPreviewPath $Metadata)
            Text = $Text
            SourceMode = $SourceMode
        }
    }.GetNewClosure()

    $FormatLogWithSummary = {
        param([Parameter(Mandatory = $true)]$Metadata, [Parameter(Mandatory = $true)][string]$Output)
        $summaryText = Format-Cp2kSummary $Metadata
        if ([string]::IsNullOrWhiteSpace($summaryText)) {
            return $Output
        }
        return "$summaryText`r`n`r`n$Output"
    }.GetNewClosure()

    $jobState = @{ Current = $null }
    $jobTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $jobTimer.Interval = [TimeSpan]::FromSeconds(1)

    $SetJobStatusText = {
        param([string]$Text)
        $controls["JobStatusText"].Text = $Text
        $controls["JobStatusText"].ToolTip = $Text
    }.GetNewClosure()

    $FormatRunningJobStatus = {
        param([Parameter(Mandatory = $true)][hashtable]$State)
        $process = [System.Diagnostics.Process]$State["Process"]
        return "Running PID $($process.Id) | job=$($State["JobDir"]) | output=$($State["OutputPath"])"
    }.GetNewClosure()

    $FormatFinishedJobStatus = {
        param([Parameter(Mandatory = $true)]$Metadata, [string]$FallbackStatus)
        $status = $FallbackStatus
        if ($null -ne $Metadata.PSObject.Properties["status"] -and $null -ne $Metadata.status) {
            $status = [string]$Metadata.status
        }
        $outputPath = ""
        if ($null -ne $Metadata.files -and $null -ne $Metadata.files.output -and $null -ne $Metadata.files.output.PSObject.Properties["path"]) {
            $outputPath = [string]$Metadata.files.output.path
        }
        if ([string]::IsNullOrWhiteSpace($outputPath)) {
            return "Last job: status=$status"
        }
        return "Last job: status=$status | output=$outputPath"
    }.GetNewClosure()

    $SetAsyncJobRunning = {
        param([bool]$IsRunning, [string]$Status)
        $controls["StatusText"].Text = $Status
        foreach ($button in $actionButtons) {
            $button.IsEnabled = -not $IsRunning
        }
        $controls["CancelJobButton"].IsEnabled = $IsRunning
        $window.Cursor = $null
        if (-not $IsRunning) {
            & $UpdateModeControls
            & $UpdateArtifactControls
        }
        else {
            foreach ($button in $artifactButtons.Values) {
                $button.IsEnabled = $false
            }
        }
        [System.Windows.Forms.Application]::DoEvents()
    }.GetNewClosure()

    $AddTailSection = {
        param(
            [string[]]$Sections,
            [string]$Title,
            [string]$Path,
            [int]$LineCount = 80
        )
        $tail = Get-WinQStepFileTail $Path $LineCount
        if ([string]::IsNullOrWhiteSpace($tail)) {
            return $Sections
        }
        return @($Sections + "--- $Title ---`r`n$tail")
    }.GetNewClosure()

    $ReadMetadataFile = {
        param([string]$MetadataPath)
        $text = Read-WinQStepFileText $MetadataPath
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $null
        }
        try {
            return ($text | ConvertFrom-Json)
        }
        catch {
            return $null
        }
    }.GetNewClosure()

    $BuildAsyncJobLog = {
        param([Parameter(Mandatory = $true)][hashtable]$State)
        $process = [System.Diagnostics.Process]$State["Process"]
        $sections = @(
            "CP2K job running asynchronously.`r`nPID=$($process.Id)`r`njob_dir=$($State["JobDir"])`r`ninput=$($State["InputPath"])`r`noutput=$($State["OutputPath"])`r`nmetadata=$($State["MetadataPath"])`r`nwrapper_stdout=$($State["WrapperStdoutPath"])`r`nwrapper_stderr=$($State["WrapperStderrPath"])"
        )

        $metadata = & $ReadMetadataFile ([string]$State["MetadataPath"])
        if ($null -ne $metadata) {
            $summaryText = Format-Cp2kSummary $metadata
            if (-not [string]::IsNullOrWhiteSpace($summaryText)) {
                $sections += $summaryText
            }
            $sections += "metadata status=$($metadata.status), returncode=$($metadata.returncode)"
        }

        $sections = & $AddTailSection $sections "CP2K output tail" ([string]$State["OutputPath"]) 80
        $sections = & $AddTailSection $sections "CP2K stdout tail" ([string]$State["JobStdoutPath"]) 60
        $sections = & $AddTailSection $sections "CP2K stderr tail" ([string]$State["JobStderrPath"]) 60
        $sections = & $AddTailSection $sections "wrapper stderr tail" ([string]$State["WrapperStderrPath"]) 40
        return ($sections -join "`r`n`r`n")
    }.GetNewClosure()

    $AddMetadataTails = {
        param([string]$LogText, [Parameter(Mandatory = $true)]$Metadata)
        $sections = @($LogText)
        if ($null -ne $Metadata.files) {
            $sections = & $AddTailSection $sections "CP2K output tail" ([string]$Metadata.files.output.path) 80
            $sections = & $AddTailSection $sections "CP2K stdout tail" ([string]$Metadata.files.stdout.path) 60
            $sections = & $AddTailSection $sections "CP2K stderr tail" ([string]$Metadata.files.stderr.path) 60
        }
        return ($sections -join "`r`n`r`n")
    }.GetNewClosure()

    $GetJsonProperty = {
        param($Object, [Parameter(Mandatory = $true)][string]$Name, [string]$Default = "")
        if ($null -eq $Object) {
            return $Default
        }
        $property = $Object.PSObject.Properties[$Name]
        if ($null -eq $property -or $null -eq $property.Value) {
            return $Default
        }
        return [string]$property.Value
    }.GetNewClosure()

    $GetJsonVectorText = {
        param($Object, [Parameter(Mandatory = $true)][string]$Name, [string]$Default = "")
        if ($null -eq $Object) {
            return $Default
        }
        $property = $Object.PSObject.Properties[$Name]
        if ($null -eq $property -or $null -eq $property.Value) {
            return $Default
        }
        $value = $property.Value
        if ($value -is [string]) {
            return $value
        }
        $items = @($value)
        if ($items.Count -eq 3) {
            return (($items | ForEach-Object {
                try {
                    "{0:g}" -f [double]$_
                }
                catch {
                    [string]$_
                }
            }) -join " ")
        }
        return [string]$value
    }.GetNewClosure()

    $GetNestedPath = {
        param($Object, [Parameter(Mandatory = $true)][string[]]$Names)
        $current = $Object
        foreach ($name in $Names) {
            if ($null -eq $current) {
                return ""
            }
            $property = $current.PSObject.Properties[$name]
            if ($null -eq $property -or $null -eq $property.Value) {
                return ""
            }
            $current = $property.Value
        }
        return [string]$current
    }.GetNewClosure()

    $GetNestedValue = {
        param($Object, [Parameter(Mandatory = $true)][string[]]$Names)
        $current = $Object
        foreach ($name in $Names) {
            if ($null -eq $current) {
                return $null
            }
            $property = $current.PSObject.Properties[$name]
            if ($null -eq $property -or $null -eq $property.Value) {
                return $null
            }
            $current = $property.Value
        }
        return $current
    }.GetNewClosure()

    $GetMetadataFilePath = {
        param($Metadata, [Parameter(Mandatory = $true)][string]$Key)
        return (& $GetNestedPath $Metadata @("files", $Key, "path"))
    }.GetNewClosure()

    $FormatResultValue = {
        param($Value, [string]$Default = "not_available")
        if ($null -eq $Value) {
            return $Default
        }
        if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
            return [System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
        }
        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $Default
        }
        return $text
    }.GetNewClosure()

    $FormatStructureScalar = {
        param($Value, [string]$Default = "")
        if ($null -eq $Value) {
            return $Default
        }
        try {
            return [System.Convert]::ToString([double]$Value, [System.Globalization.CultureInfo]::InvariantCulture)
        }
        catch {
            $text = [string]$Value
            if ([string]::IsNullOrWhiteSpace($text)) {
                return $Default
            }
            return $text
        }
    }.GetNewClosure()

    $FormatStructureVector = {
        param($Value)
        if ($null -eq $Value) {
            return ""
        }
        $items = @($Value)
        if ($items.Count -eq 0) {
            return ""
        }
        return (($items | ForEach-Object { & $FormatStructureScalar $_ }) -join " ")
    }.GetNewClosure()

    $FormatStructureBoolList = {
        param($Value)
        if ($null -eq $Value) {
            return ""
        }
        $items = @($Value)
        if ($items.Count -eq 0) {
            return ""
        }
        return (($items | ForEach-Object { ([string]$_).ToLowerInvariant() }) -join " ")
    }.GetNewClosure()

    $FormatStructureImportDisplay = {
        param([Parameter(Mandatory = $true)]$Payload, [int]$AtomLimit = 200)

        $source = & $GetNestedValue $Payload @("source")
        $cell = & $GetNestedValue $Payload @("cell")
        $atomsValue = & $GetNestedValue $Payload @("atoms")
        $atoms = if ($null -ne $atomsValue) { @($atomsValue) } else { @() }

        $elementCounts = @{}
        foreach ($atom in $atoms) {
            $element = (& $GetNestedPath $atom @("element")).Trim()
            if ([string]::IsNullOrWhiteSpace($element)) {
                $element = "?"
            }
            if ($elementCounts.ContainsKey($element)) {
                $elementCounts[$element] = [int]$elementCounts[$element] + 1
            }
            else {
                $elementCounts[$element] = 1
            }
        }
        $elementSummary = if ($elementCounts.Count -gt 0) {
            (($elementCounts.Keys | Sort-Object | ForEach-Object { "$_=$($elementCounts[$_])" }) -join ", ")
        }
        else {
            "not_available"
        }

        $lines = @(
            "Imported structure",
            "Source: $(& $GetJsonProperty $source "path")",
            "Format: $(& $GetJsonProperty $source "format")",
            "Reader: $(& $GetJsonProperty $source "reader")",
            "Atoms: $($atoms.Count)",
            "Elements: $elementSummary",
            "",
            "Cell",
            "Periodic: $(& $GetJsonProperty $cell "periodic")",
            "PBC: $(& $FormatStructureBoolList (& $GetNestedValue $cell @("pbc")))",
            "A: $(& $FormatStructureVector (& $GetNestedValue $cell @("a")))",
            "B: $(& $FormatStructureVector (& $GetNestedValue $cell @("b")))",
            "C: $(& $FormatStructureVector (& $GetNestedValue $cell @("c")))",
            "",
            "Atoms (cartesian coordinates, Angstrom)"
        )

        if ($atoms.Count -gt $AtomLimit) {
            $lines += "Showing first $AtomLimit of $($atoms.Count) atoms."
        }
        $lines += ("{0,6} {1,-8} {2,14} {3,14} {4,14}" -f "#", "Element", "X", "Y", "Z")
        $index = 0
        foreach ($atom in @($atoms | Select-Object -First $AtomLimit)) {
            $index += 1
            $element = (& $GetNestedPath $atom @("element")).Trim()
            $xyz = @(& $GetNestedValue $atom @("xyz"))
            $x = if ($xyz.Count -gt 0) { & $FormatStructureScalar $xyz[0] } else { "" }
            $y = if ($xyz.Count -gt 1) { & $FormatStructureScalar $xyz[1] } else { "" }
            $z = if ($xyz.Count -gt 2) { & $FormatStructureScalar $xyz[2] } else { "" }
            $lines += ("{0,6} {1,-8} {2,14} {3,14} {4,14}" -f $index, $element, $x, $y, $z)
        }
        return ($lines -join "`r`n")
    }.GetNewClosure()

    $BuildArtifactSummary = {
        param([Parameter(Mandatory = $true)][hashtable]$Artifacts)
        $lines = @(
            "status=$($Artifacts["status"])",
            "returncode=$($Artifacts["returncode"])",
            "cp2k_output=$($Artifacts["output_status"]), warnings=$($Artifacts["warning_count"]), program_ended=$($Artifacts["program_ended"])"
        )
        if (-not [string]::IsNullOrWhiteSpace([string]$Artifacts["ended_at"])) {
            $lines += "ended_at=$($Artifacts["ended_at"])"
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$Artifacts["total_energy_hartree"])) {
            $lines += "energy_hartree=$($Artifacts["total_energy_hartree"])"
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$Artifacts["total_atomic_force"])) {
            $forceUnit = [string]$Artifacts["force_unit"]
            $suffix = if ([string]::IsNullOrWhiteSpace($forceUnit)) { "" } else { " $forceUnit" }
            $lines += "total_atomic_force=$($Artifacts["total_atomic_force"])$suffix"
        }
        foreach ($key in @("input", "output", "metadata", "stdout", "stderr")) {
            $path = [string]$Artifacts["paths"][$key]
            $exists = if (-not [string]::IsNullOrWhiteSpace($path) -and [System.IO.File]::Exists($path)) { "exists" } else { "missing" }
            $lines += "$key=[$exists] $path"
        }
        if ($Artifacts["paths"].ContainsKey("results")) {
            $path = [string]$Artifacts["paths"]["results"]
            if (-not [string]::IsNullOrWhiteSpace($path)) {
                $exists = if ([System.IO.File]::Exists($path)) { "exists" } else { "missing" }
                $lines += "results=[$exists] $path"
            }
        }
        return ($lines -join "`r`n")
    }.GetNewClosure()

    $BuildResultSummaryFromMetadata = {
        param([Parameter(Mandatory = $true)]$Metadata)
        $summary = $Metadata.cp2k_output
        $jobMode = & $GetNestedPath $Metadata @("job", "mode")
        $projectName = & $GetNestedPath $Metadata @("quickstep", "project_name")
        if ([string]::IsNullOrWhiteSpace($projectName)) {
            $projectName = & $GetNestedPath $Metadata @("workflow", "template", "project_name")
        }
        if ([string]::IsNullOrWhiteSpace($projectName)) {
            $projectName = & $GetNestedPath $Metadata @("job", "input_stem")
        }
        $runType = & $GetNestedPath $Metadata @("quickstep", "run_type")
        if ([string]::IsNullOrWhiteSpace($runType)) {
            $runType = & $GetNestedPath $Metadata @("workflow", "template", "run_type")
        }
        $lines = @(
            "Result summary",
            "status=$(& $FormatResultValue (& $GetNestedValue $Metadata @("status")))",
            "returncode=$(& $FormatResultValue (& $GetNestedValue $Metadata @("returncode")))",
            "mode=$(& $FormatResultValue $jobMode)",
            "project=$(& $FormatResultValue $projectName)",
            "run_type=$(& $FormatResultValue $runType)",
            "cp2k_output.status=$(& $FormatResultValue (& $GetNestedValue $summary @("status")))",
            "warnings=$(& $FormatResultValue (& $GetNestedValue $summary @("warning_count")))",
            "program_ended=$(& $FormatResultValue (& $GetNestedValue $summary @("program_ended")))",
            "ended_at=$(& $FormatResultValue (& $GetNestedValue $summary @("ended_at")))",
            "stopped_in=$(& $FormatResultValue (& $GetNestedValue $summary @("stopped_in")))",
            "total_energy_hartree=$(& $FormatResultValue (& $GetNestedValue $summary @("total_energy_hartree")))",
            "input=$(& $FormatResultValue (& $GetMetadataFilePath $Metadata "input"))",
            "output=$(& $FormatResultValue (& $GetMetadataFilePath $Metadata "output"))",
            "metadata=$(& $FormatResultValue (& $GetMetadataFilePath $Metadata "metadata"))"
        )

        $forces = & $GetNestedValue $summary @("forces")
        if ($null -eq $forces) {
            $lines += "forces=not_available"
            return ($lines -join "`r`n")
        }

        $unit = & $FormatResultValue (& $GetNestedValue $forces @("unit")) ""
        $totalAtomicForce = & $GetNestedValue $forces @("total_atomic_force")
        $totalText = & $FormatResultValue $totalAtomicForce
        if ([string]::IsNullOrWhiteSpace($unit)) {
            $lines += "total_atomic_force=$totalText"
        }
        else {
            $lines += "total_atomic_force=$totalText $unit"
        }

        $atoms = @()
        $atomsValue = & $GetNestedValue $forces @("atoms")
        if ($null -ne $atomsValue) {
            $atoms = @($atomsValue)
        }
        if ($atoms.Count -gt 0) {
            $headerUnit = if ([string]::IsNullOrWhiteSpace($unit)) { "" } else { " ($unit)" }
            $lines += ""
            $lines += "Forces$headerUnit"
            $lines += ("{0,6} {1,18} {2,18} {3,18} {4,18}" -f "atom", "x", "y", "z", "|f|")
            foreach ($atom in $atoms) {
                $lines += (
                    "{0,6} {1,18} {2,18} {3,18} {4,18}" -f
                    (& $FormatResultValue (& $GetNestedValue $atom @("atom")) ""),
                    (& $FormatResultValue (& $GetNestedValue $atom @("x")) ""),
                    (& $FormatResultValue (& $GetNestedValue $atom @("y")) ""),
                    (& $FormatResultValue (& $GetNestedValue $atom @("z")) ""),
                    (& $FormatResultValue (& $GetNestedValue $atom @("norm")) "")
                )
            }
        }
        $forceSum = & $GetNestedValue $forces @("sum")
        if ($null -ne $forceSum) {
            $lines += (
                "{0,6} {1,18} {2,18} {3,18} {4,18}" -f
                "Sum",
                (& $FormatResultValue (& $GetNestedValue $forceSum @("x")) ""),
                (& $FormatResultValue (& $GetNestedValue $forceSum @("y")) ""),
                (& $FormatResultValue (& $GetNestedValue $forceSum @("z")) ""),
                ""
            )
        }
        return ($lines -join "`r`n")
    }.GetNewClosure()

    $BuildResultSummaryFromArtifacts = {
        param([Parameter(Mandatory = $true)][hashtable]$Artifacts)
        $energyText = & $FormatResultValue ($Artifacts["total_energy_hartree"])
        $forceText = & $FormatResultValue ($Artifacts["total_atomic_force"])
        $forceUnit = [string]$Artifacts["force_unit"]
        if (-not [string]::IsNullOrWhiteSpace($forceUnit)) {
            $forceText = "$forceText $forceUnit"
        }
        $lines = @(
            "Result summary",
            "status=$($Artifacts["status"])",
            "returncode=$($Artifacts["returncode"])",
            "mode=$($Artifacts["mode"])",
            "project=$($Artifacts["project_name"])",
            "run_type=$($Artifacts["run_type"])",
            "cp2k_output.status=$($Artifacts["output_status"])",
            "warnings=$($Artifacts["warning_count"])",
            "program_ended=$($Artifacts["program_ended"])",
            "total_energy_hartree=$energyText",
            "total_atomic_force=$forceText",
            "input=$($Artifacts["paths"]["input"])",
            "output=$($Artifacts["paths"]["output"])",
            "metadata=$($Artifacts["paths"]["metadata"])"
        )
        return ($lines -join "`r`n")
    }.GetNewClosure()

    $SetArtifactsFromMetadata = {
        param([Parameter(Mandatory = $true)]$Metadata)
        $summary = $Metadata.cp2k_output
        $forces = & $GetNestedValue $summary @("forces")
        $forceUnit = if ($null -ne $forces) { & $GetNestedPath $forces @("unit") } else { "" }
        $totalAtomicForce = if ($null -ne $forces) { & $FormatResultValue (& $GetNestedValue $forces @("total_atomic_force")) "" } else { "" }
        $artifacts = @{
            status = (& $GetJsonProperty $Metadata "status" "")
            returncode = (& $GetJsonProperty $Metadata "returncode" "")
            mode = (& $GetNestedPath $Metadata @("job", "mode"))
            project_name = (& $GetNestedPath $Metadata @("quickstep", "project_name"))
            run_type = (& $GetNestedPath $Metadata @("quickstep", "run_type"))
            output_status = (& $GetJsonProperty $summary "status" "")
            warning_count = (& $GetJsonProperty $summary "warning_count" "")
            program_ended = (& $GetJsonProperty $summary "program_ended" "")
            ended_at = (& $GetJsonProperty $summary "ended_at" "")
            total_energy_hartree = (& $FormatResultValue (& $GetNestedValue $summary @("total_energy_hartree")) "")
            total_atomic_force = $totalAtomicForce
            force_unit = $forceUnit
            paths = @{
                input = (& $GetMetadataFilePath $Metadata "input")
                output = (& $GetMetadataFilePath $Metadata "output")
                metadata = (& $GetMetadataFilePath $Metadata "metadata")
                stdout = (& $GetMetadataFilePath $Metadata "stdout")
                stderr = (& $GetMetadataFilePath $Metadata "stderr")
            }
            result_text = (& $BuildResultSummaryFromMetadata $Metadata)
        }
        if ([string]::IsNullOrWhiteSpace([string]$artifacts["project_name"])) {
            $artifacts["project_name"] = (& $GetNestedPath $Metadata @("workflow", "template", "project_name"))
        }
        if ([string]::IsNullOrWhiteSpace([string]$artifacts["run_type"])) {
            $artifacts["run_type"] = (& $GetNestedPath $Metadata @("workflow", "template", "run_type"))
        }
        $artifactState["Current"] = $artifacts
        $controls["ArtifactSummaryText"].Text = & $BuildArtifactSummary $artifacts
        & $UpdateArtifactControls
        & $SetJobStatusText (& $FormatFinishedJobStatus $Metadata ([string]$artifacts["status"]))
    }.GetNewClosure()

    $CompleteAsyncJob = {
        param([Parameter(Mandatory = $true)][hashtable]$State)
        $jobTimer.Stop()
        $process = [System.Diagnostics.Process]$State["Process"]
        $process.Refresh()
        $exitCode = if ($process.HasExited) { [int]$process.ExitCode } else { $null }
        $captured = Save-WinQStepProcessOutput $process ([string]$State["WrapperStdoutPath"]) ([string]$State["WrapperStderrPath"])
        $stdout = [string]$captured.Stdout
        $stderr = [string]$captured.Stderr
        $metadata = $null
        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            try {
                $metadata = ($stdout | ConvertFrom-Json)
            }
            catch {
                $metadata = $null
            }
        }

        if ([bool]$State["Cancelled"] -and [System.IO.File]::Exists([string]$State["MetadataPath"])) {
            $cancelArgs = @(
                "scripts\mark_job_cancelled.py",
                "--metadata", [string]$State["MetadataPath"],
                "--stdout-file", [string]$State["WrapperStdoutPath"],
                "--stderr-file", [string]$State["WrapperStderrPath"],
                "--compact"
            )
            if ($null -ne $exitCode) {
                $cancelArgs += @("--returncode", [string]$exitCode)
            }
            $cancelResult = Invoke-WinQStepPython $cancelArgs
            if ($cancelResult.ExitCode -eq 0) {
                $metadata = Get-JsonResult $cancelResult
            }
            else {
                $stderr = (($stderr, $cancelResult.Output) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n"
            }
        }

        if ($null -eq $metadata) {
            $metadata = & $ReadMetadataFile ([string]$State["MetadataPath"])
        }

        if ($null -ne $metadata) {
            $finalStatus = if ([bool]$State["Cancelled"]) { Get-WinQStepText "status.cancelled" } elseif ($exitCode -eq 0) { Get-WinQStepText "status.ready" } else { Get-WinQStepText "status.finished_with_errors" }
            $logText = & $FormatLogWithSummary $metadata $stdout
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                $logText = "$logText`r`n`r`n--- wrapper stderr ---`r`n$stderr"
            }
            $controls["LogText"].Text = & $AddMetadataTails $logText $metadata
            & $SetArtifactsFromMetadata $metadata
        }
        else {
            $parts = @("CP2K wrapper exited without JSON metadata. exit_code=$exitCode")
            if (-not [string]::IsNullOrWhiteSpace($stdout)) {
                $parts += "--- wrapper stdout ---`r`n$stdout"
            }
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                $parts += "--- wrapper stderr ---`r`n$stderr"
            }
            $controls["LogText"].Text = ($parts -join "`r`n`r`n")
            $finalStatus = if ([bool]$State["Cancelled"]) { Get-WinQStepText "status.cancelled" } else { Get-WinQStepText "status.finished_with_errors" }
            & $SetJobStatusText "Last job: status=$finalStatus | metadata=$($State["MetadataPath"])"
        }

        $controls["LogText"].ScrollToEnd()
        $jobState["Current"] = $null
        & $SetAsyncJobRunning $false $finalStatus
    }.GetNewClosure()

    $RefreshAsyncJob = {
        $current = $jobState["Current"]
        if ($null -eq $current) {
            $jobTimer.Stop()
            return
        }

        $process = [System.Diagnostics.Process]$current["Process"]
        if ($process.HasExited) {
            & $CompleteAsyncJob $current
            return
        }

        & $SetJobStatusText (& $FormatRunningJobStatus $current)
        $controls["LogText"].Text = & $BuildAsyncJobLog $current
        $controls["LogText"].ScrollToEnd()
    }.GetNewClosure()

    $jobTimer.Add_Tick({
        try {
            & $RefreshAsyncJob
        }
        catch {
            $jobTimer.Stop()
            $jobState["Current"] = $null
            $message = $_.Exception.Message
            & $AppendLog "ERROR: async job refresh failed: $message"
            & $SetAsyncJobRunning $false (Get-WinQStepText "status.finished_with_errors")
        }
    }.GetNewClosure())

    $SetArtifactsFromHistoryItem = {
        param([Parameter(Mandatory = $true)]$Item)
        $artifacts = @{
            status = (& $GetJsonProperty $Item "status" "")
            returncode = (& $GetJsonProperty $Item "returncode" "")
            mode = (& $GetJsonProperty $Item "mode" "")
            project_name = (& $GetJsonProperty $Item "project_name" "")
            run_type = (& $GetJsonProperty $Item "run_type" "")
            output_status = (& $GetJsonProperty $Item "output_status" "")
            warning_count = (& $GetJsonProperty $Item "warning_count" "")
            program_ended = (& $GetJsonProperty $Item "program_ended" "")
            ended_at = ""
            total_energy_hartree = (& $GetJsonProperty $Item "total_energy_hartree" "")
            total_atomic_force = (& $GetJsonProperty $Item "total_atomic_force" "")
            force_unit = (& $GetJsonProperty $Item "force_unit" "")
            paths = @{
                input = (& $GetJsonProperty $Item "input_path" "")
                output = (& $GetJsonProperty $Item "output_path" "")
                metadata = (& $GetJsonProperty $Item "metadata_path" "")
                stdout = (& $GetJsonProperty $Item "stdout_path" "")
                stderr = (& $GetJsonProperty $Item "stderr_path" "")
            }
        }
        $artifacts["result_text"] = & $BuildResultSummaryFromArtifacts $artifacts
        $artifactState["Current"] = $artifacts
        $controls["ArtifactSummaryText"].Text = & $BuildArtifactSummary $artifacts
        & $UpdateArtifactControls
        & $SetJobStatusText "Selected job: status=$($artifacts["status"]) | output=$($artifacts["paths"]["output"])"
    }.GetNewClosure()

    $ReadMetadataArtifact = {
        param([string]$MetadataPath)
        if ([string]::IsNullOrWhiteSpace($MetadataPath) -or -not [System.IO.File]::Exists($MetadataPath)) {
            return $null
        }
        try {
            return ([System.IO.File]::ReadAllText($MetadataPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
        }
        catch {
            return $null
        }
    }.GetNewClosure()

    $ViewResultSummary = {
        $current = $artifactState["Current"]
        if ($null -eq $current -or [string]::IsNullOrWhiteSpace([string]$current["result_text"])) {
            throw "No result summary is available."
        }
        $path = ""
        if ($null -ne $current["paths"] -and $current["paths"].ContainsKey("results")) {
            $path = [string]$current["paths"]["results"]
        }
        $title = if ([string]::IsNullOrWhiteSpace($path)) { "current job" } else { $path }
        $text = [string]$current["result_text"]
        $controls["ArtifactText"].Text = "--- results: $title ---`r`n$text"
        $controls["LogText"].Text = $text
    }.GetNewClosure()

    $GetResultSummaryPath = {
        param([Parameter(Mandatory = $true)][hashtable]$Current)
        $paths = $Current["paths"]
        $candidate = ""
        foreach ($key in @("metadata", "output", "input")) {
            if ($null -ne $paths -and $paths.ContainsKey($key)) {
                $candidate = [string]$paths[$key]
                if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                    break
                }
            }
        }
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            $jobDir = & $ResolveWindowsWorkspacePath $controls["JobDirBox"].Text
            [System.IO.Directory]::CreateDirectory($jobDir) | Out-Null
            return (Join-Path $jobDir "winqstep.results.txt")
        }
        $parent = Split-Path -Parent $candidate
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = & $ResolveWindowsWorkspacePath $controls["JobDirBox"].Text
        }
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($candidate)
        if ($stem.EndsWith(".winqstep", [System.StringComparison]::OrdinalIgnoreCase)) {
            $stem = $stem.Substring(0, $stem.Length - ".winqstep".Length)
        }
        if ([string]::IsNullOrWhiteSpace($stem)) {
            $stem = "winqstep"
        }
        return (Join-Path $parent "$stem.results.txt")
    }.GetNewClosure()

    $SaveResultSummary = {
        $current = $artifactState["Current"]
        if ($null -eq $current -or [string]::IsNullOrWhiteSpace([string]$current["result_text"])) {
            throw "No result summary is available."
        }
        $path = & $GetResultSummaryPath $current
        $text = [string]$current["result_text"]
        $encoding = $Script:Utf8NoBomEncoding
        if ($null -eq $encoding) {
            $encoding = New-Object System.Text.UTF8Encoding($false)
        }
        [System.IO.File]::WriteAllText($path, ($text + "`r`n"), $encoding)
        $current["paths"]["results"] = $path
        $artifactState["Current"] = $current
        $controls["ArtifactSummaryText"].Text = & $BuildArtifactSummary $current
        $controls["ArtifactText"].Text = "--- results: $path ---`r`n$text"
        $controls["LogText"].Text = "Saved result summary: $path`r`n`r`n$text"
        & $UpdateArtifactControls
        return $path
    }.GetNewClosure()

    $ViewArtifact = {
        param([Parameter(Mandatory = $true)][string]$Key)
        $current = $artifactState["Current"]
        if ($null -eq $current -or $null -eq $current["paths"]) {
            throw "No job artifact is selected."
        }
        $path = [string]$current["paths"][$Key]
        if ([string]::IsNullOrWhiteSpace($path) -or -not [System.IO.File]::Exists($path)) {
            throw "Artifact is not available: $Key"
        }
        $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        $controls["ArtifactText"].Text = "--- ${Key}: $path ---`r`n$text"
        if ($Key -in @("input", "output")) {
            & $ClearInputPreviewState
            $controls["PreviewText"].Text = $text
        }
        else {
            $controls["LogText"].Text = $text
        }
    }.GetNewClosure()

    $FormatConfigValidation = {
        param([Parameter(Mandatory = $true)]$Payload)
        $validation = $Payload.validation
        $lines = @()
        if ($null -ne $validation -and [bool]$validation.valid) {
            $lines += "Config valid"
        }
        else {
            $lines += "Config invalid"
        }
        if ($null -ne $validation -and $null -ne $validation.errors) {
            foreach ($errorText in @($validation.errors)) {
                $lines += "ERROR: $errorText"
            }
        }
        if ($null -ne $validation -and $null -ne $validation.warnings) {
            foreach ($warningText in @($validation.warnings)) {
                $lines += "WARNING: $warningText"
            }
        }
        return ($lines -join "`r`n")
    }.GetNewClosure()

    $ResolveWindowsWorkspacePath = {
        param([AllowEmptyString()][string]$Workspace)
        if ([string]::IsNullOrWhiteSpace($Workspace)) {
            return ""
        }
        if ([System.IO.Path]::IsPathRooted($Workspace)) {
            return [System.IO.Path]::GetFullPath($Workspace)
        }
        return Resolve-WinQStepPath $Workspace
    }.GetNewClosure()

    $SetConfigFieldsFromPayload = {
        param(
            [Parameter(Mandatory = $true)]$Payload,
            [bool]$UpdateJobDirFromWorkspace = $true
        )
        $config = $Payload.config
        $controls["DistroBox"].Text = & $GetJsonProperty $config "distro"
        $controls["Cp2kCommandBox"].Text = & $GetJsonProperty $config "cp2k_command"
        $controls["Cp2kDataDirBox"].Text = & $GetJsonProperty $config "cp2k_data_dir"
        $controls["MpirunCommandBox"].Text = & $GetJsonProperty $config "mpirun_command"
        $controls["DefaultWorkspaceBox"].Text = & $GetJsonProperty $config "default_windows_workspace"
        $controls["WslPreludeBox"].Text = & $GetJsonProperty $config "wsl_shell_prelude"
        $controls["TimeoutBox"].Text = & $GetJsonProperty $config "timeout"
        $uiLanguage = & $GetJsonProperty $config "ui_language"
        & $SetUiLanguageSelection $uiLanguage
        & $ApplyConfiguredLanguage $uiLanguage
        $workspace = $controls["DefaultWorkspaceBox"].Text
        if ($UpdateJobDirFromWorkspace -and -not [string]::IsNullOrWhiteSpace($workspace)) {
            $controls["JobDirBox"].Text = & $ResolveWindowsWorkspacePath $workspace
        }
        $controls["ConfigValidationText"].Text = & $FormatConfigValidation $Payload
    }.GetNewClosure()

    $ReadConfigManagerResult = {
        param(
            [Parameter(Mandatory = $true)]$Result,
            [bool]$UpdateJobDirFromWorkspace = $true
        )
        try {
            $payload = $Result.Output | ConvertFrom-Json
        }
        catch {
            if ($Result.ExitCode -ne 0 -and -not [string]::IsNullOrWhiteSpace([string]$Result.Error)) {
                throw $Result.Error
            }
            $raw = [string]$Result.Output
            if (-not [string]::IsNullOrWhiteSpace([string]$Result.Error)) {
                $raw = (($raw, [string]$Result.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n"
            }
            throw "Command did not return JSON. Raw output:`n$raw"
        }
        if ($null -ne $payload.config) {
            & $SetConfigFieldsFromPayload $payload $UpdateJobDirFromWorkspace
        }
        if ($Result.ExitCode -ne 0) {
            throw (& $FormatConfigValidation $payload)
        }
        return $payload
    }.GetNewClosure()

    $GetConfigFieldsJson = {
        $fields = [ordered]@{
            distro = $controls["DistroBox"].Text
            cp2k_command = $controls["Cp2kCommandBox"].Text
            mpirun_command = $controls["MpirunCommandBox"].Text
            cp2k_data_dir = $controls["Cp2kDataDirBox"].Text
            default_windows_workspace = $controls["DefaultWorkspaceBox"].Text
            wsl_shell_prelude = $controls["WslPreludeBox"].Text
            ui_language = & $GetUiLanguageSelection
            timeout = $controls["TimeoutBox"].Text
        }
        return ($fields | ConvertTo-Json -Compress)
    }.GetNewClosure()

    $LoadConfigFields = {
        param([bool]$WriteLog)
        $result = Invoke-WinQStepPython @(
            "scripts\manage_config.py",
            "--config", $controls["ConfigPathBox"].Text,
            "--compact"
        )
        $payload = & $ReadConfigManagerResult $result $true
        if ($WriteLog) {
            $controls["LogText"].Text = $result.Output
        }
        return $payload
    }.GetNewClosure()

    $SaveConfigFields = {
        param([bool]$RequireExecution, [bool]$WriteLog)
        $arguments = @(
            "scripts\manage_config.py",
            "--config", $controls["ConfigPathBox"].Text,
            "--write",
            "--fields-json", (& $GetConfigFieldsJson),
            "--compact"
        )
        if ($RequireExecution) {
            $arguments += "--require-execution"
        }
        $result = Invoke-WinQStepPython $arguments
        $payload = & $ReadConfigManagerResult $result $false
        if ($WriteLog) {
            $controls["LogText"].Text = $result.Output
        }
        return $payload
    }.GetNewClosure()

    $FormatTemplateValidation = {
        param([Parameter(Mandatory = $true)]$Payload)
        $validation = $Payload.validation
        $lines = @()
        if ($null -ne $validation -and [bool]$validation.valid) {
            $lines += "Template valid"
        }
        else {
            $lines += "Template invalid"
        }
        if ($null -ne $validation -and $null -ne $validation.errors) {
            foreach ($errorText in @($validation.errors)) {
                $lines += "ERROR: $errorText"
            }
        }
        if ($null -ne $validation -and $null -ne $validation.warnings) {
            foreach ($warningText in @($validation.warnings)) {
                $lines += "WARNING: $warningText"
            }
        }
        return ($lines -join "`r`n")
    }.GetNewClosure()

    $NewKindEntriesTable = {
        $table = [System.Data.DataTable]::new()
        [void]$table.Columns.Add("element", [string])
        [void]$table.Columns.Add("basis_set", [string])
        [void]$table.Columns.Add("potential", [string])
        Write-Output -NoEnumerate $table
    }.GetNewClosure()

    $SetKindEntriesFromText = {
        param([string]$Text)
        $table = & $NewKindEntriesTable
        foreach ($line in @($Text -split "`r?`n")) {
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
                continue
            }
            $parts = @($trimmed -split "\s+")
            if ($parts.Count -lt 3) {
                continue
            }
            $row = $table.NewRow()
            $row["element"] = $parts[0]
            $row["basis_set"] = $parts[1]
            $row["potential"] = $parts[2]
            [void]$table.Rows.Add($row)
        }
        $controls["KindEntriesGrid"].ItemsSource = $table.DefaultView
    }.GetNewClosure()

    $GetKindEntriesText = {
        $lines = @()
        foreach ($rowView in @($controls["KindEntriesGrid"].ItemsSource)) {
            if ($null -eq $rowView -or $rowView.IsNew) {
                continue
            }
            $element = ([string]$rowView["element"]).Trim()
            $basis = ([string]$rowView["basis_set"]).Trim()
            $potential = ([string]$rowView["potential"]).Trim()
            if ([string]::IsNullOrWhiteSpace($element) -and [string]::IsNullOrWhiteSpace($basis) -and [string]::IsNullOrWhiteSpace($potential)) {
                continue
            }
            $lines += "$element $basis $potential"
        }
        return ($lines -join "`n")
    }.GetNewClosure()

    $SyncKindsTextFromGrid = {
        $text = & $GetKindEntriesText
        $controls["KindsText"].Text = $text
        return $text
    }.GetNewClosure()

    $SetTemplateFieldsFromPayload = {
        param([Parameter(Mandatory = $true)]$Payload)
        $template = $Payload.template
        $dft = $template.dft
        $geoOpt = $template.geo_opt
        $cellOpt = $template.cell_opt
        $structureTransform = $template.structure_transform
        $fallbackCell = $null
        if ($null -ne $structureTransform) {
            $fallbackCell = $structureTransform.fallback_cell
        }
        $controls["TemplateProjectBox"].Text = & $GetJsonProperty $template "project_name"
        $controls["TemplateRunTypeBox"].Text = & $GetJsonProperty $template "run_type"
        $controls["PrintLevelBox"].Text = & $GetJsonProperty $template "print_level"
        $controls["BasisSetFileBox"].Text = & $GetJsonProperty $dft "basis_set_file_name"
        $controls["PotentialFileBox"].Text = & $GetJsonProperty $dft "potential_file_name"
        $controls["XcFunctionalBox"].Text = & $GetJsonProperty $dft "xc_functional"
        $controls["ChargeBox"].Text = & $GetJsonProperty $dft "charge"
        $controls["MultiplicityBox"].Text = & $GetJsonProperty $dft "multiplicity"
        $controls["CutoffBox"].Text = & $GetJsonProperty $dft "cutoff"
        $controls["RelCutoffBox"].Text = & $GetJsonProperty $dft "rel_cutoff"
        $controls["EpsScfBox"].Text = & $GetJsonProperty $dft "eps_scf"
        $controls["MaxScfBox"].Text = & $GetJsonProperty $dft "max_scf"
        $controls["ScfMethodBox"].Text = & $GetJsonProperty $dft "scf_method"
        $controls["AddedMosBox"].Text = & $GetJsonProperty $dft "added_mos"
        $controls["DiagonalizationAlgorithmBox"].Text = & $GetJsonProperty $dft "diagonalization_algorithm"
        $controls["OtMinimizerBox"].Text = & $GetJsonProperty $dft "ot_minimizer"
        $controls["OtPreconditionerBox"].Text = & $GetJsonProperty $dft "ot_preconditioner"
        $controls["MixingEnabledBox"].IsChecked = @("1", "true", "yes", "on").Contains((& $GetJsonProperty $dft "mixing_enabled" "False").ToLowerInvariant())
        $controls["MixingMethodBox"].Text = & $GetJsonProperty $dft "mixing_method"
        $controls["MixingAlphaBox"].Text = & $GetJsonProperty $dft "mixing_alpha"
        $controls["MixingBetaBox"].Text = & $GetJsonProperty $dft "mixing_beta"
        $controls["SmearingEnabledBox"].IsChecked = @("1", "true", "yes", "on").Contains((& $GetJsonProperty $dft "smearing_enabled" "False").ToLowerInvariant())
        $controls["SmearingMethodBox"].Text = & $GetJsonProperty $dft "smearing_method"
        $controls["ElectronicTemperatureBox"].Text = & $GetJsonProperty $dft "electronic_temperature"
        $controls["KpointsSchemeBox"].Text = & $GetJsonProperty $dft "kpoints_scheme"
        $controls["KpointsGridBox"].Text = & $GetJsonVectorText $dft "kpoints_grid"
        $controls["KpointsFullGridBox"].IsChecked = @("1", "true", "yes", "on").Contains((& $GetJsonProperty $dft "kpoints_full_grid" "False").ToLowerInvariant())
        $controls["KpointsSymmetryBox"].IsChecked = @("1", "true", "yes", "on").Contains((& $GetJsonProperty $dft "kpoints_symmetry" "False").ToLowerInvariant())
        $controls["KpointsWavefunctionsBox"].Text = & $GetJsonProperty $dft "kpoints_wavefunctions"
        $controls["GeoOptimizerBox"].Text = & $GetJsonProperty $geoOpt "optimizer"
        $controls["GeoMaxIterBox"].Text = & $GetJsonProperty $geoOpt "max_iter"
        $controls["CellOptTypeBox"].Text = & $GetJsonProperty $cellOpt "type"
        $controls["CellOptOptimizerBox"].Text = & $GetJsonProperty $cellOpt "optimizer"
        $controls["CellOptMaxIterBox"].Text = & $GetJsonProperty $cellOpt "max_iter"
        $controls["CellOptPressureToleranceBox"].Text = & $GetJsonProperty $cellOpt "pressure_tolerance"
        $controls["CellOptKeepAnglesBox"].IsChecked = @("1", "true", "yes", "on").Contains((& $GetJsonProperty $cellOpt "keep_angles" "False").ToLowerInvariant())
        $controls["CellOptKeepSymmetryBox"].IsChecked = @("1", "true", "yes", "on").Contains((& $GetJsonProperty $cellOpt "keep_symmetry" "False").ToLowerInvariant())
        $controls["FallbackPeriodicBox"].Text = & $GetJsonProperty $fallbackCell "periodic"
        $controls["FallbackCellABox"].Text = & $GetJsonVectorText $fallbackCell "a"
        $controls["FallbackCellBBox"].Text = & $GetJsonVectorText $fallbackCell "b"
        $controls["FallbackCellCBox"].Text = & $GetJsonVectorText $fallbackCell "c"
        $centerAtomsText = (& $GetJsonProperty $structureTransform "center_atoms" "False").ToLowerInvariant()
        $controls["CenterAtomsBox"].IsChecked = @("1", "true", "yes", "on").Contains($centerAtomsText)
        $kindsText = & $GetJsonProperty $Payload "kinds_text"
        $controls["KindsText"].Text = $kindsText
        & $SetKindEntriesFromText $kindsText
        $controls["TemplateValidationText"].Text = & $FormatTemplateValidation $Payload
    }.GetNewClosure()

    $ReadTemplateManagerResult = {
        param([Parameter(Mandatory = $true)]$Result)
        try {
            $payload = $Result.Output | ConvertFrom-Json
        }
        catch {
            if ($Result.ExitCode -ne 0 -and -not [string]::IsNullOrWhiteSpace([string]$Result.Error)) {
                throw $Result.Error
            }
            $raw = [string]$Result.Output
            if (-not [string]::IsNullOrWhiteSpace([string]$Result.Error)) {
                $raw = (($raw, [string]$Result.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n"
            }
            throw "Command did not return JSON. Raw output:`n$raw"
        }
        if ($null -ne $payload.template) {
            & $SetTemplateFieldsFromPayload $payload
        }
        if ($Result.ExitCode -ne 0) {
            throw (& $FormatTemplateValidation $payload)
        }
        return $payload
    }.GetNewClosure()

    $GetTemplateFieldsJson = {
        $fields = [ordered]@{
            project_name = $controls["TemplateProjectBox"].Text
            run_type = $controls["TemplateRunTypeBox"].Text
            print_level = $controls["PrintLevelBox"].Text
            basis_set_file_name = $controls["BasisSetFileBox"].Text
            potential_file_name = $controls["PotentialFileBox"].Text
            xc_functional = $controls["XcFunctionalBox"].Text
            charge = $controls["ChargeBox"].Text
            multiplicity = $controls["MultiplicityBox"].Text
            cutoff = $controls["CutoffBox"].Text
            rel_cutoff = $controls["RelCutoffBox"].Text
            eps_scf = $controls["EpsScfBox"].Text
            max_scf = $controls["MaxScfBox"].Text
            scf_method = $controls["ScfMethodBox"].Text
            added_mos = $controls["AddedMosBox"].Text
            ot_minimizer = $controls["OtMinimizerBox"].Text
            ot_preconditioner = $controls["OtPreconditionerBox"].Text
            diagonalization_algorithm = $controls["DiagonalizationAlgorithmBox"].Text
            mixing_enabled = [bool]$controls["MixingEnabledBox"].IsChecked
            mixing_method = $controls["MixingMethodBox"].Text
            mixing_alpha = $controls["MixingAlphaBox"].Text
            mixing_beta = $controls["MixingBetaBox"].Text
            smearing_enabled = [bool]$controls["SmearingEnabledBox"].IsChecked
            smearing_method = $controls["SmearingMethodBox"].Text
            electronic_temperature = $controls["ElectronicTemperatureBox"].Text
            kpoints_scheme = $controls["KpointsSchemeBox"].Text
            kpoints_grid = $controls["KpointsGridBox"].Text
            kpoints_full_grid = [bool]$controls["KpointsFullGridBox"].IsChecked
            kpoints_symmetry = [bool]$controls["KpointsSymmetryBox"].IsChecked
            kpoints_wavefunctions = $controls["KpointsWavefunctionsBox"].Text
            optimizer = $controls["GeoOptimizerBox"].Text
            geo_opt_max_iter = $controls["GeoMaxIterBox"].Text
            cell_opt_type = $controls["CellOptTypeBox"].Text
            cell_opt_optimizer = $controls["CellOptOptimizerBox"].Text
            cell_opt_max_iter = $controls["CellOptMaxIterBox"].Text
            cell_opt_pressure_tolerance = $controls["CellOptPressureToleranceBox"].Text
            cell_opt_keep_angles = [bool]$controls["CellOptKeepAnglesBox"].IsChecked
            cell_opt_keep_symmetry = [bool]$controls["CellOptKeepSymmetryBox"].IsChecked
            fallback_cell_periodic = $controls["FallbackPeriodicBox"].Text
            fallback_cell_a = $controls["FallbackCellABox"].Text
            fallback_cell_b = $controls["FallbackCellBBox"].Text
            fallback_cell_c = $controls["FallbackCellCBox"].Text
            center_atoms = [bool]$controls["CenterAtomsBox"].IsChecked
            kinds_text = (& $SyncKindsTextFromGrid)
        }
        return ($fields | ConvertTo-Json -Compress)
    }.GetNewClosure()

    $LoadTemplateFields = {
        param([bool]$WriteLog)
        $result = Invoke-WinQStepPython @(
            "scripts\manage_template.py",
            "--template", $controls["TemplatePathBox"].Text,
            "--compact"
        )
        $payload = & $ReadTemplateManagerResult $result
        if ($WriteLog) {
            $controls["LogText"].Text = $result.Output
        }
        return $payload
    }.GetNewClosure()

    $SaveTemplateFields = {
        param([bool]$WriteLog)
        $result = Invoke-WinQStepPython @(
            "scripts\manage_template.py",
            "--template", $controls["TemplatePathBox"].Text,
            "--write",
            "--fields-json", (& $GetTemplateFieldsJson),
            "--compact"
        )
        $payload = & $ReadTemplateManagerResult $result
        if ($WriteLog) {
            $controls["LogText"].Text = $result.Output
        }
        return $payload
    }.GetNewClosure()

    $GetDataInspectionCachePath = {
        $workspace = $controls["DefaultWorkspaceBox"].Text
        if ([string]::IsNullOrWhiteSpace($workspace)) {
            $workspace = $controls["JobDirBox"].Text
        }
        $workspace = & $ResolveWindowsWorkspacePath $workspace
        [System.IO.Directory]::CreateDirectory($workspace) | Out-Null
        return (Join-Path $workspace "cp2k-data.winqstep-cache.json")
    }.GetNewClosure()

    $SetDataLabelsFromPayload = {
        param([Parameter(Mandatory = $true)]$Payload)
        $rows = @()
        if ($null -ne $Payload.labels_by_element) {
            foreach ($property in @($Payload.labels_by_element.PSObject.Properties | Sort-Object Name)) {
                $value = $property.Value
                $rows += [pscustomobject]@{
                    element = $property.Name
                    basis_sets = (@($value.basis_sets) -join ", ")
                    potentials = (@($value.potentials) -join ", ")
                }
            }
        }
        $controls["DataLabelsGrid"].ItemsSource = $rows
        $controls["DataLabelsGrid"].Visibility = if ($rows.Count -gt 0) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $cachePath = & $GetJsonProperty $Payload "cache_path"
        $controls["TemplateValidationText"].Text = "CP2K data labels: elements=$($rows.Count), files=$($Payload.counts.files)`r`ncache=$cachePath"
    }.GetNewClosure()

    $InspectCp2kData = {
        param([bool]$WriteLog)
        $null = & $SaveConfigFields $true $false
        $cachePath = & $GetDataInspectionCachePath
        $result = Invoke-WinQStepPython @(
            "scripts\inspect_cp2k_data.py",
            "--config", $controls["ConfigPathBox"].Text,
            "--cache", $cachePath,
            "--compact"
        )
        $payload = Get-JsonResult $result
        & $SetDataLabelsFromPayload $payload
        if ($WriteLog) {
            $controls["LogText"].Text = $result.Output
        }
        return $payload
    }.GetNewClosure()

    $GetPreflightArrayText = {
        param($Object, [Parameter(Mandatory = $true)][string]$Name)
        if ($null -eq $Object) {
            return ""
        }
        $property = $Object.PSObject.Properties[$Name]
        if ($null -eq $property -or $null -eq $property.Value) {
            return ""
        }
        return ((@($property.Value) | ForEach-Object { [string]$_ }) -join ", ")
    }.GetNewClosure()

    $AddPreflightMessages = {
        param([string[]]$Lines, $Payload, [Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Prefix)
        if ($null -eq $Payload) {
            return $Lines
        }
        $property = $Payload.PSObject.Properties[$Name]
        if ($null -eq $property -or $null -eq $property.Value) {
            return $Lines
        }
        foreach ($text in @($property.Value)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$text)) {
                $Lines += "${Prefix}: $text"
            }
        }
        return $Lines
    }.GetNewClosure()

    $FormatPreflightValidation = {
        param([Parameter(Mandatory = $true)]$Payload)
        $mode = & $GetJsonProperty $Payload "mode"
        $validText = if ([bool]$Payload.valid) { "valid" } else { "invalid" }
        $lines = @("Preflight ${mode}: $validText")

        if ($mode -eq "workflow") {
            $structure = $Payload.structure
            $template = $Payload.template
            $structureElements = & $GetPreflightArrayText $structure "elements"
            $templateElements = & $GetPreflightArrayText $template "kind_elements"
            $lines += "Structure: atoms=$(& $GetJsonProperty $structure "atom_count"), elements=$structureElements"
            $lines += "Template KIND elements: $templateElements"
        }
        elseif ($mode -eq "existing_input") {
            $references = $Payload.references
            $basisFiles = & $GetPreflightArrayText $references "basis_set_file_names"
            $potentialFiles = & $GetPreflightArrayText $references "potential_file_names"
            $lines += "Existing input: $(& $GetJsonProperty $Payload.input "path")"
            $lines += "Referenced basis files: $basisFiles"
            $lines += "Referenced potential files: $potentialFiles"
        }

        $cache = $Payload.data_cache
        if ($null -ne $cache) {
            $lines += "CP2K data cache: available=$(& $GetJsonProperty $cache "available"), path=$(& $GetJsonProperty $cache "path")"
        }
        $lines = & $AddPreflightMessages $lines $Payload "errors" "ERROR"
        $lines = & $AddPreflightMessages $lines $Payload "warnings" "WARNING"
        return ($lines -join "`r`n")
    }.GetNewClosure()

    $SetPreflightValidationText = {
        param([Parameter(Mandatory = $true)]$Payload)
        $text = & $FormatPreflightValidation $Payload
        if ([string]$Payload.mode -eq "workflow") {
            $controls["TemplateValidationText"].Text = $text
            $controls["StructureText"].Text = $text
        }
        else {
            & $ClearInputPreviewState
            $controls["PreviewText"].Text = $text
            $controls["LogText"].Text = $text
        }
        return $text
    }.GetNewClosure()

    $ValidateActiveInputs = {
        $null = & $SaveConfigFields $true $false
        $cachePath = & $GetDataInspectionCachePath
        if (& $TestIsExistingInputMode) {
            $arguments = @(
                "scripts\validate_job_inputs.py",
                "--mode", "existing_input",
                "--config", $controls["ConfigPathBox"].Text,
                "--input", $controls["ExistingInputPathBox"].Text,
                "--cache", $cachePath,
                "--compact"
            )
        }
        else {
            $null = & $SaveTemplateFields $false
            $arguments = @(
                "scripts\validate_job_inputs.py",
                "--mode", "workflow",
                "--config", $controls["ConfigPathBox"].Text,
                "--template", $controls["TemplatePathBox"].Text,
                "--structure", $controls["StructurePathBox"].Text,
                "--project-name", $controls["ProjectNameBox"].Text,
                "--cache", $cachePath,
                "--compact"
            )
        }

        $result = Invoke-WinQStepPython $arguments
        try {
            $payload = $result.Output | ConvertFrom-Json
        }
        catch {
            throw "Preflight did not return JSON. Raw output:`n$($result.Output)"
        }
        $message = & $SetPreflightValidationText $payload
        if ($result.ExitCode -ne 0 -or -not [bool]$payload.valid) {
            throw $message
        }
        return $payload
    }.GetNewClosure()

    $NormalizeInputPreviewText = {
        param([AllowEmptyString()][string]$Text)
        return (($Text -replace "`r`n", "`n") -replace "`r", "`n")
    }.GetNewClosure()

    $GetEditedInputPreview = {
        $current = $previewState["Current"]
        if ($null -eq $current) {
            return $null
        }
        $previewText = [string]$controls["PreviewText"].Text
        if ([string]::IsNullOrWhiteSpace($previewText)) {
            throw "Edited input preview is empty."
        }
        $originalText = [string]$current["Text"]
        if ((& $NormalizeInputPreviewText $previewText) -eq (& $NormalizeInputPreviewText $originalText)) {
            return $null
        }
        return [ordered]@{
            InputPath = [string]$current["InputPath"]
            Text = $previewText
            SourceMode = [string]$current["SourceMode"]
        }
    }.GetNewClosure()

    $GetSafeInputStem = {
        param([AllowEmptyString()][string]$Candidate)
        $stem = ([regex]::Replace($Candidate.Trim(), "[^A-Za-z0-9_.-]+", "_")).Trim([char[]]@(".", "_"))
        if ([string]::IsNullOrWhiteSpace($stem)) {
            return "preview"
        }
        return $stem
    }.GetNewClosure()

    $SaveEditedInputPreview = {
        param([Parameter(Mandatory = $true)]$EditedPreview)
        $jobDirText = $controls["JobDirBox"].Text
        $jobDir = & $ResolveWindowsWorkspacePath $jobDirText
        if ([string]::IsNullOrWhiteSpace($jobDir)) {
            throw "Job folder is required before running an edited preview input."
        }
        [System.IO.Directory]::CreateDirectory($jobDir) | Out-Null

        $sourcePath = [string]$EditedPreview["InputPath"]
        $sourceStem = if (-not [string]::IsNullOrWhiteSpace($sourcePath)) {
            [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
        }
        else {
            [string]$controls["ProjectNameBox"].Text
        }
        $safeStem = & $GetSafeInputStem $sourceStem
        $editedPath = Join-Path $jobDir "${safeStem}_edited.inp"
        $editedText = [string]$EditedPreview["Text"]
        # Windows PowerShell 5.1 writes a UTF-8 BOM; CP2K inputs should stay BOM-free.
        Set-Content -LiteralPath $editedPath -Value $editedText -Encoding UTF8 -NoNewline
        $bytes = [System.IO.File]::ReadAllBytes($editedPath)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            if ($bytes.Length -eq 3) {
                [System.IO.File]::WriteAllBytes($editedPath, [byte[]]@())
            }
            else {
                [System.IO.File]::WriteAllBytes($editedPath, [byte[]]$bytes[3..($bytes.Length - 1)])
            }
        }
        return $editedPath
    }.GetNewClosure()

    $ValidateExistingInputPath = {
        param([Parameter(Mandatory = $true)][string]$InputPath)
        $null = & $SaveConfigFields $true $false
        $cachePath = & $GetDataInspectionCachePath
        $arguments = @(
            "scripts\validate_job_inputs.py",
            "--mode", "existing_input",
            "--config", $controls["ConfigPathBox"].Text,
            "--input", $InputPath,
            "--cache", $cachePath,
            "--compact"
        )
        $result = Invoke-WinQStepPython $arguments
        try {
            $payload = $result.Output | ConvertFrom-Json
        }
        catch {
            throw "Preflight did not return JSON. Raw output:`n$($result.Output)"
        }
        $text = & $FormatPreflightValidation $payload
        $controls["LogText"].Text = $text
        if ($result.ExitCode -ne 0 -or -not [bool]$payload.valid) {
            throw $text
        }
        return $payload
    }.GetNewClosure()

    $SelectPreferredLabel = {
        param([string]$Text, [string[]]$PreferredPatterns)
        $values = @(
            foreach ($value in ($Text -split ",")) {
                $trimmed = $value.Trim()
                if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                    $trimmed
                }
            }
        )
        foreach ($pattern in $PreferredPatterns) {
            $match = @($values | Where-Object { $_ -match $pattern } | Select-Object -First 1)
            if ($match.Count -gt 0) {
                return [string]$match[0]
            }
        }
        if ($values.Count -gt 0) {
            return [string]$values[0]
        }
        return ""
    }.GetNewClosure()

    $ApplySelectedDataLabel = {
        $item = $controls["DataLabelsGrid"].SelectedItem
        if ($null -eq $item) {
            return
        }
        $element = [string]$item.element
        $basis = & $SelectPreferredLabel ([string]$item.basis_sets) @("DZVP-MOLOPT-SR-GTH", "MOLOPT")
        $potential = & $SelectPreferredLabel ([string]$item.potentials) @("GTH-PBE-q", "GTH-PBE")
        if ([string]::IsNullOrWhiteSpace($element) -or [string]::IsNullOrWhiteSpace($basis) -or [string]::IsNullOrWhiteSpace($potential)) {
            return
        }
        $newLine = "$element $basis $potential"
        $updated = $false
        $lines = @()
        $currentKindsText = & $SyncKindsTextFromGrid
        foreach ($line in @($currentKindsText -split "`r?`n")) {
            if ($line.Trim() -match "^$([regex]::Escape($element))\s+") {
                $lines += $newLine
                $updated = $true
            }
            elseif (-not [string]::IsNullOrWhiteSpace($line)) {
                $lines += $line
            }
        }
        if (-not $updated) {
            $lines += $newLine
        }
        $controls["KindsText"].Text = ($lines -join "`r`n")
        & $SetKindEntriesFromText $controls["KindsText"].Text
    }.GetNewClosure()

    $LoadHistory = {
        $result = Invoke-WinQStepPython @(
            "scripts\list_job_history.py",
            "--workspace", $controls["JobDirBox"].Text,
            "--compact"
        )
        $history = Get-JsonResult $result
        $jobs = @()
        if ($null -ne $history.jobs) {
            $jobs = @($history.jobs)
        }
        $errors = @()
        if ($null -ne $history.errors) {
            $errors = @($history.errors)
        }
        $controls["HistoryGrid"].ItemsSource = $jobs
        $controls["LogText"].Text = "History jobs: $($jobs.Count), errors: $($errors.Count)`r`n`r`n$($result.Output)"
    }.GetNewClosure()

    $OpenSelectedHistory = {
        $item = $controls["HistoryGrid"].SelectedItem
        if ($null -eq $item) {
            return
        }

        & $SetArtifactsFromHistoryItem $item
        $metadataPath = [string]$item.metadata_path
        if (-not [string]::IsNullOrWhiteSpace($metadataPath) -and [System.IO.File]::Exists($metadataPath)) {
            $controls["LogText"].Text = [System.IO.File]::ReadAllText($metadataPath, [System.Text.Encoding]::UTF8)
            $metadata = & $ReadMetadataArtifact $metadataPath
            if ($null -ne $metadata) {
                & $SetArtifactsFromMetadata $metadata
            }
        }
        else {
            $controls["LogText"].Text = "Metadata file was not found: $metadataPath"
        }

        $outputPath = [string]$item.output_path
        if (-not [string]::IsNullOrWhiteSpace($outputPath) -and [System.IO.File]::Exists($outputPath)) {
            & $ClearInputPreviewState
            $controls["PreviewText"].Text = [System.IO.File]::ReadAllText($outputPath, [System.Text.Encoding]::UTF8)
        }
        else {
            & $ClearInputPreviewState
            $controls["PreviewText"].Text = "CP2K output was not found: $outputPath"
        }
    }.GetNewClosure()

    $StartAsyncJob = {
        if ($null -ne $jobState["Current"]) {
            & $AppendLog "A CP2K job is already running."
            return
        }

        & $SetBusy $true (Get-WinQStepText "status.preparing_cp2k_job")
        try {
            $editedPreview = & $GetEditedInputPreview
            $editedInputPath = ""
            if ($null -ne $editedPreview) {
                $editedInputPath = & $SaveEditedInputPreview $editedPreview
                $preflight = & $ValidateExistingInputPath $editedInputPath
                $preflightText = & $FormatPreflightValidation $preflight
                $prepareArguments = @(& $GetExistingInputArgumentsForPath $editedInputPath $true)
                $runArguments = @(& $GetExistingInputArgumentsForPath $editedInputPath $false)
            }
            else {
                $preflight = & $ValidateActiveInputs
                $preflightText = & $FormatPreflightValidation $preflight
                $prepareArguments = @(& $GetActiveJobArguments $true)
                $runArguments = @(& $GetActiveJobArguments $false)
            }
            $prepareArguments += "--compact"
            $prepareResult = Invoke-WinQStepPython $prepareArguments
            $preparedMetadata = Get-JsonResult $prepareResult
            $inputPath = & $GetActiveInputPreviewPath $preparedMetadata
            if ([System.IO.File]::Exists($inputPath)) {
                $inputText = [System.IO.File]::ReadAllText($inputPath, [System.Text.Encoding]::UTF8)
                $controls["PreviewText"].Text = $inputText
                $previewMode = if ($null -ne $editedPreview) { "edited_input" } elseif (& $TestIsExistingInputMode) { "existing_input" } else { "workflow" }
                & $SetInputPreviewState $preparedMetadata $inputText $previewMode
            }
            & $SetArtifactsFromMetadata $preparedMetadata

            $jobDir = [string]$preparedMetadata.dry_run.windows.job_dir
            [System.IO.Directory]::CreateDirectory($jobDir) | Out-Null
            $stamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")
            $wrapperStdoutPath = Join-Path $jobDir "winqstep-gui-$stamp.stdout.json"
            $wrapperStderrPath = Join-Path $jobDir "winqstep-gui-$stamp.stderr.log"
            $runArguments += "--compact"
            if ($EditedPreviewSmokeTestEnabled) {
                $preparedInputText = if ([System.IO.File]::Exists($inputPath)) {
                    [System.IO.File]::ReadAllText($inputPath, [System.Text.Encoding]::UTF8)
                }
                else {
                    ""
                }
                $EditedPreviewSmokeState["Report"] = [ordered]@{
                    edited_preview_used = ($null -ne $editedPreview)
                    original_preview_input_path = if ($null -ne $editedPreview) { [string]$editedPreview["InputPath"] } else { "" }
                    edited_input_path = $editedInputPath
                    prepared_input_path = [string]$preparedMetadata.files.input.path
                    prepared_metadata_path = [string]$preparedMetadata.files.metadata.path
                    prepared_job_mode = if ($null -ne $preparedMetadata.job) { [string]$preparedMetadata.job.mode } else { "" }
                    prepared_input_text = $preparedInputText
                    run_arguments = $runArguments
                }
                $controls["LogText"].Text = "$preflightText`r`n`r`nEdited preview run preparation smoke stopped before starting CP2K."
                & $SetBusy $false (Get-WinQStepText "status.ready")
                return
            }
            $process = Start-WinQStepPythonProcess -Arguments $runArguments -StdoutPath $wrapperStdoutPath -StderrPath $wrapperStderrPath

            $jobState["Current"] = @{
                Process = $process
                JobDir = $jobDir
                InputPath = [string]$preparedMetadata.files.input.path
                MetadataPath = [string]$preparedMetadata.files.metadata.path
                OutputPath = [string]$preparedMetadata.files.output.path
                JobStdoutPath = [string]$preparedMetadata.files.stdout.path
                JobStderrPath = [string]$preparedMetadata.files.stderr.path
                WrapperStdoutPath = $wrapperStdoutPath
                WrapperStderrPath = $wrapperStderrPath
                Cancelled = $false
            }
            $logSections = @($preflightText)
            if (-not [string]::IsNullOrWhiteSpace($editedInputPath)) {
                $logSections += "Edited preview input saved: $editedInputPath"
            }
            $logSections += (& $BuildAsyncJobLog $jobState["Current"])
            $controls["LogText"].Text = ($logSections -join "`r`n`r`n")
            & $SetJobStatusText (& $FormatRunningJobStatus $jobState["Current"])
            & $SetAsyncJobRunning $true (Format-WinQStepText "status.running_cp2k_pid" @($process.Id))
            $jobTimer.Start()
        }
        catch {
            $message = $_.Exception.Message
            & $AppendLog "ERROR: $message"
            if ($SuppressGuiMessageBoxes) {
                & $SetBusy $false (Get-WinQStepText "status.ready")
                throw
            }
            [System.Windows.MessageBox]::Show(
                $window,
                $message,
                (Get-WinQStepText "message.error_caption"),
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            ) | Out-Null
            & $SetBusy $false (Get-WinQStepText "status.ready")
        }
    }.GetNewClosure()

    $CancelAsyncJob = {
        $current = $jobState["Current"]
        if ($null -eq $current) {
            return
        }
        $current["Cancelled"] = $true
        $controls["CancelJobButton"].IsEnabled = $false
        $controls["StatusText"].Text = Get-WinQStepText "status.cancelling_cp2k"
        & $AppendLog "Cancellation requested."
        try {
            Stop-WinQStepProcessTree ([System.Diagnostics.Process]$current["Process"])
        }
        catch {
            & $AppendLog "ERROR: failed to stop process tree: $($_.Exception.Message)"
        }
        & $RefreshAsyncJob
    }.GetNewClosure()

    $window.Add_Closing({
        param($sender, $eventArgs)
        $current = $jobState["Current"]
        if ($null -eq $current) {
            return
        }

        $process = [System.Diagnostics.Process]$current["Process"]
        if ($process.HasExited) {
            return
        }

        $eventArgs.Cancel = $true
        $message = Format-WinQStepText "message.close_blocked" @($process.Id, [string]$current["MetadataPath"], [string]$current["OutputPath"])
        & $SetJobStatusText (& $FormatRunningJobStatus $current)
        & $AppendLog "Close blocked: CP2K job PID $($process.Id) is still running."
        [System.Windows.MessageBox]::Show(
            $window,
            $message,
            (Get-WinQStepText "message.warning_caption"),
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        ) | Out-Null
    }.GetNewClosure())

    $controls["LoadConfigButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.loading_config") -Action {
            $null = & $LoadConfigFields $true
        }
    }.GetNewClosure())

    $controls["SaveConfigButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.saving_config") -Action {
            $null = & $SaveConfigFields $false $true
        }
    }.GetNewClosure())

    $controls["ApplyLanguageButton"].Add_Click({
        & $ApplySelectedLanguage
    }.GetNewClosure())

    $controls["LoadTemplateButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.loading_template") -Action {
            $null = & $LoadTemplateFields $true
        }
    }.GetNewClosure())

    $controls["SaveTemplateButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.saving_template") -Action {
            $null = & $SaveTemplateFields $true
        }
    }.GetNewClosure())

    $controls["InspectDataButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.inspecting_cp2k_data") -Action {
            $null = & $InspectCp2kData $true
        }
    }.GetNewClosure())

    $controls["BrowseConfigButton"].Add_Click({
        & $SelectFilePath $controls["ConfigPathBox"] "JSON files (*.json)|*.json|All files (*.*)|*.*"
        & $InvokeGuiAction -Status (Get-WinQStepText "status.loading_config") -Action {
            $null = & $LoadConfigFields $true
        }
    }.GetNewClosure())
    $controls["BrowseTemplateButton"].Add_Click({
        & $SelectFilePath $controls["TemplatePathBox"] "JSON files (*.json)|*.json|All files (*.*)|*.*"
        & $InvokeGuiAction -Status (Get-WinQStepText "status.loading_template") -Action {
            $null = & $LoadTemplateFields $true
        }
    }.GetNewClosure())
    $controls["BrowseStructureButton"].Add_Click({ & $SelectFilePath $controls["StructurePathBox"] "Structures (*.xyz;*.cif;POSCAR;CONTCAR)|*.xyz;*.cif;POSCAR;CONTCAR|All files (*.*)|*.*" }.GetNewClosure())
    $controls["BrowseExistingInputButton"].Add_Click({ & $SelectFilePath $controls["ExistingInputPathBox"] "CP2K input files (*.inp)|*.inp|All files (*.*)|*.*" }.GetNewClosure())
    $controls["BrowseJobDirButton"].Add_Click({ & $SelectFolderPath $controls["JobDirBox"] }.GetNewClosure())
    $controls["WorkflowModeRadio"].Add_Checked({ & $UpdateModeControls }.GetNewClosure())
    $controls["ExistingInputModeRadio"].Add_Checked({ & $UpdateModeControls }.GetNewClosure())

    $controls["DetectButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.detecting_environment") -Action {
            $null = & $SaveConfigFields $false $false
            $result = Invoke-WinQStepPython @("scripts\detect_environment.py", "--config", $controls["ConfigPathBox"].Text)
            $controls["EnvironmentText"].Text = $result.Output
            & $AppendLog "detect_environment.py exited with code $($result.ExitCode)"
        }
    }.GetNewClosure())

    $controls["ImportButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.importing_structure") -Action {
            $result = Invoke-WinQStepPython @("scripts\import_structure.py", "--input", $controls["StructurePathBox"].Text)
            $structureText = $result.Output
            if ($result.ExitCode -eq 0) {
                try {
                    $structurePayload = $result.Output | ConvertFrom-Json
                    $structureText = & $FormatStructureImportDisplay $structurePayload
                }
                catch {
                    $structureText = $result.Output
                }
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$result.Error)) {
                $structureText = (($result.Output, $result.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n"
            }
            $controls["StructureText"].Text = $structureText
            & $AppendLog "import_structure.py exited with code $($result.ExitCode)"
        }
    }.GetNewClosure())

    $controls["PreviewButton"].Add_Click({
        $status = if (& $TestIsExistingInputMode) { Get-WinQStepText "status.preparing_existing_input_preview" } else { Get-WinQStepText "status.preparing_workflow_input_preview" }
        & $InvokeGuiAction -Status $status -Action {
            $preflight = & $ValidateActiveInputs
            $preflightText = & $FormatPreflightValidation $preflight
            $result = Invoke-WinQStepPython (& $GetActiveJobArguments $true)
            $metadata = Get-JsonResult $result
            $inputPath = & $GetActiveInputPreviewPath $metadata
            if ([System.IO.File]::Exists($inputPath)) {
                $inputText = [System.IO.File]::ReadAllText($inputPath, [System.Text.Encoding]::UTF8)
                $controls["PreviewText"].Text = $inputText
                $previewMode = if (& $TestIsExistingInputMode) { "existing_input" } else { "workflow" }
                & $SetInputPreviewState $metadata $inputText $previewMode
            }
            else {
                & $ClearInputPreviewState
                $controls["PreviewText"].Text = "Input file was not written: $inputPath"
            }
            $controls["LogText"].Text = "$preflightText`r`n`r`n$(& $FormatLogWithSummary $metadata $result.Output)"
            & $SetArtifactsFromMetadata $metadata
        }
    }.GetNewClosure())

    $controls["RunButton"].Add_Click({
        & $StartAsyncJob
    }.GetNewClosure())
    $Script:EditedPreviewSmokeStartAsyncJob = $StartAsyncJob

    $controls["CancelJobButton"].Add_Click({
        & $CancelAsyncJob
    }.GetNewClosure())

    $controls["ViewResultsButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.viewing_results_artifact") -Action {
            & $ViewResultSummary
        }
    }.GetNewClosure())

    $controls["SaveResultsButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.saving_results_artifact") -Action {
            $null = & $SaveResultSummary
        }
    }.GetNewClosure())

    $controls["ViewInputButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.viewing_input_artifact") -Action {
            & $ViewArtifact "input"
        }
    }.GetNewClosure())

    $controls["ViewOutputButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.viewing_output_artifact") -Action {
            & $ViewArtifact "output"
        }
    }.GetNewClosure())

    $controls["ViewMetadataButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.viewing_metadata_artifact") -Action {
            & $ViewArtifact "metadata"
        }
    }.GetNewClosure())

    $controls["ViewStdoutButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.viewing_stdout_artifact") -Action {
            & $ViewArtifact "stdout"
        }
    }.GetNewClosure())

    $controls["ViewStderrButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.viewing_stderr_artifact") -Action {
            & $ViewArtifact "stderr"
        }
    }.GetNewClosure())

    $controls["HistoryButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.loading_job_history") -Action {
            & $LoadHistory
        }
    }.GetNewClosure())

    $controls["HistoryGrid"].Add_MouseDoubleClick({
        & $OpenSelectedHistory
    }.GetNewClosure())

    $controls["DataLabelsGrid"].Add_MouseDoubleClick({
        & $ApplySelectedDataLabel
    }.GetNewClosure())

    $controls["ClearButton"].Add_Click({
        $controls["EnvironmentText"].Clear()
        $controls["StructureText"].Clear()
        $controls["PreviewText"].Clear()
        $controls["LogText"].Clear()
        $controls["ArtifactSummaryText"].Clear()
        $controls["ArtifactText"].Clear()
        $controls["HistoryGrid"].ItemsSource = $null
        $controls["KindEntriesGrid"].ItemsSource = (& $NewKindEntriesTable).DefaultView
        $controls["DataLabelsGrid"].ItemsSource = $null
        $controls["DataLabelsGrid"].Visibility = [System.Windows.Visibility]::Collapsed
        & $ClearInputPreviewState
        $artifactState["Current"] = $null
        & $SetJobStatusText ""
        & $UpdateArtifactControls
    }.GetNewClosure())

    try {
        $null = & $LoadConfigFields $false
    }
    catch {
        $controls["ConfigValidationText"].Text = $_.Exception.Message
    }
    try {
        $null = & $LoadTemplateFields $false
    }
    catch {
        $controls["TemplateValidationText"].Text = $_.Exception.Message
    }
    & $UpdateModeControls
    & $UpdateArtifactControls
    return $window
}

if ($Diagnostics) {
    $result = Invoke-WinQStepStartupDiagnostics ([bool]$SkipLiveProbes)
    if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
        Write-Output $result.Output
    }
    exit $result.ExitCode
}

if ($PythonInvokeSmokeTest) {
    $jsonOnStdoutResult = Invoke-WinQStepPython @(
        "-c",
        "import sys; print('{`"ok`": true}'); print('plain stderr', file=sys.stderr); sys.exit(2)"
    )
    $badFieldsResult = Invoke-WinQStepPython @(
        "scripts\manage_config.py",
        "--config", (Resolve-WinQStepPath "examples\winqstep.config.json"),
        "--write",
        "--fields-json", "{bad}",
        "--compact"
    )
    $report = [ordered]@{
        mode = "python_invoke_smoke"
        json_stdout_exit_code = $jsonOnStdoutResult.ExitCode
        json_stdout_output = $jsonOnStdoutResult.Output
        json_stdout_error = $jsonOnStdoutResult.Error
        bad_fields_exit_code = $badFieldsResult.ExitCode
        bad_fields_output = $badFieldsResult.Output
        bad_fields_error = $badFieldsResult.Error
        stderr_has_native_wrapper = (
            ([string]$jsonOnStdoutResult.Error).Contains("NativeCommandError") -or
            ([string]$badFieldsResult.Error).Contains("NativeCommandError") -or
            ([string]$badFieldsResult.Error).Contains("python.exe :")
        )
    }
    $report | ConvertTo-Json -Depth 4
    if (
        $jsonOnStdoutResult.ExitCode -eq 2 -and
        $jsonOnStdoutResult.Output -eq '{"ok": true}' -and
        $jsonOnStdoutResult.Error -eq "plain stderr" -and
        $badFieldsResult.ExitCode -eq 2 -and
        [string]::IsNullOrWhiteSpace($badFieldsResult.Output) -and
        ([string]$badFieldsResult.Error).Contains("Expecting property name enclosed in double quotes") -and
        -not [bool]$report["stderr_has_native_wrapper"]
    ) {
        exit 0
    }
    exit 1
}

if ($LifecycleSmokeTest) {
    $utf8LogText = "$([char]0x4e2d)$([char]0x6587)$([char]0x65e5)$([char]0x5fd7)"
    $report = [ordered]@{
        process_started = $false
        process_stopped = $false
        exit_code = $null
        stdout_exists = $false
        stderr_exists = $false
        stdout_utf8_ok = $false
        stderr_utf8_ok = $false
        tail_utf8_ok = $false
    }
    $process = $null
    $smokeDir = Resolve-WinQStepPath "outputs\lifecycle-smoke"
    [System.IO.Directory]::CreateDirectory($smokeDir) | Out-Null
    $stamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")
    $stdoutPath = Join-Path $smokeDir "sleeper-$stamp.stdout.log"
    $stderrPath = Join-Path $smokeDir "sleeper-$stamp.stderr.log"
    try {
        $process = Start-WinQStepPythonProcess -Arguments @(
            "-c",
            "import sys, time; text=''.join(chr(x) for x in [0x4e2d, 0x6587, 0x65e5, 0x5fd7]); print(text, flush=True); print(text, file=sys.stderr, flush=True); time.sleep(30)"
        ) -StdoutPath $stdoutPath -StderrPath $stderrPath
        Start-Sleep -Milliseconds 500
        $report["process_started"] = (-not $process.HasExited)
        Stop-WinQStepProcessTree $process
        $report["process_stopped"] = $process.WaitForExit(3000)
        if ($report["process_stopped"]) {
            $null = Save-WinQStepProcessOutput $process $stdoutPath $stderrPath
        }
        if ($process.HasExited) {
            $report["exit_code"] = [int]$process.ExitCode
        }
        $report["stdout_exists"] = [System.IO.File]::Exists($stdoutPath)
        $report["stderr_exists"] = [System.IO.File]::Exists($stderrPath)
        $stdoutText = Read-WinQStepFileText $stdoutPath
        $stderrText = Read-WinQStepFileText $stderrPath
        $stdoutTail = Get-WinQStepFileTail $stdoutPath 5
        $report["stdout_utf8_ok"] = $stdoutText.Contains($utf8LogText)
        $report["stderr_utf8_ok"] = $stderrText.Contains($utf8LogText)
        $report["tail_utf8_ok"] = $stdoutTail.Contains($utf8LogText)
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-WinQStepProcessTree $process
        }
    }
    $report | ConvertTo-Json -Depth 5
    if (
        $report["process_started"] -and
        $report["process_stopped"] -and
        $report["stdout_utf8_ok"] -and
        $report["stderr_utf8_ok"] -and
        $report["tail_utf8_ok"]
    ) {
        exit 0
    }
    exit 1
}

if ($EditedPreviewSmokeTest) {
    $report = Test-WinQStepGuiPrerequisites
    $window = New-WinQStepWindow
    $smokeDir = Resolve-WinQStepPath "outputs\gui-edited-preview-smoke"
    [System.IO.Directory]::CreateDirectory($smokeDir) | Out-Null
    $smokeConfigPath = Join-Path $smokeDir "edited_preview.config.json"
    $smokeTemplatePath = Join-Path $smokeDir "edited_preview.template.json"
    [System.IO.File]::Copy((Resolve-WinQStepPath "examples\winqstep.config.json"), $smokeConfigPath, $true)
    [System.IO.File]::Copy((Resolve-WinQStepPath "examples\templates\energy_pbe.json"), $smokeTemplatePath, $true)
    $window.FindName("ConfigPathBox").Text = $smokeConfigPath
    $window.FindName("TemplatePathBox").Text = $smokeTemplatePath
    $window.FindName("JobDirBox").Text = $smokeDir
    $window.FindName("ProjectNameBox").Text = "edited_preview_smoke"
    $window.FindName("WorkflowModeRadio").IsChecked = $true

    $InvokeEditedPreviewSmokeClick = {
        param([Parameter(Mandatory = $true)][string]$Name)
        $button = $window.FindName($Name)
        if ($null -eq $button) {
            throw "Button was not found: $Name"
        }
        if (-not [bool]$button.IsEnabled) {
            throw "Button is disabled: $Name"
        }
        $eventArgs = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
        $button.RaiseEvent($eventArgs)
        [System.Windows.Forms.Application]::DoEvents()
    }.GetNewClosure()

    $marker = "! edited preview smoke marker"
    & $InvokeEditedPreviewSmokeClick "LoadConfigButton"
    & $InvokeEditedPreviewSmokeClick "LoadTemplateButton"
    $window.FindName("JobDirBox").Text = $smokeDir
    $window.FindName("ProjectNameBox").Text = "edited_preview_smoke"
    $window.FindName("WorkflowModeRadio").IsChecked = $true
    & $InvokeEditedPreviewSmokeClick "PreviewButton"
    $window.FindName("JobDirBox").Text = $smokeDir
    $window.FindName("ProjectNameBox").Text = "edited_preview_smoke"
    $originalPreviewText = [string]$window.FindName("PreviewText").Text
    $window.FindName("PreviewText").Text = "$originalPreviewText`r`n$marker`r`n"
    $startAsyncJob = $Script:EditedPreviewSmokeStartAsyncJob
    if ($null -eq $startAsyncJob) {
        throw "StartAsyncJob smoke hook was not found."
    }
    & $startAsyncJob

    $runReport = $EditedPreviewSmokeState["Report"]
    $editedInputText = ""
    $originalInputText = ""
    if ($null -ne $runReport) {
        if ([System.IO.File]::Exists([string]$runReport["edited_input_path"])) {
            $editedInputText = [System.IO.File]::ReadAllText([string]$runReport["edited_input_path"], [System.Text.Encoding]::UTF8)
        }
        if ([System.IO.File]::Exists([string]$runReport["original_preview_input_path"])) {
            $originalInputText = [System.IO.File]::ReadAllText([string]$runReport["original_preview_input_path"], [System.Text.Encoding]::UTF8)
        }
    }

    $report["mode"] = "edited_preview_smoke"
    $report["preview_original_has_global"] = $originalPreviewText.Contains("&GLOBAL")
    $report["edited_preview_reported"] = ($null -ne $runReport)
    $report["edited_preview_used"] = if ($null -ne $runReport) { [bool]$runReport["edited_preview_used"] } else { $false }
    $report["edited_input_path"] = if ($null -ne $runReport) { [string]$runReport["edited_input_path"] } else { "" }
    $report["prepared_input_path"] = if ($null -ne $runReport) { [string]$runReport["prepared_input_path"] } else { "" }
    $report["prepared_job_mode"] = if ($null -ne $runReport) { [string]$runReport["prepared_job_mode"] } else { "" }
    $report["run_arguments"] = if ($null -ne $runReport) { @($runReport["run_arguments"]) } else { @() }
    $report["edited_input_contains_marker"] = $editedInputText.Contains($marker)
    $report["prepared_input_contains_marker"] = if ($null -ne $runReport) { ([string]$runReport["prepared_input_text"]).Contains($marker) } else { $false }
    $report["original_input_contains_marker"] = $originalInputText.Contains($marker)
    $report["edited_input_separate_from_original"] = if ($null -ne $runReport) {
        [string]$runReport["edited_input_path"] -ne [string]$runReport["original_preview_input_path"]
    } else {
        $false
    }
    $report | ConvertTo-Json -Depth 6

    if (
        $report["preview_original_has_global"] -and
        $report["edited_preview_reported"] -and
        $report["edited_preview_used"] -and
        $report["prepared_job_mode"] -eq "existing_input" -and
        $report["edited_input_contains_marker"] -and
        $report["prepared_input_contains_marker"] -and
        $report["edited_input_separate_from_original"] -and
        -not $report["original_input_contains_marker"] -and
        (@($report["run_arguments"]) -contains [string]$report["edited_input_path"])
    ) {
        exit 0
    }
    exit 1
}

if ($AsyncRunSmokeTest) {
    $report = Test-WinQStepGuiPrerequisites
    $window = New-WinQStepWindow
    $smokeDir = Resolve-WinQStepPath "outputs\gui-async-run-smoke"
    [System.IO.Directory]::CreateDirectory($smokeDir) | Out-Null
    $smokeConfigPath = Join-Path $smokeDir "async_run.config.json"
    $smokeTemplatePath = Join-Path $smokeDir "async_run.template.json"
    [System.IO.File]::Copy((Resolve-WinQStepPath "examples\winqstep.config.json"), $smokeConfigPath, $true)
    [System.IO.File]::Copy((Resolve-WinQStepPath "examples\templates\energy_pbe.json"), $smokeTemplatePath, $true)
    $window.FindName("ConfigPathBox").Text = $smokeConfigPath
    $window.FindName("TemplatePathBox").Text = $smokeTemplatePath
    $window.FindName("StructurePathBox").Text = Resolve-WinQStepPath "tests\fixtures\structures\water.xyz"
    $window.FindName("JobDirBox").Text = $smokeDir
    $window.FindName("ProjectNameBox").Text = "async_run_smoke"
    $window.FindName("WorkflowModeRadio").IsChecked = $true

    $PumpDispatcher = {
        param([int]$Milliseconds = 100)
        $frame = [System.Windows.Threading.DispatcherFrame]::new()
        $timer = [System.Windows.Threading.DispatcherTimer]::new(
            [System.Windows.Threading.DispatcherPriority]::Background
        )
        $timer.Interval = [TimeSpan]::FromMilliseconds($Milliseconds)
        $timer.Add_Tick({
            $timer.Stop()
            $frame.Continue = $false
        }.GetNewClosure())
        $timer.Start()
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    }.GetNewClosure()

    $ClickButton = {
        param([Parameter(Mandatory = $true)][string]$Name)
        $button = $window.FindName($Name)
        if ($null -eq $button) {
            throw "Button was not found: $Name"
        }
        if (-not [bool]$button.IsEnabled) {
            throw "Button is disabled: $Name"
        }
        $eventArgs = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
        $button.RaiseEvent($eventArgs)
        & $PumpDispatcher 50
    }.GetNewClosure()

    $runError = $null
    $runErrorStack = ""
    $timedOut = $false
    $started = $false
    try {
        & $ClickButton "RunButton"
        $started = [bool]$window.FindName("CancelJobButton").IsEnabled
        $deadline = [DateTime]::UtcNow.AddSeconds(120)
        while ([bool]$window.FindName("CancelJobButton").IsEnabled) {
            if ([DateTime]::UtcNow -gt $deadline) {
                $timedOut = $true
                break
            }
            & $PumpDispatcher 250
        }
    }
    catch {
        $runError = $_.Exception.Message
        $runErrorStack = [string]$_.ScriptStackTrace
    }

    if ($timedOut -and [bool]$window.FindName("CancelJobButton").IsEnabled) {
        try {
            & $ClickButton "CancelJobButton"
        }
        catch {
        }
    }

    $logText = [string]$window.FindName("LogText").Text
    $artifactSummary = [string]$window.FindName("ArtifactSummaryText").Text
    $jobStatusText = [string]$window.FindName("JobStatusText").Text
    $statusText = [string]$window.FindName("StatusText").Text
    $report["mode"] = "async_run_smoke"
    $report["run_error"] = $runError
    $report["run_error_stack"] = $runErrorStack
    $report["run_started"] = $started
    $report["timed_out"] = $timedOut
    $report["run_completed"] = (-not [bool]$window.FindName("CancelJobButton").IsEnabled)
    $report["run_button_reenabled"] = [bool]$window.FindName("RunButton").IsEnabled
    $report["status_text"] = $statusText
    $report["job_status_text"] = $jobStatusText
    $report["log_has_summary"] = $logText.Contains("CP2K summary:")
    $report["log_has_success"] = ($logText.Contains("status=succeeded") -or $jobStatusText.Contains("status=succeeded"))
    $report["artifact_has_output"] = $artifactSummary.Contains("output=[exists]")
    $report["artifact_has_metadata"] = $artifactSummary.Contains("metadata=[exists]")
    $report["artifact_results_enabled"] = [bool]$window.FindName("ViewResultsButton").IsEnabled
    $report["log_tail"] = if ($logText.Length -gt 1200) { $logText.Substring($logText.Length - 1200) } else { $logText }
    $report | ConvertTo-Json -Depth 6

    if (
        [string]::IsNullOrWhiteSpace($runError) -and
        $started -and
        -not $timedOut -and
        $report["run_completed"] -and
        $report["run_button_reenabled"] -and
        $report["log_has_summary"] -and
        $report["log_has_success"] -and
        $report["artifact_has_output"] -and
        $report["artifact_has_metadata"] -and
        $report["artifact_results_enabled"]
    ) {
        exit 0
    }
    exit 1
}

if ($ButtonSmokeTest) {
    $report = Test-WinQStepGuiPrerequisites
    $window = New-WinQStepWindow
    $buttonReports = [ordered]@{}

    $historySmokeDir = Resolve-WinQStepPath "outputs\gui-button-history-smoke"
    [System.IO.Directory]::CreateDirectory($historySmokeDir) | Out-Null
    $smokeConfigPath = Join-Path $historySmokeDir "button_smoke.config.json"
    $smokeTemplatePath = Join-Path $historySmokeDir "button_smoke.template.json"
    [System.IO.File]::Copy((Resolve-WinQStepPath "examples\winqstep.config.json"), $smokeConfigPath, $true)
    [System.IO.File]::Copy((Resolve-WinQStepPath "examples\templates\energy_pbe.json"), $smokeTemplatePath, $true)

    $historyMetadataPath = Join-Path $historySmokeDir "button_history.winqstep.json"
    $historyInputPath = Join-Path $historySmokeDir "button_history.inp"
    $historyOutputPath = Join-Path $historySmokeDir "button_history.out"
    $historyStdoutPath = Join-Path $historySmokeDir "button_history.stdout.log"
    $historyStderrPath = Join-Path $historySmokeDir "button_history.stderr.log"
    $historyMetadata = [ordered]@{
        status = "succeeded"
        created_at = "2026-06-29T00:00:00Z"
        completed_at = "2026-06-29T00:01:00Z"
        returncode = 0
        job = [ordered]@{
            mode = "existing_input"
            input_stem = "button_history"
        }
        files = [ordered]@{
            input = [ordered]@{ path = $historyInputPath }
            output = [ordered]@{ path = $historyOutputPath }
            stdout = [ordered]@{ path = $historyStdoutPath }
            stderr = [ordered]@{ path = $historyStderrPath }
            metadata = [ordered]@{ path = $historyMetadataPath }
        }
        cp2k_output = [ordered]@{
            status = "completed"
            warning_count = 0
            program_ended = $true
            total_energy_hartree = -17.219350325303314
            forces = [ordered]@{
                unit = "hartree/bohr"
                atoms = @(
                    [ordered]@{
                        atom = 1
                        x = 0.0
                        y = 0.0
                        z = -0.0135588799
                        norm = 0.0135588799
                    }
                )
                sum = [ordered]@{
                    x = 0.0
                    y = 0.0
                    z = 0.00148299452
                }
                total_atomic_force = 0.00148299452
            }
        }
    }
    [System.IO.File]::WriteAllText($historyInputPath, "&GLOBAL`n  PROJECT button_history`n&END GLOBAL`n", $Script:Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($historyOutputPath, "The number of warnings for this run is : 0`nPROGRAM ENDED AT                 2026-06-29 00:01:00.000`n", $Script:Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($historyStdoutPath, "stdout smoke`n", $Script:Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($historyStderrPath, "stderr smoke`n", $Script:Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText(
        $historyMetadataPath,
        (($historyMetadata | ConvertTo-Json -Depth 8) + "`n"),
        $Script:Utf8NoBomEncoding
    )
    $window.FindName("ConfigPathBox").Text = $smokeConfigPath
    $window.FindName("TemplatePathBox").Text = $smokeTemplatePath
    $window.FindName("JobDirBox").Text = $historySmokeDir
    $window.FindName("ProjectNameBox").Text = "button_workflow"

    $InvokeButtonSmokeClick = {
        param([Parameter(Mandatory = $true)][string]$Name)
        $button = $window.FindName($Name)
        if ($null -eq $button) {
            throw "Button was not found: $Name"
        }
        if (-not [bool]$button.IsEnabled) {
            throw "Button is disabled: $Name"
        }
        $eventArgs = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
        $button.RaiseEvent($eventArgs)
        [System.Windows.Forms.Application]::DoEvents()
    }.GetNewClosure()

    $RecordButtonSmokeClick = {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [string]$ReportName = ""
        )
        $key = if ([string]::IsNullOrWhiteSpace($ReportName)) { $Name } else { $ReportName }
        try {
            & $InvokeButtonSmokeClick $Name
            $buttonReports[$key] = [ordered]@{
                ok = $true
                error = $null
            }
        }
        catch {
            $buttonReports[$key] = [ordered]@{
                ok = $false
                error = $_.Exception.Message
            }
        }
    }.GetNewClosure()

    $buttonNames = @(
        "LoadConfigButton",
        "SaveConfigButton",
        "LoadTemplateButton",
        "SaveTemplateButton"
    )
    if (-not $SkipLiveProbes) {
        $buttonNames = @("DetectButton", "InspectDataButton") + $buttonNames
    }
    $buttonNames += @("ImportButton")
    foreach ($buttonName in $buttonNames) {
        & $RecordButtonSmokeClick $buttonName
    }
    $importStructureText = [string]$window.FindName("StructureText").Text

    & $RecordButtonSmokeClick "PreviewButton" "PreviewWorkflowButton"
    $workflowPreviewText = [string]$window.FindName("PreviewText").Text

    $window.FindName("ExistingInputModeRadio").IsChecked = $true
    [System.Windows.Forms.Application]::DoEvents()
    $existingModeImportDisabled = (-not [bool]$window.FindName("ImportButton").IsEnabled)
    & $RecordButtonSmokeClick "PreviewButton" "PreviewExistingInputButton"
    $existingPreviewText = [string]$window.FindName("PreviewText").Text

    & $RecordButtonSmokeClick "HistoryButton"
    $historyLogText = [string]$window.FindName("LogText").Text

    $historyGrid = $window.FindName("HistoryGrid")
    $historyItems = @($historyGrid.ItemsSource)
    $selectedHistoryItem = $null
    foreach ($item in $historyItems) {
        if ([string]$item.project_name -eq "button_history") {
            $selectedHistoryItem = $item
            break
        }
    }
    try {
        if ($null -eq $selectedHistoryItem) {
            throw "button_history job was not found in history grid."
        }
        $historyGrid.SelectedItem = $selectedHistoryItem
        $mouseArgs = [System.Windows.Input.MouseButtonEventArgs]::new(
            [System.Windows.Input.Mouse]::PrimaryDevice,
            0,
            [System.Windows.Input.MouseButton]::Left
        )
        $mouseArgs.RoutedEvent = [System.Windows.Controls.Control]::MouseDoubleClickEvent
        $historyGrid.RaiseEvent($mouseArgs)
        [System.Windows.Forms.Application]::DoEvents()
        $buttonReports["HistoryGridDoubleClick"] = [ordered]@{
            ok = $true
            error = $null
        }
    }
    catch {
        $buttonReports["HistoryGridDoubleClick"] = [ordered]@{
            ok = $false
            error = $_.Exception.Message
        }
    }

    & $RecordButtonSmokeClick "ViewResultsButton"
    $artifactResultsTextBeforeClear = [string]$window.FindName("ArtifactText").Text
    & $RecordButtonSmokeClick "SaveResultsButton"
    $artifactSummaryAfterSave = [string]$window.FindName("ArtifactSummaryText").Text
    $savedResultsPath = Join-Path $historySmokeDir "button_history.results.txt"
    $savedResultsText = if ([System.IO.File]::Exists($savedResultsPath)) {
        [System.IO.File]::ReadAllText($savedResultsPath, [System.Text.Encoding]::UTF8)
    }
    else {
        ""
    }

    foreach ($buttonName in @("ViewInputButton", "ViewOutputButton", "ViewMetadataButton", "ViewStdoutButton", "ViewStderrButton")) {
        & $RecordButtonSmokeClick $buttonName
    }

    $window.FindName("UiLanguageBox").SelectedIndex = 2
    [System.Windows.Forms.Application]::DoEvents()
    & $RecordButtonSmokeClick "ApplyLanguageButton"
    $languageAfterApply = Get-WinQStepLanguage
    $previewButtonTextAfterLanguageApply = [string]$window.FindName("PreviewButton").Content

    $artifactSummaryBeforeClear = [string]$window.FindName("ArtifactSummaryText").Text
    $artifactTextBeforeClear = [string]$window.FindName("ArtifactText").Text
    $previewTextBeforeClear = [string]$window.FindName("PreviewText").Text
    $logTextBeforeClear = [string]$window.FindName("LogText").Text
    & $RecordButtonSmokeClick "ClearButton"

    $artifactViewButtonsDisabled = @(
        "ViewResultsButton", "SaveResultsButton",
        "ViewInputButton", "ViewOutputButton", "ViewMetadataButton", "ViewStdoutButton", "ViewStderrButton"
    ).Where({ [bool]$window.FindName($_).IsEnabled }).Count -eq 0
    $textFieldsCleared = @(
        "EnvironmentText", "StructureText", "PreviewText", "LogText", "ArtifactSummaryText", "ArtifactText"
    ).Where({ -not [string]::IsNullOrWhiteSpace([string]$window.FindName($_).Text) }).Count -eq 0

    $report["button_clicks"] = $buttonReports
    $report["button_live_probes_skipped"] = [bool]$SkipLiveProbes
    $report["button_message_boxes_suppressed"] = [bool]$Script:SuppressGuiMessageBoxes
    $report["scratch_config_path"] = $smokeConfigPath
    $report["scratch_template_path"] = $smokeTemplatePath
    $report["scratch_config_exists"] = [System.IO.File]::Exists($smokeConfigPath)
    $report["scratch_template_exists"] = [System.IO.File]::Exists($smokeTemplatePath)
    $report["import_text_has_summary"] = $importStructureText.Contains("Imported structure")
    $report["import_text_has_atom_count"] = $importStructureText.Contains("Atoms: 3")
    $report["import_text_has_elements"] = $importStructureText.Contains("Elements: H=2, O=1")
    $report["import_text_has_coordinate_table"] = (
        $importStructureText.Contains("Atoms (cartesian coordinates, Angstrom)") -and
        $importStructureText.Contains("     1 O") -and
        $importStructureText.Contains("     2 H")
    )
    $report["history_grid_count"] = $historyItems.Count
    $report["history_selected_project"] = if ($null -ne $selectedHistoryItem) { [string]$selectedHistoryItem.project_name } else { "" }
    $report["history_log_has_jobs"] = $historyLogText.Contains("History jobs:")
    $report["existing_mode_import_disabled"] = $existingModeImportDisabled
    $report["workflow_preview_has_global"] = $workflowPreviewText.Contains("&GLOBAL")
    $report["existing_preview_has_global"] = $existingPreviewText.Contains("&GLOBAL")
    $report["artifact_summary_has_history"] = $artifactSummaryBeforeClear.Contains("button_history")
    $report["artifact_summary_has_energy"] = $artifactSummaryBeforeClear.Contains("energy_hartree=-17.2193503253033")
    $report["artifact_results_has_force_table"] = ($artifactResultsTextBeforeClear.Contains("Forces (hartree/bohr)") -and $artifactResultsTextBeforeClear.Contains("total_atomic_force=0.00148299452 hartree/bohr"))
    $report["result_summary_saved"] = [System.IO.File]::Exists($savedResultsPath)
    $report["result_summary_path_in_summary"] = $artifactSummaryAfterSave.Contains("results=[exists] $savedResultsPath")
    $report["result_summary_file_has_force"] = $savedResultsText.Contains("total_atomic_force=0.00148299452 hartree/bohr")
    $report["artifact_text_has_stderr"] = $artifactTextBeforeClear.Contains("stderr smoke")
    $report["artifact_log_has_stderr"] = $logTextBeforeClear.Contains("stderr smoke")
    $report["preview_text_has_output"] = $previewTextBeforeClear.Contains("PROGRAM ENDED")
    $report["language_apply_switched_to_zh"] = ($languageAfterApply -eq "zh-CN")
    $report["language_apply_changed_preview_text"] = ($previewButtonTextAfterLanguageApply -ne "Preview")
    $report["clear_emptied_text_fields"] = $textFieldsCleared
    $report["clear_disabled_artifact_buttons"] = $artifactViewButtonsDisabled
    $report["clear_removed_history_items"] = ($null -eq $window.FindName("HistoryGrid").ItemsSource)
    $report | ConvertTo-Json -Depth 6

    $allButtonsOk = -not @($buttonReports.Values | Where-Object { -not [bool]$_.ok }).Count
    $stateChecksOk = (
        $report["scratch_config_exists"] -and
        $report["scratch_template_exists"] -and
        $report["import_text_has_summary"] -and
        $report["import_text_has_atom_count"] -and
        $report["import_text_has_elements"] -and
        $report["import_text_has_coordinate_table"] -and
        $report["history_grid_count"] -gt 0 -and
        $report["history_selected_project"] -eq "button_history" -and
        $report["history_log_has_jobs"] -and
        $report["existing_mode_import_disabled"] -and
        $report["workflow_preview_has_global"] -and
        $report["existing_preview_has_global"] -and
        $report["artifact_summary_has_history"] -and
        $report["artifact_summary_has_energy"] -and
        $report["artifact_results_has_force_table"] -and
        $report["result_summary_saved"] -and
        $report["result_summary_path_in_summary"] -and
        $report["result_summary_file_has_force"] -and
        $report["artifact_text_has_stderr"] -and
        $report["artifact_log_has_stderr"] -and
        $report["preview_text_has_output"] -and
        $report["language_apply_switched_to_zh"] -and
        $report["language_apply_changed_preview_text"] -and
        $report["clear_emptied_text_fields"] -and
        $report["clear_disabled_artifact_buttons"] -and
        $report["clear_removed_history_items"]
    )
    if ($allButtonsOk -and $stateChecksOk) {
        exit 0
    }
    exit 1
}

if ($SmokeTest) {
    $report = Test-WinQStepGuiPrerequisites
    $window = New-WinQStepWindow
    $expectedEncodingText = "$([char]0x4e2d)$([char]0x6587)$([char]0x8def)$([char]0x5f84):D:\Library\$([char]0x81ea)$([char]0x5236)$([char]0x54c1)"
    $chineseFolderName = "$([char]0x81ea)$([char]0x5236)$([char]0x54c1)"
    $encodingProbeResult = Invoke-WinQStepPython @(
        "-c",
        "import json; sep = chr(92); text = ''.join(chr(x) for x in [0x4e2d, 0x6587, 0x8def, 0x5f84]) + ':D:' + sep + 'Library' + sep + ''.join(chr(x) for x in [0x81ea, 0x5236, 0x54c1]); print(json.dumps(dict(text=text), ensure_ascii=False))"
    )
    $encodingProbe = Get-JsonResult $encodingProbeResult
    $previewResult = Invoke-WinQStepPython @(
        "scripts\run_workflow.py",
        "--config", (Resolve-WinQStepPath "examples\winqstep.config.json"),
        "--template", (Resolve-WinQStepPath "examples\templates\energy_pbe.json"),
        "--structure", (Resolve-WinQStepPath "tests\fixtures\structures\water.xyz"),
        "--job-dir", (Resolve-WinQStepPath "outputs\gui-smoke"),
        "--project-name", "gui_smoke",
        "--prepare-only",
        "--compact"
    )
    $previewMetadata = Get-JsonResult $previewResult
    $existingPreviewResult = Invoke-WinQStepPython @(
        "scripts\run_existing_input.py",
        "--config", (Resolve-WinQStepPath "examples\winqstep.config.json"),
        "--input", (Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"),
        "--job-dir", (Resolve-WinQStepPath "outputs\gui-existing-smoke"),
        "--prepare-only",
        "--compact"
    )
    $existingPreviewMetadata = Get-JsonResult $existingPreviewResult
    $historySmokeDir = Resolve-WinQStepPath "outputs\gui-history-smoke"
    [System.IO.Directory]::CreateDirectory($historySmokeDir) | Out-Null
    $historyMetadataPath = Join-Path $historySmokeDir "history_smoke.winqstep.json"
    $historyInputPath = Join-Path $historySmokeDir "history_smoke.inp"
    $historyOutputPath = Join-Path $historySmokeDir "history_smoke.out"
    $historyStdoutPath = Join-Path $historySmokeDir "history_smoke.stdout.log"
    $historyStderrPath = Join-Path $historySmokeDir "history_smoke.stderr.log"
    $historyMetadata = [ordered]@{
        status = "succeeded"
        created_at = "2026-06-29T00:00:00Z"
        completed_at = "2026-06-29T00:01:00Z"
        returncode = 0
        job = [ordered]@{
            mode = "existing_input"
            input_stem = "history_smoke"
        }
        files = [ordered]@{
            input = [ordered]@{ path = $historyInputPath }
            output = [ordered]@{ path = $historyOutputPath }
            stdout = [ordered]@{ path = $historyStdoutPath }
            stderr = [ordered]@{ path = $historyStderrPath }
            metadata = [ordered]@{ path = $historyMetadataPath }
        }
        cp2k_output = [ordered]@{
            status = "completed"
            warning_count = 0
            program_ended = $true
        }
    }
    [System.IO.File]::WriteAllText($historyInputPath, "&GLOBAL`n  PROJECT history_smoke`n&END GLOBAL`n", $Script:Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($historyOutputPath, "The number of warnings for this run is : 0`nPROGRAM ENDED AT                 2026-06-29 00:01:00.000`n", $Script:Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($historyStdoutPath, "", $Script:Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText($historyStderrPath, "", $Script:Utf8NoBomEncoding)
    [System.IO.File]::WriteAllText(
        $historyMetadataPath,
        (($historyMetadata | ConvertTo-Json -Depth 8) + "`n"),
        $Script:Utf8NoBomEncoding
    )
    $historyResult = Invoke-WinQStepPython @(
        "scripts\list_job_history.py",
        "--workspace", $historySmokeDir,
        "--compact"
    )
    $history = Get-JsonResult $historyResult
    $historyJobs = @()
    if ($null -ne $history.jobs) {
        $historyJobs = @($history.jobs)
    }
    $window.FindName("ExistingInputModeRadio").IsChecked = $true
    $configWorkspace = [string]$window.FindName("DefaultWorkspaceBox").Text
    $report["xaml_loaded"] = ($window -is [System.Windows.Window])
    $report["title"] = $window.Title
    $report["ui_language"] = Get-WinQStepLanguage
    $report["main_scroll_viewer_loaded"] = ($window.FindName("MainScrollViewer") -is [System.Windows.Controls.ScrollViewer])
    $report["main_scroll_vertical_auto"] = (
        $window.FindName("MainScrollViewer").VerticalScrollBarVisibility -eq
        [System.Windows.Controls.ScrollBarVisibility]::Auto
    )
    $report["main_scroll_horizontal_disabled"] = (
        $window.FindName("MainScrollViewer").HorizontalScrollBarVisibility -eq
        [System.Windows.Controls.ScrollBarVisibility]::Disabled
    )
    $report["action_button_panel_wraps"] = ($window.FindName("ActionButtonPanel") -is [System.Windows.Controls.WrapPanel])
    $report["preview_button_text"] = [string]$window.FindName("PreviewButton").Content
    $report["config_tab_header"] = [string]$window.FindName("ConfigTab").Header
    $report["status_text_initial"] = [string]$window.FindName("StatusText").Text
    $report["cancel_button_loaded"] = ($window.FindName("CancelJobButton") -is [System.Windows.Controls.Button])
    $report["cancel_button_initially_disabled"] = (-not [bool]$window.FindName("CancelJobButton").IsEnabled)
    $report["job_status_text_loaded"] = ($window.FindName("JobStatusText") -is [System.Windows.Controls.TextBlock])
    $report["job_status_text_initial"] = [string]$window.FindName("JobStatusText").Text
    $report["artifact_summary_loaded"] = ($window.FindName("ArtifactSummaryText") -is [System.Windows.Controls.TextBox])
    $report["artifact_text_loaded"] = ($window.FindName("ArtifactText") -is [System.Windows.Controls.TextBox])
    $report["artifact_result_buttons_loaded"] = @(
        "ViewResultsButton", "SaveResultsButton"
    ).Where({ $window.FindName($_) -is [System.Windows.Controls.Button] }).Count
    $report["artifact_result_buttons_initially_disabled"] = @(
        "ViewResultsButton", "SaveResultsButton"
    ).Where({ [bool]$window.FindName($_).IsEnabled }).Count -eq 0
    $report["artifact_view_buttons_loaded"] = @(
        "ViewInputButton", "ViewOutputButton", "ViewMetadataButton", "ViewStdoutButton", "ViewStderrButton"
    ).Where({ $window.FindName($_) -is [System.Windows.Controls.Button] }).Count
    $report["artifact_view_buttons_initially_disabled"] = @(
        "ViewInputButton", "ViewOutputButton", "ViewMetadataButton", "ViewStdoutButton", "ViewStderrButton"
    ).Where({ [bool]$window.FindName($_).IsEnabled }).Count -eq 0
    $report["config_tab_loaded"] = ($window.FindName("DistroBox") -is [System.Windows.Controls.TextBox])
    $report["config_distro"] = [string]$window.FindName("DistroBox").Text
    $report["config_cp2k_command"] = [string]$window.FindName("Cp2kCommandBox").Text
    $report["config_data_dir"] = [string]$window.FindName("Cp2kDataDirBox").Text
    $report["config_ui_language"] = [string]$window.FindName("UiLanguageBox").SelectedItem.Tag
    $report["config_ui_language_text"] = [string]$window.FindName("UiLanguageBox").SelectedItem.Content
    $report["config_workspace_path"] = $configWorkspace
    $report["config_workspace_resolved_path"] = if ([System.IO.Path]::IsPathRooted($configWorkspace)) {
        [System.IO.Path]::GetFullPath($configWorkspace)
    }
    else {
        Resolve-WinQStepPath $configWorkspace
    }
    $report["config_workspace_encoding_ok"] = $report["config_workspace_resolved_path"].Contains($chineseFolderName)
    $report["config_validation_text"] = [string]$window.FindName("ConfigValidationText").Text
    $templateComboNames = @(
        "TemplateProjectBox", "TemplateRunTypeBox", "PrintLevelBox", "BasisSetFileBox", "PotentialFileBox",
        "XcFunctionalBox", "EpsScfBox", "ChargeBox", "MultiplicityBox",
        "CutoffBox", "RelCutoffBox", "MaxScfBox", "GeoOptimizerBox", "GeoMaxIterBox",
        "CellOptTypeBox", "CellOptOptimizerBox", "CellOptMaxIterBox",
        "CellOptPressureToleranceBox",
        "ScfMethodBox", "AddedMosBox", "DiagonalizationAlgorithmBox",
        "OtMinimizerBox", "OtPreconditionerBox", "MixingMethodBox",
        "MixingAlphaBox", "MixingBetaBox", "SmearingMethodBox",
        "ElectronicTemperatureBox", "KpointsSchemeBox", "KpointsGridBox",
        "KpointsWavefunctionsBox",
        "FallbackPeriodicBox", "FallbackCellABox", "FallbackCellBBox", "FallbackCellCBox"
    )
    $templateSectionGroupNames = @(
        "TemplateGlobalGroup", "TemplateDftGroup", "TemplateScfGroup", "TemplateMixingGroup",
        "TemplateSmearingGroup", "TemplateGeoOptGroup", "TemplateCellOptGroup",
        "TemplateCellGroup", "TemplateKpointsGroup", "TemplateKindGroup"
    )
    $report["template_tab_loaded"] = ($window.FindName("TemplateProjectBox") -is [System.Windows.Controls.ComboBox])
    $report["template_section_groups_loaded"] = $templateSectionGroupNames.Where({ $window.FindName($_) -is [System.Windows.Controls.GroupBox] }).Count
    $report["template_section_group_headers"] = @($templateSectionGroupNames | ForEach-Object { [string]$window.FindName($_).Header })
    $report["template_combo_fields_loaded"] = $templateComboNames.Where({ $window.FindName($_) -is [System.Windows.Controls.ComboBox] }).Count
    $report["template_combo_fields_editable"] = $templateComboNames.Where({ [bool]$window.FindName($_).IsEditable }).Count
    $report["template_run_type_options"] = @($window.FindName("TemplateRunTypeBox").Items | ForEach-Object { [string]$_.Content })
    $report["template_print_level_options"] = @($window.FindName("PrintLevelBox").Items | ForEach-Object { [string]$_.Content })
    $report["template_optimizer_options"] = @($window.FindName("GeoOptimizerBox").Items | ForEach-Object { [string]$_.Content })
    $report["template_cell_opt_type_options"] = @($window.FindName("CellOptTypeBox").Items | ForEach-Object { [string]$_.Content })
    $report["template_project_name"] = [string]$window.FindName("TemplateProjectBox").Text
    $report["template_run_type"] = [string]$window.FindName("TemplateRunTypeBox").Text
    $report["template_print_level"] = [string]$window.FindName("PrintLevelBox").Text
    $report["template_cutoff"] = [string]$window.FindName("CutoffBox").Text
    $report["template_scf_method"] = [string]$window.FindName("ScfMethodBox").Text
    $report["template_added_mos"] = [string]$window.FindName("AddedMosBox").Text
    $report["template_mixing_enabled"] = [bool]$window.FindName("MixingEnabledBox").IsChecked
    $report["template_smearing_enabled"] = [bool]$window.FindName("SmearingEnabledBox").IsChecked
    $report["template_cell_opt_type"] = [string]$window.FindName("CellOptTypeBox").Text
    $report["template_cell_opt_optimizer"] = [string]$window.FindName("CellOptOptimizerBox").Text
    $report["template_cell_opt_max_iter"] = [string]$window.FindName("CellOptMaxIterBox").Text
    $report["template_cell_opt_pressure_tolerance"] = [string]$window.FindName("CellOptPressureToleranceBox").Text
    $report["template_cell_opt_keep_angles"] = [bool]$window.FindName("CellOptKeepAnglesBox").IsChecked
    $report["template_cell_opt_keep_symmetry"] = [bool]$window.FindName("CellOptKeepSymmetryBox").IsChecked
    $report["template_kpoints_scheme"] = [string]$window.FindName("KpointsSchemeBox").Text
    $report["template_kpoints_grid"] = [string]$window.FindName("KpointsGridBox").Text
    $report["template_kpoints_full_grid"] = [bool]$window.FindName("KpointsFullGridBox").IsChecked
    $report["template_kpoints_symmetry"] = [bool]$window.FindName("KpointsSymmetryBox").IsChecked
    $report["template_kpoints_wavefunctions"] = [string]$window.FindName("KpointsWavefunctionsBox").Text
    $report["template_fallback_periodic"] = [string]$window.FindName("FallbackPeriodicBox").Text
    $report["template_fallback_cell_a"] = [string]$window.FindName("FallbackCellABox").Text
    $report["template_center_atoms"] = [bool]$window.FindName("CenterAtomsBox").IsChecked
    $kindEntriesView = $window.FindName("KindEntriesGrid").ItemsSource
    $report["kind_entries_grid_loaded"] = ($window.FindName("KindEntriesGrid") -is [System.Windows.Controls.DataGrid])
    $report["kind_entries_grid_rows"] = if ($null -ne $kindEntriesView) { $kindEntriesView.Count } else { 0 }
    $report["kinds_text_hidden"] = ($window.FindName("KindsText").Visibility -eq [System.Windows.Visibility]::Collapsed)
    $report["template_kinds_has_oxygen"] = ([string]$window.FindName("KindsText").Text).Contains("O")
    $report["template_validation_text"] = [string]$window.FindName("TemplateValidationText").Text
    $report["data_labels_grid_loaded"] = ($window.FindName("DataLabelsGrid") -is [System.Windows.Controls.DataGrid])
    $report["data_labels_grid_initially_collapsed"] = ($window.FindName("DataLabelsGrid").Visibility -eq [System.Windows.Visibility]::Collapsed)
    $report["history_grid_loaded"] = ($window.FindName("HistoryGrid") -is [System.Windows.Controls.DataGrid])
    $mainTabs = $window.FindName("MainTabs")
    $tabOrder = @($mainTabs.Items | ForEach-Object { [string]$_.Name })
    $report["tab_order"] = $tabOrder
    $templateIndex = [array]::IndexOf($tabOrder, "TemplateTab")
    $previewIndex = [array]::IndexOf($tabOrder, "InputPreviewTab")
    $report["template_preview_tabs_adjacent"] = ($templateIndex -ge 0 -and $previewIndex -eq ($templateIndex + 1))
    $report["console_output_encoding"] = [Console]::OutputEncoding.WebName
    $report["pythonioencoding"] = $env:PYTHONIOENCODING
    $report["encoding_probe_exit_code"] = $encodingProbeResult.ExitCode
    $report["encoding_probe_text"] = $encodingProbe.text
    $report["encoding_probe_ok"] = $encodingProbe.text -eq $expectedEncodingText
    $report["preview_exit_code"] = $previewResult.ExitCode
    $report["preview_input_exists"] = [System.IO.File]::Exists($previewMetadata.files.input.path)
    $report["preview_summary_status"] = $previewMetadata.cp2k_output.status
    $report["existing_preview_exit_code"] = $existingPreviewResult.ExitCode
    $report["existing_preview_mode"] = $existingPreviewMetadata.job.mode
    $report["existing_preview_input_exists"] = [System.IO.File]::Exists($existingPreviewMetadata.files.input.path)
    $report["existing_preview_summary_status"] = $existingPreviewMetadata.cp2k_output.status
    $report["existing_preview_input_path"] = [string]$existingPreviewMetadata.files.input.path
    $report["existing_preview_path_encoding_ok"] = ([string]$existingPreviewMetadata.files.input.path).Contains($chineseFolderName)
    $report["history_exit_code"] = $historyResult.ExitCode
    $report["history_job_count"] = $historyJobs.Count
    $report["history_first_mode"] = if ($historyJobs.Count -gt 0) { [string]$historyJobs[0].mode } else { "" }
    $report["history_first_warning_count"] = if ($historyJobs.Count -gt 0) { $historyJobs[0].warning_count } else { $null }
    $report["existing_mode_input_enabled"] = [bool]$window.FindName("ExistingInputPathBox").IsEnabled
    $report["existing_mode_import_enabled"] = [bool]$window.FindName("ImportButton").IsEnabled
    $report | ConvertTo-Json -Depth 5
    exit 0
}

[void](Test-WinQStepGuiPrerequisites)
$app = [System.Windows.Application]::new()
$window = $null
$app.Add_DispatcherUnhandledException({
    param($sender, $eventArgs)
    $message = $eventArgs.Exception.Message
    try {
        $caption = Get-WinQStepText "message.error_caption"
        [System.Windows.MessageBox]::Show(
            $window,
            $message,
            $caption,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
    catch {
        Write-Error $message
    }
    $eventArgs.Handled = $true
}.GetNewClosure())
$window = New-WinQStepWindow
[void]$app.Run($window)

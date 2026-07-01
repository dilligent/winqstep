#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SmokeTest,
    [switch]$LifecycleSmokeTest,
    [switch]$ButtonSmokeTest,
    [switch]$EditedPreviewSmokeTest,
    [switch]$AsyncRunSmokeTest,
    [switch]$PythonInvokeSmokeTest,
    [switch]$EnvironmentDisplaySmokeTest,
    [switch]$BatchSmokeTest,
    [switch]$BatchRunSmokeTest,
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
$SuppressGuiMessageBoxes = [bool]($ButtonSmokeTest -or $EditedPreviewSmokeTest -or $AsyncRunSmokeTest -or $BatchSmokeTest -or $BatchRunSmokeTest)
$EditedPreviewSmokeTestEnabled = [bool]$EditedPreviewSmokeTest
$BatchRunSmokeTestEnabled = [bool]$BatchRunSmokeTest
$EditedPreviewSmokeState = @{
    Report = $null
    ConfirmationRequested = $false
    ConfirmationSuppressed = $false
    ConfirmationResult = ""
}
$BatchRunSmokeState = @{
    Report = $null
}
$Script:SuppressGuiMessageBoxes = $SuppressGuiMessageBoxes
$Script:EditedPreviewSmokeStartAsyncJob = $null
$Script:EnvironmentDisplaySmokeFormatter = $null
$Script:StructurePreviewSmokeApplyInteraction = $null
$Script:StructurePreviewSmokeGetState = $null
$Script:StructurePreviewSmokeToggleAtomSelection = $null
$Script:StructurePreviewSmokeApplyFixedAtoms = $null

. (Join-Path $PSScriptRoot "gui\WinQStep.GuiHost.ps1")
. (Join-Path $PSScriptRoot "gui\WinQStep.GuiControls.ps1")

function Ensure-WinQStepLocalExampleFile {
    param(
        [Parameter(Mandatory = $true)][string]$LocalRelativePath,
        [Parameter(Mandatory = $true)][string]$ExampleRelativePath
    )

    $localPath = Resolve-WinQStepPath $LocalRelativePath
    if (Test-Path -LiteralPath $localPath) {
        return $localPath
    }

    $examplePath = Resolve-WinQStepPath $ExampleRelativePath
    if (-not (Test-Path -LiteralPath $examplePath)) {
        throw "Example file was not found: $examplePath"
    }
    $parent = Split-Path -Parent $localPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    Copy-Item -LiteralPath $examplePath -Destination $localPath -Force
    return $localPath
}

function New-WinQStepWindow {
    Add-WinQStepWpfAssemblies
    $defaultConfigPath = Ensure-WinQStepLocalExampleFile "examples\winqstep.config.json" "examples\winqstep.config.example.json"
    $defaultTemplatePath = Ensure-WinQStepLocalExampleFile "examples\templates\energy_pbe.json" "examples\templates\energy_pbe.example.json"
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
    $names = @(Get-WinQStepGuiControlNames)
    foreach ($name in $names) {
        $controls[$name] = $window.FindName($name)
    }

    $ApplyLocalizationToControls = {
        Set-WinQStepLocalizedControls -Window $window -Controls $controls
    }.GetNewClosure()
    & $ApplyLocalizationToControls

    $controls["ConfigPathBox"].Text = $defaultConfigPath
    $controls["TemplatePathBox"].Text = $defaultTemplatePath
    $controls["StructurePathBox"].Text = Resolve-WinQStepPath "tests\fixtures\structures\water.xyz"
    $defaultExistingInputPath = Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"
    $controls["ExistingInputPathBox"].Text = $defaultExistingInputPath
    $controls["BatchInputFilesBox"].Text = $defaultExistingInputPath
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
    $batchQueueButtons = @(
        $controls["ResumeBatchButton"],
        $controls["SkipBatchItemButton"],
        $controls["RerunBatchItemButton"],
        $controls["CancelBatchItemButton"]
    )
    foreach ($button in $batchQueueButtons) {
        $button.IsEnabled = $false
    }
    $batchQueueSelectionOverride = @{ Index = 0 }
    $artifactState = @{ Current = $null }
    $previewState = @{ Current = $null }
    $jobState = @{ Current = $null }
    $structurePreviewState = @{
        Current = $null
        Radius = 5.0
        DefaultDistance = 5.0
        Distance = 5.0
        Yaw = 0.0
        Pitch = 0.0
        PanX = 0.0
        PanY = 0.0
        IsDragging = $false
        DragMode = ""
        LastPoint = $null
        DragStartPoint = $null
        DragMoved = $false
        PendingSelectionKey = ""
        AtomModels = @{}
        AtomModelsByIndex = @{}
        SelectedAtomIndices = @{}
    }

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
        $controls["BrowseExistingInputButton"], $controls["BrowseBatchInputDirButton"],
        $controls["BrowseBatchInputFilesButton"], $controls["BrowseBatchInputListButton"],
        $controls["BrowseJobDirButton"]
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
        if ($null -ne $UpdateRunTargetStatus) {
            & $UpdateRunTargetStatus
        }
        if ($null -ne $SyncTemplateDependencyState) {
            & $SyncTemplateDependencyState
        }
    }.GetNewClosure()

    $ApplySelectedLanguage = {
        $language = & $GetUiLanguageSelection
        $null = Initialize-WinQStepLocalization $language
        & $ApplyLocalizationToControls
        & $SetUiLanguageSelection $language
        if ($null -ne $UpdateStructureSelectionControls) {
            & $UpdateStructureSelectionControls
        }
        if ($null -ne $UpdateModeControls) {
            & $UpdateModeControls
        }
        if ($null -ne $UpdateRunTargetStatus) {
            & $UpdateRunTargetStatus
        }
        if ($null -ne $SyncTemplateDependencyState) {
            & $SyncTemplateDependencyState
        }
    }.GetNewClosure()

    $TestIsExistingInputMode = {
        return [bool]$controls["ExistingInputModeRadio"].IsChecked
    }.GetNewClosure()

    $TestIsExistingInputBatchMode = {
        return [bool]$controls["ExistingInputBatchModeRadio"].IsChecked
    }.GetNewClosure()

    $TestUsesExistingInputPath = {
        return ((& $TestIsExistingInputMode) -or (& $TestIsExistingInputBatchMode))
    }.GetNewClosure()

    $NormalizeRunTargetPreviewText = {
        param([AllowEmptyString()][string]$Text)
        return (($Text -replace "`r`n", "`n") -replace "`r", "`n")
    }.GetNewClosure()

    $TestPreviewHasManualEdits = {
        $current = $previewState["Current"]
        if ($null -eq $current) {
            return $false
        }
        $previewText = [string]$controls["PreviewText"].Text
        if ([string]::IsNullOrWhiteSpace($previewText)) {
            return $false
        }
        $originalText = [string]$current["Text"]
        return ((& $NormalizeRunTargetPreviewText $previewText) -ne (& $NormalizeRunTargetPreviewText $originalText))
    }.GetNewClosure()

    $GetRunTargetDisplayPath = {
        param([AllowEmptyString()][string]$PathText)
        $trimmed = ([string]$PathText).Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            return ""
        }
        try {
            if ([System.IO.Path]::IsPathRooted($trimmed)) {
                return [System.IO.Path]::GetFileName($trimmed)
            }
        }
        catch {
        }
        return $trimmed
    }.GetNewClosure()

    $ResolveRunTargetPath = {
        param([AllowEmptyString()][string]$PathText)
        $trimmed = ([string]$PathText).Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            return ""
        }
        try {
            if ([System.IO.Path]::IsPathRooted($trimmed)) {
                return [System.IO.Path]::GetFullPath($trimmed)
            }
            return Resolve-WinQStepPath $trimmed
        }
        catch {
            return $trimmed
        }
    }.GetNewClosure()

    $GetBatchInputFilePaths = {
        $text = [string]$controls["BatchInputFilesBox"].Text
        return @(
            foreach ($part in ($text -split '[;\r\n]+')) {
                $trimmed = ([string]$part).Trim()
                if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                    $trimmed
                }
            }
        )
    }.GetNewClosure()

    $ClearDefaultBatchInputFilesIfNeeded = {
        param([AllowEmptyString()][string]$SourceText)
        if ([string]::IsNullOrWhiteSpace($SourceText)) {
            return
        }
        if ([string]$controls["BatchInputFilesBox"].Text -eq $defaultExistingInputPath) {
            $controls["BatchInputFilesBox"].Text = ""
        }
    }.GetNewClosure()

    $ResolveBatchInputPath = {
        param(
            [AllowEmptyString()][string]$PathText,
            [AllowEmptyString()][string]$BaseDirectory = ""
        )
        $trimmed = ([string]$PathText).Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            return ""
        }
        try {
            if ([System.IO.Path]::IsPathRooted($trimmed)) {
                return [System.IO.Path]::GetFullPath($trimmed)
            }
            if (-not [string]::IsNullOrWhiteSpace($BaseDirectory)) {
                return [System.IO.Path]::GetFullPath((Join-Path $BaseDirectory $trimmed))
            }
            return & $ResolveRunTargetPath $trimmed
        }
        catch {
            return $trimmed
        }
    }.GetNewClosure()

    $GetRunTargetBatchInputCountForSources = {
        param(
            [string[]]$Directories = @(),
            [string[]]$Inputs = @(),
            [string[]]$Lists = @()
        )
        $seen = @{}
        $AddInputPath = {
            param(
                [AllowEmptyString()][string]$PathText,
                [AllowEmptyString()][string]$BaseDirectory = ""
            )
            $resolved = & $ResolveBatchInputPath $PathText $BaseDirectory
            if ([string]::IsNullOrWhiteSpace($resolved)) {
                return
            }
            $key = $resolved.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
            }
        }

        foreach ($directoryText in @($Directories)) {
            $directory = & $ResolveRunTargetPath $directoryText
            if ([System.IO.Directory]::Exists($directory)) {
                foreach ($inputPath in [System.IO.Directory]::EnumerateFiles($directory, "*.inp")) {
                    & $AddInputPath $inputPath
                }
            }
        }
        foreach ($inputText in @($Inputs)) {
            & $AddInputPath $inputText
        }
        foreach ($listText in @($Lists)) {
            $listPath = & $ResolveRunTargetPath $listText
            if (-not [System.IO.File]::Exists($listPath)) {
                continue
            }
            $baseDirectory = [System.IO.Path]::GetDirectoryName($listPath)
            foreach ($line in [System.IO.File]::ReadLines($listPath, [System.Text.Encoding]::UTF8)) {
                $trimmed = ([string]$line).Trim()
                if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
                    continue
                }
                & $AddInputPath $trimmed $baseDirectory
            }
        }
        return $seen.Count
    }.GetNewClosure()

    $GetRunTargetBatchInputCount = {
        param([Parameter(Mandatory = $true)][string]$PathText)
        $resolved = & $ResolveRunTargetPath $PathText
        if ([string]::IsNullOrWhiteSpace($resolved)) {
            return 0
        }
        if ([System.IO.Directory]::Exists($resolved)) {
            return (& $GetRunTargetBatchInputCountForSources -Directories @($PathText) -Inputs @() -Lists @())
        }
        if ([System.IO.File]::Exists($resolved)) {
            $extension = [System.IO.Path]::GetExtension($resolved)
            if ($extension.Equals(".inp", [System.StringComparison]::OrdinalIgnoreCase)) {
                return (& $GetRunTargetBatchInputCountForSources -Directories @() -Inputs @($PathText) -Lists @())
            }
            return (& $GetRunTargetBatchInputCountForSources -Directories @() -Inputs @() -Lists @($PathText))
        }
        return (& $GetRunTargetBatchInputCountForSources -Directories @() -Inputs @($PathText) -Lists @())
    }.GetNewClosure()

    $GetBatchInputSelectionSummary = {
        $directoryText = ([string]$controls["BatchInputDirBox"].Text).Trim()
        $inputTexts = @(& $GetBatchInputFilePaths)
        $listText = ([string]$controls["BatchInputListBox"].Text).Trim()
        $directoryTexts = @()
        $listTexts = @()
        if (-not [string]::IsNullOrWhiteSpace($directoryText)) {
            $directoryTexts += $directoryText
        }
        if (-not [string]::IsNullOrWhiteSpace($listText)) {
            $listTexts += $listText
        }

        $sourceKinds = @()
        if ($directoryTexts.Count -gt 0) {
            $sourceKinds += "directory"
        }
        if ($inputTexts.Count -gt 0) {
            $sourceKinds += "input"
        }
        if ($listTexts.Count -gt 0) {
            $sourceKinds += "list"
        }

        if ($sourceKinds.Count -eq 0) {
            $legacyText = ([string]$controls["ExistingInputPathBox"].Text).Trim()
            $legacyResolved = & $ResolveRunTargetPath $legacyText
            $legacyKind = "empty"
            if (-not [string]::IsNullOrWhiteSpace($legacyText)) {
                if ([System.IO.Directory]::Exists($legacyResolved)) {
                    $legacyKind = "directory"
                }
                elseif ([System.IO.File]::Exists($legacyResolved)) {
                    $extension = [System.IO.Path]::GetExtension($legacyResolved)
                    if ($extension.Equals(".inp", [System.StringComparison]::OrdinalIgnoreCase)) {
                        $legacyKind = "input"
                    }
                    else {
                        $legacyKind = "list"
                    }
                }
                else {
                    $legacyKind = "path"
                }
            }
            return [ordered]@{
                Count = (& $GetRunTargetBatchInputCount $legacyText)
                SourceKind = $legacyKind
                Display = if ($legacyKind -eq "input") { & $GetRunTargetDisplayPath $legacyText } else { $legacyText }
                ToolTip = $legacyResolved
            }
        }

        $count = & $GetRunTargetBatchInputCountForSources -Directories $directoryTexts -Inputs $inputTexts -Lists $listTexts
        $kind = "selection"
        if ($sourceKinds.Count -eq 1) {
            if ($sourceKinds[0] -eq "directory") {
                $kind = "directory"
            }
            elseif ($sourceKinds[0] -eq "list") {
                $kind = "list"
            }
            elseif ($sourceKinds[0] -eq "input" -and $inputTexts.Count -eq 1) {
                $kind = "input"
            }
        }
        $tooltipParts = @()
        if ($directoryTexts.Count -gt 0) {
            $tooltipParts += ("Directories: " + ($directoryTexts -join "; "))
        }
        if ($inputTexts.Count -gt 0) {
            $tooltipParts += ("Inputs: " + ($inputTexts -join "; "))
        }
        if ($listTexts.Count -gt 0) {
            $tooltipParts += ("Input lists: " + ($listTexts -join "; "))
        }
        return [ordered]@{
            Count = $count
            SourceKind = $kind
            Display = if ($inputTexts.Count -eq 1) { & $GetRunTargetDisplayPath $inputTexts[0] } else { "" }
            ToolTip = ($tooltipParts -join "`r`n")
        }
    }.GetNewClosure()

    $SetBatchInputCountText = {
        param(
            [int]$Count,
            [AllowEmptyString()][string]$ToolTip = ""
        )
        if ($null -eq $controls["BatchInputCountText"]) {
            return
        }
        $text = Format-WinQStepText "batch_input_count.files" @($Count)
        $controls["BatchInputCountText"].Text = $text
        $controls["BatchInputCountText"].ToolTip = if ([string]::IsNullOrWhiteSpace($ToolTip)) { $text } else { $ToolTip }
    }.GetNewClosure()

    $SetRunTargetText = {
        param(
            [Parameter(Mandatory = $true)][string]$Key,
            [object[]]$Arguments = @(),
            [AllowEmptyString()][string]$ToolTip = ""
        )
        $text = Format-WinQStepText $Key $Arguments
        $controls["RunTargetText"].Text = $text
        $controls["RunTargetText"].ToolTip = if ([string]::IsNullOrWhiteSpace($ToolTip)) { $text } else { $ToolTip }
    }.GetNewClosure()

    $UpdateRunTargetStatus = {
        if ($null -eq $controls["RunTargetText"]) {
            return
        }
        if ((& $TestPreviewHasManualEdits) -and -not (& $TestIsExistingInputBatchMode)) {
            $current = $previewState["Current"]
            $toolTip = if ($null -ne $current) { [string]$current["InputPath"] } else { "" }
            & $SetRunTargetText "run_target.edited_preview" @() $toolTip
            return
        }
        if (& $TestIsExistingInputBatchMode) {
            $summary = & $GetBatchInputSelectionSummary
            $count = [int]$summary["Count"]
            $toolTip = [string]$summary["ToolTip"]
            & $SetBatchInputCountText $count $toolTip
            switch ([string]$summary["SourceKind"]) {
                "directory" {
                    & $SetRunTargetText "run_target.batch_directory" @($count) $toolTip
                }
                "list" {
                    & $SetRunTargetText "run_target.batch_list" @($count) $toolTip
                }
                "input" {
                    & $SetRunTargetText "run_target.batch_input" @([string]$summary["Display"]) $toolTip
                }
                "selection" {
                    & $SetRunTargetText "run_target.batch_selection" @($count) $toolTip
                }
                default {
                    & $SetRunTargetText "run_target.batch_path" @([string]$summary["Display"]) $toolTip
                }
            }
            return
        }
        if (& $TestIsExistingInputMode) {
            $pathText = ([string]$controls["ExistingInputPathBox"].Text).Trim()
            $resolved = & $ResolveRunTargetPath $pathText
            & $SetRunTargetText "run_target.existing_input" @((& $GetRunTargetDisplayPath $pathText)) $resolved
            return
        }
        & $SetRunTargetText "run_target.workflow"
    }.GetNewClosure()
    $Script:RunTargetSmokeUpdate = $UpdateRunTargetStatus

    $UpdateExistingInputPathLabel = {
        if (& $TestIsExistingInputBatchMode) {
            Set-WinQStepText $controls["ExistingInputPathLabel"] "label.batch_inputs"
        }
        else {
            Set-WinQStepText $controls["ExistingInputPathLabel"] "label.existing_input"
        }
    }.GetNewClosure()

    $UpdateModeControls = {
        $usesExistingInputPath = & $TestUsesExistingInputPath
        $isBatchMode = & $TestIsExistingInputBatchMode
        $isExistingInputMode = & $TestIsExistingInputMode
        foreach ($name in @("TemplatePathBox", "BrowseTemplateButton", "StructurePathBox", "BrowseStructureButton", "ProjectNameBox")) {
            $controls[$name].IsEnabled = -not $usesExistingInputPath
        }
        $existingVisibility = if ($isBatchMode) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
        foreach ($name in @("ExistingInputPathLabel", "ExistingInputPathBox", "BrowseExistingInputButton")) {
            $controls[$name].Visibility = $existingVisibility
        }
        foreach ($name in @("ExistingInputPathBox", "BrowseExistingInputButton")) {
            $controls[$name].IsEnabled = $isExistingInputMode
        }
        $controls["BatchInputsPanel"].Visibility = if ($isBatchMode) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        foreach ($name in @("BatchInputDirBox", "BrowseBatchInputDirButton", "BatchInputFilesBox", "BrowseBatchInputFilesButton", "BatchInputListBox", "BrowseBatchInputListButton")) {
            $controls[$name].IsEnabled = $isBatchMode
        }
        $controls["BatchStopOnFailureBox"].IsEnabled = $isBatchMode
        $controls["ImportButton"].IsEnabled = -not $usesExistingInputPath
        & $UpdateExistingInputPathLabel
        & $UpdateRunTargetStatus
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
        if ($null -ne $UpdateBatchQueueControls) {
            & $UpdateBatchQueueControls
        }
    }.GetNewClosure()

    $GetCurrentBatchSummaryPath = {
        $current = $artifactState["Current"]
        if ($null -ne $current -and [string]$current["mode"] -eq "existing_input_batch" -and $null -ne $current["paths"]) {
            $path = [string]$current["paths"]["metadata"]
            if (-not [string]::IsNullOrWhiteSpace($path)) {
                return $path
            }
        }
        $jobDir = & $ResolveWindowsWorkspacePath $controls["JobDirBox"].Text
        if ([string]::IsNullOrWhiteSpace($jobDir)) {
            return ""
        }
        return (Join-Path $jobDir "batch.winqstep-batch.json")
    }.GetNewClosure()

    $GetSelectedBatchRow = {
        $overrideIndex = [int]$batchQueueSelectionOverride["Index"]
        if ($overrideIndex -gt 0) {
            $current = $artifactState["Current"]
            if ($null -ne $current -and $null -ne $current["batch_summary"]) {
                foreach ($row in @($current["batch_summary"].items)) {
                    try {
                        if ([int]$row.index -eq $overrideIndex) {
                            return $row
                        }
                    }
                    catch {
                    }
                }
            }
        }
        $row = $controls["BatchResultsGrid"].SelectedItem
        if ($null -eq $row) {
            return $null
        }
        return $row
    }.GetNewClosure()

    $GetSelectedBatchItemIndex = {
        $row = & $GetSelectedBatchRow
        if ($null -eq $row) {
            return 0
        }
        try {
            return [int]$row.index
        }
        catch {
            return 0
        }
    }.GetNewClosure()

    $UpdateBatchQueueControls = {
        $summaryPath = & $GetCurrentBatchSummaryPath
        $hasSummary = (-not [string]::IsNullOrWhiteSpace($summaryPath)) -and [System.IO.File]::Exists($summaryPath)
        $currentJob = $jobState["Current"]
        $isBatchRunning = ($null -ne $currentJob -and [string]$currentJob["Mode"] -eq "existing_input_batch")
        $selectedRow = & $GetSelectedBatchRow
        $selectedStatus = if ($null -ne $selectedRow) { [string]$selectedRow.status } else { "" }
        $hasSelected = ($null -ne $selectedRow -and (& $GetSelectedBatchItemIndex) -gt 0)

        $controls["ResumeBatchButton"].IsEnabled = ($hasSummary -and $null -eq $currentJob)
        $controls["SkipBatchItemButton"].IsEnabled = (
            $hasSummary -and $hasSelected -and
            $selectedStatus -notin @("running", "cancel_requested", "succeeded")
        )
        $controls["RerunBatchItemButton"].IsEnabled = (
            $hasSummary -and $hasSelected -and
            $selectedStatus -notin @("running", "cancel_requested")
        )
        $controls["CancelBatchItemButton"].IsEnabled = (
            $hasSummary -and $hasSelected -and
            $selectedStatus -notin @("succeeded", "skipped", "cancelled")
        )
        if (-not $isBatchRunning -and $selectedStatus -eq "running") {
            $controls["CancelBatchItemButton"].IsEnabled = $hasSummary -and $hasSelected
        }
    }.GetNewClosure()

    $Script:BatchQueueSmokeSelectIndex = {
        param([int]$Index)
        $batchQueueSelectionOverride["Index"] = $Index
        & $UpdateBatchQueueControls
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

    $SelectMultipleFilePaths = {
        param([Parameter(Mandatory = $true)]$TextBox, [Parameter(Mandatory = $true)][string]$Filter)
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Filter = $Filter
        $dialog.Multiselect = $true
        $firstPath = @(& $GetBatchInputFilePaths | Select-Object -First 1)
        if ($firstPath.Count -gt 0 -and [System.IO.File]::Exists($firstPath[0])) {
            $dialog.InitialDirectory = Split-Path -Parent $firstPath[0]
        }
        if ($dialog.ShowDialog($window)) {
            $TextBox.Text = ([string[]]$dialog.FileNames) -join "`r`n"
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

    $GetExistingInputBatchSelectionArguments = {
        $arguments = @()
        $directoryText = ([string]$controls["BatchInputDirBox"].Text).Trim()
        $listText = ([string]$controls["BatchInputListBox"].Text).Trim()
        if (-not [string]::IsNullOrWhiteSpace($directoryText)) {
            $arguments += @("--input-dir", $directoryText)
        }
        foreach ($inputText in @(& $GetBatchInputFilePaths)) {
            $arguments += @("--input", $inputText)
        }
        if (-not [string]::IsNullOrWhiteSpace($listText)) {
            $arguments += @("--input-list", $listText)
        }
        if ($arguments.Count -gt 0) {
            return $arguments
        }

        $inputText = ([string]$controls["ExistingInputPathBox"].Text).Trim()
        if ([string]::IsNullOrWhiteSpace($inputText)) {
            throw "Batch inputs path is empty."
        }
        if ([System.IO.Directory]::Exists($inputText)) {
            return @("--input-dir", $inputText)
        }
        if ([System.IO.File]::Exists($inputText)) {
            $extension = [System.IO.Path]::GetExtension($inputText)
            if ($extension.Equals(".inp", [System.StringComparison]::OrdinalIgnoreCase)) {
                return @("--input", $inputText)
            }
            return @("--input-list", $inputText)
        }
        return @("--input", $inputText)
    }.GetNewClosure()

    $GetExistingInputBatchArguments = {
        param([bool]$PrepareOnly)
        $arguments = @(
            "scripts\run_existing_input_batch.py",
            "--config", $controls["ConfigPathBox"].Text
        )
        $arguments += (& $GetExistingInputBatchSelectionArguments)
        $arguments += @(
            "--job-dir", $controls["JobDirBox"].Text,
            "--job-layout", "subdirs"
        )
        if ([bool]$controls["BatchStopOnFailureBox"].IsChecked) {
            $arguments += "--stop-on-failure"
        }
        if ($PrepareOnly) {
            $arguments += "--prepare-only"
        }
        return $arguments
    }.GetNewClosure()

    $GetActiveJobArguments = {
        param([bool]$PrepareOnly)
        if (& $TestIsExistingInputBatchMode) {
            return (& $GetExistingInputBatchArguments $PrepareOnly)
        }
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
        if ($null -ne $UpdateRunTargetStatus) {
            & $UpdateRunTargetStatus
        }
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
        & $UpdateRunTargetStatus
    }.GetNewClosure()

    $FormatLogWithSummary = {
        param([Parameter(Mandatory = $true)]$Metadata, [Parameter(Mandatory = $true)][string]$Output)
        $summaryText = Format-Cp2kSummary $Metadata
        if ([string]::IsNullOrWhiteSpace($summaryText)) {
            return $Output
        }
        return "$summaryText`r`n`r`n$Output"
    }.GetNewClosure()

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
        if ([string]$State["Mode"] -eq "existing_input_batch") {
            return "Running batch PID $($process.Id) | job=$($State["JobDir"]) | summary=$($State["BatchSummaryPath"])"
        }
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
        if ($null -ne $UpdateBatchQueueControls) {
            & $UpdateBatchQueueControls
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
        if ([string]$State["Mode"] -eq "existing_input_batch") {
            $sections = @(
                "Existing input batch running asynchronously.`r`nPID=$($process.Id)`r`njob_dir=$($State["JobDir"])`r`nsummary=$($State["BatchSummaryPath"])`r`nwrapper_stdout=$($State["WrapperStdoutPath"])`r`nwrapper_stderr=$($State["WrapperStderrPath"])"
            )
            $summary = & $ReadMetadataFile ([string]$State["BatchSummaryPath"])
            if ($null -ne $summary) {
                $items = if ($null -ne $summary.items) { @($summary.items) } else { @() }
                $total = [int]$summary.input_count
                $completed = if ($null -ne $summary.completed_count) { [int]$summary.completed_count } else { 0 }
                $running = if ($null -ne $summary.running_count) { [int]$summary.running_count } else { 0 }
                $current = $completed + $running
                if ([string]$summary.status -eq "running" -and $running -eq 0 -and $total -gt 0 -and $completed -lt $total) {
                    $current = $completed + 1
                }
                elseif ($total -gt 0 -and $current -gt $total) {
                    $current = $total
                }
                $sections += (
                    @(
                        "Existing input batch: status=$($summary.status)",
                        "progress: current=$current/$total, completed=$completed/$total, queued=$($summary.queued_count), running=$running, succeeded=$($summary.succeeded_count), failed=$($summary.failed_count), errors=$($summary.error_count), skipped=$($summary.skipped_count), cancelled=$($summary.cancelled_count)",
                        "inputs=$($summary.input_count), items=$($summary.item_count), prepared=$($summary.prepared_count), queued=$($summary.queued_count), running=$($summary.running_count), succeeded=$($summary.succeeded_count), failed=$($summary.failed_count), errors=$($summary.error_count)",
                        "job_dir=$($summary.job_dir)",
                        "summary=$($summary.summary_path)",
                        "visible_items=$($items.Count)"
                    ) -join "`r`n"
                )
            }
            $sections = & $AddTailSection $sections "wrapper stdout tail" ([string]$State["WrapperStdoutPath"]) 40
            $sections = & $AddTailSection $sections "wrapper stderr tail" ([string]$State["WrapperStderrPath"]) 40
            return ($sections -join "`r`n`r`n")
        }
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
        if ($items.Count -gt 0) {
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

    $GetBatchSummaryResult = {
        param([Parameter(Mandatory = $true)]$Result)
        if (-not [string]::IsNullOrWhiteSpace([string]$Result.Output)) {
            try {
                return ($Result.Output | ConvertFrom-Json)
            }
            catch {
            }
        }
        if ($Result.ExitCode -ne 0 -and -not [string]::IsNullOrWhiteSpace([string]$Result.Error)) {
            throw $Result.Error
        }
        $raw = [string]$Result.Output
        if (-not [string]::IsNullOrWhiteSpace([string]$Result.Error)) {
            $raw = (($raw, [string]$Result.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n"
        }
        throw "Batch command did not return JSON. Raw output:`n$raw"
    }.GetNewClosure()

    $GetBatchSummaryItems = {
        param($Summary)
        if ($null -eq $Summary -or $null -eq $Summary.items) {
            return @()
        }
        return @($Summary.items)
    }.GetNewClosure()

    $GetJsonIntProperty = {
        param($Object, [Parameter(Mandatory = $true)][string]$Name)
        $text = & $GetJsonProperty $Object $Name "0"
        try {
            return [int]$text
        }
        catch {
            return 0
        }
    }.GetNewClosure()

    $GetBatchProgressText = {
        param([Parameter(Mandatory = $true)]$Summary)
        $status = & $GetJsonProperty $Summary "status"
        $total = & $GetJsonIntProperty $Summary "input_count"
        $completed = & $GetJsonIntProperty $Summary "completed_count"
        $running = & $GetJsonIntProperty $Summary "running_count"
        $current = $completed + $running
        if ($status -eq "running" -and $running -eq 0 -and $total -gt 0 -and $completed -lt $total) {
            $current = $completed + 1
        }
        elseif ($total -gt 0 -and $current -gt $total) {
            $current = $total
        }
        return "current=$current/$total, completed=$completed/$total, queued=$(& $GetJsonProperty $Summary "queued_count"), running=$running, succeeded=$(& $GetJsonProperty $Summary "succeeded_count"), failed=$(& $GetJsonProperty $Summary "failed_count"), errors=$(& $GetJsonProperty $Summary "error_count"), skipped=$(& $GetJsonProperty $Summary "skipped_count"), cancelled=$(& $GetJsonProperty $Summary "cancelled_count")"
    }.GetNewClosure()

    $NewBatchResultRows = {
        param([Parameter(Mandatory = $true)]$Summary)
        $rows = @()
        foreach ($item in @(& $GetBatchSummaryItems $Summary)) {
            $rows += [pscustomobject][ordered]@{
                index = (& $GetJsonProperty $item "index")
                status = (& $GetJsonProperty $item "status")
                attempt = (& $GetJsonProperty $item "attempt")
                returncode = (& $GetJsonProperty $item "returncode")
                input_path = (& $GetJsonProperty $item "input_path")
                job_dir = (& $GetJsonProperty $item "job_dir")
                metadata_path = (& $GetJsonProperty $item "metadata_path")
                output_path = (& $GetJsonProperty $item "output_path")
                stdout_path = (& $GetJsonProperty $item "stdout_path")
                stderr_path = (& $GetJsonProperty $item "stderr_path")
                generated_artifact_count = (& $GetJsonProperty $item "generated_artifact_count")
                error = (& $GetJsonProperty $item "error")
            }
        }
        return $rows
    }.GetNewClosure()

    $FormatBatchResultTable = {
        param([Parameter(Mandatory = $true)]$Summary)
        $rows = @(& $NewBatchResultRows $Summary)
        if ($rows.Count -eq 0) {
            return "Batch result table: no items"
        }
        $lines = @(
            "Batch result table",
            ("{0,5} {1,-12} {2,6} {3,-40} {4,-40} {5}" -f "#", "status", "code", "input", "output", "error")
        )
        foreach ($row in $rows) {
            $inputPath = [string]$row.input_path
            $outputPath = [string]$row.output_path
            if ($inputPath.Length -gt 40) {
                $inputPath = "..." + $inputPath.Substring($inputPath.Length - 37)
            }
            if ($outputPath.Length -gt 40) {
                $outputPath = "..." + $outputPath.Substring($outputPath.Length - 37)
            }
            $lines += ("{0,5} {1,-12} {2,6} {3,-40} {4,-40} {5}" -f $row.index, $row.status, $row.returncode, $inputPath, $outputPath, $row.error)
        }
        return ($lines -join "`r`n")
    }.GetNewClosure()

    $EscapeBatchTsvValue = {
        param($Value)
        if ($null -eq $Value) {
            return ""
        }
        return ([string]$Value) -replace "`t", " " -replace "`r?`n", " "
    }.GetNewClosure()

    $FormatBatchResultTsv = {
        param([Parameter(Mandatory = $true)]$Summary)
        $columns = @("index", "status", "returncode", "input_path", "job_dir", "metadata_path", "output_path", "stdout_path", "stderr_path", "generated_artifact_count", "error", "attempt")
        $lines = @($columns -join "`t")
        foreach ($row in @(& $NewBatchResultRows $Summary)) {
            $values = foreach ($column in $columns) {
                $property = $row.PSObject.Properties[$column]
                $value = if ($null -ne $property) { $property.Value } else { "" }
                & $EscapeBatchTsvValue $value
            }
            $lines += ($values -join "`t")
        }
        return (($lines -join "`r`n") + "`r`n")
    }.GetNewClosure()

    $FormatBatchSummary = {
        param([Parameter(Mandatory = $true)]$Summary)
        $items = @(& $GetBatchSummaryItems $Summary)
        $lines = @(
            "Existing input batch: status=$(& $GetJsonProperty $Summary "status")",
            "progress: $(& $GetBatchProgressText $Summary)",
            "inputs=$(& $GetJsonProperty $Summary "input_count"), items=$(& $GetJsonProperty $Summary "item_count"), prepared=$(& $GetJsonProperty $Summary "prepared_count"), queued=$(& $GetJsonProperty $Summary "queued_count"), running=$(& $GetJsonProperty $Summary "running_count"), succeeded=$(& $GetJsonProperty $Summary "succeeded_count"), failed=$(& $GetJsonProperty $Summary "failed_count"), errors=$(& $GetJsonProperty $Summary "error_count"), skipped=$(& $GetJsonProperty $Summary "skipped_count"), cancelled=$(& $GetJsonProperty $Summary "cancelled_count")",
            "prepare_only=$(& $GetJsonProperty $Summary "prepare_only"), stop_on_failure=$(& $GetJsonProperty $Summary "stop_on_failure"), stopped_on_failure=$(& $GetJsonProperty $Summary "stopped_on_failure")",
            "job_dir=$(& $GetJsonProperty $Summary "job_dir")",
            "summary=$(& $GetJsonProperty $Summary "summary_path")"
        )
        if ($items.Count -gt 0) {
            $lines += ""
            $lines += "Items"
            $maxRows = 20
            foreach ($item in @($items | Select-Object -First $maxRows)) {
                $itemIndex = & $GetJsonProperty $item "index"
                $itemStatus = & $GetJsonProperty $item "status"
                $itemInputPath = & $GetJsonProperty $item "input_path"
                $line = "#{0}: status={1} input={2}" -f $itemIndex, $itemStatus, $itemInputPath
                $outputPath = & $GetJsonProperty $item "output_path"
                if (-not [string]::IsNullOrWhiteSpace($outputPath)) {
                    $line += " output=$outputPath"
                }
                $errorText = & $GetJsonProperty $item "error"
                if (-not [string]::IsNullOrWhiteSpace($errorText)) {
                    $line += " error=$errorText"
                }
                $lines += $line
            }
            if ($items.Count -gt $maxRows) {
                $lines += "... $($items.Count - $maxRows) more item(s)"
            }
        }
        return ($lines -join "`r`n")
    }.GetNewClosure()

    $BuildBatchArtifactSummary = {
        param([Parameter(Mandatory = $true)]$Summary)
        $summaryPath = & $GetJsonProperty $Summary "summary_path"
        $exists = if (-not [string]::IsNullOrWhiteSpace($summaryPath) -and [System.IO.File]::Exists($summaryPath)) { "exists" } else { "missing" }
        return (@(
            "mode=existing_input_batch",
            "status=$(& $GetJsonProperty $Summary "status")",
            "progress=$(& $GetBatchProgressText $Summary)",
            "inputs=$(& $GetJsonProperty $Summary "input_count"), items=$(& $GetJsonProperty $Summary "item_count"), prepared=$(& $GetJsonProperty $Summary "prepared_count"), queued=$(& $GetJsonProperty $Summary "queued_count"), running=$(& $GetJsonProperty $Summary "running_count"), succeeded=$(& $GetJsonProperty $Summary "succeeded_count"), failed=$(& $GetJsonProperty $Summary "failed_count"), errors=$(& $GetJsonProperty $Summary "error_count"), skipped=$(& $GetJsonProperty $Summary "skipped_count"), cancelled=$(& $GetJsonProperty $Summary "cancelled_count")",
            "job_dir=$(& $GetJsonProperty $Summary "job_dir")",
            "summary=[$exists] $summaryPath"
        ) -join "`r`n")
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

    $GetPreviewNumber = {
        param($Value, [double]$Default = 0.0)
        if ($null -eq $Value) {
            return $Default
        }
        try {
            return [System.Convert]::ToDouble($Value, [System.Globalization.CultureInfo]::InvariantCulture)
        }
        catch {
            return $Default
        }
    }.GetNewClosure()

    $GetPreviewVector = {
        param($Value, [double[]]$Default = @(0.0, 0.0, 0.0))
        if ($null -eq $Value) {
            return [double[]]$Default
        }
        $items = @($Value)
        if ($items.Count -ne 3) {
            return [double[]]$Default
        }
        return [double[]]@(
            (& $GetPreviewNumber $items[0] $Default[0]),
            (& $GetPreviewNumber $items[1] $Default[1]),
            (& $GetPreviewNumber $items[2] $Default[2])
        )
    }.GetNewClosure()

    $NewPreviewPoint = {
        param($Value, [double[]]$Center)
        $vector = & $GetPreviewVector $Value
        return [System.Windows.Media.Media3D.Point3D]::new(
            $vector[0] - $Center[0],
            $vector[1] - $Center[1],
            $vector[2] - $Center[2]
        )
    }.GetNewClosure()

    $NewPreviewColor = {
        param([string]$Hex, [string]$Fallback = "#B0B0B0")
        $candidate = if ([string]::IsNullOrWhiteSpace($Hex)) { $Fallback } else { $Hex }
        try {
            return [System.Windows.Media.ColorConverter]::ConvertFromString($candidate)
        }
        catch {
            return [System.Windows.Media.ColorConverter]::ConvertFromString($Fallback)
        }
    }.GetNewClosure()

    $NewPreviewMaterial = {
        param([string]$Hex)
        $brush = [System.Windows.Media.SolidColorBrush]::new((& $NewPreviewColor $Hex))
        if ($brush.CanFreeze) {
            $brush.Freeze()
        }
        $material = [System.Windows.Media.Media3D.DiffuseMaterial]::new($brush)
        if ($material.CanFreeze) {
            $material.Freeze()
        }
        return $material
    }.GetNewClosure()

    $NewSphereMesh = {
        param(
            [Parameter(Mandatory = $true)][System.Windows.Media.Media3D.Point3D]$Center,
            [double]$Radius,
            [int]$LatitudeSegments = 6,
            [int]$LongitudeSegments = 12
        )
        $mesh = [System.Windows.Media.Media3D.MeshGeometry3D]::new()
        for ($lat = 0; $lat -le $LatitudeSegments; $lat += 1) {
            $theta = [Math]::PI * $lat / $LatitudeSegments
            $sinTheta = [Math]::Sin($theta)
            $cosTheta = [Math]::Cos($theta)
            for ($lon = 0; $lon -le $LongitudeSegments; $lon += 1) {
                $phi = 2.0 * [Math]::PI * $lon / $LongitudeSegments
                $x = $Center.X + $Radius * $sinTheta * [Math]::Cos($phi)
                $y = $Center.Y + $Radius * $cosTheta
                $z = $Center.Z + $Radius * $sinTheta * [Math]::Sin($phi)
                $mesh.Positions.Add([System.Windows.Media.Media3D.Point3D]::new($x, $y, $z))
            }
        }
        $rowSize = $LongitudeSegments + 1
        for ($lat = 0; $lat -lt $LatitudeSegments; $lat += 1) {
            for ($lon = 0; $lon -lt $LongitudeSegments; $lon += 1) {
                $first = $lat * $rowSize + $lon
                $second = $first + $rowSize
                $mesh.TriangleIndices.Add($first)
                $mesh.TriangleIndices.Add($second)
                $mesh.TriangleIndices.Add($first + 1)
                $mesh.TriangleIndices.Add($first + 1)
                $mesh.TriangleIndices.Add($second)
                $mesh.TriangleIndices.Add($second + 1)
            }
        }
        if ($mesh.CanFreeze) {
            $mesh.Freeze()
        }
        return $mesh
    }.GetNewClosure()

    $NewCylinderMesh = {
        param(
            [Parameter(Mandatory = $true)][System.Windows.Media.Media3D.Point3D]$Start,
            [Parameter(Mandatory = $true)][System.Windows.Media.Media3D.Point3D]$End,
            [double]$Radius,
            [int]$Segments = 8
        )
        $axis = [System.Windows.Media.Media3D.Vector3D]::new($End.X - $Start.X, $End.Y - $Start.Y, $End.Z - $Start.Z)
        if ($axis.Length -le 1.0e-8) {
            return $null
        }
        $axis.Normalize()
        $reference = [System.Windows.Media.Media3D.Vector3D]::new(0.0, 0.0, 1.0)
        if ([Math]::Abs([System.Windows.Media.Media3D.Vector3D]::DotProduct($axis, $reference)) -gt 0.9) {
            $reference = [System.Windows.Media.Media3D.Vector3D]::new(0.0, 1.0, 0.0)
        }
        $normal1 = [System.Windows.Media.Media3D.Vector3D]::CrossProduct($axis, $reference)
        $normal1.Normalize()
        $normal2 = [System.Windows.Media.Media3D.Vector3D]::CrossProduct($axis, $normal1)
        $normal2.Normalize()

        $mesh = [System.Windows.Media.Media3D.MeshGeometry3D]::new()
        for ($index = 0; $index -lt $Segments; $index += 1) {
            $angle = 2.0 * [Math]::PI * $index / $Segments
            $offset = ($normal1 * ([Math]::Cos($angle) * $Radius)) + ($normal2 * ([Math]::Sin($angle) * $Radius))
            $mesh.Positions.Add($Start + $offset)
            $mesh.Positions.Add($End + $offset)
        }
        for ($index = 0; $index -lt $Segments; $index += 1) {
            $next = ($index + 1) % $Segments
            $a = $index * 2
            $b = $a + 1
            $c = $next * 2
            $d = $c + 1
            $mesh.TriangleIndices.Add($a)
            $mesh.TriangleIndices.Add($b)
            $mesh.TriangleIndices.Add($c)
            $mesh.TriangleIndices.Add($c)
            $mesh.TriangleIndices.Add($b)
            $mesh.TriangleIndices.Add($d)
        }
        if ($mesh.CanFreeze) {
            $mesh.Freeze()
        }
        return $mesh
    }.GetNewClosure()

    $GetStructurePreviewDimension = {
        param($Value, [double]$Fallback)
        try {
            $number = [double]$Value
            if (-not [double]::IsNaN($number) -and -not [double]::IsInfinity($number) -and $number -gt 1.0) {
                return $number
            }
        }
        catch {
        }
        return $Fallback
    }.GetNewClosure()

    $GetStructurePreviewViewportSize = {
        $windowWidth = & $GetStructurePreviewDimension $window.Width 900.0
        $widthFallback = [Math]::Max(($windowWidth * 0.52) - 44.0, 320.0)
        $heightFallback = [Math]::Max(($windowWidth * 0.42), 360.0)
        $viewport = $controls["StructurePreviewViewport"]
        if ($null -eq $viewport) {
            return [ordered]@{
                Width = $widthFallback
                Height = $heightFallback
            }
        }

        $width = & $GetStructurePreviewDimension $viewport.ActualWidth (& $GetStructurePreviewDimension $viewport.RenderSize.Width $widthFallback)
        $height = & $GetStructurePreviewDimension $viewport.ActualHeight (& $GetStructurePreviewDimension $viewport.RenderSize.Height $heightFallback)
        return [ordered]@{
            Width = $width
            Height = $height
        }
    }.GetNewClosure()

    $GetStructurePreviewFitDistance = {
        param([double]$Radius)
        $safeRadius = [Math]::Max($Radius, 1.0)
        $camera = $controls["StructurePreviewCamera"]
        $fieldOfView = if ($null -ne $camera) { [double]$camera.FieldOfView } else { 45.0 }
        $fieldOfView = [Math]::Min([Math]::Max($fieldOfView, 1.0), 120.0)
        $halfHorizontalFovRadians = ([Math]::PI / 180.0) * ($fieldOfView / 2.0)
        $viewportSize = & $GetStructurePreviewViewportSize
        $aspect = [Math]::Max([double]($viewportSize["Width"]) / [double]($viewportSize["Height"]), 0.1)
        # WPF FieldOfView is horizontal, so wide panes need the derived vertical angle.
        $halfVerticalFovRadians = [Math]::Atan([Math]::Tan($halfHorizontalFovRadians) / $aspect)
        $limitingHalfFovRadians = [Math]::Max([Math]::Min($halfHorizontalFovRadians, $halfVerticalFovRadians), 0.01)
        $distance = $safeRadius / [Math]::Sin($limitingHalfFovRadians)
        return [Math]::Max($distance * 1.18, 5.0)
    }.GetNewClosure()

    $UpdateStructurePreviewView = {
        $camera = $controls["StructurePreviewCamera"]
        $distance = [Math]::Max([double]$structurePreviewState["Distance"], 0.1)
        $radius = [Math]::Max([double]$structurePreviewState["Radius"], 1.0)
        $panX = [double]$structurePreviewState["PanX"]
        $panY = [double]$structurePreviewState["PanY"]

        $camera.Position = [System.Windows.Media.Media3D.Point3D]::new($panX, $panY, $distance)
        $camera.LookDirection = [System.Windows.Media.Media3D.Vector3D]::new(0.0, 0.0, -$distance)
        $camera.UpDirection = [System.Windows.Media.Media3D.Vector3D]::new(0.0, 1.0, 0.0)
        $camera.NearPlaneDistance = 0.01
        $camera.FarPlaneDistance = [Math]::Max(100.0, $distance + ($radius * 6.0))

        $content = $controls["StructurePreviewVisual"].Content
        if ($null -ne $content) {
            $transform = [System.Windows.Media.Media3D.Transform3DGroup]::new()
            $pitchRotation = [System.Windows.Media.Media3D.AxisAngleRotation3D]::new(
                [System.Windows.Media.Media3D.Vector3D]::new(1.0, 0.0, 0.0),
                [double]$structurePreviewState["Pitch"]
            )
            $yawRotation = [System.Windows.Media.Media3D.AxisAngleRotation3D]::new(
                [System.Windows.Media.Media3D.Vector3D]::new(0.0, 1.0, 0.0),
                [double]$structurePreviewState["Yaw"]
            )
            $transform.Children.Add([System.Windows.Media.Media3D.RotateTransform3D]::new($pitchRotation))
            $transform.Children.Add([System.Windows.Media.Media3D.RotateTransform3D]::new($yawRotation))
            $content.Transform = $transform
        }
    }.GetNewClosure()

    $ResetStructurePreviewCamera = {
        param($Preview)
        $radius = & $GetPreviewNumber (& $GetNestedValue $Preview @("bounding_radius")) 5.0
        $distance = & $GetStructurePreviewFitDistance $radius
        $structurePreviewState["Radius"] = $radius
        $structurePreviewState["DefaultDistance"] = $distance
        $structurePreviewState["Distance"] = $distance
        $structurePreviewState["Yaw"] = 0.0
        $structurePreviewState["Pitch"] = 0.0
        $structurePreviewState["PanX"] = 0.0
        $structurePreviewState["PanY"] = 0.0
        & $UpdateStructurePreviewView
    }.GetNewClosure()

    $ApplyStructurePreviewInteraction = {
        param(
            [Parameter(Mandatory = $true)][string]$Mode,
            [double]$DeltaX = 0.0,
            [double]$DeltaY = 0.0,
            [int]$WheelDelta = 0
        )
        if ($null -eq $structurePreviewState["Current"]) {
            return
        }

        switch ($Mode.ToLowerInvariant()) {
            "rotate" {
                $structurePreviewState["Yaw"] = [double]$structurePreviewState["Yaw"] + ($DeltaX * 0.45)
                $structurePreviewState["Pitch"] = [double]$structurePreviewState["Pitch"] + ($DeltaY * 0.45)
            }
            "pan" {
                $scale = [Math]::Max(([double]$structurePreviewState["Distance"]) * 0.002, 0.005)
                $structurePreviewState["PanX"] = [double]$structurePreviewState["PanX"] - ($DeltaX * $scale)
                $structurePreviewState["PanY"] = [double]$structurePreviewState["PanY"] + ($DeltaY * $scale)
            }
            "zoom" {
                $factor = if ($WheelDelta -gt 0) { 0.9 } else { 1.1 }
                $radius = [Math]::Max([double]$structurePreviewState["Radius"], 1.0)
                $minDistance = [Math]::Max($radius * 0.35, 0.5)
                $maxDistance = [Math]::Max($radius * 25.0, 25.0)
                $nextDistance = [double]$structurePreviewState["Distance"] * $factor
                $structurePreviewState["Distance"] = [Math]::Min([Math]::Max($nextDistance, $minDistance), $maxDistance)
            }
        }
        & $UpdateStructurePreviewView
    }.GetNewClosure()

    $GetSortedStructureSelectedAtomIndices = {
        $selected = $structurePreviewState["SelectedAtomIndices"]
        if ($selected -isnot [hashtable]) {
            $selected = @{}
            $structurePreviewState["SelectedAtomIndices"] = $selected
        }
        if ($null -eq $selected) {
            return @()
        }
        $indices = @()
        foreach ($key in @($selected.Keys)) {
            try {
                $indices += [int]$key
            }
            catch {
            }
        }
        return @($indices | Sort-Object)
    }.GetNewClosure()

    $UpdateStructureSelectionControls = {
        $indices = @(& $GetSortedStructureSelectedAtomIndices)
        if ($indices.Count -gt 0) {
            $joined = ($indices -join " ")
            $controls["StructureSelectionText"].Text = Format-WinQStepText "structure.fixed_atoms.selected" @($joined)
        }
        else {
            $controls["StructureSelectionText"].Text = Get-WinQStepText "structure.fixed_atoms.none"
        }
        $hasSelection = ($indices.Count -gt 0)
        $controls["StructureApplyFixedAtomsButton"].IsEnabled = $hasSelection
        $controls["StructureClearSelectionButton"].IsEnabled = $hasSelection
    }.GetNewClosure()

    $SetStructureAtomSelectionState = {
        param([int]$Index, [bool]$IsSelected)
        if ($Index -le 0) {
            return
        }
        $indexKey = [string]$Index
        $atomModelsByIndex = $structurePreviewState["AtomModelsByIndex"]
        if ($atomModelsByIndex -isnot [hashtable]) {
            return
        }
        if ($null -eq $atomModelsByIndex -or -not $atomModelsByIndex.ContainsKey($indexKey)) {
            return
        }
        $selectedMap = $structurePreviewState["SelectedAtomIndices"]
        if ($selectedMap -isnot [hashtable]) {
            $selectedMap = @{}
            $structurePreviewState["SelectedAtomIndices"] = $selectedMap
        }
        if ($IsSelected) {
            $selectedMap[$indexKey] = $true
        }
        else {
            $selectedMap.Remove($indexKey) | Out-Null
        }

        $info = $atomModelsByIndex[$indexKey]
        $model = $info["model"]
        if ($model -is [System.Windows.Media.Media3D.GeometryModel3D]) {
            $material = if ($selectedMap.ContainsKey($indexKey)) { $info["selected_material"] } else { $info["material"] }
            $model.Material = $material
            $model.BackMaterial = $material
        }
        & $UpdateStructureSelectionControls
    }.GetNewClosure()

    $ToggleStructureAtomSelectionByIndex = {
        param([int]$Index)
        if ($Index -le 0) {
            return
        }
        $selectedMap = $structurePreviewState["SelectedAtomIndices"]
        if ($selectedMap -isnot [hashtable]) {
            $selectedMap = @{}
            $structurePreviewState["SelectedAtomIndices"] = $selectedMap
        }
        $indexKey = [string]$Index
        & $SetStructureAtomSelectionState $Index (-not $selectedMap.ContainsKey($indexKey))
    }.GetNewClosure()

    $ToggleStructureAtomSelectionByModelKey = {
        param([string]$ModelKey)
        if ([string]::IsNullOrWhiteSpace($ModelKey)) {
            return
        }
        $atomModels = $structurePreviewState["AtomModels"]
        if ($null -eq $atomModels -or -not $atomModels.ContainsKey($ModelKey)) {
            return
        }
        $index = [int]$atomModels[$ModelKey]["index"]
        & $ToggleStructureAtomSelectionByIndex $index
    }.GetNewClosure()

    $HitTestStructurePreviewAtom = {
        param([Parameter(Mandatory = $true)][System.Windows.Point]$Point)
        $hit = [System.Windows.Media.VisualTreeHelper]::HitTest($controls["StructurePreviewViewport"], $Point)
        if ($hit -isnot [System.Windows.Media.Media3D.RayHitTestResult]) {
            return ""
        }
        $model = $hit.ModelHit
        if ($null -eq $model) {
            return ""
        }
        $key = [string]$model.GetHashCode()
        $atomModels = $structurePreviewState["AtomModels"]
        if ($null -ne $atomModels -and $atomModels.ContainsKey($key)) {
            return $key
        }
        return ""
    }.GetNewClosure()

    $ApplyStructureSelectionToFixedAtoms = {
        $indices = @(& $GetSortedStructureSelectedAtomIndices)
        if ($indices.Count -eq 0) {
            return ""
        }
        $text = ($indices -join " ")
        $controls["FixedAtomsBox"].Text = $text
        $controls["StatusText"].Text = Format-WinQStepText "structure.fixed_atoms.applied" @($text)
        return $text
    }.GetNewClosure()

    $ClearStructureAtomSelection = {
        foreach ($index in @(& $GetSortedStructureSelectedAtomIndices)) {
            & $SetStructureAtomSelectionState ([int]$index) $false
        }
        & $UpdateStructureSelectionControls
    }.GetNewClosure()

    $Script:StructurePreviewSmokeApplyInteraction = $ApplyStructurePreviewInteraction
    $Script:StructurePreviewSmokeToggleAtomSelection = $ToggleStructureAtomSelectionByIndex
    $Script:StructurePreviewSmokeApplyFixedAtoms = $ApplyStructureSelectionToFixedAtoms
    $Script:StructurePreviewSmokeGetState = {
        $viewportSize = & $GetStructurePreviewViewportSize
        $radius = [double]$structurePreviewState["Radius"]
        return [ordered]@{
            radius = $radius
            default_distance = [double]$structurePreviewState["DefaultDistance"]
            distance = [double]$structurePreviewState["Distance"]
            fit_distance = (& $GetStructurePreviewFitDistance $radius)
            viewport_width = [double]($viewportSize["Width"])
            viewport_height = [double]($viewportSize["Height"])
            field_of_view = [double]$controls["StructurePreviewCamera"].FieldOfView
            selected_atom_count = @(& $GetSortedStructureSelectedAtomIndices).Count
        }
    }.GetNewClosure()

    $ClearStructurePreview = {
        $structurePreviewState["Current"] = $null
        $structurePreviewState["AtomModels"] = @{}
        $structurePreviewState["AtomModelsByIndex"] = @{}
        $structurePreviewState["SelectedAtomIndices"] = @{}
        $structurePreviewState["PendingSelectionKey"] = ""
        $structurePreviewState["DragStartPoint"] = $null
        $structurePreviewState["DragMoved"] = $false
        $controls["StructurePreviewVisual"].Content = [System.Windows.Media.Media3D.Model3DGroup]::new()
        $controls["StructurePreviewStatusText"].Text = Get-WinQStepText "structure.preview.empty"
        $controls["StructureResetViewButton"].IsEnabled = $false
        & $UpdateStructureSelectionControls
        & $ResetStructurePreviewCamera ([ordered]@{ bounding_radius = 5.0 })
    }.GetNewClosure()

    $SetStructurePreview = {
        param($Preview)
        if ($null -eq $Preview) {
            & $ClearStructurePreview
            return
        }

        $center = & $GetPreviewVector (& $GetNestedValue $Preview @("center"))
        $radius = & $GetPreviewNumber (& $GetNestedValue $Preview @("bounding_radius")) 5.0
        $atomGeometryRadiusScale = 0.35
        $group = [System.Windows.Media.Media3D.Model3DGroup]::new()
        $structurePreviewState["AtomModels"] = @{}
        $structurePreviewState["AtomModelsByIndex"] = @{}
        $structurePreviewState["SelectedAtomIndices"] = @{}
        $structurePreviewState["PendingSelectionKey"] = ""
        $structurePreviewState["DragStartPoint"] = $null
        $structurePreviewState["DragMoved"] = $false

        $previewAtomsValue = & $GetNestedValue $Preview @("atoms")
        $previewAtoms = if ($null -ne $previewAtomsValue) { @($previewAtomsValue) } else { @() }
        foreach ($atom in $previewAtoms) {
            if ($null -eq $atom) {
                continue
            }
            $atomIndex = [int](& $GetPreviewNumber (& $GetNestedValue $atom @("index")) 0.0)
            if ($atomIndex -le 0) {
                continue
            }
            $point = & $NewPreviewPoint (& $GetNestedValue $atom @("xyz")) $center
            $displayRadius = [Math]::Max((& $GetPreviewNumber (& $GetNestedValue $atom @("radius")) 0.7) * $atomGeometryRadiusScale, 0.12)
            $mesh = & $NewSphereMesh $point $displayRadius
            $material = & $NewPreviewMaterial (& $GetNestedPath $atom @("color"))
            $selectedMaterial = & $NewPreviewMaterial "#FACC15"
            $model = [System.Windows.Media.Media3D.GeometryModel3D]::new($mesh, $material)
            $model.BackMaterial = $material
            $group.Children.Add($model)
            $modelKey = [string]$model.GetHashCode()
            $info = @{
                index = $atomIndex
                model = $model
                material = $material
                selected_material = $selectedMaterial
            }
            $structurePreviewState["AtomModels"][$modelKey] = $info
            $structurePreviewState["AtomModelsByIndex"][[string]$atomIndex] = $info
        }

        $edgeRadius = [Math]::Max([Math]::Min($radius * 0.004, 0.04), 0.015)
        $previewEdgesValue = & $GetNestedValue $Preview @("cell", "edges")
        $previewEdges = if ($null -ne $previewEdgesValue) { @($previewEdgesValue) } else { @() }
        foreach ($edge in $previewEdges) {
            if ($null -eq $edge) {
                continue
            }
            $start = & $NewPreviewPoint (& $GetNestedValue $edge @("start")) $center
            $end = & $NewPreviewPoint (& $GetNestedValue $edge @("end")) $center
            $mesh = & $NewCylinderMesh $start $end $edgeRadius
            if ($null -eq $mesh) {
                continue
            }
            $material = & $NewPreviewMaterial "#D6E4F0"
            $model = [System.Windows.Media.Media3D.GeometryModel3D]::new($mesh, $material)
            $model.BackMaterial = $material
            $group.Children.Add($model)
        }

        $structurePreviewState["Current"] = $Preview
        $controls["StructurePreviewVisual"].Content = $group
        & $ResetStructurePreviewCamera $Preview
        $displayedAtoms = & $GetPreviewNumber (& $GetNestedValue $Preview @("displayed_atom_count")) 0.0
        $totalAtoms = & $GetPreviewNumber (& $GetNestedValue $Preview @("atom_count")) 0.0
        $edgeCount = $previewEdges.Count
        $controls["StructurePreviewStatusText"].Text = Format-WinQStepText "structure.preview.loaded" @([int]$displayedAtoms, [int]$totalAtoms, $edgeCount)
        $controls["StructureResetViewButton"].IsEnabled = ($group.Children.Count -gt 0)
        & $UpdateStructureSelectionControls
    }.GetNewClosure()

    & $ClearStructurePreview

    $FormatEnvironmentDisplayValue = {
        param($Value, [string]$Default = "not_configured")
        if ($null -eq $Value) {
            return $Default
        }
        if ($Value -is [bool]) {
            return ([string]$Value).ToLowerInvariant()
        }
        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) {
            return $Default
        }
        return $text
    }.GetNewClosure()

    $FormatEnvironmentList = {
        param($Value, [int]$Limit = 12)
        if ($null -eq $Value) {
            return @()
        }
        $items = @($Value)
        if ($items.Count -eq 0) {
            return @()
        }
        $lines = @()
        foreach ($item in @($items | Select-Object -First $Limit)) {
            $text = [string]$item
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $lines += "- $text"
            }
        }
        if ($items.Count -gt $Limit) {
            $lines += "- ... ($($items.Count - $Limit) more)"
        }
        return $lines
    }.GetNewClosure()

    $FormatEnvironmentProbeDisplay = {
        param([Parameter(Mandatory = $true)]$Payload)

        $hostInfo = & $GetNestedValue $Payload @("host")
        $wsl = & $GetNestedValue $Payload @("wsl")
        $cp2k = & $GetNestedValue $Payload @("cp2k")
        $mpi = & $GetNestedValue $Payload @("mpi")
        $workspace = & $GetNestedValue $Payload @("workspace")
        $commands = & $GetNestedValue $Payload @("commands")
        $warnings = @()
        $warningValue = & $GetNestedValue $Payload @("warnings")
        if ($null -ne $warningValue) {
            $warnings = @($warningValue)
        }

        $generatedAt = & $FormatEnvironmentDisplayValue (& $GetNestedValue $Payload @("generated_at")) "not_available"
        $configPath = & $FormatEnvironmentDisplayValue (& $GetNestedValue $Payload @("config", "path")) "not_available"
        $hostSystem = & $FormatEnvironmentDisplayValue (& $GetNestedValue $hostInfo @("system")) "unknown"
        $hostRelease = & $FormatEnvironmentDisplayValue (& $GetNestedValue $hostInfo @("release")) ""
        $hostMachine = & $FormatEnvironmentDisplayValue (& $GetNestedValue $hostInfo @("machine")) "unknown"
        $wslAvailable = & $FormatEnvironmentDisplayValue (& $GetNestedValue $wsl @("available")) "false"
        $wslExecutable = & $FormatEnvironmentDisplayValue (& $GetNestedValue $wsl @("executable"))
        $selectedDistro = & $FormatEnvironmentDisplayValue (& $GetNestedValue $wsl @("selected_distro"))
        $shellPrelude = & $FormatEnvironmentDisplayValue (& $GetNestedValue $wsl @("shell_prelude"))

        $lines = @(
            "Environment detection",
            "Generated: $generatedAt",
            "Config: $configPath",
            "",
            "Host",
            "System: $hostSystem $hostRelease",
            "Machine: $hostMachine",
            "",
            "WSL",
            "Available: $wslAvailable",
            "Executable: $wslExecutable",
            "Selected distro: $selectedDistro",
            "Shell prelude: $shellPrelude",
            "Distros:"
        )

        $distrosValue = & $GetNestedValue $wsl @("distros")
        $distros = if ($null -ne $distrosValue) { @($distrosValue) } else { @() }
        if ($distros.Count -gt 0) {
            foreach ($distro in $distros) {
                $marker = if ([bool](& $GetNestedValue $distro @("default"))) { "*" } else { "-" }
                $lines += ("  {0} {1} state={2} version={3}" -f
                    $marker,
                    (& $FormatEnvironmentDisplayValue (& $GetNestedValue $distro @("name")) "unknown"),
                    (& $FormatEnvironmentDisplayValue (& $GetNestedValue $distro @("state")) "unknown"),
                    (& $FormatEnvironmentDisplayValue (& $GetNestedValue $distro @("version")) "unknown")
                )
            }
        }
        else {
            $lines += "  none"
        }

        $dataFilesValue = & $GetNestedValue $cp2k @("data_files")
        $dataFiles = if ($null -ne $dataFilesValue) { @($dataFilesValue) } else { @() }
        $versionOutput = (& $FormatEnvironmentDisplayValue (& $GetNestedValue $cp2k @("version_output")) "not_available")
        if ($versionOutput.Length -gt 240) {
            $versionOutput = $versionOutput.Substring(0, 240) + "..."
        }
        $cp2kCommand = & $FormatEnvironmentDisplayValue (& $GetNestedValue $cp2k @("command"))
        $cp2kDataDir = & $FormatEnvironmentDisplayValue (& $GetNestedValue $cp2k @("data_dir"))
        $lines += @(
            "",
            "CP2K",
            "Command: $cp2kCommand",
            "Version: $versionOutput",
            "Data dir: $cp2kDataDir",
            "Data files: $($dataFiles.Count)"
        )
        $lines += & $FormatEnvironmentList $dataFiles 12

        $mpiCommand = & $FormatEnvironmentDisplayValue (& $GetNestedValue $mpi @("command"))
        $defaultWorkspace = & $FormatEnvironmentDisplayValue (& $GetNestedValue $workspace @("default_windows_workspace"))
        $lines += @(
            "",
            "MPI",
            "Command: $mpiCommand",
            "",
            "Workspace",
            "Default Windows workspace: $defaultWorkspace"
        )

        if ($warnings.Count -gt 0) {
            $lines += ""
            $lines += "Warnings"
            foreach ($warningText in $warnings) {
                $lines += "WARNING: $warningText"
            }
        }

        if ($null -ne $commands) {
            $commandProperties = @($commands.PSObject.Properties | Sort-Object Name)
            if ($commandProperties.Count -gt 0) {
                $lines += ""
                $lines += "Probe commands"
                foreach ($property in $commandProperties) {
                    $commandResult = $property.Value
                    $okText = & $FormatEnvironmentDisplayValue (& $GetNestedValue $commandResult @("ok")) "false"
                    $returnCode = & $FormatEnvironmentDisplayValue (& $GetNestedValue $commandResult @("returncode")) "not_available"
                    $errorText = & $FormatEnvironmentDisplayValue (& $GetNestedValue $commandResult @("error")) ""
                    $line = "$($property.Name): ok=$okText returncode=$returnCode"
                    if (-not [string]::IsNullOrWhiteSpace($errorText)) {
                        $line += " error=$errorText"
                    }
                    $lines += $line
                }
            }
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
        $generatedArtifacts = @($Artifacts["generated_artifacts"])
        if ($generatedArtifacts.Count -gt 0) {
            $lines += "generated_artifacts=$($generatedArtifacts.Count)"
            foreach ($artifact in $generatedArtifacts) {
                $artifactPath = [string]$artifact["path"]
                $artifactType = [string]$artifact["type"]
                $exists = if (-not [string]::IsNullOrWhiteSpace($artifactPath) -and [System.IO.File]::Exists($artifactPath)) { "exists" } else { "missing" }
                $lines += "generated.$artifactType=[$exists] $artifactPath"
            }
        }
        return ($lines -join "`r`n")
    }.GetNewClosure()

    $GetGeneratedArtifacts = {
        param($Value)
        if ($null -eq $Value) {
            return @()
        }
        $artifacts = @()
        foreach ($item in @($Value)) {
            if ($null -eq $item) {
                continue
            }
            $path = & $GetJsonProperty $item "path"
            if ([string]::IsNullOrWhiteSpace($path)) {
                continue
            }
            $artifacts += @{
                path = $path
                name = (& $GetJsonProperty $item "name" ([System.IO.Path]::GetFileName($path)))
                type = (& $GetJsonProperty $item "type" "generated")
                size = (& $GetJsonProperty $item "size" "")
            }
        }
        return $artifacts
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
        $generatedArtifacts = @(& $GetGeneratedArtifacts (& $GetNestedValue $Metadata @("files", "generated")))
        if ($generatedArtifacts.Count -gt 0) {
            $lines += "generated_artifacts=$($generatedArtifacts.Count)"
            foreach ($artifact in $generatedArtifacts) {
                $lines += "generated.$($artifact["type"])=$($artifact["path"])"
            }
        }

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
        $generatedArtifacts = @($Artifacts["generated_artifacts"])
        if ($generatedArtifacts.Count -gt 0) {
            $lines += "generated_artifacts=$($generatedArtifacts.Count)"
            foreach ($artifact in $generatedArtifacts) {
                $lines += "generated.$($artifact["type"])=$($artifact["path"])"
            }
        }
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
            generated_artifacts = @(& $GetGeneratedArtifacts (& $GetNestedValue $Metadata @("files", "generated")))
            result_text = (& $BuildResultSummaryFromMetadata $Metadata)
        }
        if ([string]::IsNullOrWhiteSpace([string]$artifacts["project_name"])) {
            $artifacts["project_name"] = (& $GetNestedPath $Metadata @("workflow", "template", "project_name"))
        }
        if ([string]::IsNullOrWhiteSpace([string]$artifacts["run_type"])) {
            $artifacts["run_type"] = (& $GetNestedPath $Metadata @("workflow", "template", "run_type"))
        }
        $artifactState["Current"] = $artifacts
        $controls["BatchResultsGrid"].ItemsSource = $null
        $controls["BatchResultsGrid"].Visibility = [System.Windows.Visibility]::Collapsed
        $controls["ArtifactSummaryText"].Text = & $BuildArtifactSummary $artifacts
        & $UpdateArtifactControls
        & $SetJobStatusText (& $FormatFinishedJobStatus $Metadata ([string]$artifacts["status"]))
    }.GetNewClosure()

    $SetArtifactsFromBatchSummary = {
        param([Parameter(Mandatory = $true)]$Summary)
        $summaryPath = & $GetJsonProperty $Summary "summary_path"
        $summaryText = & $FormatBatchSummary $Summary
        $rows = @(& $NewBatchResultRows $Summary)
        $artifacts = @{
            status = (& $GetJsonProperty $Summary "status" "")
            returncode = ""
            mode = "existing_input_batch"
            project_name = ""
            run_type = ""
            output_status = ""
            warning_count = ""
            program_ended = ""
            ended_at = (& $GetJsonProperty $Summary "completed_at" "")
            total_energy_hartree = ""
            total_atomic_force = ""
            force_unit = ""
            paths = @{
                input = ""
                output = ""
                metadata = $summaryPath
                stdout = ""
                stderr = ""
            }
            generated_artifacts = @()
            result_text = "$summaryText`r`n`r`n$(& $FormatBatchResultTable $Summary)"
            batch_summary = $Summary
        }
        $artifactState["Current"] = $artifacts
        $controls["ArtifactSummaryText"].Text = & $BuildBatchArtifactSummary $Summary
        $controls["BatchResultsGrid"].ItemsSource = $rows
        $controls["BatchResultsGrid"].Visibility = if ($rows.Count -gt 0) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        & $UpdateArtifactControls
        & $SetJobStatusText "Batch: status=$($artifacts["status"]) | $(& $GetBatchProgressText $Summary) | summary=$summaryPath"
    }.GetNewClosure()

    $InvokeBatchQueueAction = {
        param([Parameter(Mandatory = $true)][string]$Action)
        $summaryPath = & $GetCurrentBatchSummaryPath
        if ([string]::IsNullOrWhiteSpace($summaryPath) -or -not [System.IO.File]::Exists($summaryPath)) {
            throw "No batch summary is available."
        }
        $index = & $GetSelectedBatchItemIndex
        if ($index -le 0) {
            throw "No batch item is selected."
        }
        $result = Invoke-WinQStepPython @(
            "scripts\manage_existing_input_batch.py",
            "--summary", $summaryPath,
            "--index", [string]$index,
            "--action", $Action,
            "--compact"
        )
        $summary = & $GetBatchSummaryResult $result
        $summaryText = & $FormatBatchSummary $summary
        & $SetArtifactsFromBatchSummary $summary
        & $ClearInputPreviewState
        $controls["PreviewText"].Text = $summaryText
        $controls["LogText"].Text = "Batch item $index action=$Action`r`n`r`n$summaryText"
        & $UpdateBatchQueueControls
        return $summary
    }.GetNewClosure()

    $StartExistingInputBatchResumeJob = {
        if ($null -ne $jobState["Current"]) {
            & $AppendLog "A CP2K job is already running."
            return
        }

        $summaryPath = & $GetCurrentBatchSummaryPath
        if ([string]::IsNullOrWhiteSpace($summaryPath) -or -not [System.IO.File]::Exists($summaryPath)) {
            throw "No batch summary is available."
        }
        $summary = & $ReadMetadataFile $summaryPath
        if ($null -eq $summary) {
            throw "Batch summary could not be read: $summaryPath"
        }
        $batchDir = & $GetJsonProperty $summary "job_dir"
        if ([string]::IsNullOrWhiteSpace($batchDir)) {
            $batchDir = Split-Path -Parent $summaryPath
        }
        if ([string]::IsNullOrWhiteSpace($batchDir)) {
            throw "Batch job folder could not be resolved."
        }

        & $SetBusy $true (Get-WinQStepText "status.resuming_batch")
        try {
            $null = & $SaveConfigFields $true $false
            $stamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")
            $wrapperStdoutPath = Join-Path $batchDir "winqstep-gui-batch-resume-$stamp.stdout.json"
            $wrapperStderrPath = Join-Path $batchDir "winqstep-gui-batch-resume-$stamp.stderr.log"
            $runArguments = @(
                "scripts\run_existing_input_batch.py",
                "--config", $controls["ConfigPathBox"].Text,
                "--job-dir", $batchDir,
                "--resume",
                "--compact"
            )
            $summaryStopOnFailure = & $GetJsonProperty $summary "stop_on_failure"
            if ([bool]$controls["BatchStopOnFailureBox"].IsChecked -or $summaryStopOnFailure -eq "True") {
                $runArguments += "--stop-on-failure"
            }
            $process = Start-WinQStepPythonProcess -Arguments $runArguments -StdoutPath $wrapperStdoutPath -StderrPath $wrapperStderrPath
            $jobState["Current"] = @{
                Mode = "existing_input_batch"
                Process = $process
                JobDir = $batchDir
                BatchSummaryPath = $summaryPath
                MetadataPath = $summaryPath
                OutputPath = ""
                WrapperStdoutPath = $wrapperStdoutPath
                WrapperStderrPath = $wrapperStderrPath
                Cancelled = $false
            }
            $controls["LogText"].Text = (& $BuildAsyncJobLog $jobState["Current"])
            & $SetJobStatusText (& $FormatRunningJobStatus $jobState["Current"])
            & $SetAsyncJobRunning $true (Format-WinQStepText "status.running_cp2k_pid" @($process.Id))
            $jobTimer.Start()
        }
        catch {
            $message = $_.Exception.Message
            $startedState = $jobState["Current"]
            if ($null -ne $startedState -and [string]$startedState["Mode"] -eq "existing_input_batch") {
                try {
                    Stop-WinQStepProcessTree ([System.Diagnostics.Process]$startedState["Process"])
                    $null = Save-WinQStepProcessOutput ([System.Diagnostics.Process]$startedState["Process"]) ([string]$startedState["WrapperStdoutPath"]) ([string]$startedState["WrapperStderrPath"])
                }
                catch {
                }
                $jobTimer.Stop()
                $jobState["Current"] = $null
            }
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

    $CompleteAsyncJob = {
        param([Parameter(Mandatory = $true)][hashtable]$State)
        $jobTimer.Stop()
        $process = [System.Diagnostics.Process]$State["Process"]
        $process.Refresh()
        $exitCode = if ($process.HasExited) { [int]$process.ExitCode } else { $null }
        $captured = Save-WinQStepProcessOutput $process ([string]$State["WrapperStdoutPath"]) ([string]$State["WrapperStderrPath"])
        $stdout = [string]$captured.Stdout
        $stderr = [string]$captured.Stderr
        if ([string]$State["Mode"] -eq "existing_input_batch") {
            $summary = $null
            if (-not [string]::IsNullOrWhiteSpace($stdout)) {
                try {
                    $summary = ($stdout | ConvertFrom-Json)
                }
                catch {
                    $summary = $null
                }
            }
            if ($null -eq $summary) {
                $summary = & $ReadMetadataFile ([string]$State["BatchSummaryPath"])
            }

            if ($null -ne $summary) {
                $finalStatus = if ([bool]$State["Cancelled"]) { Get-WinQStepText "status.cancelled" } elseif ($exitCode -eq 0) { Get-WinQStepText "status.ready" } else { Get-WinQStepText "status.finished_with_errors" }
                $logSections = @(& $FormatBatchSummary $summary)
                if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                    $logSections += "--- wrapper stderr ---`r`n$stderr"
                }
                $controls["LogText"].Text = ($logSections -join "`r`n`r`n")
                & $SetArtifactsFromBatchSummary $summary
            }
            else {
                $parts = @("Existing input batch wrapper exited without JSON summary. exit_code=$exitCode")
                if (-not [string]::IsNullOrWhiteSpace($stdout)) {
                    $parts += "--- wrapper stdout ---`r`n$stdout"
                }
                if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                    $parts += "--- wrapper stderr ---`r`n$stderr"
                }
                $controls["LogText"].Text = ($parts -join "`r`n`r`n")
                $finalStatus = if ([bool]$State["Cancelled"]) { Get-WinQStepText "status.cancelled" } else { Get-WinQStepText "status.finished_with_errors" }
                & $SetJobStatusText "Batch: status=$finalStatus | summary=$($State["BatchSummaryPath"])"
            }

            $controls["LogText"].ScrollToEnd()
            $jobState["Current"] = $null
            & $SetAsyncJobRunning $false $finalStatus
            return
        }
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
        if ([string]$current["Mode"] -eq "existing_input_batch") {
            $selectedIndex = & $GetSelectedBatchItemIndex
            $summary = & $ReadMetadataFile ([string]$current["BatchSummaryPath"])
            if ($null -ne $summary) {
                & $SetArtifactsFromBatchSummary $summary
                if ($selectedIndex -gt 0 -and $null -ne $controls["BatchResultsGrid"].ItemsSource) {
                    foreach ($row in @($controls["BatchResultsGrid"].ItemsSource)) {
                        try {
                            if ([int]$row.index -eq $selectedIndex) {
                                $controls["BatchResultsGrid"].SelectedItem = $row
                                break
                            }
                        }
                        catch {
                        }
                    }
                }
            }
        }
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
            generated_artifacts = @(& $GetGeneratedArtifacts (& $GetNestedValue $Item @("generated_artifacts")))
        }
        $artifacts["result_text"] = & $BuildResultSummaryFromArtifacts $artifacts
        $artifactState["Current"] = $artifacts
        $controls["BatchResultsGrid"].ItemsSource = $null
        $controls["BatchResultsGrid"].Visibility = [System.Windows.Visibility]::Collapsed
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

    $GetBatchResultTablePath = {
        param([Parameter(Mandatory = $true)][hashtable]$Current)
        $paths = $Current["paths"]
        $candidate = ""
        if ($null -ne $paths -and $paths.ContainsKey("metadata")) {
            $candidate = [string]$paths["metadata"]
        }
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            $jobDir = & $ResolveWindowsWorkspacePath $controls["JobDirBox"].Text
            [System.IO.Directory]::CreateDirectory($jobDir) | Out-Null
            return (Join-Path $jobDir "batch-results.tsv")
        }
        $parent = Split-Path -Parent $candidate
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = & $ResolveWindowsWorkspacePath $controls["JobDirBox"].Text
        }
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
        return (Join-Path $parent "batch-results.tsv")
    }.GetNewClosure()

    $SaveResultSummary = {
        $current = $artifactState["Current"]
        if ($null -eq $current -or [string]::IsNullOrWhiteSpace([string]$current["result_text"])) {
            throw "No result summary is available."
        }
        if ([string]$current["mode"] -eq "existing_input_batch" -and $null -ne $current["batch_summary"]) {
            $path = & $GetBatchResultTablePath $current
            $text = & $FormatBatchResultTsv $current["batch_summary"]
            $encoding = $Script:Utf8NoBomEncoding
            if ($null -eq $encoding) {
                $encoding = New-Object System.Text.UTF8Encoding($false)
            }
            [System.IO.File]::WriteAllText($path, $text, $encoding)
            $current["paths"]["results"] = $path
            $artifactState["Current"] = $current
            $controls["ArtifactSummaryText"].Text = & $BuildBatchArtifactSummary $current["batch_summary"]
            $controls["ArtifactText"].Text = "--- batch results: $path ---`r`n$text"
            $controls["LogText"].Text = "Saved batch result table: $path`r`n`r`n$text"
            & $UpdateArtifactControls
            return $path
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
        if ($Key -eq "input") {
            $controls["PreviewText"].Text = $text
            $previewState["Current"] = [ordered]@{
                InputPath = $path
                Text = $text
                SourceMode = "artifact_input"
            }
            & $UpdateRunTargetStatus
        }
        elseif ($Key -ne "output") {
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

    $GetTemplateControlText = {
        param([Parameter(Mandatory = $true)][string]$Name)
        if ($null -eq $controls[$Name]) {
            return ""
        }
        return ([string]$controls[$Name].Text).Trim()
    }.GetNewClosure()

    $GetTemplateControlChecked = {
        param([Parameter(Mandatory = $true)][string]$Name)
        return ($null -ne $controls[$Name] -and [bool]$controls[$Name].IsChecked)
    }.GetNewClosure()

    $SetTemplateDependentControls = {
        param(
            [Parameter(Mandatory = $true)][string[]]$Names,
            [Parameter(Mandatory = $true)][bool]$Active,
            [Parameter(Mandatory = $true)][bool]$Visible
        )
        $visibility = if ($Visible) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $opacity = if ($Active) { 1.0 } else { 0.45 }
        foreach ($name in $Names) {
            $control = $controls[$name]
            if ($null -eq $control) {
                continue
            }
            $control.Visibility = $visibility
            $control.IsEnabled = $Active
            $control.Opacity = $opacity
        }
    }.GetNewClosure()

    $SetTemplateSectionTone = {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][bool]$Active
        )
        $control = $controls[$Name]
        if ($null -eq $control) {
            $control = $window.FindName($Name)
        }
        if ($null -ne $control) {
            $control.Opacity = if ($Active) { 1.0 } else { 0.68 }
        }
    }.GetNewClosure()

    $SetTemplateHint = {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string]$Key,
            [string]$State = "neutral"
        )
        $control = $controls[$Name]
        if ($null -eq $control) {
            return
        }
        $control.Text = Get-WinQStepText $Key
        $control.Foreground = switch ($State) {
            "active" { [System.Windows.Media.Brushes]::ForestGreen }
            "warning" { [System.Windows.Media.Brushes]::DarkOrange }
            default { [System.Windows.Media.Brushes]::DimGray }
        }
    }.GetNewClosure()

    $SyncTemplateDependencyState = {
        $scfMethod = (& $GetTemplateControlText "ScfMethodBox").ToUpperInvariant()
        $dispersionEnabled = & $GetTemplateControlChecked "DispersionEnabledBox"
        & $SetTemplateDependentControls -Names @(
            "DispersionTypeLabel", "DispersionTypeBox",
            "DispersionParameterFileLabel", "DispersionParameterFileBox",
            "DispersionReferenceFunctionalLabel", "DispersionReferenceFunctionalBox"
        ) -Active $dispersionEnabled -Visible $dispersionEnabled
        if (-not $dispersionEnabled) {
            & $SetTemplateHint "DispersionHintText" "template.hint.dispersion_disabled"
        }
        elseif (
            [string]::IsNullOrWhiteSpace((& $GetTemplateControlText "DispersionTypeBox")) -or
            [string]::IsNullOrWhiteSpace((& $GetTemplateControlText "DispersionParameterFileBox")) -or
            [string]::IsNullOrWhiteSpace((& $GetTemplateControlText "DispersionReferenceFunctionalBox"))
        ) {
            & $SetTemplateHint "DispersionHintText" "template.hint.dispersion_missing" "warning"
        }
        else {
            & $SetTemplateHint "DispersionHintText" "template.hint.dispersion_enabled" "active"
        }

        $outerScfEnabled = & $GetTemplateControlChecked "OuterScfEnabledBox"
        & $SetTemplateSectionTone "TemplateOuterScfGroup" $outerScfEnabled
        & $SetTemplateDependentControls -Names @(
            "OuterScfEpsScfLabel", "OuterScfEpsScfBox",
            "OuterScfMaxScfLabel", "OuterScfMaxScfBox"
        ) -Active $outerScfEnabled -Visible $outerScfEnabled
        if (-not $outerScfEnabled) {
            & $SetTemplateHint "OuterScfHintText" "template.hint.outer_scf_disabled"
        }
        elseif (
            [string]::IsNullOrWhiteSpace((& $GetTemplateControlText "OuterScfEpsScfBox")) -or
            [string]::IsNullOrWhiteSpace((& $GetTemplateControlText "OuterScfMaxScfBox"))
        ) {
            & $SetTemplateHint "OuterScfHintText" "template.hint.outer_scf_missing" "warning"
        }
        else {
            & $SetTemplateHint "OuterScfHintText" "template.hint.outer_scf_enabled" "active"
        }

        $mixingEnabled = & $GetTemplateControlChecked "MixingEnabledBox"
        & $SetTemplateSectionTone "TemplateMixingGroup" $mixingEnabled
        & $SetTemplateDependentControls -Names @(
            "MixingMethodLabel", "MixingMethodBox",
            "MixingAlphaLabel", "MixingAlphaBox",
            "MixingBetaLabel", "MixingBetaBox"
        ) -Active $mixingEnabled -Visible $mixingEnabled
        if (-not $mixingEnabled) {
            & $SetTemplateHint "MixingHintText" "template.hint.mixing_disabled"
        }
        elseif ($scfMethod -ne "DIAGONALIZATION") {
            & $SetTemplateHint "MixingHintText" "template.hint.mixing_scf_method" "warning"
        }
        elseif (
            [string]::IsNullOrWhiteSpace((& $GetTemplateControlText "MixingMethodBox")) -or
            [string]::IsNullOrWhiteSpace((& $GetTemplateControlText "MixingAlphaBox")) -or
            [string]::IsNullOrWhiteSpace((& $GetTemplateControlText "MixingBetaBox"))
        ) {
            & $SetTemplateHint "MixingHintText" "template.hint.mixing_missing" "warning"
        }
        else {
            & $SetTemplateHint "MixingHintText" "template.hint.mixing_enabled" "active"
        }

        $smearingEnabled = & $GetTemplateControlChecked "SmearingEnabledBox"
        & $SetTemplateSectionTone "TemplateSmearingGroup" $smearingEnabled
        & $SetTemplateDependentControls -Names @(
            "SmearingMethodLabel", "SmearingMethodBox",
            "ElectronicTemperatureLabel", "ElectronicTemperatureBox"
        ) -Active $smearingEnabled -Visible $smearingEnabled
        $addedMosValue = 0
        $hasAddedMosNumber = [int]::TryParse((& $GetTemplateControlText "AddedMosBox"), [ref]$addedMosValue)
        if (-not $smearingEnabled) {
            & $SetTemplateHint "SmearingHintText" "template.hint.smearing_disabled"
        }
        elseif ($scfMethod -ne "DIAGONALIZATION") {
            & $SetTemplateHint "SmearingHintText" "template.hint.smearing_scf_method" "warning"
        }
        elseif (-not $hasAddedMosNumber -or $addedMosValue -le 0) {
            & $SetTemplateHint "SmearingHintText" "template.hint.smearing_added_mos" "warning"
        }
        elseif (
            [string]::IsNullOrWhiteSpace((& $GetTemplateControlText "SmearingMethodBox")) -or
            [string]::IsNullOrWhiteSpace((& $GetTemplateControlText "ElectronicTemperatureBox"))
        ) {
            & $SetTemplateHint "SmearingHintText" "template.hint.smearing_missing" "warning"
        }
        else {
            & $SetTemplateHint "SmearingHintText" "template.hint.smearing_enabled" "active"
        }

        $kpointsScheme = (& $GetTemplateControlText "KpointsSchemeBox").ToUpperInvariant()
        $kpointsKnown = @("NONE", "GAMMA", "MONKHORST-PACK").Contains($kpointsScheme)
        $kpointsEnabled = ($kpointsKnown -and $kpointsScheme -ne "NONE")
        $kpointsMonkhorstPack = ($kpointsScheme -eq "MONKHORST-PACK")
        & $SetTemplateSectionTone "TemplateKpointsGroup" $kpointsEnabled
        & $SetTemplateDependentControls -Names @("KpointsGridLabel", "KpointsGridBox") -Active $kpointsMonkhorstPack -Visible $kpointsMonkhorstPack
        & $SetTemplateDependentControls -Names @(
            "KpointsFullGridBox", "KpointsSymmetryBox",
            "KpointsWavefunctionsLabel", "KpointsWavefunctionsBox"
        ) -Active $kpointsEnabled -Visible $kpointsEnabled
        if (-not $kpointsKnown) {
            & $SetTemplateHint "KpointsHintText" "template.hint.kpoints_unknown" "warning"
        }
        elseif (-not $kpointsEnabled) {
            & $SetTemplateHint "KpointsHintText" "template.hint.kpoints_none"
        }
        elseif ($kpointsMonkhorstPack -and [string]::IsNullOrWhiteSpace((& $GetTemplateControlText "KpointsGridBox"))) {
            & $SetTemplateHint "KpointsHintText" "template.hint.kpoints_missing_grid" "warning"
        }
        elseif ($kpointsMonkhorstPack) {
            & $SetTemplateHint "KpointsHintText" "template.hint.kpoints_monkhorst_pack" "active"
        }
        else {
            & $SetTemplateHint "KpointsHintText" "template.hint.kpoints_gamma" "active"
        }

        $printSelected = @(
            "PrintMullikenBox", "PrintLowdinBox", "PrintPdosBox",
            "PrintEDensityCubeBox", "PrintVHartreeCubeBox"
        ).Where({ & $GetTemplateControlChecked $_ }).Count -gt 0
        & $SetTemplateSectionTone "TemplateDftPrintGroup" $printSelected
        if ($printSelected) {
            & $SetTemplateHint "DftPrintHintText" "template.hint.print_selected" "active"
        }
        else {
            & $SetTemplateHint "DftPrintHintText" "template.hint.print_none"
        }
    }.GetNewClosure()
    $Script:TemplateDependencySmokeSync = $SyncTemplateDependencyState

    $SetTemplateFieldsFromPayload = {
        param([Parameter(Mandatory = $true)]$Payload)
        $template = $Payload.template
        $dft = $template.dft
        $motion = $template.motion
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
        $controls["XcPbeParametrizationBox"].Text = & $GetJsonProperty $dft "xc_pbe_parametrization"
        $controls["DispersionEnabledBox"].IsChecked = @("1", "true", "yes", "on").Contains((& $GetJsonProperty $dft "dispersion_enabled" "False").ToLowerInvariant())
        $controls["DispersionTypeBox"].Text = & $GetJsonProperty $dft "dispersion_type"
        $controls["DispersionParameterFileBox"].Text = & $GetJsonProperty $dft "dispersion_parameter_file_name"
        $controls["DispersionReferenceFunctionalBox"].Text = & $GetJsonProperty $dft "dispersion_reference_functional"
        $controls["ChargeBox"].Text = & $GetJsonProperty $dft "charge"
        $controls["MultiplicityBox"].Text = & $GetJsonProperty $dft "multiplicity"
        $controls["UksEnabledBox"].IsChecked = @("1", "true", "yes", "on").Contains((& $GetJsonProperty $dft "uks_enabled" "False").ToLowerInvariant())
        $controls["CutoffBox"].Text = & $GetJsonProperty $dft "cutoff"
        $controls["RelCutoffBox"].Text = & $GetJsonProperty $dft "rel_cutoff"
        $controls["PoissonSolverBox"].Text = & $GetJsonProperty $dft "poisson_solver"
        $controls["WfnRestartFileNameBox"].Text = & $GetJsonProperty $dft "wfn_restart_file_name"
        $controls["ScfGuessBox"].Text = & $GetJsonProperty $dft "scf_guess"
        $controls["EpsScfBox"].Text = & $GetJsonProperty $dft "eps_scf"
        $controls["MaxScfBox"].Text = & $GetJsonProperty $dft "max_scf"
        $controls["OuterScfEnabledBox"].IsChecked = @("1", "true", "yes", "on").Contains((& $GetJsonProperty $dft "outer_scf_enabled" "False").ToLowerInvariant())
        $controls["OuterScfEpsScfBox"].Text = & $GetJsonProperty $dft "outer_scf_eps_scf"
        $controls["OuterScfMaxScfBox"].Text = & $GetJsonProperty $dft "outer_scf_max_scf"
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
        $controls["PrintMullikenBox"].IsChecked = @("1", "true", "yes", "on").Contains((& $GetJsonProperty $dft "print_mulliken" "False").ToLowerInvariant())
        $controls["PrintLowdinBox"].IsChecked = @("1", "true", "yes", "on").Contains((& $GetJsonProperty $dft "print_lowdin" "False").ToLowerInvariant())
        $controls["PrintPdosBox"].IsChecked = @("1", "true", "yes", "on").Contains((& $GetJsonProperty $dft "print_pdos" "False").ToLowerInvariant())
        $controls["PrintEDensityCubeBox"].IsChecked = @("1", "true", "yes", "on").Contains((& $GetJsonProperty $dft "print_e_density_cube" "False").ToLowerInvariant())
        $controls["PrintVHartreeCubeBox"].IsChecked = @("1", "true", "yes", "on").Contains((& $GetJsonProperty $dft "print_v_hartree_cube" "False").ToLowerInvariant())
        $controls["FixedAtomsBox"].Text = & $GetJsonVectorText $motion "fixed_atoms"
        $controls["FixedAtomComponentsBox"].Text = & $GetJsonProperty $motion "fixed_atom_components" "XYZ"
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
        & $SyncTemplateDependencyState
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
            xc_pbe_parametrization = $controls["XcPbeParametrizationBox"].Text
            dispersion_enabled = [bool]$controls["DispersionEnabledBox"].IsChecked
            dispersion_type = $controls["DispersionTypeBox"].Text
            dispersion_parameter_file_name = $controls["DispersionParameterFileBox"].Text
            dispersion_reference_functional = $controls["DispersionReferenceFunctionalBox"].Text
            charge = $controls["ChargeBox"].Text
            multiplicity = $controls["MultiplicityBox"].Text
            uks_enabled = [bool]$controls["UksEnabledBox"].IsChecked
            cutoff = $controls["CutoffBox"].Text
            rel_cutoff = $controls["RelCutoffBox"].Text
            poisson_solver = $controls["PoissonSolverBox"].Text
            wfn_restart_file_name = $controls["WfnRestartFileNameBox"].Text
            scf_guess = $controls["ScfGuessBox"].Text
            eps_scf = $controls["EpsScfBox"].Text
            max_scf = $controls["MaxScfBox"].Text
            outer_scf_enabled = [bool]$controls["OuterScfEnabledBox"].IsChecked
            outer_scf_eps_scf = $controls["OuterScfEpsScfBox"].Text
            outer_scf_max_scf = $controls["OuterScfMaxScfBox"].Text
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
            print_mulliken = [bool]$controls["PrintMullikenBox"].IsChecked
            print_lowdin = [bool]$controls["PrintLowdinBox"].IsChecked
            print_pdos = [bool]$controls["PrintPdosBox"].IsChecked
            print_e_density_cube = [bool]$controls["PrintEDensityCubeBox"].IsChecked
            print_v_hartree_cube = [bool]$controls["PrintVHartreeCubeBox"].IsChecked
            fixed_atoms = $controls["FixedAtomsBox"].Text
            fixed_atom_components = $controls["FixedAtomComponentsBox"].Text
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

    $ConfirmEditedInputPreviewRun = {
        param([Parameter(Mandatory = $true)]$EditedPreview)
        if ($EditedPreviewSmokeTestEnabled) {
            $EditedPreviewSmokeState["ConfirmationRequested"] = $true
        }
        if ($SuppressGuiMessageBoxes) {
            if ($EditedPreviewSmokeTestEnabled) {
                $EditedPreviewSmokeState["ConfirmationSuppressed"] = $true
                $EditedPreviewSmokeState["ConfirmationResult"] = "suppressed_yes"
            }
            & $AppendLog "Edited input preview confirmation suppressed for GUI smoke test."
            return $true
        }
        $result = [System.Windows.MessageBox]::Show(
            $window,
            (Get-WinQStepText "message.edited_preview_confirm"),
            (Get-WinQStepText "message.edited_preview_caption"),
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning,
            [System.Windows.MessageBoxResult]::No
        )
        if ($EditedPreviewSmokeTestEnabled) {
            $EditedPreviewSmokeState["ConfirmationResult"] = [string]$result
        }
        if ($result -ne [System.Windows.MessageBoxResult]::Yes) {
            & $AppendLog (Get-WinQStepText "message.edited_preview_cancelled")
            return $false
        }
        return $true
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

    $StartExistingInputBatchJob = {
        if ($null -ne $jobState["Current"]) {
            & $AppendLog "A CP2K job is already running."
            return
        }

        & $SetBusy $true (Get-WinQStepText "status.preparing_cp2k_job")
        try {
            $null = & $SaveConfigFields $true $false
            $prepareArguments = @(& $GetExistingInputBatchArguments $true)
            $prepareArguments += "--compact"
            $prepareResult = Invoke-WinQStepPython $prepareArguments
            $preparedSummary = & $GetBatchSummaryResult $prepareResult
            $summaryText = & $FormatBatchSummary $preparedSummary
            & $ClearInputPreviewState
            $controls["PreviewText"].Text = $summaryText
            $controls["LogText"].Text = $summaryText
            & $SetArtifactsFromBatchSummary $preparedSummary
            if ($prepareResult.ExitCode -ne 0 -or (& $GetJsonProperty $preparedSummary "status") -ne "prepared") {
                throw $summaryText
            }

            $batchDir = & $GetJsonProperty $preparedSummary "job_dir"
            if ([string]::IsNullOrWhiteSpace($batchDir)) {
                $batchDir = & $ResolveWindowsWorkspacePath $controls["JobDirBox"].Text
            }
            [System.IO.Directory]::CreateDirectory($batchDir) | Out-Null
            $summaryPath = & $GetJsonProperty $preparedSummary "summary_path"
            if ([string]::IsNullOrWhiteSpace($summaryPath)) {
                $summaryPath = Join-Path $batchDir "batch.winqstep-batch.json"
            }

            $stamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")
            $wrapperStdoutPath = Join-Path $batchDir "winqstep-gui-batch-$stamp.stdout.json"
            $wrapperStderrPath = Join-Path $batchDir "winqstep-gui-batch-$stamp.stderr.log"
            $runArguments = @(& $GetExistingInputBatchArguments $false)
            $runArguments += "--compact"
            $processArguments = $runArguments
            if ($BatchRunSmokeTestEnabled) {
                $processArguments = @("-c", "import time; time.sleep(5)")
            }
            $process = Start-WinQStepPythonProcess -Arguments $processArguments -StdoutPath $wrapperStdoutPath -StderrPath $wrapperStderrPath

            $jobState["Current"] = @{
                Mode = "existing_input_batch"
                Process = $process
                JobDir = $batchDir
                BatchSummaryPath = $summaryPath
                MetadataPath = $summaryPath
                OutputPath = ""
                WrapperStdoutPath = $wrapperStdoutPath
                WrapperStderrPath = $wrapperStderrPath
                Cancelled = $false
            }
            $controls["LogText"].Text = ($summaryText, (& $BuildAsyncJobLog $jobState["Current"])) -join "`r`n`r`n"
            if ($BatchRunSmokeTestEnabled) {
                $BatchRunSmokeState["Report"] = [ordered]@{
                    prepared_status = (& $GetJsonProperty $preparedSummary "status")
                    prepared_item_count = (& $GetJsonProperty $preparedSummary "item_count")
                    summary_path = $summaryPath
                    wrapper_stdout_path = $wrapperStdoutPath
                    wrapper_stderr_path = $wrapperStderrPath
                    run_arguments = $runArguments
                    preview_text = [string]$controls["PreviewText"].Text
                    artifact_summary_text = [string]$controls["ArtifactSummaryText"].Text
                    async_log_text = [string]$controls["LogText"].Text
                }
                try {
                    Stop-WinQStepProcessTree $process
                    $null = Save-WinQStepProcessOutput $process $wrapperStdoutPath $wrapperStderrPath
                }
                catch {
                }
                $jobState["Current"] = $null
                $controls["LogText"].Text = "$summaryText`r`n`r`nExisting input batch run smoke stopped before starting CP2K."
                & $SetBusy $false (Get-WinQStepText "status.ready")
                return
            }
            & $SetJobStatusText (& $FormatRunningJobStatus $jobState["Current"])
            & $SetAsyncJobRunning $true (Format-WinQStepText "status.running_cp2k_pid" @($process.Id))
            $jobTimer.Start()
        }
        catch {
            $message = $_.Exception.Message
            $startedState = $jobState["Current"]
            if ($null -ne $startedState -and [string]$startedState["Mode"] -eq "existing_input_batch") {
                try {
                    Stop-WinQStepProcessTree ([System.Diagnostics.Process]$startedState["Process"])
                    $null = Save-WinQStepProcessOutput ([System.Diagnostics.Process]$startedState["Process"]) ([string]$startedState["WrapperStdoutPath"]) ([string]$startedState["WrapperStderrPath"])
                }
                catch {
                }
                $jobTimer.Stop()
                $jobState["Current"] = $null
            }
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

    $StartAsyncJob = {
        if (& $TestIsExistingInputBatchMode) {
            & $StartExistingInputBatchJob
            return
        }

        if ($null -ne $jobState["Current"]) {
            & $AppendLog "A CP2K job is already running."
            return
        }

        & $SetBusy $true (Get-WinQStepText "status.preparing_cp2k_job")
        try {
            $editedPreview = & $GetEditedInputPreview
            $editedInputPath = ""
            if ($null -ne $editedPreview) {
                if (-not (& $ConfirmEditedInputPreviewRun $editedPreview)) {
                    & $SetBusy $false (Get-WinQStepText "status.ready")
                    return
                }
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
                    edited_preview_confirmation_requested = [bool]$EditedPreviewSmokeState["ConfirmationRequested"]
                    edited_preview_confirmation_suppressed = [bool]$EditedPreviewSmokeState["ConfirmationSuppressed"]
                    edited_preview_confirmation_result = [string]$EditedPreviewSmokeState["ConfirmationResult"]
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

    $OpenExternalUri = {
        param([Parameter(Mandatory = $true)][string]$Uri)
        try {
            $startInfo = [System.Diagnostics.ProcessStartInfo]::new($Uri)
            $startInfo.UseShellExecute = $true
            [System.Diagnostics.Process]::Start($startInfo) | Out-Null
            $controls["StatusText"].Text = "Opened CP2K manual."
        }
        catch {
            $message = "Failed to open external link: $($_.Exception.Message)"
            $controls["StatusText"].Text = $message
            if (-not $Script:SuppressGuiMessageBoxes) {
                [System.Windows.MessageBox]::Show(
                    $window,
                    $message,
                    (Get-WinQStepText "message.error_caption"),
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                ) | Out-Null
            }
        }
    }.GetNewClosure()

    $controls["Cp2kInputManualLink"].Add_RequestNavigate({
        param($sender, $eventArgs)
        & $OpenExternalUri ([string]$eventArgs.Uri.AbsoluteUri)
        $eventArgs.Handled = $true
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
    $controls["BrowseExistingInputButton"].Add_Click({
        & $SelectFilePath $controls["ExistingInputPathBox"] "CP2K input files (*.inp)|*.inp|All files (*.*)|*.*"
    }.GetNewClosure())
    $controls["BrowseBatchInputDirButton"].Add_Click({ & $SelectFolderPath $controls["BatchInputDirBox"] }.GetNewClosure())
    $controls["BrowseBatchInputFilesButton"].Add_Click({ & $SelectMultipleFilePaths $controls["BatchInputFilesBox"] "CP2K input files (*.inp)|*.inp|All files (*.*)|*.*" }.GetNewClosure())
    $controls["BrowseBatchInputListButton"].Add_Click({ & $SelectFilePath $controls["BatchInputListBox"] "Input list files (*.txt;*.lst;*.list)|*.txt;*.lst;*.list|All files (*.*)|*.*" }.GetNewClosure())
    $controls["BrowseJobDirButton"].Add_Click({ & $SelectFolderPath $controls["JobDirBox"] }.GetNewClosure())
    $controls["WorkflowModeRadio"].Add_Checked({ & $UpdateModeControls }.GetNewClosure())
    $controls["ExistingInputModeRadio"].Add_Checked({ & $UpdateModeControls }.GetNewClosure())
    $controls["ExistingInputBatchModeRadio"].Add_Checked({ & $UpdateModeControls }.GetNewClosure())
    $controls["ExistingInputPathBox"].Add_TextChanged({ & $UpdateRunTargetStatus }.GetNewClosure())
    $controls["BatchInputDirBox"].Add_TextChanged({
        & $ClearDefaultBatchInputFilesIfNeeded ([string]$controls["BatchInputDirBox"].Text)
        & $UpdateRunTargetStatus
    }.GetNewClosure())
    $controls["BatchInputFilesBox"].Add_TextChanged({ & $UpdateRunTargetStatus }.GetNewClosure())
    $controls["BatchInputListBox"].Add_TextChanged({
        & $ClearDefaultBatchInputFilesIfNeeded ([string]$controls["BatchInputListBox"].Text)
        & $UpdateRunTargetStatus
    }.GetNewClosure())
    $controls["PreviewText"].Add_TextChanged({ & $UpdateRunTargetStatus }.GetNewClosure())

    foreach ($name in @(
        "DispersionEnabledBox", "OuterScfEnabledBox", "MixingEnabledBox", "SmearingEnabledBox",
        "PrintMullikenBox", "PrintLowdinBox", "PrintPdosBox", "PrintEDensityCubeBox", "PrintVHartreeCubeBox"
    )) {
        $controls[$name].Add_Checked({ & $SyncTemplateDependencyState }.GetNewClosure())
        $controls[$name].Add_Unchecked({ & $SyncTemplateDependencyState }.GetNewClosure())
    }
    foreach ($name in @(
        "DispersionTypeBox", "DispersionParameterFileBox", "DispersionReferenceFunctionalBox",
        "OuterScfEpsScfBox", "OuterScfMaxScfBox",
        "ScfMethodBox", "AddedMosBox",
        "MixingMethodBox", "MixingAlphaBox", "MixingBetaBox",
        "SmearingMethodBox", "ElectronicTemperatureBox",
        "KpointsSchemeBox", "KpointsGridBox", "KpointsWavefunctionsBox"
    )) {
        $controls[$name].Add_SelectionChanged({ & $SyncTemplateDependencyState }.GetNewClosure())
        $controls[$name].Add_DropDownClosed({ & $SyncTemplateDependencyState }.GetNewClosure())
        $controls[$name].Add_LostFocus({ & $SyncTemplateDependencyState }.GetNewClosure())
    }

    $controls["DetectButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.detecting_environment") -Action {
            $null = & $SaveConfigFields $false $false
            $result = Invoke-WinQStepPython @("scripts\detect_environment.py", "--config", $controls["ConfigPathBox"].Text)
            $environmentText = $result.Output
            try {
                $environmentPayload = $result.Output | ConvertFrom-Json
                $environmentText = & $FormatEnvironmentProbeDisplay $environmentPayload
            }
            catch {
                if (-not [string]::IsNullOrWhiteSpace([string]$result.Error)) {
                    $environmentText = (($result.Output, $result.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n"
                }
            }
            $controls["EnvironmentText"].Text = $environmentText
            $controls["LogText"].Text = "--- detect_environment.py raw JSON ---`r`n$($result.Output)"
            & $AppendLog "detect_environment.py exited with code $($result.ExitCode)"
        }
    }.GetNewClosure())

    $controls["ImportButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.importing_structure") -Action {
            $result = Invoke-WinQStepPython @("scripts\import_structure.py", "--input", $controls["StructurePathBox"].Text, "--include-preview")
            $structureText = $result.Output
            if ($result.ExitCode -eq 0) {
                try {
                    $payload = $result.Output | ConvertFrom-Json
                    $structurePayload = if ($null -ne $payload.structure) { $payload.structure } else { $payload }
                    $structureText = & $FormatStructureImportDisplay $structurePayload
                    if ($null -ne $payload.preview) {
                        & $SetStructurePreview $payload.preview
                    }
                    else {
                        & $ClearStructurePreview
                    }
                }
                catch {
                    $structureText = $result.Output
                    & $ClearStructurePreview
                }
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$result.Error)) {
                $structureText = (($result.Output, $result.Error) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n"
                & $ClearStructurePreview
            }
            else {
                & $ClearStructurePreview
            }
            $controls["StructureText"].Text = $structureText
            & $AppendLog "import_structure.py exited with code $($result.ExitCode)"
        }
    }.GetNewClosure())

    $controls["PreviewButton"].Add_Click({
        $status = if (& $TestIsExistingInputBatchMode) {
            Get-WinQStepText "status.preparing_existing_input_batch_preview"
        }
        elseif (& $TestIsExistingInputMode) {
            Get-WinQStepText "status.preparing_existing_input_preview"
        }
        else {
            Get-WinQStepText "status.preparing_workflow_input_preview"
        }
        & $InvokeGuiAction -Status $status -Action {
            if (& $TestIsExistingInputBatchMode) {
                $null = & $SaveConfigFields $true $false
                $arguments = @(& $GetExistingInputBatchArguments $true)
                $arguments += "--compact"
                $result = Invoke-WinQStepPython $arguments
                $summary = & $GetBatchSummaryResult $result
                $summaryText = & $FormatBatchSummary $summary
                & $ClearInputPreviewState
                $controls["PreviewText"].Text = $summaryText
                $controls["LogText"].Text = $summaryText
                & $SetArtifactsFromBatchSummary $summary
                return
            }
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
    $Script:EnvironmentDisplaySmokeFormatter = $FormatEnvironmentProbeDisplay

    $controls["CancelJobButton"].Add_Click({
        & $CancelAsyncJob
    }.GetNewClosure())

    $controls["BatchResultsGrid"].Add_SelectionChanged({
        & $UpdateBatchQueueControls
    }.GetNewClosure())

    $controls["ResumeBatchButton"].Add_Click({
        try {
            & $StartExistingInputBatchResumeJob
        }
        catch {
            $message = $_.Exception.Message
            & $AppendLog "ERROR: $message"
            if (-not $SuppressGuiMessageBoxes) {
                [System.Windows.MessageBox]::Show(
                    $window,
                    $message,
                    (Get-WinQStepText "message.error_caption"),
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                ) | Out-Null
            }
            & $SetBusy $false (Get-WinQStepText "status.ready")
        }
    }.GetNewClosure())

    $controls["SkipBatchItemButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.updating_batch_queue") -Action {
            $null = & $InvokeBatchQueueAction "skip"
        }
    }.GetNewClosure())

    $controls["RerunBatchItemButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.updating_batch_queue") -Action {
            $null = & $InvokeBatchQueueAction "rerun"
        }
    }.GetNewClosure())

    $controls["CancelBatchItemButton"].Add_Click({
        & $InvokeGuiAction -Status (Get-WinQStepText "status.updating_batch_queue") -Action {
            $null = & $InvokeBatchQueueAction "cancel"
        }
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

    $controls["StructurePreviewViewport"].Add_MouseDown({
        param($sender, $eventArgs)
        if ($null -eq $structurePreviewState["Current"]) {
            return
        }
        $point = $eventArgs.GetPosition($controls["StructurePreviewViewport"])
        if ($eventArgs.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
            $structurePreviewState["DragMode"] = "rotate"
            $structurePreviewState["PendingSelectionKey"] = & $HitTestStructurePreviewAtom $point
        }
        elseif ($eventArgs.ChangedButton -eq [System.Windows.Input.MouseButton]::Right -or $eventArgs.ChangedButton -eq [System.Windows.Input.MouseButton]::Middle) {
            $structurePreviewState["DragMode"] = "pan"
            $structurePreviewState["PendingSelectionKey"] = ""
        }
        else {
            return
        }
        $structurePreviewState["IsDragging"] = $true
        $structurePreviewState["LastPoint"] = $point
        $structurePreviewState["DragStartPoint"] = $point
        $structurePreviewState["DragMoved"] = $false
        $null = $controls["StructurePreviewViewport"].CaptureMouse()
        $eventArgs.Handled = $true
    }.GetNewClosure())

    $controls["StructurePreviewViewport"].Add_MouseMove({
        param($sender, $eventArgs)
        if (-not [bool]$structurePreviewState["IsDragging"]) {
            return
        }
        $lastPoint = $structurePreviewState["LastPoint"]
        if ($null -eq $lastPoint) {
            return
        }
        $point = $eventArgs.GetPosition($controls["StructurePreviewViewport"])
        $deltaX = [double]$point.X - [double]$lastPoint.X
        $deltaY = [double]$point.Y - [double]$lastPoint.Y
        $startPoint = $structurePreviewState["DragStartPoint"]
        if ($null -ne $startPoint) {
            $totalDeltaX = [double]$point.X - [double]$startPoint.X
            $totalDeltaY = [double]$point.Y - [double]$startPoint.Y
            if ([Math]::Sqrt(($totalDeltaX * $totalDeltaX) + ($totalDeltaY * $totalDeltaY)) -gt 3.0) {
                $structurePreviewState["DragMoved"] = $true
            }
        }
        if (-not [bool]$structurePreviewState["DragMoved"] -and -not [string]::IsNullOrWhiteSpace([string]$structurePreviewState["PendingSelectionKey"])) {
            $structurePreviewState["LastPoint"] = $point
            $eventArgs.Handled = $true
            return
        }
        if ([Math]::Abs($deltaX) -gt 0.0 -or [Math]::Abs($deltaY) -gt 0.0) {
            & $ApplyStructurePreviewInteraction ([string]$structurePreviewState["DragMode"]) $deltaX $deltaY 0
        }
        $structurePreviewState["LastPoint"] = $point
        $eventArgs.Handled = $true
    }.GetNewClosure())

    $controls["StructurePreviewViewport"].Add_MouseUp({
        param($sender, $eventArgs)
        if (-not [bool]$structurePreviewState["IsDragging"]) {
            return
        }
        $dragMode = [string]$structurePreviewState["DragMode"]
        $pendingSelectionKey = [string]$structurePreviewState["PendingSelectionKey"]
        $wasClick = -not [bool]$structurePreviewState["DragMoved"]
        $structurePreviewState["IsDragging"] = $false
        $structurePreviewState["DragMode"] = ""
        $structurePreviewState["LastPoint"] = $null
        $structurePreviewState["DragStartPoint"] = $null
        $structurePreviewState["DragMoved"] = $false
        $structurePreviewState["PendingSelectionKey"] = ""
        $controls["StructurePreviewViewport"].ReleaseMouseCapture()
        if ($dragMode -eq "rotate" -and $wasClick -and -not [string]::IsNullOrWhiteSpace($pendingSelectionKey)) {
            & $ToggleStructureAtomSelectionByModelKey $pendingSelectionKey
        }
        $eventArgs.Handled = $true
    }.GetNewClosure())

    $controls["StructurePreviewViewport"].Add_MouseLeave({
        if ([bool]$structurePreviewState["IsDragging"] -and -not [bool]$controls["StructurePreviewViewport"].IsMouseCaptured) {
            $structurePreviewState["IsDragging"] = $false
            $structurePreviewState["DragMode"] = ""
            $structurePreviewState["LastPoint"] = $null
            $structurePreviewState["DragStartPoint"] = $null
            $structurePreviewState["DragMoved"] = $false
            $structurePreviewState["PendingSelectionKey"] = ""
        }
    }.GetNewClosure())

    $controls["StructurePreviewViewport"].Add_MouseWheel({
        param($sender, $eventArgs)
        if ($null -eq $structurePreviewState["Current"]) {
            return
        }
        & $ApplyStructurePreviewInteraction "zoom" 0.0 0.0 ([int]$eventArgs.Delta)
        $eventArgs.Handled = $true
    }.GetNewClosure())

    $controls["StructureResetViewButton"].Add_Click({
        if ($null -ne $structurePreviewState["Current"]) {
            & $ResetStructurePreviewCamera $structurePreviewState["Current"]
        }
    }.GetNewClosure())

    $controls["StructureApplyFixedAtomsButton"].Add_Click({
        $null = & $ApplyStructureSelectionToFixedAtoms
    }.GetNewClosure())

    $controls["StructureClearSelectionButton"].Add_Click({
        & $ClearStructureAtomSelection
    }.GetNewClosure())

    $controls["ClearButton"].Add_Click({
        $controls["EnvironmentText"].Clear()
        $controls["StructureText"].Clear()
        $controls["PreviewText"].Clear()
        $controls["LogText"].Clear()
        $controls["ArtifactSummaryText"].Clear()
        $controls["ArtifactText"].Clear()
        $controls["BatchResultsGrid"].ItemsSource = $null
        $controls["BatchResultsGrid"].Visibility = [System.Windows.Visibility]::Collapsed
        $controls["HistoryGrid"].ItemsSource = $null
        $controls["KindEntriesGrid"].ItemsSource = (& $NewKindEntriesTable).DefaultView
        $controls["DataLabelsGrid"].ItemsSource = $null
        $controls["DataLabelsGrid"].Visibility = [System.Windows.Visibility]::Collapsed
        & $ClearInputPreviewState
        & $ClearStructurePreview
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
    & $SyncTemplateDependencyState
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
        "--config", (Resolve-WinQStepPath "examples\winqstep.config.example.json"),
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

if ($EnvironmentDisplaySmokeTest) {
    $report = Test-WinQStepGuiPrerequisites
    $window = New-WinQStepWindow
    $payload = ([ordered]@{
        generated_at = "2026-06-30T00:00:00Z"
        config = [ordered]@{ path = "examples\winqstep.config.example.json" }
        host = [ordered]@{
            system = "Windows"
            release = "11"
            version = "10.0"
            machine = "AMD64"
        }
        wsl = [ordered]@{
            executable = "C:\Windows\System32\wsl.exe"
            available = $true
            selected_distro = "Ubuntu"
            shell_prelude = "conda deactivate >/dev/null 2>&1 || true"
            distros = @(
                [ordered]@{ name = "Ubuntu"; state = "Running"; version = "2"; default = $true }
            )
        }
        cp2k = [ordered]@{
            command = "/home/teng/cp2k/exe/local/cp2k.ssmp"
            version_output = "CP2K version 2025.2"
            data_dir = "/home/teng/cp2k/data"
            data_files = @("BASIS_MOLOPT", "GTH_POTENTIALS")
        }
        mpi = [ordered]@{ command = "" }
        workspace = [ordered]@{ default_windows_workspace = "outputs" }
        commands = [ordered]@{
            wsl_list = [ordered]@{ ok = $true; returncode = 0; error = $null }
            cp2k_version = [ordered]@{ ok = $true; returncode = 0; error = $null }
            find_mpi = [ordered]@{ ok = $true; returncode = 0; error = $null }
        }
        warnings = @("No MPI launcher is configured; jobs will run CP2K directly.")
    } | ConvertTo-Json -Depth 8 | ConvertFrom-Json)

    $text = & $Script:EnvironmentDisplaySmokeFormatter $payload
    $window.FindName("EnvironmentText").Text = $text
    $report["mode"] = "environment_display_smoke"
    $report["environment_text_has_summary"] = $text.Contains("Environment detection")
    $report["environment_text_has_distro"] = $text.Contains("Selected distro: Ubuntu")
    $report["environment_text_has_cp2k"] = $text.Contains("Command: /home/teng/cp2k/exe/local/cp2k.ssmp")
    $report["environment_text_has_data_files"] = ($text.Contains("Data files: 2") -and $text.Contains("- BASIS_MOLOPT"))
    $report["environment_text_has_warning"] = $text.Contains("WARNING: No MPI launcher is configured")
    $report["environment_text_has_command_status"] = $text.Contains("cp2k_version: ok=true returncode=0")
    $report["environment_text_is_not_raw_json"] = (-not $text.TrimStart().StartsWith("{"))
    $report["environment_text"] = $text
    $report | ConvertTo-Json -Depth 6

    if (
        $report["environment_text_has_summary"] -and
        $report["environment_text_has_distro"] -and
        $report["environment_text_has_cp2k"] -and
        $report["environment_text_has_data_files"] -and
        $report["environment_text_has_warning"] -and
        $report["environment_text_has_command_status"] -and
        $report["environment_text_is_not_raw_json"]
    ) {
        exit 0
    }
    exit 1
}

if ($BatchSmokeTest) {
    $report = Test-WinQStepGuiPrerequisites
    $window = New-WinQStepWindow
    $smokeDir = Resolve-WinQStepPath ("outputs\gui-batch-smoke-{0}" -f ([System.Guid]::NewGuid().ToString("N")))
    $batchInputDir = Join-Path $smokeDir "inputs"
    $batchJobDir = Join-Path $smokeDir "jobs"
    [System.IO.Directory]::CreateDirectory($batchInputDir) | Out-Null
    [System.IO.Directory]::CreateDirectory($batchJobDir) | Out-Null
    $smokeConfigPath = Join-Path $smokeDir "batch_smoke.config.json"
    [System.IO.File]::Copy((Resolve-WinQStepPath "examples\winqstep.config.example.json"), $smokeConfigPath, $true)
    [System.IO.File]::Copy((Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"), (Join-Path $batchInputDir "batch_one.inp"), $true)
    [System.IO.File]::Copy((Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"), (Join-Path $batchInputDir "batch_two.inp"), $true)

    $window.FindName("ConfigPathBox").Text = $smokeConfigPath
    $window.FindName("ExistingInputBatchModeRadio").IsChecked = $true
    $window.FindName("BatchInputDirBox").Text = $batchInputDir
    $window.FindName("JobDirBox").Text = $batchJobDir
    [System.Windows.Forms.Application]::DoEvents()

    $previewOk = $true
    $previewError = ""
    try {
        $button = $window.FindName("PreviewButton")
        $eventArgs = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
        $button.RaiseEvent($eventArgs)
        [System.Windows.Forms.Application]::DoEvents()
    }
    catch {
        $previewOk = $false
        $previewError = $_.Exception.Message
    }

    $previewText = [string]$window.FindName("PreviewText").Text
    $artifactSummaryText = [string]$window.FindName("ArtifactSummaryText").Text
    $summaryPath = Join-Path $batchJobDir "batch.winqstep-batch.json"
    $summary = $null
    if ([System.IO.File]::Exists($summaryPath)) {
        $summary = [System.IO.File]::ReadAllText($summaryPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    $batchGrid = $window.FindName("BatchResultsGrid")
    $batchGridRows = if ($null -ne $batchGrid.ItemsSource) { @($batchGrid.ItemsSource).Count } else { 0 }
    $batchGridVisible = ($batchGrid.Visibility -eq [System.Windows.Visibility]::Visible)

    $saveOk = $true
    $saveError = ""
    try {
        $button = $window.FindName("SaveResultsButton")
        $eventArgs = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
        $button.RaiseEvent($eventArgs)
        [System.Windows.Forms.Application]::DoEvents()
    }
    catch {
        $saveOk = $false
        $saveError = $_.Exception.Message
    }
    $savedBatchResultsPath = Join-Path $batchJobDir "batch-results.tsv"
    $savedBatchResultsText = if ([System.IO.File]::Exists($savedBatchResultsPath)) {
        [System.IO.File]::ReadAllText($savedBatchResultsPath, [System.Text.Encoding]::UTF8)
    }
    else {
        ""
    }

    $queueActionOk = $true
    $queueActionError = ""
    $queueSummary = $summary
    $SelectBatchGridIndex = {
        param([int]$Index)
        if ($null -ne $Script:BatchQueueSmokeSelectIndex) {
            & $Script:BatchQueueSmokeSelectIndex $Index
            return $true
        }
        $grid = $window.FindName("BatchResultsGrid")
        $sourceRows = if ($null -ne $grid.ItemsSource) { @($grid.ItemsSource) } else { @() }
        if ($sourceRows.Count -ge $Index) {
            try {
                $grid.SelectedItem = $sourceRows[$Index - 1]
                [System.Windows.Forms.Application]::DoEvents()
            }
            catch {
            }
            return $true
        }
        $rows = New-Object System.Collections.ArrayList
        if ($null -ne $grid.ItemsSource -and $grid.ItemsSource -is [System.Collections.IEnumerable]) {
            foreach ($row in ([System.Collections.IEnumerable]$grid.ItemsSource)) {
                [void]$rows.Add($row)
            }
        }
        if ($rows.Count -eq 0 -and $null -ne $grid.Items) {
            foreach ($row in @($grid.Items)) {
                [void]$rows.Add($row)
            }
        }
        foreach ($row in @($rows)) {
            try {
                $property = $row.PSObject.Properties["index"]
                $rowIndex = if ($null -ne $property) { [int]$property.Value } else { [int]$row.index }
                if ($rowIndex -eq $Index) {
                    $grid.SelectedItem = $row
                    [System.Windows.Forms.Application]::DoEvents()
                    return $true
                }
            }
            catch {
            }
        }
        return $false
    }
    try {
        if (-not (& $SelectBatchGridIndex 2)) {
            throw "Could not select batch item 2."
        }
        $eventArgs = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
        $window.FindName("SkipBatchItemButton").RaiseEvent($eventArgs)
        [System.Windows.Forms.Application]::DoEvents()
        $queueSummary = [System.IO.File]::ReadAllText($summaryPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

        if (-not (& $SelectBatchGridIndex 2)) {
            throw "Could not reselect batch item 2."
        }
        $eventArgs = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
        $window.FindName("RerunBatchItemButton").RaiseEvent($eventArgs)
        [System.Windows.Forms.Application]::DoEvents()
        $queueSummary = [System.IO.File]::ReadAllText($summaryPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

        if (-not (& $SelectBatchGridIndex 1)) {
            throw "Could not select batch item 1."
        }
        $eventArgs = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
        $window.FindName("CancelBatchItemButton").RaiseEvent($eventArgs)
        [System.Windows.Forms.Application]::DoEvents()
        $queueSummary = [System.IO.File]::ReadAllText($summaryPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    catch {
        $queueActionOk = $false
        $queueActionError = $_.Exception.Message
    }

    $report["mode"] = "batch_smoke"
    $report["preview_ok"] = $previewOk
    $report["preview_error"] = $previewError
    $report["save_ok"] = $saveOk
    $report["save_error"] = $saveError
    $report["batch_mode_loaded"] = ($window.FindName("ExistingInputBatchModeRadio") -is [System.Windows.Controls.RadioButton])
    $report["batch_stop_on_failure_loaded"] = ($window.FindName("BatchStopOnFailureBox") -is [System.Windows.Controls.CheckBox])
    $report["batch_input_enabled"] = [bool]$window.FindName("BatchInputDirBox").IsEnabled
    $report["batch_inputs_panel_visible"] = ($window.FindName("BatchInputsPanel").Visibility -eq [System.Windows.Visibility]::Visible)
    $report["batch_input_count_text"] = [string]$window.FindName("BatchInputCountText").Text
    $report["batch_stop_on_failure_enabled"] = [bool]$window.FindName("BatchStopOnFailureBox").IsEnabled
    $report["batch_import_disabled"] = (-not [bool]$window.FindName("ImportButton").IsEnabled)
    $report["batch_input_label"] = [string]$window.FindName("ExistingInputPathLabel").Text
    $report["preview_text_has_summary"] = $previewText.Contains("Existing input batch: status=prepared")
    $report["preview_text_has_items"] = ($previewText.Contains("inputs=2") -and $previewText.Contains("#1: status=prepared") -and $previewText.Contains("#2: status=prepared"))
    $report["artifact_summary_has_batch"] = ($artifactSummaryText.Contains("mode=existing_input_batch") -and $artifactSummaryText.Contains("summary=[exists]"))
    $report["summary_exists"] = [System.IO.File]::Exists($summaryPath)
    $report["summary_path"] = $summaryPath
    $report["summary_status"] = if ($null -ne $summary) { [string]$summary.status } else { "" }
    $report["summary_item_count"] = if ($null -ne $summary) { [int]$summary.item_count } else { 0 }
    $report["batch_results_grid_visible"] = $batchGridVisible
    $report["batch_results_grid_rows"] = $batchGridRows
    $report["batch_results_tsv_exists"] = [System.IO.File]::Exists($savedBatchResultsPath)
    $report["batch_results_tsv_has_header"] = $savedBatchResultsText.StartsWith("index`tstatus`treturncode`tinput_path")
    $report["batch_results_tsv_has_rows"] = ($savedBatchResultsText.Contains("batch_one.inp") -and $savedBatchResultsText.Contains("batch_two.inp"))
    $report["metadata_button_enabled"] = [bool]$window.FindName("ViewMetadataButton").IsEnabled
    $report["results_button_enabled"] = [bool]$window.FindName("ViewResultsButton").IsEnabled
    $report["batch_resume_button_enabled"] = [bool]$window.FindName("ResumeBatchButton").IsEnabled
    $report["batch_queue_action_ok"] = $queueActionOk
    $report["batch_queue_action_error"] = $queueActionError
    $report["batch_queue_cancelled_first"] = if ($null -ne $queueSummary) { [string]$queueSummary.items[0].status -eq "cancelled" } else { $false }
    $report["batch_queue_rerun_second"] = if ($null -ne $queueSummary) { [string]$queueSummary.items[1].status -eq "queued" } else { $false }
    $report["batch_queue_summary_pending"] = if ($null -ne $queueSummary) { [string]$queueSummary.status -eq "pending" } else { $false }
    $report | ConvertTo-Json -Depth 6

    if (
        $report["preview_ok"] -and
        $report["save_ok"] -and
        $report["batch_mode_loaded"] -and
        $report["batch_stop_on_failure_loaded"] -and
        $report["batch_input_enabled"] -and
        $report["batch_inputs_panel_visible"] -and
        $report["batch_input_count_text"].Contains("2") -and
        $report["batch_stop_on_failure_enabled"] -and
        $report["batch_import_disabled"] -and
        $report["preview_text_has_summary"] -and
        $report["preview_text_has_items"] -and
        $report["artifact_summary_has_batch"] -and
        $report["summary_exists"] -and
        $report["summary_status"] -eq "prepared" -and
        $report["summary_item_count"] -eq 2 -and
        $report["batch_results_grid_visible"] -and
        $report["batch_results_grid_rows"] -eq 2 -and
        $report["batch_results_tsv_exists"] -and
        $report["batch_results_tsv_has_header"] -and
        $report["batch_results_tsv_has_rows"] -and
        $report["metadata_button_enabled"] -and
        $report["results_button_enabled"] -and
        $report["batch_resume_button_enabled"] -and
        $report["batch_queue_action_ok"] -and
        $report["batch_queue_cancelled_first"] -and
        $report["batch_queue_rerun_second"] -and
        $report["batch_queue_summary_pending"]
    ) {
        exit 0
    }
    exit 1
}

if ($BatchRunSmokeTest) {
    $report = Test-WinQStepGuiPrerequisites
    $window = New-WinQStepWindow
    $smokeDir = Resolve-WinQStepPath ("outputs\gui-batch-run-smoke-{0}" -f ([System.Guid]::NewGuid().ToString("N")))
    $batchInputDir = Join-Path $smokeDir "inputs"
    $batchJobDir = Join-Path $smokeDir "jobs"
    [System.IO.Directory]::CreateDirectory($batchInputDir) | Out-Null
    [System.IO.Directory]::CreateDirectory($batchJobDir) | Out-Null
    $smokeConfigPath = Join-Path $smokeDir "batch_run_smoke.config.json"
    [System.IO.File]::Copy((Resolve-WinQStepPath "examples\winqstep.config.example.json"), $smokeConfigPath, $true)
    [System.IO.File]::Copy((Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"), (Join-Path $batchInputDir "batch_run_one.inp"), $true)
    [System.IO.File]::Copy((Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"), (Join-Path $batchInputDir "batch_run_two.inp"), $true)

    $window.FindName("ConfigPathBox").Text = $smokeConfigPath
    $window.FindName("ExistingInputBatchModeRadio").IsChecked = $true
    $window.FindName("BatchInputDirBox").Text = $batchInputDir
    $window.FindName("JobDirBox").Text = $batchJobDir
    [System.Windows.Forms.Application]::DoEvents()

    $runOk = $true
    $runError = ""
    try {
        $button = $window.FindName("RunButton")
        $eventArgs = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
        $button.RaiseEvent($eventArgs)
        [System.Windows.Forms.Application]::DoEvents()
    }
    catch {
        $runOk = $false
        $runError = $_.Exception.Message
    }

    $smokeReport = $BatchRunSmokeState["Report"]
    $window.FindName("WorkflowModeRadio").IsChecked = $true
    [System.Windows.Forms.Application]::DoEvents()
    $workflowRunEnabled = [bool]$window.FindName("RunButton").IsEnabled
    $window.FindName("ExistingInputModeRadio").IsChecked = $true
    [System.Windows.Forms.Application]::DoEvents()
    $existingRunEnabled = [bool]$window.FindName("RunButton").IsEnabled
    $window.FindName("ExistingInputBatchModeRadio").IsChecked = $true
    [System.Windows.Forms.Application]::DoEvents()
    $batchRunEnabled = [bool]$window.FindName("RunButton").IsEnabled

    $report["mode"] = "batch_run_smoke"
    $report["run_ok"] = $runOk
    $report["run_error"] = $runError
    $report["run_reported"] = ($null -ne $smokeReport)
    $report["prepared_status"] = if ($null -ne $smokeReport) { [string]$smokeReport["prepared_status"] } else { "" }
    $report["prepared_item_count"] = if ($null -ne $smokeReport) { [int]$smokeReport["prepared_item_count"] } else { 0 }
    $report["summary_exists"] = if ($null -ne $smokeReport) { [System.IO.File]::Exists([string]$smokeReport["summary_path"]) } else { $false }
    $report["run_arguments"] = if ($null -ne $smokeReport) { @($smokeReport["run_arguments"]) } else { @() }
    $report["run_arguments_has_batch_script"] = @($report["run_arguments"]).Contains("scripts\run_existing_input_batch.py")
    $report["run_arguments_has_compact"] = @($report["run_arguments"]).Contains("--compact")
    $report["preview_text_has_summary"] = if ($null -ne $smokeReport) { ([string]$smokeReport["preview_text"]).Contains("Existing input batch: status=prepared") } else { $false }
    $report["artifact_summary_has_batch"] = if ($null -ne $smokeReport) { ([string]$smokeReport["artifact_summary_text"]).Contains("mode=existing_input_batch") } else { $false }
    $report["async_log_has_batch_status"] = if ($null -ne $smokeReport) { ([string]$smokeReport["async_log_text"]).Contains("Existing input batch: status=prepared") } else { $false }
    $report["async_log_has_batch_progress"] = if ($null -ne $smokeReport) { ([string]$smokeReport["async_log_text"]).Contains("completed=0/2") } else { $false }
    $report["async_log_has_wrapper_paths"] = if ($null -ne $smokeReport) { ([string]$smokeReport["async_log_text"]).Contains("wrapper_stdout=") -and ([string]$smokeReport["async_log_text"]).Contains("wrapper_stderr=") } else { $false }
    $report["workflow_run_enabled_after_batch"] = $workflowRunEnabled
    $report["existing_run_enabled_after_batch"] = $existingRunEnabled
    $report["batch_run_enabled_after_batch"] = $batchRunEnabled
    $report | ConvertTo-Json -Depth 6

    if (
        $report["run_ok"] -and
        $report["run_reported"] -and
        $report["prepared_status"] -eq "prepared" -and
        $report["prepared_item_count"] -eq 2 -and
        $report["summary_exists"] -and
        $report["run_arguments_has_batch_script"] -and
        $report["run_arguments_has_compact"] -and
        $report["preview_text_has_summary"] -and
        $report["artifact_summary_has_batch"] -and
        $report["async_log_has_batch_status"] -and
        $report["async_log_has_batch_progress"] -and
        $report["async_log_has_wrapper_paths"] -and
        $report["workflow_run_enabled_after_batch"] -and
        $report["existing_run_enabled_after_batch"] -and
        $report["batch_run_enabled_after_batch"]
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
    [System.IO.File]::Copy((Resolve-WinQStepPath "examples\winqstep.config.example.json"), $smokeConfigPath, $true)
    [System.IO.File]::Copy((Resolve-WinQStepPath "examples\templates\energy_pbe.example.json"), $smokeTemplatePath, $true)
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
    [System.Windows.Forms.Application]::DoEvents()
    $editedRunTargetBeforeRun = [string]$window.FindName("RunTargetText").Text
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
    $report["edited_run_target_before_run"] = $editedRunTargetBeforeRun
    $report["preview_original_has_global"] = $originalPreviewText.Contains("&GLOBAL")
    $report["edited_preview_reported"] = ($null -ne $runReport)
    $report["edited_preview_used"] = if ($null -ne $runReport) { [bool]$runReport["edited_preview_used"] } else { $false }
    $report["edited_preview_confirmation_requested"] = if ($null -ne $runReport) { [bool]$runReport["edited_preview_confirmation_requested"] } else { $false }
    $report["edited_preview_confirmation_suppressed"] = if ($null -ne $runReport) { [bool]$runReport["edited_preview_confirmation_suppressed"] } else { $false }
    $report["edited_preview_confirmation_result"] = if ($null -ne $runReport) { [string]$runReport["edited_preview_confirmation_result"] } else { "" }
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
        $report["edited_run_target_before_run"].Contains("edited preview") -and
        $report["edited_preview_used"] -and
        $report["edited_preview_confirmation_requested"] -and
        $report["edited_preview_confirmation_suppressed"] -and
        $report["edited_preview_confirmation_result"] -eq "suppressed_yes" -and
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
    [System.IO.File]::Copy((Resolve-WinQStepPath "examples\winqstep.config.example.json"), $smokeConfigPath, $true)
    [System.IO.File]::Copy((Resolve-WinQStepPath "examples\templates\energy_pbe.example.json"), $smokeTemplatePath, $true)
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

    $historySmokeDir = Resolve-WinQStepPath ("outputs\gui-button-history-smoke-{0}" -f ([System.Guid]::NewGuid().ToString("N")))
    [System.IO.Directory]::CreateDirectory($historySmokeDir) | Out-Null
    $smokeConfigPath = Join-Path $historySmokeDir "button_smoke.config.json"
    $smokeTemplatePath = Join-Path $historySmokeDir "button_smoke.template.json"
    [System.IO.File]::Copy((Resolve-WinQStepPath "examples\winqstep.config.example.json"), $smokeConfigPath, $true)
    [System.IO.File]::Copy((Resolve-WinQStepPath "examples\templates\energy_pbe.example.json"), $smokeTemplatePath, $true)
    $smokeConfig = [System.IO.File]::ReadAllText($smokeConfigPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $smokeConfig.default_windows_workspace = $historySmokeDir
    [System.IO.File]::WriteAllText(
        $smokeConfigPath,
        (($smokeConfig | ConvertTo-Json -Depth 8) + "`n"),
        $Script:Utf8NoBomEncoding
    )

    $historyMetadataPath = Join-Path $historySmokeDir "button_history.winqstep.json"
    $historyInputPath = Join-Path $historySmokeDir "button_history.inp"
    $historyOutputPath = Join-Path $historySmokeDir "button_history.out"
    $historyStdoutPath = Join-Path $historySmokeDir "button_history.stdout.log"
    $historyStderrPath = Join-Path $historySmokeDir "button_history.stderr.log"
    $historyResultsPath = Join-Path $historySmokeDir "button_history.results.txt"
    if ([System.IO.File]::Exists($historyResultsPath)) {
        [System.IO.File]::Delete($historyResultsPath)
    }
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
    $structurePreviewContent = $window.FindName("StructurePreviewVisual").Content
    $structurePreviewGeometryCount = if ($null -ne $structurePreviewContent -and $null -ne $structurePreviewContent.Children) {
        $structurePreviewContent.Children.Count
    }
    else {
        0
    }
    $structurePreviewStatus = [string]$window.FindName("StructurePreviewStatusText").Text
    $structureResetEnabledAfterImport = [bool]$window.FindName("StructureResetViewButton").IsEnabled
    $structureSelectionHookLoaded = ($null -ne $Script:StructurePreviewSmokeToggleAtomSelection)
    if ($structureSelectionHookLoaded) {
        & $Script:StructurePreviewSmokeToggleAtomSelection 1
        & $Script:StructurePreviewSmokeToggleAtomSelection 3
        [System.Windows.Forms.Application]::DoEvents()
    }
    $structureSelectionTextAfterToggle = [string]$window.FindName("StructureSelectionText").Text
    $structureApplySelectionEnabled = [bool]$window.FindName("StructureApplyFixedAtomsButton").IsEnabled
    $structureClearSelectionEnabled = [bool]$window.FindName("StructureClearSelectionButton").IsEnabled
    $appliedFixedAtoms = ""
    if ($null -ne $Script:StructurePreviewSmokeApplyFixedAtoms) {
        $appliedFixedAtoms = [string](& $Script:StructurePreviewSmokeApplyFixedAtoms)
        [System.Windows.Forms.Application]::DoEvents()
    }
    $fixedAtomsAfterStructureSelection = [string]$window.FindName("FixedAtomsBox").Text
    $window.FindName("TemplateRunTypeBox").Text = "GEO_OPT"
    $structurePreviewCamera = $window.FindName("StructurePreviewCamera")
    $structurePreviewInitialDistance = [double]$structurePreviewCamera.Position.Z
    $structurePreviewInitialPanX = [double]$structurePreviewCamera.Position.X
    $structurePreviewInitialPanY = [double]$structurePreviewCamera.Position.Y
    $structurePreviewInitialTransform = [string]$window.FindName("StructurePreviewVisual").Content.Transform.Value
    $structurePreviewStateSnapshot = if ($null -ne $Script:StructurePreviewSmokeGetState) {
        & $Script:StructurePreviewSmokeGetState
    }
    else {
        $null
    }
    $structurePreviewInitialFitsViewport = $false
    if ($null -ne $structurePreviewStateSnapshot) {
        $structurePreviewFitDistance = [double]($structurePreviewStateSnapshot["fit_distance"])
        $structurePreviewSnapshotRadius = [double]($structurePreviewStateSnapshot["radius"])
        $structurePreviewInitialFitsViewport = (
            [Math]::Abs($structurePreviewInitialDistance - $structurePreviewFitDistance) -lt 0.001 -and
            [Math]::Abs([double]($structurePreviewStateSnapshot["default_distance"]) - $structurePreviewFitDistance) -lt 0.001 -and
            [double]($structurePreviewStateSnapshot["viewport_width"]) -ge 320.0 -and
            [double]($structurePreviewStateSnapshot["viewport_height"]) -ge 320.0 -and
            $structurePreviewFitDistance -gt ($structurePreviewSnapshotRadius * 2.4)
        )
    }
    $structurePreviewRotatedTransform = $structurePreviewInitialTransform
    $structurePreviewPannedPosition = $structurePreviewCamera.Position
    $structurePreviewDistanceBeforeZoom = [double]$structurePreviewCamera.Position.Z
    $structurePreviewZoomedDistance = $structurePreviewDistanceBeforeZoom
    $structurePreviewInteractionHook = $Script:StructurePreviewSmokeApplyInteraction
    if ($null -ne $structurePreviewInteractionHook) {
        & $structurePreviewInteractionHook "rotate" 40.0 20.0 0
        [System.Windows.Forms.Application]::DoEvents()
        $structurePreviewRotatedTransform = [string]$window.FindName("StructurePreviewVisual").Content.Transform.Value
        & $structurePreviewInteractionHook "pan" 30.0 -15.0 0
        [System.Windows.Forms.Application]::DoEvents()
        $structurePreviewPannedPosition = $structurePreviewCamera.Position
        $structurePreviewDistanceBeforeZoom = [double]$structurePreviewCamera.Position.Z
        & $structurePreviewInteractionHook "zoom" 0.0 0.0 120
        [System.Windows.Forms.Application]::DoEvents()
        $structurePreviewZoomedDistance = [double]$structurePreviewCamera.Position.Z
    }
    & $RecordButtonSmokeClick "StructureResetViewButton"
    $structurePreviewResetPosition = $structurePreviewCamera.Position
    $structurePreviewResetTransform = [string]$window.FindName("StructurePreviewVisual").Content.Transform.Value

    & $RecordButtonSmokeClick "PreviewButton" "PreviewWorkflowButton"
    $workflowPreviewText = [string]$window.FindName("PreviewText").Text
    $workflowRunTargetAfterPreview = [string]$window.FindName("RunTargetText").Text

    $window.FindName("ExistingInputModeRadio").IsChecked = $true
    [System.Windows.Forms.Application]::DoEvents()
    $existingModeImportDisabled = (-not [bool]$window.FindName("ImportButton").IsEnabled)
    $existingRunTargetBeforePreview = [string]$window.FindName("RunTargetText").Text
    & $RecordButtonSmokeClick "PreviewButton" "PreviewExistingInputButton"
    $existingPreviewText = [string]$window.FindName("PreviewText").Text
    $existingRunTargetAfterPreview = [string]$window.FindName("RunTargetText").Text

    $batchInputDir = Join-Path $historySmokeDir "batch-inputs"
    $batchJobDir = Join-Path $historySmokeDir "batch-jobs"
    [System.IO.Directory]::CreateDirectory($batchInputDir) | Out-Null
    [System.IO.Directory]::CreateDirectory($batchJobDir) | Out-Null
    [System.IO.File]::Copy((Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"), (Join-Path $batchInputDir "button_batch_one.inp"), $true)
    [System.IO.File]::Copy((Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"), (Join-Path $batchInputDir "button_batch_two.inp"), $true)
    $window.FindName("ExistingInputBatchModeRadio").IsChecked = $true
    $window.FindName("BatchInputDirBox").Text = $batchInputDir
    $window.FindName("JobDirBox").Text = $batchJobDir
    [System.Windows.Forms.Application]::DoEvents()
    $batchModeImportDisabled = (-not [bool]$window.FindName("ImportButton").IsEnabled)
    $batchModeStopOnFailureEnabled = [bool]$window.FindName("BatchStopOnFailureBox").IsEnabled
    $batchRunTargetBeforePreview = [string]$window.FindName("RunTargetText").Text
    & $RecordButtonSmokeClick "PreviewButton" "PreviewExistingInputBatchButton"
    $batchPreviewText = [string]$window.FindName("PreviewText").Text
    $batchRunTargetAfterPreview = [string]$window.FindName("RunTargetText").Text
    $batchArtifactSummaryText = [string]$window.FindName("ArtifactSummaryText").Text
    $batchSummaryPath = Join-Path $batchJobDir "batch.winqstep-batch.json"
    $window.FindName("JobDirBox").Text = $historySmokeDir

    & $RecordButtonSmokeClick "HistoryButton"
    $historyLogText = [string]$window.FindName("LogText").Text

    $historyGrid = $window.FindName("HistoryGrid")
    $historyItems = @($historyGrid.ItemsSource)
    $selectedHistoryItem = $null
    foreach ($item in $historyItems) {
        if ([string]$item.metadata_path -eq [string]$historyMetadataPath) {
            $selectedHistoryItem = $item
            break
        }
    }
    if ($null -eq $selectedHistoryItem) {
        foreach ($item in $historyItems) {
            if ([string]$item.project_name -eq "button_history") {
                $selectedHistoryItem = $item
                break
            }
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
    $savedResultsPath = $historyResultsPath
    $savedResultsText = if ([System.IO.File]::Exists($savedResultsPath)) {
        [System.IO.File]::ReadAllText($savedResultsPath, [System.Text.Encoding]::UTF8)
    }
    else {
        ""
    }

    & $RecordButtonSmokeClick "ViewInputButton"
    $previewTextAfterViewInput = [string]$window.FindName("PreviewText").Text
    & $RecordButtonSmokeClick "ViewOutputButton"
    $previewTextAfterViewOutput = [string]$window.FindName("PreviewText").Text
    $artifactTextAfterViewOutput = [string]$window.FindName("ArtifactText").Text
    foreach ($buttonName in @("ViewMetadataButton", "ViewStdoutButton", "ViewStderrButton")) {
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
    $structurePreviewContentAfterClear = $window.FindName("StructurePreviewVisual").Content
    $structurePreviewGeometryCountAfterClear = if ($null -ne $structurePreviewContentAfterClear -and $null -ne $structurePreviewContentAfterClear.Children) {
        $structurePreviewContentAfterClear.Children.Count
    }
    else {
        0
    }

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
    $report["structure_preview_geometry_count"] = $structurePreviewGeometryCount
    $report["structure_preview_status_has_atoms"] = $structurePreviewStatus.Contains("3/3")
    $report["structure_preview_reset_enabled_after_import"] = $structureResetEnabledAfterImport
    $report["structure_selection_hook_loaded"] = $structureSelectionHookLoaded
    $report["structure_selection_text_after_toggle"] = $structureSelectionTextAfterToggle
    $report["structure_apply_selection_enabled"] = $structureApplySelectionEnabled
    $report["structure_clear_selection_enabled"] = $structureClearSelectionEnabled
    $report["structure_applied_fixed_atoms"] = $appliedFixedAtoms
    $report["fixed_atoms_after_structure_selection"] = $fixedAtomsAfterStructureSelection
    $report["structure_preview_initial_distance_fits_viewport"] = $structurePreviewInitialFitsViewport
    $report["structure_preview_interaction_hook_loaded"] = ($null -ne $structurePreviewInteractionHook)
    $report["structure_preview_rotate_changed_transform"] = ($structurePreviewRotatedTransform -ne $structurePreviewInitialTransform)
    $report["structure_preview_pan_changed_camera"] = (
        [Math]::Abs([double]$structurePreviewPannedPosition.X - $structurePreviewInitialPanX) -gt 0.001 -or
        [Math]::Abs([double]$structurePreviewPannedPosition.Y - $structurePreviewInitialPanY) -gt 0.001
    )
    $report["structure_preview_zoom_changed_distance"] = ([Math]::Abs($structurePreviewZoomedDistance - $structurePreviewDistanceBeforeZoom) -gt 0.001)
    $report["structure_preview_reset_restored_camera"] = (
        [Math]::Abs([double]$structurePreviewResetPosition.X - $structurePreviewInitialPanX) -lt 0.001 -and
        [Math]::Abs([double]$structurePreviewResetPosition.Y - $structurePreviewInitialPanY) -lt 0.001 -and
        [Math]::Abs([double]$structurePreviewResetPosition.Z - $structurePreviewInitialDistance) -lt 0.001
    )
    $report["structure_preview_reset_restored_transform"] = ($structurePreviewResetTransform -eq $structurePreviewInitialTransform)
    $report["history_grid_count"] = $historyItems.Count
    $report["history_selected_project"] = if ($null -ne $selectedHistoryItem) { [string]$selectedHistoryItem.project_name } else { "" }
    $report["history_log_has_jobs"] = $historyLogText.Contains("History jobs:")
    $report["existing_mode_import_disabled"] = $existingModeImportDisabled
    $report["batch_mode_import_disabled"] = $batchModeImportDisabled
    $report["batch_mode_stop_on_failure_enabled"] = $batchModeStopOnFailureEnabled
    $report["workflow_run_target_after_preview"] = $workflowRunTargetAfterPreview
    $report["existing_run_target_before_preview"] = $existingRunTargetBeforePreview
    $report["existing_run_target_after_preview"] = $existingRunTargetAfterPreview
    $report["batch_run_target_before_preview"] = $batchRunTargetBeforePreview
    $report["batch_run_target_after_preview"] = $batchRunTargetAfterPreview
    $report["batch_preview_has_summary"] = $batchPreviewText.Contains("Existing input batch: status=prepared")
    $report["batch_preview_has_items"] = ($batchPreviewText.Contains("inputs=2") -and $batchPreviewText.Contains("#1: status=prepared") -and $batchPreviewText.Contains("#2: status=prepared"))
    $report["batch_artifact_summary_has_batch"] = ($batchArtifactSummaryText.Contains("mode=existing_input_batch") -and $batchArtifactSummaryText.Contains("summary=[exists]"))
    $report["batch_summary_exists"] = [System.IO.File]::Exists($batchSummaryPath)
    $report["workflow_preview_has_global"] = $workflowPreviewText.Contains("&GLOBAL")
    $report["existing_preview_has_global"] = $existingPreviewText.Contains("&GLOBAL")
    $report["artifact_summary_has_history"] = $artifactSummaryBeforeClear.Contains("button_history")
    $report["artifact_summary_has_energy"] = $artifactSummaryBeforeClear.Contains("energy_hartree=-17.2193503253033")
    $report["artifact_results_has_force_table"] = ($artifactResultsTextBeforeClear.Contains("Forces (hartree/bohr)") -and $artifactResultsTextBeforeClear.Contains("total_atomic_force=0.00148299452 hartree/bohr"))
    $report["result_summary_saved"] = [System.IO.File]::Exists($savedResultsPath)
    $report["result_summary_path_in_summary"] = $artifactSummaryAfterSave.Contains("results=[exists] $savedResultsPath")
    $report["result_summary_file_has_force"] = $savedResultsText.Contains("total_atomic_force=0.00148299452 hartree/bohr")
    $report["artifact_input_synced_preview"] = $previewTextAfterViewInput.Contains("&GLOBAL")
    $report["artifact_output_text_has_program_end"] = $artifactTextAfterViewOutput.Contains("PROGRAM ENDED")
    $report["artifact_output_preserved_input_preview"] = (
        $previewTextAfterViewOutput -eq $previewTextAfterViewInput -and
        $previewTextAfterViewOutput.Contains("&GLOBAL") -and
        -not $previewTextAfterViewOutput.Contains("PROGRAM ENDED")
    )
    $report["artifact_text_has_stderr"] = $artifactTextBeforeClear.Contains("stderr smoke")
    $report["artifact_log_has_stderr"] = $logTextBeforeClear.Contains("stderr smoke")
    $report["preview_text_preserved_after_output_artifact"] = $previewTextBeforeClear.Contains("&GLOBAL") -and -not $previewTextBeforeClear.Contains("PROGRAM ENDED")
    $report["language_apply_switched_to_zh"] = ($languageAfterApply -eq "zh-CN")
    $report["language_apply_changed_preview_text"] = ($previewButtonTextAfterLanguageApply -ne "Preview")
    $report["clear_emptied_text_fields"] = $textFieldsCleared
    $report["clear_removed_structure_preview_geometry"] = ($structurePreviewGeometryCountAfterClear -eq 0)
    $report["clear_disabled_structure_reset"] = (-not [bool]$window.FindName("StructureResetViewButton").IsEnabled)
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
        $report["structure_preview_geometry_count"] -ge 3 -and
        $report["structure_preview_status_has_atoms"] -and
        $report["structure_preview_reset_enabled_after_import"] -and
        $report["structure_selection_hook_loaded"] -and
        $report["structure_apply_selection_enabled"] -and
        $report["structure_clear_selection_enabled"] -and
        ($report["fixed_atoms_after_structure_selection"] -eq "1 3") -and
        $report["structure_preview_initial_distance_fits_viewport"] -and
        $report["structure_preview_interaction_hook_loaded"] -and
        $report["structure_preview_rotate_changed_transform"] -and
        $report["structure_preview_pan_changed_camera"] -and
        $report["structure_preview_zoom_changed_distance"] -and
        $report["structure_preview_reset_restored_camera"] -and
        $report["structure_preview_reset_restored_transform"] -and
        $report["history_grid_count"] -gt 0 -and
        $report["history_selected_project"] -eq "button_history" -and
        $report["history_log_has_jobs"] -and
        $report["existing_mode_import_disabled"] -and
        $report["batch_mode_import_disabled"] -and
        $report["batch_mode_stop_on_failure_enabled"] -and
        $report["workflow_run_target_after_preview"].Contains("Run target:") -and
        $report["existing_run_target_before_preview"].Contains("quickstep_energy.inp") -and
        $report["existing_run_target_after_preview"].Contains("quickstep_energy.inp") -and
        $report["batch_run_target_before_preview"].Contains("2") -and
        $report["batch_run_target_after_preview"].Contains("2") -and
        $report["batch_preview_has_summary"] -and
        $report["batch_preview_has_items"] -and
        $report["batch_artifact_summary_has_batch"] -and
        $report["batch_summary_exists"] -and
        $report["workflow_preview_has_global"] -and
        $report["existing_preview_has_global"] -and
        $report["artifact_summary_has_history"] -and
        $report["artifact_summary_has_energy"] -and
        $report["artifact_results_has_force_table"] -and
        $report["result_summary_saved"] -and
        $report["result_summary_path_in_summary"] -and
        $report["result_summary_file_has_force"] -and
        $report["artifact_input_synced_preview"] -and
        $report["artifact_output_text_has_program_end"] -and
        $report["artifact_output_preserved_input_preview"] -and
        $report["artifact_text_has_stderr"] -and
        $report["artifact_log_has_stderr"] -and
        $report["preview_text_preserved_after_output_artifact"] -and
        $report["language_apply_switched_to_zh"] -and
        $report["language_apply_changed_preview_text"] -and
        $report["clear_emptied_text_fields"] -and
        $report["clear_removed_structure_preview_geometry"] -and
        $report["clear_disabled_structure_reset"] -and
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
    $window.FindName("ConfigPathBox").Text = Resolve-WinQStepPath "examples\winqstep.config.example.json"
    $window.FindName("TemplatePathBox").Text = Resolve-WinQStepPath "examples\templates\energy_pbe.example.json"
    foreach ($buttonName in @("LoadConfigButton", "LoadTemplateButton")) {
        $eventArgs = [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)
        $window.FindName($buttonName).RaiseEvent($eventArgs)
        [System.Windows.Forms.Application]::DoEvents()
    }
    $workflowRunTargetText = [string]$window.FindName("RunTargetText").Text
    $expectedEncodingText = "$([char]0x4e2d)$([char]0x6587)$([char]0x8def)$([char]0x5f84):D:\Library\$([char]0x81ea)$([char]0x5236)$([char]0x54c1)"
    $chineseFolderName = "$([char]0x81ea)$([char]0x5236)$([char]0x54c1)"
    $encodingProbeResult = Invoke-WinQStepPython @(
        "-c",
        "import json; sep = chr(92); text = ''.join(chr(x) for x in [0x4e2d, 0x6587, 0x8def, 0x5f84]) + ':D:' + sep + 'Library' + sep + ''.join(chr(x) for x in [0x81ea, 0x5236, 0x54c1]); print(json.dumps(dict(text=text), ensure_ascii=False))"
    )
    $encodingProbe = Get-JsonResult $encodingProbeResult
    $previewResult = Invoke-WinQStepPython @(
        "scripts\run_workflow.py",
        "--config", (Resolve-WinQStepPath "examples\winqstep.config.example.json"),
        "--template", (Resolve-WinQStepPath "examples\templates\energy_pbe.example.json"),
        "--structure", (Resolve-WinQStepPath "tests\fixtures\structures\water.xyz"),
        "--job-dir", (Resolve-WinQStepPath "outputs\gui-smoke"),
        "--project-name", "gui_smoke",
        "--prepare-only",
        "--compact"
    )
    $previewMetadata = Get-JsonResult $previewResult
    $existingPreviewResult = Invoke-WinQStepPython @(
        "scripts\run_existing_input.py",
        "--config", (Resolve-WinQStepPath "examples\winqstep.config.example.json"),
        "--input", (Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"),
        "--job-dir", (Resolve-WinQStepPath "outputs\gui-existing-smoke"),
        "--prepare-only",
        "--compact"
    )
    $existingPreviewMetadata = Get-JsonResult $existingPreviewResult
    $existingBatchPreviewResult = Invoke-WinQStepPython @(
        "scripts\run_existing_input_batch.py",
        "--config", (Resolve-WinQStepPath "examples\winqstep.config.example.json"),
        "--input", (Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"),
        "--job-dir", (Resolve-WinQStepPath "outputs\gui-existing-batch-smoke"),
        "--prepare-only",
        "--compact"
    )
    $existingBatchPreviewSummary = Get-JsonResult $existingBatchPreviewResult
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
    $batchSelectorDir = Join-Path $historySmokeDir "batch-selector"
    [System.IO.Directory]::CreateDirectory($batchSelectorDir) | Out-Null
    $batchSelectorOne = Join-Path $batchSelectorDir "selector_one.inp"
    $batchSelectorTwo = Join-Path $batchSelectorDir "selector_two.inp"
    $batchSelectorList = Join-Path $batchSelectorDir "selector-list.txt"
    [System.IO.File]::Copy((Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"), $batchSelectorOne, $true)
    [System.IO.File]::Copy((Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"), $batchSelectorTwo, $true)
    [System.IO.File]::WriteAllText($batchSelectorList, "# selector smoke`nselector_two.inp`n", $Script:Utf8NoBomEncoding)
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
    [System.Windows.Forms.Application]::DoEvents()
    $existingModeInputEnabled = [bool]$window.FindName("ExistingInputPathBox").IsEnabled
    $existingModeImportEnabled = [bool]$window.FindName("ImportButton").IsEnabled
    $existingRunTargetText = [string]$window.FindName("RunTargetText").Text
    $window.FindName("ExistingInputBatchModeRadio").IsChecked = $true
    $window.FindName("BatchInputDirBox").Text = ""
    $window.FindName("BatchInputFilesBox").Text = $batchSelectorOne
    $window.FindName("BatchInputListBox").Text = $batchSelectorList
    [System.Windows.Forms.Application]::DoEvents()
    $batchModeInputEnabled = [bool]$window.FindName("BatchInputDirBox").IsEnabled
    $batchInputsPanelVisible = ($window.FindName("BatchInputsPanel").Visibility -eq [System.Windows.Visibility]::Visible)
    $existingInputPathCollapsedInBatch = ($window.FindName("ExistingInputPathBox").Visibility -eq [System.Windows.Visibility]::Collapsed)
    $batchInputCountText = [string]$window.FindName("BatchInputCountText").Text
    $batchModeImportEnabled = [bool]$window.FindName("ImportButton").IsEnabled
    $batchModeStopOnFailureEnabled = [bool]$window.FindName("BatchStopOnFailureBox").IsEnabled
    $batchModeLabelText = [string]$window.FindName("ExistingInputPathLabel").Text
    $batchRunTargetText = [string]$window.FindName("RunTargetText").Text
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
    $report["run_target_loaded"] = ($window.FindName("RunTargetText") -is [System.Windows.Controls.TextBlock])
    $report["run_target_label_text"] = [string]$window.FindName("RunTargetLabel").Text
    $report["run_target_workflow_text"] = $workflowRunTargetText
    $report["run_target_existing_text"] = $existingRunTargetText
    $report["run_target_batch_text"] = $batchRunTargetText
    $report["structure_preview_viewport_loaded"] = ($window.FindName("StructurePreviewViewport") -is [System.Windows.Controls.Viewport3D])
    $report["structure_preview_visual_loaded"] = ($window.FindName("StructurePreviewVisual") -is [System.Windows.Media.Media3D.ModelVisual3D])
    $report["structure_preview_camera_loaded"] = ($window.FindName("StructurePreviewCamera") -is [System.Windows.Media.Media3D.PerspectiveCamera])
    $report["structure_preview_status_initial"] = [string]$window.FindName("StructurePreviewStatusText").Text
    $report["structure_reset_button_initially_disabled"] = (-not [bool]$window.FindName("StructureResetViewButton").IsEnabled)
    $report["structure_selection_text_initial"] = [string]$window.FindName("StructureSelectionText").Text
    $report["structure_apply_fixed_atoms_initially_disabled"] = (-not [bool]$window.FindName("StructureApplyFixedAtomsButton").IsEnabled)
    $report["structure_clear_selection_initially_disabled"] = (-not [bool]$window.FindName("StructureClearSelectionButton").IsEnabled)
    $report["artifact_summary_loaded"] = ($window.FindName("ArtifactSummaryText") -is [System.Windows.Controls.TextBox])
    $report["artifact_text_loaded"] = ($window.FindName("ArtifactText") -is [System.Windows.Controls.TextBox])
    $report["batch_results_grid_loaded"] = ($window.FindName("BatchResultsGrid") -is [System.Windows.Controls.DataGrid])
    $report["batch_results_grid_initially_collapsed"] = ($window.FindName("BatchResultsGrid").Visibility -eq [System.Windows.Visibility]::Collapsed)
    $report["batch_queue_buttons_loaded"] = @(
        "ResumeBatchButton", "SkipBatchItemButton", "RerunBatchItemButton", "CancelBatchItemButton"
    ).Where({ $window.FindName($_) -is [System.Windows.Controls.Button] }).Count
    $report["batch_queue_buttons_initially_disabled"] = @(
        "ResumeBatchButton", "SkipBatchItemButton", "RerunBatchItemButton", "CancelBatchItemButton"
    ).Where({ [bool]$window.FindName($_).IsEnabled }).Count -eq 0
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
    $configWorkspaceResolvedPath = if ([System.IO.Path]::IsPathRooted($configWorkspace)) {
        [System.IO.Path]::GetFullPath($configWorkspace)
    }
    else {
        Resolve-WinQStepPath $configWorkspace
    }
    $expectedWorkspacePath = Resolve-WinQStepPath "outputs"
    $report["config_workspace_resolved_path"] = $configWorkspaceResolvedPath
    $report["config_workspace_expected_path"] = $expectedWorkspacePath
    $report["config_workspace_resolution_ok"] = (
        [string]$configWorkspace -eq "outputs" -and
        [string]$configWorkspaceResolvedPath -eq [string]$expectedWorkspacePath
    )
    $report["config_workspace_encoding_ok"] = $report["config_workspace_resolution_ok"]
    $report["config_validation_text"] = [string]$window.FindName("ConfigValidationText").Text
    $templateManualLink = $window.FindName("Cp2kInputManualLink")
    $templateComboNames = @(
        "TemplateProjectBox", "TemplateRunTypeBox", "PrintLevelBox", "BasisSetFileBox", "PotentialFileBox",
        "PoissonSolverBox", "WfnRestartFileNameBox",
        "XcFunctionalBox", "XcPbeParametrizationBox", "DispersionTypeBox",
        "DispersionParameterFileBox", "DispersionReferenceFunctionalBox",
        "EpsScfBox", "ChargeBox", "MultiplicityBox",
        "CutoffBox", "RelCutoffBox", "MaxScfBox", "GeoOptimizerBox", "GeoMaxIterBox",
        "CellOptTypeBox", "CellOptOptimizerBox", "CellOptMaxIterBox",
        "CellOptPressureToleranceBox",
        "FixedAtomsBox", "FixedAtomComponentsBox",
        "ScfMethodBox", "ScfGuessBox", "AddedMosBox", "DiagonalizationAlgorithmBox",
        "OtMinimizerBox", "OtPreconditionerBox",
        "OuterScfEpsScfBox", "OuterScfMaxScfBox", "MixingMethodBox",
        "MixingAlphaBox", "MixingBetaBox", "SmearingMethodBox",
        "ElectronicTemperatureBox", "KpointsSchemeBox", "KpointsGridBox",
        "KpointsWavefunctionsBox",
        "FallbackPeriodicBox", "FallbackCellABox", "FallbackCellBBox", "FallbackCellCBox"
    )
    $templateSectionGroupNames = @(
        "TemplateGlobalGroup", "TemplateDftGroup", "TemplatePoissonGroup", "TemplateXcGroup", "TemplateScfGroup", "TemplateOuterScfGroup",
        "TemplateMixingGroup", "TemplateSmearingGroup", "TemplateKpointsGroup", "TemplateDftPrintGroup", "TemplateCellGroup",
        "TemplateKindGroup", "TemplateFixedAtomsGroup", "TemplateGeoOptGroup", "TemplateCellOptGroup"
    )
    $templateSectionTabNames = @(
        "TemplateCoreTab", "TemplateDftTab", "TemplateSubsystemTab", "TemplateMotionTab"
    )
    $templateDependencyHintNames = @(
        "DispersionHintText", "OuterScfHintText", "MixingHintText", "SmearingHintText", "KpointsHintText", "DftPrintHintText"
    )
    $GetTemplateSectionHeaderText = {
        param([Parameter(Mandatory = $true)][string]$Name)
        $header = $window.FindName($Name).Header
        if ($header -is [System.Windows.Controls.TextBlock]) {
            return [string]$header.Text
        }
        return ([string]$header).Replace("__", "_")
    }
    $report["template_tab_loaded"] = ($window.FindName("TemplateProjectBox") -is [System.Windows.Controls.ComboBox])
    $report["template_manual_link_loaded"] = ($templateManualLink -is [System.Windows.Documents.Hyperlink])
    $report["template_manual_link_uri"] = if ($templateManualLink -is [System.Windows.Documents.Hyperlink]) {
        [string]$templateManualLink.NavigateUri.AbsoluteUri
    }
    else {
        ""
    }
    $report["template_section_tabs_loaded"] = $templateSectionTabNames.Where({ $window.FindName($_) -is [System.Windows.Controls.TabItem] }).Count
    $report["template_section_tab_headers"] = @($templateSectionTabNames | ForEach-Object { & $GetTemplateSectionHeaderText $_ })
    $report["template_section_groups_loaded"] = $templateSectionGroupNames.Where({ $window.FindName($_) -is [System.Windows.Controls.GroupBox] }).Count
    $report["template_section_group_headers"] = @($templateSectionGroupNames | ForEach-Object { & $GetTemplateSectionHeaderText $_ })
    $report["template_section_group_left_margins"] = @($templateSectionGroupNames | ForEach-Object { [int]$window.FindName($_).Margin.Left })
    $report["template_dependency_hints_loaded"] = $templateDependencyHintNames.Where({ $window.FindName($_) -is [System.Windows.Controls.TextBlock] }).Count
    $report["template_dependency_smoke_sync_loaded"] = ($null -ne $Script:TemplateDependencySmokeSync)
    $report["template_dispersion_details_hidden_when_disabled"] = ($window.FindName("DispersionTypeBox").Visibility -eq [System.Windows.Visibility]::Collapsed)
    $report["template_outer_scf_details_hidden_when_disabled"] = ($window.FindName("OuterScfEpsScfBox").Visibility -eq [System.Windows.Visibility]::Collapsed)
    $report["template_mixing_details_hidden_when_disabled"] = ($window.FindName("MixingMethodBox").Visibility -eq [System.Windows.Visibility]::Collapsed)
    $report["template_smearing_details_visible_when_enabled"] = ($window.FindName("SmearingMethodBox").Visibility -eq [System.Windows.Visibility]::Visible)
    $report["template_kpoints_grid_hidden_when_none"] = ($window.FindName("KpointsGridBox").Visibility -eq [System.Windows.Visibility]::Collapsed)
    $report["template_kpoints_wavefunctions_hidden_when_none"] = ($window.FindName("KpointsWavefunctionsBox").Visibility -eq [System.Windows.Visibility]::Collapsed)
    $report["template_print_group_dimmed_when_none"] = ([double]$window.FindName("TemplateDftPrintGroup").Opacity -lt 1.0)
    $report["template_print_hint_text"] = [string]$window.FindName("DftPrintHintText").Text
    $report["template_combo_fields_loaded"] = $templateComboNames.Where({ $window.FindName($_) -is [System.Windows.Controls.ComboBox] }).Count
    $report["template_combo_fields_editable"] = $templateComboNames.Where({ [bool]$window.FindName($_).IsEditable }).Count
    $report["template_run_type_options"] = @($window.FindName("TemplateRunTypeBox").Items | ForEach-Object { [string]$_.Content })
    $report["template_print_level_options"] = @($window.FindName("PrintLevelBox").Items | ForEach-Object { [string]$_.Content })
    $report["template_poisson_solver_options"] = @($window.FindName("PoissonSolverBox").Items | ForEach-Object { [string]$_.Content })
    $report["template_scf_guess_options"] = @($window.FindName("ScfGuessBox").Items | ForEach-Object { [string]$_.Content })
    $report["template_fixed_atom_components_options"] = @($window.FindName("FixedAtomComponentsBox").Items | ForEach-Object { [string]$_.Content })
    $report["template_optimizer_options"] = @($window.FindName("GeoOptimizerBox").Items | ForEach-Object { [string]$_.Content })
    $report["template_cell_opt_type_options"] = @($window.FindName("CellOptTypeBox").Items | ForEach-Object { [string]$_.Content })
    $report["template_project_name"] = [string]$window.FindName("TemplateProjectBox").Text
    $report["template_run_type"] = [string]$window.FindName("TemplateRunTypeBox").Text
    $report["template_print_level"] = [string]$window.FindName("PrintLevelBox").Text
    $report["template_xc_functional"] = [string]$window.FindName("XcFunctionalBox").Text
    $report["template_xc_pbe_parametrization"] = [string]$window.FindName("XcPbeParametrizationBox").Text
    $report["template_dispersion_enabled"] = [bool]$window.FindName("DispersionEnabledBox").IsChecked
    $report["template_dispersion_type"] = [string]$window.FindName("DispersionTypeBox").Text
    $report["template_dispersion_parameter_file"] = [string]$window.FindName("DispersionParameterFileBox").Text
    $report["template_dispersion_reference_functional"] = [string]$window.FindName("DispersionReferenceFunctionalBox").Text
    $report["template_cutoff"] = [string]$window.FindName("CutoffBox").Text
    $report["template_poisson_solver"] = [string]$window.FindName("PoissonSolverBox").Text
    $report["template_wfn_restart_file_name"] = [string]$window.FindName("WfnRestartFileNameBox").Text
    $report["template_uks_enabled"] = [bool]$window.FindName("UksEnabledBox").IsChecked
    $report["template_scf_method"] = [string]$window.FindName("ScfMethodBox").Text
    $report["template_scf_guess"] = [string]$window.FindName("ScfGuessBox").Text
    $report["template_added_mos"] = [string]$window.FindName("AddedMosBox").Text
    $report["template_outer_scf_enabled"] = [bool]$window.FindName("OuterScfEnabledBox").IsChecked
    $report["template_outer_scf_eps_scf"] = [string]$window.FindName("OuterScfEpsScfBox").Text
    $report["template_outer_scf_max_scf"] = [string]$window.FindName("OuterScfMaxScfBox").Text
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
    $report["template_print_mulliken"] = [bool]$window.FindName("PrintMullikenBox").IsChecked
    $report["template_print_lowdin"] = [bool]$window.FindName("PrintLowdinBox").IsChecked
    $report["template_print_pdos"] = [bool]$window.FindName("PrintPdosBox").IsChecked
    $report["template_print_e_density_cube"] = [bool]$window.FindName("PrintEDensityCubeBox").IsChecked
    $report["template_print_v_hartree_cube"] = [bool]$window.FindName("PrintVHartreeCubeBox").IsChecked
    $report["template_fixed_atoms"] = [string]$window.FindName("FixedAtomsBox").Text
    $report["template_fixed_atom_components"] = [string]$window.FindName("FixedAtomComponentsBox").Text
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
    $report["existing_batch_preview_exit_code"] = $existingBatchPreviewResult.ExitCode
    $report["existing_batch_preview_mode"] = $existingBatchPreviewSummary.mode
    $report["existing_batch_preview_status"] = $existingBatchPreviewSummary.status
    $report["existing_batch_preview_item_count"] = $existingBatchPreviewSummary.item_count
    $report["existing_batch_preview_summary_exists"] = [System.IO.File]::Exists([string]$existingBatchPreviewSummary.summary_path)
    $report["history_exit_code"] = $historyResult.ExitCode
    $report["history_job_count"] = $historyJobs.Count
    $report["history_first_mode"] = if ($historyJobs.Count -gt 0) { [string]$historyJobs[0].mode } else { "" }
    $report["history_first_warning_count"] = if ($historyJobs.Count -gt 0) { $historyJobs[0].warning_count } else { $null }
    $report["existing_mode_input_enabled"] = $existingModeInputEnabled
    $report["existing_mode_import_enabled"] = $existingModeImportEnabled
    $report["existing_input_batch_mode_loaded"] = ($window.FindName("ExistingInputBatchModeRadio") -is [System.Windows.Controls.RadioButton])
    $report["batch_stop_on_failure_loaded"] = ($window.FindName("BatchStopOnFailureBox") -is [System.Windows.Controls.CheckBox])
    $report["batch_mode_input_enabled"] = $batchModeInputEnabled
    $report["batch_inputs_panel_visible"] = $batchInputsPanelVisible
    $report["existing_input_path_collapsed_in_batch"] = $existingInputPathCollapsedInBatch
    $report["batch_input_count_text"] = $batchInputCountText
    $report["batch_mode_import_enabled"] = $batchModeImportEnabled
    $report["batch_mode_stop_on_failure_enabled"] = $batchModeStopOnFailureEnabled
    $report["batch_mode_label_text"] = $batchModeLabelText
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

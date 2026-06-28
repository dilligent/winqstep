#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Script:RepoRoot = Split-Path -Parent $PSScriptRoot
$Script:PythonCommand = "python"
$Script:Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($false)

function Set-WinQStepUtf8Encoding {
    [Console]::InputEncoding = $Script:Utf8NoBomEncoding
    [Console]::OutputEncoding = $Script:Utf8NoBomEncoding
    $global:OutputEncoding = $Script:Utf8NoBomEncoding
    $env:PYTHONIOENCODING = "utf-8"
    $env:PYTHONUTF8 = "1"
}

Set-WinQStepUtf8Encoding

function Resolve-WinQStepPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    return [System.IO.Path]::GetFullPath((Join-Path $Script:RepoRoot $RelativePath))
}

function Add-WinQStepWpfAssemblies {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Windows.Forms
}

function Test-WinQStepGuiPrerequisites {
    Add-WinQStepWpfAssemblies
    $python = Get-Command $Script:PythonCommand -ErrorAction SilentlyContinue
    if ($null -eq $python) {
        throw "python was not found on PATH."
    }

    $requiredFiles = @(
        "scripts\detect_environment.py",
        "scripts\import_structure.py",
        "scripts\run_workflow.py",
        "scripts\run_existing_input.py",
        "scripts\list_job_history.py",
        "examples\winqstep.config.json",
        "examples\templates\energy_pbe.json",
        "tests\fixtures\structures\water.xyz",
        "tests\fixtures\quickstep_energy.inp"
    )
    $missing = @(
        foreach ($relativePath in $requiredFiles) {
            $path = Resolve-WinQStepPath $relativePath
            if (-not (Test-Path -LiteralPath $path)) {
                $relativePath
            }
        }
    )
    if ($missing.Count -gt 0) {
        throw "Missing required file(s): $($missing -join ', ')"
    }

    return [ordered]@{
        wpf_available = $true
        python = $python.Source
        repo_root = $Script:RepoRoot
        checked_files = $requiredFiles
    }
}

function Invoke-WinQStepPython {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    Push-Location $Script:RepoRoot
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & $Script:PythonCommand @Arguments 2>&1
        $exitCode = if ($null -eq $global:LASTEXITCODE) { 0 } else { $global:LASTEXITCODE }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Pop-Location
    }

    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output = (($output | Out-String).TrimEnd())
    }
}

function Get-JsonResult {
    param([Parameter(Mandatory = $true)]$Result)
    if ($Result.ExitCode -ne 0) {
        throw $Result.Output
    }
    try {
        return ($Result.Output | ConvertFrom-Json)
    }
    catch {
        throw "Command did not return JSON. Raw output:`n$($Result.Output)"
    }
}

function Format-Cp2kSummary {
    param([Parameter(Mandatory = $true)]$Metadata)
    if ($null -eq $Metadata.cp2k_output) {
        return ""
    }
    $summary = $Metadata.cp2k_output
    $warningCount = if ($null -eq $summary.warning_count) { "n/a" } else { [string]$summary.warning_count }
    return "CP2K summary: status=$($summary.status), warnings=$warningCount, program_ended=$($summary.program_ended)"
}

function New-WinQStepWindow {
    Add-WinQStepWpfAssemblies

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinQStep" Height="760" Width="1120" MinHeight="620" MinWidth="900"
        Background="#F5F7FA" FontFamily="Segoe UI, Microsoft YaHei UI, Microsoft YaHei" WindowStartupLocation="CenterScreen">
  <Window.Resources>
    <Style TargetType="TextBox">
      <Setter Property="Margin" Value="6,4"/>
      <Setter Property="Padding" Value="6,4"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Margin" Value="6,4"/>
      <Setter Property="Padding" Value="10,5"/>
      <Setter Property="MinWidth" Value="90"/>
    </Style>
    <Style TargetType="TextBlock">
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
  </Window.Resources>
  <Grid Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <DockPanel Grid.Row="0">
      <TextBlock Text="WinQStep" FontSize="22" FontWeight="SemiBold" DockPanel.Dock="Left"/>
      <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
        <Button x:Name="DetectButton" Content="Detect"/>
        <Button x:Name="ImportButton" Content="Import"/>
        <Button x:Name="PreviewButton" Content="Preview"/>
        <Button x:Name="RunButton" Content="Run"/>
        <Button x:Name="HistoryButton" Content="History"/>
        <Button x:Name="ClearButton" Content="Clear"/>
      </StackPanel>
    </DockPanel>

    <GroupBox Grid.Row="1" Header="Job Inputs" Padding="10" Margin="0,10,0,10">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="110"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Grid.Column="0" Text="Mode"/>
        <StackPanel Grid.Row="0" Grid.Column="1" Orientation="Horizontal" Margin="6,4">
          <RadioButton x:Name="WorkflowModeRadio" Content="Workflow" GroupName="JobMode" IsChecked="True" Margin="0,0,18,0"/>
          <RadioButton x:Name="ExistingInputModeRadio" Content="Existing input" GroupName="JobMode"/>
        </StackPanel>

        <TextBlock Grid.Row="1" Grid.Column="0" Text="Config"/>
        <TextBox x:Name="ConfigPathBox" Grid.Row="1" Grid.Column="1"/>
        <Button x:Name="BrowseConfigButton" Grid.Row="1" Grid.Column="2" Content="Browse"/>

        <TextBlock Grid.Row="2" Grid.Column="0" Text="Template"/>
        <TextBox x:Name="TemplatePathBox" Grid.Row="2" Grid.Column="1"/>
        <Button x:Name="BrowseTemplateButton" Grid.Row="2" Grid.Column="2" Content="Browse"/>

        <TextBlock Grid.Row="3" Grid.Column="0" Text="Structure"/>
        <TextBox x:Name="StructurePathBox" Grid.Row="3" Grid.Column="1"/>
        <Button x:Name="BrowseStructureButton" Grid.Row="3" Grid.Column="2" Content="Browse"/>

        <TextBlock Grid.Row="4" Grid.Column="0" Text="Existing Input"/>
        <TextBox x:Name="ExistingInputPathBox" Grid.Row="4" Grid.Column="1"/>
        <Button x:Name="BrowseExistingInputButton" Grid.Row="4" Grid.Column="2" Content="Browse"/>

        <TextBlock Grid.Row="5" Grid.Column="0" Text="Job Folder"/>
        <TextBox x:Name="JobDirBox" Grid.Row="5" Grid.Column="1"/>
        <Button x:Name="BrowseJobDirButton" Grid.Row="5" Grid.Column="2" Content="Browse"/>

        <TextBlock Grid.Row="6" Grid.Column="0" Text="Project"/>
        <TextBox x:Name="ProjectNameBox" Grid.Row="6" Grid.Column="1"/>
      </Grid>
    </GroupBox>

    <TabControl Grid.Row="2">
      <TabItem Header="Environment">
        <TextBox x:Name="EnvironmentText" FontFamily="Cascadia Mono, Consolas, Microsoft YaHei UI, Microsoft YaHei, SimSun" FontSize="12"
                 AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap"
                 HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
      </TabItem>
      <TabItem Header="Structure">
        <TextBox x:Name="StructureText" FontFamily="Cascadia Mono, Consolas, Microsoft YaHei UI, Microsoft YaHei, SimSun" FontSize="12"
                 AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap"
                 HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
      </TabItem>
      <TabItem Header="Input Preview">
        <TextBox x:Name="PreviewText" FontFamily="Cascadia Mono, Consolas, Microsoft YaHei UI, Microsoft YaHei, SimSun" FontSize="12"
                 AcceptsReturn="True" AcceptsTab="True" TextWrapping="NoWrap"
                 HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
      </TabItem>
      <TabItem Header="Job Log">
        <TextBox x:Name="LogText" FontFamily="Cascadia Mono, Consolas, Microsoft YaHei UI, Microsoft YaHei, SimSun" FontSize="12"
                 AcceptsReturn="True" AcceptsTab="True" TextWrapping="Wrap"
                 HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
      </TabItem>
      <TabItem Header="History">
        <DataGrid x:Name="HistoryGrid" AutoGenerateColumns="False" IsReadOnly="True"
                  SelectionMode="Single" HeadersVisibility="Column" GridLinesVisibility="Horizontal"
                  FontSize="12">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Completed" Binding="{Binding completed_at}" Width="155"/>
            <DataGridTextColumn Header="Mode" Binding="{Binding mode}" Width="115"/>
            <DataGridTextColumn Header="Status" Binding="{Binding status}" Width="90"/>
            <DataGridTextColumn Header="Code" Binding="{Binding returncode}" Width="55"/>
            <DataGridTextColumn Header="Warnings" Binding="{Binding warning_count}" Width="75"/>
            <DataGridTextColumn Header="Project/Input" Binding="{Binding project_name}" Width="160"/>
            <DataGridTextColumn Header="Output" Binding="{Binding output_path}" Width="*"/>
          </DataGrid.Columns>
        </DataGrid>
      </TabItem>
    </TabControl>

    <StatusBar Grid.Row="3" Margin="0,10,0,0">
      <StatusBarItem>
        <TextBlock x:Name="StatusText" Text="Ready"/>
      </StatusBarItem>
    </StatusBar>
  </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $controls = @{}
    $names = @(
        "WorkflowModeRadio", "ExistingInputModeRadio",
        "ConfigPathBox", "TemplatePathBox", "StructurePathBox", "ExistingInputPathBox",
        "JobDirBox", "ProjectNameBox",
        "EnvironmentText", "StructureText", "PreviewText", "LogText", "HistoryGrid", "StatusText",
        "DetectButton", "ImportButton", "PreviewButton", "RunButton", "HistoryButton", "ClearButton",
        "BrowseConfigButton", "BrowseTemplateButton", "BrowseStructureButton",
        "BrowseExistingInputButton", "BrowseJobDirButton"
    )
    foreach ($name in $names) {
        $controls[$name] = $window.FindName($name)
    }

    $controls["ConfigPathBox"].Text = Resolve-WinQStepPath "examples\winqstep.config.json"
    $controls["TemplatePathBox"].Text = Resolve-WinQStepPath "examples\templates\energy_pbe.json"
    $controls["StructurePathBox"].Text = Resolve-WinQStepPath "tests\fixtures\structures\water.xyz"
    $controls["ExistingInputPathBox"].Text = Resolve-WinQStepPath "tests\fixtures\quickstep_energy.inp"
    $controls["JobDirBox"].Text = Resolve-WinQStepPath "outputs\gui-preview"
    $controls["ProjectNameBox"].Text = "gui_preview"

    $actionButtons = @(
        $controls["DetectButton"], $controls["ImportButton"], $controls["PreviewButton"],
        $controls["RunButton"], $controls["HistoryButton"], $controls["ClearButton"], $controls["BrowseConfigButton"],
        $controls["BrowseTemplateButton"], $controls["BrowseStructureButton"],
        $controls["BrowseExistingInputButton"], $controls["BrowseJobDirButton"]
    )

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

    $SetBusy = {
        param([bool]$IsBusy, [string]$Status)
        $controls["StatusText"].Text = $Status
        foreach ($button in $actionButtons) {
            $button.IsEnabled = -not $IsBusy
        }
        $window.Cursor = if ($IsBusy) { [System.Windows.Input.Cursors]::Wait } else { $null }
        if (-not $IsBusy) {
            & $UpdateModeControls
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
        param([string]$Status, [scriptblock]$Action)
        & $SetBusy $true $Status
        try {
            & $Action
        }
        catch {
            $message = $_.Exception.Message
            & $AppendLog "ERROR: $message"
            [System.Windows.MessageBox]::Show($window, $message, "WinQStep", "OK", "Error") | Out-Null
        }
        finally {
            & $SetBusy $false "Ready"
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

    $GetExistingInputArguments = {
        param([bool]$PrepareOnly)
        $arguments = @(
            "scripts\run_existing_input.py",
            "--config", $controls["ConfigPathBox"].Text,
            "--input", $controls["ExistingInputPathBox"].Text,
            "--job-dir", $controls["JobDirBox"].Text
        )
        if ($PrepareOnly) {
            $arguments += "--prepare-only"
        }
        return $arguments
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

    $FormatLogWithSummary = {
        param([Parameter(Mandatory = $true)]$Metadata, [Parameter(Mandatory = $true)][string]$Output)
        $summaryText = Format-Cp2kSummary $Metadata
        if ([string]::IsNullOrWhiteSpace($summaryText)) {
            return $Output
        }
        return "$summaryText`r`n`r`n$Output"
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

        $metadataPath = [string]$item.metadata_path
        if (-not [string]::IsNullOrWhiteSpace($metadataPath) -and [System.IO.File]::Exists($metadataPath)) {
            $controls["LogText"].Text = [System.IO.File]::ReadAllText($metadataPath, [System.Text.Encoding]::UTF8)
        }
        else {
            $controls["LogText"].Text = "Metadata file was not found: $metadataPath"
        }

        $outputPath = [string]$item.output_path
        if (-not [string]::IsNullOrWhiteSpace($outputPath) -and [System.IO.File]::Exists($outputPath)) {
            $controls["PreviewText"].Text = [System.IO.File]::ReadAllText($outputPath, [System.Text.Encoding]::UTF8)
        }
        else {
            $controls["PreviewText"].Text = "CP2K output was not found: $outputPath"
        }
    }.GetNewClosure()

    $controls["BrowseConfigButton"].Add_Click({ & $SelectFilePath $controls["ConfigPathBox"] "JSON files (*.json)|*.json|All files (*.*)|*.*" }.GetNewClosure())
    $controls["BrowseTemplateButton"].Add_Click({ & $SelectFilePath $controls["TemplatePathBox"] "JSON files (*.json)|*.json|All files (*.*)|*.*" }.GetNewClosure())
    $controls["BrowseStructureButton"].Add_Click({ & $SelectFilePath $controls["StructurePathBox"] "Structures (*.xyz;*.cif;POSCAR;CONTCAR)|*.xyz;*.cif;POSCAR;CONTCAR|All files (*.*)|*.*" }.GetNewClosure())
    $controls["BrowseExistingInputButton"].Add_Click({ & $SelectFilePath $controls["ExistingInputPathBox"] "CP2K input files (*.inp)|*.inp|All files (*.*)|*.*" }.GetNewClosure())
    $controls["BrowseJobDirButton"].Add_Click({ & $SelectFolderPath $controls["JobDirBox"] }.GetNewClosure())
    $controls["WorkflowModeRadio"].Add_Checked({ & $UpdateModeControls }.GetNewClosure())
    $controls["ExistingInputModeRadio"].Add_Checked({ & $UpdateModeControls }.GetNewClosure())

    $controls["DetectButton"].Add_Click({
        & $InvokeGuiAction "Detecting environment" {
            $result = Invoke-WinQStepPython @("scripts\detect_environment.py", "--config", $controls["ConfigPathBox"].Text)
            $controls["EnvironmentText"].Text = $result.Output
            & $AppendLog "detect_environment.py exited with code $($result.ExitCode)"
        }
    }.GetNewClosure())

    $controls["ImportButton"].Add_Click({
        & $InvokeGuiAction "Importing structure" {
            $result = Invoke-WinQStepPython @("scripts\import_structure.py", "--input", $controls["StructurePathBox"].Text)
            $controls["StructureText"].Text = $result.Output
            & $AppendLog "import_structure.py exited with code $($result.ExitCode)"
        }
    }.GetNewClosure())

    $controls["PreviewButton"].Add_Click({
        $status = if (& $TestIsExistingInputMode) { "Preparing existing input preview" } else { "Preparing workflow input preview" }
        & $InvokeGuiAction $status {
            $result = Invoke-WinQStepPython (& $GetActiveJobArguments $true)
            $metadata = Get-JsonResult $result
            $inputPath = & $GetActiveInputPreviewPath $metadata
            if ([System.IO.File]::Exists($inputPath)) {
                $controls["PreviewText"].Text = [System.IO.File]::ReadAllText($inputPath, [System.Text.Encoding]::UTF8)
            }
            else {
                $controls["PreviewText"].Text = "Input file was not written: $inputPath"
            }
            $controls["LogText"].Text = & $FormatLogWithSummary $metadata $result.Output
        }
    }.GetNewClosure())

    $controls["RunButton"].Add_Click({
        & $InvokeGuiAction "Running CP2K" {
            $result = Invoke-WinQStepPython (& $GetActiveJobArguments $false)
            $metadata = Get-JsonResult $result
            $logText = & $FormatLogWithSummary $metadata $result.Output
            $outputPath = $metadata.files.output.path
            if ([System.IO.File]::Exists($outputPath)) {
                $tail = Get-Content -LiteralPath $outputPath -Tail 80 | Out-String
                $logText = "$logText`r`n`r`n--- CP2K output tail ---`r`n$tail"
            }
            $controls["LogText"].Text = $logText
        }
    }.GetNewClosure())

    $controls["HistoryButton"].Add_Click({
        & $InvokeGuiAction "Loading job history" {
            & $LoadHistory
        }
    }.GetNewClosure())

    $controls["HistoryGrid"].Add_MouseDoubleClick({
        & $OpenSelectedHistory
    }.GetNewClosure())

    $controls["ClearButton"].Add_Click({
        $controls["EnvironmentText"].Clear()
        $controls["StructureText"].Clear()
        $controls["PreviewText"].Clear()
        $controls["LogText"].Clear()
        $controls["HistoryGrid"].ItemsSource = $null
    }.GetNewClosure())

    & $UpdateModeControls
    return $window
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
            stdout = [ordered]@{ path = (Join-Path $historySmokeDir "history_smoke.stdout.log") }
            stderr = [ordered]@{ path = (Join-Path $historySmokeDir "history_smoke.stderr.log") }
            metadata = [ordered]@{ path = $historyMetadataPath }
        }
        cp2k_output = [ordered]@{
            status = "completed"
            warning_count = 0
            program_ended = $true
        }
    }
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
    $report["xaml_loaded"] = ($window -is [System.Windows.Window])
    $report["title"] = $window.Title
    $report["history_grid_loaded"] = ($window.FindName("HistoryGrid") -is [System.Windows.Controls.DataGrid])
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
$window = New-WinQStepWindow
[void]$app.Run($window)
